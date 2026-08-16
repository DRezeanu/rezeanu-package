function qCatch = getLcrQuantalCatch(device, persistor)
    % Grab epoch group 
    try
        epoch_group = persistor.currentEpochGroup;
    catch ME
        qCatch = device.getResource('quantalCatch');
        fprintf('\nUnable to instantiate epoch group, error: %s\n', ME.identifier);
        fprintf('\nReturning placeholder quantal catch for primate with FW00 filter\n');
        return
    end
    
    if isempty(epoch_group)
        qCatch = device.getResource('quantalCatch');
        fprintf('\nNo active epoch group detected');
        fprintf('\nReturning placeholder quantal catch for primate with FW00 filter\n');
        return
    end
    
    % Pull spectrum, ndf attenuations, fluxFactors, current active
    % ndfs and light path from Stage device
    spectrum = device.getResource('spectrum');
    attenuations = device.getResource('ndfAttenuations');
    fluxFactors = device.getResource('fluxFactors');
    ndfs = device.getConfigurationSetting('ndfs');
    path = device.getConfigurationSetting('lightPath');

    % Pull channel specific NDF attenuation values
    r_attenuations = attenuations('red');
    g_attenuations = attenuations('green');
    b_attenuations = attenuations('blue');

    % Get Species for Photoreceptor Spectral Sensitivities
    source = epoch_group.source;
    while ~isempty(source) && ~any(strcmp(source.getResourceNames(), 'photoreceptors'))
        source = source.parent;
    end
    species = source;

    photoreceptors = species.getResource('photoreceptors');

    % Get Preparation for Photoreceptor Orientation info, which is
    % used to get collecting area
    source = epoch_group.source;
    while ~isempty(source) ...
            && isempty(source.getPropertyDescriptors().findByName('preparation')) ...
            && ~any(strcmp(source.getResourceNames(), 'photoreceptorOrientations'))
        source = source.parent;
    end
    preparation = source;
    prep = preparation.getProperty('preparation');

    pr_orientations = preparation.getResource('photoreceptorOrientations');
    if pr_orientations.isKey(prep)
        pr_orientation = pr_orientations(prep);
    else
        pr_orientation = '';
    end

    r_factor = fluxFactors('red');
    g_factor = fluxFactors('green');
    b_factor = fluxFactors('blue');

    r_spectrum = spectrum('red');
    g_spectrum = spectrum('green');
    b_spectrum = spectrum('blue');

    intensity=1.0;
    units = 'intensity';
    
    lmsToRgb = zeros(3,4);
    
    % Swap rods with s cones so the PR names are listed as
    % L, M, S, rod instead of L, M, rod, S;
    prNames = photoreceptors.keys;
    temp = prNames{4};
    prNames{4}=prNames{3};
    prNames{3} = temp;
    
    for i = 1:length(prNames)
        pr = prNames{i};
        collectingArea = getCollectingArea(photoreceptors(pr).collectingArea, ...
            path, pr_orientation);

        lmsToRgb(1,i) = edu.washington.riekelab.util.convisom(intensity, units, r_factor, r_spectrum, ...
                photoreceptors(pr).spectrum, collectingArea, ndfs, r_attenuations);
    end
    
    for i = 1:length(prNames)
        pr = prNames{i};
        collectingArea = getCollectingArea(photoreceptors(pr).collectingArea, ...
            path, pr_orientation);

        lmsToRgb(2,i) = edu.washington.riekelab.util.convisom(intensity, units, g_factor, g_spectrum, ...
                photoreceptors(pr).spectrum, collectingArea, ndfs, g_attenuations);
    end
    
    for i = 1:length(prNames)
        pr = prNames{i};
        collectingArea = getCollectingArea(photoreceptors(pr).collectingArea, ...
            path, pr_orientation);

        lmsToRgb(3,i) = edu.washington.riekelab.util.convisom(intensity, units, b_factor, b_spectrum, ...
                photoreceptors(pr).spectrum, collectingArea, ndfs, b_attenuations);
    end
   
    qCatch = round(lmsToRgb);
end

function a = getCollectingArea(map, path, orientation)
    if (strcmpi(path, 'below') && any(strcmpi(orientation, {'down', 'lateral'}))) ...
            || (strcmpi(path, 'above') && any(strcmpi(orientation, {'up', 'lateral'})))
        a = map('photoreceptorSide');
    elseif (strcmpi(path, 'below') && strcmpi(orientation, 'up')) ...
            || (strcmpi(path, 'above') && strcmpi(orientation, 'down'))
        a = map('ganglionCellSide');
    else
        warning('Unexpected light path or photoreceptor orientation. Using 0 for collecting area.');
        a = 0;
    end
end

           
            