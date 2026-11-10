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
        a=gate(REQUIRED_MEASURED_FIELDS)
        self.assertTrue(a["has_minimal_complete_measurement_bundle"])
        self.assertFalse(a["experimentally_traceable_validation_ready"])
        self.assertTrue(a["unverified_independent_prerequisites"])

    def test_complete_metadata_only_reaches_readiness_not_model_validation(self):
        a=gate(REQUIRED_MEASURED_FIELDS,{x:True for x in REQUIRED_METADATA})
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


if __name__=="__main__":
    unittest.main()
