"""Software tests only: artificial rows are NOT real turbine validation evidence."""
from __future__ import annotations
import math
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from xml.etree import ElementTree as ET
from scripts.audit_real_esan_gt2017 import (
    ORIGINAL_SHA256, ORIGINAL_WORKSHEETS, SOURCE_ROWS,
    get_original, metric, number, parse_cells, sha,
)


class RealEsanSourceContracts(unittest.TestCase):
    def test_pinned_original_hash_and_no_network_on_local_replay(self):
        self.assertEqual(len(ORIGINAL_SHA256),64)
        self.assertEqual(ORIGINAL_WORKSHEETS,317)
        with tempfile.TemporaryDirectory() as td:
            f=Path(td)/"forged-original.xlsx"
            f.write_bytes(b"PK-this-is-not-a-real-measured-workbook")
            with self.assertRaisesRegex(ValueError,"SHA-256 mismatch"):
                get_original(f)

    def test_original_row_labels_include_units_and_are_not_pseudo_stations(self):
        self.assertEqual(SOURCE_ROWS[11],"Compressor outlet air pressure (PCD) (barg)")
        self.assertEqual(SOURCE_ROWS[31],"Gas fuel flow (kg/h)")
        self.assertEqual(SOURCE_ROWS[39],"Real power (kW)")
        self.assertEqual(SOURCE_ROWS[42],"Power factor (None)")
        self.assertNotIn("turbine_firing_T_K",SOURCE_ROWS.values())
        self.assertNotIn("fuel_LHV_J_kg",SOURCE_ROWS.values())

    def test_arithmetic_and_identity_score(self):
        # Three-phase mathematical values; *not* measured source observations.
        voltage=11000.
        current=100.
        pf=.9
        calculated=math.sqrt(3)*voltage*current*pf/1000.
        example={"measured_real_power_kW":calculated+10.,"measured_minus_reconstructed_kW":10.}
        m=metric([example,example])
        self.assertAlmostEqual(m["rmse_kW"],10.,places=12)
        self.assertAlmostEqual(m["bias_observed_minus_identity_kW"],10.,places=12)
        self.assertEqual(m["n"],2)
        with self.assertRaisesRegex(ValueError,"No actual observed"):
            metric([])

    def test_value_parser_rejects_fabricated_or_nonfinite(self):
        self.assertIsNone(number("SHUTDOWN ON AUTHORITY REQUEST"))
        self.assertIsNone(number("nan"))
        self.assertIsNone(number("inf"))
        self.assertIsNone(number(""))
        self.assertEqual(number("450"),450.0)

    def test_reject_derived_formula_cells_in_instrument_channels(self):
        ns="{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
        root=ET.fromstring(
            f'<worksheet xmlns="{ns[1:-1]}"><sheetData>'
            '<row r="39"><c r="B39"><f>1+2</f><v>3</v></c></row>'
            '</sheetData></worksheet>'
        )
        with self.assertRaisesRegex(ValueError,"formulas"):
            parse_cells(root,[],{39})


if __name__=="__main__":
    unittest.main()
