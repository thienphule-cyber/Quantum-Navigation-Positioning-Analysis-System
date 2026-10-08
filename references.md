# References

Background reading for the physics, navigation, and estimation concepts used in this project. Please verify volume, page, and edition details before citing formally.

## Atom interferometry and quantum inertial sensing

1. M. Kasevich and S. Chu, "Atomic interferometry using stimulated Raman transitions," *Physical Review Letters* **67**, 181 (1991).
2. A. Peters, K. Y. Chung, and S. Chu, "Measurement of gravitational acceleration by dropping atoms," *Nature* **400**, 849-852 (1999).
3. A. Peters, K. Y. Chung, and S. Chu, "High-precision gravity measurements using atom interferometry," *Metrologia* **38**, 25 (2001).
4. T. L. Gustavson, P. Bouyer, and M. A. Kasevich, "Precision rotation measurements with an atom interferometer gyroscope," *Physical Review Letters* **78**, 2046 (1997).
5. A. D. Cronin, J. Schmiedmayer, and D. E. Pritchard, "Optics and interferometry with atoms and molecules," *Reviews of Modern Physics* **81**, 1051 (2009).
6. R. Geiger et al., "Detecting inertial effects with airborne matter-wave interferometry," *Nature Communications* **2**, 474 (2011).
7. B. Barrett et al., "Dual matter-wave inertial sensors in weightlessness," *Nature Communications* **7**, 13786 (2016).

## Quantum sensing and measurement

8. C. L. Degen, F. Reinhard, and P. Cappellaro, "Quantum sensing," *Reviews of Modern Physics* **89**, 035002 (2017).
9. V. Giovannetti, S. Lloyd, and L. Maccone, "Quantum-enhanced measurements: beating the standard quantum limit," *Science* **306**, 1330-1336 (2004).
10. M. A. Nielsen and I. L. Chuang, *Quantum Computation and Quantum Information*, Cambridge University Press (2000; 10th anniversary edition 2010).
11. D. A. Steck, "Rubidium 87 D Line Data," available online at steck.us/alkalidata.

## Quantum navigation systems

12. C. Jekeli, "Navigation error analysis of atom interferometer inertial sensor," *Navigation* **52**(1), 1-14 (2005).
13. B. Cheiney et al., "Navigation-compatible hybrid quantum accelerometer using a Kalman filter," *Physical Review Applied* **10**, 034030 (2018).

## Inertial navigation and estimation

14. D. H. Titterton and J. L. Weston, *Strapdown Inertial Navigation Technology*, 2nd ed., IET (2004).
15. P. D. Groves, *Principles of GNSS, Inertial, and Multisensor Integrated Navigation Systems*, 2nd ed., Artech House (2013).
16. R. E. Kalman, "A new approach to linear filtering and prediction problems," *Journal of Basic Engineering* **82**(1), 35-45 (1960).
17. Y. Bar-Shalom, X. R. Li, and T. Kirubarajan, *Estimation with Applications to Tracking and Navigation*, Wiley (2001).

## How these map to the project

| Project part | Relevant references |
|---|---|
| Phase sensing, `phi = k_eff * a * T^2` | 1, 2, 3, 5 |
| Two-level state, pulses, measurement probability | 8, 10 |
| Shot noise and sensitivity limits | 8, 9 |
| Rb-87 wavelength and constants | 11 |
| Error growth, drift, dead reckoning | 12, 14, 15 |
| Planned Kalman filter upgrade | 13, 16, 17 |