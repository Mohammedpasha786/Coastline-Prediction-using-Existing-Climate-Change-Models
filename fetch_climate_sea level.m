function [years, sealevel_m, metadata] = fetchClimateSealevel(lat, lon, varargin)
% FETCHCLIMATESEALEVEL  Retrieve projected sea-level rise from a climate server.
%
%   [years, sealevel_m, metadata] = fetchClimateSealevel(lat, lon)
%   [years, sealevel_m, metadata] = fetchClimateSealevel(lat, lon, Name, Value)
%
%   Queries NOAA's CO-OPS (Tides & Currents) or Copernicus CDS for
%   sea-level projections at the supplied geographic point.
%
%   Inputs:
%     lat  – Latitude  of the point of interest (decimal degrees).
%     lon  – Longitude of the point of interest (decimal degrees).
%
%   Optional Name-Value pairs:
%     'Source'       – Data source string: 'NOAA' (default) | 'Copernicus'.
%     'Scenario'     – Emissions scenario: 'low' | 'intermediate' (default)
%                      | 'high'.  Maps to RCP2.6, RCP4.5, RCP8.5.
%     'YearRange'    – [startYear endYear] – default [2020 2150].
%     'APIKey'       – API key / UID:key for Copernicus CDS (not needed for
%                      NOAA public endpoints).
%     'CacheDir'     – Directory to cache downloaded data (default: tempdir).
%     'ForceRefresh' – true to bypass cache (default: false).
%
%   Outputs:
%     years      – Row vector of years.
%     sealevel_m – Row vector of projected sea-level rise (m) relative to
%                  the 2000 baseline, median estimate.
%     metadata   – Struct with source, scenario, station info, and units.
%
%   Notes:
%     The function finds the nearest NOAA tide gauge station (or Copernicus
%     grid cell) to the requested lat/lon and downloads projected SLR.
%     Results are interpolated to annual resolution.
%
%   Example:
%     % Sea-level projection for Miami, FL (high-emissions scenario)
%     [yrs, slr, meta] = fetchClimateSealevel(25.77, -80.19, ...
%         'Source', 'NOAA', 'Scenario', 'high', 'YearRange', [2024 2124]);
%     plot(yrs, slr);
%     xlabel('Year'); ylabel('SLR (m)');
%
%   See also: PREDICTCOASTLINE, VISUALIZECOASTLINE

% -------------------------------------------------------------------------
%  Parse inputs
% -------------------------------------------------------------------------
p = inputParser();
p.addRequired('lat',  @(x) isnumeric(x) && isscalar(x));
p.addRequired('lon',  @(x) isnumeric(x) && isscalar(x));
p.addParameter('Source',       'NOAA',        @ischar);
p.addParameter('Scenario',     'intermediate',@ischar);
p.addParameter('YearRange',    [2020 2150],   @(x) isnumeric(x) && numel(x)==2);
p.addParameter('APIKey',       '',            @ischar);
p.addParameter('CacheDir',     tempdir,       @ischar);
p.addParameter('ForceRefresh', false,         @islogical);
p.parse(lat, lon, varargin{:});
opts = p.Results;

source   = upper(opts.Source);
scenario = lower(opts.Scenario);
yr0      = opts.YearRange(1);
yr1      = opts.YearRange(2);

% -------------------------------------------------------------------------
%  Route to appropriate data-fetching backend
% -------------------------------------------------------------------------
switch source
    case 'NOAA'
        [years, sealevel_m, metadata] = fetchNOAA(lat, lon, scenario, ...
                                                   yr0, yr1, opts);
    case 'COPERNICUS'
        [years, sealevel_m, metadata] = fetchCopernicus(lat, lon, scenario, ...
                                                        yr0, yr1, opts);
    otherwise
        error('fetchClimateSealevel:unknownSource', ...
              'Unknown Source "%s". Use ''NOAA'' or ''Copernicus''.', source);
end
end


% =========================================================================
%  NOAA backend
% =========================================================================
function [years, slr, meta] = fetchNOAA(lat, lon, scenario, yr0, yr1, opts)
% Uses NOAA's Sea Level Trends API (tidesandcurrents.noaa.gov)
% Projections endpoint: https://api.tidesandcurrents.noaa.gov/dpapi/prod/webapi/

BASE_URL   = 'https://api.tidesandcurrents.noaa.gov/dpapi/prod/webapi/';
STATION_URL = [BASE_URL 'stations.json'];

% ---------- find nearest NOAA tide-gauge station ----------
cacheFile = fullfile(opts.CacheDir, 'noaa_stations.mat');
if ~opts.ForceRefresh && isfile(cacheFile)
    load(cacheFile, 'stationData');
else
    try
        resp        = webread(STATION_URL);
        stationData = resp.stations;
        save(cacheFile, 'stationData');
    catch ME
        error('fetchClimateSealevel:noaaStationFetch', ...
              'Could not fetch NOAA station list: %s', ME.message);
    end
end

% Find nearest by great-circle distance
stLat = [stationData.lat];
stLon = [stationData.lng];
dist  = greatCircleDist(lat, lon, stLat, stLon);
[~, idx] = min(dist);
station  = stationData(idx);

fprintf('[fetchClimateSealevel] Nearest NOAA station: %s (%.2f km away)\n', ...
    station.name, dist(idx));

% ---------- fetch sea-level projections ----------
scenMap = struct('low','low','intermediate','int','high','high');
scenKey = scenMap.(scenario);

projURL = sprintf('%ssltrends/slr.json?stationId=%s&scenario=%s', ...
                  BASE_URL, station.id, scenKey);

cacheProj = fullfile(opts.CacheDir, ...
    sprintf('noaa_slr_%s_%s.mat', station.id, scenKey));

if ~opts.ForceRefresh && isfile(cacheProj)
    load(cacheProj, 'projData');
else
    try
        resp     = webread(projURL);
        projData = resp;
        save(cacheProj, 'projData');
    catch ME
        warning('fetchClimateSealevel:noaaProjFetch', ...
                'Could not fetch NOAA projections: %s\nUsing synthetic data.', ...
                ME.message);
        projData = [];
    end
end

if ~isempty(projData) && isfield(projData, 'SLRProjections')
    rawYears = [projData.SLRProjections.year];
    rawSLR   = [projData.SLRProjections.median] / 100;  % cm → m
else
    % ---------- synthetic fallback (IPCC AR6 approximate curves) ----------
    warning('fetchClimateSealevel:synthetic', ...
            'Using synthetic AR6-approximate SLR curve (no live data retrieved).');
    rawYears = 2020:10:2150;
    switch scenario
        case 'low'
            rawSLR = [0 0.06 0.12 0.18 0.24 0.30 0.35 0.38 0.41 0.43 0.46 0.48 0.50 0.52];
        case 'intermediate'
            rawSLR = [0 0.10 0.21 0.34 0.49 0.65 0.82 1.00 1.19 1.40 1.60 1.82 2.05 2.30];
        otherwise  % high
            rawSLR = [0 0.13 0.28 0.46 0.68 0.94 1.25 1.60 2.00 2.45 2.95 3.50 4.10 4.75];
    end
    rawYears = rawYears(1:numel(rawSLR));
end

% Interpolate to annual resolution and clip to requested range
allYears   = rawYears(1):rawYears(end);
allSLR     = interp1(rawYears, rawSLR, allYears, 'pchip');
mask       = allYears >= yr0 & allYears <= yr1;
years      = allYears(mask);
slr        = allSLR(mask);

meta.source    = 'NOAA CO-OPS';
meta.station   = station.name;
meta.stationId = station.id;
meta.scenario  = scenario;
meta.units     = 'metres above 2000 baseline';
meta.lat       = lat;
meta.lon       = lon;
end


% =========================================================================
%  Copernicus CDS backend
% =========================================================================
function [years, slr, meta] = fetchCopernicus(lat, lon, scenario, yr0, yr1, opts)
% Downloads CMIP6 sea-level projections from Copernicus Climate Data Store.
% Requires a CDS API key stored in opts.APIKey or the ~/.cdsapirc file.

fprintf('[fetchClimateSealevel] Querying Copernicus CDS for (%.2f, %.2f)...\n', ...
        lat, lon);

% Map friendly scenario names to CDS dataset identifiers
scenMap = struct('low','ssp126','intermediate','ssp245','high','ssp585');
if ~isfield(scenMap, scenario)
    error('fetchClimateSealevel:badScenario', ...
          'Scenario must be low/intermediate/high for Copernicus source.');
end
ssp = scenMap.(scenario);

% Build CDS API request (Python cdsapi would normally do this;
% here we use MATLAB's webwrite / RESTful interface as an alternative)
CDS_URL = 'https://cds.climate.copernicus.eu/api/v2/resources/';
dataset = 'sea-level-rise';
request = struct( ...
    'variable',     'total_sea_level_change', ...
    'experiment',   ssp, ...
    'format',       'netcdf', ...
    'area',         [lat+1, lon-1, lat-1, lon+1]);  % bounding box

cacheFile = fullfile(opts.CacheDir, ...
    sprintf('cds_slr_%.2f_%.2f_%s.nc', lat, lon, ssp));

if ~opts.ForceRefresh && isfile(cacheFile)
    fprintf('[fetchClimateSealevel] Loading cached Copernicus data...\n');
else
    if isempty(opts.APIKey)
        warning('fetchClimateSealevel:noAPIKey', ...
                'No Copernicus CDS API key supplied. Using synthetic data.');
        [years, slr, meta] = syntheticFallback(lat, lon, scenario, yr0, yr1);
        return
    end
    try
        opts2 = weboptions('HeaderFields', ...
            {'Authorization', ['Bearer ' opts.APIKey]});
        webwrite([CDS_URL dataset], request, opts2);
    catch ME
        warning('fetchClimateSealevel:cdsFetch', ...
                'Copernicus CDS fetch failed: %s\nUsing synthetic data.', ME.message);
        [years, slr, meta] = syntheticFallback(lat, lon, scenario, yr0, yr1);
        return
    end
end

% Read NetCDF
ncInfo   = ncinfo(cacheFile);
timeVar  = ncread(cacheFile, 'time');
slrVar   = ncread(cacheFile, 'sea_level_change');   % [lon lat time]
latVec   = ncread(cacheFile, 'latitude');
lonVec   = ncread(cacheFile, 'longitude');

% Find nearest grid cell
[~,iLat] = min(abs(latVec - lat));
[~,iLon] = min(abs(lonVec - lon));
slrPoint = squeeze(slrVar(iLon, iLat, :)) / 1000;  % mm → m

% Convert CF time to calendar years (assuming 'days since 1850-01-01')
baseYear = 1850;
cdYears  = baseYear + timeVar/365.25;
allYears = round(cdYears)';
mask     = allYears >= yr0 & allYears <= yr1;
years    = allYears(mask)';
slr      = slrPoint(mask)';

meta.source   = 'Copernicus CDS (CMIP6)';
meta.scenario = ssp;
meta.units    = 'metres above 2000 baseline';
meta.lat      = lat;
meta.lon      = lon;
end


% =========================================================================
%  Synthetic fallback
% =========================================================================
function [years, slr, meta] = syntheticFallback(lat, lon, scenario, yr0, yr1)
warning('fetchClimateSealevel:synthetic', ...
        'No live data available – using IPCC AR6 synthetic SLR curve.');
rawYears = 2020:10:2150;
switch scenario
    case 'low'
        rawSLR = [0 0.06 0.12 0.18 0.24 0.30 0.35 0.38 0.41 0.43 0.46 0.48 0.50 0.52];
    case 'intermediate'
        rawSLR = [0 0.10 0.21 0.34 0.49 0.65 0.82 1.00 1.19 1.40 1.60 1.82 2.05 2.30];
    otherwise
        rawSLR = [0 0.13 0.28 0.46 0.68 0.94 1.25 1.60 2.00 2.45 2.95 3.50 4.10 4.75];
end
rawYears = rawYears(1:numel(rawSLR));
allYears = rawYears(1):rawYears(end);
allSLR   = interp1(rawYears, rawSLR, allYears, 'pchip');
mask     = allYears >= yr0 & allYears <= yr1;
years    = allYears(mask);
slr      = allSLR(mask);
meta.source   = 'Synthetic (IPCC AR6 approximate)';
meta.scenario = scenario;
meta.units    = 'metres above 2000 baseline';
meta.lat      = lat;
meta.lon      = lon;
end


% =========================================================================
%  Great-circle distance (km)
% =========================================================================
function d = greatCircleDist(lat1, lon1, lat2, lon2)
R      = 6371;
dlat   = deg2rad(lat2 - lat1);
dlon   = deg2rad(lon2 - lon1);
a      = sin(dlat/2).^2 + cosd(lat1)*cosd(lat2).*sin(dlon/2).^2;
d      = 2 * R * asin(sqrt(a));
end
