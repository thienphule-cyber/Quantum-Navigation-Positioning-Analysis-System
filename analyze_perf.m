function perf = analyze_perf(params, truth, meas, est, opts)
% ANALYZE_PERF  Phase 5 - Navigation performance analysis.
%   Computes trajectory/velocity/acceleration errors, RMSE, drift, quantum
%   sensor performance figures, and (optionally) sensitivity / robustness
%   sweeps by re-running the full pipeline with modified parameters.
%
%   Input : params, truth, meas, est - structs from Phases 1-4
%           opts (optional struct):
%               opts.do_sweep : run sensitivity sweeps   (default true)
%               opts.n_mc     : Monte Carlo runs per point (default 5)
%               opts.do_plot  : draw figures              (default true)
%   Output: perf - struct with all metrics.
%
%   Usage:  perf = analyze_perf(params, truth, meas, est);

%% ---------------- Options ----------------
if nargin < 5, opts = struct(); end
if ~isfield(opts, 'do_sweep'), opts.do_sweep = true; end
if ~isfield(opts, 'n_mc'),     opts.n_mc     = 5;    end
if ~isfield(opts, 'do_plot'),  opts.do_plot  = true; end

t  = truth.t;
N  = params.sim.N;

%% ---------------- Trajectory / velocity / acceleration errors ----------------
e_p = truth.p - est.p;                         % position error vector [m]
e_v = truth.v - est.v;                         % velocity error vector [m/s]
e_a = est.a_hat - meas.a_along;                % along-track acceleration error [m/s^2]

pos_err = sqrt(sum(e_p.^2, 2));                % position error norm [m]
vel_err = sqrt(sum(e_v.^2, 2));                % velocity error norm [m/s]

perf.rmse_pos  = sqrt(mean(sum(e_p.^2, 2)));   % RMSE = sqrt(1/N * sum ||e_k||^2) [m]
perf.rmse_vel  = sqrt(mean(sum(e_v.^2, 2)));   % [m/s]
perf.rmse_acc  = sqrt(mean(e_a.^2));           % [m/s^2]
[perf.max_pos_err, idx_max] = max(pos_err);    % maximum positioning error [m]
perf.t_max_err = t(idx_max);                   % time of maximum error [s]
perf.final_pos_err = pos_err(end);             % final position error [m]
perf.final_vel_err = vel_err(end);             % final velocity error [m/s]

%% ---------------- Drift / error growth ----------------
% Fit pos_err ~ c * t^n on a log-log scale (ignore the first 2 s)
idx = t >= 2 & pos_err > 0;
coef = polyfit(log(t(idx)), log(pos_err(idx)), 1);
perf.drift_exponent = coef(1);                 % n  (n ~ 2 means bias-dominated drift)
perf.drift_coeff    = exp(coef(2));            % c
perf.drift_pct      = 100 * pos_err(end) / max(truth.distance(end), eps); % [% of distance]
perf.drift_rate     = pos_err(end) / t(end);   % average drift rate [m/s]

%% ---------------- Quantum sensor performance ----------------
sens = meas.sens_phase;                        % phase sensitivity [rad per m/s^2]
phi_res = est.phi_hat - meas.phi_true;         % phase estimation residual [rad]
a_res   = e_a;                                 % acceleration residual [m/s^2]

perf.q.sens_phase        = sens;
perf.q.a_max             = (pi/2) / sens;      % unambiguous range [m/s^2]
perf.q.sigma_phi_theory  = sqrt(meas.sigma_phi_shot^2 + params.sensor.meas_noise^2);
perf.q.sigma_phi_meas    = std(phi_res);       % measured phase noise [rad]
perf.q.sigma_a_theory    = meas.sigma_a_total; % theoretical per-shot uncertainty [m/s^2]
perf.q.sigma_a_meas      = std(a_res);         % measured acceleration noise [m/s^2]
perf.q.bias_est          = mean(a_res);        % effective bias seen by the navigator [m/s^2]
perf.q.n_out_of_range    = nnz(abs(meas.phi_true) > pi/2);
perf.q.P_mean            = mean(meas.P_meas);
perf.q.P_range           = [min(meas.P_meas), max(meas.P_meas)];

%% ---------------- Pack basic output ----------------
perf.t       = t;
perf.pos_err = pos_err;
perf.vel_err = vel_err;
perf.e_p     = e_p;
perf.e_v     = e_v;
perf.e_a     = e_a;

%% ---------------- Print summary ----------------
fprintf('\n=== Navigation performance ===\n');
fprintf('Position RMSE        : %.3f m\n',   perf.rmse_pos);
fprintf('Velocity RMSE        : %.4f m/s\n', perf.rmse_vel);
fprintf('Acceleration RMSE    : %.2e m/s^2\n', perf.rmse_acc);
fprintf('Max position error   : %.3f m at t = %.1f s\n', perf.max_pos_err, perf.t_max_err);
fprintf('Final position error : %.3f m (%.2f %% of travelled distance)\n', ...
        perf.final_pos_err, perf.drift_pct);
fprintf('Drift model          : err ~ %.2e * t^%.2f\n', perf.drift_coeff, perf.drift_exponent);
fprintf('\n=== Quantum sensor performance ===\n');
fprintf('Phase sensitivity    : %.3f rad per (m/s^2)\n', perf.q.sens_phase);
fprintf('Unambiguous range    : +/- %.3f m/s^2 (%d samples out of range)\n', ...
        perf.q.a_max, perf.q.n_out_of_range);
fprintf('Phase noise          : %.2e rad measured, %.2e rad theory\n', ...
        perf.q.sigma_phi_meas, perf.q.sigma_phi_theory);
fprintf('Acceleration noise   : %.2e m/s^2 measured, %.2e m/s^2 theory\n', ...
        perf.q.sigma_a_meas, perf.q.sigma_a_theory);
fprintf('Effective bias       : %.2e m/s^2\n', perf.q.bias_est);

%% ---------------- Sensitivity / robustness sweeps ----------------
if opts.do_sweep
    fprintf('\nRunning sensitivity sweeps (%d Monte Carlo runs per point)...\n', opts.n_mc);

    perf.sweep.T_int = run_sweep(params, 'T_int',     [0.1 0.2 0.3 0.5 0.7 1.0 1.5]*1e-3, opts.n_mc);
    perf.sweep.noise = run_sweep(params, 'meas_noise', [1e-3 3e-3 1e-2 3e-2 1e-1],         opts.n_mc);
    perf.sweep.atoms = run_sweep(params, 'N_atoms',    [1e3 1e4 1e5 1e6 1e7],              opts.n_mc);
    perf.sweep.bias  = run_sweep(params, 'bias',       [0 1e-4 3e-4 1e-3 3e-3 1e-2],       opts.n_mc);

    % Robustness at nominal settings: spread of RMSE over random seeds
    r = run_sweep(params, 'bias', params.sensor.bias, max(opts.n_mc, 20));
    perf.robust.rmse_mean = r.rmse_mean;
    perf.robust.rmse_std  = r.rmse_std;
    fprintf('Robustness (nominal) : RMSE = %.3f +/- %.3f m over %d runs\n', ...
            r.rmse_mean, r.rmse_std, max(opts.n_mc, 20));
end

%% ---------------- Plots ----------------
if opts.do_plot
    plot_navigation(truth, est, perf);
    plot_quantum(meas, perf, phi_res, params);
    if opts.do_sweep
        plot_sweeps(perf, params);
    end
end
end

%% =====================================================================
%  Local functions
%  =====================================================================

function sw = run_sweep(params, name, values, n_mc)
% RUN_SWEEP  Re-run Phases 2-4 for each parameter value and collect RMSE.
    warn_state = warning;               % silence repeated range warnings
    warning('off', 'all');
    cleaner = onCleanup(@() warning(warn_state));

    nv = numel(values);
    rmse_mean = zeros(1, nv);
    rmse_std  = zeros(1, nv);
    final_mean = zeros(1, nv);

    for i = 1:nv
        r = zeros(1, n_mc);
        f = zeros(1, n_mc);
        for m = 1:n_mc
            p = params;
            p.sensor.(name) = values(i);
            p.sim.seed = params.sim.seed + 100*m;   % different noise per run

            % Keep derived quantities consistent with the modified sensor
            p.derived.phase_sensitivity = p.sensor.k_eff * p.sensor.T_int^2;
            p.derived.a_max = (pi/2) / p.derived.phase_sensitivity;

            [r(m), f(m)] = run_pipeline(p);
        end
        rmse_mean(i)  = mean(r);
        rmse_std(i)   = std(r);
        final_mean(i) = mean(f);
    end

    sw.name       = name;
    sw.values     = values;
    sw.rmse_mean  = rmse_mean;
    sw.rmse_std   = rmse_std;
    sw.final_mean = final_mean;
end

function [rmse, final_err] = run_pipeline(p)
% RUN_PIPELINE  Run Phases 2-4 silently and return position RMSE.
    evalc('tr = true_motion(p); ms = quantum_sensor(p, tr); es = estimate_nav(p, tr, ms);');
    rmse = sqrt(mean(es.pos_err.^2));
    final_err = es.pos_err(end);
end

function plot_navigation(truth, est, perf)
% PLOT_NAVIGATION  Trajectory and error figures.
    t = truth.t;
    figure('Name', 'Phase 5 - Navigation errors', 'Color', 'w');

    subplot(2,3,1);
    plot(truth.p(:,1), truth.p(:,2), 'b-', 'LineWidth', 1.5); hold on;
    plot(est.p(:,1), est.p(:,2), 'r--', 'LineWidth', 1.5);
    plot(truth.p(1,1), truth.p(1,2), 'go', 'MarkerFaceColor', 'g');
    axis equal; grid on; xlabel('x [m]'); ylabel('y [m]');
    title('Trajectory'); legend('True', 'Estimated', 'Start', 'Location', 'best');

    subplot(2,3,2);
    plot(t, perf.e_p(:,1), 'LineWidth', 1); hold on;
    plot(t, perf.e_p(:,2), 'LineWidth', 1);
    plot(t, perf.pos_err, 'k', 'LineWidth', 1.5);
    yline(perf.rmse_pos, 'r--', sprintf('RMSE = %.2f m', perf.rmse_pos));
    grid on; xlabel('Time [s]'); ylabel('Position error [m]');
    title('Position error'); legend('e_x', 'e_y', '||e||', 'Location', 'best');

    subplot(2,3,3);
    plot(t, perf.e_v, 'LineWidth', 1); hold on;
    plot(t, perf.vel_err, 'k', 'LineWidth', 1.5);
    grid on; xlabel('Time [s]'); ylabel('Velocity error [m/s]');
    title('Velocity error'); legend('e_{vx}', 'e_{vy}', '||e_v||', 'Location', 'best');

    subplot(2,3,4);
    plot(t, perf.e_a, 'Color', [0.2 0.4 0.8]); hold on;
    yline(perf.q.bias_est, 'r--', 'Mean (bias)');
    grid on; xlabel('Time [s]'); ylabel('Acceleration error [m/s^2]');
    title('Along-track acceleration error');

    subplot(2,3,5);
    loglog(t(2:end), perf.pos_err(2:end), 'b', 'LineWidth', 1.2); hold on;
    loglog(t(2:end), perf.drift_coeff * t(2:end).^perf.drift_exponent, 'r--', 'LineWidth', 1.5);
    grid on; xlabel('Time [s]'); ylabel('||e|| [m]');
    title(sprintf('Error growth (n = %.2f)', perf.drift_exponent));
    legend('Error', 'Fit c t^n', 'Location', 'southeast');

    subplot(2,3,6);
    plot(t, truth.distance, 'b', 'LineWidth', 1.5); hold on;
    plot(t, est.distance, 'r--', 'LineWidth', 1.5);
    grid on; xlabel('Time [s]'); ylabel('Distance [m]');
    title('Accumulated distance'); legend('True', 'Estimated', 'Location', 'best');
end

function plot_quantum(meas, perf, phi_res, params)
% PLOT_QUANTUM  Quantum sensor performance figures.
    figure('Name', 'Phase 5 - Quantum sensor performance', 'Color', 'w');

    subplot(2,2,1);
    plot(meas.t, meas.P_meas, '.', 'MarkerSize', 3); hold on;
    plot(meas.t, meas.P_ideal, 'k', 'LineWidth', 1);
    grid on; xlabel('Time [s]'); ylabel('P(|1>)');
    title('Quantum state probability'); legend('Measured', 'Ideal', 'Location', 'best');

    subplot(2,2,2);
    a_axis = linspace(-1.5*perf.q.a_max, 1.5*perf.q.a_max, 600);
    plot(a_axis, (1 + sin(perf.q.sens_phase * a_axis))/2, 'k', 'LineWidth', 1.3); hold on;
    plot(meas.a_sensed, meas.P_meas, '.', 'MarkerSize', 3);
    xline(perf.q.a_max, 'r--'); xline(-perf.q.a_max, 'r--');
    grid on; xlabel('Acceleration [m/s^2]'); ylabel('P(|1>)');
    title(sprintf('Phase response (%.2f rad per m/s^2)', perf.q.sens_phase));
    legend('Ideal fringe', 'Measured', 'Range limit', 'Location', 'best');

    subplot(2,2,3);
    histogram(phi_res, 40, 'Normalization', 'pdf', 'FaceColor', [0.3 0.5 0.8]); hold on;
    x = linspace(min(phi_res), max(phi_res), 300);
    s = perf.q.sigma_phi_theory;
    plot(x, exp(-x.^2/(2*s^2)) / (s*sqrt(2*pi)), 'r', 'LineWidth', 1.5);
    grid on; xlabel('Phase residual [rad]'); ylabel('PDF');
    title('Measurement uncertainty'); legend('Simulated', 'Theory (Gaussian)');

    subplot(2,2,4);
    plot(meas.t, perf.e_a, 'Color', [0.2 0.4 0.8]); hold on;
    yline( 3*perf.q.sigma_a_theory + perf.q.bias_est, 'r--');
    yline(-3*perf.q.sigma_a_theory + perf.q.bias_est, 'r--');
    grid on; xlabel('Time [s]'); ylabel('a_{est} - a_{true} [m/s^2]');
    title('Acceleration noise with 3\sigma bounds');
end

function plot_sweeps(perf, params)
% PLOT_SWEEPS  Sensitivity and robustness figures.
    figure('Name', 'Phase 5 - Sensitivity analysis', 'Color', 'w');

    s = perf.sweep.T_int;
    subplot(2,2,1);
    errorbar(s.values*1e3, s.rmse_mean, s.rmse_std, 'o-', 'LineWidth', 1.3);
    set(gca, 'XScale', 'log', 'YScale', 'log'); grid on;
    xlabel('Interrogation time T [ms]'); ylabel('Position RMSE [m]');
    title('Sensitivity vs. T_{int}  (range limit appears at large T)');

    s = perf.sweep.noise;
    subplot(2,2,2);
    errorbar(s.values, s.rmse_mean, s.rmse_std, 'o-', 'LineWidth', 1.3);
    set(gca, 'XScale', 'log', 'YScale', 'log'); grid on;
    xlabel('Phase noise \sigma [rad]'); ylabel('Position RMSE [m]');
    title('Robustness vs. phase noise');

    s = perf.sweep.atoms;
    subplot(2,2,3);
    errorbar(s.values, s.rmse_mean, s.rmse_std, 'o-', 'LineWidth', 1.3);
    set(gca, 'XScale', 'log', 'YScale', 'log'); grid on;
    xlabel('Atoms per shot N'); ylabel('Position RMSE [m]');
    title('Shot-noise limit vs. atom number');

    s = perf.sweep.bias;
    subplot(2,2,4);
    semilogy(s.values, s.rmse_mean, 'o-', 'LineWidth', 1.3); hold on;
    semilogy(s.values, s.final_mean, 's--', 'LineWidth', 1.3);
    grid on; xlabel('Sensor bias [m/s^2]'); ylabel('Position error [m]');
    title('Sensitivity vs. bias (drift)'); legend('RMSE', 'Final error', 'Location', 'northwest');
end