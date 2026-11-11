# Genuine measured-time micro gas turbine dynamic prediction (UCI #994)

**Stage 2 of ThermoTwin-F's real-data roadmap** (2026-11-11). This predicts real measured **electrical power in watts** from a known control-voltage trajectory at physically measured time in seconds. It is **not** a retrofit of an industrial Siemens turbine or a thermodynamic Brayton-cycle physics model.

## Original real experiments

[UCI Micro Gas Turbine Electrical Energy Prediction](https://doi.org/10.24432/C58S4T), by Bielski/Kottonau and collaborators, is an experimental 3 kW commercial micro gas turbine with **71,225 real time-series samples across eight independent experiments**, approximately 1 second apart and lasting 1.8–3.3 h each, licensed **CC BY 4.0**. There is a physically meaningful relative time-in-seconds axis, input control voltage (V), and measured generated electrical power (W). The source's explicit frozen split is:

- Training experiments: **1, 9, 20, 21, 23, 24**.
- Untouched source test experiments: **4 and 22**.

Do not mix this small machine with UCI #551 (one utility-scale real turbine in Turkey with only annual order) or ThermoTwin-F's generic 30 MW reference.

## Causal prediction problem

Predict the **future electrical-power response when a control voltage command trajectory is supplied**. Use a simple, transparent, bounded first-order dynamical model:
\[
y_{k} = (1-\alpha_k) y_{k-1} + \alpha_k\,\operatorname{clip}(a+b u_k+c u_k^2,0,P_{\max,\mathrm{train}}),
\quad \alpha_k = 1-\exp[-(t_k-t_{k-1})/\tau].
\]

Here `u_k` is an **intended known/issued control voltage**, `y` is *predicted* electrical power (W), `t` is source relative time (s), and `tau` is a fitted lag (s). The clip is a declared modelling bound, **not** a certified turbine safety envelope.

- Fit `a,b,c` using only source training experiments. Select `tau` by **leave-one-training-experiment-out, fully open-loop** scoring (not with test data).
- In each test experiment, initialize the model to exactly **one actual first measured power value** at the start. This point is **not scored**. From the second point onward, no test target output is used to advance or correct predictions; only the predeclared voltage commands are inputs.
- Compare untouched test traces with an independent **static voltage-to-power quadratic baseline** fitted on the same training experiments. Report aggregate/experiment-level RMSE, MAE, bias, sampling count, source SHA, temperature constant and learned coefficients.
- Mark voltage values outside the observed training-command range as extrapolation risk, not fault diagnosis.
- This setup is a **known-input open-loop prediction**. It does not forecast future unknown commands, future disturbances, turbine faults, or electrical power of an engine whose identification has not been performed. It provides a meaningful time axis but not independently synchronized calendar time.

## Run

~~~powershell
git pull --ff-only origin main
python -m pip install numpy==2.2.6
python -m unittest scripts.test_uci994_microgt -v
python scripts/fetch_uci994_microgt.py --output-dir build/uci994
python -m scripts.forecast_uci994_microgt --data-dir build/uci994 --out build/uci994/forecast
~~~

### Reproduce offline using original archived data

~~~powershell
python scripts/fetch_uci994_microgt.py --original-zip build/uci994/uci994_original.zip --output-dir build/uci994
python -m scripts.forecast_uci994_microgt --data-dir build/uci994 --out build/uci994/forecast
~~~

Outputs:
- `build/uci994/manifest.json`: exact original source archive and member hashes, counts, time and units, split, audited CSV names; source ZIP retained for reproduction.
- `build/uci994/forecast/heldout_microturbine_power_forecast.csv`: all actual source time/command/power readings for test 4 and 22, open-loop predictions, static baseline, residual and train-range flag.
- `build/uci994/forecast/forecast_report.json`: fitted lag/coefficients and independently reserved experiment RMSE.
- `build/uci994/forecast/real_microturbine_power_forecast.html`: self-contained measured versus predicted trace viewer.

## Original measured-data evaluation (first independent-source CI run)

Original UCI ZIP SHA-256 verified and pinned:
`9a5b3fa76e24076c914b73378467539a550641e280015f5e2e88510b493f530f`.
The actual initial source fetch (real observations, not fixtures) reported:

- Training-only CV selected **tau = 128 s**.
- On independently reserved test experiments 4 and 22, **18,283 scored samples** after excluding one first initial measurement per experiment.
- **Open-loop dynamic RMSE 293.290 W** versus **static voltage baseline RMSE 377.689 W** (about 22% lower RMSE). These results are on a **3-kW nominal turbine**, not the 30 MW generic cycle. There is no guaranteed model advantage on another turbine, unobserved input schedule, or safety-critical transient.
- Source, prediction, and model outputs are archived in the passing real-source CI job. This result is external experiment performance only, **not field-certified physical GT thermodynamic validation**.

The generated `real_microturbine_power_forecast.html` also provides an offline interactive trace view with actual experiment time (seconds), observed measured power, open-loop predicted power, the baseline and command voltage at the selected point.

## Limitations and next stage

This is a measured electrical power dynamic response model of a **3 kW commercial micro turbine**. The source lacks measured internal compressor/turbine station pressure/temperature, fuel mass flow, component maps, quantified instrument uncertainties, and industrial hardware metadata. It cannot validate ThermoTwin-F's complete GT cycle, turbine trip sequence, combustion instability, rotor overspeed or component life. Stage 3 must explicitly separate **microturbine observed dynamic-system identification** (which this measured dataset supports) from a **full physical Brayton/industrial-machine calibration** (which needs much more data).

The genuine-source CI job verifies all raw/audited sample counts, source and generated artifact hashes and the untouched test split. Software fixture tests use artificial equations **only for code behavior**, never report their errors as turbine performance.
