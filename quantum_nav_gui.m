function quantum_nav_gui()
% QUANTUM_NAV_GUI  Interactive GUI for the simplified quantum navigation model.
%   Runs the same 5-phase pipeline as main.m, with editable parameters,
%   a simulation mode and a real-data mode (CSV track).
%
%   Requires MATLAB R2020a or newer.
%   Files needed in the same folder: setup_params, true_motion,
%   quantum_sensor, estimate_nav, analyze_perf, load_real_data,
%   make_demo_real_data.
%
%   Usage:  quantum_nav_gui

%% ---------------- Check required files ----------------
req = {'setup_params', 'true_motion', 'quantum_sensor', 'estimate_nav', ...
       'analyze_perf', 'load_real_data', 'make_demo_real_data'};
for ii = 1:numel(req)
    if exist(req{ii}, 'file') ~= 2
        error('quantum_nav_gui:missingFile', 'Missing file: %s.m', req{ii});
    end
end

%% ---------------- Shared state ----------------
d        = setup_params();    % Phase 1 defaults
R        = struct();          % last results
dataFile = '';                % selected real-data file

%% ---------------- Figure and layout ----------------
fig = uifigure('Name', 'Quantum Navigation & Positioning Analysis', ...
               'Position', [40 40 1300 780]);
rootGrid = uigridlayout(fig, [1 2]);
rootGrid.ColumnWidth = {360, '1x'};
rootGrid.RowHeight   = {'1x'};

ctrlPanel = uipanel(rootGrid, 'Title', 'Controls');
ctrlPanel.Layout.Row = 1;  ctrlPanel.Layout.Column = 1;

lg = uigridlayout(ctrlPanel, [21 2]);
lg.ColumnWidth = {175, '1x'};
lg.RowHeight   = [repmat({26}, 1, 20), {90}];
lg.Scrollable  = 'on';

%% ---------------- Parameter controls ----------------
addLabel(1, 'Data source');
srcDD = addDD(1, {'Simulation', 'Real data (CSV)'}, 'Simulation');
srcDD.ValueChangedFcn = @onSource;

addLabel(2, 'Duration [s]');             durEdit   = addNum(2,  d.sim.t_total, [1 3600]);
addLabel(3, 'Sample interval dt [s]');   dtEdit    = addNum(3,  d.sim.dt, [1e-3 1]);
addLabel(4, 'Accel profile');            accDD     = addDD(4, {'sinusoidal', 'constant', 'piecewise'}, d.vehicle.accel.type);
addLabel(5, 'Accel amplitude ax [m/s^2]'); axEdit  = addNum(5,  d.vehicle.accel.amplitude(1), [-5 5]);
addLabel(6, 'Accel amplitude ay [m/s^2]'); ayEdit  = addNum(6,  d.vehicle.accel.amplitude(2), [-5 5]);
addLabel(7, 'Interrogation T [ms]');     TEdit     = addNum(7,  d.sensor.T_int*1e3, [0.01 10]);
addLabel(8, 'Atoms per shot');           atomEdit  = addNum(8,  d.sensor.N_atoms, [1 1e12]);
addLabel(9, 'Phase noise [rad]');        noiseEdit = addNum(9,  d.sensor.meas_noise, [0 1]);
addLabel(10, 'Sensor bias [m/s^2]');     biasEdit  = addNum(10, d.sensor.bias, [-1 1]);
addLabel(11, 'Heading noise [deg]');     hdgEdit   = addNum(11, 0.5, [0 90]);
addLabel(12, 'Bias compensation [m/s^2]'); biasCompEdit = addNum(12, 0, [-1 1]);
addLabel(13, 'Integration');             integDD   = addDD(13, {'trapezoid', 'euler'}, 'trapezoid');

%% ---------------- Real-data controls ----------------
loadBtn = uibutton(lg, 'push', 'Text', 'Load CSV...', 'ButtonPushedFcn', @onLoad);
loadBtn.Layout.Row = 14;  loadBtn.Layout.Column = 1;
demoBtn = uibutton(lg, 'push', 'Text', 'Create demo file', 'ButtonPushedFcn', @onDemo);
demoBtn.Layout.Row = 14;  demoBtn.Layout.Column = 2;

fileLbl = uilabel(lg, 'Text', 'No file selected', 'WordWrap', 'on');
fileLbl.Layout.Row = 15;  fileLbl.Layout.Column = [1 2];

addLabel(16, 'Smoothing window [s]');
smoothEdit = addNum(16, 2, [0.1 30]);

autoCB = uicheckbox(lg, 'Text', 'Auto-adapt T to data range', 'Value', true);
autoCB.Layout.Row = 17;  autoCB.Layout.Column = [1 2];

sweepCB = uicheckbox(lg, 'Text', 'Run sensitivity sweeps (simulation only)', 'Value', false);
sweepCB.Layout.Row = 18;  sweepCB.Layout.Column = [1 2];

%% ---------------- Action buttons and status ----------------
runBtn = uibutton(lg, 'push', 'Text', 'RUN ANALYSIS', 'FontWeight', 'bold', ...
                  'ButtonPushedFcn', @onRun);
runBtn.Layout.Row = 19;  runBtn.Layout.Column = [1 2];

exportBtn = uibutton(lg, 'push', 'Text', 'Export results...', 'ButtonPushedFcn', @onExport);
exportBtn.Layout.Row = 20;  exportBtn.Layout.Column = 1;
resetBtn = uibutton(lg, 'push', 'Text', 'Reset defaults', 'ButtonPushedFcn', @(~,~) applyDefaults());
resetBtn.Layout.Row = 20;  resetBtn.Layout.Column = 2;

statusLbl = uilabel(lg, 'Text', 'Ready.', 'WordWrap', 'on', 'VerticalAlignment', 'top');
statusLbl.Layout.Row = 21;  statusLbl.Layout.Column = [1 2];

%% ---------------- Result tabs ----------------
tg = uitabgroup(rootGrid);
tg.Layout.Row = 1;  tg.Layout.Column = 2;

tabNav = uitab(tg, 'Title', 'Navigation');
tabQ   = uitab(tg, 'Title', 'Quantum sensor');
tabS   = uitab(tg, 'Title', 'Sensitivity');
tabSum = uitab(tg, 'Title', 'Summary');

gN = uigridlayout(tabNav, [2 2]);
axTraj = mkAx(gN, 1, 1);   axErr = mkAx(gN, 1, 2);
axSpd  = mkAx(gN, 2, 1);   axAcc = mkAx(gN, 2, 2);

gQ = uigridlayout(tabQ, [2 2]);
axPhase  = mkAx(gQ, 1, 1);  axFringe = mkAx(gQ, 1, 2);
axProb   = mkAx(gQ, 2, 1);  axHist   = mkAx(gQ, 2, 2);

gS = uigridlayout(tabS, [2 2]);
axS1 = mkAx(gS, 1, 1);  axS2 = mkAx(gS, 1, 2);
axS3 = mkAx(gS, 2, 1);  axS4 = mkAx(gS, 2, 2);

gSum = uigridlayout(tabSum, [1 1]);
txtSum = uitextarea(gSum, 'Editable', 'off', 'FontName', 'Courier New', ...
                    'Value', {'Press RUN ANALYSIS to start.'});

onSource([], []);     % set initial enable states

%% =====================================================================
%  Nested functions
%  =====================================================================

    function lab = addLabel(row, txt)
        lab = uilabel(lg, 'Text', txt);
        lab.Layout.Row = row;  lab.Layout.Column = 1;
    end

    function ef = addNum(row, val, lim)
        ef = uieditfield(lg, 'numeric', 'Value', val, 'Limits', lim, ...
                         'ValueDisplayFormat', '%.6g');
        ef.Layout.Row = row;  ef.Layout.Column = 2;
    end

    function dd = addDD(row, items, val)
        dd = uidropdown(lg, 'Items', items, 'Value', val);
        dd.Layout.Row = row;  dd.Layout.Column = 2;
    end

    function ax = mkAx(g, r, c)
        ax = uiaxes(g);
        ax.Layout.Row = r;  ax.Layout.Column = c;
        box(ax, 'on');  grid(ax, 'on');
    end

    function resetAx(ax)
        cla(ax, 'reset');
        hold(ax, 'on');  grid(ax, 'on');  box(ax, 'on');
    end

    function setStatus(msg, col)
        if nargin < 2, col = [0 0 0]; end
        statusLbl.Text = msg;
        statusLbl.FontColor = col;
        drawnow;
    end

    function onSource(~, ~)
        isReal = strcmp(srcDD.Value, 'Real data (CSV)');
        simCtl  = {durEdit, accDD, axEdit, ayEdit, sweepCB};
        realCtl = {loadBtn, demoBtn, smoothEdit, autoCB};
        stSim = 'on';   if isReal, stSim = 'off'; end
        stReal = 'off'; if isReal, stReal = 'on'; end
        for k = 1:numel(simCtl),  simCtl{k}.Enable  = stSim;  end
        for k = 1:numel(realCtl), realCtl{k}.Enable = stReal; end
        if isReal, sweepCB.Value = false; end
    end

    function applyDefaults()
        srcDD.Value = 'Simulation';
        durEdit.Value = d.sim.t_total;   dtEdit.Value = d.sim.dt;
        accDD.Value = d.vehicle.accel.type;
        axEdit.Value = d.vehicle.accel.amplitude(1);
        ayEdit.Value = d.vehicle.accel.amplitude(2);
        TEdit.Value = d.sensor.T_int*1e3;
        atomEdit.Value = d.sensor.N_atoms;
        noiseEdit.Value = d.sensor.meas_noise;
        biasEdit.Value = d.sensor.bias;
        hdgEdit.Value = 0.5;  biasCompEdit.Value = 0;
        integDD.Value = 'trapezoid';
        smoothEdit.Value = 2;  autoCB.Value = true;  sweepCB.Value = false;
        onSource([], []);
        setStatus('Defaults restored.');
    end

    function onLoad(~, ~)
        [f, pth] = uigetfile({'*.csv;*.txt;*.xlsx', 'Data files'}, 'Select real-data file');
        figure(fig);
        if isequal(f, 0), return; end
        dataFile = fullfile(pth, f);
        fileLbl.Text = f;
        setStatus(['Loaded file: ' f]);
    end

    function onDemo(~, ~)
        f = fullfile(pwd, 'demo_real_track.csv');
        make_demo_real_data(f);
        dataFile = f;
        fileLbl.Text = 'demo_real_track.csv (synthetic)';
        setStatus('Demo file created and selected.');
    end

    function p = build_params()
        p = setup_params();
        dtv = dtEdit.Value;  dur = durEdit.Value;
        p.sim.dt = dtv;  p.sim.t_total = dur;
        p.sim.t  = (0:dtv:dur)';  p.sim.N = numel(p.sim.t);
        p.vehicle.accel.type = accDD.Value;
        p.vehicle.accel.amplitude = [axEdit.Value; ayEdit.Value];
        p.sensor.T_int      = TEdit.Value * 1e-3;
        p.sensor.N_atoms    = atomEdit.Value;
        p.sensor.meas_noise = noiseEdit.Value;
        p.sensor.bias       = biasEdit.Value;
        p.derived.phase_sensitivity = p.sensor.k_eff * p.sensor.T_int^2;
        p.derived.a_max = (pi/2) / p.derived.phase_sensitivity;
        p.est.heading_noise_std = deg2rad(hdgEdit.Value);
        p.est.bias_comp         = biasCompEdit.Value;
        p.est.integration       = integDD.Value;
    end

    function onRun(~, ~)
        setStatus('Running...');
        lastwarn('');
        try
            useReal = strcmp(srcDD.Value, 'Real data (CSV)');
            if useReal && isempty(dataFile)
                error('Select a real-data file first (Load CSV or Create demo file).');
            end

            params = build_params();
            info = [];
            if useReal
                ropts.dt       = params.sim.dt;
                ropts.smooth_s = smoothEdit.Value;
                ropts.auto_T   = autoCB.Value;
                [params, truth, info] = load_real_data(dataFile, params, ropts);
            else
                truth = true_motion(params);
            end

            meas = quantum_sensor(params, truth);
            est  = estimate_nav(params, truth, meas);

            popts.do_sweep = sweepCB.Value && ~useReal;
            popts.n_mc     = 3;
            popts.do_plot  = false;
            if popts.do_sweep
                setStatus('Running sensitivity sweeps (may take about a minute)...');
            end
            perf = analyze_perf(params, truth, meas, est, popts);

            R = struct('params', params, 'truth', truth, 'meas', meas, ...
                       'est', est, 'perf', perf, 'info', info);
            updatePlots();
            updateSummary();

            msg = sprintf('Done. Position RMSE = %.3f m, final error = %.3f m.', ...
                          perf.rmse_pos, perf.final_pos_err);
            wmsg = lastwarn;
            if ~isempty(wmsg), msg = [msg ' Warning: ' wmsg]; end
            setStatus(msg, [0 0.4 0]);
        catch ME
            setStatus(['Error: ' ME.message], [0.8 0 0]);
        end
    end

    function updatePlots()
        tr = R.truth;  me = R.meas;  es = R.est;  pf = R.perf;
        t = tr.t;

        % ---------- Navigation tab ----------
        resetAx(axTraj);
        plot(axTraj, tr.p(:,1), tr.p(:,2), 'b-', 'LineWidth', 1.5);
        plot(axTraj, es.p(:,1), es.p(:,2), 'r--', 'LineWidth', 1.5);
        plot(axTraj, tr.p(1,1), tr.p(1,2), 'go', 'MarkerFaceColor', 'g');
        axis(axTraj, 'equal');
        xlabel(axTraj, 'x [m]');  ylabel(axTraj, 'y [m]');
        title(axTraj, 'Trajectory');
        legend(axTraj, {'True', 'Estimated', 'Start'}, 'Location', 'best');

        resetAx(axErr);
        plot(axErr, t, pf.e_p(:,1), 'LineWidth', 1);
        plot(axErr, t, pf.e_p(:,2), 'LineWidth', 1);
        plot(axErr, t, pf.pos_err, 'k', 'LineWidth', 1.5);
        yline(axErr, pf.rmse_pos, 'r--', sprintf('RMSE = %.2f m', pf.rmse_pos));
        xlabel(axErr, 'Time [s]');  ylabel(axErr, 'Position error [m]');
        title(axErr, 'Position error');
        legend(axErr, {'e_x', 'e_y', '||e||'}, 'Location', 'best');

        resetAx(axSpd);
        plot(axSpd, t, tr.speed, 'b', 'LineWidth', 1.5);
        plot(axSpd, t, es.speed_hat, 'r--', 'LineWidth', 1.5);
        xlabel(axSpd, 'Time [s]');  ylabel(axSpd, 'Speed [m/s]');
        title(axSpd, 'Speed');
        legend(axSpd, {'True', 'Estimated'}, 'Location', 'best');

        resetAx(axAcc);
        plot(axAcc, t, es.a_hat, 'Color', [0.65 0.8 1]);
        plot(axAcc, t, me.a_along, 'k', 'LineWidth', 1.2);
        xlabel(axAcc, 'Time [s]');  ylabel(axAcc, 'a [m/s^2]');
        title(axAcc, 'Along-track acceleration');
        legend(axAcc, {'Estimated', 'True'}, 'Location', 'best');

        % ---------- Quantum tab ----------
        resetAx(axPhase);
        plot(axPhase, t, me.phi_true, 'LineWidth', 1.2);
        yline(axPhase, pi/2, 'r--');  yline(axPhase, -pi/2, 'r--');
        xlabel(axPhase, 'Time [s]');  ylabel(axPhase, '\phi [rad]');
        title(axPhase, 'Phase shift (red = range limit)');

        resetAx(axFringe);
        aa = linspace(-1.5*pf.q.a_max, 1.5*pf.q.a_max, 600);
        plot(axFringe, aa, (1 + sin(pf.q.sens_phase * aa))/2, 'k', 'LineWidth', 1.3);
        plot(axFringe, me.a_sensed, me.P_meas, '.', 'MarkerSize', 3);
        xline(axFringe, pf.q.a_max, 'r--');  xline(axFringe, -pf.q.a_max, 'r--');
        xlabel(axFringe, 'Acceleration [m/s^2]');  ylabel(axFringe, 'P(|1>)');
        title(axFringe, 'Phase response (fringe)');
        legend(axFringe, {'Ideal', 'Measured'}, 'Location', 'best');

        resetAx(axProb);
        plot(axProb, t, me.P_meas, '.', 'MarkerSize', 3);
        plot(axProb, t, me.P_ideal, 'k', 'LineWidth', 1);
        xlabel(axProb, 'Time [s]');  ylabel(axProb, 'P(|1>)');
        title(axProb, 'Quantum state probability');
        legend(axProb, {'Measured', 'Ideal'}, 'Location', 'best');

        resetAx(axHist);
        phi_res = es.phi_hat - me.phi_true;
        histogram(axHist, phi_res, 40, 'Normalization', 'pdf', 'FaceColor', [0.3 0.5 0.8]);
        xs = linspace(min(phi_res), max(phi_res), 300);
        sg = pf.q.sigma_phi_theory;
        plot(axHist, xs, exp(-xs.^2/(2*sg^2)) / (sg*sqrt(2*pi)), 'r', 'LineWidth', 1.5);
        xlabel(axHist, 'Phase residual [rad]');  ylabel(axHist, 'PDF');
        title(axHist, 'Measurement uncertainty');
        legend(axHist, {'Simulated', 'Theory'}, 'Location', 'best');

        % ---------- Sensitivity tab ----------
        if isfield(pf, 'sweep')
            plotSweep(axS1, pf.sweep.T_int, pf.sweep.T_int.values*1e3, 'T_{int} [ms]',  'Sensitivity vs. T_{int}', true);
            plotSweep(axS2, pf.sweep.noise, pf.sweep.noise.values,     'Phase noise [rad]', 'Robustness vs. phase noise', true);
            plotSweep(axS3, pf.sweep.atoms, pf.sweep.atoms.values,     'Atoms per shot', 'Shot-noise limit', true);
            plotSweep(axS4, pf.sweep.bias,  pf.sweep.bias.values,      'Bias [m/s^2]',  'Sensitivity vs. bias (drift)', false);
        else
            axList = {axS1, axS2, axS3, axS4};
            for k = 1:4
                resetAx(axList{k});
                title(axList{k}, 'Enable "Run sensitivity sweeps" and press RUN');
            end
        end
    end

    function plotSweep(ax, s, xs, xlab, ttl, logx)
        resetAx(ax);
        errorbar(ax, xs, s.rmse_mean, s.rmse_std, 'o-', 'LineWidth', 1.3);
        set(ax, 'YScale', 'log');
        if logx, set(ax, 'XScale', 'log'); end
        xlabel(ax, xlab);  ylabel(ax, 'Position RMSE [m]');
        title(ax, ttl);
    end

    function updateSummary()
        pp = R.params;  pf = R.perf;
        L = {};
        L{end+1} = '=== Scenario ===';
        L{end+1} = sprintf('Source              : %s', srcDD.Value);
        L{end+1} = sprintf('Duration / dt / N   : %.1f s / %.3f s / %d', pp.sim.t_total, pp.sim.dt, pp.sim.N);
        if ~isempty(R.info)
            L{end+1} = sprintf('Data file           : %s', R.info.file);
            L{end+1} = sprintf('Raw samples         : %d (median dt %.3f s)', R.info.n_raw, R.info.dt_raw);
            L{end+1} = sprintf('Peak along-track a : %.3f m/s^2', R.info.a_peak);
            L{end+1} = sprintf('T_int adapted       : %.3f ms -> %.3f ms', R.info.T_old*1e3, R.info.T_new*1e3);
        end
        L{end+1} = sprintf('Interrogation time   : %.3f ms', pp.sensor.T_int*1e3);
        L{end+1} = sprintf('Atoms per shot        : %.2e', pp.sensor.N_atoms);
        L{end+1} = '';
        L{end+1} = '=== Navigation performance ===';
        L{end+1} = sprintf('Position RMSE        : %.3f m', pf.rmse_pos);
        L{end+1} = sprintf('Velocity RMSE        : %.4f m/s', pf.rmse_vel);
        L{end+1} = sprintf('Acceleration RMSE    : %.2e m/s^2', pf.rmse_acc);
        L{end+1} = sprintf('Max position error   : %.3f m at t = %.1f s', pf.max_pos_err, pf.t_max_err);
        L{end+1} = sprintf('Final position error : %.3f m (%.2f %% of distance)', pf.final_pos_err, pf.drift_pct);
        L{end+1} = sprintf('Drift model          : err ~ %.2e * t^%.2f', pf.drift_coeff, pf.drift_exponent);
        L{end+1} = '';
        L{end+1} = '=== Quantum sensor ===';
        L{end+1} = sprintf('Phase sensitivity    : %.3f rad per (m/s^2)', pf.q.sens_phase);
        L{end+1} = sprintf('Unambiguous range    : +/- %.3f m/s^2 (%d samples out of range)', pf.q.a_max, pf.q.n_out_of_range);
        L{end+1} = sprintf('Phase noise          : %.2e rad (theory %.2e)', pf.q.sigma_phi_meas, pf.q.sigma_phi_theory);
        L{end+1} = sprintf('Acceleration noise   : %.2e m/s^2 (theory %.2e)', pf.q.sigma_a_meas, pf.q.sigma_a_theory);
        L{end+1} = sprintf('Effective bias       : %.2e m/s^2', pf.q.bias_est);
        if isfield(pf, 'robust')
            L{end+1} = '';
            L{end+1} = sprintf('Robustness (nominal) : RMSE = %.3f +/- %.3f m', pf.robust.rmse_mean, pf.robust.rmse_std);
        end
        txtSum.Value = L;
    end

    function onExport(~, ~)
        if isempty(fieldnames(R))
            setStatus('Run the analysis first.', [0.8 0 0]);
            return;
        end
        [f, pth] = uiputfile({'*.mat', 'MAT-file (*.mat)'; ...
                              '*.csv', 'Trajectory CSV (*.csv)'}, ...
                             'Export results', 'results.mat');
        figure(fig);
        if isequal(f, 0), return; end
        full = fullfile(pth, f);
        [~, ~, ext] = fileparts(f);
        try
            if strcmpi(ext, '.csv')
                tr = R.truth;  es = R.est;  me = R.meas;  pf = R.perf;
                Tb = table(tr.t, tr.p(:,1), tr.p(:,2), es.p(:,1), es.p(:,2), ...
                           pf.pos_err, me.a_along, es.a_hat, me.P_meas, ...
                           'VariableNames', {'t', 'x_true', 'y_true', 'x_est', 'y_est', ...
                                             'pos_err', 'a_true_along', 'a_est_along', 'P_meas'});
                writetable(Tb, full);
            else
                save(full, '-struct', 'R');
            end
            setStatus(['Saved: ' full], [0 0.4 0]);
        catch ME
            setStatus(['Export error: ' ME.message], [0.8 0 0]);
        end
    end

end