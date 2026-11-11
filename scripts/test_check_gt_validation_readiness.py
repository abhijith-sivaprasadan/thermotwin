"""Unit tests for readiness contract. Artificial field names only; no engine measurements."""
import tempfile
import unittest
from pathlib import Path
from scripts.check_gt_validation_readiness import gate, inspect, REQUIRED_MEASURED_FIELDS, REQUIRED_METADATA


class Prerequisites(unittest.TestCase):
    def test_external_smart_schema_rejects_claim(self):
        fields=("AT","AP","DF","CH","GP","CPR","CPD","TTXM","EP")
        a=gate(fields)
        self.assertFalse(a["experimentally_traceable_validation_ready"])
        self.assertFalse(a["engine_accuracy_verified"])
        self.assertTrue(any(x["field"]=="fuel_mass_flow_kg_s" for x in a["missing_measured_fields"]))
        self.assertTrue(any(x["field"]=="timestamp_utc" for x in a["missing_measured_fields"]))

    def test_all_fields_without_calibration_rejected(self):
        a=gate(REQUIRED_MEASURED_FIELDS,quality={"rows_inspected":1,"invalid_or_incomplete_rows":0})
        self.assertTrue(a["has_minimal_complete_measurement_bundle"])
        self.assertFalse(a["experimentally_traceable_validation_ready"])
        self.assertTrue(a["unverified_independent_prerequisites"])

    def test_complete_metadata_only_reaches_readiness_not_model_validation(self):
        a=gate(REQUIRED_MEASURED_FIELDS,{x:True for x in REQUIRED_METADATA},{"rows_inspected":1,"invalid_or_incomplete_rows":0})
        self.assertTrue(a["required_document_attestations_declared"])
        self.assertFalse(a["experimentally_traceable_validation_ready"])
        self.assertFalse(a["engine_accuracy_verified"])
        self.assertFalse(a["measured_heat_rate_verified"])
        self.assertFalse(a["OEM_or_contractual_passoff_established"])

    def test_unsupported_truthy_string_not_accepted(self):
        metadata={x:"yes" for x in REQUIRED_METADATA}
        a=gate(REQUIRED_MEASURED_FIELDS,metadata)
        self.assertFalse(a["experimentally_traceable_validation_ready"])

    def test_source_csv_fails_closed_with_clear_missing_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)
            inp=p/"source.csv"
            inp.write_text("AT,AP,EP\n10,29,100\n")
            a=inspect(inp,p/"audit.json")
            self.assertFalse(a["experimentally_traceable_validation_ready"])
            self.assertTrue((p/"audit.json").exists())

    def test_header_only_never_claims_complete_measurement_bundle(self):
        r=gate(REQUIRED_MEASURED_FIELDS,{x:True for x in REQUIRED_METADATA})
        self.assertTrue(r["required_measurement_headers_present"])
        self.assertFalse(r["has_minimal_complete_measurement_bundle"])
        self.assertFalse(r["required_document_attestations_declared"])

    def test_header_only_csv_and_incomplete_values_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)
            path=p/"full.csv"
            names=list(REQUIRED_MEASURED_FIELDS)
            path.write_text(",".join(names)+"\n",encoding="utf-8")
            empty=inspect(path,p/"empty.json")
            self.assertEqual(empty["rows_inspected"],0)
            self.assertFalse(empty["has_minimal_complete_measurement_bundle"])
            # A row can have all 21 headings but contain invalid/blank contents.
            invalid={key:"1" for key in names}
            invalid["timestamp_utc"]="not-a-timestamp"
            invalid["fuel_mass_flow_kg_s"]=""
            path.write_text(",".join(names)+"\n"+",".join(invalid[n] for n in names)+"\n",encoding="utf-8")
            bad=inspect(path,p/"bad.json")
            self.assertEqual(bad["invalid_or_incomplete_rows"],1)
            self.assertFalse(bad["has_minimal_complete_measurement_bundle"])

    def test_missing_or_extra_csv_cells_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)
            path=p/"source.csv"
            path.write_text("AT,AP,EP\n10,29,100,extra\n",encoding="utf-8")
            r=inspect(path,p/"audit.json")
            self.assertEqual(r["invalid_or_incomplete_rows"],1)
            self.assertFalse(r["has_minimal_complete_measurement_bundle"])


if __name__=="__main__":
    unittest.main()
