#!/usr/bin/env python3
"""Fail-closed readiness audit for independent measured GT power/heat-rate validation.

A complete looking CSV does NOT itself validate a physical model. The gate
checks whether prerequisites are available for subsequent independently
specified, untampered, calibrated and physically identical engine comparison.
"""
import argparse
import csv
import json
import math
from datetime import datetime
from pathlib import Path

REQUIRED_MEASURED_FIELDS={
 "timestamp_utc":"instrument UTC synchronized measurement",
 "unit_id":"unique physical turbine ID",
 "operating_mode":"observed full/part load operating mode",
 "ambient_T_K":"measured ambient temperature in kelvin",
 "compressor_flange_T_K":"calibrated intake flange temperature in kelvin",
 "compressor_flange_P_Pa":"calibrated intake flange total pressure in pascals",
 "turbine_exhaust_flange_P_Pa":"calibrated turbine exhaust static pressure in pascals",
 "compressor_air_mass_flow_kg_s":"measured compressor air mass flow in kg/s",
 "fuel_mass_flow_kg_s":"independently metered fuel mass flow in kg/s",
 "fuel_LHV_J_kg":"measured fuel heating value with declared basis",
 "net_electric_power_MW":"metered electrical output with agreed plant boundary",
 "compressor_pressure_ratio":"measured pressure ratio with station definition",
 "turbine_firing_T_K":"validated firing temperature or measured OEM-equivalent",
 "exhaust_T_K":"measured exhaust temperature and station location",
 "generator_efficiency":"independently verified drivetrain definition",
 "inlet_loss_fraction":"measured actual intake pressure loss",
 "exhaust_loss_fraction":"measured actual exhaust backpressure loss",
 "instrument_uncertainty_profile_id":"calibration and covariance budget identity",
 "hardware_and_component_map_id":"independent fixed machine component map identity",
 "fuel_composition_test_id":"fuel sample and chemistry measurement identity",
 "operating_point_id":"unique reproducible test-point identifier",
}
REQUIRED_METADATA={
 "data_license_verified","data_provenance_verified",
 "calibration_certificates_verified","instrument_traceability_verified",
 "timestamp_synchronization_verified","hardware_map_rights_verified",
 "fuel_LHV_method_verified","meter_boundary_agreed",
 "untouched_test_set_preregistered",
 "development_test_leakage_audited",
 "correction_standard_and_guarantee_scope_declared",
 "model_form_uncertainty_budget_documented",
}


def gate(fields,meta=None,quality=None):
    found=set(fields)
    meta=meta if isinstance(meta,dict) else {}
    missing=sorted(set(REQUIRED_MEASURED_FIELDS)-found)
    unmet=sorted(x for x in REQUIRED_METADATA if meta.get(x) is not True)
    # Header presence alone is NOT a measurement bundle. Only inspect()
    # supplies row-quality evidence; direct calls to gate() fail closed.
    observed=(isinstance(quality,dict) and
              isinstance(quality.get("rows_inspected"),int) and
              quality["rows_inspected"]>0 and
              quality.get("invalid_or_incomplete_rows")==0)
    complete=not missing and observed
    return {
      "schema":"thermotwin.experimentally_measured_GT_validation_readiness.v1",
      "measured_fields_present":sorted(found & set(REQUIRED_MEASURED_FIELDS)),
      "missing_measured_fields":[{"field":k,"needed_for":REQUIRED_MEASURED_FIELDS[k]} for k in missing],
      "unverified_independent_prerequisites":unmet,
      "required_measurement_headers_present":not missing,
      "rows_inspected":quality["rows_inspected"] if isinstance(quality,dict) else 0,
      "invalid_or_incomplete_rows":quality["invalid_or_incomplete_rows"] if isinstance(quality,dict) else None,
      "has_minimal_complete_measurement_bundle":complete,
      "required_document_attestations_declared":complete and not unmet,
      "experimentally_traceable_validation_ready":False,
      "independent_document_and_calibration_verification_still_required":True,
      "engine_accuracy_verified":False,
      "measured_heat_rate_verified":False,
      "OEM_or_contractual_passoff_established":False,
      "scope":"Input readiness only. Predictive accuracy requires independent model comparison after this gate.",
    }


# These are *syntax and elementary physical-domain* checks, not calibration.
NUMERIC_REQUIRED_FIELDS={
 "ambient_T_K","compressor_flange_T_K","compressor_flange_P_Pa",
 "turbine_exhaust_flange_P_Pa","compressor_air_mass_flow_kg_s",
 "fuel_mass_flow_kg_s","fuel_LHV_J_kg","net_electric_power_MW",
 "compressor_pressure_ratio","turbine_firing_T_K","exhaust_T_K",
 "generator_efficiency","inlet_loss_fraction","exhaust_loss_fraction",
}


def structurally_valid_row(row, required):
    if None in row or any(row.get(k) is None or not str(row[k]).strip() for k in required):
        return False
    for name in required & NUMERIC_REQUIRED_FIELDS:
        try:
            value=float(row[name])
        except (TypeError,ValueError):
            return False
        if not math.isfinite(value):
            return False
        if name.endswith("_loss_fraction"):
            if value < 0 or value > 0.20:
                return False
        elif name == "generator_efficiency":
            if value <= 0 or value > 1:
                return False
        elif value <= 0:
            return False
    if "timestamp_utc" in required:
        try:
            stamp=datetime.fromisoformat(row["timestamp_utc"].replace("Z","+00:00"))
            if stamp.tzinfo is None or stamp.utcoffset().total_seconds() != 0:
                return False
        except (ValueError, TypeError, AttributeError):
            return False
    return True


def inspect(csv_file,output,metadata_file=None):
    with csv_file.open(newline="",encoding="utf-8-sig") as file:
        reader=csv.DictReader(file)
        columns=reader.fieldnames
        if (columns is None or len(columns)!=len(set(columns)) or
                any(not x or not x.strip() or x != x.strip() for x in columns)):
            raise ValueError("Malformed source measurement columns")
        required=set(columns)&set(REQUIRED_MEASURED_FIELDS)
        rows=0
        invalid=0
        for row in reader:
            rows+=1
            if not structurally_valid_row(row,required):
                invalid+=1
    meta=json.loads(metadata_file.read_text(encoding="utf-8")) if metadata_file else {}
    report=gate(columns,meta,{"rows_inspected":rows,
                               "invalid_or_incomplete_rows":invalid})
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("Independent GT engine validation readiness:",report["experimentally_traceable_validation_ready"])
    print("Source rows inspected:",rows,"invalid/incomplete:",invalid)
    print("Missing measured engine fields:",len(report["missing_measured_fields"]))
    print("Missing traceability/test prerequisites:",len(report["unverified_independent_prerequisites"]))
    print("No experimental power accuracy or contract result asserted.")
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--csv",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--metadata",type=Path)
    a=p.parse_args()
    inspect(a.csv,a.output,a.metadata)


if __name__=="__main__":main()
