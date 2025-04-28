classdef MovingLetters < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        flashTime = 68                  % Flash duration (ms)
        tailTime = 250                  % Stimulus trailing duration (ms)
        gapTime = 400                   % Gap between images in ms
        backgroundIntensity = 0.45
        numOrientations = 4
        numDirections = 4
        matFile = 'tumblingE_3.mat'       % Filename of matfile with images in it
        movementScale = [0.5, 1, 2]       % Scale in bar widths that the tumbling Es will move
        randomizePresentations = true    % Whether to randomize the order of images in each .mat file
        onlineAnalysis = 'extracellular'% Type of online analysis
        numberOfAverages = uint16(100)   % Number of epochs
    end
    
    properties (Dependent)
        imagesPerEpoch
        stimTime                        % Total stim time for the full epoch
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
                    obj.imgDir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\letter_motion';
                end
            catch
                obj.imgDir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\letter_motion';
            end

            % Get frame counts
            obj.preFrames = floor((obj.preTime*1e-3)*obj.frameRate);
            obj.flashFrames = floor((obj.flashTime*1e-3)*obj.frameRate);
            obj.gapFrames = floor((obj.gapTime*1e-3)*obj.frameRate);
            obj.stimFrames = floor((obj.stimTime*1e-3)*obj.frameRate);
            obj.tailFrames = floor((obj.tailTime*1e-3)*obj.frameRate);
            
            % Get .mat file name from the directory as a sanity check to
            % make sure the correct file was loaded
            dir_contents = dir(fullfile(obj.imgDir, '*.mat'));
            obj.loadedFile = {dir_contents.name}; % Store file names
            
            if isempty(obj.loadedFile)
                error('No .mat files found in image directory. \n');
            end
            
            fprintf('Loaded %s from image directory.\n', obj.loadedFile{1});
        end
        
        function createTrajectories(obj)

            % create placeholder vectors of the right length for the
            % stimuli (stimFrames), the gaps (gapFrames), and the tail
            % trajectory (tailFrames)
            stimTrajectory_x = zeros(1,obj.stimFrames);
            stimTrajectory_y = zeros(1,obj.stimFrames);
            gapTrajectory = zeros(1,obj.gapFrames);
            tailTrajectory = zeros(1,obj.tailFrames);
            
            % Each flash we display one iteration of flash frames + gap
            % frames. This variable is used to populate stimTrajectory_x
            % and stimTrajectory_y correctly so the movement only happens
            % when the image is being flashed
            displayFrames = obj.flashFrames + obj.gapFrames;
            
            % Pull X and Y axis movements and populate the two stim
            % trajectory variables appropriately
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

            % Concatenate the stim trajectories with the tail trajectory
            % (which is just no movement) into the global xTraj and yTraj
            % variables that now contain the full trajectory for the entire
            % epoch
            obj.xTraj = [stimTrajectory_x, tailTrajectory];
            obj.yTraj = [stimTrajectory_y, tailTrajectory];
            
            % Generate the frame numbers for every single frame in the full
            % x and y trajectory variables. This may seem strange but we
            % need this because we can't index directly into xTraj and
            % yTraj to set scene position (for some unholy reason).
            obj.frameTraj = 1:1:length(obj.xTraj);
            
        end
        
        function p = createPresentation(obj)
            % Create a presentation that's the correct length of time
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            totalTimePerEpoch = (obj.preTime + obj.stimTime + obj.tailTime)*1e-3;
            p = stage.core.Presentation(totalTimePerEpoch);
            
            % Set the background color of the screen
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create an image scene using the first image in the stack
            % contained inside imageMatrix and define p0 (the starting
            % position) as the center pixel of the canvas
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = ceil([size(obj.imageMatrix{1},2) size(obj.imageMatrix{1},1)]*obj.magnificationFactor);
            p0 = canvasSize / 2;
            scene.position = p0;
            
            % Ensure the scene uses linear interploation for scaling
            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);
            
            % Add the scene to the presentation.
            p.addStimulus(scene); 
            
            % Create a visibility controller that makes the scene visible
            % after preFrames have elapsed and then invisible once
            % preFrames + stimFrames have elapsed.
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < obj.preFrames + obj.stimFrames);
            
            % Add the visibility controller to the presentation
            p.addController(sceneVisible);
            
            % Create an imageMatrix controller that cycles through all of
            % the images inside the imageMatrix cell array, and uses the
            % setImage method to decide what image is currently being used
            % to populate the scene
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.frame - obj.preFrames));
            
            % Add the imageMatrix controller to the presentation
            p.addController(imgValue);
            
            % SetImage method outputs the image that should be shown and
            % takes as input the current frame minus the pre-frames. This
            % value is used to compute the "img_index" variable that
            % essentially changes value for every complete cycle of flash
            % frames + gap frames, starting at 0. The elseif condition is a
            % little confusing but essentially ensures that the imageMatrix
            % image is being shown only when flashFrames are being shown
            % and not when gapFrames are shown or when preFrames and
            % tailFrames are shown
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
            
            % Create a position controller that uses the calculated X and Y
            % trajectories to set the scene position.
            scenePosition = stage.builtin.controllers.PropertyController(scene,...
                'position', @(state)setScenePosition(obj, state.frame - obj.preFrames, p0));
            
            % Add the position controller to the presentation.
            p.addController(scenePosition);
            
            % Similar to the setImage method, the setScenePosition method
            % uses the same img_index method to count frames and output the
            % correct position "p" based on the xTraj and yTraj variables
            % we created earlier. Note that we can't just index into xTraj
            % and yTraj to get dx and dy. For some reason that doesn't
            % work, so we "interpolate" using a vector that counts from 1
            % to the total numbe of frames (frameTraj), the X and Y
            % trajectories, and the current frame-preFrames. This assigns a
            % single value to dx and dy, which are then added to p0 to
            % shift the image around.
            function p = setScenePosition(obj, frame, p0)
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
            
            % Create the image matrix, pulling three layers at a time to
            % generate each RGB image and storing each image into a
            % separate cell in the images variable
            images = cell(1,obj.numOrientations);
            for i = 1:obj.numOrientations
                images{i} = matData(:,:, (3*i-2):(3*i));
            end

            % Repeat this set of four images as many times as it takes to
            % get every combination of E orientation, directions of
            % movement, and scale of movement (4 orientations * 3
            % directions * 3 scales of movement = 36 total images per
            % epoch)
            images = repmat(images, 1, obj.numDirections * length(obj.movementScale));

            % Randomize if necessary 
            imageIndices = 1:obj.imagesPerEpoch;
            
            if obj.randomizePresentations
                randomizedOrder = randperm(obj.imagesPerEpoch);
                images = images(randomizedOrder);
            else
                randomizedOrder = imageIndices;
            end
            
            % Store the images inside the imageMatrix variable
            obj.imageMatrix = images;
            
            % Create a cell array of strings that stores the E orientations
            % shown in plain english (i.e. 'up', 'down', 'left', and
            % 'right')
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
            
            % Arrange all movement distances starting with the shortest
            % distance first, then the middle distance, then the longest
            % distance. These don't need to be randomized. They'll be used
            % to scale the movement trajectories below, and then the
            % movement trajectories are randomized if the option to
            % randomizePresentations is checked.
            distances = [repmat(obj.movementScale(1), 1, obj.imagesPerEpoch/length(obj.movementScale)),...
                repmat(obj.movementScale(2), 1, obj.imagesPerEpoch/length(obj.movementScale)),....
                repmat(obj.movementScale(3), 1, obj.imagesPerEpoch/length(obj.movementScale))];

            % Assign movement trajectories to all stimuli based on whether
            % the E is oriented vertically or horizontally. If the E is
            % oriented vertically (pointing up or down) there is only one
            % left-right movement trajectory since they are redundant, but
            % there are separate up and down trajectories since they are
            % different. If the E is oriented horizontally (pointing left
            % or right) there is only one up-down movement trajectory but
            % separate left and right movement trajectories.
            trajectories_idx = 1:4;
            trajectories = {[0,10], [10,0], [0,-10], [-10,0]};

            movement_trajectories = [repmat(trajectories_idx(1), 1, obj.imagesPerEpoch/length(trajectories_idx)),...
                            repmat(trajectories_idx(2), 1, obj.imagesPerEpoch/length(trajectories_idx)),...
                            repmat(trajectories_idx(3), 1, obj.imagesPerEpoch/length(trajectories_idx)),...
                            repmat(trajectories_idx(4), 1, obj.imagesPerEpoch/length(trajectories_idx))];
            movement_trajectories = num2cell(movement_trajectories);

            for i = 1:obj.imagesPerEpoch
                movement_trajectories{i} = floor(trajectories{movement_trajectories{i}}*distances(i));
            end
            
            % Randomize movement order if randomize presntations is
            % checked, note that the code above means "randomizedOrder" may
            % not actually be randomized, so we don't have to include a
            % second if statement here.
            movement_trajectories = movement_trajectories(randomizedOrder);
            
            % Assign movement trajectories to the movementMatrix property
            % and then call createTrajectories to use that matrix to create
            % the x and y trajectories for the entire epoch.
            obj.movementMatrix = movement_trajectories;
            obj.createTrajectories()

            % Get the magnification factor to retain aspect ratio.
            obj.magnificationFactor = max(obj.canvasSize(2)/size(obj.imageMatrix{1},1),obj.canvasSize(1)/size(obj.imageMatrix{1},2));

            % Create background image
            obj.backgroundImage = ones(size(images{1})) * obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);

            % Save the parameters.
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('imageOrder', imageOrder)
            epoch.addParameter('distanceMoved', obj.movementMatrix)
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);

        end
        
        % Define images per epoch using number of orientations, number of
        % directions, and number of number of different scales of movement.
        function imagesPerEpoch = get.imagesPerEpoch(obj)
            imagesPerEpoch = obj.numOrientations * obj.numDirections * length(obj.movementScale);
        end
        
        % Define stim time as images per epoch * (flash time + gap time)
        function stimTime = get.stimTime(obj)
            stimTime = obj.imagesPerEpoch * (obj.flashTime + obj.gapTime);
        end
        
        % Continue preparing epochs if the number of epochs prepared is
        % less than the defined number of averages
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        % Continue this run if the number of epochs completed is less than
        % the number of averages.
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end
