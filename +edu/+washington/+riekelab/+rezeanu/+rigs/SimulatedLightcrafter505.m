classdef SimulatedLightcrafter505 < symphonyui.core.descriptions.RigDescription
    
    methods
        
        function obj = SimulatedLightcrafter505()
            import symphonyui.builtin.daqs.*;
            import symphonyui.builtin.devices.*;
            import symphonyui.core.*;
            
            daq = HekaSimulationDaqController();
            obj.daqController = daq;
            
            % Rig name and laboratory.
            rigDev = manookinlab.devices.RigPropertyDevice('RiekeLab','SimulatedLightcrafter');
            obj.addDevice(rigDev);
            
            amp1 = MultiClampDevice('Amp1', 1).bindStream(daq.getStream('ao0')).bindStream(daq.getStream('ai0'));
            obj.addDevice(amp1);

            % Add an analog trigger device to simulate the MEA.
            trigger = UnitConvertingDevice('ExternalTrigger', 'V').bindStream(daq.getStream('ao1'));
            obj.addDevice(trigger);
           
            % The 505 nm LED.
            greenRamp = importdata(edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'green_led_gamma_ramp.txt'));
            green = CalibratedDevice('Green LED', Measurement.NORMALIZED, greenRamp(:, 1), greenRamp(:, 2)).bindStream(daq.getStream('ao2'));
            green.addConfigurationSetting('ndfs', {}, ...
                'type', PropertyType('cellstr', 'row', {'C1', 'C2', 'C3', 'C4', 'C5'}));
            green.addResource('ndfAttenuations', containers.Map( ...
                {'C1', 'C2', 'C3', 'C4', 'C5'}, ...
                {0.2866, 0.5933, 0.9675, 1.9279, 2.1372}));
            green.addConfigurationSetting('gain', '', ...
                'type', PropertyType('char', 'row', {'', 'low', 'medium', 'high'}));
            green.addResource('fluxFactorPaths', containers.Map( ...
                {'low', 'medium', 'high'}, { ...
                edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'green_led_low_flux_factors.txt'), ...
                edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'green_led_medium_flux_factors.txt'), ...
                edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'green_led_high_flux_factors.txt')}));
            green.addConfigurationSetting('lightPath', 'below', 'isReadOnly', true);
            green.addResource('spectrum', importdata(edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'green_led_spectrum.txt')));
            obj.addDevice(green);
            
            
%              trigger1 = UnitConvertingDevice('Trigger1', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
%             daq.getStream('doport1').setBitPosition(trigger1, 0);
%             obj.addDevice(trigger1);
%             
%             trigger2 = UnitConvertingDevice('Trigger2', symphonyui.core.Measurement.UNITLESS).bindStream(daq.getStream('doport1'));
%             daq.getStream('doport1').setBitPosition(trigger2, 2);
%             obj.addDevice(trigger2);
            
            frameMonitor = UnitConvertingDevice('Frame Monitor', 'V').bindStream(obj.daqController.getStream('ai7'));
            obj.addDevice(frameMonitor);
            
            microdisplay = edu.washington.riekelab.rezeanu.devices.SimulatedLcrVideoMode('micronsPerPixel', 3.07);
            
            microdisplay.addResource('fluxFactorPaths', containers.Map( ...
                {'auto', 'red', 'green', 'blue'}, { ...
                edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'lightcrafter_below_auto505_flux_factors.txt'), ...
                edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'lightcrafter_below_red505_flux_factors.txt'), ...
                edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'lightcrafter_below_green505_flux_factors.txt'), ...
                edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'lightcrafter_below_blue505_flux_factors.txt')}));
            microdisplay.addConfigurationSetting('lightPath', 'below', 'isReadOnly', true);
            
            myspect = containers.Map( ...
                {'auto', 'red', 'green', 'blue'}, { ...
                importdata(edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'lightcrafter_below_auto505_spectrum.txt')), ...
                importdata(edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'lightcrafter_below_red505_spectrum.txt')), ...
                importdata(edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'lightcrafter_below_green505_spectrum.txt')), ...
                importdata(edu.washington.riekelab.Package.getCalibrationResource('rigs', 'suction', 'lightcrafter_below_blue505_spectrum.txt'))});
            
            microdisplay.addResource('spectrum', myspect);

            
            
            % Compute the Quantal catch.
            qCatch = [
               0.664987   0.169773   0.040604   0.154258
               0.638458   1.136154   0.227892   3.911955
               0.114495   0.115746   1.121788   0.715405]*1e6;
           
            microdisplay.addResource('quantalCatch', qCatch);
            
            microdisplay.addConfigurationSetting('ndfs', {}, ...
                'type', PropertyType('cellstr', 'row', {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40','C1', 'C2', 'C3', 'C4', 'C5'}));
            
            microdisplay.addResource('ndfAttenuations', containers.Map( ...
                {'auto','red', 'green', 'blue'}, { ...
                containers.Map( ...
                    {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40','C1', 'C2', 'C3', 'C4', 'C5'}, ...
                    {0, 0.5153, 1.0175, 2.1873, 3.2603, 4.3110, 0.2866, 0.5460, 0.9675, 1.9279, 2.1372}), ...
                containers.Map( ...
                    {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40','C1', 'C2', 'C3', 'C4', 'C5'}, ...
                    {0, 0.5089, 1.0047, 2.0381, 3.0604, 4.0434, 0.2866, 0.5945, 0.9675, 1.9279, 2.1372}), ...
                containers.Map( ...
                    {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40','C1', 'C2', 'C3', 'C4', 'C5'}, ...
                    {0, 0.5074, 1.0031, 2.1752, 3.2626, 4.2867, 0.2866, 0.5470, 0.9675, 1.9279, 2.1372}), ...
                containers.Map( ...
                    {'FW00', 'FW05', 'FW10', 'FW20', 'FW30', 'FW40','C1', 'C2', 'C3', 'C4', 'C5'}, ...
                    {0, 0.5312, 1.0494, 2.4151, 3.6192, 4.7103, 0.2663, 0.5140, 0.9569, 2.0810, 2.3747})}));    
            
            % Binding the video device to an unused stream only so its configuration settings are written to each epoch.
            microdisplay.bindStream(daq.getStream('doport1'));
            daq.getStream('doport1').setBitPosition(microdisplay, 15);    
            obj.addDevice(microdisplay);
            
            % Add mea device (this will fail, but it more accurately
            % represents what figures will be shown on screen)
            mea = manookinlab.devices.MEADevice(9001);
            obj.addDevice(mea);
            
            % Add the filter wheel.
%             filterWheel = manookinlab.devices.FilterWheelDevice('comPort', 'COM13');
%             obj.addDevice(filterWheel);
        end
    end
    
end

