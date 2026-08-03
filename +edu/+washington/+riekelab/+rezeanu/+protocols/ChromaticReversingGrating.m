classdef ChromaticReversingGrating < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Grating leading duration (ms)
        moveTime = 4000                 % Grating duration (ms)
        tailTime = 250                  % Grating trailing duration (ms)
        waitTime = 1000                 % Grating wait duration (ms)
        contrast = 1.0                  % Grating contrast (0-1)
        orientation = 0.0               % Grating orientation (deg)
        spatialFreqs = 10.^(-0.301:0.301/3:1.4047) % Spatial frequency (cyc/short axis of screen)
        temporalFrequency = 2.0         % Temporal frequency (Hz)
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        apertureRadius = 0              % Aperture radius in pixels.
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'sinewave'       % Spatial type (sinewave or squarewave)
        chromaticClass = 'achromatic'   % Chromatic type
        onlineAnalysis = 'none'         % Type of online analysis
        randomOrder = true              % Run the sequence in random order?
        numberOfRepetitions = uint16(4) % Number of times to repeat each grating
    end
    
    properties (Hidden)
        ampType
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'achromatic','red','green','yellow','blue','S-iso','M-iso','L-iso'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        rawImage
        spatialPhaseRad % The spatial phase in radians.
        spatialFrequencies
        spatialFreq % The current spatial frequency for the epoch
        xaxis
        F1Amp
        F2Amp
        F1Phase
        repsPerX
        coneContrasts 
        qCatch
        preFrames
        tailFrames
        waitFrames
        moveFrames
        stimFrames
    end
    
    properties (Dependent) 
        stimTime
        numberOfAverages
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            fprintf('\nPreparing run\n');
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            end

            obj.preFrames = round(obj.preTime*60*1e-3);
            obj.tailFrames = round(obj.tailTime*60*1e-3);
            obj.waitFrames = round(obj.waitTime*60*1e-3);
            obj.moveFrames = round(obj.moveTime*60*1e-3);
            obj.stimFrames = round(obj.stimTime*60*1e-3);
            
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

            fprintf('\nPrepared run\n');
        end
        

        function parseChromaticClass(obj, className)

            switch className
                case 'achromatic'
                    obj.colorWeights = [1,1,1] * obj.contrast;
                case 'yellow'
                    obj.colorWeights = [1,1,0] * obj.contrast;
                case 'red'
                    obj.colorWeights = [1,0,0] * obj.contrast;
                case 'green'
                    obj.colorWeights = [0,1,0] * obj.contrast;
                case 'blue'
                    obj.colorWeights = [0,0,1] * obj.contrast;
                case 'S-Iso'
                    sIsoWeights = obj.qCatch(:, 1:3)' \  [0,0,1]';
                    obj.colorWeights = sIsoWeights/max(abs(sIsoWeights));
                otherwise
                    obj.colorWeights = [1,1,1] * obj.contrast;
            end
        end

        function p = createPresentation(obj)
            fprintf('\nCreating presentation\n');
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * (60/obj.frameRate) * 1e-3); % Create presentation of specified duration
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
            function g = setReversingGrating(obj, time)
                if time >= 0
                    phase = round(0.5 * sin(time * 2 * pi * obj.temporalFrequency) + 0.5) * pi;
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
            fprintf('\nCreated presentation\n');
        end
        
        function setRawImage(obj)
            downsamp = 3;
            sz = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            [x,y] = meshgrid(...
                linspace(-sz/2, sz/2, sz/downsamp), ...
                linspace(-sz/2, sz/2, sz/downsamp));
            
            % Calculate the orientation in radians.
            rotRads = obj.orientation / 180 * pi;
            
            
%             [x,y] = meshgrid(...
%                 linspace(-obj.canvasSize(1)/2, obj.canvasSize(1)/2, obj.canvasSize(1)/downsamp), ...
%                 linspace(-obj.canvasSize(2)/2, obj.canvasSize(2)/2, obj.canvasSize(2)/downsamp));
            
            % Center the stimulus.
            x = x + obj.centerOffset(1)*cos(rotRads);
            y = y + obj.centerOffset(2)*sin(rotRads);
            
            x = x / min(obj.canvasSize) * 2 * pi;
            y = y / min(obj.canvasSize) * 2 * pi;
            
            % Calculate the raw grating image.
            img = (cos(0)*x + sin(0) * y) * obj.spatialFreq;
            obj.rawImage = img(1,:);
%             obj.rawImage = (cos(rotRads) * x + sin(rotRads) * y) * obj.spatialFreq;
            
            if ~strcmp(obj.chromaticClass, 'achromatic')
                obj.rawImage = repmat(obj.rawImage, [1 1 3]);
            end
        end
        
        % This is a method of organizing stimulus parameters.
        function organizeParameters(obj)
            
            
            % Get the array of radii.
            freqs = obj.spatialFreqs(:) * ones(1, obj.numberOfRepetitions);
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
            
            obj.xaxis = unique(obj.spatialFrequencies);
            obj.F1Amp = zeros(size(obj.xaxis));
            obj.F1Phase = zeros(size(obj.xaxis));
            obj.repsPerX = zeros(size(obj.xaxis));
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            fprintf('\nPreparing epoch\n');

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
            obj.spatialFreq = obj.spatialFrequencies( obj.numEpochsCompleted+1 );
            
            % Set up the raw image.
            obj.setRawImage();

            % Add the spatial frequency to the epoch.
            epoch.addParameter('spatialFreq', obj.spatialFreq);
            
            % Save out the cone/rod contrasts.
            epoch.addParameter('lContrast', obj.coneContrasts(1));
            epoch.addParameter('mContrast', obj.coneContrasts(2));
            epoch.addParameter('sContrast', obj.coneContrasts(3));
            epoch.addParameter('rodContrast', obj.coneContrasts(4));
            fprintf('\nPrepared Epoch\n');
        end

        function numberOfAverages = get.numberOfAverages(obj)
            numberOfAverages = length(obj.spatialFreqs)*obj.numberOfRepetitions;
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


