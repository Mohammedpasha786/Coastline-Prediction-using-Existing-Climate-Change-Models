%% Coastline Prediction – Miami, FL  (100-year projection)
%
%  This script demonstrates the full pipeline:
%    1.  Download a 1 arc-second DEM from the USGS National Map.
%    2.  Fetch NOAA projected sea-level rise for three emissions scenarios.
%    3.  Compute new coastline boundaries for 2050, 2075, and 2124.
%    4.  Visualize the results on a terrain map with flood overlays.
%    5.  Generate a summary statistics table.
%
%  Toolboxes required: Mapping Toolbox, Image Processing Toolbox
%
%  Note: The first run downloads ~50 MB of data; subsequent runs use cache.

clearvars; close all; clc;

% Add project source to path
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'src'));

%% ─────────────────────────────────────────────────────────────────────────
%  1.  Study area and DEM
% ─────────────────────────────────────────────────────────────────────────
LAT_LIM = [25.55  25.95];   % Southern Miami-Dade County
LON_LIM = [-80.55 -80.05];  % Biscayne Bay to Miami Beach

fprintf('=== Downloading DEM ===\n');
[dem, R] = downloadUSGSDEM(LAT_LIM, LON_LIM, ...
    'Resolution',  3, ...                   % 1 arc-second  (~30 m)
    'OutputDir',   fullfile(tempdir, 'coastline_cache'), ...
    'ForceRefresh', false);

% Quick sanity plot
figure('Name','Raw DEM');
imagescm(dem, R);
colorbar;
title('Miami DEM – elevation (m above MSL)');
colormap('terrain');

%% ─────────────────────────────────────────────────────────────────────────
%  2.  Fetch sea-level projections (three scenarios)
% ─────────────────────────────────────────────────────────────────────────
LAT_QUERY = mean(LAT_LIM);
LON_QUERY = mean(LON_LIM);

fprintf('\n=== Fetching SLR projections ===\n');

[yrsLow,  slrLow,  metaLow]  = fetchClimateSealevel(LAT_QUERY, LON_QUERY, ...
    'Source','NOAA','Scenario','low',         'YearRange',[2024 2124]);
[yrsInt,  slrInt,  metaInt]  = fetchClimateSealevel(LAT_QUERY, LON_QUERY, ...
    'Source','NOAA','Scenario','intermediate','YearRange',[2024 2124]);
[yrsHigh, slrHigh, metaHigh] = fetchClimateSealevel(LAT_QUERY, LON_QUERY, ...
    'Source','NOAA','Scenario','high',        'YearRange',[2024 2124]);

% Plot SLR curves
figure('Name','SLR Projections','Position',[100 100 800 400]);
hold on;
fill([yrsLow fliplr(yrsHigh)], [slrLow fliplr(slrHigh)], ...
     [0.7 0.85 1.0], 'EdgeColor','none','FaceAlpha',0.4);
plot(yrsLow,  slrLow,  'b-',  'LineWidth',1.5, 'DisplayName','Low (RCP2.6)');
plot(yrsInt,  slrInt,  'g-',  'LineWidth',1.5, 'DisplayName','Intermediate (RCP4.5)');
plot(yrsHigh, slrHigh, 'r-',  'LineWidth',1.5, 'DisplayName','High (RCP8.5)');
legend('Location','northwest');
xlabel('Year');  ylabel('Sea-level rise (m above 2000 baseline)');
title(sprintf('Projected SLR near %s', metaLow.station));
grid on;  box on;

%% ─────────────────────────────────────────────────────────────────────────
%  3.  Predict coastlines for target years
% ─────────────────────────────────────────────────────────────────────────
TARGET_YEARS  = [2050, 2075, 2124];
SCENARIO      = 'high';        % Use the high-emissions scenario for planning

% Interpolate SLR to target years
slrAtYear = interp1(yrsHigh, slrHigh, TARGET_YEARS, 'pchip');

fprintf('\n=== Computing coastlines ===\n');
fprintf('  Scenario: %s\n', SCENARIO);
fprintf('  %-8s  %-15s\n', 'Year', 'SLR (m)');
fprintf('  %-8s  %-15s\n', '----', '-------');

coastlines  = cell(numel(TARGET_YEARS), 1);
floodMasks  = cell(numel(TARGET_YEARS), 1);
statsAll    = cell(numel(TARGET_YEARS), 1);

for k = 1:numel(TARGET_YEARS)
    yr  = TARGET_YEARS(k);
    slr = slrAtYear(k);
    fprintf('  %-8d  %.3f m\n', yr, slr);

    [coastlines{k}, floodMasks{k}, statsAll{k}] = predictCoastline( ...
        dem, R, slr, ...
        'BaselineElevation', 0, ...
        'ConnectedOcean',    true, ...
        'SmoothCoastline',   true);
end

%% ─────────────────────────────────────────────────────────────────────────
%  4.  Visualize
% ─────────────────────────────────────────────────────────────────────────
coastLabels = arrayfun(@(k) sprintf('%d (+%.2f m)', TARGET_YEARS(k), slrAtYear(k)), ...
                       1:numel(TARGET_YEARS), 'UniformOutput', false);

fig = visualizeCoastline(dem, R, coastlines, coastLabels, ...
    'FloodMasks',   floodMasks, ...
    'Title',        sprintf('Miami, FL – Projected Coastlines (%s scenario)', upper(SCENARIO)), ...
    'ColorMap',     'terrain', ...
    'ElevationLimits', [-5 30], ...
    'FigureSize',   [1400 800]);

% Save figure
outDir = fullfile(fileparts(mfilename('fullpath')), '..', 'output');
if ~isfolder(outDir); mkdir(outDir); end
exportgraphics(fig, fullfile(outDir, 'miami_coastline_projection.png'), ...
               'Resolution', 200);
fprintf('\nFigure saved → output/miami_coastline_projection.png\n');

%% ─────────────────────────────────────────────────────────────────────────
%  5.  Summary statistics table
% ─────────────────────────────────────────────────────────────────────────
fprintf('\n=== Inundation Summary (%s scenario) ===\n', upper(SCENARIO));
fprintf('  %-6s  %-10s  %-16s\n', 'Year', 'SLR (m)', 'Flooded Area (km²)');
fprintf('  %-6s  %-10s  %-16s\n', '----', '-------', '------------------');
for k = 1:numel(TARGET_YEARS)
    fprintf('  %-6d  %-10.3f  %-16.1f\n', ...
        TARGET_YEARS(k), slrAtYear(k), statsAll{k}.floodedAreaKm2);
end
fprintf('\n');

%% ─────────────────────────────────────────────────────────────────────────
%  6.  Animated GIF (optional)
% ─────────────────────────────────────────────────────────────────────────
CREATE_GIF = false;   % Set to true to export an animated GIF (~60 s)

if CREATE_GIF
    gifPath = fullfile(outDir, 'miami_coastline_animation.gif');
    allYears = 2024:5:2124;
    allSLR   = interp1(yrsHigh, slrHigh, allYears, 'pchip');

    figAnim = figure('Visible','off','Position',[0 0 900 600]);

    for k = 1:numel(allYears)
        [cst, fld] = predictCoastline(dem, R, allSLR(k), ...
            'ConnectedOcean',true,'SmoothCoastline',true);
        clf(figAnim);
        visualizeCoastline(dem, R, {cst}, {sprintf('%d (+%.2fm)', allYears(k), allSLR(k))}, ...
            'FloodMasks',{fld}, ...
            'Title',     sprintf('Miami SLR – %s scenario', upper(SCENARIO)), ...
            'ElevationLimits',[-5 30]);

        frame = getframe(figAnim);
        im    = frame2im(frame);
        [imInd, cm] = rgb2ind(im, 256);
        if k == 1
            imwrite(imInd, cm, gifPath, 'gif', 'LoopCount',Inf,'DelayTime',0.2);
        else
            imwrite(imInd, cm, gifPath, 'gif', 'WriteMode','append','DelayTime',0.2);
        end
    end
    fprintf('Animated GIF saved → %s\n', gifPath);
    close(figAnim);
end

fprintf('Done.\n');
