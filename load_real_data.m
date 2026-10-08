function [params, truth, info] = load_real_data(filename, params, opts)
% LOAD_REAL_DATA  Real-case data loader.
%   Reads a recorded vehicle track from a CSV/XLSX file, resamples it to
%   the simulation time step, and builds the same 'truth' struct that
%   true_motion() produces, so Phases 3-5 run unchanged.
%
%   Required columns (names are case-insensitive):
%       time     : t | time | timestamp | time_s | seconds   [s]
%       position : x,y (or east,north) in metres   OR   lat,lon in degrees
%
%   Input : filename - path to the data file
%           params   - struct from setup_params()
%           opts     - optional struct:
%               opts.dt         resample interval [s]        (default params.sim.dt)
%               opts.smooth_s   smoothing window [s]         (default 2.0)
%               opts.time_scale multiply time column by this (default 1; use 1e-3 for ms)
%               opts.auto_T     shrink T_int to fit data     (default true)
%               opts.margin     range margin for auto_T      (default 1.25)
%               opts.min_speed  min speed for valid heading  (default 0.5 m/s)
%               opts.t_max      crop data after this time    (default Inf)
%   Output: params - updated (time base, initial state, T_int)
%           truth  - reference trajectory (smoothed, derived from position)
%           info   - data summary
%
%   Usage:  [params, truth, info] = load_real_data('track.csv', params);

%% ---------------- Options ----------------
if nargin < 3 || isempty(opts), opts = struct(); end
opts = set_default(opts, 'dt',         params.sim.dt);
opts = set_default(opts, 'smooth_s',   2.0);
opts = set_default(opts, 'time_scale', 1);
opts = set_default(opts, 'auto_T',     true);
opts = set_default(opts, 'margin',     1.25);
opts = set_default(opts, 'min_speed',  0.5);
opts = set_default(opts, 't_max',      Inf);

if exist(filename, 'file') ~= 2
    error('load_real_data:noFile', 'File not found: %s', filename);
end

%% ---------------- Read table and find columns ----------------
tbl   = readtable(filename);
t_raw = find_col(tbl, {'t', 'time', 'timestamp', 'time_s', 'seconds'});
x_raw = find_col(tbl, {'x', 'east', 'e', 'x_m', 'easting'});
y_raw = find_col(tbl, {'y', 'north', 'n', 'y_m', 'northing'});
lat   = find_col(tbl, {'lat', 'latitude'});
lon   = find_col(tbl, {'lon', 'lng', 'long', 'longitude'});

if isempty(t_raw)
    error('load_real_data:noTime', 'No time column found (t, time, timestamp, ...).');
end
if ~isempty(x_raw) && ~isempty(y_raw)
    px = x_raw; py = y_raw; isgeo = false;
elseif ~isempty(lat) && ~isempty(lon)
    px = lon;   py = lat;   isgeo = true;
else
    error('load_real_data:noPos', 'Need columns (x,y) in metres or (lat,lon) in degrees.');
end

%% ---------------- Clean: remove NaN, sort, remove duplicate times ----------------
t  = t_raw(:) * opts.time_scale;
ok = isfinite(t) & isfinite(px) & isfinite(py);
t  = t(ok);  px = px(ok);  py = py(ok);

[t, ia] = unique(t, 'sorted');
px = px(ia);  py = py(ia);
t  = t - t(1);

keep = t <= opts.t_max;
t = t(keep);  px = px(keep);  py = py(keep);

if numel(t) < 10 || t(end) < 2
    error('load_real_data:tooShort', 'Not enough data (need >= 10 samples and >= 2 s).');
end

%% ---------------- Convert to local metric coordinates ----------------
if isgeo
    R_earth = 6378137;                                % Earth radius [m]
    lat0 = py(1);  lon0 = px(1);
    X = R_earth * deg2rad(px - lon0) * cosd(lat0);    % east  [m]
    Y = R_earth * deg2rad(py - lat0);                 % north [m]
    px = X;  py = Y;
else
    px = px - px(1);                                  % start at the origin
    py = py - py(1);
end

dt_raw = median(diff(t));
if dt_raw > opts.smooth_s
    warning('load_real_data:sparse', ...
        'Raw sampling interval (%.2f s) is longer than the smoothing window.', dt_raw);
end

%% ---------------- Resample to uniform time base ----------------
dt = opts.dt;
tu = (0:dt:t(end))';
N  = numel(tu);
pxu = interp1(t, px, tu, 'linear');
pyu = interp1(t, py, tu, 'linear');

%% ---------------- Smooth and differentiate ----------------
w = max(3, 2*floor(opts.smooth_s / dt / 2) + 1);      % odd window length [samples]
p = [movmean(pxu, w), movmean(pyu, w)];               % smoothed position [m]

v = [gradient(p(:,1), dt), gradient(p(:,2), dt)];     % velocity [m/s]
v = movmean(v, w);
a = [gradient(v(:,1), dt), gradient(v(:,2), dt)];     % acceleration [m/s^2]

speed = sqrt(sum(v.^2, 2));
hd = atan2(v(:,2), v(:,1));
hd(speed < opts.min_speed) = NaN;                     % heading undefined at low speed
if all(isnan(hd))
    error('load_real_data:noHeading', 'Speed never exceeds %.2f m/s.', opts.min_speed);
end
hd = fillmissing(hd, 'nearest');
hd = unwrap(hd);

distance = [0; cumsum(sqrt(sum(diff(p).^2, 2)))];

%% ---------------- Pack truth ----------------
truth.t        = tu;
truth.a_nom    = a;
truth.a        = a;
truth.v        = v;
truth.p        = p;
truth.speed    = speed;
truth.heading  = hd;
truth.distance = distance;

%% ---------------- Update params ----------------
params.sim.dt      = dt;
params.sim.t       = tu;
params.sim.N       = N;
params.sim.t_total = tu(end);
params.vehicle.p0       = p(1, :)';
params.vehicle.v0       = v(1, :)';
params.vehicle.speed0   = speed(1);
params.vehicle.heading0 = hd(1);
params.vehicle.accel.type = 'real data';

%% ---------------- Adapt interrogation time to the data range ----------------
u       = [cos(hd), sin(hd)];
a_along = sum(a .* u, 2);
srt     = sort(abs(a_along));
a_pk    = srt(max(1, ceil(0.999 * N)));               % 99.9th percentile [m/s^2]
a_need  = opts.margin * (a_pk + abs(params.sensor.bias));

T_old = params.sensor.T_int;
T_fit = sqrt((pi/2) / (params.sensor.k_eff * a_need));
if opts.auto_T && T_fit < T_old
    params.sensor.T_int = T_fit;
end
params.derived.phase_sensitivity = params.sensor.k_eff * params.sensor.T_int^2;
params.derived.a_max = (pi/2) / params.derived.phase_sensitivity;

%% ---------------- Info ----------------
[~, nm, ext] = fileparts(filename);
info.file   = [nm ext];
info.n_raw  = numel(t);
info.dt_raw = dt_raw;
info.a_peak = a_pk;
info.T_old  = T_old;
info.T_new  = params.sensor.T_int;
info.a_max  = params.derived.a_max;

fprintf('=== Real data loaded ===\n');
fprintf('File             : %s (%d raw samples, median dt %.3f s)\n', info.file, info.n_raw, dt_raw);
fprintf('Resampled        : %.1f s, dt = %.3f s, N = %d\n', tu(end), dt, N);
fprintf('Travelled dist.  : %.1f m, max speed %.2f m/s\n', distance(end), max(speed));
fprintf('Peak along-track a: %.3f m/s^2\n', a_pk);
fprintf('Interrogation T  : %.3f ms -> %.3f ms (unambiguous +/- %.3f m/s^2)\n', ...
        T_old*1e3, params.sensor.T_int*1e3, params.derived.a_max);
end

%% =====================================================================
function s = set_default(s, name, value)
    if ~isfield(s, name), s.(name) = value; end
end

function col = find_col(tbl, aliases)
    names = lower(tbl.Properties.VariableNames);
    col = [];
    for k = 1:numel(aliases)
        j = find(strcmp(names, aliases{k}), 1);
        if ~isempty(j)
            c = tbl.(tbl.Properties.VariableNames{j});
            if isdatetime(c), c = seconds(c - c(1)); end
            if isduration(c), c = seconds(c); end
            col = double(c(:));
            return;
        end
    end
end