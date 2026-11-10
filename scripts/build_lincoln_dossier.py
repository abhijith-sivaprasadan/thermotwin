#!/usr/bin/env python3
"""Build a source-backed, strictly qualified engineering evidence dossier.

Inputs are artifacts from the *same* successful CI run:
  - original UCI #551 source, audited annual CSVs, held-out evaluation JSON;
  - original ERA5 API response, replay metadata, and Fortran site output.
No measured engine power is inferred from the weather model; no OEM accuracy
or guarantee is estimated. SVGs are generated from actual input artifacts.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import xml.etree.ElementTree as ET

SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def data(path: Path) -> dict:
    result = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(result, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return result


def single_csv(path: Path) -> dict:
    with path.open(encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != 1 or not rows[0] or any(value is None for value in rows[0].values()):
        raise ValueError(f"Expected exactly one complete CSV row: {path}")
    return rows[0]


def number(value: object, label: str, minimum: float | None = None) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{label}: boolean is not numeric")
    try:
        x = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label}: not numeric") from exc
    if not math.isfinite(x) or (minimum is not None and x <= minimum):
        raise ValueError(f"{label}: not finite/positive as required")
    return x


def close(a: float, b: float, label: str, rtol: float = 2e-5, atol: float = 2e-5):
    if not math.isclose(a, b, rel_tol=rtol, abs_tol=atol):
        raise ValueError(f"{label}: mathematical identity or source boundary mismatch")


def audit(uci: Path, weather: Path, reference: Path) -> dict:
    u = data(uci / "condition_residual_report.json")
    um = data(uci / "manifest.json")
    umzip = uci / "uci551_original.zip"
    uhash = digest(umzip)
    if (um.get("doi") != "10.24432/C5WC95" or
            um.get("number_of_turbines") != 1 or
            um.get("total_rows") != 36733 or
            um.get("original_zip_sha256") != uhash or
            u.get("source_zip_sha256") != uhash or
            u.get("doi") != um["doi"] or
            u.get("measured_observations") != 36733 or
            u.get("turbine_count") != 1 or
            u.get("fit_years") != [2011, 2012, 2013] or
            u.get("untouched_evaluation_years") != [2014, 2015] or
            u.get("holdout", {}).get("rows") != 14542 or
            u.get("measured_gt_power_MW_claimed") is not False or
            u.get("not_a_pass_off_or_known_fault_dataset") is not True):
        raise ValueError("UCI source/identity, train-test split or disclaimers failed")
    counts = 0
    years = um.get("years", {})
    for year in range(2011, 2016):
        entry = years[str(year)]
        relative = Path(entry["audited_csv"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("Audited UCI source path escapes input directory")
        path = uci / relative
        if digest(path) != entry["audited_csv_sha256"]:
            raise ValueError(f"UCI {year} annual CSV source digest mismatch")
        counts += entry["rows"]
    if counts != 36733:
        raise ValueError("UCI annual counts disagree with original source manifest")

    hold = u["holdout"]
    rmse = number(hold["rmse_source_TEY_units"], "actual held-out RMSE", 0)
    baseline = number(hold["training_mean_baseline_rmse_source_TEY_units"],
                      "training-mean baseline RMSE", 0)
    lag = number(u["condition_adjustment"]["training_residual_lag1_within_year_demeaned"],
                 "within-year lag-1")
    support = number(
        u["heldout_covariate_support"]["heldout_fraction_outside_any_feature"],
        "support fraction")
    band = u["heldout_adjacent_row_resampling_sensitivity"]["sensitivity"]["64"][
        "rmse_central_95pct_resampling_range"
    ]
    lo, hi = (number(z, "resampling percentile", 0) for z in band)
    if not (-1 <= lag <= 1 and 0 <= support <= 1 and lo <= hi and
            u["heldout_adjacent_row_resampling_sensitivity"]["block_lengths_published_rows"]
            == [32, 64, 128]):
        raise ValueError("UCI dependence diagnostics inconsistent")

    raw = weather / "lincoln_era5_raw.json"
    wm = data(weather / "lincoln_era5_boundary.manifest.json")
    replay = data(weather / "lincoln_era5_model_boundary.manifest.json")
    boundary = single_csv(weather / "lincoln_era5_boundary.csv")
    site = single_csv(weather / "lincoln_era5_site_model.csv")
    model_case = single_csv(weather / "lincoln_era5_model_boundary_case.csv")
    whash = digest(raw)
    for item in (wm, replay):
        if (item.get("raw_response_sha256") != whash or
                item.get("weather_source") != "Open-Meteo" or
                item.get("meteo_type") != "reanalysis" or
                item.get("observed_engine_measurement") is not False or
                item.get("flange_condition_measured") is not False or
                item.get("humidity_used_in_thermotwin_physics") is not False or
                item.get("valid_time_utc") != "2025-10-01T12:00:00Z"):
            raise ValueError("Weather source, timing, provenance or type mismatch")
    if (replay.get("humidity_mode") != "dry_air_approximation_requested_by_operator" or
            replay.get("humidity_correction_performed") is not False or
            replay.get("hardware_deck_sha256") != digest(reference) or
            replay.get("hardware_calibration_not_verified_by_weather_data") is not True or
            wm.get("raw_response_sha256") != boundary.get("raw_sha256") or
            boundary["valid_time_utc"] != wm["valid_time_utc"]):
        raise ValueError("Weather replay did not preserve original dry-air/data provenance")
    t = number(boundary["temperature_K"], "ERA5 T", 0)
    p = number(boundary["surface_pressure_Pa"], "ERA5 P", 0)
    rh = number(boundary["relative_humidity_fraction"], "ERA5 RH")
    if not 0 <= rh <= 1:
        raise ValueError("ERA5 RH outside fraction range")
    close(t, number(site["site_ambient_T_K"], "site T"), "weather/site T")
    close(p, number(site["site_ambient_P_Pa"], "site P"), "weather/site P")
    close(t, number(model_case["ambient_T_K"], "model input T"), "weather/model T")
    close(p, number(model_case["ambient_P_Pa"], "model input P"), "weather/model P")
    close(rh, number(replay["actual_weather_relative_humidity_fraction"], "retained RH"),
          "actual weather RH preservation")
    close(number(model_case["relative_humidity"], "model-input RH"),
          number(replay["model_input_relative_humidity_fraction"], "declared RH"),
          "model RH provenance")
    if site["valid"] != "1":
        raise ValueError("Fortran site comparison rejected model site input")
    ref_power = number(site["reference_net_power_MW"], "model reference power", 0)
    site_power = number(site["site_net_power_MW"], "model site power", 0)
    ratio = number(site["power_derate_ratio"], "model power ratio", 0)
    pcorr = number(site["power_correction_ref_per_site"], "power correction", 0)
    hr_ref = number(site["reference_heat_rate_kJ_kWh"], "reference HR", 0)
    hr_site = number(site["site_heat_rate_kJ_kWh"], "site HR", 0)
    hcorr = number(site["heat_rate_correction_ref_per_site"], "HR correction", 0)
    flow_ref = number(site["reference_exhaust_flow_kg_s"], "reference flow", 0)
    flow_site = number(site["site_exhaust_flow_kg_s"], "site flow", 0)
    flow_corr = number(site["exhaust_flow_correction_ref_per_site"], "flow correction", 0)
    temp_ref = number(site["reference_exhaust_T_K"], "reference exhaust T", 0)
    temp_site = number(site["site_exhaust_T_K"], "site exhaust T", 0)
    temp_corr = number(site["exhaust_T_additive_ref_minus_site_K"], "exhaust T offset")
    for x, y, label in (
            (ratio, site_power/ref_power, "site power"),
            (pcorr, ref_power/site_power, "power round trip"),
            (hcorr, hr_ref/hr_site, "heat rate correction"),
            (flow_corr, flow_ref/flow_site, "exhaust flow correction"),
            (temp_corr, temp_ref-temp_site, "exhaust temperature correction")):
        close(x, y, label)
    if not 0.5 < ratio < 1.5:
        raise ValueError("Model correction outside explicitly supported display envelope")
    return {
        "uci_report": u, "uci_manifest": um, "uci_rmse": rmse,
        "uci_baseline_rmse": baseline, "uci_lag": lag, "uci_support": support,
        "uci_block64_range": [lo, hi],
        "weather_manifest": wm, "weather_replay": replay,
        "weather_temperature_K": t, "weather_surface_pressure_Pa": p,
        "weather_rh": rh, "site": site, "site_ratio": ratio,
        "uci_source_sha256": uhash, "weather_raw_sha256": whash,
        "reference_sha256": digest(reference),
    }


def svg_root(title: str, description: str):
    root = ET.Element(f"{{{SVG}}}svg", {"width": "1080", "height": "590",
            "viewBox": "0 0 1080 590", "role": "img", "aria-label": title})
    ET.SubElement(root, f"{{{SVG}}}title").text = title
    ET.SubElement(root, f"{{{SVG}}}desc").text = description
    rect(root, 0, 0, 1080, 590, "#f7f9fc")
    return root


def rect(root, x, y, w, h, color, radius=0):
    ET.SubElement(root, f"{{{SVG}}}rect", {
        "x": str(x), "y": str(y), "width": str(w), "height": str(h),
        "rx": str(radius), "fill": color})


def txt(root, x, y, value, size=22, color="#24364b", bold=False):
    attrs = {"x": str(x), "y": str(y), "font-size": str(size),
             "font-family": "Arial, Helvetica, sans-serif", "fill": color}
    if bold:
        attrs["font-weight"] = "700"
    ET.SubElement(root, f"{{{SVG}}}text", attrs).text = str(value)


def save_svg(root, path: Path):
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def plot_uci(a: dict, output: Path):
    target, baseline = a["uci_rmse"], a["uci_baseline_rmse"]
    root = svg_root("Real UCI turbine data: chronological holdout RMSE",
                    "Actual original UCI #551 records from one turbine. "
                    "OLS and training-mean statistical baselines, not a validated physical engine prediction.")
    txt(root, 52, 59, "Real measured turbine records: UCI #551", 31, bold=True)
    txt(root, 52, 93, "2014-2015 held out; trained on 2011-2013; ONE turbine", 19)
    txt(root, 52, 137, "Source-labelled TEY RMSE (published units unresolved)", 20, bold=True)
    left, available = 280, 640
    for idx, (label, value, color) in enumerate((
            ("Condition-adjusted OLS", target, "#147d91"),
            ("Training-mean baseline", baseline, "#d18843"))):
        y = 192 + idx * 112
        txt(root, 52, y+27, label, 18, bold=True)
        rect(root, left, y, available * value / max(target, baseline), 44, color, 4)
        txt(root, left + available * value / max(target, baseline) + 14, y+30,
            f"{value:.4f}", 20, bold=True)
    txt(root, 52, 449, f"n = {a['uci_report']['holdout']['rows']:,} actual source records", 18)
    lo, hi = a["uci_block64_range"]
    txt(root, 52, 480,
        f"64-row blocked RMSE resampling: {lo:.4f}-{hi:.4f} (descriptive; NOT calibrated CI)", 17)
    txt(root, 52, 519, "No reliable per-record timestamps, validated faults or multi-engine IDs.", 18)
    txt(root, 52, 553, "Statistics describe a regression on measurements; NOT ThermoTwin model validation.", 16)
    save_svg(root, output)


def plot_site(a: dict, output: Path):
    ratio = a["site_ratio"]
    site = a["site"]
    root = svg_root("ERA5 boundary to educational Fortran site correction",
                    "Historical weather reanalysis at requested site, used as model input. "
                    "Both bars are model simulated powers, neither a turbine measurement.")
    txt(root, 52, 59, "Historical ERA5 weather -> Fortran site model", 30, bold=True)
    txt(root, 52, 95, "One model hour: 2025-10-01 12:00 UTC (not an engine test)", 19)
    txt(root, 52, 141,
        f"ERA5 2 m air: {a['weather_temperature_K']:.2f} K; surface P: {a['weather_surface_pressure_Pa']:.0f} Pa", 20)
    txt(root, 52, 177, "Simulated net power, normalized to model ISO reference = 1.000", 19, bold=True)
    maximum = max(1.0, ratio, 1.02)
    for idx, (label, value, color) in enumerate((
            ("ISO flange model reference", 1.0, "#325a7d"),
            ("ERA5-driven site model", ratio, "#147d91"))):
        y = 230 + idx * 108
        txt(root, 52, y+27, label, 19, bold=True)
        length = 620 * value / maximum
        rect(root, 338, y, length, 45, color, 4)
        txt(root, 352 + length, y+30, f"{value:.6f}", 19, bold=True)
    txt(root, 52, 463,
        f"Reference/site heat-rate model factor: {float(site['heat_rate_correction_ref_per_site']):.6f}", 19)
    txt(root, 52, 501, "Source: Open-Meteo ERA5 reanalysis. Dry-air approximation: explicit.", 18)
    txt(root, 52, 536, "No measured flange T/P, fuel, power, OEM maps or pass-off acceptance.", 18)
    save_svg(root, output)


def generate(a: dict, out: Path, revision: str, run_id: str):
    out.mkdir(parents=True, exist_ok=True)
    f_uci = out / "01_uci_measured_holdout.svg"
    f_site = out / "02_era5_model_site.svg"
    plot_uci(a, f_uci)
    plot_site(a, f_site)
    rmse, baseline = a["uci_rmse"], a["uci_baseline_rmse"]
    site = a["site"]
    cite_run = (f"https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/{run_id}"
                if run_id.isdigit() else "local generation; no confirmed GitHub run")
    report = f"""# ThermoTwin-F | performance engineering evidence
Generated from original CI source artifacts; **not a customer pass-off, engine calibration or certified prediction**.

**Revision:** {revision}
**Source CI:** {cite_run}

## 1. Actual observed turbine operations — statistical evaluation
![Observed turbine dataset regression and baseline](01_uci_measured_holdout.svg)

The [UCI #551 gas-turbine dataset](https://doi.org/10.24432/C5WC95)
contains **{a['uci_report']['measured_observations']:,} actual records from ONE turbine**, across
2011-2015, with **{a['uci_report']['holdout']['rows']:,} records held out from 2014-2015**.
The observed TEY response retains the dataset's published **source-labelled units**;
no unverified interpretation as measured electrical MW is made.

- Condition-adjusted OLS held-out RMSE: **{rmse:.4f}** source TEY units.
- Training-mean baseline held-out RMSE: **{baseline:.4f}** same source TEY units.
- Corrected, within-year de-meaned training residual lag-1: **{a['uci_lag']:.4f}**.
- Held-out outside any training marginal feature range: **{100*a['uci_support']:.2f}%**.
- 64-published-row block-bootstrap RMSE **descriptive sensitivity range**:
  **{a['uci_block64_range'][0]:.4f}-{a['uci_block64_range'][1]:.4f}**.
  This is NOT a statistically calibrated 95% confidence interval.

The original dataset has no exact timestamps or independently verified fault
labels. The regression is **not** ThermoTwin's physical gas-turbine validation.
A one-turbine sample does **not** establish real fleet statistics.

## 2. Actual ERA5 weather reanalysis driving an educational gas-turbine model
![ERA5 atmospheric input and simulated site corrections](02_era5_model_site.svg)

A historical [Open-Meteo ERA5](https://open-meteo.com/) **reanalysis** value
at 2025-10-01 12:00 UTC supplied model ambient temperature
**{a['weather_temperature_K']:.3f} K**, surface pressure
**{a['weather_surface_pressure_Pa']:.0f} Pa**, and source relative humidity
**{100*a['weather_rh']:.2f}%** (recorded, **not** physically corrected).
A separate fixed-hardware, ISO-flange reference deck, and a declared dry-air
approximation were used in the original Fortran solver.

- Reference **model** electrical power: **{float(site['reference_net_power_MW']):.4f} MW**.
- ERA5-boundary **model** electrical power: **{float(site['site_net_power_MW']):.4f} MW**.
- Site/reference **model** power ratio: **{a['site_ratio']:.8f}**.
- Reference/site **model** heat-rate correction: **{float(site['heat_rate_correction_ref_per_site']):.8f}**.

Those MW figures are **simulator predictions for a generic teaching machine,
NOT measured turbine performance, guaranteed site power or Siemens OEM predictions**.
ERA5 2 m temperature and surface pressure are **not** calibrated compressor
flange measurements. Fuel, control mode, component maps and model-form
uncertainty are not independently validated.

## 3. Physics and verification boundaries
- Model: modern Fortran, energy-balance Brayton cycle with independently defined
  compressor-inlet / exhaust ISO flange reference conditions, property-mixture
  consistency checks, off-design model and negative-input tests.
- Measured evidence: the original **one-turbine UCI observations only**.
- Externally sourced model boundary: **ERA5 reanalysis only**, not site measurements.
- Engineering method: pass-off correction and conditional instrument covariance
  equations exist, but there are **no actual customer test-stand inputs**.
  **Guarantee outcome: NOT ASSESSED.**
- Passing CI confirms software/physics-code checks and source provenance,
  not compliance with ASME PTC 22 / ISO 2314 or engine qualification.
- Full assumptions: docs/SITE_PERFORMANCE_v0.1.md,
  docs/UCI551_REAL_OPERATIONS.md, docs/PASSOFF_CORRECTION_METHOD.md.

## 4. Source identity and replay
- UCI DOI: 10.24432/C5WC95; UCI source licence: CC BY 4.0.
- UCI original ZIP SHA-256: {a['uci_source_sha256']}.
- ERA5 original HTTP JSON SHA-256: {a['weather_raw_sha256']}.
- Declared ISO hardware input deck SHA-256: {a['reference_sha256']}.
- Generated SVGs, dossier and source ledger are packaged as the same CI artifact.
  Original-source UCI and weather artifacts are separate uploads in that same run.
"""
    report_path = out / "ENGINEERING_DOSSIER.md"
    report_path.write_text(report, encoding="utf-8")
    ledger = {
        "schema": "thermotwin.lincoln.source_backed_dossier.v1",
        "revision": revision,
        "github_actions_run_id": run_id,
        "source_data": {
            "uci_551_doi": "10.24432/C5WC95",
            "uci_original_zip_sha256": a["uci_source_sha256"],
            "original_turbines": 1,
            "observed_records": a["uci_report"]["measured_observations"],
            "heldout_records": a["uci_report"]["holdout"]["rows"],
            "weather_source": "Open-Meteo ERA5 reanalysis",
            "weather_original_json_sha256": a["weather_raw_sha256"],
            "reference_hardware_deck_sha256": a["reference_sha256"],
            "weather_utc": "2025-10-01T12:00:00Z",
        },
        "disclosures": {
            "measured_engine_power_claimed": False,
            "engine_population_claimed": False,
            "oem_model_calibrated": False,
            "humid_air_correction_performed": False,
            "contractual_guarantee_assessed": False,
            "engine_fault_labels_verified": False,
            "statistical_intervals_calibrated": False,
        },
        "outputs_sha256": {
            path.name: digest(path) for path in (f_uci, f_site, report_path)
        },
    }
    (out / "source_ledger.json").write_text(
        json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return ledger


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uci-dir", type=Path, required=True)
    parser.add_argument("--weather-dir", type=Path, required=True)
    parser.add_argument("--reference-case", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.uci_dir, args.weather_dir, args.reference_case)
    revision = os.environ.get("GITHUB_SHA", "local-unversioned")
    run_id = os.environ.get("GITHUB_RUN_ID", "local")
    ledger = generate(result, args.output_dir, revision, run_id)
    print(f"Audited evidence dossier: {args.output_dir}")
    print(f"Original UCI source: {ledger['source_data']['uci_original_zip_sha256']}")
    print(f"Original ERA5 JSON: {ledger['source_data']['weather_original_json_sha256']}")
    print("No OEM validation, fabricated measured power, engine population or guarantee.")


if __name__ == "__main__":
    main()
