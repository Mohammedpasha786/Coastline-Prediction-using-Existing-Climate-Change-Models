function [newCoast, floodedArea, stats] = predictCoastline(dem, R, seaLevelRise, varargin)
% PREDICTCOASTLINE  Calculate a new coastline given a sea-level rise value.
%
%   [newCoast, floodedArea, stats] = predictCoastline(dem, R, seaLevelRise)
%
%   Inputs:
%     dem          – Digital Elevation Model matrix (metres above current MSL).
%                    NaN cells are treated as open ocean.
%     R            – Raster reference object (georasterref or map raster ref)
%                    matching the DEM grid.
%     seaLevelRise – Scalar sea-level rise in metres (positive = rise).
%
%   Optional Name-Value pairs:
%     'BaselineElevation'  – Current sea-level elevation in the DEM
%                            (default: 0 m, i.e. cells <= 0 are ocean).
%     'ConnectedOcean'     – true/false – only flood cells connected to the
%                            existing ocean mask (default: true).
%     'SmoothCoastline'    – true/false – apply light morphological smoothing
%                            to the output coastline (default: true).
%     'PopulationGrid'     – Optional population-density matrix (persons/km²)
%                            same size as dem; enables displacement stats.
%
%   Outputs:
%     newCoast    – Mx2 array of [lat, lon] (or [y, x]) coastline vertices.
%     floodedArea – Binary mask (same size as dem) of newly inundated cells.
%     stats       – Struct with summary statistics:
%                     .floodedCells        number of newly inundated cells
%                     .floodedAreaKm2      total flooded area in km²
%                     .displacedPopulation (if PopulationGrid supplied)
%
%   Example:
%     [dem, R] = readgeoraster('miami_dem.tif');
%     [coast, flood, s] = predictCoastline(dem, R, 1.5);
%     fprintf('Flooded area: %.1f km²\n', s.floodedAreaKm2);
%
%   See also: VISUALIZECOASTLINE, FETCHCLIMATESEALEVEL, GEORASTERREF

% -------------------------------------------------------------------------
%  Parse inputs
% -------------------------------------------------------------------------
p = inputParser();
p.addRequired('dem',           @(x) isnumeric(x) && ismatrix(x));
p.addRequired('R',             @(x) ~isempty(x));
p.addRequired('seaLevelRise',  @(x) isnumeric(x) && isscalar(x));
p.addParameter('BaselineElevation', 0,    @isnumeric);
p.addParameter('ConnectedOcean',    true, @islogical);
p.addParameter('SmoothCoastline',   true, @islogical);
p.addParameter('PopulationGrid',    [],   @isnumeric);
p.parse(dem, R, seaLevelRise, varargin{:});
opts = p.Results;

baseline    = opts.BaselineElevation;
popGrid     = opts.PopulationGrid;

% -------------------------------------------------------------------------
%  Build current and future ocean masks
% -------------------------------------------------------------------------
% Cells at or below baseline elevation (or NaN) are currently ocean
currentOcean = (dem <= baseline) | isnan(dem);

% After sea-level rise, cells at or below (baseline + rise) become ocean
futureThreshold = baseline + seaLevelRise;
futureOcean     = (dem <= futureThreshold) | isnan(dem);

% Cells that are newly flooded
rawFlooded = futureOcean & ~currentOcean;

% -------------------------------------------------------------------------
%  Connectivity filter – only flood cells reachable from existing ocean
% -------------------------------------------------------------------------
if opts.ConnectedOcean
    % Label connected components of the future-ocean mask
    CC = bwconncomp(futureOcean, 8);          % 8-connectivity
    % Find which components overlap with the current ocean
    currentOceanLabels = unique(labelmatrix(CC)(currentOcean));
    currentOceanLabels(currentOceanLabels == 0) = [];
    % Rebuild mask from only those components
    connectedFuture = false(size(dem));
    for k = currentOceanLabels(:)'
        connectedFuture(CC.PixelIdxList{k}) = true;
    end
    floodedArea = connectedFuture & ~currentOcean;
else
    floodedArea = rawFlooded;
end

% -------------------------------------------------------------------------
%  Extract new coastline (boundary of the future ocean mask)
% -------------------------------------------------------------------------
futureMask = currentOcean | floodedArea;

if opts.SmoothCoastline
    % Light morphological closing to remove single-pixel noise
    se         = strel('disk', 1);
    futureMask = imclose(futureMask, se);
end

% Trace the boundary of the combined ocean mask
B = bwboundaries(futureMask, 8, 'noholes');

% Convert pixel row/col to geographic coordinates
newCoast = cell2geographiccoords(B, R);

% -------------------------------------------------------------------------
%  Compute summary statistics
% -------------------------------------------------------------------------
stats.floodedCells = nnz(floodedArea);

% Cell area in km²
cellArea_m2  = areacell(dem, R);          % helper below
cellArea_km2 = cellArea_m2 / 1e6;
stats.floodedAreaKm2 = stats.floodedCells * mean(cellArea_km2(:), 'omitnan');

if ~isempty(popGrid) && isequal(size(popGrid), size(dem))
    % Population per cell = density * cell area (km²)
    popPerCell = popGrid .* cellArea_km2;
    stats.displacedPopulation = sum(popPerCell(floodedArea), 'omitnan');
else
    stats.displacedPopulation = NaN;
end

end  % predictCoastline


% =========================================================================
%  Local helpers
% =========================================================================

function coords = cell2geographiccoords(boundaries, R)
% Convert bwboundaries pixel lists to geographic [lat lon] or [y x] arrays.
% Concatenates all boundary segments, separated by NaN rows.

coords = [];
for k = 1:numel(boundaries)
    rc = boundaries{k};              % [row col]
    if isa(R,'map.rasterref.GeographicCellsReference') || ...
       isa(R,'map.rasterref.GeographicPostingsReference')
        [lat, lon] = R.intrinsicToGeographic(rc(:,2), rc(:,1));
        seg = [lat, lon];
    else
        [x, y] = R.intrinsicToWorld(rc(:,2), rc(:,1));
        seg = [y, x];
    end
    coords = [coords; seg; NaN NaN]; %#ok<AGROW>
end
end


function A = areacell(dem, R)
% Return a matrix of cell areas in m² for each DEM grid cell.
[nRows, nCols] = size(dem);
A = zeros(nRows, nCols);

if isa(R,'map.rasterref.GeographicCellsReference') || ...
   isa(R,'map.rasterref.GeographicPostingsReference')
    % Geographic raster – use areamat (Mapping Toolbox)
    latLim = R.LatitudeLimits;
    lonLim = R.LongitudeLimits;
    latVec = linspace(latLim(1), latLim(2), nRows+1);
    for r = 1:nRows
        % Area of one cell row (m²): Δlat × Δlon × R_earth² × cos(lat)
        latMid   = (latVec(r) + latVec(r+1)) / 2;
        dlat_m   = deg2rad(R.CellExtentInLatitude)  * 6371000;
        dlon_m   = deg2rad(R.CellExtentInLongitude) * 6371000 * cosd(latMid);
        A(r,:)   = dlat_m * dlon_m;
    end
else
    % Planar raster – constant cell size
    dx = R.CellExtentInWorldX;
    dy = R.CellExtentInWorldY;
    A(:) = dx * dy;
end
end
