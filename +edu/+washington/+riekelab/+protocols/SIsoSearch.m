classdef SIsoSearch < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Grating leading duration (ms)
        moveTime = 5000                 % Grating duration (ms)
        tailTime = 250                  % Grating trailing duration (ms)
        waitTime = 0                    % Grating wait time before motion (ms)
        RGGridPoints = [6, 6]           % Number of grid points in red and green dims
        RGStepSize = [0.1, 0.05]        % Step size between grid for red and green dims
        orientations = [0,0]            % Grating orientation (deg)
        barWidths = [400,400]           % Grating half-cycle width (microns)
        temporalFrequencies = [4,4]     % Range of temporal frequencies to test.
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        randomOrder = true              % Random orientation order?
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        apertureRadius = 0              % Aperture radius in microns.
        greenLED = 505                  % nm of Green LED in use
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'sinewave'       % Spatial type (sinewave or squarewave)
        temporalClass = 'drifting'      % Temporal type (drifting or reversing)      
        onlineAnalysis = 'none'         % Type of online analysis
        repeats = 4                     % Number of times to repeat full grid

    end
    
    properties (Hidden)
        ampType
        chromaticClassType = symphonyui.core.PropertyType('char', 'row', {'S-iso-search', 'LM-iso-search'})
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        orientationsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        barWidthsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        temporalFrequenciesType = symphonyui.core.PropertyType('denserealdouble','matrix')
        redWeightsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        greenWeightsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        blueWeightsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        spatialFrequency
        orientation
        phaseShift
        barWidth
        barWidthPix
        apertureRadiusPix
        sequence
        sizeSequence
        freqSequence
        temporalFrequency
        gratingLength
        rgbWeights
        spatialPhaseRad
        rawImage
        redWeights
        greenWeights
        blueWeights
        chromaticClass
        colorOrder
        computedColorWeights
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
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if ~obj.isMeaRig
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                if ~strcmp(obj.onlineAnalysis, 'none')
                    obj.showFigure('manookinlab.figures.GratingDSFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                        'orientations', obj.orientations, ...
                        'temporalFrequency', obj.temporalFrequency);
                end
            end
            
            % Calculate the spatial phase in radians.
            obj.spatialPhaseRad = obj.spatialPhase / 180 * pi;
            
            obj.gratingLength = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            
            % Convert from microns to pixels
            obj.apertureRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.apertureRadius);

            % Create red, green and blue weight vectors
            numPoints = obj.RGGridPoints(1)*obj.RGGridPoints(2);

            % Calculate expected color weights (based on latest
            % calibrations as of 10/29/25... will replace this with
            % something more robust)

            if obj.greenLED == 565
                           %R      %G     %B
                qCatch = [35262, 191230, 8866; %L
                          12305, 160385, 8323; %M
                          3560, 7512, 66757];  %S
            elseif obj.greenLED == 505
                           %R      %G     %B
                qCatch = [135282, 199609, 14474; %L
                          47210, 324391, 13682; %M
                          13659, 36759, 109742];  %S
            else
                error('LED must be 505 or 565');
            end

            obj.computedColorWeights = qCatch \ [0 0 1]';
            obj.computedColorWeights = obj.computedColorWeights/max(abs(obj.computedColorWeights));

            fprintf('\nComputed color weights are: %5.3f %5.3f %5.3f \n', obj.computedColorWeights);

            fprintf('\nExpected S-iso weights are: %s \n', num2str(obj.computedColorWeights));
            
            range = obj.RGGridPoints.*obj.RGStepSize;
            redStart = obj.computedColorWeights(1)-range(1)/2;
            redEnd = obj.computedColorWeights(1)+range(1)/2;
            obj.redWeights = linspace(redStart, redEnd, obj.RGGridPoints(1));
            obj.redWeights = repelem(obj.redWeights, obj.RGGridPoints(2));

            greenStart = obj.computedColorWeights(2)-range(2)/2;
            greenEnd = obj.computedColorWeights(2)+range(2)/2;
            obj.greenWeights = linspace(greenStart, greenEnd, obj.RGGridPoints(2));
            obj.greenWeights = repmat(obj.greenWeights, [1, obj.RGGridPoints(1)]);

            obj.blueWeights = ones([1, numPoints]);

            fprintf('There are %d red weights \n', length(obj.redWeights));
            fprintf('There are %d green weights \n', length(obj.greenWeights));
            fprintf('There are %d blue weight \n', length(obj.blueWeights));

            if obj.randomOrder
                obj.colorOrder = randperm(numPoints);
            else
                obj.colorOrder = 1:numPoints;
            end

            obj.redWeights = obj.redWeights(obj.colorOrder);
            obj.greenWeights = obj.greenWeights(obj.colorOrder);
            obj.blueWeights = obj.blueWeights(obj.colorOrder);


        end
        
        function setRawImage(obj)
            downsamp = 3;
            sz = obj.gratingLength;
            
            x = linspace(-sz/2, sz/2, sz/downsamp);
            x = x / obj.gratingLength * 2 * pi;
            obj.rawImage = x*obj.spatialFrequency;
            
            obj.rawImage = repmat(obj.rawImage, [1 1 3]);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
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

            redWeight = obj.redWeights(mod(obj.numEpochsCompleted, length(obj.redWeights))+1);
            greenWeight = obj.greenWeights(mod(obj.numEpochsCompleted, length(obj.greenWeights))+1);
            blueWeight = obj.blueWeights(mod(obj.numEpochsCompleted, length(obj.blueWeights))+1);
            
            % Set the RGB weights.
            obj.rgbWeights = [redWeight, greenWeight, blueWeight];
            
            % Set the current orientation.
            obj.orientation = obj.orientations(mod(obj.numEpochsCompleted, length(obj.orientations))+1);

            % Set the temporal frequency.
            obj.temporalFrequency = obj.temporalFrequencies(mod(obj.numEpochsCompleted, length(obj.temporalFrequencies))+1);
            
            % Get the bar width in pixels
            obj.barWidth = obj.barWidths(mod(obj.numEpochsCompleted, length(obj.barWidths))+1);
            obj.barWidthPix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);
            epoch.addParameter('barWidth', obj.barWidth);
            
            % Get the spatial frequency.
            obj.spatialFrequency = obj.gratingLength/(2*obj.barWidthPix);
            
            % Set up the raw image.
            obj.setRawImage();

            % Add the spatial frequency to the epoch.
            epoch.addParameter('spatialFrequency', obj.spatialFrequency);

            % Add the temporal frequency in Hz.
            epoch.addParameter('temporalFrequency', obj.temporalFrequency);
            
            % Save out the current orientation.
            epoch.addParameter('orientation', obj.orientation);
            
            % Save out the current RGB weights.
            epoch.addParameter('redWeight', obj.rgbWeights(1));
            epoch.addParameter('greenWeight', obj.rgbWeights(2));
            epoch.addParameter('blueWeight', obj.rgbWeights(3));
        end

        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create the grating.
            grate = stage.builtin.stimuli.Image(uint8(0 * obj.rawImage));
            grate.position = obj.canvasSize / 2;
            grate.size = obj.gratingLength*ones(1,2);
            grate.orientation = obj.orientation;
            
            % Set the minifying and magnifying functions.
            grate.setMinFunction(GL.NEAREST);
            grate.setMagFunction(GL.NEAREST);
            
            % Add the grating.
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            %--------------------------------------------------------------
            % Generate the grating.
            if strcmp(obj.temporalClass, 'drifting')
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setDriftingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setReversingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            end
            p.addController(imgController);
            
            % Set the drifting grating.
            function g = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                
                g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                
                if strcmp(obj.spatialClass, 'squarewave')
                    g = sign(g);
                end
                
                % Deal with chromatic gratings.
                for m = 1 : 3
                    g(:,:,m) = obj.rgbWeights(m) * g(:,:,m);
                end
                g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
            end
            
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
                
                % Deal with chromatic gratings.
                for m = 1 : 3
                    g(:,:,m) = obj.rgbWeights(m) * g(:,:,m);
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
        end
         
        function numberOfAverages = get.numberOfAverages(obj)
            numberOfAverages = uint16(obj.repeats * obj.RGGridPoints(1)*obj.RGGridPoints(2));
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
