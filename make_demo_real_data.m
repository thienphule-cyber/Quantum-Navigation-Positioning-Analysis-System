function make_demo_real_data(filename, seed)
% MAKE_DEMO_REAL_DATA  Create a synthetic "real-like" vehicle track (CSV).
%   Mimics a 5 Hz GPS-style recording with timestamp jitter and position
%   noise. Columns: t [s], x [m], y [m].
%
%   Usage:  make_demo_real_data('demo_real_track.csv');

if nargin < 1, filename = 'demo_real_track.csv'; end
if nargin < 2, seed = 7; end
rng(seed);

fs = 5;                          % recording rate [Hz]
T  = 120;                        % duration [s]
sigma_pos = 0.3;                 % position noise std [m]

% Fine-grid reference path (varying speed and winding heading)
tf      = (0:0.01:T)';
speed   = 10 + 4*sin(2*pi*tf/30);
heading = deg2rad(20) + (pi/3)*sin(2*pi*tf/60) + 0.15*sin(2*pi*tf/17);
x = cumtrapz(tf, speed .* cos(heading));
y = cumtrapz(tf, speed .* sin(heading));

% Sample at the recording rate with small timestamp jitter
t = (0:1/fs:T)';
t(2:end-1) = t(2:end-1) + 0.01*randn(numel(t)-2, 1);

xs = interp1(tf, x, t) + sigma_pos*randn(size(t));
ys = interp1(tf, y, t) + sigma_pos*randn(size(t));

writetable(table(t, xs, ys, 'VariableNames', {'t', 'x', 'y'}), filename);
fprintf('Demo track written to: %s (%d samples)\n', filename, numel(t));
end