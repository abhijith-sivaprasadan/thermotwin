#!/usr/bin/env python3
"""Reference correction and instrument-only UQ for traceable gas-turbine tests.

This does NOT supply invented measurements or confidential Siemens data.
Without a validated OEM model, a full uncertainty budget, and contractual
terms, the report MUST NOT assert an industrial pass-off result.

Site correction factors are imported from thermotwin's fixed-hardware
"site" model; fuel heat input derives from observed flow and measured LHV.
Analytical derivatives propagate supplied precision + calibration covariance
using a first-order Guide to the Expression of Uncertainty in Measurement
(GUM)-style computation. It is NOT ASME PTC 22 / ISO 2314 compliant.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from hashlib import sha256
import json
import math
from pathlib import Path

ORDER = ("net_power_MW", "fuel_flow_kg_s", "fuel_LHV_J_kg")
INPUT_SCHEMA = "thermotwin.passoff.measurements.v1"
OUTPUT_SCHEMA = "thermotwin.passoff.instrument_method.v1"


def number(name, value, positive=False):
    if isinstance(value, bool) or value is None:
        raise ValueError(f"{name}: missing/invalid number")
    try:
        x = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name}: not numeric") from exc
    if not math.isfinite(x) or (positive and x <= 0.0):
        raise ValueError(f"{name}: nonfinite or nonpositive")
    return x


def covariance_3x3(name, value):
    if (not isinstance(value, list) or len(value) != 3 or
            any(not isinstance(row, list) or len(row) != 3 for row in value)):
        raise ValueError(f"{name}: expected 3x3 covariance in channel units squared")
    c = [[number(f"{name}[{i},{j}]", value[i][j]) for j in range(3)] for i in range(3)]
    for i in range(3):
        if c[i][i] < 0:
            raise ValueError(f"{name}: negative variance")
        for j in range(i+1, 3):
            if abs(c[i][j]-c[j][i]) > 1e-8 * max(abs(c[i][j]), abs(c[j][i]), 1e-100):
                raise ValueError(f"{name}: asymmetric covariance")
    # Check positive semidefiniteness on a dimensionless correlation matrix.
    # Covariances carry disparate units (MW, kg/s, J/kg), so principal minors
    # must not be evaluated at raw scales.
    r = [[0.0]*3 for _ in range(3)]
    for i in range(3):
        r[i][i] = 1.0 if c[i][i] > 0 else 0.0
        for j in range(i):
            norm = math.sqrt(c[i][i])*math.sqrt(c[j][j])
            if norm == 0:
                if c[i][j] != 0.0:
                    raise ValueError(f"{name}: nonzero covariance with zero variance")
                r[i][j] = r[j][i] = 0.0
            else:
                r[i][j] = r[j][i] = c[i][j]/norm
                if abs(r[i][j]) > 1.0 + 1e-9:
                    raise ValueError(f"{name}: impossible correlation magnitude")
    for i in range(3):
        for j in range(i+1,3):
            if r[i][i]*r[j][j]-r[i][j]*r[j][i] < -1e-9:
                raise ValueError(f"{name}: not positive semidefinite (pairwise)")
    det = (r[0][0]*(r[1][1]*r[2][2]-r[1][2]*r[2][1])
           -r[0][1]*(r[1][0]*r[2][2]-r[1][2]*r[2][0])
           +r[0][2]*(r[1][0]*r[2][1]-r[1][1]*r[2][0]))
    if det < -1e-9:
        raise ValueError(f"{name}: not positive semidefinite (determinant)")
    return c


def quadratic(jac, covariance):
    return sum(jac[i]*covariance[i][k]*jac[k]
               for i in range(3) for k in range(3))


def bilinear(a, b, covariance):
    return sum(a[i]*covariance[i][k]*b[k]
               for i in range(3) for k in range(3))


def combine_covariances(*matrices):
    return [[sum(c[i][j] for c in matrices) for j in range(3)]
            for i in range(3)]


def compute_corrected(measurements, power_factor, heat_rate_factor, precision, calibration):
    p = number("observed net power [MW]", measurements["net_power_MW"], positive=True)
    mf = number("observed fuel mass flow [kg/s]", measurements["fuel_flow_kg_s"], positive=True)
    lhv = number("observed fuel LHV [J/kg]", measurements["fuel_LHV_J_kg"], positive=True)
    cp = number("power correction factor", power_factor, positive=True)
    ch = number("heat rate correction factor", heat_rate_factor, positive=True)
    cprec = covariance_3x3("precision covariance", precision)
    ccal = covariance_3x3("calibration covariance", calibration)
    cov = combine_covariances(cprec, ccal)
    # Fuel LHV balance: fuel thermal input MW = mf*LHV/1e6.
    # HR in kJ/kWh = 3600*(fuel thermal MW)/(electric MW).
    hr_site = 3600.0 * (mf * lhv / 1.0e6) / p
    corrected_power = p * cp
    corrected_hr = hr_site * ch
    jac_p = (cp, 0.0, 0.0)
    jac_h = (-corrected_hr/p, corrected_hr/mf, corrected_hr/lhv)
    components = {
        "precision": (quadratic(jac_p, cprec), quadratic(jac_h, cprec)),
        "calibration": (quadratic(jac_p, ccal), quadratic(jac_h, ccal)),
        "combined": (quadratic(jac_p, cov), quadratic(jac_h, cov)),
    }
    # Tolerate roundoff only; variance cannot be a negative physical number.
    for name, pair in components.items():
        if any(v < -1e-9*max(1.0, abs(v)) for v in pair):
            raise ValueError(f"{name}: propagation yielded negative variance")
    var_power, var_hr = (max(0.0, v) for v in components["combined"])
    std_power, std_hr = math.sqrt(var_power), math.sqrt(var_hr)
    covariance_ph = bilinear(jac_p, jac_h, cov)
    corr = covariance_ph/(std_power*std_hr) if std_power and std_hr else None
    return {
        "observed_site_power_MW": p,
        "observed_site_heat_rate_kJ_kWh": hr_site,
        "model_reference_per_site_power_factor": cp,
        "model_reference_per_site_heat_rate_factor": ch,
        "corrected_reference_power_MW": corrected_power,
        "corrected_reference_heat_rate_kJ_kWh": corrected_hr,
        "conditional_instrument_standard_uncertainty": {
            "corrected_power_MW": std_power,
            "corrected_heat_rate_kJ_kWh": std_hr,
            "power_heat_rate_covariance_MW_times_kJ_kWh": covariance_ph,
            "power_heat_rate_correlation": corr,
            "variance_components_precision": list(components["precision"]),
            "variance_components_calibration": list(components["calibration"]),
            "variable_order": list(ORDER),
            "jacobian_power_MW": list(jac_p),
            "jacobian_heat_rate_kJ_kWh": list(jac_h),
        },
        "uncertainty_scope": (
            "conditional first-order measurement instrument uncertainty only: "
            "does NOT include site/reference correction model error, inlet/flange "
            "effects, operating-state mismatch or uncertainty of ambient correction factors"
        ),
        "reference_guarantee_decision": "NOT ASSESSED — UNVALIDATED MODEL / NO VERIFIED CONTRACT GUARANTEE",
    }


def parse_utc(name, value):
    if not isinstance(value, str):
        raise ValueError(f"{name}: missing timestamp")
    try:
        t = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{name}: invalid ISO timestamp") from exc
    if t.tzinfo is None or t.utcoffset().total_seconds() != 0:
        raise ValueError(f"{name}: explicit UTC is mandatory")
    return t


def load_site_result(path, case_name):
    with path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    found = [row for row in rows if row.get("case_name") == case_name]
    if len(found) != 1 or found[0].get("valid") != "1":
        raise ValueError("Exactly one accepted Fortran site case is required")
    row = found[0]
    cp = number("site model power ratio", row.get("power_correction_ref_per_site"), positive=True)
    ch = number("site model heat-rate ratio", row.get("heat_rate_correction_ref_per_site"), positive=True)
    pref = number("site model reference power", row.get("reference_net_power_MW"), positive=True)
    psite = number("site model site power", row.get("site_net_power_MW"), positive=True)
    href = number("site model reference heat rate", row.get("reference_heat_rate_kJ_kWh"), positive=True)
    hsite = number("site model site heat rate", row.get("site_heat_rate_kJ_kWh"), positive=True)
    if not math.isclose(cp, pref/psite, rel_tol=1e-7):
        raise ValueError("Fortran result violates power factor identity")
    if not math.isclose(ch, href/hsite, rel_tol=1e-7):
        raise ValueError("Fortran result violates heat-rate factor identity")
    return row, cp, ch


def evaluate(measurement_document, model_row, model_factors, measurement_sha, model_sha):
    if measurement_document.get("schema") != INPUT_SCHEMA:
        raise ValueError(f"Measurement schema must be {INPUT_SCHEMA}")
    if measurement_document.get("source_class") != "recorded_test_stand_measurements":
        raise ValueError("Recorded test-stand measurement provenance required")
    if measurement_document.get("steady_state_verified") is not True:
        raise ValueError("Steady state has not been independently verified")
    for key in ("test_id", "engine_id", "measurement_source_identifier",
                "instrument_calibration_source_identifier"):
        if not str(measurement_document.get(key, "")).strip():
            raise ValueError(f"Missing measurement provenance: {key}")
    start = parse_utc("start_utc", measurement_document.get("start_utc"))
    end = parse_utc("end_utc", measurement_document.get("end_utc"))
    if end <= start:
        raise ValueError("Acquisition end must be later than start")
    fields = measurement_document.get("measured", {})
    if not isinstance(fields, dict):
        raise ValueError("Measured channels missing")
    for channel in (*ORDER, "ambient_T_K", "ambient_P_Pa"):
        if channel not in fields:
            raise ValueError(f"Missing measured channel {channel}")
    if measurement_document.get("model_site_case") != model_row.get("case_name"):
        raise ValueError("Measurement/model operating point identity mismatch")
    Ta = number("measured ambient temperature", fields["ambient_T_K"], positive=True)
    Pa = number("measured ambient pressure", fields["ambient_P_Pa"], positive=True)
    Ta_model = number("model site temperature", model_row.get("site_ambient_T_K"), positive=True)
    Pa_model = number("model site pressure", model_row.get("site_ambient_P_Pa"), positive=True)
    # Model must be regenerated at the test's measured atmospheric boundaries.
    # Differences can be widened ONLY through reviewed, explicit model changes.
    if abs(Ta - Ta_model) > 0.1 or abs(Pa - Pa_model) > 10.0:
        raise ValueError("Test ambient and model site boundary differ; regenerate site case")
    model_lhv = number("model fuel LHV", model_row.get("site_fuel_LHV_J_kg"), positive=True)
    observed_lhv = number("measured fuel LHV", fields["fuel_LHV_J_kg"], positive=True)
    if abs(observed_lhv/model_lhv-1.0) > 0.001:
        raise ValueError("Fuel LHV differs from model input; regenerate model at measured fuel basis")
    covariance = measurement_document.get("covariance", {})
    if covariance.get("variable_order") != list(ORDER):
        raise ValueError("Covariance channel order must be explicit and match input")
    result = compute_corrected(
        fields, model_factors[0], model_factors[1],
        covariance["precision"], covariance["calibration"]
    )
    return {
        "schema": OUTPUT_SCHEMA,
        "test_id": measurement_document["test_id"],
        "engine_id": measurement_document["engine_id"],
        "source_class": "operator_provided_measurement_not_independently_authenticated",
        "measurement_source_identifier": measurement_document["measurement_source_identifier"],
        "instrument_calibration_source_identifier": measurement_document["instrument_calibration_source_identifier"],
        "start_utc": measurement_document["start_utc"],
        "end_utc": measurement_document["end_utc"],
        "measurement_document_sha256": measurement_sha,
        "site_model_results_sha256": model_sha,
        "model_site_case": model_row["case_name"],
        "site_boundary": {"ambient_T_K": Ta, "ambient_P_Pa": Pa},
        "site_model_scope": "fixed-reference educational simple-cycle; not OEM validated",
        "computation": result,
        "disclaimer": (
            "This is a method report with operator-supplied records. The "
            "software cannot authenticate whether the original measurements "
            "were genuinely acquired or calibrations valid. The model is not "
            "manufacturer calibrated. No contractual pass-off verdict is supported."
        ),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--measurement-json", type=Path, required=True,
                        help="Real recorded measurement and instrument covariance; no examples bundled")
    parser.add_argument("--site-result-csv", type=Path, required=True,
                        help="Output of thermotwin site from same physical boundary")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    measurement_raw = args.measurement_json.read_bytes()
    model_raw = args.site_result_csv.read_bytes()
    data = json.loads(measurement_raw)
    row, cp, ch = load_site_result(args.site_result_csv, data.get("model_site_case"))
    report = evaluate(data, row, (cp, ch),
                      sha256(measurement_raw).hexdigest(), sha256(model_raw).hexdigest())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    print(f"Calculated reference-corrected KPIs for {report['test_id']}; {args.output}")
    print("Measurement/instrument-only UQ; no industrial guarantee decision or engine validation.")


if __name__ == "__main__":
    main()
