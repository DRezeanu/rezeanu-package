classdef MovingLetters < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        flashTime = 400                 % Flash duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        gapTime = 400                   % Gap between images in ms
        backgroundIntensity = 0.45
        numOrientations = 4
        numDirections = 3
        matFile = 'tumblingE.mat'       % Filename of matfile with images in it
        movementScale = [0.5, 1, 2]          % Scale in bar widths that the tumbling Es will move
        randomizePresentations = true    % Whether to randomize the order of images in each .mat file
        onlineAnalysis = 'extracellular'% Type of online analysis
        numberOfAverages = uint16(100)   % Number of epochs
    end
    
    properties (Dependent)
        imagesPerEpoch
        stimTime                        % Total stim time
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
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
        loadedFile
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
            
            % Get the resources directory.
            try
                obj.imgDir = obj.rig.getDevice('Stage').getConfigurationSetting('local_image_directory');
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
            
            % Get .mat file name from the directory
            dir_contents = dir(fullfile(obj.imgDir, '*.mat'));
            obj.loadedFile = {dir_contents.name}; % Store file names
            
            if isempty(obj.loadedFile)
                error('No .mat files found in image directory. \n');
            end
            
            fprintf('Loaded %s from image directory.\n', obj.loadedFile{1});
        end
        
        function createTrajectories(obj)

            % movement trajectories
            stimTrajectory_x = zeros(1,obj.stimFrames);
            stimTrajectory_y = zeros(1,obj.stimFrames);

            gapTrajectory = zeros(1,obj.gapFrames);
            tailTrajectory = zeros(1,obj.tailFrames);
            
            displayFrames = obj.flashFrames + obj.gapFrames;
            
            for i = 0:obj.imagesPerEpoch-1
                
                x_shift = obj.movementMatrix{i+1}(1);
                flashTrajectory_x = round(linspace(0,x_shift,obj.flashFrames));
                stimTrajectory_x(i*displayFrames+1:(i+1)*displayFrames) = ...
                    [flashTrajectory_x, gapTrajectory];
                
                y_shift = obj.movementMatrix{i+1}(2);
                flashTrajectory_y = round(linspace(0,y_shift, obj.flashFrames));
                stimTrajectory_y(i*displayFrames+1:(i+1)*displayFrames) = ...
                    [flashTrajectory_y, gapTrajectory];
            end

            fullTrajectory_x = [stimTrajectory_x, tailTrajectory];
            fullTrajectory_y = [stimTrajectory_y, tailTrajectory];
            
            obj.xTraj = fullTrajectory_x;
            obj.yTraj = fullTrajectory_y;
            obj.frameTraj = 1:1:length(fullTrajectory_x);
            
        end
        
        function p = createPresentation(obj)
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            totalTimePerEpoch = (obj.preTime + obj.stimTime + obj.tailTime)*1e-3;
            p = stage.core.Presentation(totalTimePerEpoch);
            
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create your scene.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = [size(obj.imageMatrix{1},2) size(obj.imageMatrix{1},1)]*obj.magnificationFactor;
            p0 = canvasSize / 2;
            scene.position = p0;
            
            % Use linear interploation for scaling
            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(scene); 
            
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < obj.preFrames + obj.stimFrames);
            p.addController(sceneVisible);
            
            % Cycle through the images within the .mat file
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.frame - obj.preFrames));
            
            % Add the controller
            p.addController(imgValue);
            
            function img = setImage(obj, frame)
                img_index = floor(frame / (obj.flashFrames + obj.gapFrames)) + 1;
                if img_index < 1 || img_index > obj.imagesPerEpoch
                    img = obj.backgroundImage;
                elseif (frame >= (obj.flashFrames+obj.gapFrames)*(img_index-1)) && (frame <= ((obj.flashFrames+obj.gapFrames)*(img_index-1)+obj.flashFrames))
                    img = obj.imageMatrix{img_index};
                else
                    img = obj.backgroundImage;
                end
            end
            
            % apply eye trajectories to move image around
            scenePosition = stage.builtin.controllers.PropertyController(scene,...
                'position', @(state)getScenePosition(obj, state.frame - obj.preFrames, p0));
            
            % Add the controller.
            p.addController(scenePosition);
            
            
            function p = getScenePosition(obj, frame, p0)
                img_index = floor(frame / (obj.flashFrames + obj.gapFrames)) + 1;
                if img_index < 1 || img_index > obj.imagesPerEpoch
                    p = p0;
                elseif (frame >= (obj.flashFrames+obj.gapFrames)*(img_index-1)) && (frame <= ((obj.flashFrames+obj.gapFrames)*(img_index-1)+obj.flashFrames))
                    dx = interp1(obj.frameTraj, obj.xTraj, frame);
                    dy = interp1(obj.frameTraj, obj.yTraj, frame);
                    p(1) = p0(1)+dx;
                    p(2) = p0(2)+dy;
                else
                    p = p0;
                end
            end
            
            
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
            
            % Load mat file
            matFilePath = fullfile(obj.imgDir, obj.matFile);
            data = load(matFilePath);
            fields = fieldnames(data);
            matData = data.(fields{1});
            
            % Create image matrix
            images = cell(1,obj.numOrientations);
            for i = 1:obj.numOrientations
                images{i} = matData(:,:, (3*i-2):(3*i));
            end
            images = repmat(images, 1, obj.numDirections * length(obj.movementScale));

            % Randomize if necessary 
            imageIndices = 1:obj.imagesPerEpoch;
            
            if obj.randomizePresentations
                randomizedOrder = randperm(obj.imagesPerEpoch);
                images = images(randomizedOrder);
            else
                randomizedOrder = imageIndices;
            end
            
            obj.imageMatrix = images; % store images
            
            imageOrder = cell(1,obj.imagesPerEpoch);
            
            % Pull image order as cell array of strings for metadata
            for i = 1:obj.imagesPerEpoch
                if randomizedOrder(i) == 1 || mod(randomizedOrder(i),4) == 1
                    imageOrder{i} = 'up';
                elseif randomizedOrder(i) == 2 || mod(randomizedOrder(i), 4) == 2
                    imageOrder{i} = 'left';
                elseif randomizedOrder(i) == 3 || mod(randomizedOrder(i), 4) == 3
                    imageOrder{i} = 'down';
                else
                    imageOrder{i} = 'right';
                end
            end
            
            % Randomize distances
            distances = repmat(obj.movementScale, 1, obj.numOrientations*obj.numDirections);
            distances = distances(randomizedOrder);
           
            
            % Directions
            d_ver = {[0,10], [-10,0], [10,0]};
            d_hor = {[-10,0], [10,0], [0,-10]};
            
            d_ver = repmat(d_ver, 1, obj.numOrientations*length(obj.movementScale)/2);
            d_hor = repmat(d_hor, 1, obj.numOrientations*length(obj.movementScale)/2);
            
            movement = cell(1,obj.imagesPerEpoch);
            
            vertical_count = 0;
            horizontal_count = 0;
            
            for i = 1:length(randomizedOrder)
                if mod(randomizedOrder(i),2) == 1
                    vertical_count = vertical_count + 1;
                    movement{i} = floor(d_ver{vertical_count}*distances(i));
                else
                    horizontal_count = horizontal_count + 1;
                    movement{i} = floor(d_hor{horizontal_count}*distances(i));
                end
            end
            
            obj.movementMatrix = movement;
            obj.createTrajectories()

            % Get the magnification factor to retain aspect ratio.
            obj.magnificationFactor = ceil( max(obj.canvasSize(2)/size(obj.imageMatrix{1},1),obj.canvasSize(1)/size(obj.imageMatrix{1},2)) );

            % Create background image
            obj.backgroundImage = ones(size(images{1})) * obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);

            % Save the parameters.
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('imageOrder', imageOrder)
            epoch.addParameter('distanceMoved', obj.movementMatrix)

        end
        
        function imagesPerEpoch = get.imagesPerEpoch(obj)
            imagesPerEpoch = obj.numOrientations * obj.numDirections * length(obj.movementScale);
        end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.imagesPerEpoch * (obj.flashTime + obj.gapTime);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
