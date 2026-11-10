"""Algebraic-only tests for independent measured-data validation gates.

The numerical rows below are mathematical fixtures, NOT actual turbine records.
"""
import csv
import math
from pathlib import Path
import tempfile
import unittest

from scripts.independent_smart_gtpp_checks import (
    close, pearson, pressure_unit_hypotheses, load, draw
)


class MeasuredEvidenceGates(unittest.TestCase):
    def test_exact_pressure_ratio_unit_hypotheses(self):
        ambient_inHg=100000/3386.38866667
        artificial=[{"AP":ambient_inHg,"CPD":10.0,"CPR":11.0}]
        d=pressure_unit_hypotheses(artificial)
        self.assertAlmostEqual(d["gauge_CPR_rmse"],0.0,places=8)
        self.assertAlmostEqual(d["absolute_CPR_rmse"],1.0,places=8)
        self.assertTrue(d["AP_inHg_CPD_bar_source_units_are_UNVERIFIED"])

    def test_invalid_pressure_and_null_values_rejected(self):
        for p in (0,-1,float("nan"),float("inf")):
            with self.subTest(p=p),self.assertRaises(ValueError):
                pressure_unit_hypotheses([{"AP":p,"CPD":10,"CPR":11}])

    def test_pearson_and_identity_guards(self):
        self.assertAlmostEqual(pearson([1,2,3,4],[6,4,2,0]),-1)
        self.assertAlmostEqual(pearson([1,2,3],[2,4,6]),1)
        close(1.02,102/100,"model ratio mathematical fixture")
        with self.assertRaises(ValueError):close(1.02,1.3,"wrong equation")
        with self.assertRaises(ValueError):pearson([1,1,1],[2,3,4])

    def test_fail_on_trailing_csv_unquoted_status_or_bad_header(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/"broken.csv"
            p.write_text("a,b\n1,foo,bar\n")
            with self.assertRaisesRegex(ValueError,"Malformed"):
                load(p)
            p.write_text('a,b\n1,"foo,bar"\n')
            keys,items=load(p)
            self.assertEqual(keys,["a","b"])
            self.assertEqual(items[0]["b"],"foo,bar")
            p.write_text("a,a\n1,2\n")
            with self.assertRaisesRegex(ValueError,"header"):load(p)

    def test_shape_svg_is_descriptive_only(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/"sample.svg"
            pts=[{"bin_center_C":x,"observed_EP_ratio":1+.01*x,
                  "generic_model_power_ratio":1-.005*x}
                 for x in (0,5,10,15,20)]
            draw(pts,p)
            text=p.read_text()
            self.assertIn("NOT predicted MW accuracy",text)
            self.assertIn("Source ambient T",text)


if __name__=="__main__":
    unittest.main()
