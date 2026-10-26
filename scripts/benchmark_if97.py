#!/usr/bin/env python3
"""Descriptive comparison: ThermoTwin approximate steam functions vs CoolProp IF97.

Completing this benchmark does NOT certify compliance or accuracy. CoolProp is
an optional external reference dependency, not copied into the Fortran engine.
"""
import argparse
import csv
import hashlib
import io
import json
import math
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ("T_sat_K", "h_liq_kJ_kg", "h_vap_kJ_kg", "s_liq_kJ_kgK",
          "s_vap_kJ_kgK", "h_superheat_50K_kJ_kg")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--executable", type=Path, default=Path("build/property_reference_grid"))
    ap.add_argument("--output", type=Path, default=Path("build/if97_benchmark.json"))
    a = ap.parse_args()
    try:
        import CoolProp
        from CoolProp.CoolProp import PropsSI
    except ImportError as e:
        ap.error("Install optional reference package: pip install CoolProp==8.0.0")
    grid = (ROOT / a.executable).resolve()
    run = subprocess.run([str(grid)], cwd=ROOT, check=True, capture_output=True, text=True)
    table = list(csv.DictReader(io.StringIO(run.stdout)))
    if not table or not set(("p_bar", *FIELDS)).issubset(table[0]):
        raise ValueError("Missing or malformed property CSV output")
    cases = []
    for row in table:
        p = float(row["p_bar"])
        pa = p * 100000.0
        fluid = "IF97::Water"
        t = PropsSI("T", "P", pa, "Q", 0, fluid)
        ref = {
          "T_sat_K": t,
          "h_liq_kJ_kg": PropsSI("H", "P", pa, "Q", 0, fluid)/1000.0,
          "h_vap_kJ_kg": PropsSI("H", "P", pa, "Q", 1, fluid)/1000.0,
          "s_liq_kJ_kgK": PropsSI("S", "P", pa, "Q", 0, fluid)/1000.0,
          "s_vap_kJ_kgK": PropsSI("S", "P", pa, "Q", 1, fluid)/1000.0,
          "h_superheat_50K_kJ_kg": PropsSI("H", "P", pa, "T", t + 50.0, fluid)/1000.0,
        }
        actual = {key: float(row[key]) for key in FIELDS}
        if not all(math.isfinite(v) for v in list(ref.values()) + list(actual.values())):
            raise ValueError(f"Non-finite data at {p} bar")
        error = {key: actual[key]-ref[key] for key in FIELDS}
        cases.append({"pressure_bar":p,"thermotwin_approx":actual,"coolprop_if97":ref,
                      "signed_error":error})
    metrics = {}
    for key in FIELDS:
        es = [c["signed_error"][key] for c in cases]
        metrics[key] = {"mean_absolute_error":sum(map(abs,es))/len(es),
                        "max_absolute_error":max(map(abs,es)),
                        "mean_signed_error":sum(es)/len(es)}
    sha = subprocess.run(["git","rev-parse","HEAD"],cwd=ROOT,check=True,
                          capture_output=True,text=True).stdout.strip()
    data = {"source_commit":sha,"description":"Cross-implementation verification, NOT physical validation",
            "tool":"CoolProp IF97::Water","coolprop_version":CoolProp.__version__,
            "python_version":platform.python_version(),
            "sampler_stdout_sha256":hashlib.sha256(run.stdout.encode()).hexdigest(),
            "case_count":len(cases),"units":"K, kJ/kg and kJ/(kg K) per field",
            "note":"Superheat is 50K above each implementation's own saturation temperature; its discrepancy includes temperature-definition error.",
            "metrics":metrics,"cases":cases}
    dest = (ROOT / a.output).resolve()
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(data,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(f"Compared {len(cases)} pressure points against CoolProp {CoolProp.__version__}:")
    for field, m in metrics.items():
        print(f"  {field}: MAE={m['mean_absolute_error']:.6g}, max_abs={m['max_absolute_error']:.6g}")
    print(f"Recorded descriptive errors: {dest}")
    print("A successful run is NOT proof of acceptable IF97 accuracy.")


if __name__ == "__main__":
    main()
