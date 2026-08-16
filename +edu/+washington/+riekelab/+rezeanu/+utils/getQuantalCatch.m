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

    intensity=1.0;
    units = 'intensity';
    
    prNames = photoreceptors.keys;

    qCatch = containers.Map(prNames, cell(1,length(prNames)));
    
    for i = 1:length(prNames)
        pr = prNames{i};
        collectingArea = getCollectingArea(photoreceptors(pr).collectingArea, ...
            lightPath, prOrientation);

        temp = zeros(1,length(spectrum.keys));
        for j = 1:length(spectrum.keys)
            key = spectrum.keys{j};
            flux = fluxFactors(key);
            attenuation = attenuations(key);
            spec = spectrum(key);

            temp(j) = edu.washington.riekelab.util.convisom(intensity, units, flux, spec,...
                photoreceptors(pr).spectrum, collectingArea, ndfs, attenuation);
        end
        qCatch(pr) = containers.Map(spectrum.keys, num2cell(round(temp)));
    end
   
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

           
            