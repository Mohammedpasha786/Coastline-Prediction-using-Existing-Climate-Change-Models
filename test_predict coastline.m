%  Run from the project root:
%    runtests('tests/test_predictCoastline')

    properties (TestParameter)
        Rise = {0.5, 1.0, 2.0}
    end

    methods (TestMethodSetup)
        function addSrcPath(tc) %#ok<MANU>
            addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'src'));
        end
    end

    % ------------------------------------------------------------------ %
    %  Helpers                                                             %
    % ------------------------------------------------------------------ %
    methods (Access = private)
        function [dem, R] = makeSyntheticDEM(~, rows, cols, slope)
            % Flat inclined ramp: bottom row at -(rows*slope), top at 0
            % => elevation increases northward (classic beach gradient)
            if nargin < 4; slope = 0.05; end   % 5 cm/cell rise
            dem = repmat(linspace(-(rows*slope), 0, rows)', 1, cols);
            latLim = [25.0 25.5];
            lonLim = [-80.5 -80.0];
            R = georasterref('RasterSize',[rows cols], ...
                             'LatitudeLimits', latLim, ...
                             'LongitudeLimits',lonLim, ...
                             'ColumnsStartFrom','south');
        end
    end

    % ------------------------------------------------------------------ %
    %  Tests                                                               %
    % ------------------------------------------------------------------ %
    methods (Test)

        function testOutputSizes(tc)
            [dem, R] = tc.makeSyntheticDEM(200, 300);
            [coast, flood, stats] = predictCoastline(dem, R, 0.5);
            tc.verifySize(flood, [200 300], ...
                'Flood mask must match DEM size.');
            tc.verifyClass(coast, 'double', ...
                'Coastline must be a double array.');
            tc.verifySize(coast, [NaN 2], ...
                'Coastline must have 2 columns [lat lon].');
            tc.verifyTrue(isstruct(stats), 'stats must be a struct.');
        end

        function testNoFloodAtZeroRise(tc)
            [dem, R] = tc.makeSyntheticDEM(200, 300);
            [~, flood, stats] = predictCoastline(dem, R, 0.0);
            tc.verifyEqual(stats.floodedCells, 0, ...
                'Zero sea-level rise must produce zero flooded cells.');
            tc.verifyFalse(any(flood(:)), ...
                'Flood mask must be all-false at zero rise.');
        end

        function testFloodMonotonicity(tc)
            [dem, R] = tc.makeSyntheticDEM(200, 300);
            [~, ~, s1] = predictCoastline(dem, R, 0.5);
            [~, ~, s2] = predictCoastline(dem, R, 1.0);
            [~, ~, s3] = predictCoastline(dem, R, 2.0);
            tc.verifyGreaterThanOrEqual(s2.floodedAreaKm2, s1.floodedAreaKm2, ...
                'Larger SLR must flood at least as much area.');
            tc.verifyGreaterThanOrEqual(s3.floodedAreaKm2, s2.floodedAreaKm2, ...
                'Larger SLR must flood at least as much area.');
        end

        function testParametrizedRise(tc, Rise)
            [dem, R] = tc.makeSyntheticDEM(100, 150);
            [coast, flood, stats] = predictCoastline(dem, R, Rise);
            tc.verifyGreaterThan(stats.floodedAreaKm2, 0, ...
                sprintf('SLR = %.1f m should flood some area.', Rise));
            tc.verifyEqual(size(coast,2), 2, ...
                'Coastline array should have exactly 2 columns.');
        end

        function testStatsWithPopulation(tc)
            [dem, R] = tc.makeSyntheticDEM(100, 100);
            pop = ones(100,100) * 500;   % 500 persons/km² everywhere
            [~, ~, stats] = predictCoastline(dem, R, 1.0, ...
                'PopulationGrid', pop);
            tc.verifyGreaterThan(stats.displacedPopulation, 0, ...
                'Population displacement should be > 0 when pop grid is supplied.');
            tc.verifyFalse(isnan(stats.displacedPopulation), ...
                'displacedPopulation should not be NaN when pop grid is provided.');
        end

        function testDisconnectedFloodExclusion(tc)
            % Create a DEM with a low-lying inland basin surrounded by high ground.
            dem = ones(50, 50) * 10;       % high ground
            dem(20:30, 20:30) = -1;        % inland basin (would flood if unmasked)
            dem(1:5, :) = -2;              % coastal strip (connected to ocean)
            R = georasterref('RasterSize',[50 50], ...
                             'LatitudeLimits',[25 25.5], ...
                             'LongitudeLimits',[-80 -79.5], ...
                             'ColumnsStartFrom','south');
            [~, floodConn]    = predictCoastline(dem, R, 0.5, 'ConnectedOcean', true);
            [~, floodNoConn]  = predictCoastline(dem, R, 0.5, 'ConnectedOcean', false);

            % The inland basin should NOT be flooded when connectivity is enforced
            basinMask = false(50,50);
            basinMask(20:30,20:30) = true;
            tc.verifyFalse(any(floodConn(basinMask)), ...
                'Connected-ocean mode should not flood isolated inland basins.');
            tc.verifyTrue(any(floodNoConn(basinMask)), ...
                'Without connectivity, inland basin should appear flooded.');
        end

        function testInvalidInputs(tc)
            [dem, R] = tc.makeSyntheticDEM(50, 50);
            tc.verifyError(@() predictCoastline('notadouble', R, 1.0), ...
                'MATLAB:InputParser:ArgumentFailedValidation');
            tc.verifyError(@() predictCoastline(dem, R, [1 2]), ...
                'MATLAB:InputParser:ArgumentFailedValidation');
        end

    end
end
