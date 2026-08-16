function qCatch = getQuantalCatch(species, spectrum, attenuations, fluxFactors, ndfs, lightPath, prOrientation)
    
    ip = inputParser;
    
    isMapping = @(x) isa(x, 'containers.Map');
    addRequired(ip, 'species', @(x) isa(x, 'edu.washington.riekelab.sources.Subject'));
    addRequired(ip, 'spectrum', isMapping);
    addRequired(ip, 'attenuations', isMapping);
    addRequired(ip, 'fluxFactors', isMapping);
    addRequired(ip, 'ndfs', @iscell);
    addRequired(ip, 'lightPath', @ischar);
    addRequired(ip, 'prOrientation', @ischar);

    parse(ip, species, spectrum, attenuations, fluxFactors, ndfs, lightPath, prOrientation); 
    
    species = ip.Results.species;
    spectrum = ip.Results.spectrum;
    attenuations = ip.Results.attenuations;
    fluxFactors = ip.Results.fluxFactors;
    ndfs = ip.Results.ndfs;
    lightPath = ip.Results.lightPath;
    prOrientation = ip.Results.prOrientation;
    
    photoreceptors = species.getResource('photoreceptors');
    
    % Pull channel specific NDF attenuation values
    r_attenuations = attenuations('red');
    g_attenuations = attenuations('green');
    b_attenuations = attenuations('blue');

    r_factor = fluxFactors('red');
    g_factor = fluxFactors('green');
    b_factor = fluxFactors('blue');

    r_spectrum = spectrum('red');
    g_spectrum = spectrum('green');
    b_spectrum = spectrum('blue');

    intensity=1.0;
    units = 'intensity';
    
    PrsToRgb = zeros(3,length(photoreceptors.keys));
    
    % Swap rods with s cones so the PR names are listed as
    % L, M, S, rod instead of L, M, rod, S;
    prNames = photoreceptors.keys;
    temp = prNames{4};
    prNames{4}=prNames{3};
    prNames{3} = temp;
    
    for i = 1:length(prNames)
        pr = prNames{i};
        collectingArea = getCollectingArea(photoreceptors(pr).collectingArea, ...
            lightPath, prOrientation);

        PrsToRgb(1,i) = edu.washington.riekelab.util.convisom(intensity, units, r_factor, r_spectrum, ...
                photoreceptors(pr).spectrum, collectingArea, ndfs, r_attenuations);
         
    end
    
    for i = 1:length(prNames)
        pr = prNames{i};
        collectingArea = getCollectingArea(photoreceptors(pr).collectingArea, ...
            lightPath, prOrientation);

        PrsToRgb(2,i) = edu.washington.riekelab.util.convisom(intensity, units, g_factor, g_spectrum, ...
                photoreceptors(pr).spectrum, collectingArea, ndfs, g_attenuations);
    end
    
    for i = 1:length(prNames)
        pr = prNames{i};
        collectingArea = getCollectingArea(photoreceptors(pr).collectingArea, ...
            lightPath, prOrientation);

        PrsToRgb(3,i) = edu.washington.riekelab.util.convisom(intensity, units, b_factor, b_spectrum, ...
                photoreceptors(pr).spectrum, collectingArea, ndfs, b_attenuations);
    end
   
    qCatch = round(PrsToRgb);
end

function a = getCollectingArea(map, lightPath, orientation)
    if (strcmpi(lightPath, 'below') && any(strcmpi(orientation, {'down', 'lateral'}))) ...
            || (strcmpi(lightPath, 'above') && any(strcmpi(orientation, {'up', 'lateral'})))
        a = map('photoreceptorSide');
    elseif (strcmpi(lightPath, 'below') && strcmpi(orientation, 'up')) ...
            || (strcmpi(lightPath, 'above') && strcmpi(orientation, 'down'))
        a = map('ganglionCellSide');
    else
        warning('Unexpected light path or photoreceptor orientation. Using 0 for collecting area.');
        a = 0;
    end
end

           
            