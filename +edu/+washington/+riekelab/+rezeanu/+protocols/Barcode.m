classdef Barcode < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Barcode leading duration (ms)
        tailTime = 500                  % Barcode trailing duration (ms)
        orientations = [0, 45, 90]      % Barcode angle (deg)
        speeds = [635, 1205, 1660, 3150]  % Barcode speeds (um/sec)
        contrast = 1                    % Barcode contrast (-1 to 1 units)
        barWidths = [525, 280, 175, 420,...
            210, 350, 490, 420,...
            560, 35, 280, 490,...
            35, 595, 665, 105,...
            665, 420, 490, 455,...
            525, 245, 175, 595,...
            595, 105, 105]              % Bar widths in microns
        chromaticClass = 'achromatic'
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        innerMaskRadius = 0             % Inner mask radius in microns.
        outerMaskRadius = 0             % Outer mask radius in microns.
        randomOrder = true              % Random orientation order?
        onlineAnalysis = 'none'         % Online analysis type.
        numberOfReps = uint16(5)        % N times each speed/ori combo is shown
    end
    
    properties (Dependent)
        numberOfBarcodes
        numberOfAverages
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row',...
            {'none', 'extracellular', 'spikes_CClamp',...
            'subthresh_CClamp', 'analog'})
        orientationsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        barWidthsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        speedsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        chromaticClassType = symphonyui.core.PropertyType('char', 'row',...
            {'achromatic', 'red', 'green', 'blue', 'yellow', ...
            'blue-yellow', 'red-green', 'S-Iso', 'M-Iso', 'L-Iso'})
        orientationSequence
        speedSequence
        orientation
        orientationRads
        barWidthsPix
        innerMaskRadiusPix
        outerMaskRadiusPix
        lightBar
        darkBar
        imageMatrix
        stimTime
        stimFrames
        preFrames
        tailFrames
        speedsPix
        speedPixPerFrame
        barcodeSize
    end
    
    methods
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            obj.preFrames = round(obj.preTime*1e-3*60);
            obj.tailFrames = round(obj.tailTime*1e-3*60);
            
            % Epoch constructor can't CREATE stimTime de novo, it has to be
            % created here, and then every epoch manipulates it.
            obj.stimTime = 2000;
            obj.stimFrames = round(obj.stimTime*1e-3*60);

            
            obj.barWidthsPix = obj.rig.getDevice('Stage').um2pix(obj.barWidths);
            obj.outerMaskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.outerMaskRadius);
            obj.innerMaskRadiusPix = obj.rig.getDevice('Stage').um2pix(obj.outerMaskRadius);
            obj.speedsPix = obj.rig.getDevice('Stage').um2pix(obj.speeds);
            
            if ~obj.isMeaRig
                % Pull colors for single-cell online analysis figures
                if length(obj.orientations) > 1
                    colors = pmkmp(length(obj.orientations),'CubicYF');
                else
                    colors = zeros(1,3);
                end
                
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                if ~strcmp(obj.onlineAnalysis, 'none')
                    obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                        obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                        'sweepColor',colors,...
                        'groupBy',{'orientation'});

                    if length(unique(obj.orientations)) > 1
                        obj.showFigure('manookinlab.figures.DirectionFigure', ...
                            obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                            'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                            'orientations', unique(obj.orientations));                 
                    end
                end
            end
            
            % Get the canvas size.
            obj.canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            
            % Check the outer mask radius.
            if obj.outerMaskRadiusPix > min(obj.canvasSize/2)
                obj.outerMaskRadiusPix = min(obj.canvasSize/2);
            elseif obj.outerMaskRadiusPix <= 0
                obj.outerMaskRadiusPix = max(obj.canvasSize/2);
            end
            
            % Set the barcode colors
            [obj.lightBar, obj.darkBar] = obj.parseChromaticClass(obj.chromaticClass);
            
            % Generate barcode image
            obj.generateBarcode();
            obj.barcodeSize = size(obj.imageMatrix);
            
            % Generate the order in which speed/ori combos will be shown
            obj.getStimulusOrder();

        end
        
        function [lB, dB] = parseChromaticClass(obj, colorClass)
            b1_rgb = obj.contrast*obj.backgroundIntensity+obj.backgroundIntensity;
            b2_rgb = -obj.contrast*obj.backgroundIntensity+obj.backgroundIntensity;
            
            switch colorClass
                case 'achromatic'
                    lB = [b2_rgb,b2_rgb,b2_rgb];
                    dB = [b1_rgb, b1_rgb, b1_rgb];
                case 'red'
                    lB = [b1_rgb, 0, 0];
                    dB = [obj.backgroundIntensity, ...
                        obj.backgroundIntensity, ...
                        obj.backgroundIntensity];
                case 'green'
                    lB = [0, b1_rgb, 0];
                    dB = [obj.backgroundIntensity, ...
                        obj.backgroundIntensity, ...
                        obj.backgroundIntensity];
                case 'blue'
                    lB = [0, 0, b1_rgb];
                    dB = [obj.backgroundIntensity, ...
                        obj.backgroundIntensity, ...
                        obj.backgroundIntensity];
                case 'yellow'
                    lB = [b1_rgb, b1_rgb, 0];
                    dB = [obj.backgroundIntensity, ...
                        obj.backgroundIntensity, ...
                        obj.backgroundIntensity];
                case 'blue-yellow'
                    if obj.contrast >= 0
                        lB = [b2_rgb, b2_rgb, b1_rgb];
                        dB = [b1_rgb, b1_rgb, b2_rgb];
                    else
                        lB = [b1_rgb, b1_rgb, b2_rgb];
                        dB = [b2_rgb, b2_rgb, b1_rgb];
                    end
                case 'red-green'
                    if obj.contrast >= 0
                        lB = [b1_rgb, b2_rgb, b2_rgb];
                        dB = [b2_rgb, b1_rgb, b2_rgb];
                    else
                        lB = [b2_rgb, b1_rgb, b1_rgb];
                        dB = [b1_rgb, b2_rgb, b1_rgb];
                    end

                case 'S-Iso'
                    sIsoWeights = obj.getSIsoWeights();
                    lB = sIsoWeights .* obj.backgroundIntensity+obj.backgroundIntensity;
                    dB = -sIsoWeights .* obj.backgroundIntensity+obj.backgroundIntensity;
                case 'M-Iso'
                    mIsoWeights = obj.getMIsoWeights();
                    lB = mIsoWeights .* obj.backgroundIntensity+obj.backgroundIntensity;
                    dB = -mIsoWeights .* obj.backgroundIntensity+obj.backgroundIntensity;
                case 'L-Iso'
                    lIsoWeights = obj.getLIsoWeights();
                    lB = lIsoWeights .* obj.backgroundIntensity+obj.backgroundIntensity;
                    dB = -lIsoWeights .* obj.backgroundIntensity+obj.backgroundIntensity;
                otherwise
                    lB = [b2_rgb,b2_rgb,b2_rgb];
                    dB = [b1_rgb, b1_rgb, b1_rgb];
            end
        end
        
        function sIsoWeights = getSIsoWeights(obj)
            device = obj.rig.getDevice('Stage');
            qCatch = edu.washington.riekelab.rezeanu.utils.getLcrQuantalCatch(device, obj.persistor);
            colorWeights = qCatch(:, 1:3)' \ [0,0,1]';
            sIsoWeights = colorWeights./max(abs(colorWeights));
        end

        function mIsoWeights = getMIsoWeights(obj)
            device = obj.rig.getDevice('Stage');
            qCatch = edu.washington.riekelab.rezeanu.utils.getLcrQuantalCatch(device, obj.persistor);
            colorWeights = qCatch(:, 1:3)' \ [0,1,0]';
            mIsoWeights = colorWeights./max(abs(colorWeights));
        end
        
        function lIsoWeights = getLIsoWeights(obj)
            device = obj.rig.getDevice('Stage');
            qCatch = edu.washington.riekelab.rezeanu.utils.getLcrQuantalCatch(device, obj.persistor);
            colorWeights = qCatch(:, 1:3)' \ [1,0,0]';
            lIsoWeights = colorWeights./max(abs(colorWeights));
        end

        function getStimulusOrder(obj)
            [ori_grid, spd_grid] = meshgrid(obj.orientations, obj.speedsPix);
            all_ori = ori_grid(:)';
            all_spd = spd_grid(:)';
            
            barcodeSequence = [all_ori; all_spd];
            
            % Set the sequence.
            if obj.randomOrder
                obj.speedSequence = zeros(obj.numberOfReps, length(barcodeSequence));
                obj.orientationSequence = zeros(obj.numberOfReps, length(barcodeSequence));
                for k = 1 : obj.numberOfReps
                    barcodeOrder = randperm(length(barcodeSequence));
                    obj.speedSequence(k, :) = barcodeSequence(2,barcodeOrder);
                    obj.orientationSequence(k, :) = barcodeSequence(1,barcodeOrder);
                end
                obj.speedSequence = obj.speedSequence';
                obj.orientationSequence = obj.orientationSequence';
            else
                obj.orientationSequence = repmat(obj.barcodeSequence(1,:), [obj.numberOfReps,1])';
                obj.speedSequence = repmat(obj.barcodeSequence(2,:), [obj.numberOfReps,1])';
            end
            
            obj.orientationSequence = obj.orientationSequence(:)';
            obj.speedSequence = obj.speedSequence(:)';
        end
        
        function generateBarcode(obj)
            obj.imageMatrix = zeros(1, sum(obj.barWidthsPix), 3);
            for i = 1:length(obj.barWidthsPix)
                % Set start and stop index
                if i == 1
                    start = 1;
                    stop = obj.barWidthsPix(i);
                else
                    start = stop;
                    stop = start + obj.barWidthsPix(i);
                end

                % Assign alternating bar colors
                if mod(i,2) == 0
                    obj.imageMatrix(1,start:stop, 1) = obj.darkBar(1);
                    obj.imageMatrix(1,start:stop, 2) = obj.darkBar(2);
                    obj.imageMatrix(1,start:stop, 3) = obj.darkBar(3);
                else
                    obj.imageMatrix(1,start:stop,1) = obj.lightBar(1);
                    obj.imageMatrix(1,start:stop,2) = obj.lightBar(2);
                    obj.imageMatrix(1,start:stop,3) = obj.lightBar(3);
                end
            end    
            diagnoalScreenDistance = ceil(sqrt(obj.canvasSize(1)^2+obj.canvasSize(2)^2));
            obj.imageMatrix = uint8(repmat(obj.imageMatrix, [diagnoalScreenDistance, 1, 1])*255);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime)*(60/obj.frameRate) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            barcode = stage.builtin.stimuli.Image(obj.imageMatrix);
            barcode.size = [size(obj.imageMatrix,2),size(obj.imageMatrix,1)];
            barcode.position = obj.barcodeSize/2;
            barcode.orientation = obj.orientation;
            
            % Add the stimulus to the presentation.
            p.addStimulus(barcode);
            
            barcodeVisible = stage.builtin.controllers.PropertyController(barcode, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < (obj.preFrames + obj.stimFrames));
            p.addController(barcodeVisible);
            
            % Bar position controller
            barcodePosition = stage.builtin.controllers.PropertyController(barcode, 'position', ...
                @(state)motionTable(obj, state.frame - obj.preFrames));
            p.addController(barcodePosition);

            function p = motionTable(obj, frame)
                % Calculate the increment with time.  
                inc = frame * obj.speedPixPerFrame - obj.outerMaskRadiusPix - obj.barcodeSize(2)/2;
                
                p = [cos(obj.orientationRads) sin(obj.orientationRads)] .* (inc*ones(1,2)) + obj.canvasSize/2;
            end
            
            % Create the inner mask.
            if (obj.innerMaskRadiusPix > 0)
                p.addStimulus(obj.makeInnerMask());
            end

            
            % Create the outer mask.
            if (obj.outerMaskRadius > 0)
                p.addStimulus(obj.makeOuterMask());
            end
        end
        
        function mask = makeOuterMask(obj)
            mask = stage.builtin.stimuli.Rectangle();
            mask.color = [obj.backgroundIntensity,...
                obj.backgroundIntensity,...
                obj.backgroundIntensity];
            mask.position = obj.canvasSize/2;
            mask.orientation = 0;
            mask.size = 2 * max(obj.canvasSize) * ones(1,2);
            sc = obj.outerMaskRadiusPix*2 / (2*max(obj.canvasSize));
            m = stage.core.Mask.createCircularAperture(sc);
            mask.setMask(m);
        end
        
        function mask = makeInnerMask(obj)
            mask = stage.builtin.stimuli.Ellipse();
            mask.radiusX = obj.innerMaskRadiusPix;
            mask.radiusY = obj.innerMaskRadiusPix;
            mask.color = [obj.backgroundIntensity,...
                obj.backgroundIntensity,...
                obj.backgroundIntensity];
            mask.position = obj.canvasSize/2;
        end
        
        function prepareEpoch(obj, epoch)
            % Get the current bar orientation.
            obj.orientation = obj.orientationSequence(obj.numEpochsCompleted+1);
            obj.orientationRads = obj.orientation / 180 * pi;
            
            % Get current speed in pix per frame
            obj.speedPixPerFrame = obj.speedSequence(obj.numEpochsCompleted+1)/60;
            
            
            obj.stimFrames = ceil((obj.barcodeSize(2)+obj.outerMaskRadiusPix*2)/obj.speedPixPerFrame);
            obj.stimTime = obj.stimFrames/60*1e3;
            
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
            
            epoch.addParameter('orientation', obj.orientation);
            epoch.addParameter('speed', obj.speedPixPerFrame*60);
            epoch.addParameter('preFrames', obj.preFrames);
            epoch.addParameter('stimFrames', obj.stimFrames);
            epoch.addParameter('tailFrames', obj.tailFrames);
        end
        
        function numberOfBarcodes = get.numberOfBarcodes(obj)
            numberOfBarcodes = length(obj.orientations)*length(obj.speeds);
        end
        
        function numberOfAverages = get.numberOfAverages(obj)
            numberOfAverages = obj.numberOfBarcodes*obj.numberOfReps;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
