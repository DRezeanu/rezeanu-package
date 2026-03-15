% Loads and presents sets of 5 images contained within a .mat file. The
% fileFolder name is determined by the various perameters entered in the
% epoch block params (stixel size, eccentricity, and green primary).
%
% Analysis note:
% Because we are presenting multiple images per epoch, the epoch property imageOrder 
% saves the order in which the five images in the .mat file were presented.
% 
% For now images [1, 2, 3, 4, 5] correspond to index of the defocusStates
% property. And the property "matFile" stores the name of the .mat file,
% which includes a number in the file name counting from file #1 to file #500.

classdef DefocusImages < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                                                 % Output amplifier
        preTime     = 250                                   % Pre time in ms
        flashTime   = 400                                   % Time to flash each image in ms
        gapTime     = 200                                   % Gap between images in ms
        tailTime    = 250                                   % Tail time in ms
        imagesPerEpoch = 5                                  % Number of images per .mat file
        stixelSize = 150                                    % Stixel size in microns (150 or 100)
        eccentricity = -10                                  % Eccentricity (only -10)
        greenPrimary = 565                                  % Green primary of rig config (Rig C Only)
        includeLCA = true                                   % Boolean: true = with LCA, false = noLCA
        invertLCA = false                                   % Boolean: inverts LCA only if LCA = true
        backgroundIntensity = 0.5                           % Intensity of background gray to use during gap time
        randomize = true;                                   % Whether to randomize the order of images in each .mat file
        onlineAnalysis = 'none'                             % Type of online analysis
        numberOfAverages = uint16(500)                      % Number of epochs to queue (one per .mat file)
        defocusStates = [-3, -1, 0, 1, 3]                   % Diopters of defocus contained in each .mat file image
    end

    properties (Dependent)
        stimTime                      % Total stimulus duration per epoch
        fileFolder
    end

    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'}) 
        matFiles
        imageMatrix
        imageDir
        magnificationFactor
        backgroundImage
        preFrames
        flashFrames
        gapFrames
        stimFrames
        tailFrames
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
                obj.imageDir = obj.rig.getDevice('Stage').getConfigurationSetting('local_image_directory');
                if isempty(obj.imageDir)
                    obj.imageDir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
                end
            catch
                obj.imageDir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\';
            end

            obj.preFrames = round((obj.preTime * 1e-3) * 60);
            obj.flashFrames = round((obj.flashTime * 1e-3) * 60);
            obj.gapFrames = round((obj.gapTime * 1e-3) * 60);
            obj.tailFrames = round((obj.tailTime * 1e-3) * 60);
            obj.stimFrames = round((obj.flashFrames + obj.gapFrames) * obj.imagesPerEpoch);

            % Get list of .mat files in the directory
            matFile_dir = fullfile(obj.imageDir, obj.fileFolder);
            dir_contents = dir(fullfile(matFile_dir, '*.mat'));

            % Only load the first numberOfAverages number of images BEFORE
            % randomizing. 
            if length(dir_contents) <= obj.numberOfAverages
                dir_contents = dir_contents(1:obj.numberOfAverages);
            else
                error('Number of averages is larger than the number of mat files in directory.')
            end

            obj.matFiles = {dir_contents.name}; % Store file names
            
            if isempty(obj.matFiles)
                error('No .mat files found in the specified directory: %s', matFile_dir);
            else
                fprintf('Loaded %d .mat files from %s.\n', length(obj.matFiles), matFile_dir);
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
            matFilePath = fullfile(obj.imageDir, obj.fileFolder, obj.matFiles{current_index});
            data = load(matFilePath);
            fields = fieldnames(data);
            matData = data.(fields{1});

            if iscell(matData)
                images = matData;
            else  
                error('DefocusImages requires that the images be organized into a cell array')
            end

            assert(length(images)==length(obj.defocusStates), 'Error: More Images per mat file that Defocus States');

                        
            % Generate original order indices
            imageIndices = 1:obj.imagesPerEpoch; 
        
            % Randomize if necessary
            if obj.randomize
                randomizedOrder = randperm(obj.imagesPerEpoch); % Get random order indices
                images = images(randomizedOrder); % Apply random order to images
            else
                randomizedOrder = imageIndices; % Keep original order
            end
            obj.imageMatrix = images; % Store image
            
            % Get the magnification factor to retain aspect ratio.
            obj.magnificationFactor = max( obj.canvasSize(2)/size(obj.imageMatrix{1},1), obj.canvasSize(1)/size(obj.imageMatrix{1},2) );
            
            % Create the background image.
            obj.backgroundImage = ones(size(images{1}))*obj.backgroundIntensity;
            obj.backgroundImage = uint8(obj.backgroundImage*255);
        
            % Log metadata correctly
            epoch.addParameter('matFile', obj.matFiles{current_index});
            epoch.addParameter('imageOrder', obj.defocusStates(randomizedOrder));
            epoch.addParameter('randomizedOrder', randomizedOrder);
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
            epoch.addParameter('preFrames', obj.preFrames);
            epoch.addParameter('flashFrames', obj.flashFrames);
            epoch.addParameter('gapFrames', obj.gapFrames);
            epoch.addParameter('tailFrames', obj.tailFrames);
            epoch.addParameter('stimFrames', obj.stimFrames);
        end
        
        function p = createPresentation(obj)
            % Stage presentation setup
            totalTimePerEpoch = ceil((obj.preFrames + obj.stimFrames + obj.tailFrames)/60);
            p = stage.core.Presentation(totalTimePerEpoch);
            
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity 
            
            % Prep to display image
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = ceil([size(obj.imageMatrix{1},2),size(obj.imageMatrix{1},1)]*obj.magnificationFactor); % Retain aspect ratio.
            scene.position = obj.canvasSize / 2;

            % Use linear interpolation for scaling
            scene.setMinFunction(GL.LINEAR);
            scene.setMagFunction(GL.LINEAR);
            
            % Only display images at appropriate times
            p.addStimulus(scene);
            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < obj.preFrames + obj.stimFrames);
            p.addController(sceneVisible);
            

            % Cycle through the 5 images within the .mat file
            imgValue = stage.builtin.controllers.PropertyController(scene, ...
                'imageMatrix', @(state)setImage(obj, state.frame - obj.preFrames));
            
            % Add the controller.
            p.addController(imgValue);

            function img = setImage(obj, frame)
                img_index = floor(frame / (obj.flashFrames + obj.gapFrames)) + 1;
                if img_index < 1 || img_index > obj.imagesPerEpoch
                    img = obj.backgroundImage;
                elseif (frame >= (obj.flashFrames+obj.gapFrames)*(img_index-1)) && (frame < ((obj.flashFrames+obj.gapFrames)*(img_index-1)+obj.flashFrames))
                    img = obj.imageMatrix{img_index};
                else
                    img = obj.backgroundImage;
                end
            end
        end

        function stimTime = get.stimTime(obj)
            stimTime = ceil((obj.flashTime + obj.gapTime)* obj.imagesPerEpoch);
        end

        function fileFolder = get.fileFolder(obj)
            if obj.includeLCA
                if obj.invertLCA
                    fileFolder = sprintf('DefocusImages_%dum_%decc_%dnm_invertedLCA', obj.stixelSize, obj.eccentricity, obj.greenPrimary);
                else
                    fileFolder = sprintf('DefocusImages_%dum_%decc_%dnm', obj.stixelSize, obj.eccentricity, obj.greenPrimary);
                end
            else
                fileFolder = sprintf('DefocusImages_%dum_%decc_%dnm_noLCA', obj.stixelSize, obj.eccentricity, obj.greenPrimary);
            end
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
