# MATLAB Quantum Navigation & Positioning Analysis

A simplified MATLAB simulation and analysis tool for a **quantum-sensor-based navigation device**. It connects classical vehicle motion, a basic two-level quantum phase sensor, dead-reckoning estimation, and engineering performance analysis in one pipeline.

> **Scope:** this is a *simplified* model for learning and analysis (2D motion, a two-level quantum system, single-axis phase sensing). It is **not** a full simulation of a commercial quantum navigation device, and it does not model a quantum computer.

## Features

- **Motion model:** 2D ground-truth trajectory (position, velocity, acceleration, heading, travelled distance) with sinusoidal, constant, or piecewise acceleration profiles.
- **Quantum sensor model:** two-level system with pi/2 pulses, phase evolution, and projective measurement. Includes shot noise, phase noise, bias, and scale-factor error.
- **Estimation:** probability -> phase -> acceleration -> speed -> position by numerical integration, with a heading reference.
- **Performance analysis:** RMSE, maximum error, drift exponent, sensor noise vs. theory, and sensitivity/robustness sweeps.
- **Real-case data:** loads a recorded track (CSV/XLSX) and runs it through the same pipeline.
- **GUI:** interactive parameter editing, plots, summary, and export.

## Pipeline

```
Phase 1  setup_params     Scenario, environment, sensor parameters
   |
Phase 2  true_motion      Classical kinematics -> ground-truth trajectory
   |      (or load_real_data for a recorded track)
Phase 3  quantum_sensor   Acceleration -> phase -> quantum state -> probability -> counts
   |
Phase 4  estimate_nav     Probability -> acceleration -> speed -> position
   |
Phase 5  analyze_perf     Errors, RMSE, drift, sensitivity, robustness
```

## File structure

```
.
├── main.m                  Entry point (simulation / real / gui modes)
├── quantum_nav_gui.m       Interactive GUI
├── setup_params.m          Phase 1 - scenario definition
├── true_motion.m           Phase 2 - classical motion model
├── quantum_sensor.m        Phase 3 - quantum sensor model
├── estimate_nav.m          Phase 4 - navigation estimation
├── analyze_perf.m          Phase 5 - performance analysis
├── load_real_data.m        Real-case data loader
├── make_demo_real_data.m   Generates a synthetic demo track (CSV)
├── README.md
├── references.md
├── LICENSE.md
└── .gitignore
```

## Requirements

- MATLAB **R2020a or newer** (GUI uses `uifigure`, `uigridlayout`, `yline`/`xline` on `uiaxes`).
- No special toolbox is required. If the Statistics and Machine Learning Toolbox is available, `binornd` is used for shot noise; otherwise a Gaussian approximation is used.

## Quick start

1. Put all `.m` files in one folder and make it the current folder in MATLAB.
2. Run the simulation:

```matlab
   main
```

3. Open the GUI:

```matlab
   quantum_nav_gui
```

4. Run a real-data case: set `mode = 'real'` in `main.m` (a demo track is generated automatically if the file is missing), or choose **Real data (CSV)** in the GUI.

For a fast run without sensitivity sweeps, set `run_opts.do_sweep = false` in `main.m`.

## Models

Kinematics (Phase 2):

```
p(k+1) = p(k) + v(k)*dt + 0.5*a(k)*dt^2
v(k+1) = v(k) + a(k)*dt
```

Quantum sensor (Phase 3), two-level system `|psi> = alpha|0> + beta|1>`:

```
phi = k_eff * a * T^2                 (acceleration-induced phase)
P   = (1 + sin(phi)) / 2              (operating at mid-fringe, sign of a preserved)
```

Estimation (Phase 4):

```
phi_hat = asin(2*P_meas - 1)
a_hat   = phi_hat / (k_eff * T^2)
a_hat -> v_hat -> p_hat               (numerical integration)
```

Performance (Phase 5):

```
e_k  = p_true,k - p_est,k
RMSE = sqrt( (1/N) * sum_k ||e_k||^2 )
```

## Default scenario

| Parameter | Value |
|---|---|
| Duration / sample interval | 60 s / 0.01 s |
| Laser wavelength (Rb-87 D2) | 780 nm |
| Interrogation time `T` | 0.5 ms |
| Atoms per shot | 1e5 |
| Extra phase noise | 0.01 rad |
| Constant sensor bias | 1e-3 m/s^2 |
| Phase sensitivity | about 4.03 rad per (m/s^2) |
| Unambiguous range | about +/- 0.39 m/s^2 |

Example output for the default scenario: position RMSE about 0.87 m, final position error about 1.93 m (1.9 % of travelled distance), error growth close to `t^2` (bias-dominated drift).

## Real-case data format

A CSV or XLSX file with a time column and either metric or geographic positions (column names are case-insensitive):

| Columns | Meaning |
|---|---|
| `t` (or `time`, `timestamp`) | time in seconds |
| `x`, `y` (or `east`, `north`) | position in metres |
| `lat`, `lon` | position in degrees (converted to local metres) |

Notes:

- If time is in milliseconds, set `real_opts.time_scale = 1e-3`.
- The recorded track is smoothed (`smooth_s`) and used as the reference; velocity and acceleration are derived from it.
- The reference is fed into the **simulated** quantum sensor. This validates the pipeline on realistic motion; it is not data from a physical quantum device.
- With `auto_T = true`, the interrogation time is reduced so the data fits the unambiguous range (lower sensitivity, wider range).

## Limitations

- Single sensitive axis (along the heading); no 3D motion or rotation sensing.
- Heading comes from an external reference with simple Gaussian noise.
- Integration-only estimator: error grows roughly as `t^2` without aiding sensors.
- Simplified noise model (shot noise, white phase noise, constant bias and scale error); no vibration or magnetic-field coupling in the sensor model.

## Roadmap

- Kalman filter with intermittent position aiding (e.g. GNSS) to bound drift.
- Two-axis and 3D sensing, gyroscope model.
- Dead-time, Raman-pulse timing, and vibration-noise models.

## References and license

See [references.md](references.md) for background reading and [LICENSE.md](LICENSE.md) for license terms (MIT).