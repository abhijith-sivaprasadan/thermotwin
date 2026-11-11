"""Pure mathematical and temporary synthetic ZIP fixtures; NOT measured turbine results."""
from __future__ import annotations

import io
import math
import unittest
import zipfile

import numpy as np

from scripts.fetch_uci994_microgt import (
    EXPECTED_TOTAL, TRAIN, TEST, experiment_id, original_csv, source_experiments,
)
from scripts.forecast_uci994_microgt import (
    TAU_CANDIDATES_S, evaluate, open_loop, score,
)


def math_experiments():
    """Deterministic artificial first-order system to prove causal model algebra."""
    beta=np.array([120.0,30.0,3.0])
    all_data={}
    for experiment in (*TRAIN,*TEST):
        n=165
        time=np.arange(n,dtype=float)
        u=4+2*np.sin(time/13.+experiment*.2)
        y=open_loop(time,u,320.0,beta,16.0,5000.)
        all_data[experiment]=(time,u,y)
    return all_data


class ForecastMathematicalContracts(unittest.TestCase):
    def test_time_monotonic_and_causal_open_loop(self):
        beta=np.array([100.,20.,2.])
        t=np.arange(100,dtype=float)
        v=np.linspace(2.,8.,100)
        a=open_loop(t,v,500.,beta,16.,10000.)
        different=open_loop(t,v,500.,beta,16.,10000.)
        np.testing.assert_array_equal(a,different)
        shifted=v.copy()
        shifted[50:]+=2.
        b=open_loop(t,shifted,500.,beta,16.,10000.)
        np.testing.assert_array_equal(a[:50],b[:50])
        self.assertGreater(abs(a[-1]-b[-1]),10.)
        with self.assertRaisesRegex(ValueError,"Invalid"):
            open_loop(np.array([0.,2.,1.]),np.ones(3),100.,beta,16.,1000.)

    def test_frozen_holdout_inputs_do_not_use_future_measured_outputs(self):
        d=math_experiments()
        train={i:d[i] for i in TRAIN}
        test={i:d[i] for i in TEST}
        report,results=evaluate(train,test)
        self.assertEqual(report["test_experiments"],list(TEST))
        self.assertLess(report["test_rmse_watt"],1.0)
        self.assertFalse(report["uses_future_measured_power_as_input"])
        altered={key:(t,u,y.copy()) for key,(t,u,y) in test.items()}
        altered[4][2][50:]+=500. # change only future observed test power
        report2,new=evaluate(train,altered)
        np.testing.assert_allclose(results[4]["predicted"],new[4]["predicted"])
        np.testing.assert_allclose(results[22]["predicted"],new[22]["predicted"])
        self.assertGreater(report2["test_rmse_watt"],report["test_rmse_watt"]+10.)

    def test_frozen_training_identity_and_baseline(self):
        data=math_experiments()
        report,_=evaluate({i:data[i] for i in TRAIN},{i:data[i] for i in TEST})
        self.assertIn(report["time_constant_s"],TAU_CANDIDATES_S)
        self.assertTrue(math.isfinite(report["static_baseline_rmse_watt"]))
        self.assertTrue(math.isfinite(report["test_rmse_watt"]))
        self.assertEqual(report["test_points_scored"],2*(165-1))
        with self.assertRaisesRegex(ValueError,"original"):
            evaluate({1:data[1]}, {4:data[4]})

    def test_import_schema_and_member_id_guards(self):
        self.assertEqual(experiment_id("experiment_24_short.csv"),24)
        self.assertEqual(experiment_id("ex_4.csv"),4)
        self.assertIsNone(experiment_id("experiment_18_short.csv"))
        lines="time|input_voltage|el_power\n" + "".join(
            f"{i}|{4+i*.001}|{120+i*.01}\n" for i in range(6495)
        )
        points=original_csv(lines.encode(),"synthetic-fixture")
        self.assertEqual(len(points),6495)
        with self.assertRaisesRegex(ValueError,"Non-increasing"):
            original_csv(("time|input_voltage|el_power\n"+"1|4|10\n"*6500).encode(),"fixture")
        with self.assertRaisesRegex(ValueError,"Missing/duplicate"):
            original_csv(("time|bad_voltage|el_power\n"+"1|4|10\n"*6500).encode(),"fixture")

    def test_original_zip_integrity_exact_eight_independent_experiments(self):
        # This is an artificial archive generated only inside this test, never
        # written to a source-backed CI artifact as a turbine observation.
        sizes={experiment:9000 for experiment in (*TRAIN,*TEST)}
        sizes[24]=EXPECTED_TOTAL-7*9000
        self.assertEqual(sum(sizes.values()),EXPECTED_TOTAL)
        buffer=io.BytesIO()
        with zipfile.ZipFile(buffer,"w",compression=zipfile.ZIP_DEFLATED) as outer:
            for label,experiments in (("train.zip",TRAIN),("test.zip",TEST)):
                inner=io.BytesIO()
                with zipfile.ZipFile(inner,"w",compression=zipfile.ZIP_DEFLATED) as archive:
                    for experiment in experiments:
                        text="time|input_voltage|el_power\n" + "".join(
                            f"{i}|{4+i*.00001}|{100+i*.0001}\n" for i in range(sizes[experiment])
                        )
                        archive.writestr(f"experiment_{experiment}_short.csv",text)
                outer.writestr(label,inner.getvalue())
        all_experiments=source_experiments(buffer.getvalue())
        self.assertEqual(set(all_experiments),set(TRAIN+TEST))
        self.assertEqual(sum(len(v[0]) for v in all_experiments.values()),EXPECTED_TOTAL)


if __name__=="__main__":
    unittest.main()
