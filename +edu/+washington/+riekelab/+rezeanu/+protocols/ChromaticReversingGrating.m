classdef ChromaticReversingGrating < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                                         % Output amplifier
        preTime = 250                               % Time before grating appears (ms)
        moveTime = 4000                             % Reversing grating duration (ms)
        tailTime = 250                              % Time after grating disappears (ms)
        waitTime = 1000                             % Stationary time before reversing begins (ms)
        contrast = 1.0                              % Grating contrast (0-1)
        orientation = 0.0                           % Grating orientation (deg)
        barWidths = [15, 30, 45, 60, 75]            % Grating bar widths (um)
        temporalFrequency = 2.0                     % Temporal frequency of modulation (Hz)
        spatialPhase = 0.0                          % Spatial phase of grating (deg)
        backgroundIntensity = 0.5                   % Background intensity (0-1)
        centerOffset = [0,0]                        % Center offset in pixels (x,y)
        apertureRadius = 0                          % Aperture radius in pixels.
        apertureClass = 'spot'                      % Spot or annulus?       
        spatialClass = 'squarewave'                 % Grating type (sinewave or squarewave)
        chromaticClass = 'achromatic'               % Chromatic class
        onlineAnalysis = 'none'                     % Type of online analysis (currently unused)
        randomOrder = true                          % Run the sequence in random order?
        numReps = uint16(4)                         % Number of times to repeat each grating
        trueFrameRate = 60;                         % Actual measured device frame rate
        verbose = false;                            % Print debug statements to console?
    end
    
    properties (Hidden)
        ampType
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red','green','blue','S-iso','M-iso','L-iso', 'LM-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        rawImage
        spatialPhaseRad % The spatial phase in radians.
        spatialFrequencies
        frequency % The current spatial frequency for the epoch
        coneContrasts 
        qCatch
        preFrames
        tailFrames
        waitFrames
        moveFrames
        stimFrames
        barWidthsPix
    end
    
    properties (Dependent) 
        stimTime
        numberOfAverages
        temporalFrequencyFrames
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            if obj.verbose
                fprintf('\nPreparing run\n');
            end

            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            end
            
            obj.preFrames = round(obj.preTime*obj.trueFrameRate*1e-3);
            obj.tailFrames = round(obj.tailTime*obj.trueFrameRate*1e-3);
            obj.waitFrames = round(obj.waitTime*obj.trueFrameRate*1e-3);
            obj.moveFrames = round(obj.moveTime*obj.trueFrameRate*1e-3);
            obj.stimFrames = round(obj.stimTime*obj.trueFrameRate*1e-3);
            
            obj.barWidthsPix = obj.rig.getDevice('Stage').um2pix(obj.barWidths);
            
            % Calculate the spatial phase in radians.
            obj.spatialPhaseRad = obj.spatialPhase / 180 * pi;

            device = obj.rig.getDevice('Stage');
            obj.qCatch = edu.washington.riekelab.rezeanu.utils.getLcrQuantalCatch(device, obj.persistor);
            
            % Assign color weights from chromatic class
            obj.parseChromaticClass(obj.chromaticClass);
            
            % Calculate the cone contrasts.
            obj.coneContrasts = coneContrast(obj.backgroundIntensity*obj.qCatch, ...
                obj.colorWeights, 'michaelson');

            % Organize stimulus and analysis parameters.
            obj.organizeParameters();
            if obj.verbose 
                fprintf('\nPrepared run\n');
            end
        end
        

        function parseChromaticClass(obj, className)
            
            switch className
                case 'achromatic'
                    obj.colorWeights = [1,1,1];
                case 'red'
                    obj.colorWeights = [1,-1,-1];
                case 'green'
                    obj.colorWeights = [-1,1,-1];
                case 'blue'
                    obj.colorWeights = [-1,-1,1];
                case 'S-iso'
                    sIsoWeights = obj.qCatch(:, 1:3)' \  [0,0,1]';
                    obj.colorWeights = sIsoWeights(:)'/max(abs(sIsoWeights));
                case 'M-iso'
                    mIsoWeights = obj.qCatch(:, 1:3)' \ [0, 1, 0]';
                    obj.colorWeights = mIsoWeights(:)'/max(abs(mIsoWeights));
                case 'L-iso'
                    lIsoWeights = obj.qCatch(:, 1:3)' \ [1, 0, 0]';
                    obj.colorWeights = lIsoWeights(:)'/max(abs(lIsoWeights));
                case 'LM-iso'
                    bgExcitation = sum(obj.qCatch(:,1:3), 1);   % 1x3, cone excitation per unit primary output
                    lmIsoWeights = obj.qCatch(:,1:3)' \ [bgExcitation(1), bgExcitation(2), 0]';
                    obj.colorWeights = lmIsoWeights(:)'/max(abs(lmIsoWeights));
                otherwise
                    obj.colorWeights = [1,1,1];
            end
        end

        function p = createPresentation(obj)
            if obj.verbose
                fprintf('\nCreating presentation\n');
            end
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * (obj.trueFrameRate/obj.frameRate) * 1e-3); % Create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create the grating
            grate = stage.builtin.stimuli.Image(uint8(0 * obj.rawImage));
            grate.position = obj.canvasSize / 2;
            grate.size = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2))*ones(1,2);
            grate.orientation = obj.orientation;

            grate.setMinFunction(GL.NEAREST);
            grate.setMagFunction(GL.NEAREST);
            
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < (obj.preFrames + obj.stimFrames));

            p.addController(grateVisible);
            
            
            % Generate the grating.
            imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setReversingGrating(obj, state.frame - (obj.preFrames + obj.waitFrames)));

            p.addController(imgController);
            
            
            % Set the reversing grating
            function g = setReversingGrating(obj, frame)
                if frame >= 0
                    phase = round(0.5 * sin(frame * 2 * pi * obj.temporalFrequencyFrames) + 0.5) * pi;
                else
                    phase = 0;
                end
                
                g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                
                if strcmp(obj.spatialClass, 'squarewave')
                    g = sign(g);
                end
                
                g = obj.contrast * g;
                
                % Deal with chromatic gratings.
                if ~strcmp(obj.chromaticClass, 'achromatic')
                    for m = 1 : 3
                        g(:,:,m) = obj.colorWeights(m) * g(:,:,m);
                    end
                end
                g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
            end

            if obj.apertureRadius > 0
                if strcmpi(obj.apertureClass, 'spot')
                    aperture = stage.builtin.stimuli.Rectangle();
                    aperture.position = obj.canvasSize/2 + obj.centerOffset;
                    aperture.color = obj.backgroundIntensity;
                    aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
                    mask = stage.core.Mask.createCircularAperture(obj.apertureRadius*2/max(obj.canvasSize), 1024);
                    aperture.setMask(mask);
                    p.addStimulus(aperture);
                else
                    mask = stage.builtin.stimuli.Ellipse();
                    mask.color = obj.backgroundIntensity;
                    mask.radiusX = obj.apertureRadius;
                    mask.radiusY = obj.apertureRadius;
                    mask.position = obj.canvasSize / 2 + obj.centerOffset;
                    p.addStimulus(mask);
                end
            end
            if obj.verbose
                fprintf('\nCreated presentation\n');
            end
        end
        
        function setRawImage(obj)

            sz = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            rotRads = obj.orientation / 180 * pi;
            
            offsetAlongAxis = obj.centerOffset(1)*cos(rotRads) + obj.centerOffset(2)*sin(rotRads);
            x = linspace(-sz/2 + 0.5, sz/2 - 0.5, sz) - offsetAlongAxis;

            obj.rawImage = x / min(obj.canvasSize) * 2 * pi * obj.frequency;
            
            if ~strcmp(obj.chromaticClass, 'achromatic')
                obj.rawImage = repmat(obj.rawImage, [1 1 3]);
            end

        end
        
        % This is a method of organizing stimulus parameters.
        function organizeParameters(obj)
            
            SFs = min(obj.canvasSize) ./ (2*obj.barWidthsPix);
            
            % Get the array of radii.
            freqs = SFs(:) * ones(1, obj.numReps);
            freqs = freqs(:)';
            
            % Deal with the parameter order if it is random order.
            if ( obj.randomOrder )
                epochSyntax = randperm( obj.numberOfAverages );
            else
                epochSyntax = 1 : obj.numberOfAverages;
            end
            
            % Copy the radii in the correct order.
            freqs = freqs( epochSyntax );
            
            % Copy to spatial frequencies.
            obj.spatialFrequencies = freqs;
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            if obj.verbose
                fprintf('\nPreparing Epoch %d\n', obj.numEpochsPrepared);
            end
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii});
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii});
                    end
                end
            end

            % Set the current spatial frequency.
            obj.frequency = obj.spatialFrequencies( obj.numEpochsCompleted+1 );
            
            % Set up the raw image.
            obj.setRawImage();

            % Add the spatial frequency to the epoch.
            epoch.addParameter('frequency', obj.frequency);
            
            % Save out the cone/rod contrasts.
            epoch.addParameter('lContrast', obj.coneContrasts(1));
            epoch.addParameter('mContrast', obj.coneContrasts(2));
            epoch.addParameter('sContrast', obj.coneContrasts(3));
            epoch.addParameter('rodContrast', obj.coneContrasts(4));
            epoch.addParameter('preFrames', obj.preFrames);
            epoch.addParameter('tailFrames', obj.tailFrames);
            epoch.addParameter('waitFrames', obj.waitFrames);
            epoch.addParameter('moveFrames', obj.moveFrames);
            epoch.addParameter('stimFrames', obj.stimFrames);
            epoch.addParameter('qCatch', obj.qCatch);
            epoch.addParameter('colorWeights', obj.colorWeights);
            if obj.verbose
                fprintf('\nPrepared Epoch %d\n', obj.numEpochsPrepared);
            end
        end

        function temporalFrequencyFrames = get.temporalFrequencyFrames(obj)
            temporalFrequencyFrames = obj.temporalFrequency/obj.trueFrameRate;
        end

        function numberOfAverages = get.numberOfAverages(obj)
            numberOfAverages = length(obj.barWidths)*obj.numReps;
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        
    end
end


