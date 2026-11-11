"""Synthetic-only mathematical verification. No fixture is industrial evidence."""
from __future__ import annotations

import csv
from datetime import datetime,timedelta,timezone
from hashlib import sha256
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.calibrate_gt_physics import (
    CASE_FIELDS,EXTRA,FIXED,METRICS,OBSERVED,audit_public,
    case,calibrate,digest,estimate,load_measurements,metrics,
    run_fortran,validate_plan,
)
from scripts.check_gt_validation_readiness import REQUIRED_MEASURED_FIELDS,REQUIRED_METADATA

class CalibrationEvidenceContracts(unittest.TestCase):
    def test_all_original_public_source_schemas_block_industrial_validation(self):
        report=audit_public()
        self.assertEqual(report["status"],"BLOCKED_NO_ELIGIBLE_MATCHED_PLANT_MEASUREMENTS")
        self.assertFalse(report["real_engine_accuracy_established"])
        self.assertEqual(len(report["public_dataset_gate"]),3)
        for dataset in report["public_dataset_gate"].values():
            self.assertFalse(dataset["usable_for_industrial_brayton_calibration"])
            self.assertTrue(dataset["original_schema_based_gate"]["missing_measured_fields"])
            self.assertFalse(dataset["original_schema_based_gate"]["engine_accuracy_verified"])

    def test_no_unattested_or_tampered_measured_source(self):
        with TemporaryDirectory() as tmp:
            p=Path(tmp)/"observed.csv"
            p.write_text("timestamp_utc,unit_id\n",encoding="utf-8")
            m={"schema":"thermotwin.gt_physics_measured_plan.v1",
               "source_csv_sha256":"tampered",
               "unit_id":"fixture","hardware_and_component_map_id":"fixture-map"}
            with self.assertRaisesRegex(ValueError,"SHA256"):
                validate_plan(m,p)
            m["source_csv_sha256"]=digest(p)
            with self.assertRaisesRegex(ValueError,"attestations"):
                validate_plan(m,p)

    def test_station_boundary_mismatch_blocks_physical_comparison(self):
        meta={"fixed_model_parameters":{
            "eta_combustor":.98,"combustor_pressure_loss":.03,
            "eta_mechanical":.99,"auxiliary_load_fraction":.02,
            "relative_humidity":0.
        }}
        row={"ambient_P_Pa":"101325","ambient_T_K":"288.15",
            "inlet_loss_fraction":".01","exhaust_loss_fraction":".02",
            "compressor_flange_P_Pa":"88000","turbine_exhaust_flange_P_Pa":"103351.5"}
        with self.assertRaisesRegex(ValueError,"flange boundaries"):
            case(row,meta,.86,.89,"MATHONLY")

    def test_measured_power_does_not_enter_station_temperature_fit(self):
        # Pure algebraic source-contract test: efficiency identification is
        # explicitly T2/T4 only; power/fuel are downstream heldout metrics.
        a={"compressor_discharge_T_K":"700","exhaust_T_K":"810",
           "net_electric_power_MW":"25","fuel_mass_flow_kg_s":".9"}
        b=dict(a,net_electric_power_MW="2500",fuel_mass_flow_kg_s="90")
        from scripts.calibrate_gt_physics import temperature_loss
        pred={"T2_K":"701","T4_K":"812"}
        weights={"T2_K":1.,"T4_K":2.}
        self.assertEqual(temperature_loss([a],[pred],weights),
                         temperature_loss([b],[pred],weights))

    def test_real_fortran_numerical_fixture_is_not_field_validation(self):
        exe=Path("thermotwin")
        if os.name=="nt":
            exe=Path("thermotwin.exe")
        if not exe.exists():
            self.skipTest("Fortran binary absent; full synthetic integration covered by CI")
        with TemporaryDirectory() as temp:
            tmp=Path(temp)
            unit="SYNTHETIC-NO-ENGINE"
            hardware="SYNTHETIC-NO-MAP"
            fixed={"eta_combustor":.98,"combustor_pressure_loss":.03,
                   "eta_mechanical":.99,"auxiliary_load_fraction":.02,
                   "relative_humidity":0.}
            plan={"schema":"thermotwin.gt_physics_measured_plan.v1",
                "unit_id":unit,"hardware_and_component_map_id":hardware,
                "fixed_model_parameters":fixed,
                "fixed_parameter_source_ids":{k:"mathematical-fixture" for k in FIXED},
                "measured_standard_uncertainties":{
                   "T2_K":1.,"T4_K":1.,"net_power_MW":.05,
                   "fuel_flow_kg_s":.02,"heat_rate_kJ_kWh":10.},
                "predeclared_test_RMSE_limits":{
                   "T2_K":4.,"T4_K":4.,"net_power_MW":1.,
                   "fuel_flow_kg_s":.1,"heat_rate_kJ_kWh":200.},
                "validation_plan_id":"SYNTHETIC-ONLY-CI",
                "model_form_uncertainty_disclosure":"MODEL OUTPUT MATCH ONLY; no real measurement uncertainty",
                **{k:True for k in REQUIRED_METADATA},
            }
            raw=[]
            keys=(*REQUIRED_MEASURED_FIELDS,"compressor_discharge_T_K","split")
            for i in range(10):
                ambient=288.15+i*.2
                pressure=101325.+i*10
                inlet=.01;back=.02
                row={k:"test-fixture" for k in REQUIRED_MEASURED_FIELDS}
                row.update({
                    "timestamp_utc":(datetime(2026,1,1,tzinfo=timezone.utc)+timedelta(days=i)).isoformat(),
                    "unit_id":unit,"operating_mode":"steady_full_load",
                    "ambient_T_K":ambient,
                    "compressor_flange_T_K":ambient,
                    "ambient_P_Pa":pressure,
                    "compressor_flange_P_Pa":pressure*(1-inlet),
                    "turbine_exhaust_flange_P_Pa":pressure*(1+back),
                    "compressor_air_mass_flow_kg_s":100.+i*.3,
                    "fuel_LHV_J_kg":50e6,
                    "compressor_pressure_ratio":14.7+i*.08,
                    "turbine_firing_T_K":1390.+i*3.,
                    "generator_efficiency":.985,
                    "inlet_loss_fraction":inlet,
                    "exhaust_loss_fraction":back,
                    "instrument_uncertainty_profile_id":"SYNTHETIC",
                    "hardware_and_component_map_id":hardware,
                    "fuel_composition_test_id":"SYNTHETIC",
                    "operating_point_id":f"MATHEMATICAL-{i}",
                    "split":"development" if i<6 else "untouched_test",
                })
                raw.append(row)
            deck=[case(row,plan,.86,.89,f"MATH{i}") for i,row in enumerate(raw)]
            truth=run_fortran(exe,deck,tmp)
            for row,y in zip(raw,truth):
                row.update({
                  "compressor_discharge_T_K":float(y["T2_K"]),
                  "exhaust_T_K":float(y["T4_K"]),
                  "net_electric_power_MW":float(y["net_power_MW"]),
                  "fuel_mass_flow_kg_s":float(y["fuel_flow_kg_s"]),
                })
            path=tmp/"math_source.csv"
            with path.open("w",newline="",encoding="utf-8") as file:
                writer=csv.DictWriter(file,fieldnames=keys)
                writer.writeheader();writer.writerows(raw)
            plan["source_csv_sha256"]=digest(path)
            plan_file=tmp/"math_plan.json"
            plan_file.write_text(json.dumps(plan),encoding="utf-8")
            # Full real Fortran binary is exercised, but this fixture is
            # manufactured from the exact same model. It CANNOT measure field
            # predictive accuracy; this test only checks code consistency.
            report=calibrate(path,plan_file,exe,tmp/"output")
            self.assertEqual(report["status"],
                "CONDITIONAL_MEASURED_COMPARISON_REQUIRES_INDEPENDENT_REVIEW")
            self.assertAlmostEqual(report["fitted_eta_compressor"],.86,delta=.008)
            self.assertAlmostEqual(report["fitted_eta_turbine"],.89,delta=.008)
            self.assertEqual(report["development_rows"],6)
            self.assertEqual(report["untouched_test_rows"],4)
            self.assertTrue(report["no_test_targets_or_measured_power_used_for_fitting"])
            self.assertFalse(report["industrial_field_accuracy_verified"])
            self.assertTrue((tmp/"output"/"independent_holdout_predictions.csv").exists())
            # Defeat exact source binding; an instrument file change cannot
            # be silently fitted as though the original measurements survived.
            path.write_bytes(path.read_bytes()+b"\n")
            with self.assertRaisesRegex(ValueError,"SHA256"):
                calibrate(path,plan_file,exe,tmp/"blocked")
            b=json.loads((tmp/"blocked"/"gt_physical_calibration_report.json").read_text())
            self.assertEqual(b["status"],"BLOCKED_NO_ELIGIBLE_TRACEABLE_DATA")

if __name__=="__main__":
    unittest.main()
