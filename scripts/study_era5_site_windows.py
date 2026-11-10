#!/usr/bin/env python3
"""Actual ERA5 reanalysis hours -> generic fixed-hardware Fortran site study.

Weather is reanalysis, NOT compressor flange observation. Loss cases are
assumptions, NOT uncertainty confidence intervals. No OEM model calibration.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timedelta, timezone
from hashlib import sha256
import json
import math
from pathlib import Path
import statistics
from urllib.parse import urlencode
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

from scripts.open_meteo_boundary import (
    ENGINE_FIELDS, HOURLY_FIELDS, parse_response, read_reference_case, utc_iso
)

# Predeclared windows; selected before querying historical data.
WINDOWS = (("winter", "2025-01-15"), ("spring", "2025-04-15"),
           ("summer", "2025-07-15"), ("autumn", "2025-10-15"))
LAT, LON, MODEL = 53.23, -0.54, "era5"
HOURS = 168
# Deterministic assumption sensitivity, not model or instrument uncertainty.
LOSSES = (("z", 0., 0.), ("i", .01, 0.),
          ("e", 0., .02), ("b", .01, .02))
WEATHER_FIELDS = ("case_id", "window", "valid_time_utc",
                  "air_temperature_2m_K", "surface_pressure_Pa",
                  "relative_humidity_source_fraction",
                  "grid_latitude", "grid_longitude", "source_raw_sha256")


def digest(p: Path) -> str:
    return sha256(p.read_bytes()).hexdigest()


def times(start: str, count: int) -> list[str]:
    if not 1 <= count <= 744:
        raise ValueError("Out-of-range historical study duration")
    first = datetime.strptime(start, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    return [(first + timedelta(hours=k)).isoformat(timespec="seconds").
            replace("+00:00", "Z") for k in range(count)]


def source_url(start: str, count: int) -> str:
    end = (datetime.strptime(start, "%Y-%m-%d") +
           timedelta(hours=count - 1)).date().isoformat()
    return "https://archive-api.open-meteo.com/v1/archive?" + urlencode({
        "latitude": LAT, "longitude": LON,
        "start_date": start, "end_date": end,
        "hourly": ",".join(HOURLY_FIELDS), "timezone": "GMT",
        "models": MODEL,
    })


def verified_window(raw: bytes, start: str, count: int) -> list[dict]:
    if len(raw) > 2_000_000:
        raise ValueError("Original ERA5 API response above 2MB")
    payload = json.loads(raw)
    if not isinstance(payload, dict) or payload.get("error"):
        raise ValueError("ERA5 archive error or invalid JSON")
    hourly = payload.get("hourly")
    if not isinstance(hourly, dict) or not isinstance(hourly.get("time"), list):
        raise ValueError("Missing ERA5 hourly timestamps")
    expected = times(start, count)
    # No truncation, interpolation, daylight-saving alias or missing hours.
    if [utc_iso(x) for x in hourly["time"]] != expected:
        raise ValueError("Missing, duplicate, extra or unordered original UTC hours")
    h = sha256(raw).hexdigest()
    return [parse_response(payload, "archive", stamp, LAT, LON, MODEL, h)
            for stamp in expected]


def csv_rows(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        if not reader.fieldnames or len(reader.fieldnames) != len(set(reader.fieldnames)):
            raise ValueError(f"Malformed CSV header: {path}")
        rows = list(reader)
    if not rows or any(None in r or None in r.values() for r in rows):
        raise ValueError(f"Truncated or missing CSV: {path}")
    return rows


def save_csv(path: Path, fields, rows):
    with path.open("w", newline="", encoding="utf-8") as file:
        w = csv.DictWriter(file, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def acquire(out: Path, ref_file: Path, replay_dir: Path | None = None):
    ref, refhash = read_reference_case(ref_file)
    if (abs(float(ref["ambient_T_K"]) - 288.15) > 1e-9 or
            abs(float(ref["ambient_P_Pa"]) - 101325) > 1e-7 or
            float(ref["inlet_pressure_loss"]) != 0 or
            float(ref["exhaust_pressure_loss"]) != 0 or
            ref["degradation_mode"] != "clean"):
        raise ValueError("Required fixed ISO intake/exhaust flange reference missing")
    out.mkdir(parents=True, exist_ok=True)
    weather, inputs, originals = [], [], []
    for n, (label, first) in enumerate(WINDOWS, 1):
        raw_file = f"week_{n:02d}_{label}_era5_raw.json"
        url = source_url(first, HOURS)
        if replay_dir is None:
            req = Request(url, headers={"User-Agent": "ThermoTwin-F-research/1.0"})
            with urlopen(req, timeout=40) as response:
                if response.status != 200:
                    raise ValueError(f"Weather API returned HTTP {response.status}")
                raw = response.read(2_000_001)
            mode = "original_retrieval"
        else:
            raw = (replay_dir / raw_file).read_bytes()
            mode = "offline_replay_existing_original_response"
        values = verified_window(raw, first, HOURS)
        path = out / raw_file
        path.write_bytes(raw)
        sha = digest(path)
        grid = {(x["model_grid_latitude"], x["model_grid_longitude"]) for x in values}
        if len(grid) != 1:
            raise ValueError("ERA5 model grid changes within declared week")
        originals.append({
            "window": label, "start_date_utc": first,
            "end_date_utc": times(first, HOURS)[-1][:10],
            "requested_url": url, "retrieval_mode": mode,
            "original_raw_file": raw_file, "original_raw_sha256": sha,
            "returned_grid_lat_lon": list(next(iter(grid))),
            "hours": HOURS,
        })
        for hour, row in enumerate(values):
            key = f"w{n:02d}h{hour:03d}"
            weather.append({
                "case_id": key, "window": label, "valid_time_utc": row["valid_time_utc"],
                "air_temperature_2m_K": format(row["temperature_K"], ".10g"),
                "surface_pressure_Pa": format(row["surface_pressure_Pa"], ".10g"),
                "relative_humidity_source_fraction": format(row["relative_humidity_fraction"], ".10g"),
                "grid_latitude": row["model_grid_latitude"],
                "grid_longitude": row["model_grid_longitude"],
                "source_raw_sha256": sha,
            })
            for tag, inlet, exhaust in LOSSES:
                case = dict(ref)
                case["case_name"] = key + tag
                case["ambient_T_K"] = format(row["temperature_K"], ".10g")
                case["ambient_P_Pa"] = format(row["surface_pressure_Pa"], ".10g")
                # RH is preserved in the weather CSV, NOT passed into physics.
                case["relative_humidity"] = ref["relative_humidity"]
                case["inlet_pressure_loss"] = format(inlet, ".6f")
                case["exhaust_pressure_loss"] = format(exhaust, ".6f")
                inputs.append(case)
    if (len(weather) != 672 or len(inputs) != 2688 or
            len({r["valid_time_utc"] for r in weather}) != 672):
        raise ValueError("Actual ERA5 source UTC coverage failed")
    wp, cp = out / "weather_hours.csv", out / "site_cases.csv"
    save_csv(wp, WEATHER_FIELDS, weather)
    save_csv(cp, ENGINE_FIELDS, inputs)
    manifest = {
        "schema": "thermotwin.era5_seasonal_model.v1",
        "requested_point_lat_lon": [LAT, LON],
        "site_is_real_customer_installation": False,
        "original_weather_source": "Open-Meteo ERA5 hourly reanalysis",
        "weather_license": "CC BY 4.0; weather data by Open-Meteo.com",
        "api_terms": "https://open-meteo.com/en/terms",
        "weather_is_not_measured_compressor_flange_state": True,
        "weather_rh_retained_but_humidity_thermodynamics_not_implemented": True,
        "assumed_losses_not_actual_pressure_drop_measurements": True,
        "model_and_weather_uncertainty_not_quantified": True,
        "fixed_hardware_reference_sha256": refhash,
        "original_sources": originals, "weather_hours": 672,
        "model_cases": 2688,
        "assumed_loss_cases": [
            {"tag": tag, "inlet_fraction": i, "exhaust_fraction": e}
            for tag, i, e in LOSSES],
        "weather_csv_sha256": digest(wp),
        "input_cases_sha256": digest(cp),
    }
    (out / "source_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True)+"\n", encoding="utf-8")
    print("Acquired original ERA5 source: 672 UTC reanalysis hours, "
          "2688 fixed-hardware assumed-loss cases")
    return manifest


def fnum(row: dict, key: str, positive=False):
    try:
        x = float(row[key])
    except (KeyError, ValueError, TypeError) as exc:
        raise ValueError(f"Missing/non-numeric model output: {key}") from exc
    if not math.isfinite(x) or (positive and x <= 0):
        raise ValueError(f"Nonfinite/nonpositive model output: {key}")
    return x


def close(a, b, label):
    if not math.isclose(a, b, rel_tol=5e-7, abs_tol=2e-5):
        raise ValueError(f"Physical model output identity mismatch: {label}")


def summarize(folder: Path, ref_file: Path):
    manifest = json.loads((folder/"source_manifest.json").read_text())
    if (manifest.get("schema") != "thermotwin.era5_seasonal_model.v1" or
            manifest.get("weather_hours") != 672 or
            manifest.get("model_cases") != 2688 or
            manifest.get("weather_is_not_measured_compressor_flange_state") is not True or
            manifest.get("assumed_losses_not_actual_pressure_drop_measurements") is not True or
            manifest.get("model_and_weather_uncertainty_not_quantified") is not True or
            digest(ref_file) != manifest.get("fixed_hardware_reference_sha256")):
        raise ValueError("Required source provenance and model disclaimers missing")
    for n, (label, start) in enumerate(WINDOWS, 1):
        x = manifest["original_sources"][n-1]
        path = folder / x["original_raw_file"]
        if (x["window"] != label or x["start_date_utc"] != start or
                digest(path) != x["original_raw_sha256"] or
                len(verified_window(path.read_bytes(), start, HOURS)) != HOURS):
            raise ValueError("Original raw ERA5 source identity/UTC mismatch")
    weather_file, cases_file = folder/"weather_hours.csv", folder/"site_cases.csv"
    if (digest(weather_file) != manifest["weather_csv_sha256"] or
            digest(cases_file) != manifest["input_cases_sha256"]):
        raise ValueError("Generated weather/model-input CSV mutated after acquisition")
    weather, cases, results = (csv_rows(weather_file), csv_rows(cases_file),
                               csv_rows(folder/"site_results.csv"))
    if (len(weather), len(cases), len(results)) != (672, 2688, 2688):
        raise ValueError("Incomplete Fortran site scenario results")
    windows = {label: {"T": [], "P": [], "RH": [], "z": [], "i": [], "e": [], "b": [],
                       "span": []} for label, _ in WINDOWS}
    refpower = None
    for k, w in enumerate(weather):
        label, start = WINDOWS[k//168]
        key = f"w{k//168+1:02d}h{k%168:03d}"
        if (w["case_id"] != key or w["window"] != label or
                w["valid_time_utc"] != times(start, HOURS)[k%168]):
            raise ValueError("Original annual window timestamps or case identity changed")
        t, p, rh = (fnum(w, "air_temperature_2m_K", True),
                    fnum(w, "surface_pressure_Pa", True),
                    fnum(w, "relative_humidity_source_fraction"))
        if not (250 <= t <= 325 and 75000 <= p <= 110000 and 0 <= rh <= 1):
            raise ValueError("Reanalysis outside declared educational solver model envelope")
        window = windows[label]
        window["T"].append(t); window["P"].append(p); window["RH"].append(rh)
        for j, (tag, inlet, exhaust) in enumerate(LOSSES):
            case, output = cases[4*k+j], results[4*k+j]
            if (case["case_name"] != key+tag or output["case_name"] != key+tag or
                    output["valid"] != "1" or
                    abs(fnum(case,"inlet_pressure_loss")-inlet) > 1e-10 or
                    abs(fnum(case,"exhaust_pressure_loss")-exhaust) > 1e-10 or
                    abs(fnum(case,"relative_humidity")-0.6) > 1e-10):
                raise ValueError("Model case ordering, measured-loss or RH assumption mismatch")
            close(fnum(case,"ambient_T_K"), t, "T model boundary")
            close(fnum(case,"ambient_P_Pa"), p, "P model boundary")
            close(fnum(output,"site_ambient_T_K"), t, "T actual solver output")
            close(fnum(output,"site_ambient_P_Pa"), p, "P actual solver output")
            pref = fnum(output, "reference_net_power_MW", True)
            psite = fnum(output, "site_net_power_MW", True)
            if refpower is None: refpower = pref
            close(pref, refpower, "fixed reference machine")
            ratio = fnum(output, "power_derate_ratio", True)
            close(ratio, psite/pref, "reference/site power")
            close(fnum(output,"power_correction_ref_per_site",True),
                  pref/psite, "power correction")
            close(fnum(output,"heat_rate_correction_ref_per_site",True),
                  fnum(output,"reference_heat_rate_kJ_kWh",True)/
                  fnum(output,"site_heat_rate_kJ_kWh",True), "heat rate correction")
            close(fnum(output,"exhaust_flow_correction_ref_per_site",True),
                  fnum(output,"reference_exhaust_flow_kg_s",True)/
                  fnum(output,"site_exhaust_flow_kg_s",True), "exhaust flow correction")
            close(fnum(output,"exhaust_T_additive_ref_minus_site_K"),
                  fnum(output,"reference_exhaust_T_K")-
                  fnum(output,"site_exhaust_T_K"), "exhaust temperature correction")
            window[tag].append(ratio)
        window["span"].append(max(window[short][-1] for short, *_ in LOSSES) -
                              min(window[short][-1] for short, *_ in LOSSES))
    summaries = []
    for label, _ in WINDOWS:
        x = windows[label]
        if len(x["T"]) != 168:
            raise ValueError("Incomplete seasonal window")
        summaries.append({
            "window": label, "original_reanalysis_hours": len(x["T"]),
            "weather_T_min_K": min(x["T"]), "weather_T_max_K": max(x["T"]),
            "weather_P_min_Pa": min(x["P"]), "weather_P_max_Pa": max(x["P"]),
            "observed_weather_RH_min_fraction": min(x["RH"]),
            "observed_weather_RH_max_fraction": max(x["RH"]),
            "model_zero_loss_median_power_ratio": statistics.median(x["z"]),
            "model_zero_loss_min_power_ratio": min(x["z"]),
            "model_zero_loss_max_power_ratio": max(x["z"]),
            "model_both_loss_median_power_ratio": statistics.median(x["b"]),
            "model_both_loss_min_power_ratio": min(x["b"]),
            "model_both_loss_max_power_ratio": max(x["b"]),
            "median_model_ratio_span_assumed_losses_only": statistics.median(x["span"]),
        })
    report = {
        "schema": "thermotwin.era5_four_window_model_report.v1",
        "source_hours": 672, "model_cases": 2688,
        "software_revision": __import__("os").environ.get("GITHUB_SHA", "local-unverified"),
        "weather_model_estimates_not_engine_measurements": True,
        "site_power_is_generic_fortran_prediction": True,
        "loss_sensitivity_is_not_statistical_or_model_uncertainty": True,
        "model_form_uncertainty_not_quantified": True,
        "engine_specific_validation": False,
        "source_manifest_sha256": digest(folder/"source_manifest.json"),
        "site_output_sha256": digest(folder/"site_results.csv"),
        "generic_model_reference_net_power_MW_not_measured": refpower,
        "seasonal": summaries,
        "limitations": [
            "ERA5 reanalysis not calibrated compressor flange measurement",
            "reference and site outputs are unvalidated generic Fortran model results",
            "real weather relative humidity retained but wet air not modeled",
            "inlet/exhaust losses are engineering what-if assumptions, not measurements",
            "weather/model-form/OEM maps and control uncertainties unquantified",
            "seasonal medians are NOT model accuracy or engine acceptance guarantees",
        ],
    }
    (folder/"study_report.json").write_text(json.dumps(report, indent=2,sort_keys=True)+"\n")
    save_csv(folder/"seasonal_summary.csv", list(summaries[0]), summaries)
    render(summaries, folder/"seasonal_era5_site_model.svg")
    lines = [
        "# Four-season real ERA5 reanalysis -> generic Fortran site model",
        "",
        "Original Open-Meteo ERA5 2-m air temperature and surface pressure are",
        "weather reanalysis MODEL estimates, NOT measured compressor/turbine flange data.",
        "Four 7-day windows selected before examining their output:",
        "15-21 Jan, Apr, Jul and Oct 2025, 168 hours each, 672 actual UTC source",
        "hours total. All 672 are evaluated against the SAME generic fixed",
        "ISO-flange educational Fortran machine. Four assumed pressure-loss cases",
        "per hour yield 2,688 genuine equation-based solver outputs.",
        "",
        "![Seasonal model comparison](seasonal_era5_site_model.svg)",
        "",
        "| Window | ERA5 T range (K) | Model zero-loss median power ratio | Model 1% inlet plus 2% exhaust loss median ratio |",
        "|:--|--:|--:|--:|",
    ]
    for r in summaries:
        lines.append(f"| {r['window']} | {r['weather_T_min_K']:.2f}–{r['weather_T_max_K']:.2f} | "
                     f"{r['model_zero_loss_median_power_ratio']:.6f} | "
                     f"{r['model_both_loss_median_power_ratio']:.6f} |")
    lines += [
        "",
        "## Engineering validity",
        "- The fixed model reference uses 288.15 K, 101325 Pa, zero inlet/exhaust",
        "  ISO flange losses, and a fixed control/fuel/geometry reference.",
        "- Weather source: Open-Meteo.com, CC BY 4.0; API terms apply.",
        "  Four immutable original JSON responses and SHA-256 manifests included.",
        "- The genuine weather RH is retained separately from an unchanged 0.60",
        "  model RH scalar; humid-air correction is NOT implemented.",
        "- Zero, 1% inlet, 2% exhaust and combined cases are a priori engineering",
        "  sensitivity scenarios and NOT measured installation pressure losses.",
        "- Variation across those loss cases quantifies chosen parametric",
        "  sensitivity ONLY. It is not a confidence interval, actual instrument",
        "  uncertainty, model-form uncertainty, or an independent OEM comparison.",
        "- No matched real turbine power, fuel flow, OEM maps, or operator records",
        "  were used. Actual site performance accuracy is NOT validated and",
        "  no contract pass-off, emissions or production fleet result is claimed.",
        "- The original 672-row weather CSV, 2688-row input and result CSVs,",
        "  SHA256 provenance, study JSON and graph permit strict replay.",
    ]
    (folder/"STUDY.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
    print("Audited real reanalysis: 672 UTC hours; 2688 physical solver outputs")
    return report


def render(rows: list[dict], out: Path):
    ns = "http://www.w3.org/2000/svg"
    ET.register_namespace("", ns)
    root = ET.Element(f"{{{ns}}}svg",{"width":"1110","height":"628","viewBox":"0 0 1110 628"})
    ET.SubElement(root,f"{{{ns}}}title").text="Real ERA5 reanalysis-driven generic turbine model"
    ET.SubElement(root,f"{{{ns}}}desc").text=(
        "Four seven-day real weather reanalysis windows driving generic Fortran model; "
        "no measurements of engine power and no confidence intervals.")
    def rectangle(x,y,w,h,c):
        ET.SubElement(root,f"{{{ns}}}rect",{"x":str(x),"y":str(y),"width":str(w),
                        "height":str(h),"rx":"4","fill":c})
    def label(x,y,t,size=19,color="#253953"):
        ET.SubElement(root,f"{{{ns}}}text",{"x":str(x),"y":str(y),
                       "font-family":"Arial,Helvetica,sans-serif",
                       "font-size":str(size),"fill":color}).text=t
    rectangle(0,0,1110,628,"#f6f9fc")
    label(42,56,"ERA5 seasonality and assumed-loss model response",31)
    label(42,92,"4 a priori seven-day windows | 672 actual reanalysis hours | 2,688 Fortran simulations",17)
    label(42,129,"Normalized model electric power (reference = 1.000), NOT observed turbine power",19)
    label(42,161,"Dark: 0% inlet / 0% exhaust assumed     Light: 1% inlet / 2% exhaust assumed",17)
    for i,r in enumerate(rows):
        y=205+i*86
        label(42,y+26,r["window"].capitalize(),21)
        label(146,y+24,f"ERA5 T: {r['weather_T_min_K']:.1f}-{r['weather_T_max_K']:.1f} K",16)
        for offset,key,col in ((0,"model_zero_loss_median_power_ratio","#244f83"),
                               (28,"model_both_loss_median_power_ratio","#4b9eac")):
            value = r[key]
            width=min(604,604*value/1.30)
            rectangle(462,y+offset,width,21,col)
            label(478+width,y+offset+17,f"{value:.5f}",17)
    label(42,567,"Bars use a fixed horizontal 0–1.30 reference-power ratio scale.",17)
    label(42,596,"Assumed loss spread is NOT measurement/model uncertainty. No OEM calibration.",17)
    ET.ElementTree(root).write(out,encoding="utf-8",xml_declaration=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest="command",required=True)
    a=sub.add_parser("acquire")
    a.add_argument("--out",type=Path,required=True)
    a.add_argument("--reference",type=Path,required=True)
    a.add_argument("--replay-dir",type=Path)
    s=sub.add_parser("summarize")
    s.add_argument("--out",type=Path,required=True)
    s.add_argument("--reference",type=Path,required=True)
    args=parser.parse_args()
    if args.command=="acquire":
        acquire(args.out,args.reference,args.replay_dir)
    else:
        summarize(args.out,args.reference)


if __name__=="__main__":
    main()
