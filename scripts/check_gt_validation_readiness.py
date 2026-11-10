#!/usr/bin/env python3
"""Fail-closed readiness audit for independent measured GT power/heat-rate validation.

A complete looking CSV does NOT itself validate a physical model. The gate
checks whether prerequisites are available for subsequent independently
specified, untampered, calibrated and physically identical engine comparison.
"""
import argparse
import csv
import json
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


def gate(fields,meta=None):
    found=set(fields)
    meta=meta if isinstance(meta,dict) else {}
    missing=sorted(set(REQUIRED_MEASURED_FIELDS)-found)
    unmet=sorted(x for x in REQUIRED_METADATA if meta.get(x) is not True)
    return {
      "schema":"thermotwin.experimentally_measured_GT_validation_readiness.v1",
      "measured_fields_present":sorted(found & set(REQUIRED_MEASURED_FIELDS)),
      "missing_measured_fields":[{"field":k,"needed_for":REQUIRED_MEASURED_FIELDS[k]} for k in missing],
      "unverified_independent_prerequisites":unmet,
      "has_minimal_complete_measurement_bundle":not missing,
      "required_document_attestations_declared":not missing and not unmet,
      "experimentally_traceable_validation_ready":False,
      "independent_document_and_calibration_verification_still_required":True,
      "engine_accuracy_verified":False,
      "measured_heat_rate_verified":False,
      "OEM_or_contractual_passoff_established":False,
      "scope":"Input readiness only. Predictive accuracy requires independent model comparison after this gate.",
    }


def inspect(csv_file,output,metadata_file=None):
    with csv_file.open(newline="",encoding="utf-8-sig") as file:
        reader=csv.DictReader(file)
        if reader.fieldnames is None or len(reader.fieldnames)!=len(set(reader.fieldnames)):
            raise ValueError("Malformed source measurement columns")
        columns=reader.fieldnames
    meta=json.loads(metadata_file.read_text()) if metadata_file else {}
    report=gate(columns,meta)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print("Independent GT engine validation readiness:",report["experimentally_traceable_validation_ready"])
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
