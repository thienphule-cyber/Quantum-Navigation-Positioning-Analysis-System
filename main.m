%% MAIN  Quantum navigation and positioning analysis (simplified 2D model)
%   Choose a mode below:
%       'simulation' : synthetic motion (Phases 1-5)
%       'real'       : recorded track from a CSV file (load_real_data)
%       'gui'        : open the interactive GUI
%
%   Required files in the same folder:
%       setup_params, true_motion, quantum_sensor, estimate_nav,
%       analyze_perf, load_real_data, make_demo_real_data, quantum_nav_gui

clear; clc; close all;

%% ---------------- User options ----------------
mode = 'simulation';            % 'simulation' | 'real' | 'gui'

real_file = 'demo_real_track.csv';  % used in 'real' mode (t,x,y or t,lat,lon)
real_opts.smooth_s = 2.0;           % smoothing window [s]
real_opts.auto_T   = true;          % shrink T_int to fit the data range
% real_opts.time_scale = 1e-3;      % uncomment if the time column is in ms

run_opts.do_sweep  = true;      % sensitivity sweeps (simulation mode only)
run_opts.n_mc      = 5;         % Monte Carlo runs per sweep point
run_opts.do_plot   = true;
run_opts.save_mat  = true;      % save results to <out_dir>/results.mat
run_opts.save_figs = false;     % export all figures as PNG
run_opts.out_dir   = 'results';

%% ---------------- Check required files ----------------
required = {'setup_params', 'true_motion', 'quantum_sensor', 'estimate_nav', ...
            'analyze_perf', 'load_real_data', 'make_demo_real_data', 'quantum_nav_gui'};
for ii = 1:numel(required)
    if exist(required{ii}, 'file') ~= 2
        error('main:missingFile', 'Missing file: %s.m (keep all scripts in one folder).', required{ii});
    end
end

%% ---------------- GUI mode ----------------
if strcmpi(mode, 'gui')
    quantum_nav_gui();
    return;
end

tic_total = tic;

%% ---------------- Phase 1: system definition ----------------
fprintf('\n########## PHASE 1: System definition ##########\n');
params = setup_params();

% ---- Optional overrides (uncomment to experiment) ----
% params.sensor.N_atoms = 1e6;
% params.sensor.bias    = 0;
% params.est.bias_comp  = 1e-3;      % requires the estimate_nav.m patch
% params.vehicle.accel.type = 'piecewise';

%% ---------------- Phase 2: motion (simulated or real) ----------------
switch lower(mode)
    case 'simulation'
        fprintf('\n########## PHASE 2: Classical motion (simulation) ##########\n');
        truth = true_motion(params);

    case 'real'
        fprintf('\n########## PHASE 2: Real data ##########\n');
        if exist(real_file, 'file') ~= 2
            fprintf('File "%s" not found, creating a demo track.\n', real_file);
            make_demo_real_data(real_file);
        end
        [params, truth, info] = load_real_data(real_file, params, real_opts);
        run_opts.do_sweep = false;   % sweeps re-simulate motion, not valid for real data

    otherwise
        error('main:badMode', 'Unknown mode: %s', mode);
end

%% ---------------- Phase 3: quantum sensor ----------------
fprintf('\n########## PHASE 3: Quantum sensor ##########\n');
meas = quantum_sensor(params, truth);

%% ---------------- Phase 4: navigation estimation ----------------
fprintf('\n########## PHASE 4: Navigation estimation ##########\n');
est = estimate_nav(params, truth, meas);

%% ---------------- Phase 5: performance analysis ----------------
fprintf('\n########## PHASE 5: Performance analysis ##########\n');
perf = analyze_perf(params, truth, meas, est, run_opts);

%% ---------------- Overview figure ----------------
figure('Name', 'Overview - Quantum navigation', 'Color', 'w', ...
       'Position', [100 100 1100 650]);

subplot(2,3,1);
plot(truth.p(:,1), truth.p(:,2), 'b-', 'LineWidth', 1.5); hold on;
plot(est.p(:,1), est.p(:,2), 'r--', 'LineWidth', 1.5);
plot(truth.p(1,1), truth.p(1,2), 'go', 'MarkerFaceColor', 'g');
axis equal; grid on; xlabel('x [m]'); ylabel('y [m]');
title('Trajectory'); legend('True', 'Estimated', 'Start', 'Location', 'best');

subplot(2,3,2);
plot(truth.t, truth.a, 'LineWidth', 1);
grid on; xlabel('Time [s]'); ylabel('a [m/s^2]');
title('Reference acceleration'); legend('a_x', 'a_y', 'Location', 'best');

subplot(2,3,3);
plot(meas.t, meas.phi_true, 'LineWidth', 1.2); hold on;
yline(pi/2, 'r--'); yline(-pi/2, 'r--');
grid on; xlabel('Time [s]'); ylabel('\phi [rad]');
title('Quantum phase shift (red = range limit)');

subplot(2,3,4);
plot(meas.t, meas.P_meas, '.', 'MarkerSize', 3); hold on;
plot(meas.t, meas.P_ideal, 'k', 'LineWidth', 1);
grid on; xlabel('Time [s]'); ylabel('P(|1>)');
title('Measurement probability'); legend('Measured', 'Ideal', 'Location', 'best');

subplot(2,3,5);
plot(truth.t, truth.speed, 'b', 'LineWidth', 1.5); hold on;
plot(est.t, est.speed_hat, 'r--', 'LineWidth', 1.5);
grid on; xlabel('Time [s]'); ylabel('Speed [m/s]');
title('Speed'); legend('True', 'Estimated', 'Location', 'best');

subplot(2,3,6);
plot(perf.t, perf.pos_err, 'k', 'LineWidth', 1.5); hold on;
yline(perf.rmse_pos, 'r--', sprintf('RMSE = %.2f m', perf.rmse_pos));
grid on; xlabel('Time [s]'); ylabel('||e_p|| [m]');
title('Position error (drift)');

%% ---------------- Save results ----------------
if run_opts.save_mat || run_opts.save_figs
    if ~exist(run_opts.out_dir, 'dir'), mkdir(run_opts.out_dir); end
end

if run_opts.save_mat
    save(fullfile(run_opts.out_dir, 'results.mat'), 'params', 'truth', 'meas', 'est', 'perf');
    fprintf('\nSaved: %s\n', fullfile(run_opts.out_dir, 'results.mat'));
end

if run_opts.save_figs
    figs = findall(groot, 'Type', 'figure');
    for ii = 1:numel(figs)
        name = regexprep(figs(ii).Name, '[^\w]+', '_');
        if isempty(name), name = sprintf('figure_%d', figs(ii).Number); end
        try
            exportgraphics(figs(ii), fullfile(run_opts.out_dir, [name '.png']), 'Resolution', 150);
        catch
            saveas(figs(ii), fullfile(run_opts.out_dir, [name '.png']));
        end
    end
    fprintf('Saved %d figures to: %s\n', numel(figs), run_opts.out_dir);
end

%% ---------------- Final summary ----------------
fprintf('\n================ FINAL SUMMARY ================\n');
fprintf('Mode              : %s\n', mode);
fprintf('Duration          : %.0f s, dt = %.3f s\n', params.sim.t_total, params.sim.dt);
fprintf('Position RMSE     : %.3f m\n', perf.rmse_pos);
fprintf('Max position error: %.3f m\n', perf.max_pos_err);
fprintf('Drift model       : err ~ t^%.2f\n', perf.drift_exponent);
fprintf('Accel noise       : %.2e m/s^2 (theory %.2e)\n', ...
        perf.q.sigma_a_meas, perf.q.sigma_a_theory);
fprintf('Total run time    : %.1f s\n', toc(tic_total));
fprintf('===============================================\n');