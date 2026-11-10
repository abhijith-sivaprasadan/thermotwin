# Real weather boundary ingestion (Open-Meteo)

**Status:** Implemented data acquisition and quality control; **not** a turbine performance model and **not** a compressor-flange instrumentation feed. See [TTF-PE-PMP-001](TTF_PE_MASTER_PLAN_v1.0.md) and issue [#19](https://github.com/abhijith-sivaprasadan/thermotwin/issues/19).

Open-Meteo permits open non-commercial research access and provides weather outputs under CC BY 4.0 with attribution. Consult [terms](https://open-meteo.com/en/terms) before any commercial use. Weather data by [Open-Meteo.com](https://open-meteo.com/).

## Why this is useful

A gas-turbine site performance calculation needs boundary conditions. A real geographically specified weather-model estimate is better than an invented 35 °C installation day, but it is **not** a measure of compressor flange pressure, inlet temperature, compressor inlet filter differential pressure, or an engine's measured output.

- [Historical weather archive](https://open-meteo.com/en/docs/historical-weather-api): ERA5 or ERA5-Land reanalysis. Archived meteorological model fields, hourly. A history of real past atmospheric conditions **estimated by reanalysis**, not a physical site sensor.
- [Forecast API](https://open-meteo.com/en/docs): current model-derived local weather estimates, not engine telemetry and not necessarily station measurements.
- We request **surface_pressure**, *not* sea-level-reduced pressure_msl. Surface pressure is given in hPa and converted to Pa; 2-m dry bulb °C is converted to K; relative humidity % is converted to a fraction. Relative humidity is retained but not applied to ThermoTwin's current dry-air property equations.
- Weather metadata: request URL, UTC validity and retrieval time, coordinates/grid point, chosen model, raw SHA-256, source type and units. Raw response can be retained for an independently reproducible case.

## Commands (Python standard library; no SDK)

Historical ERA5 source near the city of Lincoln, England (for a historical illustrative **location**, not a Siemens Energy facility or a specific turbine):

```sh
python scripts/open_meteo_boundary.py \
  --source archive --model era5 \
  --latitude 53.23 --longitude -0.54 \
  --valid-time 2025-10-01T12:00:00Z \
  --output build/weather/lincoln_era5_boundary.csv \
  --snapshot build/weather/lincoln_era5_raw.json
```

Current model-estimated weather at user-supplied coordinates (do not call it live sensor telemetry):

```sh
python scripts/open_meteo_boundary.py \
  --source forecast-current --model best_match \
  --latitude 53.23 --longitude -0.54 \
  --output build/weather/lincoln_forecast_current.csv \
  --snapshot build/weather/lincoln_forecast_raw.json
```

Replay a **previously collected** API response with no network call:

```sh
python scripts/open_meteo_boundary.py \
  --source archive --model era5 \
  --latitude 53.23 --longitude -0.54 \
  --valid-time 2025-10-01T12:00:00Z \
  --response-json build/weather/lincoln_era5_raw.json \
  --output build/weather/replayed_boundary.csv
```

The importer can optionally copy a separately documented existing 18-field engine model deck into a compatible case file (`--reference-case path.csv`), changing only atmospheric T/P/RH. This does **not** establish the validity of the hardware deck. A complete fixed-reference off-design power/heat-rate correction is tracked separately under [#13](https://github.com/abhijith-sivaprasadan/thermotwin/issues/13). **Do not use the generic simple-cycle `run` results at fixed air flow and pressure ratio as a substitute for site-performance prediction.**

## Data and fail-closed constraints

- Missing/null input, unrecognized units, nonfinite readings, wrong timezone/validity, missing surface pressure, incomplete hourly array and grossly implausible pressure/temperature/humidity cause explicit error rather than a zero/default value.
- Archive requests must name an hourly UTC validity time. Forecast-current obtains its own validity time from the response.
- The one-hour historical request in GitHub CI records its source payload and digest as a workflow artifact; it is a real external integration test but no evidence of measured turbine performance.
- To reproduce a case after an API revision, use the exact raw snapshot and SHA-256 stored in the manifest. The model's best-match grid point and forecasts can change across releases.
- Outputs are boundary observations or model estimates plus metadata. No fabricated plant power, heat rate, fuel usage, guarantees or engine IDs are generated.

## Governing boundary conversions

\[
T_{\rm input,K}=T_{\rm weather,^{\circ}C}+273.15,\qquad
p_{\rm surface,Pa}=100\,p_{\rm surface,hPa},\qquad
\phi=\frac{\mathrm{RH}_{\%}}{100}.
\]

These conversions are dimensional identities, not a site-performance correction. The current compressor inlet model further applies a separate assumed or measured fractional inlet pressure loss as \(p_1=p_{\rm ambient}(1-\Delta p_{\rm inlet,frac})\); exhaust backpressure requires its own actual boundary data. The inlet loss should not be inferred from weather alone.

## Verified external ingestion evidence (10 November 2026)

GitHub CI [run 42775612320](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42775612320), job **Real ERA5 weather boundary integration**, successfully fetched the 2025-10-01 12:00 UTC ERA5 hour for the Lincoln-area sample point, producing **T = 287.250 K (14.10 °C)** and **surface pressure = 102,390 Pa**. The raw JSON, metadata manifest and boundary CSV were uploaded as [real-era5-boundary-and-source artifact](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42775612320/artifacts/13743358194); the job asserted the exact raw response SHA-256 equals the manifest digest. These are genuine ERA5 reanalysis outputs, **not physical turbine readings, not Siemens site measurements and not an OEM-corrected power estimate**.

## Verification

```sh
python -m unittest scripts.test_open_meteo_boundary -v
```

The tests construct **mathematical/schema fixtures only** and are not presented as real weather or turbine measurements. The CI integration test uses a genuine Open-Meteo API response and retains the original response file; the API connection and successful execution must be verified from the specific workflow run before claiming real ingestion works.
