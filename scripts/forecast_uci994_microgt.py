#!/usr/bin/env python3
"""Source-verified open-loop micro gas turbine power prediction from voltage plan.

Real data: UCI #994 commercial 3 kW microturbine, 8 experiments with time in s,
input_voltage V and measured output el_power W.
Train 1,9,20,21,23,24; NEVER fit/select using heldout 4,22.
This is measured input-to-output DYNAMICAL SURROGATE, not the Fortran 30 MW
Brayton-cycle model, fault diagnosis, or a qualified industrial GT controller.
"""
from __future__ import annotations

import argparse
import csv
from hashlib import sha256
import json
import math
import os
from pathlib import Path
import numpy as np

from scripts.fetch_uci994_microgt import COLUMNS, DOI, EXPECTED_TOTAL, TRAIN, TEST


TAU_CANDIDATES_S = (1., 2., 4., 8., 16., 32., 64., 128., 256., 512.)


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def load_audited(data_dir: Path) -> tuple[dict, dict[int, tuple[np.ndarray, np.ndarray, np.ndarray]]]:
    m = json.loads((data_dir / "manifest.json").read_text(encoding="utf-8"))
    if (m.get("schema") != "thermotwin.uci994.original_micro_turbine.v1"
            or m.get("doi") != DOI
            or m.get("training_experiments") != list(TRAIN)
            or m.get("untouched_test_experiments") != list(TEST)
            or m.get("total_observations") != EXPECTED_TOTAL
            or set(m.get("experiments", {})) != set(map(str, TRAIN+TEST))):
        raise ValueError("UCI original source provenance / experimental split mismatch")
    if digest(data_dir / "uci994_original.zip") != m.get("original_zip_sha256"):
        raise ValueError("Original source ZIP SHA-256 mismatch")
    data = {}
    for exp in (*TRAIN, *TEST):
        entry = m["experiments"][str(exp)]
        if entry.get("split") != ("test" if exp in TEST else "train"):
            raise ValueError("Training/test source split conflict")
        path = data_dir / entry["audited_csv"]
        if path.name != f"experiment_{exp}_audited.csv":
            raise ValueError("Unexpected audited CSV member path")
        if digest(path) != entry["audited_csv_sha256"]:
            raise ValueError("Original audited experiment CSV mutated")
        with path.open(encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            if tuple(reader.fieldnames or ()) != COLUMNS:
                raise ValueError("Audited source time/voltage/power schema mismatch")
            triplets = []
            for row in reader:
                triplets.append(tuple(float(row[key]) for key in COLUMNS))
        points = np.asarray(triplets, dtype=float)
        if (points.shape != (entry["n"],3) or not np.isfinite(points).all()
                or not np.all(np.diff(points[:,0])>0)):
            raise ValueError("Original source experiment wrong size or non-monotonic time")
        data[exp] = (points[:,0],points[:,1],points[:,2])
    if sum(len(d[0]) for d in data.values()) != EXPECTED_TOTAL:
        raise ValueError("Source observations not complete")
    return m, data


def single_experiment(data) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    t,u,y = [np.asarray(v,dtype=float) for v in data]
    if (t.ndim!=1 or len(t)<12 or len(u)!=len(t) or len(y)!=len(t)
            or not np.isfinite(t).all() or not np.isfinite(u).all()
            or not np.isfinite(y).all() or not np.all(np.diff(t)>0)):
        raise ValueError("Malformed experiment time, control or measured power")
    return t,u,y


def coefficients_for_tau(experiments: dict, tau_s: float) -> np.ndarray:
    if tau_s <= 0 or not math.isfinite(tau_s) or not experiments:
        raise ValueError("Invalid dynamical model time constant or training data")
    mats,targets=[],[]
    for seq in experiments.values():
        t,u,y=single_experiment(seq)
        alpha=-np.expm1(-np.diff(t)/tau_s)
        design=alpha[:,None]*np.column_stack((np.ones(len(u)-1),u[1:],u[1:]**2))
        rhs=y[1:]-(1-alpha)*y[:-1]
        mats.append(design)
        targets.append(rhs)
    x=np.concatenate(mats);target=np.concatenate(targets)
    beta,_,rank,_=np.linalg.lstsq(x,target,rcond=None)
    if rank!=3 or not np.isfinite(beta).all():
        raise ValueError("Cannot identify voltage-power stationary mapping")
    return beta


def open_loop(t: np.ndarray,u: np.ndarray, initial_w: float,
              beta: np.ndarray,tau_s: float,limit_w: float) -> np.ndarray:
    """One measured initial state only; all future y values are autoregressive predictions.

    Input voltage at each time is the predeclared control/command trajectory.
    """
    t=np.asarray(t,dtype=float);u=np.asarray(u,dtype=float)
    beta=np.asarray(beta,dtype=float)
    if (len(t)!=len(u) or not len(t) or not np.isfinite(t).all()
            or not np.isfinite(u).all() or not np.all(np.diff(t)>0)
            or beta.shape!=(3,) or not np.isfinite(beta).all()
            or not math.isfinite(initial_w) or limit_w<=0 or tau_s<=0):
        raise ValueError("Invalid open-loop dynamic forecast specification")
    y=np.empty(len(t),dtype=float)
    y[0]=initial_w  # declared one-point initialization, not used in scored rows
    for i in range(1,len(t)):
        alpha=-math.expm1(-(t[i]-t[i-1])/tau_s)
        equilibrium=float(beta[0]+beta[1]*u[i]+beta[2]*u[i]*u[i])
        equilibrium=min(limit_w,max(0.,equilibrium))
        y[i]=(1-alpha)*y[i-1]+alpha*equilibrium
    return y


def static_fit(experiments:dict) -> np.ndarray:
    xs=[];ys=[]
    for seq in experiments.values():
        _,u,y=single_experiment(seq)
        xs.append(np.column_stack([np.ones(len(u)),u,u*u]))
        ys.append(y)
    beta,_,rank,_=np.linalg.lstsq(np.concatenate(xs),np.concatenate(ys),rcond=None)
    if rank!=3:
        raise ValueError("Static voltage variation insufficient to fit baseline")
    return beta


def score(actual,pred) -> dict:
    actual=np.asarray(actual,dtype=float)
    pred=np.asarray(pred,dtype=float)
    if (len(actual)!=len(pred) or not len(actual)
            or not np.isfinite(actual).all() or not np.isfinite(pred).all()):
        raise ValueError("Cannot score nonfinite or missing observed power")
    delta=actual-pred
    return {"rmse_watt":float(np.sqrt(np.mean(delta*delta))),
            "mae_watt":float(np.mean(abs(delta))),
            "bias_observed_minus_predicted_watt":float(delta.mean()),
            "n":len(delta)}


def select_tau(training:dict, candidates=TAU_CANDIDATES_S):
    """Leave-one-experiment-out CV on TRAIN experiments only, open-loop."""
    if len(training)<3:
        raise ValueError("Need at least three distinct calibration experiments")
    cv={}
    limit=max(float(max(single_experiment(v)[2])) for v in training.values())*1.5
    for tau in candidates:
        if not math.isfinite(tau) or tau<=0:
            raise ValueError("Invalid candidate tau")
        squared=[]
        for validation_id in sorted(training):
            fit={key:seq for key,seq in training.items() if key!=validation_id}
            beta=coefficients_for_tau(fit,tau)
            t,u,y=single_experiment(training[validation_id])
            predicted=open_loop(t,u,float(y[0]),beta,tau,limit)
            squared.extend(((y[1:]-predicted[1:])**2).tolist())
        cv[str(tau)]=float(math.sqrt(np.mean(squared)))
    winner=min(candidates,key=lambda tau:(cv[str(tau)],tau))
    return winner,cv


def evaluate(training:dict, holdout:dict) -> tuple[dict,dict]:
    if set(training)!=set(TRAIN) or set(holdout)!=set(TEST):
        raise ValueError("Original official training/test experiment IDs required")
    for seq in (*training.values(),*holdout.values()):
        single_experiment(seq)
    tau,cv=select_tau(training)
    beta=coefficients_for_tau(training,tau)
    static_beta=static_fit(training)
    combined_voltage=np.concatenate([np.asarray(v[1],dtype=float) for v in training.values()])
    combined_power=np.concatenate([np.asarray(v[2],dtype=float) for v in training.values()])
    lower,upper=float(min(combined_voltage)),float(max(combined_voltage))
    power_limit=max(float(max(combined_power))*1.5,1.)
    report_exps={}
    actual_all=[];pred_all=[];static_all=[]
    outputs={}
    for exp in TEST:
        t,u,y=single_experiment(holdout[exp])
        dynamic=open_loop(t,u,float(y[0]),beta,tau,power_limit)
        stationary=np.clip(static_beta[0]+static_beta[1]*u+static_beta[2]*u*u,
                           0.,power_limit)
        mask=(u<lower)|(u>upper)
        # First observed output is solely an initial condition, NOT scored.
        # No y[t] from t>=1 is ever used to predict future output.
        dynamic_score=score(y[1:],dynamic[1:])
        static_score=score(y[1:],stationary[1:])
        report_exps[str(exp)]={
            **dynamic_score,"static_baseline_rmse_watt":static_score["rmse_watt"],
            "voltage_outside_train_range_fraction":float(mask[1:].mean()),
            "initial_measured_power_watt_for_warmstart":float(y[0]),
            "warmstart_samples_not_scored":1,
        }
        outputs[exp]={"time":t,"voltage":u,"measured":y,"predicted":dynamic,
                      "static":stationary,"outside":mask}
        actual_all.append(y[1:]);pred_all.append(dynamic[1:]);static_all.append(stationary[1:])
    scores=score(np.concatenate(actual_all),np.concatenate(pred_all))
    baseline=score(np.concatenate(actual_all),np.concatenate(static_all))
    report={
        "schema":"thermotwin.uci994.microgt_open_loop_prediction.v1",
        "model":"bounded first-order lag to quadratic voltage equilibrium",
        "time_constant_s":float(tau),
        "equilibrium_coefficients_watt_vs_volt":beta.tolist(),
        "static_baseline_coefficients_watt_vs_volt":static_beta.tolist(),
        "train_experiments":list(TRAIN),
        "test_experiments":list(TEST),
        "train_only_leave_one_experiment_out_cv_rmse_watt":cv,
        "test_rmse_watt":scores["rmse_watt"],
        "test_mae_watt":scores["mae_watt"],
        "test_bias_observed_minus_predicted_watt":scores["bias_observed_minus_predicted_watt"],
        "static_baseline_rmse_watt":baseline["rmse_watt"],
        "test_points_scored":scores["n"],
        "per_test_experiment":report_exps,
        "observed_voltage_training_min_v":lower,
        "observed_voltage_training_max_v":upper,
        "equilibrium_power_limit_watt":power_limit,
        "uses_future_measured_power_as_input":False,
        "initial_measured_power_per_test_experiment_only":True,
        "has_actual_time_axis_seconds":True,
        "is_oem_cycle_thermodynamics":False,
        "is_fault_prediction":False,
        "data": "real UCI 994 microturbine (~3 kW), not 30 MW industrial gas turbine",
        "forecast_type": "open-loop response to known/commanded future control-voltage trajectory",
        "limitations":[
            "Small commercial 3 kW turbine, cannot transfer coefficients to 30 MW generic Brayton engine",
            "System identification of input-voltage-to-electrical-power only, no internal stations/fuel/thermodynamics",
            "Test experiment first measured power sample is an explicitly declared warm-start, not scored",
            "Voltage trajectory through entire forecast horizon is assumed supplied/known as a commanded input",
            "Unseen experiment holdout is not unseen turbine validation, and a good fit is not a safety claim",
            "Time is relative per experiment, not a proven synchronized wall-clock calendar timestamp",
            "Voltage support checks are descriptive, not a physical safety operating envelope",
        ]
    }
    return report,outputs


def export_predictions(out:Path,results:dict,report:dict):
    out.mkdir(parents=True,exist_ok=True)
    columns=("experiment","time_s","input_voltage_v","measured_el_power_w",
             "predicted_open_loop_el_power_w","static_voltage_baseline_w",
             "residual_measured_minus_forecast_w","voltage_outside_training_range",
             "initial_state_observation_not_scored")
    output=out/"heldout_microturbine_power_forecast.csv"
    with output.open("w",encoding="utf-8",newline="") as handle:
        writer=csv.writer(handle)
        writer.writerow(columns)
        for exp in TEST:
            e=results[exp]
            for i in range(len(e["time"])):
                writer.writerow((exp,float(e["time"][i]),float(e["voltage"][i]),
                    float(e["measured"][i]),float(e["predicted"][i]),
                    float(e["static"][i]),float(e["measured"][i]-e["predicted"][i]),
                    int(e["outside"][i]),int(i==0)))
    report["predictions_csv_sha256"]=digest(output)



def write_interactive_viewer(out: Path, outputs: dict, report: dict) -> None:
    """Self-contained local real-signal viewer. No external libraries or fabricated data."""
    payload={}
    for exp in TEST:
        seq=outputs[exp]
        payload[str(exp)]=[
            [round(float(seq["time"][i]),4),round(float(seq["voltage"][i]),4),
             round(float(seq["measured"][i]),4),round(float(seq["predicted"][i]),4),
             round(float(seq["static"][i]),4),int(seq["outside"][i])]
            for i in range(len(seq["time"]))
        ]
    body=json.dumps(payload,separators=(",",":"),allow_nan=False).replace("<","\\u003c")
    doc="""<!doctype html><html lang="en"><head><meta charset="utf-8">
<title>Measured 3-kW micro gas turbine | ThermoTwin-F</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{color-scheme:dark}body{margin:auto;max-width:1140px;padding:28px;
background:#0c1b26;color:#edf4f6;font:15px system-ui,Arial}
p{line-height:1.6;color:#afc1d0}.metrics{display:flex;gap:12px;flex-wrap:wrap}
.metrics section{padding:16px;flex:1;border:1px solid #49616e;min-width:160px}
h1{font-size:26px}strong{display:block;font-size:24px}
label{display:block;margin-top:14px}select,input{width:100%;padding:7px}
canvas{width:100%;height:350px;background:#091622;border:1px solid #3b5565}
a{color:#70cbdc}.caption{font-size:13px}.source{color:#7ed7ec}
</style></head><body>
<h1>ThermoTwin-F · Measured microturbine dynamic response</h1>
<p>REAL UCI #994 observed power (W) versus open-loop predicted power (W).
3-kW-class experimental gas turbine, not an industrial 30 MW cycle model.
Train runs 1/9/20/21/23/24; independent test runs 4/22.</p>
<div class="metrics">
<section>Open-loop RMSE (W)<strong id="dynamic"></strong></section>
<section>Static voltage baseline RMSE (W)<strong id="static"></strong></section>
<section>Fitted dynamic lag (s)<strong id="tau"></strong></section></div>
<p class="source">Cyan = original measured power &nbsp; · &nbsp;
Amber = dynamic prediction &nbsp; · &nbsp; Grey = static prediction</p>
<label for="exp">Held-out experiment</label>
<select id="exp"><option value="4">Experiment 4</option><option value="22">Experiment 22</option></select>
<canvas id="chart" width="1060" height="350" role="img"
aria-label="Measured power against model predictions at actual source relative time"></canvas>
<label for="cursor">Measured experiment time (seconds)</label>
<input type="range" id="cursor" min="0" max="100" step="1" value="0">
<p id="readout" aria-live="polite"></p>
<p class="caption">Only the very first measured power is used to initialize
each test forecast and is excluded from scores. Later measured power values
are NEVER used to advance the prediction. Input voltage over the horizon is a
known supplied control trajectory; this is not unknown-weather forecasting.
No future failure diagnosis, certified safety limit or thermodynamic
performance prediction is supported.</p>
<p><a href="https://doi.org/10.24432/C58S4T">Real source: UCI micro gas turbine
electrical energy prediction dataset (CC BY 4.0)</a></p>
<script>
"use strict";
const series=__SOURCE_POINTS__;
const metrics=__REPORT_METRICS__;
document.getElementById("dynamic").textContent=metrics[0].toFixed(2);
document.getElementById("static").textContent=metrics[1].toFixed(2);
document.getElementById("tau").textContent=metrics[2].toFixed(1);
const sel=document.getElementById("exp"),range=document.getElementById("cursor");
const canvas=document.getElementById("chart"),ctx=canvas.getContext("2d");
function render(){
 const data=series[sel.value],i=Number(range.value),first=Math.max(0,i-230);
 const last=Math.min(data.length,i+231),points=data.slice(first,last);
 const bottom=318,top=22,left=35,right=canvas.width-20;
 const vals=points.flatMap(d=>[d[2],d[3],d[4]]);
 const lo=Math.min(...vals),hi=Math.max(...vals),span=Math.max(.001,hi-lo);
 ctx.clearRect(0,0,canvas.width,canvas.height);
 ctx.strokeStyle="#425667";ctx.lineWidth=1;
 for(let k=0;k<5;k++){let y=top+(bottom-top)*k/4;
   ctx.beginPath();ctx.moveTo(left,y);ctx.lineTo(right,y);ctx.stroke();}
 for(const [index,color] of [[2,"#67d5e7"],[3,"#ffc67d"],[4,"#858f97"]]){
   ctx.strokeStyle=color;ctx.lineWidth=1.8;ctx.beginPath();
   points.forEach((p,k)=>{const x=left+(right-left)*k/Math.max(1,points.length-1);
     const y=bottom-(p[index]-lo)/span*(bottom-top);
     if(k===0)ctx.moveTo(x,y);else ctx.lineTo(x,y);});
   ctx.stroke();
 }
 const row=data[i],at=left+(right-left)*(i-first)/Math.max(1,points.length-1);
 ctx.strokeStyle="white";ctx.lineWidth=1;ctx.beginPath();
 ctx.moveTo(at,top);ctx.lineTo(at,bottom);ctx.stroke();
 document.getElementById("readout").textContent="t="+row[0].toFixed(1)+
  " s | command "+row[1].toFixed(3)+" V | measured "+row[2].toFixed(1)+
  " W | predicted "+row[3].toFixed(1)+" W | residual "+
  (row[2]-row[3]).toFixed(1)+" W | "+(row[5]?"OUTSIDE TRAINING COMMAND RANGE":"in command range")+
  (i===0?" | initial measured state, NOT scored":"");
}
function reset(){range.max=String(series[sel.value].length-1);range.value="0";render();}
sel.addEventListener("change",reset);range.addEventListener("input",render);reset();
</script></body></html>"""
    metrics=json.dumps([
        report["test_rmse_watt"],report["static_baseline_rmse_watt"],
        report["time_constant_s"]],allow_nan=False)
    doc=doc.replace("__SOURCE_POINTS__",body).replace("__REPORT_METRICS__",metrics)
    (out/"real_microturbine_power_forecast.html").write_text(doc,encoding="utf-8")

def run(argv=None)->dict:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args(argv)
    manifest,experiments=load_audited(args.data_dir)
    train={i:experiments[i] for i in TRAIN}
    test={i:experiments[i] for i in TEST}
    report,outputs=evaluate(train,test)
    export_predictions(args.out,outputs,report)
    write_interactive_viewer(args.out,outputs,report)
    report['interactive_viewer_sha256']=digest(args.out/'real_microturbine_power_forecast.html')
    report.update({"source_doi":DOI,"source_zip_sha256":manifest["original_zip_sha256"],
                   "source_manifest_sha256":digest(args.data_dir/"manifest.json"),
                   "source_license":"CC BY 4.0","code_revision":os.environ.get("GITHUB_SHA","local")})
    (args.out/"forecast_report.json").write_text(
        json.dumps(report,indent=2,sort_keys=True,allow_nan=False)+"\n",encoding="utf-8")
    print("Real UCI 994 measured control-voltage -> power DYNAMICAL forecast, watts.")
    print("Train experiments:",TRAIN,"untouched test:",TEST)
    print("Selected tau (s):",report["time_constant_s"])
    print("Open-loop RMSE (W):",round(report["test_rmse_watt"],3),
          "static baseline RMSE (W):",round(report["static_baseline_rmse_watt"],3))
    print("Scored points:",report["test_points_scored"])
    print("Not OEM physics, industrial turbine, or safety control validation.")
    return report


if __name__=="__main__":
    run()
