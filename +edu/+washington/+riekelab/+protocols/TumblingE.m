classdef TumblingE < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 200                   % Stimulus leading duration (ms)
        stimTime = 100                  % Stimulus duration (ms)
        tailTime = 200                  % Stimulus trailing duration (ms)
        gapTime = 200                   % Gap between images in ms
        backgroundIntensity = 0.45
        movementScale = [0.5, 1, 2]     % Scale in bar widths that the tumbling Es will move
        randomizeOrientations = true    % Whether to randomize the order of images in each .mat file
        randomizeMovementDirections = true  % Whether to randomize order of movement directions
        onlineAnalysis = 'extracellular'% Type of online analysis
        numOrientations = 4
        numberOfAverages = uint16(100)   % Number of epochs
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        imageMatrix
        moveHor
        moveVer
        timeTraj
        frameTraj
        orientation
        magnificationFactor
        imgDir
        matFile
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if ~obj.isMeaRig
                obj.showFigure('manookinlab.figures.ResponseFigure', obj.rig.getDevices('Amp'), ...
                    'numberOfAverages', obj.numberOfAverages);

                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',[0 0 0]);
            end
            
            % Get the resources directory.
            try
                obj.imgDir = obj.rig.getDevice('Stage').getConfigurationSetting('local_image_directory');
                if isempty(obj.imgDir)
                    obj.imgDir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\E_motion';
                end
            catch
                obj.imgDir = 'C:\Users\Public\Documents\GitRepos\Symphony2\flashed_images\E_motion';
            end
            
            obj.matFile = 'tumblingE.mat';

            % Get frame counts
            obj.preFrames = floor((obj.preTime*1e-3)*obj.frameRate);
            obj.flashFrames = floor((obj.flashTime*1e-3)*obj.frameRate);
            obj.gapFrames = floor((obj.gapTime*1e-3)*obj.frameRate);
            obj.stimFrames = floor((obj.stimTime*1e-3)*obj.frameRate);
        end
        
        function createTrajectories(obj)

            %get appropriate eye trajectories, at 200Hz
            obj.moveHor = 1:1:9;
            obj.moveVer = 1:1:9;

            obj.timeTraj = (0:(length(obj.moveHor)-1)) ./ obj.stimTime; % sec
           
            %need to make eye trajectories for PRESENTATION relative to the center of the image and
            %flip them across the x axis: to shift scene right, move
            %position left, same for y axis - but y axis definition is
            %flipped for DOVES data (uses MATLAB image convention) and
            %stage (uses positive Y UP/negative Y DOWN), so flips cancel in
            %Y direction
            obj.moveHor = -(obj.moveHor - 1140/2);
            obj.moveVer = (obj.moveVer - 912/2);
            
        end
        
        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);
            
            % Create your scene.
            scene = stage.builtin.stimuli.Image(obj.imageMatrix{1});
            scene.size = [size(obj.imageMatrix{1},2) size(obj.imageMatrix{1},1)]*obj.magnificationFactor;
            p0 = obj.canvasSize/2;
            scene.position = p0;
            
            % Use linear interploation for scaling
            scene.setMinFunction(GL.NEAREST);
            scene.setMagFunction(GL.NEAREST);
            
            % Add the stimulus to the presentation.
            p.addStimulus(scene);
            
            % apply eye trajectories to move image around
            scenePosition = stage.builtin.controllers.PropertyController(scene,...
                'position', @(state)getScenePosition(obj, state.frame - (obj.preFrames+obj.gapFrames), p0));
            
            % Add the controller.
            p.addController(scenePosition);
            
            function p = getScenePosition(obj, time, p0)
                if time < 0
                    p = p0;
                elseif time > obj.timeTraj(end) %out of eye trajectory, hang on last frame
                    p(1) = p0(1) + obj.xTraj(end);
                    p(2) = p0(2) + obj.yTraj(end);
                else % within eye trajectory and stim time
                    dx = interp1(obj.timeTraj,obj.xTraj,time);
                    dy = interp1(obj.timeTraj,obj.yTraj,time);
                    p(1) = p0(1) + dx;
                    p(2) = p0(2) + dy;
                end
            end

            sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(sceneVisible);
            
            
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
            
            images = cell(1,5);
            for i = 1:5
                images{i} = obj.matFile(:,:, (3*i-2):(3*i));
            end
            
            imageIndices = 1:obj.numOrientations;

            % Randomize if necessary 
            if obj.randomizeOrientations
                randomizedOrder = randperm(obj.numOrientations);
                images = images(randomizedOrder);
            else
                randomizedOrder = imageIndices;
            end
            
            obj.imageMatrix = images; % store images

            % Get the magnification factor to retain aspect ratio.
            obj.magnificationFactor = ceil( max(obj.canvasSize(2)/size(obj.imageMatrix{1},1),obj.canvasSize(1)/size(obj.imageMatrix{1},2)) );
            
            % Save the parameters.
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('imageOrder', randomizedOrder)

        end
        
        % Same presentation each epoch in a run. Replay.
        function controllerDidStartHardware(obj)
            controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            if (obj.numEpochsCompleted >= 1) && (obj.numEpochsCompleted < obj.numberOfAverages) && (length(unique(obj.stimulusIndices)) == 1)
                obj.rig.getDevice('Stage').replay
            else
                obj.rig.getDevice('Stage').play(obj.createPresentation());
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
