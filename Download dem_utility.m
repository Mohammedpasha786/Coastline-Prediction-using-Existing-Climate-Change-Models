function [dem, R] = downloadUSGSDEM(latLim, lonLim, varargin)
% DOWNLOADUSGSDEM  Download a DEM tile from the USGS National Map (3DEP).
%
%   [dem, R] = downloadUSGSDEM(latLim, lonLim)
%   [dem, R] = downloadUSGSDEM(latLim, lonLim, Name, Value, ...)
%
%   Fetches the highest-available 3DEP resolution elevation data for a
%   bounding box from the USGS National Map REST service and returns it as
%   a geographically referenced matrix.
%
%   Inputs:
%     latLim – [south north] latitude limits (decimal degrees).
%     lonLim – [west  east]  longitude limits (decimal degrees).
%
%   Optional Name-Value pairs:
%     'Resolution'  – Target grid resolution in arc-seconds:
%                       1  (≈30 m, 1/3 arc-second, best available)
%                       3  (≈90 m, 1 arc-second)        [default]
%                       9  (≈270 m, 1/3 arc-minute)
%     'Format'      – Output format: 'GeoTIFF' (default) | 'IMG' | 'GridFloat'
%     'OutputDir'   – Local directory to save the raw tile (default: tempdir).
%     'ForceRefresh'– true to re-download even if a local file exists.
%
%   Outputs:
%     dem – Matrix of elevation values in metres (NaN = water / no data).
%     R   – Geographic raster reference object (GeographicCellsReference).
%
%   Notes:
%     - Requires MATLAB Mapping Toolbox and an active internet connection.
%     - For very large bounding boxes the download may take several minutes.
%     - Non-US regions should use the Copernicus GLO-30 DEM or SRTM instead
%       (see downloadSRTM.m for an alternative).
%
%   Example:
%     % Download 1 arc-second DEM for Miami, FL
%     [dem, R] = downloadUSGSDEM([25.5 26.2], [-80.6 -80.0], ...
%                                'Resolution', 1);
%     figure; imagesc(dem); colorbar; title('Miami DEM (m)');
%
%   References:
%     USGS National Map:  https://apps.nationalmap.gov/
%     3DEP REST endpoint: https://elevation.nationalmap.gov/arcgis/rest/services/

% -------------------------------------------------------------------------
%  Input parsing
% -------------------------------------------------------------------------
p = inputParser();
p.addRequired('latLim', @(x) isnumeric(x) && numel(x)==2 && x(1)<x(2));
p.addRequired('lonLim', @(x) isnumeric(x) && numel(x)==2 && x(1)<x(2));
p.addParameter('Resolution',   3,        @(x) ismember(x,[1 3 9]));
p.addParameter('Format',       'GeoTIFF',@ischar);
p.addParameter('OutputDir',    tempdir,  @ischar);
p.addParameter('ForceRefresh', false,    @islogical);
p.parse(latLim, lonLim, varargin{:});
opts = p.Results;

% -------------------------------------------------------------------------
%  Build request URL
% -------------------------------------------------------------------------
% USGS 3DEP Elevation Image Server (Export endpoint)
BASE = ['https://elevation.nationalmap.gov/arcgis/rest/services/' ...
        '3DEPElevation/ImageServer/exportImage'];

resMap = struct('r1','1/3 arc-second','r3','1 arc-second','r9','1/3 arc-minute');
resKey = sprintf('r%d', opts.Resolution);
fprintf('[downloadUSGSDEM] Requesting %s DEM for [%.3f–%.3f N, %.3f–%.3f E]...\n', ...
        resMap.(resKey), latLim(1), latLim(2), lonLim(1), lonLim(2));

% Number of pixels (limit to ~4000 each dimension for memory safety)
maxPix = 4000;
degW   = lonLim(2) - lonLim(1);
degH   = latLim(2) - latLim(1);
pxW    = min(maxPix, round(degW * 3600 / opts.Resolution));
pxH    = min(maxPix, round(degH * 3600 / opts.Resolution));

bbox   = sprintf('%.6f,%.6f,%.6f,%.6f', lonLim(1), latLim(1), lonLim(2), latLim(2));
params = { ...
    'bbox',         bbox; ...
    'bboxSR',       '4326'; ...
    'size',         sprintf('%d,%d', pxW, pxH); ...
    'imageSR',      '4326'; ...
    'format',       lower(opts.Format); ...
    'pixelType',    'F32'; ...
    'noData',       '-3.4028235e+38'; ...
    'interpolation','RSP_BilinearInterpolation'; ...
    'f',            'image' };

% Assemble query string
qs = strjoin(arrayfun(@(k) [params{k,1} '=' urlencode(params{k,2})], ...
                       (1:size(params,1))', 'UniformOutput',false), '&');
url = [BASE '?' qs];

% -------------------------------------------------------------------------
%  Download
% -------------------------------------------------------------------------
outExt = struct('geotiff','.tif','img','.img','gridfloat','.flt');
ext    = outExt.(lower(opts.Format));
fname  = sprintf('usgs_dem_%.3f_%.3f_%.3f_%.3f%s', ...
                 latLim(1), lonLim(1), latLim(2), lonLim(2), ext);
fpath  = fullfile(opts.OutputDir, fname);

if ~opts.ForceRefresh && isfile(fpath)
    fprintf('[downloadUSGSDEM] Found cached file: %s\n', fpath);
else
    try
        fprintf('[downloadUSGSDEM] Downloading to %s...\n', fpath);
        websave(fpath, url);
        fprintf('[downloadUSGSDEM] Download complete (%.1f MB).\n', ...
                dir(fpath).bytes / 1e6);
    catch ME
        error('downloadUSGSDEM:downloadFailed', ...
              'Download failed: %s\nURL: %s', ME.message, url);
    end
end

% -------------------------------------------------------------------------
%  Read into MATLAB
% -------------------------------------------------------------------------
[dem, R] = readgeoraster(fpath);
dem      = double(dem);

% Replace no-data fill values and large negatives with NaN
dem(dem < -1e10) = NaN;
dem(dem < -500)  = NaN;   % below −500 m is unphysical for coastal areas

fprintf('[downloadUSGSDEM] Loaded %d × %d grid (resolution ≈ %.1f m/cell).\n', ...
        size(dem,1), size(dem,2), mean(R.CellExtentInLatitude * 111320));
end
