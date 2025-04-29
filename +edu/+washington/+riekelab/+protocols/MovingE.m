classdef MovingE < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp
        preTime = 250
        flashTime = 68
        tailTime = 250
        gapTime = 400
        backgroundIntensity = 0.5
        numOrientations = 4
        numDirections = 4
        matFile = 'tumblingE.mat'
        movementScale = [0.5, 1, 2]
        randomizePresentations = true
        onlineAnalysis = 'none'
        numberOfAverages = uint16(100)
    end
    
    properties (Dependent)
        imagesPerEpoch
        stimTime
    end
    
    properties (Dependent, SetAccess = private)
        amp2
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        imageMatrix
        movementMatrix
        xTraj
        yTraj
        frameTraj
        magnificationFactor
        backgroundImage
        imgDir
        preFrames
        flashFrames
        gapFrames
        tailFrames
        stimFrames
        imageOrder
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
            end
            
            try
                obj.imgDir = obj.rig.getDevice('Stage').getConfigurationSettings('local_image_directory');
                if isempty(obj.imgDir)
                    obj.imgDir = 'C:\Users\dreze\UW\letter_motion';
                end
            catch
                obj.imgDir = 'C:\Users\dreze\UW\letter_motion';
            end
            
            % Get frame counts
            obj.preFrames = floor((obj.preTime*1e-3)*obj.frameRate);
            obj.flashFrames = floor((obj.flashTime*1e-3)*obj.frameRate);
            obj.gapFrames = floor((obj.gapTime*1e-3)*obj.frameRate);
            obj.stimFrames = floor((obj.stimTime*1e-3)*obj.frameRate);
            obj.tailFrames = floor((obj.tailTime*1e-3)*obj.frameRate);
            
            % Get the mat file
            dir_contents = dir(fullfile(obj.imgDir, '*.mat'));
            loadedFiles = {dir_contents.name};
            
            if isempty(loadedFiles)
                error('No .mat files found in image directory. \n');
            end
            
            fprintf('%d files loaded from image directory. \n', length(loadedFiles))
            
        end
        
        function createTrajectories(obj)
            
            stimTrajectory_x = zeros(1, obj.stimFrames);
            stimTrajectory_y = zeros(1, obj.stimFrames);
            gapTrajectory = zeros(1,obj.gapFrames);
            tailTrajectory = zeros(1,obj.tailFrames);
            
            displayFrames = obj.flashFrames + obj.gapFrames;
            
            obj.xTraj = [stimTrajectory_x, tailTrajectory];
            obj.yTraj = [stimTrajectory_y, tailTrajectory];
            
            obj.frameTraj = 1:1:length(obj.xTraj);
        end
        
        
        function p = createPresentation(obj)
            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            totalTimePerEpoch = (obj.preFrames + obj.stimFrames + obj.tailFrames)/obj.frameRate;
            p = stage.core.Presentation(totalTimePerEpoch);
            
            p.setBackgroundColor(obj.backgroundIntensity);
            
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = floor([size(obj.imageMatrix{1},2) size(obj.imageMatrix{1},1)]*obj.magnificationFactor);
            p0 = canvasSize / 2;
            scene.position = p0;
            
            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);
            
            p.addStimulus(scene);
            
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < obj.preFrames + obj.stimFrames);
            
            p.addController(sceneVisible);
            
            imgValue = stage.builtin.controllers.PropertyController(scene, 'imageMatrix',...
                @(state)setImage(obj, state.frame - obj.preFrames));
            
            p.addController(imgValue);
            
            function img = setImage(obj, frame)
                img_index = floor(frame / (obj.flashFrames + obj.gapFrames)) + 1;
                if img_index < 1 || img_index > obj.imagesPerEpoch
                    img = obj.backgroundImage;
                elseif (frame >= (obj.flashFrames + opj.gapFrames)*(img_index-1)) && ...
                        (frame <= ((obj.flashFrames + obj.gapFrames)*(img_index-1)+obj.flashFrames))
                    img = obj.imageMatrix{img_index};
                else
                    img = obj.backgroundImage;
                end
            end
            
            % Placeholder for position controller
            
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii})
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii})
                    end
                end
            end
            
            % Load mat file
            matFilePath = fullfile(obj.imgDir, obj.matFile);
            data = load(matFilePath);
            fields = fieldnames(data);
            matData = data.(fields{1});
            
            images = cell(1, obj.numOrientations);
            for i = 1:obj.numOrientations
                images{i} = matData(:,:, (3*i-2):(3*i));
            end
            
            images = repmat(images, 1, obj.numDirections * length(obj.movementScale));
            
            imageIndices = 1:obj.imagesPerEpoch;
            
            if obj.randomizePresentations
                randomizeOrder = randperm(obj.imagesPerEpoch);
                images = images(randomizeOrder);
            else
                randomizeOrder = imageIndices;
            end
            
            
            obj.imageMatrix = images;
            
            obj.imageOrder = cell(1,obj.imagesPerEpoch);
            
            for i = 1:obj.imagesPerEpoch
                if randomizeOrder(i) == 1 || mod(randomizeOrder(i),4) == 1
                    obj.imageOrder{i} = 'up';
                elseif randomizeOrder(i) == 2 || mod(randomizeOrder(i), 4) == 2
                    obj.imageOrder{i} = 'left';
                elseif randomizeOrder(i) == 3 || mod(randomizeOrder(i), 4) == 3
                    obj.imageOrder{i} = 'down';
                else
                    obj.imageOrder{i} = 'right';
                end
            end
            
            distances = [repmat(obj.movementScale(1), 1, obj.imagesPerEpoch/length(obj.movementScale)),...
                repmat(obj.movementScale(2), 1, obj.imagesPerEpoch/length(obj.movementScale)),...
                repmat(obj.movementScale(3), 1, obj.imagesPerEpoch/length(obj.movementScale))];
            
            trajectories_idx = 1:4;
            trajectories = {[0, 10], [10, 0], [0, -10], [-10, 0]};
            
            movement_trajectories = [repmat(trajectories_idx(1), 1, obj.imagesPerEpoch/length(trajectories_idx)),...
                repmat(trajectories_idx(2), 1, obj.imagesPerEpoch/length(trajectories_idx)),...
                repmat(trajectories_idx(3), 1, obj.imagesPerEpoch/length(trajectories_idx)),...
                repmat(trajectories_idx(4), 1, obj.imagesPerEpoch/length(trajectories_idx))];
            
            movement_trajectories = num2cell(movement_trajectories);
            
            for i = 1:obj.imagesPerEpoch
                movement_trajectories{i} = floor(trajectories{movement_trajectories{i}}*distances(i));
            end
            
            
            movement_trajectories = movement_trajectories(randomizeOrder);
            
            obj.movementMatrix = movement_trajectories;
            
            obj.createTrajectories()
            
            obj.magnificationFactor = max(obj.canvasSize(2)/size(obj.imageMatrix{i},1), obj.canvasSize(1)/size(obj.imageMatrix{1},2));
            
            obj.backgroundImage = ones(size(obj.imageMatrix{i})) * obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);
            
            
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('imageOrder', obj.imageOrder);
            epoch.addParameter('movementMatrix', obj.movementMatrix);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            
        end
        
        function imagesPerEpoch = get.imagesPerEpoch(obj)
            imagesPerEpoch = obj.numOrientations * obj.numDirections * length(obj.movementScale);
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.imagesPerEpoch * (obj.flashTime + obj.gapTime);
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end

            
            