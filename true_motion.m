function truth = true_motion(params)
% TRUE_MOTION  Phase 2 - Classical motion model (ground truth).
%   Generates the true 2D trajectory using discrete kinematics:
%       p(k+1) = p(k) + v(k)*dt + 0.5*a(k)*dt^2
%       v(k+1) = v(k) + a(k)*dt
%
%   Input : params - struct from setup_params()
%   Output: truth  - struct with time, acceleration, velocity, position,
%                    speed, heading and travelled distance.
%
%   Usage:  truth = true_motion(params);

%% ---------------- Unpack parameters ----------------
t  = params.sim.t;          % time vector [s], N x 1
dt = params.sim.dt;         % sampling interval [s]
N  = params.sim.N;          % number of samples

rng(params.sim.seed);       % reproducible disturbance

%% ---------------- Nominal acceleration profile ----------------
a_nom = zeros(N, 2);        % nominal acceleration [ax, ay] [m/s^2]

switch lower(params.vehicle.accel.type)
    case 'sinusoidal'
        A = params.vehicle.accel.amplitude(:)';   % 1x2 amplitude
        f = params.vehicle.accel.freq;            % frequency [Hz]
        a_nom = sin(2*pi*f*t) * A;                % N x 2

    case 'constant'
        a_nom = repmat(params.vehicle.accel.const(:)', N, 1);

    case 'piecewise'
        % Three segments: accelerate, cruise, then brake/turn
        T = params.sim.t_total;
        seg1 = t < 0.33*T;
        seg2 = t >= 0.33*T & t < 0.66*T;
        seg3 = t >= 0.66*T;
        a_nom(seg1, :) = repmat([ 0.10,  0.00], nnz(seg1), 1);
        a_nom(seg2, :) = repmat([ 0.00,  0.00], nnz(seg2), 1);
        a_nom(seg3, :) = repmat([-0.10,  0.05], nnz(seg3), 1);

    otherwise
        error('true_motion:unknownProfile', ...
            'Unknown acceleration type: %s', params.vehicle.accel.type);
end

%% ---------------- External disturbance ----------------
if params.env.disturbance.enable
    a_dist = params.env.disturbance.std * randn(N, 2);   % white disturbance
else
    a_dist = zeros(N, 2);
end

a_true = a_nom + a_dist;    % true acceleration acting on the platform

%% ---------------- Kinematic integration ----------------
p = zeros(N, 2);            % position [x, y] [m]
v = zeros(N, 2);            % velocity [vx, vy] [m/s]

p(1, :) = params.vehicle.p0(:)';
v(1, :) = params.vehicle.v0(:)';

for k = 1:N-1
    p(k+1, :) = p(k, :) + v(k, :)*dt + 0.5*a_true(k, :)*dt^2;
    v(k+1, :) = v(k, :) + a_true(k, :)*dt;
end

%% ---------------- Derived quantities ----------------
speed   = sqrt(sum(v.^2, 2));                 % speed magnitude [m/s]
heading = atan2(v(:, 2), v(:, 1));            % heading from x-axis [rad]
heading = unwrap(heading);                    % remove 2*pi jumps

step_len = [0; sqrt(sum(diff(p).^2, 2))];     % distance per step [m]
distance = cumsum(step_len);                  % travelled distance [m]

%% ---------------- Pack output ----------------
truth.t        = t;
truth.a_nom    = a_nom;      % nominal acceleration (no disturbance)
truth.a        = a_true;     % true acceleration (with disturbance)
truth.v        = v;
truth.p        = p;
truth.speed    = speed;
truth.heading  = heading;
truth.distance = distance;

%% ---------------- Summary ----------------
fprintf('=== True motion generated ===\n');
fprintf('Final position   : [%.2f, %.2f] m\n', p(end, 1), p(end, 2));
fprintf('Final velocity   : [%.2f, %.2f] m/s\n', v(end, 1), v(end, 2));
fprintf('Travelled distance: %.2f m\n', distance(end));
fprintf('Peak |a|         : %.3f m/s^2\n', max(sqrt(sum(a_true.^2, 2))));
end