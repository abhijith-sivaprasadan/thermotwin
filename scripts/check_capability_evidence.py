#!/usr/bin/env python3
"""Audit the declared capability evidence against code, tests and CI wiring.

Static provenance/claim-inventory gate only; cannot verify physical accuracy,
external measurement certificates or functional GUI behavior.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
MANIFEST=Path("docs/capability_evidence.json")
ALLOWED_STATUSES={"implemented","experimental","unsupported","published_source_only"}
ALLOWED_TIERS={"internal_numerical","source_inputs_only","empirical_statistics",
               "observational_consistency","mathematical_method","build_only",
               "archived_source","none"}
REQUIRED_IDS={"simple_brayton_cycle","off_design_and_degradation",
              "fixed_reference_site_correction","external_weather_boundary",
              "historical_era5_site_study","uci551_one_turbine_statistics",
              "smart_gtpp_observation_checks","independent_physical_validation_readiness",
              "passoff_instrument_uq_method","recruiter_engineering_dossier",
              "windows_gui_compile","humidity_physics","fuel_composition_chemistry",
              "industrial_oem_validation","historical_published_beta"}
BLOCKED={"humidity_physics","fuel_composition_chemistry","industrial_oem_validation"}


def safe_file(root,relative):
    if not isinstance(relative,str) or not relative or "\\" in relative:
        raise ValueError("Invalid evidence path: "+repr(relative))
    p=Path(relative)
    if p.is_absolute() or ".." in p.parts or p.as_posix()!=relative:
        raise ValueError("Unsafe evidence path: "+relative)
    full=(root/p).resolve()
    if full!=root and root not in full.parents:
        raise ValueError("Evidence path escapes repository: "+relative)
    if not full.exists():
        raise ValueError("Evidence source missing: "+relative)
    return full


def audit(root,manifest):
    root=Path(root).resolve()
    if manifest.get("schema")!="thermotwin.capability-evidence.v1":
        raise ValueError("Unrecognized evidence manifest schema")
    baseline=manifest.get("baseline",{})
    if not isinstance(baseline.get("commit"),str) or len(baseline["commit"])!=40:
        raise ValueError("Pinned baseline Git SHA required")
    ci_text=safe_file(root,".github/workflows/ci.yml").read_text(encoding="utf-8")
    items=manifest.get("capabilities")
    if not isinstance(items,list) or not items:
        raise ValueError("Missing capability entries")
    seen=set()
    files=set()
    supported=0
    for entry in items:
        ident=entry.get("id")
        if not isinstance(ident,str) or not ident or ident in seen:
            raise ValueError("Blank or duplicate capability identifier")
        seen.add(ident)
        status=entry.get("status")
        tier=entry.get("evidence_tier")
        if status not in ALLOWED_STATUSES or tier not in ALLOWED_TIERS:
            raise ValueError(ident+": unsupported status/tier")
        if entry.get("independent_field_validation") is not False:
            raise ValueError(ident+": unverified independent-field validation claim")
        if status=="unsupported" and tier!="none":
            raise ValueError(ident+": unsupported feature cannot have evidence tier")
        if status!="unsupported" and tier=="none":
            raise ValueError(ident+": implemented feature lacks evidence tier")
        paths=entry.get("paths")
        checks=entry.get("checks")
        jobs=entry.get("ci_evidence")
        artifacts=entry.get("source_artifacts")
        issues=entry.get("open_issues")
        if (not isinstance(paths,list) or not paths or
            not all(isinstance(x,str) for x in paths)):
            raise ValueError(ident+": evidence files required")
        if not all(isinstance(a,list) for a in (checks,jobs,artifacts,issues)):
            raise ValueError(ident+": invalid evidence arrays")
        if not issues or not all(isinstance(i,int) and i in {12,13,14,15,16,19} for i in issues):
            raise ValueError(ident+": unresolved issue IDs required")
        if not isinstance(entry.get("limitation"),str) or len(entry["limitation"])<25:
            raise ValueError(ident+": precise limitation required")
        for path in paths+checks:
            safe_file(root,path)
            files.add(path)
        for name in jobs+artifacts:
            if not isinstance(name,str) or not name.strip() or name not in ci_text:
                raise ValueError(ident+": CI evidence or artifact missing in workflow: "+str(name))
        if status not in {"unsupported","published_source_only"} and not checks and status!="experimental":
            raise ValueError(ident+": implemented capability missing a verification test")
        if status!="unsupported":
            supported+=1
    if not REQUIRED_IDS.issubset(seen):
        raise ValueError("Missing critical advertised capabilities: "+repr(sorted(REQUIRED_IDS-seen)))
    if any(next(x for x in items if x["id"]==i)["status"]!="unsupported" for i in BLOCKED):
        raise ValueError("Unverified physical capabilities cannot be described as implemented")
    return {"schema":"thermotwin.capability-audit-result.v1",
            "baseline_commit":baseline["commit"],
            "baseline_ci_url":baseline.get("ci_url"),
            "capabilities_audited":len(items),
            "non_unsupported_capabilities":supported,
            "distinct_evidence_paths_checked":len(files),
            "blocked_industrial_validation":True,
            "approved_industrial_deployment":False,
            "manual_GUI_acceptance_completed":False,
            "audit_scope":"Static claim/path/CI consistency; not field/OEM model validation"}


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root",type=Path,default=ROOT)
    p.add_argument("--manifest",type=Path,default=MANIFEST)
    p.add_argument("--output",type=Path)
    args=p.parse_args(argv)
    root=args.root.resolve()
    source=safe_file(root,str(args.manifest))
    raw=source.read_bytes()
    result=audit(root,json.loads(raw))
    try:
        commit=subprocess.check_output(["git","rev-parse","HEAD"],cwd=root,
                                       text=True,stderr=subprocess.DEVNULL).strip()
    except (OSError,subprocess.CalledProcessError):
        commit=None
    result["candidate_source_commit"]=commit
    result["github_actions_run_id"]=os.getenv("GITHUB_RUN_ID") or None
    result["manifest_sha256"]=hashlib.sha256(raw).hexdigest()
    result["research_release_published_by_this_gate"]=False
    if args.output:
        out=args.output if args.output.is_absolute() else root/args.output
        out.parent.mkdir(parents=True,exist_ok=True)
        out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(json.dumps(result,indent=2,sort_keys=True))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
