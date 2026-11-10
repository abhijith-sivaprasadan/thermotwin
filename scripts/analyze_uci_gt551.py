#!/usr/bin/env python3
"""Physics-informed operating-condition residual study on genuine UCI #551 data.

Uses observed TEY (source label MWh, aggregation semantics unresolved), not
invented plant power. This is condition adjustment via measured covariates,
NOT a validated thermodynamic digital twin, fault diagnosis or pass-off test.

Data: one turbine, published within-year order, 2011-2013 fit vs 2014-2015
untouched holdout. No exact timestamps and no genuine fault labels exist.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
from pathlib import Path

import numpy as np

T_REF = 288.15  # K, standard reference temperature
P_REF = 101325.0  # Pa, standard reference pressure
T_TIT_SCALE = 1400.0  # K nondimensional scaling only, NOT OEM firing reference
COLUMNS = ("ambient_flow_availability", "inlet_filter_loss_fraction",
           "turbine_temperature_ratio", "turbine_temperature_drop_fraction")


def physics_features(values: dict) -> list[float]:
    """Dimensionless physically interpretable covariates, not a heat-rate model.

    p1 = p_ambient - dp_filter; under constant corrected inlet flow,
    mdot_ambient/mdot_reference ~ (p1/p_ref)*sqrt(T_ref/T_ambient).
    This is a throughput *availability factor*, not measured mass flow.
    w_t ~ cp_gas*(TIT-TAT) for an idealized adiabatic turbine, motivating
    the temperature-drop ratio; no shaft work is inferred without cp and flow.
    """
    Ta = float(values["AT"]) + 273.15
    Pa = float(values["AP"]) * 100.0
    dP = float(values["AFDP"]) * 100.0
    Tit = float(values["TIT"]) + 273.15
    Tat = float(values["TAT"]) + 273.15
    if not all(math.isfinite(z) for z in (Ta, Pa, dP, Tit, Tat)):
        raise ValueError("Nonfinite recorded channel")
    if Ta <= 0 or Pa <= 0 or dP < 0 or dP >= Pa or Tat <= 0 or Tit <= Tat:
        raise ValueError("Inconsistent observed thermodynamic boundary")
    inlet_p = Pa - dP
    available = (inlet_p / P_REF) * math.sqrt(T_REF / Ta)
    dp_fraction = dP / Pa
    tit_fraction = Tit / T_TIT_SCALE
    temperature_drop = (Tit - Tat) / Tit
    return [available, dp_fraction, tit_fraction, temperature_drop]


def fit_normalizer(x_train: np.ndarray, y_train: np.ndarray):
    x_train = np.asarray(x_train, dtype=float)
    y_train = np.asarray(y_train, dtype=float)
    if x_train.ndim != 2 or x_train.shape[1] != len(COLUMNS):
        raise ValueError("Physical feature matrix has wrong dimension")
    if y_train.ndim != 1 or len(y_train) != len(x_train) or len(y_train) < 20:
        raise ValueError("Invalid train target length")
    mean = x_train.mean(axis=0)
    scale = x_train.std(axis=0, ddof=1)
    if not np.isfinite(scale).all() or (scale <= 1e-10).any():
        raise ValueError("Insufficient variation in measured training channels")
    centered = (x_train - mean) / scale
    regressor = np.column_stack([np.ones(len(centered)), centered])
    beta, _residual, rank, singular = np.linalg.lstsq(regressor, y_train, rcond=None)
    if rank != regressor.shape[1]:
        raise ValueError("Operating-condition covariates lack independent rank")
    return mean, scale, beta


def predict(x: np.ndarray, mean, scale, beta):
    xx = np.asarray(x, dtype=float)
    return np.column_stack([np.ones(len(xx)), (xx - mean) / scale]) @ beta


def stats_by_year(residual, year, threshold):
    sample = np.asarray(residual, dtype=float)
    if len(sample) < 2:
        raise ValueError("Empty/insufficient annual residual sequence")
    t = np.arange(len(sample), dtype=float) / 1000.0
    # Descriptive slope per 1,000 published consecutive records; not a time
    # trend in hours/days because missing original timestamps/gaps.
    slope = float(np.polyfit(t, sample, deg=1)[0])
    return {
        "year": int(year), "rows": int(len(sample)),
        "mean_error_in_source_TEY_units": float(np.mean(sample)),
        "rmse_in_source_TEY_units": float(np.sqrt(np.mean(sample ** 2))),
        "mae_in_source_TEY_units": float(np.mean(np.abs(sample))),
        "median_error_in_source_TEY_units": float(np.median(sample)),
        "fraction_above_training_3sigma_in_absolute_residual": float(
            np.mean(np.abs(sample) > threshold)
        ),
        "residual_slope_per_1000_published_rows": slope,
    }


def load_year(data_dir: Path, year: int, verified_manifest: dict):
    entry = verified_manifest["years"].get(str(year))
    if not entry or entry.get("rows") is None:
        raise ValueError(f"Year {year} missing from provenance manifest")
    source = data_dir / entry["audited_csv"]
    import hashlib
    if hashlib.sha256(source.read_bytes()).hexdigest() != entry["audited_csv_sha256"]:
        raise ValueError(f"Audited source SHA mismatch for {year}")
    features, target = [], []
    with source.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader, start=1):
            if int(row["year"]) != year or int(row["within_year_row"]) != i:
                raise ValueError("Original within-year row order/identity corrupted")
            features.append(physics_features(row))
            target.append(float(row["TEY"]))
    if len(features) != entry["rows"]:
        raise ValueError("Year count mismatch")
    values = np.asarray(features, dtype=float)
    measured = np.asarray(target, dtype=float)
    if not np.isfinite(measured).all():
        raise ValueError("Non-finite real TEY values")
    return values, measured


def run(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data-dir", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    a = ap.parse_args(argv)
    manifest = json.loads((a.data_dir / "manifest.json").read_text(encoding="utf-8"))
    if (manifest.get("doi") != "10.24432/C5WC95" or
            manifest.get("total_rows") != 36733 or
            manifest.get("number_of_turbines") != 1):
        raise ValueError("Wrong source dataset/provenance")
    per_year = {year: load_year(a.data_dir, year, manifest) for year in range(2011, 2016)}
    train_x = np.concatenate([per_year[y][0] for y in (2011, 2012, 2013)])
    train_y = np.concatenate([per_year[y][1] for y in (2011, 2012, 2013)])
    means, scales, beta = fit_normalizer(train_x, train_y)
    train_residual = train_y - predict(train_x, means, scales, beta)
    train_sigma = float(np.std(train_residual, ddof=1))
    if train_sigma <= 0 or not math.isfinite(train_sigma):
        raise ValueError("Training residual sigma invalid")
    train_lag1 = float(np.corrcoef(train_residual[:-1], train_residual[1:])[0, 1])
    if not math.isfinite(train_lag1):
        raise ValueError("Training residual autocorrelation invalid")
    annual = {}
    for year, (x, y) in per_year.items():
        r = y - predict(x, means, scales, beta)
        annual[str(year)] = stats_by_year(r, year, 3.0 * train_sigma)
    hold_y = np.concatenate([per_year[y][1] for y in (2014, 2015)])
    hold_pred = np.concatenate([predict(per_year[y][0], means, scales, beta) for y in (2014, 2015)])
    hold_residual = hold_y - hold_pred
    report = {
        "schema": "thermotwin.uci551.physics_condition_residual.v1",
        "source_dataset": "UCI 551", "doi": manifest["doi"],
        "source_zip_sha256": manifest["original_zip_sha256"],
        "source_license": "CC BY 4.0",
        "source_version": os.environ.get("GITHUB_SHA", "local-not-tagged"),
        "turbine_count": 1, "measured_observations": int(len(train_y) + len(hold_y)),
        "fit_years": [2011, 2012, 2013], "untouched_evaluation_years": [2014, 2015],
        "target_label": "TEY", "target_units": "MWh as labelled at UCI; interpretation requires review",
        "measured_gt_power_MW_claimed": False,
        "not_a_pass_off_or_known_fault_dataset": True,
        "physical_covariates": {
            "column_order": list(COLUMNS),
            "ambient_flow_availability": "(P_amb - dP_filter)/101325 * sqrt(288.15/T_amb_K)",
            "inlet_filter_loss_fraction": "dP_filter/P_amb",
            "turbine_temperature_ratio": "TIT_K/1400; 1400 K is scaling only",
            "turbine_temperature_drop_fraction": "(TIT_K - TAT_K)/TIT_K",
            "pressure_conversion": "AP and AFDP mbar * 100 -> Pa",
            "temperature_conversion": "AT, TIT and TAT Celsius +273.15 -> K",
            "cautions": "No mass flow, fuel rate, compressor PR or mechanical work estimated; CDP units remain ambiguous",
        },
        "condition_adjustment": {
            "method": "OLS on independent physical covariates using only 2011-2013",
            "trained_center": means.tolist(), "trained_scale": scales.tolist(),
            "coefficient_intercept_and_standardized_slopes": beta.tolist(),
            "training_residual_std_in_TEY_units": train_sigma,
            "training_residual_lag1_across_published_rows": train_lag1,
            "flag_condition": "|residual| > 3 * train residual sigma; diagnostic only, NOT verified fault",
        },
        "annual_observed_residual_statistics": annual,
        "holdout": {
            "rows": int(len(hold_residual)),
            "rmse_source_TEY_units": float(np.sqrt(np.mean(hold_residual ** 2))),
            "mae_source_TEY_units": float(np.mean(np.abs(hold_residual))),
            "mean_bias_source_TEY_units": float(np.mean(hold_residual)),
            "absolute_3sigma_exceedance_fraction": float(
                np.mean(np.abs(hold_residual) > 3 * train_sigma)
            ),
        },
        "limitations": [
            "One turbine only; no production engine fleet or measured pass-off population",
            "No genuine fault/maintenance labels; flags cannot be classified true malfunctions",
            "Exact observation timestamps are not supplied; published row order is not a continuous hourly clock",
            "OLS residuals are not fully corrected site performance or ASME/ISO guarantee acceptance",
            "Autocorrelation can invalidate naive 3sigma false-alarm interpretation",
            "TEY labelled MWh; hourly-aggregate definition requires independent source confirmation",
            "Source CDP pressure units seem ambiguous; excluded from physics features",
            "No measured fuel flow, mass flow, heat rate, or manufacturer component map",
        ],
    }
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"UCI real observed records: {report['measured_observations']}; one turbine")
    print(f"Untouched {report['holdout']['rows']} records (2014-2015): TEY RMSE={report['holdout']['rmse_source_TEY_units']:.4f} source units; MAE={report['holdout']['mae_source_TEY_units']:.4f}")
    print(f"Train residual lag-1 correlation: {train_lag1:.4f} (naive control flags are NOT independent fault labels)")
    print(f"Recorded source-backed analysis at {a.output}")


if __name__ == "__main__":
    run()
