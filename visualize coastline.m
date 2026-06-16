function fig = visualizeCoastline(dem, R, coastlines, labels, varargin)
% VISUALIZECOASTLINE  Render DEM + multiple coastline scenarios on a map.
%
%   fig = visualizeCoastline(dem, R, coastlines, labels)
%   fig = visualizeCoastline(dem, R, coastlines, labels, Name, Value, ...)
%
%   Inputs:
%     dem        – Digital Elevation Model (m). NaN = open ocean.
%     R          – Raster reference object matching dem.
%     coastlines – Cell array of Nx2 [lat lon] coastline arrays.
%                  Each element is one scenario (e.g., different years).
%     labels     – Cell array of strings, one per coastline scenario.
%
%   Optional Name-Value pairs:
%     'FloodMasks'    – Cell array of binary flood-mask matrices (same size
%                       as dem) to shade newly flooded areas.
%     'Title'         – Figure title string.
%     'ColorMap'      – Colormap for the DEM hillshade (default: 'terrain').
%     'ElevationLimits' – [min max] clamp for the colorbar (default: auto).
%     'BaseCoastColor'  – RGB or colour name for current coastline.
%     'FigureSize'      – [width height] in pixels (default: [1200 700]).
%
%   Output:
%     fig – Handle to the created figure.
%
%   Example:
%     fig = visualizeCoastline(dem, R, {coast2050, coast2100}, ...
%           {'2050 (+0.5 m)', '2100 (+1.2 m)'}, ...
%           'FloodMasks', {flood2050, flood2100}, ...
%           'Title', 'Miami, FL – Projected Coastlines');

% -------------------------------------------------------------------------
%  Input parsing
% -------------------------------------------------------------------------
p = inputParser();
p.addRequired('dem');
p.addRequired('R');
p.addRequired('coastlines', @iscell);
p.addRequired('labels',     @iscell);
p.addParameter('FloodMasks',      {},           @iscell);
p.addParameter('Title',           'Coastline Projection', @ischar);
p.addParameter('ColorMap',        'terrain',    @ischar);
p.addParameter('ElevationLimits', [],           @isnumeric);
p.addParameter('BaseCoastColor',  [0 0 0],      @(x) isnumeric(x)||ischar(x));
p.addParameter('FigureSize',      [1200 700],   @isnumeric);
p.parse(dem, R, coastlines, labels, varargin{:});
opts = p.Results;

% -------------------------------------------------------------------------
%  Setup figure
% -------------------------------------------------------------------------
fig = figure('Color','w','Position',[100 100 opts.FigureSize]);
ax  = axes(fig);

% -------------------------------------------------------------------------
%  Display DEM as hillshaded terrain
% -------------------------------------------------------------------------
% Hillshade approximation: gradient-based shading
[Gx, Gy]   = gradient(dem);
hillshade   = -Gx * cosd(45) * cosd(315) ...
              - Gy * cosd(45) * sind(315) ...
              + sind(45);
hillshade   = mat2gray(hillshade);   % normalise 0–1

% Get spatial extent from reference object
if isa(R,'map.rasterref.GeographicCellsReference') || ...
   isa(R,'map.rasterref.GeographicPostingsReference')
    xLim = R.LongitudeLimits;
    yLim = R.LatitudeLimits;
    xLabel = 'Longitude (°)';
    yLabel = 'Latitude (°)';
else
    xLim = R.XWorldLimits;
    yLim = R.YWorldLimits;
    xLabel = 'Easting (m)';
    yLabel = 'Northing (m)';
end

% Create RGB terrain image blended with hillshade
if isempty(opts.ElevationLimits)
    elevLim = [min(dem(:), [], 'omitnan'), max(dem(:), [], 'omitnan')];
else
    elevLim = opts.ElevationLimits;
end

demNorm    = (dem - elevLim(1)) / (elevLim(2) - elevLim(1));
demNorm    = max(0, min(1, demNorm));
cmap       = colormap(ax, opts.ColorMap);
nC         = size(cmap,1);
idxMat     = round(demNorm * (nC-1)) + 1;
idxMat(isnan(idxMat)) = 1;
terrainRGB = reshape(cmap(idxMat(:),:), [size(dem) 3]);

% Blend with hillshade
blend = 0.6;
for ch = 1:3
    layer          = terrainRGB(:,:,ch);
    layer          = layer * blend + hillshade * (1-blend);
    terrainRGB(:,:,ch) = layer;
end

% Set ocean pixels to a fixed blue
oceanMask = isnan(dem) | dem <= 0;
oceanBlue = permute([0.12 0.35 0.60], [1 3 2]);
for ch = 1:3
    layer = terrainRGB(:,:,ch);
    layer(oceanMask) = oceanBlue(ch);
    terrainRGB(:,:,ch) = layer;
end

imagesc(ax, xLim, yLim, terrainRGB);
set(ax, 'YDir', 'normal');
hold(ax, 'on');

% -------------------------------------------------------------------------
%  Overlay flood masks (semi-transparent)
% -------------------------------------------------------------------------
floodColors = [
    0.20 0.60 1.00;   % blue
    0.00 0.80 0.80;   % cyan
    0.60 0.20 1.00;   % purple
    1.00 0.40 0.00;   % orange
];

for k = 1:numel(opts.FloodMasks)
    mask = opts.FloodMasks{k};
    col  = floodColors(mod(k-1, size(floodColors,1))+1, :);
    % Build RGBA overlay
    overlay      = zeros([size(mask) 4]);
    overlay(:,:,1) = col(1);
    overlay(:,:,2) = col(2);
    overlay(:,:,3) = col(3);
    overlay(:,:,4) = 0.35 * double(mask);   % alpha channel
    image(ax, xLim, yLim, overlay(:,:,1:3), 'AlphaData', overlay(:,:,4));
end

% -------------------------------------------------------------------------
%  Plot coastlines
% -------------------------------------------------------------------------
lineStyles = {'-','--',':','-.'};
lineWidths = [2.0, 1.8, 1.6, 1.5];
coastColors = [
    1.00 0.20 0.00;   % red
    1.00 0.80 0.00;   % yellow
    0.20 1.00 0.20;   % green
    1.00 0.40 1.00;   % magenta
];

hLines = gobjects(numel(coastlines),1);
for k = 1:numel(coastlines)
    c   = coastlines{k};
    col = coastColors(mod(k-1, size(coastColors,1))+1, :);
    ls  = lineStyles{mod(k-1, numel(lineStyles))+1};
    lw  = lineWidths(mod(k-1, numel(lineWidths))+1);
    hLines(k) = plot(ax, c(:,2), c(:,1), ls, ...
        'Color', col, 'LineWidth', lw, ...
        'DisplayName', labels{k});
end

% -------------------------------------------------------------------------
%  Formatting
% -------------------------------------------------------------------------
xlabel(ax, xLabel);
ylabel(ax, yLabel);
title(ax, opts.Title, 'FontSize', 14, 'FontWeight', 'bold');

legend(ax, hLines, labels, 'Location', 'best', ...
    'TextColor', 'w', 'Color', [0.15 0.15 0.15], ...
    'EdgeColor', [0.5 0.5 0.5]);

% Colorbar for elevation
cb = colorbar(ax);
colormap(ax, opts.ColorMap);
clim(ax, elevLim);
cb.Label.String = 'Elevation (m above MSL)';

grid(ax, 'on');
ax.GridColor     = [1 1 1];
ax.GridAlpha     = 0.15;
ax.Box           = 'on';

axis(ax, 'tight');
end
