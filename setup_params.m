function params = setup_params()
% SETUP_PARAMS  Phase 1 - Navigation system definition.
%   Returns a struct with vehicle, environment and quantum sensor settings.
%   Units: SI (m, s, rad, K, T) unless stated otherwise.
%
%   Usage:  params = setup_params();

%% ---------------- Simulation timing ----------------
params.sim.t_total = 60;          % total operating time [s]
params.sim.dt      = 0.01;        % sampling interval [s] (100 Hz)
params.sim.t       = (0:params.sim.dt:params.sim.t_total)';  % time vector
params.sim.N       = numel(params.sim.t);                    % number of samples
params.sim.seed    = 42;          % random seed for reproducible noise

%% ---------------- Vehicle / platform (2D) ----------------
params.vehicle.p0          = [0; 0];     % initial position [x; y] [m]
params.vehicle.speed0      = 1.0;        % initial speed [m/s]
params.vehicle.heading0    = deg2rad(30);% initial heading from x-axis [rad]
params.vehicle.v0          = params.vehicle.speed0 * ...
    [cos(params.vehicle.heading0); ...
    sin(params.vehicle.heading0)];  % initial velocity [m/s]

% Acceleration profile (simple, defined here, generated in Phase 2)
params.vehicle.accel.type      = 'sinusoidal'; % 'sinusoidal' | 'constant' | 'piecewise'
params.vehicle.accel.amplitude = [0.20; 0.10]; % [ax; ay] amplitude [m/s^2]
params.vehicle.accel.freq      = 0.05;         % frequency [Hz]
params.vehicle.accel.const     = [0.05; 0.02]; % used when type = 'constant' [m/s^2]

%% ---------------- Environment ----------------
params.env.gravity        = 9.81;      % gravity [m/s^2] (kept for later 3D extension)
params.env.temperature    = 300;       % ambient temperature [K]
params.env.magnetic_field = 50e-6;     % magnetic field magnitude [T] (optional use)
params.env.use_magnetic   = false;     % enable magnetic field effect in the sensor model

% External disturbance (e.g. vibration) added to the true acceleration
params.env.disturbance.enable = true;
params.env.disturbance.std    = 0.005; % white acceleration disturbance std [m/s^2]

%% ---------------- Quantum sensor (atom-interferometer-like, simplified) ----------------
params.sensor.lambda       = 780e-9;                       % laser wavelength [m] (Rb-87 D2 line)
params.sensor.k_eff        = 2 * (2*pi / params.sensor.lambda); % effective wave vector [rad/m]
params.sensor.T_int        = 0.5e-3;                       % interrogation time T [s]
params.sensor.N_atoms      = 1e5;                          % atoms per measurement (shot noise)
params.sensor.phase_offset = pi/2;                         % operate at mid-fringe to keep sign of a
params.sensor.meas_noise   = 0.01;                         % extra phase noise std [rad]
params.sensor.bias         = 1e-3;                         % constant acceleration bias [m/s^2]
params.sensor.scale_error  = 0;                            % scale-factor error (0 = ideal)

% Initial two-level quantum state |psi> = alpha|0> + beta|1>
params.sensor.psi0 = [1; 0];       % start in |0>
params.sensor.psi0 = params.sensor.psi0 / norm(params.sensor.psi0); % normalise

%% ---------------- Derived quantities ----------------
% Phase sensitivity: phi = k_eff * a * T^2  ->  d(phi)/da [rad per m/s^2]
params.derived.phase_sensitivity = params.sensor.k_eff * params.sensor.T_int^2;

% Max unambiguous acceleration when working at mid-fringe: |phi| < pi/2
params.derived.a_max = (pi/2) / params.derived.phase_sensitivity;  % [m/s^2]

%% ---------------- Sanity checks ----------------
if params.sensor.T_int * 2 > params.sim.dt
    warning('setup_params:timing', ...
        'Sampling interval dt is shorter than the sensor cycle time (2*T_int).');
end

a_peak = norm(params.vehicle.accel.amplitude) + 3 * params.env.disturbance.std;
if a_peak > params.derived.a_max
    warning('setup_params:ambiguity', ...
        ['Peak acceleration (%.3f m/s^2) exceeds the unambiguous range ' ...
        '(%.3f m/s^2). Phase wrapping will occur.'], a_peak, params.derived.a_max);
end

%% ---------------- Print scenario summary ----------------
fprintf('=== Navigation scenario ===\n');
fprintf('Duration          : %.1f s, dt = %.3f s, N = %d\n', ...
    params.sim.t_total, params.sim.dt, params.sim.N);
fprintf('Initial position  : [%.2f, %.2f] m\n', params.vehicle.p0);
fprintf('Initial velocity  : [%.2f, %.2f] m/s (heading %.1f deg)\n', ...
    params.vehicle.v0, rad2deg(params.vehicle.heading0));
fprintf('Acceleration      : %s, amplitude [%.2f, %.2f] m/s^2\n', ...
    params.vehicle.accel.type, params.vehicle.accel.amplitude);
fprintf('Interrogation time: %.2f ms, N_atoms = %.0e\n', ...
    params.sensor.T_int*1e3, params.sensor.N_atoms);
fprintf('Phase sensitivity : %.3f rad per (m/s^2)\n', params.derived.phase_sensitivity);
fprintf('Unambiguous range : +/- %.3f m/s^2\n', params.derived.a_max);
end