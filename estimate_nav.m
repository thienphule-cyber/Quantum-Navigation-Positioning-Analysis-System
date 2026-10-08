function est = estimate_nav(params, truth, meas)
% ESTIMATE_NAV  Phase 4 - Quantum navigation and position estimation.
%   Pipeline (dead reckoning):
%       P_meas -> phi_hat -> a_hat (along-track) -> speed_hat -> position_hat
%
%   Inversion at mid-fringe:  P = (1 + sin(phi))/2  ->  phi_hat = asin(2P - 1)
%   Acceleration:             a_hat = phi_hat / (k_eff * T^2)
%
%   The quantum sensor measures acceleration along ONE axis only (the
%   heading direction), so a heading reference (compass/gyro) is used to
%   project the estimated speed back to the 2D plane.
%
%   Input : params - struct from setup_params()
%           truth  - struct from true_motion()
%           meas   - struct from quantum_sensor()
%   Output: est    - struct with estimated phase, acceleration, velocity,
%                    position, heading and quick error figures.
%
%   Usage:  est = estimate_nav(params, truth, meas);

%% ---------------- Estimator settings (edit here) ----------------
cfg.heading_noise_std = deg2rad(0.5);  % heading reference noise std [rad]
cfg.bias_comp         = 0;             % known bias to subtract [m/s^2] (0 = uncompensated)
cfg.scale_comp        = 0;             % known scale-factor error to correct (0 = none)
cfg.integration       = 'trapezoid';   % 'euler' | 'trapezoid'

%% ---------------- Optional overrides from params.est (used by the GUI) ----------------
if isfield(params, 'est')
    fn = fieldnames(params.est);
    for ii = 1:numel(fn)
        cfg.(fn{ii}) = params.est.(fn{ii});
    end
end

%% ---------------- Unpack parameters ----------------
N     = params.sim.N;
dt    = params.sim.dt;
k_eff = params.sensor.k_eff;
T     = params.sensor.T_int;

rng(params.sim.seed + 2);   % independent seed from motion and sensor models

%% ---------------- Step 1: probability -> phase ----------------
x = 2 * meas.P_meas - 1;                 % = sin(phi) at mid-fringe
x = min(max(x, -1), 1);                  % guard against |x| > 1 from noise
phi_hat = asin(x);                       % estimated phase [rad], sign preserved

%% ---------------- Step 2: phase -> acceleration ----------------
a_hat = phi_hat / (k_eff * T^2);         % along-track acceleration [m/s^2]
a_hat = a_hat - cfg.bias_comp;           % remove known bias (if any)
a_hat = a_hat / (1 + cfg.scale_comp);    % remove known scale error (if any)

%% ---------------- Step 3: heading reference ----------------
heading_hat = truth.heading + cfg.heading_noise_std * randn(N, 1);
u_hat = [cos(heading_hat), sin(heading_hat)];   % estimated heading unit vector

%% ---------------- Step 4: integrate acceleration -> speed -> position ----------------
speed_hat = zeros(N, 1);
v_hat     = zeros(N, 2);
p_hat     = zeros(N, 2);

speed_hat(1) = params.vehicle.speed0;           % known initial speed [m/s]
v_hat(1, :)  = speed_hat(1) * u_hat(1, :);
p_hat(1, :)  = params.vehicle.p0(:)';           % known initial position [m]

for k = 1:N-1
    switch cfg.integration
        case 'euler'
            speed_hat(k+1) = speed_hat(k) + a_hat(k) * dt;
            v_hat(k+1, :)  = speed_hat(k+1) * u_hat(k+1, :);
            p_hat(k+1, :)  = p_hat(k, :) + v_hat(k, :) * dt;
        case 'trapezoid'
            speed_hat(k+1) = speed_hat(k) + 0.5 * (a_hat(k) + a_hat(k+1)) * dt;
            v_hat(k+1, :)  = speed_hat(k+1) * u_hat(k+1, :);
            p_hat(k+1, :)  = p_hat(k, :) + 0.5 * (v_hat(k, :) + v_hat(k+1, :)) * dt;
        otherwise
            error('estimate_nav:unknownMethod', ...
                  'Unknown integration method: %s', cfg.integration);
    end
end

%% ---------------- Derived quantities ----------------
a_vec_hat = a_hat .* u_hat;                         % along-track part of acceleration (N x 2)
distance_hat = [0; cumsum(sqrt(sum(diff(p_hat).^2, 2)))];  % travelled distance [m]

%% ---------------- Quick error figures (full analysis is Phase 5) ----------------
e_p = truth.p - p_hat;
e_v = truth.v - v_hat;
pos_err = sqrt(sum(e_p.^2, 2));
vel_err = sqrt(sum(e_v.^2, 2));

%% ---------------- Pack output ----------------
est.t            = truth.t;
est.phi_hat      = phi_hat;        % estimated phase [rad]
est.a_hat        = a_hat;          % estimated along-track acceleration [m/s^2]
est.a_vec_hat    = a_vec_hat;      % N x 2 (along-track component only)
est.heading_hat  = heading_hat;    % heading reference [rad]
est.speed_hat    = speed_hat;      % estimated speed [m/s]
est.v            = v_hat;          % estimated velocity [m/s]
est.p            = p_hat;          % estimated position [m]
est.distance     = distance_hat;   % estimated travelled distance [m]
est.pos_err      = pos_err;        % quick position error norm [m]
est.vel_err      = vel_err;        % quick velocity error norm [m/s]
est.cfg          = cfg;

%% ---------------- Summary ----------------
fprintf('=== Navigation estimated ===\n');
fprintf('Integration       : %s\n', cfg.integration);
fprintf('Final position    : [%.2f, %.2f] m (true [%.2f, %.2f])\n', ...
        p_hat(end, 1), p_hat(end, 2), truth.p(end, 1), truth.p(end, 2));
fprintf('Final position err: %.3f m\n', pos_err(end));
fprintf('Max position err  : %.3f m\n', max(pos_err));
fprintf('Final velocity err: %.4f m/s\n', vel_err(end));
end