#!/usr/bin/env python3
"""Replay original UCI #551 held-out turbine measurements against a frozen model.

Train on 2011-2013 only, then make same-record *conditional* predictions for
2014-2015 using measured ambient pressure, inlet filter loss, and turbine
inlet/after temperatures.  Not a future forecast, dynamic simulator, turbine
health classifier, or physically calibrated plant model.

Inputs are the provenance-audited outputs of scripts.fetch_uci_gt551.
Run: python -m scripts.replay_uci_gt551 --data-dir build/uci551 --out build/uci551/replay
"""
from __future__ import annotations

import argparse
import csv
from hashlib import sha256
import json
import math
import os
from pathlib import Path

import numpy as np

from scripts.analyze_uci_gt551 import (
    COLUMNS, fit_normalizer, load_year, predict,
)
from scripts.fetch_uci_gt551 import YEAR_COUNTS

TRAIN_YEARS = (2011, 2012, 2013)
TEST_YEARS = (2014, 2015)
FIELDS = (
    "year", "within_year_row",
    "observed_AT_degC", "observed_AP_mbar", "observed_AFDP_mbar",
    "observed_TIT_degC", "observed_TAT_degC",
    "measured_TEY_source_units", "predicted_TEY_source_units",
    "training_mean_baseline_TEY_source_units",
    "residual_measured_minus_prediction_source_units",
    "outside_training_feature_ranges",
    "large_residual_relative_to_training_3sigma",
)


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def validated_manifest(data_dir: Path) -> dict:
    path = data_dir / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if (manifest.get("schema") != "thermotwin.uci551.source_audit.v1"
            or manifest.get("doi") != "10.24432/C5WC95"
            or manifest.get("number_of_turbines") != 1
            or manifest.get("total_rows") != 36733
            or manifest.get("actual_utc_timestamps_present") is not False
            or manifest.get("test_policy") != {
                "development": [2011, 2012, 2013],
                "untouched_test": [2014, 2015],
            }):
        raise ValueError("UCI #551 original provenance or holdout policy invalid")
    if digest(data_dir / "uci551_original.zip") != manifest.get("original_zip_sha256"):
        raise ValueError("Original UCI archive SHA-256 mismatch")
    years = manifest.get("years", {})
    if set(years) != set(map(str, YEAR_COUNTS)):
        raise ValueError("Incomplete annual provenance manifest")
    for year, count in YEAR_COUNTS.items():
        entry = years[str(year)]
        if entry.get("rows") != count:
            raise ValueError("Wrong source year row count")
        if digest(data_dir / entry["audited_csv"]) != entry.get("audited_csv_sha256"):
            raise ValueError("Original audited annual CSV hash mismatch")
    return manifest


def replay_arrays(per_year: dict[int, tuple[np.ndarray, np.ndarray]]) -> tuple[dict, dict]:
    """Pure numeric evaluation; fixtures here are never claimed as field data.

    Same-record temperature readings are needed before each prediction. A future
    unknown TIT/TAT cannot be substituted with observed evaluation values.
    """
    if set(per_year) != set(YEAR_COUNTS):
        raise ValueError("Expected five annual source groups 2011-2015")
    for year, (x, y) in per_year.items():
        if (x.ndim != 2 or x.shape[1] != len(COLUMNS)
                or y.ndim != 1 or len(x) != len(y) or len(x) < 20
                or not np.isfinite(x).all() or not np.isfinite(y).all()):
            raise ValueError("Malformed finite annual prediction arrays: " + str(year))
    train_x = np.concatenate([per_year[y][0] for y in TRAIN_YEARS])
    train_y = np.concatenate([per_year[y][1] for y in TRAIN_YEARS])
    center, scale, coefficients = fit_normalizer(train_x, train_y)
    train_predictions = predict(train_x, center, scale, coefficients)
    train_sigma = float(np.std(train_y - train_predictions, ddof=1))
    if not math.isfinite(train_sigma) or train_sigma <= 0:
        raise ValueError("Invalid fitted training-residual standard deviation")
    low, high = train_x.min(axis=0), train_x.max(axis=0)
    baseline = float(train_y.mean())
    per_test_year = {}
    evaluation = {}
    for year in TEST_YEARS:
        x, actual = per_year[year]
        estimate = predict(x, center, scale, coefficients)
        outside = np.any((x < low) | (x > high), axis=1)
        error = actual - estimate
        flags = np.abs(error) > 3.0 * train_sigma
        evaluation[year] = {
            "prediction": estimate, "actual": actual,
            "residual": error, "outside": outside, "flags": flags,
        }
        per_test_year[str(year)] = {
            "rows": int(len(actual)),
            "rmse_source_TEY_units": float(np.sqrt(np.mean(error**2))),
            "mae_source_TEY_units": float(np.mean(np.abs(error))),
            "mean_bias_source_TEY_units": float(np.mean(error)),
            "outside_training_feature_ranges_fraction": float(outside.mean()),
            "large_residual_fraction_descriptive_only": float(flags.mean()),
        }
    actual = np.concatenate([evaluation[y]["actual"] for y in TEST_YEARS])
    estimated = np.concatenate([evaluation[y]["prediction"] for y in TEST_YEARS])
    error = actual - estimated
    outside = np.concatenate([evaluation[y]["outside"] for y in TEST_YEARS])
    report = {
        "schema": "thermotwin.uci551.measured_conditional_replay.v1",
        "model": "OLS on four physically motivated *measured same-record* covariates",
        "target": "TEY",
        "target_units": "UCI source label MWh; exact hourly aggregation meaning unresolved",
        "input_covariate_order": list(COLUMNS),
        "train_years": list(TRAIN_YEARS),
        "test_years": list(TEST_YEARS),
        "train_rows": int(len(train_y)),
        "test_rows": int(len(actual)),
        "training_feature_center": center.tolist(),
        "training_feature_scale": scale.tolist(),
        "trained_intercept_and_standardized_slopes": coefficients.tolist(),
        "training_feature_min": low.tolist(),
        "training_feature_max": high.tolist(),
        "training_residual_sigma_source_TEY_units": train_sigma,
        "training_mean_baseline_source_TEY_units": baseline,
        "heldout_rmse_source_TEY_units": float(np.sqrt(np.mean(error**2))),
        "heldout_mae_source_TEY_units": float(np.mean(np.abs(error))),
        "heldout_mean_bias_source_TEY_units": float(np.mean(error)),
        "heldout_training_mean_baseline_rmse_source_TEY_units":
            float(np.sqrt(np.mean((actual - baseline)**2))),
        "heldout_outside_training_feature_range_fraction": float(outside.mean()),
        "annual_holdout_metrics": per_test_year,
        "has_actual_sample_timestamps": False,
        "is_next_step_forecast": False,
        "is_independent_physics_model_validation": False,
        "is_fault_prediction_or_remaining_life_estimation": False,
        "observed_operating_measurements_required_at_inference": True,
        "residual_3sigma_flags_are_confirmed_faults": False,
        "limitations": [
            "One instrumented turbine only; no turbine identity/calibrated maps",
            "Within-year published order is preserved but true per-row UTC times are absent",
            "TIT and TAT are measured on the same record; this is NOT a lead-time forecast",
            "Source TEY is labelled MWh; direct MW and heat-rate claims are not supported",
            "3-sigma residual and training min/max flags are descriptive, not diagnosed failures",
            "No fault/maintenance labels, fuel flow, true load commands or transient trips",
            "Numerical regression does not validate ThermoTwin's generic Brayton model",
        ],
    }
    return report, evaluation


def measured_holdout_rows(data_dir: Path, manifest: dict, results: dict, baseline: float):
    """Join predictions to the original hashed observed rows in their source order."""
    for year in TEST_YEARS:
        entry = manifest["years"][str(year)]
        path = data_dir / entry["audited_csv"]
        with path.open(encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            expected = ("year", "within_year_row", *(
                "AT", "AP", "AH", "AFDP", "GTEP", "TIT", "TAT", "TEY", "CDP", "CO", "NOX",
            ))
            if tuple(reader.fieldnames or ()) != expected:
                raise ValueError("Audited source CSV column schema changed")
            i = 0
            for i, source in enumerate(reader, start=1):
                actual = float(source["TEY"])
                if (int(source["year"]) != year
                        or int(source["within_year_row"]) != i
                        or not math.isclose(actual, float(results[year]["actual"][i-1]),
                                            abs_tol=1e-9, rel_tol=0)):
                    raise ValueError("Measured source row and prediction alignment differ")
                yield {
                    "year": year,
                    "within_year_row": i,
                    "observed_AT_degC": source["AT"],
                    "observed_AP_mbar": source["AP"],
                    "observed_AFDP_mbar": source["AFDP"],
                    "observed_TIT_degC": source["TIT"],
                    "observed_TAT_degC": source["TAT"],
                    "measured_TEY_source_units": actual,
                    "predicted_TEY_source_units": float(results[year]["prediction"][i-1]),
                    "training_mean_baseline_TEY_source_units": baseline,
                    "residual_measured_minus_prediction_source_units":
                        float(results[year]["residual"][i-1]),
                    "outside_training_feature_ranges":
                        int(results[year]["outside"][i-1]),
                    "large_residual_relative_to_training_3sigma":
                        int(results[year]["flags"][i-1]),
                }
            if i != entry["rows"]:
                raise ValueError("Holdout source rows truncated")


def make_viewer(rows: list[dict], report: dict) -> str:
    """Generate a self-contained offline interactive measured-vs-predicted plot."""
    if not rows or len(rows) != report["test_rows"]:
        raise ValueError("Cannot render empty or incomplete observed replay")
    points = [
        [int(r["year"]), int(r["within_year_row"]),
         float(r["measured_TEY_source_units"]),
         float(r["predicted_TEY_source_units"]),
         int(r["outside_training_feature_ranges"]),
         float(r["observed_AT_degC"]), float(r["observed_TIT_degC"])]
        for r in rows
    ]
    payload = json.dumps(points, separators=(",", ":"), allow_nan=False).replace("<", "\\u003c")
    template = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>ThermoTwin-F | Measured turbine replay (UCI 551)</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{color-scheme:dark}body{font:15px system-ui,sans-serif;max-width:1100px;
margin:auto;padding:24px;background:#0c1821;color:#e8f1f5}
a{color:#88dce9}.sub{color:#b6cbd4}main{border:1px solid #395260;border-radius:12px;
padding:18px;background:#142833}canvas{display:block;width:100%;height:360px;
background:#07151f;border-radius:6px}input{width:100%}
.card{display:flex;gap:20px;flex-wrap:wrap}.card>div{flex:1;min-width:175px;
padding:12px;border:1px solid #47606b;border-radius:7px}
strong{font-size:19px}button{padding:9px 16px;background:#243f4e;color:#e8f1f5;
border:1px solid #78919e;border-radius:5px;cursor:pointer}
.warn{color:#ffd18a}.key{color:#7edcef}.chartlabel{display:flex;gap:20px;flex-wrap:wrap}
</style></head><body>
<h1>ThermoTwin-F · Measured turbine replay</h1>
<p class="sub">UCI #551 · actual turbine readings · 2011–2013 model fit ·
2014–2015 untouched holdout. Ordered records, <b>NOT a calibrated time axis</b>.
Inputs include contemporaneous measured TIT/TAT. This is not a future forecast.</p>
<main><div class="card">
<div>Held-out records<br><strong id="count"></strong></div>
<div>Held-out RMSE (source TEY units)<br><strong id="rmse"></strong></div>
<div>Training-mean baseline RMSE<br><strong id="baseline"></strong></div>
</div><p class="chartlabel"><span class="key">● Observed TEY</span>
<span style="color:#ffc875">● Predicted TEY</span></p>
<canvas id="chart" width="1024" height="360" role="img"
aria-label="Observed and predicted TEY in a local row window"></canvas>
<p><label for="index">Select a published observation (not an exact UTC time):</label>
<input id="index" type="range" min="0" max="0" value="0"></p>
<p><button id="prev" type="button">Previous</button>
<button id="next" type="button">Next</button></p>
<p id="detail" aria-live="polite"></p></main>
<p class="sub">Out-of-range means a measured covariate exceeds the development
sample's marginal min/max. Neither an error nor a large residual proves a fault.
No sensor streams, turbine transients, fuel efficiency, remaining life, or OEM
performance prediction have been validated here.</p>
<p>Source: <a href="https://doi.org/10.24432/C5WC95">UCI #551 (CC BY 4.0)</a>.
The original dataset contains 36,733 hourly aggregates from one turbine.
TEY source unit interpretation and exact per-record times remain unresolved.</p>
<script>
"use strict";
const data=__DATA_JSON__;
const report=__METRICS_JSON__;
const slider=document.getElementById("index");
slider.max=String(data.length-1);
document.getElementById("count").textContent=String(data.length);
document.getElementById("rmse").textContent=report[0].toFixed(3);
document.getElementById("baseline").textContent=report[1].toFixed(3);
const canvas=document.getElementById("chart"),ctx=canvas.getContext("2d");
function draw(){
 const k=Number(slider.value),first=Math.max(0,k-100),last=Math.min(data.length,k+101);
 const view=data.slice(first,last),width=canvas.width,height=canvas.height,pad=30;
 const values=view.flatMap(r=>[r[2],r[3]]);
 const low=Math.min(...values),high=Math.max(...values),span=Math.max(high-low,0.001);
 ctx.clearRect(0,0,width,height);
 ctx.strokeStyle="#365361";ctx.lineWidth=1;
 for(let j=0;j<5;j++){let y=pad+j*(height-2*pad)/4;ctx.beginPath();
 ctx.moveTo(pad,y);ctx.lineTo(width-pad,y);ctx.stroke();}
 function series(offset,color){
  ctx.strokeStyle=color;ctx.lineWidth=2;ctx.beginPath();
  view.forEach((r,i)=>{let x=pad+i*(width-2*pad)/Math.max(1,view.length-1);
   let y=height-pad-(r[offset]-low)/span*(height-2*pad);
   if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);});
  ctx.stroke();
 }
 series(2,"#7edcef");series(3,"#ffc875");
 const x=pad+(k-first)*(width-2*pad)/Math.max(1,view.length-1);
 ctx.strokeStyle="#f5f8fa";ctx.lineWidth=1;ctx.beginPath();
 ctx.moveTo(x,pad);ctx.lineTo(x,height-pad);ctx.stroke();
 const row=data[k],diff=row[2]-row[3];
 document.getElementById("detail").textContent="Year "+row[0]+", published row "+row[1]+
  " | Observed TEY: "+row[2].toFixed(3)+" | Predicted: "+row[3].toFixed(3)+
  " | Residual (observed - predicted): "+diff.toFixed(3)+
  " | Ambient: "+row[5].toFixed(2)+" °C | TIT: "+row[6].toFixed(2)+
  " °C | "+(row[4]?"OUTSIDE TRAINING FEATURE RANGE":"within marginal training ranges");
}
slider.addEventListener("input",draw);
document.getElementById("prev").addEventListener("click",()=>{slider.value=String(Math.max(0,Number(slider.value)-1));draw();});
document.getElementById("next").addEventListener("click",()=>{slider.value=String(Math.min(data.length-1,Number(slider.value)+1));draw();});
draw();
</script></body></html>"""
    metrics = json.dumps([
        report["heldout_rmse_source_TEY_units"],
        report["heldout_training_mean_baseline_rmse_source_TEY_units"],
    ], allow_nan=False)
    return template.replace("__DATA_JSON__", payload).replace("__METRICS_JSON__", metrics)


def run(argv=None) -> dict:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, required=True,
                        help="Output of original UCI #551 source auditor")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    manifest = validated_manifest(args.data_dir)
    per_year = {year: load_year(args.data_dir, year, manifest)
                for year in YEAR_COUNTS}
    report, result = replay_arrays(per_year)
    report.update({
        "source": "https://doi.org/10.24432/C5WC95",
        "license": "CC BY 4.0",
        "number_of_measured_turbines": 1,
        "source_zip_sha256": manifest["original_zip_sha256"],
        "source_manifest_sha256": digest(args.data_dir / "manifest.json"),
        "code_revision": os.environ.get("GITHUB_SHA", "local-not-tagged"),
        "real_source_data_only": True,
    })
    args.out.mkdir(parents=True, exist_ok=True)
    data_rows = list(measured_holdout_rows(
        args.data_dir, manifest, result, report["training_mean_baseline_source_TEY_units"]
    ))
    if len(data_rows) != sum(YEAR_COUNTS[y] for y in TEST_YEARS):
        raise ValueError("Incomplete real-source held-out replay")
    csv_path = args.out / "measured_vs_predicted_2014_2015.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(data_rows)
    viewer = args.out / "measured_turbine_replay.html"
    viewer.write_text(make_viewer(data_rows, report), encoding="utf-8")
    report["prediction_csv_sha256"] = digest(csv_path)
    report["interactive_viewer_sha256"] = digest(viewer)
    (args.out / "replay_report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    print("UCI 551: source-verified measured turbine conditional replay")
    print("Fit:", TRAIN_YEARS, "held-out:", TEST_YEARS, "rows:", len(data_rows))
    print("Holdout TEY RMSE: {:.4f} (source units), baseline: {:.4f}".format(
        report["heldout_rmse_source_TEY_units"],
        report["heldout_training_mean_baseline_rmse_source_TEY_units"]))
    print("Local interactive viewer:", viewer)
    print("Not a future forecast, fault classifier or calibrated physics model.")
    return report


if __name__ == "__main__":
    run()
