function meas = quantum_sensor(params, truth)
% QUANTUM_SENSOR  Phase 3 - Basic quantum sensor model.
%   Simulates a two-level quantum system (Ramsey / atom-interferometer-like):
%       1) pi/2 pulse   : |0> -> superposition  (alpha|0> + beta|1>)
%       2) free phase evolution under H = (hbar*Phi/(2T)) * sigma_z
%       3) pi/2 pulse   : converts phase into population difference
%       4) projective measurement of N_atoms -> shot noise
%
%   Phase shift from acceleration:  phi = k_eff * a * T^2
%   With mid-fringe offset:         P   = (1 + sin(phi)) / 2
%
%   Input : params - struct from setup_params()
%           truth  - struct from true_motion()
%   Output: meas   - struct with phase, state, probability and counts
%
%   Usage:  meas = quantum_sensor(params, truth);

%% ---------------- Unpack parameters ----------------
N      = params.sim.N;
k_eff  = params.sensor.k_eff;
T      = params.sensor.T_int;
Natoms = params.sensor.N_atoms;
offset = params.sensor.phase_offset;
psi0   = params.sensor.psi0(:);
sig_ph = params.sensor.meas_noise;
bias   = params.sensor.bias;
scale  = params.sensor.scale_error;

rng(params.sim.seed + 1);   % independent seed from the motion model

%% ---------------- Acceleration seen by the sensor ----------------
% Sensor measures acceleration along one axis (sensitive axis = platform
% heading direction). Project the 2D true acceleration onto that axis.
u   = [cos(truth.heading), sin(truth.heading)];   % N x 2 unit heading vector
a_s = sum(truth.a .* u, 2);                       % along-track acceleration [m/s^2]

% Apply sensor imperfections (scale-factor error and constant bias)
a_sensed = (1 + scale) * a_s + bias;

%% ---------------- Phase shift ----------------
phi_true  = k_eff * a_sensed * T^2;               % signal phase [rad]
phi_noise = sig_ph * randn(N, 1);                 % extra phase noise [rad]

% Total phase seen by the atoms. Subtracting pi/2 puts the sensor at
% mid-fringe, so P = (1 + sin(phi)) / 2 and the sign of a is preserved.
Phi = phi_true + phi_noise - offset;

%% ---------------- Quantum state evolution ----------------
% Beam-splitter (pi/2 rotation about x) and phase accumulation unitary
U_bs = (1/sqrt(2)) * [1, -1i; -1i, 1];

psi_final = zeros(2, N);                          % final state for every sample
for k = 1:N
    U_phase = diag([exp(-1i*Phi(k)/2), exp(1i*Phi(k)/2)]);  % exp(-iHt/hbar)
    psi_final(:, k) = U_bs * (U_phase * (U_bs * psi0));
end

% Probability of finding the atom in |1>
P_ideal = abs(psi_final(2, :)').^2;               % N x 1, ideal probability
P_ideal = min(max(P_ideal, 0), 1);                % guard against rounding

% Cross-check with the analytic formula P = (1 + cos(Phi)) / 2
P_analytic = (1 + cos(Phi)) / 2;
if params.sensor.psi0(1) == 1 && max(abs(P_ideal - P_analytic)) > 1e-9
    warning('quantum_sensor:mismatch', ...
        'Simulated state evolution differs from the analytic formula.');
end

%% ---------------- Projective measurement (shot noise) ----------------
if exist('binornd', 'file') == 2
    counts = binornd(Natoms, P_ideal);            % Statistics Toolbox
else
    % Gaussian approximation of the binomial distribution
    counts = round(Natoms * P_ideal + sqrt(Natoms * P_ideal .* (1 - P_ideal)) .* randn(N, 1));
    counts = min(max(counts, 0), Natoms);
end
P_meas = counts / Natoms;                         % measured probability

%% ---------------- Sensor performance figures ----------------
sens_phase = k_eff * T^2;                         % [rad per m/s^2]
sigma_phi_shot = 1 / sqrt(Natoms);                % shot-noise phase limit at mid-fringe [rad]
sigma_a_shot   = sigma_phi_shot / sens_phase;     % acceleration uncertainty (shot noise) [m/s^2]
sigma_a_total  = sqrt(sigma_phi_shot^2 + sig_ph^2) / sens_phase;  % incl. phase noise [m/s^2]

%% ---------------- Range check ----------------
n_wrap = nnz(abs(phi_true) > pi/2);
if n_wrap > 0
    warning('quantum_sensor:wrap', ...
        '%d samples exceed the unambiguous phase range (|phi| > pi/2).', n_wrap);
end

%% ---------------- Pack output ----------------
meas.t              = truth.t;
meas.a_sensed       = a_sensed;        % acceleration seen by the sensor
meas.a_along        = a_s;             % along-track true acceleration (no sensor error)
meas.phi_true       = phi_true;        % signal phase [rad]
meas.Phi_total      = Phi;             % phase including noise and offset [rad]
meas.psi_final      = psi_final;       % 2 x N final quantum states
meas.P_ideal        = P_ideal;         % noise-free probability
meas.counts         = counts;          % detected atoms in |1>
meas.P_meas         = P_meas;          % measured probability (with shot noise)
meas.sens_phase     = sens_phase;
meas.sigma_phi_shot = sigma_phi_shot;
meas.sigma_a_shot   = sigma_a_shot;
meas.sigma_a_total  = sigma_a_total;
meas.heading_axis   = u;               % sensitive-axis direction (N x 2)

%% ---------------- Summary ----------------
fprintf('=== Quantum sensor simulated ===\n');
fprintf('Phase range         : [%.4f, %.4f] rad\n', min(phi_true), max(phi_true));
fprintf('Probability range   : [%.4f, %.4f]\n', min(P_meas), max(P_meas));
fprintf('Shot-noise limit    : %.2e rad  ->  %.2e m/s^2 per shot\n', ...
        sigma_phi_shot, sigma_a_shot);
fprintf('Total uncertainty   : %.2e m/s^2 per shot\n', sigma_a_total);
end