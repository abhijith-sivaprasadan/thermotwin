#!/usr/bin/env python3
"""Machine-specific Brayton calibration, with untouched independent tests.

No eligible plant data are bundled. Public observed UCI 551, UCI 994 and
SMART GTPP sources fail the full-cycle validation-data gate by design.
Calibrate from externally supplied, checksum-frozen, station-matched records
only. Fit eta_compressor and eta_turbine from measured T2 and T4 on
DEVELOPMENT rows only; evaluate electrical MW, fuel flow, heat rate and
station temperatures on later untouched test rows.

This program cannot authenticate third-party metrology documentation or
issue an OEM/contract guarantee. Its conclusions remain conditional.
"""
from __future__ import annotations
import argparse
import csv
from datetime import datetime
from hashlib import sha256
import json
import math
from pathlib import Path
import subprocess
import tempfile
import numpy as np
from scripts.check_gt_validation_readiness import (
    REQUIRED_MEASURED_FIELDS, REQUIRED_METADATA, gate, structurally_valid_row,
)

CASE_FIELDS = ("case_name","ambient_T_K","ambient_P_Pa","relative_humidity",
    "inlet_pressure_loss","mdot_air_kg_s","pressure_ratio","eta_compressor",
    "T_turbine_inlet_K","eta_combustor","combustor_pressure_loss","LHV_J_kg",
    "eta_turbine","exhaust_pressure_loss","eta_mechanical","eta_generator",
    "auxiliary_load_fraction","degradation_mode")
OBSERVED = {"T2_K":"compressor_discharge_T_K","T4_K":"exhaust_T_K",
            "net_power_MW":"net_electric_power_MW","fuel_flow_kg_s":"fuel_mass_flow_kg_s"}
METRICS = ("T2_K","T4_K","net_power_MW","fuel_flow_kg_s","heat_rate_kJ_kWh")
FIXED = ("eta_combustor","combustor_pressure_loss",
         "eta_mechanical","auxiliary_load_fraction","relative_humidity")
EXTRA = {"compressor_discharge_T_K","split"}
PUBLIC = {
 "UCI_551":{"doi":"10.24432/C5WC95",
     "source_columns":["AT","AP","AH","AFDP","GTEP","TIT","TAT","TEY","CDP","CO","NOX"],
     "why_blocked":"No known turbine identity/maps, matched fuel flow or metered heat rate; TEY units unresolved"},
 "SMART_GTPP":{"doi":"10.17632/6sk3mhm7hb.1",
     "source_columns":["AT","AP","DF","CH","GP","CPR","CPD","TTXM","EP"],
     "why_blocked":"Pressure units/stations and fuel mass-flow/chemistry/hardware maps unverified"},
 "UCI_994_MICRO_GT":{"doi":"10.24432/C58S4T",
     "source_columns":["time","input_voltage","el_power"],
     "why_blocked":"Measured 3-kW input/power dynamics only; no thermodynamic station or metered fuel record"}
}

def digest(path:Path)->str:
    return sha256(path.read_bytes()).hexdigest()

def audit_public()->dict:
    findings={}
    for name,source in PUBLIC.items():
        blocked=gate(source["source_columns"])
        findings[name]={**source,"original_schema_based_gate":blocked,
                        "usable_for_industrial_brayton_calibration":False}
    return {"schema":"thermotwin.physical_gt_data_readiness.v1",
            "status":"BLOCKED_NO_ELIGIBLE_MATCHED_PLANT_MEASUREMENTS",
            "public_dataset_gate":findings,
            "required_measured_columns":sorted(set(REQUIRED_MEASURED_FIELDS)|EXTRA),
            "real_engine_accuracy_established":False,
            "synthetic_data_accepted_as_field_evidence":False}

def numeric(v,low=None,high=None)->float:
    try:
        x=float(v)
    except (ValueError,TypeError) as err:
        raise ValueError("Missing/invalid finite physical reading") from err
    if not math.isfinite(x) or (low is not None and x<low) or (high is not None and x>high):
        raise ValueError("Physical quantity outside declared range: "+str(v))
    return x

def timestamp(s:str):
    try:
        dt=datetime.fromisoformat(s.replace("Z","+00:00"))
    except (ValueError,AttributeError) as err:
        raise ValueError("Invalid exact instrument UTC time") from err
    if dt.tzinfo is None or dt.utcoffset().total_seconds()!=0:
        raise ValueError("Original data timestamp not verified UTC")
    return dt

def validate_plan(meta:dict,measurements:Path)->None:
    if meta.get("schema")!="thermotwin.gt_physics_measured_plan.v1":
        raise ValueError("Missing calibrated GT measurement plan schema")
    if meta.get("source_csv_sha256")!=digest(measurements):
        raise ValueError("Source measurement bytes do not match pre-frozen SHA256")
    if not meta.get("unit_id") or not meta.get("hardware_and_component_map_id"):
        raise ValueError("Machine identity and fixed component map required")
    missing=sorted(key for key in REQUIRED_METADATA if meta.get(key) is not True)
    if missing:
        raise ValueError("Document/calibration attestations absent: "+", ".join(missing))
    fixed=meta.get("fixed_model_parameters")
    if not isinstance(fixed,dict) or set(fixed)!=set(FIXED):
        raise ValueError("Fixed component/model parameters not supplied by test plan")
    limits={"eta_combustor":(.8,1.),"combustor_pressure_loss":(0.,.15),
            "eta_mechanical":(.8,1.),"auxiliary_load_fraction":(0.,.2),
            "relative_humidity":(0.,0.)}
    for k,(lo,hi) in limits.items():
        numeric(fixed[k],lo,hi)
    if set(meta.get("fixed_parameter_source_ids",{}))!=set(FIXED) or any(
        not str(v).strip() for v in meta["fixed_parameter_source_ids"].values()
    ):
        raise ValueError("Every fixed model parameter needs independently identified source")
    uncertainties=meta.get("measured_standard_uncertainties",{})
    criteria=meta.get("predeclared_test_RMSE_limits",{})
    if set(uncertainties)!=set(METRICS) or set(criteria)!=set(METRICS):
        raise ValueError("Measured standard uncertainties and untouched RMSE thresholds required")
    for obj in (uncertainties,criteria):
        for val in obj.values():
            numeric(val,1.e-12,None)
    if not meta.get("validation_plan_id") or not meta.get("model_form_uncertainty_disclosure"):
        raise ValueError("Predeclared independent validation plan and model limitations missing")

def load_measurements(path:Path,meta:dict)->list[dict]:
    with path.open(newline="",encoding="utf-8-sig") as file:
        reader=csv.DictReader(file)
        fields=reader.fieldnames or []
        if not fields or len(set(fields))!=len(fields) or any(x!=x.strip() for x in fields):
            raise ValueError("Malformed source headers")
        required=set(REQUIRED_MEASURED_FIELDS)|EXTRA
        if not required.issubset(fields):
            raise ValueError("Missing actual physical sensor channels: "+str(sorted(required-set(fields))))
        rows=list(reader)
    if len(rows)<10:
        raise ValueError("Need at least 10 real steady operating points")
    for row in rows:
        if (not structurally_valid_row(row,required)
            or row["unit_id"]!=meta["unit_id"]
            or row["hardware_and_component_map_id"]!=meta["hardware_and_component_map_id"]
            or row["operating_mode"]!="steady_full_load"
            or row["split"] not in ("development","untouched_test")):
            raise ValueError("Invalid source, machine identity, steady mode or declared split")
        t2=numeric(row["compressor_discharge_T_K"],200,1700)
        if not (numeric(row["compressor_flange_T_K"],200,380)<t2<
                numeric(row["turbine_firing_T_K"],750,2200)):
            raise ValueError("Original compressor station temperatures inconsistent")
        if not (numeric(row["exhaust_T_K"],300,1500)<float(row["turbine_firing_T_K"])):
            raise ValueError("Original turbine expansion temperatures inconsistent")
        numeric(row["ambient_T_K"],200,350)
        numeric(row["compressor_pressure_ratio"],1.1,40)
        numeric(row["generator_efficiency"],.85,1.)
        numeric(row["fuel_LHV_J_kg"],1e7,1e8)
        numeric(row["compressor_air_mass_flow_kg_s"],1,None)
    times=[timestamp(row["timestamp_utc"]) for row in rows]
    if times!=sorted(set(times)):
        raise ValueError("Nonchronological/duplicate source time")
    ids=[row["operating_point_id"] for row in rows]
    if not all(ids) or len(ids)!=len(set(ids)):
        raise ValueError("Missing or duplicated source operating point ID")
    train=[row for row in rows if row["split"]=="development"]
    test=[row for row in rows if row["split"]=="untouched_test"]
    if len(train)<6 or len(test)<4 or rows!=train+test:
        raise ValueError("Training and later untouched test split is invalid")
    if timestamp(train[-1]["timestamp_utc"])>=timestamp(test[0]["timestamp_utc"]):
        raise ValueError("Untouched test chronology overlaps training")
    if (max(float(r["compressor_pressure_ratio"]) for r in train) -
        min(float(r["compressor_pressure_ratio"]) for r in train)<.05 and
        max(float(r["turbine_firing_T_K"]) for r in train) -
        min(float(r["turbine_firing_T_K"]) for r in train)<5):
        raise ValueError("Training regime lacks variation for identification")
    return rows

def case(row:dict,meta:dict,eta_c:float,eta_t:float,name:str)->dict:
    # The physical station data must agree with model inlet/outlet conventions.
    pamb=float(row["ambient_P_Pa"]);tin=float(row["ambient_T_K"])
    inlet=float(row["inlet_loss_fraction"]);outlet=float(row["exhaust_loss_fraction"])
    p1=float(row["compressor_flange_P_Pa"]);p4=float(row["turbine_exhaust_flange_P_Pa"])
    if (abs(p1-pamb*(1-inlet))>max(120.,.002*pamb) or
        abs(p4-pamb*(1+outlet))>max(120.,.002*pamb) or
        abs(float(row["compressor_flange_T_K"])-tin)>.75):
        raise ValueError("Measured flange boundaries inconsistent with fixed Fortran station model")
    fixed=meta["fixed_model_parameters"]
    return {"case_name":name,"ambient_T_K":tin,"ambient_P_Pa":pamb,
        "relative_humidity":fixed["relative_humidity"],"inlet_pressure_loss":inlet,
        "mdot_air_kg_s":float(row["compressor_air_mass_flow_kg_s"]),
        "pressure_ratio":float(row["compressor_pressure_ratio"]),
        "eta_compressor":eta_c,"T_turbine_inlet_K":float(row["turbine_firing_T_K"]),
        "eta_combustor":fixed["eta_combustor"],"combustor_pressure_loss":fixed["combustor_pressure_loss"],
        "LHV_J_kg":float(row["fuel_LHV_J_kg"]),"eta_turbine":eta_t,
        "exhaust_pressure_loss":outlet,"eta_mechanical":fixed["eta_mechanical"],
        "eta_generator":float(row["generator_efficiency"]),
        "auxiliary_load_fraction":fixed["auxiliary_load_fraction"],
        "degradation_mode":"clean"}

def run_fortran(exe:Path,cases:list[dict],working:Path)->list[dict]:
    if not cases or len(cases)>120000:
        raise ValueError("Invalid physics model batch")
    with tempfile.TemporaryDirectory(dir=working,prefix="gtfit-") as tmp:
        inp=Path(tmp)/"in.csv";out=Path(tmp)/"out.csv"
        with inp.open("w",newline="",encoding="utf-8") as handle:
            writer=csv.DictWriter(handle,fieldnames=CASE_FIELDS)
            writer.writeheader();writer.writerows(cases)
        result=subprocess.run([str(exe.resolve()),"run",str(inp),str(out)],
                              capture_output=True,text=True,timeout=180,check=False)
        if result.returncode!=0:
            raise ValueError("Real Fortran solver rejected physical calibration cases: "+result.stderr[-350:])
        with out.open(encoding="utf-8",newline="") as handle:
            predictions=list(csv.DictReader(handle))
    if len(predictions)!=len(cases):
        raise ValueError("Solver row count does not match original candidate deck")
    for inp,p in zip(cases,predictions):
        if p.get("case_name")!=inp["case_name"] or p.get("converged")!="1":
            raise ValueError("Missing case/solver not converged")
        for k in METRICS:
            if not math.isfinite(float(p[k])):
                raise ValueError("Solver output nonfinite "+k)
    return predictions

def temperature_loss(rows,predictions,uncertainties):
    if len(rows)!=len(predictions): raise ValueError("Incomplete calibration results")
    return sum(
        ((float(row[OBSERVED[key]])-float(p[key]))/float(uncertainties[key]))**2
        for row,p in zip(rows,predictions) for key in ("T2_K","T4_K")
    )/(2*len(rows))

def estimate(train:list[dict],meta:dict,exe:Path,working:Path,solver=run_fortran):
    """Run three grid refinements. NO untouched test/power/fuel in fit."""
    ec,et=.83,.86
    history=[]
    for stage,(wc,wt) in enumerate(((.15,.135),(.028,.028),(.0056,.0056))):
        cc=np.linspace(max(.65,ec-wc),min(.975,ec+wc),11)
        tt=np.linspace(max(.65,et-wt),min(.985,et+wt),11)
        candidates=[(float(a),float(b)) for a in cc for b in tt]
        deck=[case(row,meta,a,b,f"S{stage}C{j}P{i}")
              for j,(a,b) in enumerate(candidates) for i,row in enumerate(train)]
        predictions=solver(exe,deck,working)
        scored=[]
        n=len(train)
        for j,(a,b) in enumerate(candidates):
            loss=temperature_loss(train,predictions[j*n:(j+1)*n],
                                  meta["measured_standard_uncertainties"])
            scored.append((loss,a,b))
        loss,ec,et=min(scored)
        history.append({"stage":stage,"weighted_station_temperature_MSE":loss,
                        "eta_compressor":ec,"eta_turbine":et})
    return (ec,et,history)

def metrics(rows:list[dict],result:list[dict])->dict:
    if not rows or len(rows)!=len(result): raise ValueError("Missing measurement comparison")
    report={}
    for key in METRICS:
        obs=np.array([
          3600*float(row["fuel_mass_flow_kg_s"])*float(row["fuel_LHV_J_kg"])/
          (1e6*float(row["net_electric_power_MW"]))
          if key=="heat_rate_kJ_kWh" else float(row[OBSERVED[key]])
          for row in rows])
        pred=np.array([float(p[key]) for p in result])
        residual=obs-pred
        report[key]={"rmse":float(np.sqrt(np.mean(residual**2))),
                     "mae":float(np.mean(np.abs(residual))),
                     "bias_observed_minus_model":float(np.mean(residual)),
                     "records":len(rows)}
    return report

def calibrate(measurements:Path,meta_path:Path,exe:Path,out:Path,solver=run_fortran):
    out.mkdir(parents=True,exist_ok=True)
    report={"schema":"thermotwin.gt_physical_calibration.v1",
            "status":"BLOCKED_NO_ELIGIBLE_TRACEABLE_DATA",
            "industrial_field_accuracy_verified":False,
            "independent_model_form_uncertainty_verified":False,
            "contractual_or_OEM_acceptance":False}
    try:
        meta=json.loads(meta_path.read_text(encoding="utf-8"))
        validate_plan(meta,measurements)
        rows=load_measurements(measurements,meta)
        train=[r for r in rows if r["split"]=="development"]
        hold=[r for r in rows if r["split"]=="untouched_test"]
        ec,et,history=estimate(train,meta,exe,out,solver)
        predictions=solver(exe,[case(row,meta,ec,et,f"TEST{i}") for i,row in enumerate(hold)],out)
        observed_metrics=metrics(hold,predictions)
        thresholds=meta["predeclared_test_RMSE_limits"]
        decisions={name:observed_metrics[name]["rmse"]<=thresholds[name] for name in METRICS}
        file=out/"independent_holdout_predictions.csv"
        with file.open("w",newline="",encoding="utf-8") as handle:
            writer=csv.writer(handle)
            writer.writerow(("operating_point_id","timestamp_utc","metric","measured","predicted","residual"))
            for row,p in zip(hold,predictions):
                for key in METRICS:
                    value=(3600*float(row["fuel_mass_flow_kg_s"])*float(row["fuel_LHV_J_kg"])/
                        (1e6*float(row["net_electric_power_MW"]))
                        if key=="heat_rate_kJ_kWh" else float(row[OBSERVED[key]]))
                    writer.writerow((row["operating_point_id"],row["timestamp_utc"],key,
                                     value,float(p[key]),value-float(p[key])))
        report.update({"status":"CONDITIONAL_MEASURED_COMPARISON_REQUIRES_INDEPENDENT_REVIEW",
            "source_measurements_sha256":digest(measurements),
            "metadata_sha256":digest(meta_path),"fortran_solver_sha256":digest(exe),
            "unit_id":meta["unit_id"],"hardware_and_component_map_id":meta["hardware_and_component_map_id"],
            "validation_plan_id":meta["validation_plan_id"],"development_rows":len(train),
            "untouched_test_rows":len(hold),"fitted_eta_compressor":ec,
            "fitted_eta_turbine":et,"fit_history":history,
            "calibration_targets":["T2_K","T4_K"],"untouched_test":observed_metrics,
            "predeclared_RMSE_checks":decisions,"all_predeclared_RMSE_checks_pass":all(decisions.values()),
            "holdout_results_sha256":digest(file),
            "no_test_targets_or_measured_power_used_for_fitting":True,
            "interpretation":"Qualified machine-specific numerical comparison using operator-attested "
              "sensor/map/fuel metadata, not independently authenticated traceability, "
              "map calibration, field accuracy or OEM/pass-off certificate."})
    except (ValueError,KeyError,OSError,subprocess.SubprocessError) as exc:
        report["blocked_reason"]=str(exc)
        (out/"gt_physical_calibration_report.json").write_text(
            json.dumps(report,indent=2,sort_keys=True)+"\n",encoding="utf-8")
        raise
    (out/"gt_physical_calibration_report.json").write_text(
        json.dumps(report,indent=2,sort_keys=True,allow_nan=False)+"\n",encoding="utf-8")
    return report

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--audit-public",action="store_true")
    p.add_argument("--measurements",type=Path)
    p.add_argument("--metadata",type=Path)
    p.add_argument("--solver",type=Path)
    p.add_argument("--output",required=True,type=Path)
    args=p.parse_args(argv)
    if args.audit_public:
        if any((args.measurements,args.metadata,args.solver)):
            p.error("public audit and measured calibration are mutually exclusive")
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(audit_public(),indent=2,sort_keys=True)+"\n",
                               encoding="utf-8")
        print("Public turbine datasets: BLOCKED for full Brayton physical calibration.")
        return
    if not all((args.measurements,args.metadata,args.solver)):
        p.error("Need physical measured CSV, metadata/test plan, and Fortran solver")
    report=calibrate(args.measurements,args.metadata,args.solver,args.output)
    print("Conditional physical comparison (NOT verified plant accuracy):",
          report["untouched_test"])

if __name__=="__main__":
    main()
