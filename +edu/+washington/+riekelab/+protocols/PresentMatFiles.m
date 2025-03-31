% Loads and presents sets of 5 images contained within a .mat file within
% a folder at the 'fileFolder' property.
%
% To determine the 'numberOfAverages' needed to present all of the images in the 
% directory once, you would divide the number of images by the 'imagesPerEpoch'
% property. If there are 1000 images and 'imagesPerEpoch' is 100, then the 
% 'numberOfAverages' needed to present each image once is 1000/100 = 10.
%
% Analysis note:
% Because we are presenting multiple images per epoch, the epoch property imageName 
% that saves the image presented is now a list of all images presented in the correct 
% order with each image delimited by a comma. This should make analyzing the data 
% straightforward.
%
% Also, there is a magnificationFactor property that records the degree to which the
% images were scaled in order to fill the screen.

classdef PresentMatFiles < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                           % Output amplifier
        preTime     = 250             % Pre time in ms
        flashTime   = 400             % Time to flash each image in ms
        gapTime     = 200             % Gap between images in ms
        tailTime    = 250             % Tail time in ms
        imagesPerEpoch = 5            % Number of images per .mat file
        fileFolder  = 'defocusImages'   % Folder containing the .mat files
        backgroundIntensity = 0.5    % 0 - 1 (corresponds to image intensities in folder)
        randomize = true;             % Whether to randomize the order of images in each .mat file
        onlineAnalysis = 'none'       % Type of online analysis
        numberOfAverages = uint16(500)% Number of epochs to queue (one per .mat file)
    end

    properties (Dependent)
        stimTime                      % Total stimulus duration per epoch
    end

    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'}) 
        matFiles
        imageMatrix
        image_dir
        magnificationFactor
        backgroundImage
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
                obj.image_dir = obj.rig.getDevice('Stage').getConfigurationSetting('local_image_directory');
                if isempty(obj.image_dir)
                    obj.image_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
                end
            catch
                obj.image_dir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
            end

            % Get list of .mat files in the directory
            matFile_dir = fullfile(obj.image_dir, obj.fileFolder); 
            dir_contents = dir(fullfile(matFile_dir, '*.mat'));
            obj.matFiles = {dir_contents.name}; % Store file names
            
            if isempty(obj.matFiles)
                error('No .mat files found in the specified directory: %s', obj.fileFolder);
            end
            
            fprintf('Loaded %d .mat files from %s.\n', length(obj.matFiles), obj.fileFolder);
        end

        function p = createPresentation(obj)
            % Stage presentation setup
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            totalTimePerEpoch = (obj.preTime + obj.stimTime + obj.tailTime)*1e-3;
            p = stage.core.Presentation(totalTimePerEpoch);
            
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity 
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = [size(obj.imageMatrix{1},2),size(obj.imageMatrix{1},1)]*obj.magnificationFactor; % Retain aspect ratio.
            scene.position = canvasSize / 2;

            % Use linear interpolation for scaling
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);
            
            % Only display images at appropriate times
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            

            % Cycle through the 5 images within the .mat file
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.time - obj.preTime * 1e-3));
            % Add the controller.
            p.addController(imgValue);

            function img = setImage(obj, time)
                img_index = floor(time / ((obj.flashTime + obj.gapTime) * 1e-3)) + 1;
                if img_index < 1 || img_index > obj.imagesPerEpoch
                    img = obj.backgroundImage;
                elseif (time >= ((obj.flashTime+obj.gapTime)*1e-3)*(img_index-1)) && (time <= (((obj.flashTime+obj.gapTime)*1e-3)*(img_index-1)+obj.flashTime*1e-3))
                    img = obj.imageMatrix{img_index};
                else
                    img = obj.backgroundImage;
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
            
            current_index = obj.numEpochsCompleted+1;
            % Load next .mat file
            matFilePath = fullfile(obj.image_dir, obj.fileFolder, obj.matFiles{current_index});
            data = load(matFilePath);
            fields = fieldnames(data);
            matData = data.(fields{1}); % Extract the stored matrix (912 x 1141 x 15)
            
            % Extract 5 RGB images
            images = cell(1,5);
            for i = 1:5
                images{i} = matData(:,:, (3*i-2):(3*i)); % Extract RGB slices
            end
                        
            % Generate original order indices
            imageIndices = 1:obj.imagesPerEpoch; 
        
            % Randomize if necessary
            if obj.randomize
                randomizedOrder = randperm(5); % Get random order indices
                images = images(randomizedOrder); % Apply random order to images
            else
                randomizedOrder = imageIndices; % Keep original order
            end
            obj.imageMatrix = images; % Store image
            
            % Get the magnification factor to retain aspect ratio.
            obj.magnificationFactor = ceil( max(obj.canvasSize(2)/size(obj.imageMatrix{1},1),obj.canvasSize(1)/size(obj.imageMatrix{1},2)) );
            
            % Create the background image.
            obj.backgroundImage = ones(size(images{1}))*obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);
        
            % Log metadata correctly
            epoch.addParameter('matFile', obj.matFiles{current_index});
            epoch.addParameter('imageOrder', strjoin(arrayfun(@num2str, randomizedOrder, 'UniformOutput', false), ','));
        
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
