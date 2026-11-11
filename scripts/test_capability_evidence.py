"""Negative and positive tests of engineering claim/evidence gates; no physical data."""
import copy
import json
from pathlib import Path
import unittest

from scripts.check_capability_evidence import ROOT, audit

SOURCE=json.loads((ROOT/"docs/capability_evidence.json").read_text(encoding="utf-8"))

class EvidenceInventory(unittest.TestCase):
    def test_actual_repository_manifest(self):
        r=audit(ROOT,SOURCE)
        self.assertTrue(r["blocked_industrial_validation"])
        self.assertGreaterEqual(r["capabilities_audited"],17)
        self.assertFalse(r["approved_industrial_deployment"])

    def test_missing_path_is_rejected(self):
        d=copy.deepcopy(SOURCE)
        d["capabilities"][0]["paths"].append("docs/this-is-not-a-real-document.md")
        with self.assertRaisesRegex(ValueError,"missing"):
            audit(ROOT,d)

    def test_traversal_is_rejected(self):
        d=copy.deepcopy(SOURCE)
        d["capabilities"][0]["paths"].append("../outside.txt")
        with self.assertRaisesRegex(ValueError,"Unsafe"):
            audit(ROOT,d)

    def test_invented_ci_artifact_is_rejected(self):
        d=copy.deepcopy(SOURCE)
        d["capabilities"][0]["source_artifacts"].append("imaginary-validated-OEM-plant")
        with self.assertRaisesRegex(ValueError,"CI evidence"):
            audit(ROOT,d)

    def test_false_industrial_claim_is_rejected(self):
        d=copy.deepcopy(SOURCE)
        d["capabilities"][0]["independent_field_validation"]=True
        with self.assertRaisesRegex(ValueError,"independent-field"):
            audit(ROOT,d)

    def test_unsupported_humidity_cannot_be_promoted(self):
        d=copy.deepcopy(SOURCE)
        next(x for x in d["capabilities"] if x["id"]=="humidity_physics")["status"]="implemented"
        with self.assertRaises(ValueError):
            audit(ROOT,d)

    def test_duplicate_feature_is_rejected(self):
        d=copy.deepcopy(SOURCE)
        d["capabilities"].append(copy.deepcopy(d["capabilities"][0]))
        with self.assertRaisesRegex(ValueError,"duplicate"):
            audit(ROOT,d)

if __name__=="__main__":
    unittest.main()
