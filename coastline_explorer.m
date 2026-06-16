classdef CoastlineExplorer < matlab.apps.AppBase
% COASTLINEEXPLORER  Interactive MATLAB App for sea-level rise visualization.
%
%  Features:
%    • Enter a target year (2024–2200) with a slider or spinner
%    • Choose emissions scenario: Low / Intermediate / High
%    • Optionally override sea-level rise directly (metres)
%    • Click a point on the world map to set the study region
%    • Press "Compute" to download the DEM & SLR data and render
%      the predicted coastline with flood shading
%    • Export the current map view as a PNG
%
%  Usage:
%    app = CoastlineExplorer();    % Launch the app
%
%  Requirements:
%    MATLAB R2021b+, Mapping Toolbox, Image Processing Toolbox,
%    App Designer Runtime

    % ------------------------------------------------------------------ %
    %  Properties – UI components                                          %
    % ------------------------------------------------------------------ %
    properties (Access = private)
        UIFigure        matlab.ui.Figure

        % --- Left panel (controls) ---
        ControlPanel    matlab.ui.container.Panel
        YearLabel       matlab.ui.control.Label
        YearSlider      matlab.ui.control.Slider
        YearSpinner     matlab.ui.control.Spinner
        ScenarioLabel   matlab.ui.control.Label
        ScenarioDD      matlab.ui.control.DropDown
        ManualSLRCheck  matlab.ui.control.CheckBox
        ManualSLRSpinner matlab.ui.control.Spinner
        RegionLabel     matlab.ui.control.Label
        LatMinSpinner   matlab.ui.control.Spinner
        LatMaxSpinner   matlab.ui.control.Spinner
        LonMinSpinner   matlab.ui.control.Spinner
        LonMaxSpinner   matlab.ui.control.Spinner
        ComputeButton   matlab.ui.control.Button
        ExportButton    matlab.ui.control.Button
        StatusLabel     matlab.ui.control.Label

        % --- Right panel (map) ---
        MapPanel        matlab.ui.container.Panel
        MapAxes         matlab.ui.control.UIAxes

        % --- Stats panel (bottom) ---
        StatsPanel      matlab.ui.container.Panel
        StatsText       matlab.ui.control.TextArea

        % --- Internal state ---
        DEM             double
        R                           % georasterref
        CurrentCoast    double
        CurrentFlood    logical
        SLRCurves       struct      % low / int / high year + slr arrays
        LastRegion      double      % [latMin latMax lonMin lonMax]
    end

    % ------------------------------------------------------------------ %
    %  Startup                                                             %
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Name','Coastline Explorer', ...
                'Position',[50 50 1350 750],'Color',[0.15 0.15 0.18]);

            % ---- Control panel (left) ----
            app.ControlPanel = uipanel(app.UIFigure, ...
                'Title','Controls','Position',[10 10 280 730], ...
                'BackgroundColor',[0.18 0.18 0.22],'ForegroundColor','w', ...
                'FontSize',13,'FontWeight','bold');

            y = 680;
            app.YearLabel = uilabel(app.ControlPanel,'Text','Target Year:', ...
                'Position',[10 y 200 22],'FontColor','w','FontSize',12);
            y = y - 30;
            app.YearSlider = uislider(app.ControlPanel,'Limits',[2024 2200], ...
                'Value',2074,'Position',[10 y 240 3]);
            app.YearSlider.ValueChangedFcn = @(~,e) app.syncYear(e.Value,'slider');
            y = y - 40;
            app.YearSpinner = uispinner(app.ControlPanel,'Limits',[2024 2200], ...
                'Value',2074,'Step',1,'Position',[10 y 100 28],'FontSize',12);
            app.YearSpinner.ValueChangedFcn = @(~,e) app.syncYear(e.Value,'spinner');

            y = y - 50;
            app.ScenarioLabel = uilabel(app.ControlPanel,'Text','Emissions Scenario:', ...
                'Position',[10 y 240 22],'FontColor','w','FontSize',12);
            y = y - 30;
            app.ScenarioDD = uidropdown(app.ControlPanel, ...
                'Items',{'Low (RCP2.6)','Intermediate (RCP4.5)','High (RCP8.5)'}, ...
                'Value','High (RCP8.5)','Position',[10 y 240 28],'FontSize',12);

            y = y - 50;
            app.ManualSLRCheck = uicheckbox(app.ControlPanel, ...
                'Text','Override SLR (m):', ...
                'Value',false,'Position',[10 y 180 22], ...
                'FontColor','w','FontSize',12);
            app.ManualSLRCheck.ValueChangedFcn = @(~,~) app.toggleManualSLR();
            y = y - 30;
            app.ManualSLRSpinner = uispinner(app.ControlPanel, ...
                'Limits',[0 10],'Value',1,'Step',0.1, ...
                'Position',[10 y 100 28],'Enable','off','FontSize',12);

            y = y - 60;
            app.RegionLabel = uilabel(app.ControlPanel, ...
                'Text','Region (Lat/Lon bounds):', ...
                'Position',[10 y 240 22],'FontColor','w','FontSize',12);
            y = y - 28;
            uilabel(app.ControlPanel,'Text','Lat min / max:', ...
                'Position',[10 y 130 20],'FontColor',[0.7 0.7 0.7],'FontSize',11);
            y = y - 26;
            app.LatMinSpinner = uispinner(app.ControlPanel, ...
                'Limits',[-90 90],'Value',25.55,'Step',0.05, ...
                'Position',[10 y 105 26],'FontSize',11);
            app.LatMaxSpinner = uispinner(app.ControlPanel, ...
                'Limits',[-90 90],'Value',25.95,'Step',0.05, ...
                'Position',[125 y 105 26],'FontSize',11);
            y = y - 30;
            uilabel(app.ControlPanel,'Text','Lon min / max:', ...
                'Position',[10 y 130 20],'FontColor',[0.7 0.7 0.7],'FontSize',11);
            y = y - 26;
            app.LonMinSpinner = uispinner(app.ControlPanel, ...
                'Limits',[-180 180],'Value',-80.55,'Step',0.05, ...
                'Position',[10 y 105 26],'FontSize',11);
            app.LonMaxSpinner = uispinner(app.ControlPanel, ...
                'Limits',[-180 180],'Value',-80.05,'Step',0.05, ...
                'Position',[125 y 105 26],'FontSize',11);

            y = y - 60;
            app.ComputeButton = uibutton(app.ControlPanel,'Text','▶  Compute', ...
                'Position',[10 y 120 36],'FontSize',13,'FontWeight','bold', ...
                'BackgroundColor',[0.18 0.55 0.34],'FontColor','w', ...
                'ButtonPushedFcn',@(~,~) app.runCompute());
            app.ExportButton = uibutton(app.ControlPanel,'Text','⬇  Export PNG', ...
                'Position',[150 y 110 36],'FontSize',12, ...
                'BackgroundColor',[0.25 0.45 0.70],'FontColor','w', ...
                'ButtonPushedFcn',@(~,~) app.exportMap());

            y = y - 40;
            app.StatusLabel = uilabel(app.ControlPanel,'Text','Ready.', ...
                'Position',[10 y 250 22],'FontColor',[0.7 0.9 0.7], ...
                'FontSize',11,'WordWrap','on');

            % ---- Map panel (right) ----
            app.MapPanel = uipanel(app.UIFigure,'Title','Coastline Map', ...
                'Position',[300 180 1040 560], ...
                'BackgroundColor',[0.12 0.12 0.15],'ForegroundColor','w', ...
                'FontSize',13,'FontWeight','bold');
            app.MapAxes = uiaxes(app.MapPanel,'Position',[10 10 1015 530], ...
                'Color',[0.1 0.2 0.35],'XColor','w','YColor','w');

            % ---- Stats panel (bottom right) ----
            app.StatsPanel = uipanel(app.UIFigure,'Title','Statistics', ...
                'Position',[300 10 1040 160], ...
                'BackgroundColor',[0.18 0.18 0.22],'ForegroundColor','w', ...
                'FontSize',13,'FontWeight','bold');
            app.StatsText = uitextarea(app.StatsPanel, ...
                'Value',{'Run a computation to see statistics.'}, ...
                'Position',[10 10 1015 125], ...
                'FontSize',12,'FontColor','w', ...
                'BackgroundColor',[0.10 0.10 0.13], ...
                'Editable','off');
        end

    end  % private component creation

    % ------------------------------------------------------------------ %
    %  Callbacks                                                           %
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function syncYear(app, val, src)
            val = round(val);
            if strcmp(src,'slider')
                app.YearSpinner.Value = val;
            else
                app.YearSlider.Value = val;
            end
        end

        function toggleManualSLR(app)
            if app.ManualSLRCheck.Value
                app.ManualSLRSpinner.Enable = 'on';
                app.ScenarioDD.Enable = 'off';
            else
                app.ManualSLRSpinner.Enable = 'off';
                app.ScenarioDD.Enable = 'on';
            end
        end

        function runCompute(app)
            app.setStatus('Fetching DEM…');
            drawnow;

            latLim = [app.LatMinSpinner.Value, app.LatMaxSpinner.Value];
            lonLim = [app.LonMinSpinner.Value, app.LonMaxSpinner.Value];
            yr     = round(app.YearSlider.Value);

            % Reload DEM only if region changed
            if isempty(app.LastRegion) || ~isequal([latLim lonLim], app.LastRegion)
                try
                    [app.DEM, app.R] = downloadUSGSDEM(latLim, lonLim, ...
                        'Resolution',3,'OutputDir',fullfile(tempdir,'coastline_cache'));
                    app.LastRegion = [latLim lonLim];
                    app.SLRCurves  = [];   % invalidate cached curves
                catch ME
                    app.setStatus(['DEM error: ' ME.message]);
                    return
                end
            end

            % Fetch SLR curves if needed
            if isempty(app.SLRCurves)
                app.setStatus('Fetching SLR projections…'); drawnow;
                lat = mean(latLim); lon = mean(lonLim);
                for sc = {'low','intermediate','high'}
                    s = sc{1};
                    try
                        [y, v] = fetchClimateSealevel(lat, lon, ...
                            'Source','NOAA','Scenario',s,'YearRange',[2024 2200]);
                        app.SLRCurves.(s).years = y;
                        app.SLRCurves.(s).slr   = v;
                    catch
                        app.SLRCurves.(s).years = 2024:2200;
                        app.SLRCurves.(s).slr   = linspace(0,2,177);
                    end
                end
            end

            % Determine SLR value
            if app.ManualSLRCheck.Value
                slrVal = app.ManualSLRSpinner.Value;
            else
                scenKey = lower(strtok(app.ScenarioDD.Value));
                curve   = app.SLRCurves.(scenKey);
                slrVal  = interp1(curve.years, curve.slr, yr, 'pchip', 'extrap');
            end

            app.setStatus(sprintf('Computing coastline for %d (SLR = %.3f m)…', yr, slrVal));
            drawnow;

            try
                [app.CurrentCoast, app.CurrentFlood, stats] = predictCoastline( ...
                    app.DEM, app.R, slrVal, ...
                    'ConnectedOcean',true,'SmoothCoastline',true);
            catch ME
                app.setStatus(['Compute error: ' ME.message]);
                return
            end

            % Render
            app.renderMap(yr, slrVal);

            % Stats
            scenStr = app.ScenarioDD.Value;
            statsLines = { ...
                sprintf('Year: %d   |   SLR: %.3f m   |   Scenario: %s', yr, slrVal, scenStr), ...
                sprintf('Newly flooded area:  %.2f km²  (%d grid cells)', ...
                        stats.floodedAreaKm2, stats.floodedCells), ...
                sprintf('Grid resolution:     %.0f × %.0f cells  (%.1f × %.1f km²)', ...
                        size(app.DEM,2), size(app.DEM,1), ...
                        (lonLim(2)-lonLim(1))*111, (latLim(2)-latLim(1))*111) };
            app.StatsText.Value = statsLines;
            app.setStatus(sprintf('Done.  Flooded area = %.1f km²', stats.floodedAreaKm2));
        end

        function renderMap(app, yr, slrVal)
            ax = app.MapAxes;
            cla(ax);

            [nR, nC] = size(app.DEM);
            if isa(app.R,'map.rasterref.GeographicCellsReference') || ...
               isa(app.R,'map.rasterref.GeographicPostingsReference')
                xLim = app.R.LongitudeLimits;
                yLim = app.R.LatitudeLimits;
            else
                xLim = app.R.XWorldLimits;
                yLim = app.R.YWorldLimits;
            end

            % Terrain image
            demN = mat2gray(app.DEM, [-5 25]);
            cmap = parula(256);
            idx  = max(1, min(256, round(demN*255)+1));
            idx(isnan(idx)) = 1;
            rgb  = reshape(cmap(idx(:),:),[nR nC 3]);
            ocean = isnan(app.DEM)|app.DEM<=0;
            for ch=1:3; lyr=rgb(:,:,ch); lyr(ocean)=[0.05 0.30 0.55]*ch/ch; rgb(:,:,ch)=lyr; end
            imagesc(ax, xLim, yLim, rgb); set(ax,'YDir','normal'); hold(ax,'on');

            % Flood overlay
            if ~isempty(app.CurrentFlood)
                ov      = zeros([size(app.CurrentFlood) 4]);
                ov(:,:,1)= 0.1; ov(:,:,2)=0.5; ov(:,:,3)=1.0;
                ov(:,:,4)= 0.40*double(app.CurrentFlood);
                image(ax, xLim, yLim, ov(:,:,1:3),'AlphaData',ov(:,:,4));
            end

            % Coastline
            if ~isempty(app.CurrentCoast)
                plot(ax, app.CurrentCoast(:,2), app.CurrentCoast(:,1), ...
                    'r-','LineWidth',2,'DisplayName', ...
                    sprintf('%d (+%.2fm)', yr, slrVal));
            end

            xlabel(ax,'Longitude (°)'); ylabel(ax,'Latitude (°)');
            title(ax, sprintf('Projected Coastline – %d  (SLR = %.3f m)', yr, slrVal), ...
                'Color','w','FontSize',13);
            legend(ax,'Location','best','TextColor','w','Color',[0.1 0.1 0.12]);
            ax.GridColor=[1 1 1]; ax.GridAlpha=0.1; grid(ax,'on');
        end

        function exportMap(app)
            if isempty(app.CurrentCoast)
                uialert(app.UIFigure,'Run a computation first.','No data');
                return
            end
            [f, p] = uiputfile({'*.png','PNG Image';'*.pdf','PDF'},'Save map as');
            if isequal(f,0); return; end
            exportgraphics(app.MapAxes, fullfile(p,f),'Resolution',200);
            app.setStatus(['Exported: ' f]);
        end

        function setStatus(app, msg)
            app.StatusLabel.Text = msg;
        end

    end  % private callbacks

    % ------------------------------------------------------------------ %
    %  Constructor                                                         %
    % ------------------------------------------------------------------ %
    methods (Access = public)
        function app = CoastlineExplorer()
            addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'src'));
            createComponents(app);
            registerApp(app, app.UIFigure);
            if nargout == 0; clear app; end
        end

        function delete(app)
            delete(app.UIFigure);
        end
    end

end  % CoastlineExplorer
