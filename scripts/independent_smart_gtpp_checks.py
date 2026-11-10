#!/usr/bin/env python3
"""Independent measured-data checks; NEVER certified turbine-model validation.

Measured source: SMART-GTPP DOI:10.17632/6sk3mhm7hb.1 (CC BY 4.0).
Raw file does not label AP/CPD units or provide authenticated UTC timestamps.
Atmospheric and pressure mappings here are EXPLORATORY hypotheses.
"""
import argparse
import csv
from hashlib import sha256
import json
import math
from pathlib import Path
import statistics
import xml.etree.ElementTree as ET

from scripts.fetch_smart_gtpp import FIELDS, ORIGINAL_RECORDS, ORIGINAL_SHA256, DOI
from scripts.open_meteo_boundary import ENGINE_FIELDS, read_reference_case

INHG_TO_PA = 3386.38866667  # assumed, NOT source-verified pressure unit
BAR_TO_PA = 100000.0       # assumed, source CPD gauge status also unknown


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def load(path):
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader=csv.DictReader(f)
        if reader.fieldnames is None or len(reader.fieldnames)!=len(set(reader.fieldnames)):
            raise ValueError("Missing/duplicate original CSV headers")
        cols=list(reader.fieldnames)
        rows=list(reader)
    if not rows or any(None in r or None in r.values() for r in rows):
        raise ValueError("Malformed or truncated CSV")
    return cols, rows


def number(row, key, positive=False):
    try:
        x=float(row[key])
    except (KeyError,ValueError,TypeError) as exc:
        raise ValueError("Missing or nonnumeric "+key) from exc
    if not math.isfinite(x) or (positive and x<=0):
        raise ValueError("Nonfinite or nonpositive "+key)
    return x


def close(a,b,label):
    if not math.isclose(a,b,rel_tol=5e-7,abs_tol=2e-5):
        raise ValueError("Source-to-model physical identity check: "+label)


def source_rows(path):
    if digest(path)!=ORIGINAL_SHA256:
        raise ValueError("Original fixed-version measured source SHA256 changed")
    cols, data=load(path)
    if cols!=list(FIELDS) or len(data)!=ORIGINAL_RECORDS:
        raise ValueError("Source measured feature schema or count changed")
    for row in data:
        for col in FIELDS:
            number(row,col)
    return data


def save(path, cols, items):
    with path.open("w",newline="",encoding="utf-8") as f:
        writer=csv.DictWriter(f,fieldnames=cols,lineterminator="\n")
        writer.writeheader()
        writer.writerows(items)


def prepare(original, reference, out):
    observations=source_rows(original)
    ref,ref_hash=read_reference_case(reference)
    if (ref["degradation_mode"]!="clean" or
        abs(number(ref,"ambient_T_K")-288.15)>1e-8 or
        abs(number(ref,"ambient_P_Pa")-101325)>1e-6 or
        number(ref,"inlet_pressure_loss")!=0 or
        number(ref,"exhaust_pressure_loss")!=0):
        raise ValueError("Reference is not declared fixed ISO-flange reference")
    inputs=[]
    for i,observation in enumerate(observations):
        # These source-unit hypotheses have NOT been confirmed by instruments.
        T=number(observation,"AT")+273.15
        P=number(observation,"AP")*INHG_TO_PA
        if not 250<=T<=325 or not 75000<=P<=110000:
            raise ValueError("Assumed measured units outside model input domain")
        row=dict(ref)
        row["case_name"]=f"smart{i:05d}"
        row["ambient_T_K"]=format(T,".10g")
        row["ambient_P_Pa"]=format(P,".10g")
        # Keep all other generic hardware and assumed RH invariant; no
        # invented fuel mass flow, compressor maps or pressure losses.
        inputs.append(row)
    out.mkdir(parents=True,exist_ok=True)
    csvpath=out/"model_input_cases.csv"
    save(csvpath,ENGINE_FIELDS,inputs)
    manifest={
      "schema":"thermotwin.smart_gtpp.external_observed_gate.v1",
      "source_doi":DOI,"license":"CC BY 4.0",
      "original_source_sha256":digest(original),
      "original_records":len(observations),
      "generic_reference_sha256":ref_hash,
      "generic_model_input_sha256":digest(csvpath),
      "input_rows":len(inputs),
      "pressure_unit_hypotheses_UNVERIFIED":{
        "AP":"inHg assumed; source CSV has no units",
        "CPD":"bar assumed; gauge/absolute not source-confirmed",
        "AT":"degrees C assumed; source CSV has no units"},
      "observed_ep_active_electric_power_MW_source_description":True,
      "source_utc_timestamps_verified":False,
      "source_air_mass_flow_available":False,
      "source_fuel_mass_flow_available":False,
      "source_fuel_LHV_available":False,
      "source_OEM_maps_available":False,
      "model_humidity_is_fixed_generic_scalar":True,
      "physical_model_validated_against_engine":False,
      "industrial_guarantee_assessed":False,
    }
    (out/"source_and_assumptions.json").write_text(json.dumps(manifest,indent=2,sort_keys=True)+"\n")
    print(f"Prepared {len(inputs)} measured-boundary analogues, no OEM calibration")
    return manifest


def pearson(xs,ys):
    if len(xs)!=len(ys) or len(xs)<3:raise ValueError("Too few paired source data")
    mx,my=statistics.mean(xs),statistics.mean(ys)
    xx=sum((z-mx)**2 for z in xs)
    yy=sum((z-my)**2 for z in ys)
    if xx<=0 or yy<=0:raise ValueError("Zero variance observed source")
    return sum((a-mx)*(b-my) for a,b in zip(xs,ys))/math.sqrt(xx*yy)


def pressure_unit_hypotheses(data):
    gauge, absolute = [], []
    for row in data:
        ambient=number(row,"AP",True)*INHG_TO_PA
        discharge=number(row,"CPD",True)*BAR_TO_PA
        observed=number(row,"CPR",True)
        absolute.append(discharge/ambient-observed)
        gauge.append((ambient+discharge)/ambient-observed)
    return {
      "AP_inHg_CPD_bar_source_units_are_UNVERIFIED":True,
      "exploratory_not_preregistered":True,
      "gauge_CPR_rmse":math.sqrt(statistics.mean(v*v for v in gauge)),
      "absolute_CPR_rmse":math.sqrt(statistics.mean(v*v for v in absolute)),
      "gauge_CPR_mae":statistics.mean(abs(v) for v in gauge),
      "absolute_CPR_mae":statistics.mean(abs(v) for v in absolute),
      "pressure_instruments_not_calibrated_or_validated":True,
    }


def draw(points, path):
    """Observed EP and generic model independently normalized: SHAPE ONLY."""
    ns="http://www.w3.org/2000/svg"
    ET.register_namespace("",ns)
    root=ET.Element(f"{{{ns}}}svg",{"width":"1100","height":"600","viewBox":"0 0 1100 600"})
    def element(tag,**attrs):
        return ET.SubElement(root,f"{{{ns}}}{tag}",{k:str(v) for k,v in attrs.items()})
    def title(x,y,value,size=18):
        element("text",x=x,y=y,fill="#23364e",font_size=size,
                font_family="Arial,Helvetica,sans-serif").text=value
    ET.SubElement(root,f"{{{ns}}}title").text="Measured turbine power and unrelated generic model: exploratory shapes only"
    element("rect",x=0,y=0,width=1100,height=600,fill="#f7f9fc")
    title(40,58,"Observed turbine power vs generic model shape",30)
    title(40,91,"SMART-GTPP original measurements (7893) | fixed generic teaching machine",18)
    title(40,122,"Each power curve divided by its OWN median; this is NOT predicted MW accuracy.",18)
    left,right,top,bottom=120,1030,158,470
    low,high=0.6,1.45
    def xmap(z):return left+(z+5)*(right-left)/55
    def ymap(z):return bottom-(z-low)*(bottom-top)/(high-low)
    for i in range(6):
        v=.6+.17*i
        element("line",x1=left,y1=ymap(v),x2=right,y2=ymap(v),stroke="#d5dfe6")
        title(55,ymap(v)+5,f"{v:.2f}",15)
    for key,color in (("observed_EP_ratio","#c07836"),("generic_model_power_ratio","#17808a")):
        pairs=" ".join(f"{xmap(p['bin_center_C']):.1f},{ymap(p[key]):.1f}" for p in points)
        element("polyline",points=pairs,fill="none",stroke=color,stroke_width=4)
    title(120,510,"Source ambient T, °C assumed | median within 5°C bins | no temporal holdout",17)
    title(120,545,"Orange: measured turbine power / measured sample median",17)
    title(120,570,"Teal: unrelated generic model / its own sample median; no OEM, fuel or load matching",16)
    ET.ElementTree(root).write(path,encoding="utf-8",xml_declaration=True)


def assess(original,reference,out):
    obs=source_rows(original)
    prior=json.loads((out/"source_and_assumptions.json").read_text())
    if (prior["original_source_sha256"]!=digest(original) or
        prior["generic_reference_sha256"]!=digest(reference) or
        prior["generic_model_input_sha256"]!=digest(out/"model_input_cases.csv") or
        prior["physical_model_validated_against_engine"] is not False):
        raise ValueError("Reference/source identity or no-validation disclosure altered")
    _, cases=load(out/"model_input_cases.csv")
    _, modeled=load(out/"model_site_results.csv")
    if len(cases)!=ORIGINAL_RECORDS or len(modeled)!=ORIGINAL_RECORDS:
        raise ValueError("Site output is not paired to every original observed row")
    AT, EP, model_ratios=[],[],[]
    p_ref=None
    for i,(o,c,m) in enumerate(zip(obs,cases,modeled)):
        name=f"smart{i:05d}"
        if (c["case_name"]!=name or m["case_name"]!=name or m["valid"]!="1" or
            abs(number(c,"relative_humidity")-.6)>1e-10 or
            abs(number(c,"inlet_pressure_loss"))>1e-10 or
            abs(number(c,"exhaust_pressure_loss"))>1e-10):
            raise ValueError("Measured/model case alignment or assumed boundary violated")
        T=number(o,"AT")+273.15
        P=number(o,"AP")*INHG_TO_PA
        for label,value,expected in [
            ("input T",number(c,"ambient_T_K"),T),("input P",number(c,"ambient_P_Pa"),P),
            ("model T",number(m,"site_ambient_T_K"),T),("model P",number(m,"site_ambient_P_Pa"),P)]:
            close(value,expected,label)
        refpower=number(m,"reference_net_power_MW",True)
        sitepower=number(m,"site_net_power_MW",True)
        if p_ref is None:p_ref=refpower
        close(p_ref,refpower,"fixed reference machine")
        ratio=number(m,"power_derate_ratio",True)
        close(ratio,sitepower/refpower,"Fortran power-ratio identity")
        close(number(m,"power_correction_ref_per_site",True),refpower/sitepower,"power correction")
        close(number(m,"heat_rate_correction_ref_per_site",True),
              number(m,"reference_heat_rate_kJ_kWh",True)/
              number(m,"site_heat_rate_kJ_kWh",True),"heat-rate correction")
        AT.append(number(o,"AT"));EP.append(number(o,"EP",True));model_ratios.append(ratio)
    pressure=pressure_unit_hypotheses(obs)
    ar=pearson(AT,EP)
    mr=pearson(AT,model_ratios)
    cross=pearson(EP,model_ratios)
    ep_med=statistics.median(EP)
    model_med=statistics.median(model_ratios)
    grouped={}
    for t,e,r in zip(AT,EP,model_ratios):
        center=5*(math.floor(t/5)+.5)
        a=grouped.setdefault(center,([],[]))
        a[0].append(e);a[1].append(r)
    bins=[{"bin_center_C":c,"observed_count":len(v[0]),
           "observed_EP_ratio":statistics.median(v[0])/ep_med,
           "generic_model_power_ratio":statistics.median(v[1])/model_med}
          for c,v in sorted(grouped.items()) if len(v[0])>=20]
    if len(bins)<5:raise ValueError("Not enough original measured temperature-bin coverage")
    draw(bins,out/"measured_EP_vs_generic_model_shape.svg")
    report={
      "schema":"thermotwin.smart_gtpp.external_measured_partial_physics_check.v1",
      "source_doi":DOI,"original_sha256":digest(original),
      "original_measured_rows":len(obs),"measured_plant_count":1,
      "generic_model_case_count":len(modeled),
      "observational_EP_AT_Pearson_noncausal":ar,
      "generic_model_power_AT_Pearson_noncausal":mr,
      "observed_EP_vs_unrelated_generic_model_Pearson_not_validation":cross,
      "pressure_sensor_identity_exploratory_unit_hypotheses":pressure,
      "temperature_bins_separately_normalized_only_for_visual_shape":bins,
      "generic_model_reference_power_MW_not_measured_or_same_hardware":p_ref,
      "model_results_sha256":digest(out/"model_site_results.csv"),
      "per_record_verified_UTC_available":False,
      "measured_fuel_massflow_and_LHV_available":False,
      "measured_compressor_air_massflow_available":False,
      "pressure_units_in_original_CSV_verified":False,
      "validated_OEM_engine_hardware_or_maps_available":False,
      "genuine_independent_power_prediction_accuracy_assessed":False,
      "physical_model_validation_success_claimed":False,
      "contractual_passoff_assessed":False,
      "limitations":[
        "Source AP inches Hg and CPD bar gauge interpretations exploratory and unverified",
        "Observed EP is actual active electric MW; model net power is an unrelated generic turbine",
        "Different source load, fuel, controls, efficiencies, maps and sensor calibration unknown",
        "Missing measured fuel flow/LHV/airflow and authenticated UTC; no independent test set",
        "Observed-model correlation cannot estimate causal sensitivity or predictive accuracy",
        "No fitting, no absolute-power RMSE and no OEM validation or contractual guarantee"],
    }
    (out/"measured_partial_check.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    text=[
        "# Independent real gas-turbine observations: partial physical checks",
        "",
        "Ameen and Hamarash (2026), SMART-GTPP v1, DOI: "+DOI,
        f"Original active-power observations: **{len(obs)}** from one gas-turbine installation.",
        "All source bytes pinned by original SHA256 "+digest(original),
        "",
        "## Explicit exploratory source-unit hypotheses (NOT verified)",
        "Assume source AP is inHg and source CPD is bar. Compare stated compressor",
        "ratio CPR with discharge/ambient under bar absolute and bar gauge alternatives.",
        f"Gauge hypothesis ratio RMSE: **{pressure['gauge_CPR_rmse']:.4f}**.",
        f"Absolute hypothesis ratio RMSE: **{pressure['absolute_CPR_rmse']:.4f}**.",
        "This is NOT pressure-instrument calibration, guaranteed unit provenance,",
        "or validation of ThermoTwin's compressor or turbine map.",
        "",
        "## Descriptive measured and generic-model environmental associations",
        f"Original ambient AT versus measured electrical EP Pearson r: **{ar:.4f}**.",
        f"Original AT versus generic-model output ratio Pearson r: **{mr:.4f}**.",
        f"Measured EP versus unrelated generic-model power-ratio Pearson r: **{cross:.4f}**.",
        "These associations are confounded by unknown loading, maintenance, controls,",
        "fuel states and hardware. No measured air mass flow or fuel flow/LHV exists.",
        "",
        "![Source measured EP vs separately normalized generic model shape](measured_EP_vs_generic_model_shape.svg)",
        "",
        "Both power series have independent full-sample median scaling for a",
        "descriptive *shape only* visualization. They do not predict the same",
        "engine's power, and no out-of-sample physical accuracy claim is possible.",
        "",
        "## Validation verdict: NOT ESTABLISHED",
        "The original CSV contains no authenticated UTC stamps, unit-labelled",
        "AP or CPD fields, unit-specific component maps, source-matched hardware",
        "geometry, measured LHV, fuel or air mass flow, or calibration certificates.",
        "Therefore no independent physical model power accuracy, heat-rate",
        "validation, predictive uncertainty, pass-off result or OEM claim is possible.",
        "This CI job demonstrates genuine external measured-evidence acquisition,",
        "a conditional pressure-ratio consistency hypothesis and software",
        "integrity/physics-equation checks against matched *generic* model cases.",
    ]
    (out/"EXTERNAL_MEASURED_EVIDENCE.md").write_text("\n".join(text)+"\n")
    print(f"Measured EP/AT r={ar:.4f}; generic model r={mr:.4f}; "
          f"CPR gauge/absolute RMSE={pressure['gauge_CPR_rmse']:.4f}/"
          f"{pressure['absolute_CPR_rmse']:.4f}. Physics calibration NOT ESTABLISHED.")
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest="command",required=True)
    for name in ("prepare","assess"):
        s=sub.add_parser(name)
        s.add_argument("--original",type=Path,required=True)
        s.add_argument("--reference",type=Path,required=True)
        s.add_argument("--out",type=Path,required=True)
    a=p.parse_args()
    if a.command=="prepare":prepare(a.original,a.reference,a.out)
    else:assess(a.original,a.reference,a.out)


if __name__=="__main__":main()
