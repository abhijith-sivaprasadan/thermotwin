#!/usr/bin/env python3
"""Audit real 2017 operating measurements from Esan & Ehiaguina's 5.68 MW GT.

Original openly licensed XLSX, doi:10.17632/6w3vy3ybhg.3, source-locked.
Source workbook has 317 day/night worksheets, transposed instrument channels,
and 12 nominal hourly columns per worksheet. Preserve published sheet order;
do NOT invent UTC timestamps or claim stable device station definitions.

Validate only ELECTRICAL MEASUREMENT CONSISTENCY:
  P_est[kW] = sqrt(3) * voltage[V] * mean(IA,IB,IC)[A] * PF / 1000
This assumes measured "Voltage (Vac)" is line-to-line and the current average
is appropriate. Its validity is NOT independently certified. Power, current and
PF may come from one metering system, so this is internal consistency, not
independent proof of electrical meter accuracy or the Brayton cycle.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
from hashlib import sha256
import io
import json
import math
from pathlib import Path
import re
from urllib.request import Request, urlopen
from xml.etree import ElementTree as ET
import zipfile

DATASET_URL = "https://data.mendeley.com/datasets/6w3vy3ybhg/3"
SOURCE_URL = ("https://data.mendeley.com/public-files/datasets/6w3vy3ybhg/files/"
              "37f98837-3e29-4af0-a776-776093c43a59/file_downloaded")
DOI = "10.17632/6w3vy3ybhg.3"
ORIGINAL_SHA256 = "09b8ba80991998a370b6f8124450792a5150103383c0eff41f8f00b54d3e3bf9"
ORIGINAL_WORKSHEETS = 317
MAX_BYTES = 8_000_000
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
SOURCE_ROWS = {
    8: "Compressor inlet air temp. (T1) (oC)",
    9: "Compressor T5 average (oC)",
    11: "Compressor outlet air pressure (PCD) (barg)",
    28: "Turbine Exhaust temperature T7 (Average) (oC)",
    31: "Gas fuel flow (kg/h)",
    33: "Liquid fuel flow (kg/min)",
    35: "Voltage (Vac)",
    36: "Current A (A)",
    37: "Current B (A)",
    38: "Current C (A)",
    39: "Real power (kW)",
    40: "Apparent power (kVA)",
    41: "Reactive power (kVAR)",
    42: "Power factor (None)",
    43: "Frequency (Hz)",
}
NEEDED_FOR_POWER = (35,36,37,38,39,42)
RAW_SIGNAL_NAMES = tuple(SOURCE_ROWS.values())
CSV_FIELDS = (
    "source_sheet_number", "published_sheet_label", "source_hour_column",
    "source_hour_fraction_if_numeric", "measured_real_power_kW",
    "predicted_electrical_identity_power_kW", "measured_minus_reconstructed_kW",
    "voltage_reported_Vac", "mean_phase_current_A", "measured_pf",
    "measured_apparent_power_kVA", "gas_fuel_flow_kg_h",
    "compressor_inlet_T1_reported_C", "compressor_outlet_PCD_reported_barg",
    "turbine_T7_reported_C", "analysis_partition",
)


def sha(data: bytes) -> str:
    return sha256(data).hexdigest()


def get_original(original_zip: Path | None) -> bytes:
    if original_zip is not None:
        content = original_zip.read_bytes()
    else:
        request = Request(SOURCE_URL, headers={"User-Agent": "ThermoTwin-F academic research provenance audit"})
        with urlopen(request, timeout=90) as reply:
            if reply.status != 200:
                raise ValueError("Original Mendeley XLSX HTTP status not 200")
            content = reply.read(MAX_BYTES + 1)
    if len(content) > MAX_BYTES:
        raise ValueError("Published original XLSX exceeded expected size")
    if sha(content) != ORIGINAL_SHA256:
        raise ValueError("Published 2019 measured source SHA-256 mismatch: STOP, review new archive")
    return content


def parse_cells(root: ET.Element, shared: list[str], rows: set[int]) -> dict[tuple[int,str],str]:
    cells = {}
    for row in root.findall(f".//{NS}sheetData/{NS}row"):
        n = int(row.attrib["r"])
        if n not in rows:
            continue
        for cell in row.findall(f"{NS}c"):
            address = cell.get("r", "")
            match = re.fullmatch(r"([A-Z]+)([0-9]+)", address)
            if not match or int(match.group(2)) != n:
                raise ValueError("Unexpected source XML cell address")
            if cell.find(f"{NS}f") is not None:
                # Formula-derived values are not raw instrument observations.
                raise ValueError("Original XLSX contains formulas in required sensor channels")
            value = cell.find(f"{NS}v")
            if value is None:
                continue
            text = value.text or ""
            if cell.attrib.get("t") == "s":
                text = shared[int(text)]
            if (n,match.group(1)) in cells:
                raise ValueError("Duplicate original XML sensor cell")
            cells[(n,match.group(1))] = text
    return cells


def number(raw: str | None):
    if raw is None:
        return None
    try:
        n = float(raw)
    except (ValueError,TypeError):
        return None
    return n if math.isfinite(n) else None


def read_original(raw: bytes):
    """Return original-sheet-ordered measurement records and rejection reasons.

    The printed source worksheet order is used only as an ordered sequence.
    The sheet clock values/date labels are *not* asserted to represent
    synchronized UTC stamps, so no hourly operational forecast is inferred.
    """
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        if len(z.namelist()) > 2500 or z.testzip() is not None:
            raise ValueError("Damaged/oversized original XLSX archive")
        shared_path = "xl/sharedStrings.xml"
        if shared_path not in z.namelist():
            raise ValueError("Original source has no expected shared string dictionary")
        shared_doc = ET.fromstring(z.read(shared_path))
        shared = ["".join(x.text or "" for x in row.iter(f"{NS}t"))
                  for row in shared_doc.findall(f"{NS}si")]
        wb = ET.fromstring(z.read("xl/workbook.xml"))
        sheets = wb.findall(f".//{NS}sheets/{NS}sheet")
        if len(sheets) != ORIGINAL_WORKSHEETS:
            raise ValueError("Original workbook sheet count changed")
        # In this source snapshot, workbook order maps to sheet1...sheet317;
        # verify the exact source XML structure, not just sorted ZIP filenames.
        items = []
        discarded = Counter()
        totals = Counter()
        per_sheet_labels = []
        for index,sheet in enumerate(sheets, start=1):
            path = f"xl/worksheets/sheet{index}.xml"
            if path not in z.namelist() or z.getinfo(path).file_size > 3_000_000:
                raise ValueError("Unexpected original measured sheet content")
            root = ET.fromstring(z.read(path))
            rows_to_read = set(SOURCE_ROWS) | {3}
            cells = parse_cells(root,shared,rows_to_read)
            for r,expected in SOURCE_ROWS.items():
                if cells.get((r,"A")) != expected:
                    raise ValueError(f"Published source sensor column definition changed in sheet {index} row {r}")
            title = sheet.get("name","")
            per_sheet_labels.append(title)
            for col in "BCDEFGHIJKLM":
                totals["nominal_hour_slots"]+=1
                recorded = {key: number(cells.get((key,col))) for key in SOURCE_ROWS}
                if any(recorded[i] is None for i in NEEDED_FOR_POWER):
                    discarded["missing_or_non_numeric_required_electrical_channels"]+=1
                    continue
                voltage,ia,ib,ic,p,pf = [recorded[i] for i in NEEDED_FOR_POWER]
                if not (0.0 < p <= 5680.0):
                    discarded["measured_power_nonpositive_or_above_nameplate_kW"]+=1
                    continue
                if not (9000 <= voltage <= 12000):
                    discarded["voltage_outside_declared_11kV_domain"]+=1
                    continue
                if any(not(0.0 < i < 450) for i in (ia,ib,ic)):
                    discarded["phase_current_missing_or_exceeds_predeclared_limit"]+=1
                    continue
                if not (0.60 <= pf <= 1.0):
                    discarded["power_factor_outside_predeclared_domain"]+=1
                    continue
                mean_current=(ia+ib+ic)/3.0
                reconstructed=math.sqrt(3)*voltage*mean_current*pf/1000.
                observation = {
                    "source_sheet_number":index,
                    "published_sheet_label":title,
                    "source_hour_column":col,
                    "source_hour_fraction_if_numeric":number(cells.get((3,col))),
                    "measured_real_power_kW":p,
                    "predicted_electrical_identity_power_kW":reconstructed,
                    "measured_minus_reconstructed_kW":p-reconstructed,
                    "voltage_reported_Vac":voltage,
                    "mean_phase_current_A":mean_current,
                    "measured_pf":pf,
                    "measured_apparent_power_kVA":recorded[40],
                    "gas_fuel_flow_kg_h":recorded[31],
                    "compressor_inlet_T1_reported_C":recorded[8],
                    "compressor_outlet_PCD_reported_barg":recorded[11],
                    "turbine_T7_reported_C":recorded[28],
                }
                if not all(math.isfinite(value) for value in (p,reconstructed,mean_current)):
                    raise ValueError("Nonfinite derived electrical reconstruction")
                items.append(observation)
        if len(items)<2500 or len(items)>3300:
            raise ValueError("Filtered original measured source count unexpectedly changed")
        if totals["nominal_hour_slots"] != 12*ORIGINAL_WORKSHEETS:
            raise ValueError("Original hourly-column source geometry changed")
        if sum(discarded.values())+len(items)!=totals["nominal_hour_slots"]:
            raise ValueError("Source filter did not classify each original hourly slot")
        return items,dict(discarded),dict(totals),per_sheet_labels


def metric(rows: list[dict]) -> dict:
    if not rows:
        raise ValueError("No actual observed electrical measurements to assess")
    actual=[x["measured_real_power_kW"] for x in rows]
    err=[x["measured_minus_reconstructed_kW"] for x in rows]
    n=len(rows)
    return {"n":n,
            "rmse_kW":math.sqrt(sum(e*e for e in err)/n),
            "mae_kW":sum(abs(e) for e in err)/n,
            "bias_observed_minus_identity_kW":sum(err)/n,
            "maximum_absolute_residual_kW":max(abs(e) for e in err),
            "mean_measured_power_kW":sum(actual)/n,
            "sample_order_source_sheets_only":True}


def run(argv=None) -> dict:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--original-xlsx",type=Path,help="Local copy of original pinned XLSX, no network")
    ap.add_argument("--out",type=Path,required=True)
    args=ap.parse_args(argv)
    raw=get_original(args.original_xlsx)
    rows,discarded,totals,sheet_names=read_original(raw)
    # Source-sheet order, not invented absolute chronology or sample timestamps.
    pivot=int(len(rows)*0.70)
    for i,row in enumerate(rows):
        row["analysis_partition"]="earlier_source_sheets" if i<pivot else "later_source_sheets_untouched"
    first,last=rows[:pivot],rows[pivot:]
    out=args.out
    out.mkdir(parents=True,exist_ok=True)
    (out/"original_2019_raw_shift_workbook.xlsx").write_bytes(raw)
    ledger=out/"real_turbine_electrical_identity.csv"
    with ledger.open("w",newline="",encoding="utf-8") as f:
        writer=csv.DictWriter(f,fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    report={
        "schema":"thermotwin.2017_5p68MW_real_gt_electrical_consistency.v1",
        "source":DATASET_URL, "doi":DOI,"license":"CC BY 4.0",
        "machine_nameplate_capacity_MW":5.68,
        "original_xlsx_sha256":ORIGINAL_SHA256,
        "source_workbook_shifts":ORIGINAL_WORKSHEETS,
        "source_signal_labels":list(RAW_SIGNAL_NAMES),
        "nominal_source_slots":totals["nominal_hour_slots"],
        "accepted_electrical_measurement_points":len(rows),
        "predeclared_source_filters":{
            "real_power_kW":">0 and <=5680",
            "voltage_V":"9000 to 12000",
            "phase_current_A":">0 and <450 for each phase",
            "power_factor":"0.60 to 1.00",
            "nonfinite_or_text":"reject required electrical channel",
            "not_postfiltered_on_identity_residual":True,
        },
        "excluded_by_first_applicable_reason":discarded,
        "observed_generator_power_consistency":{
            "assumption":"V is line-to-line and mean phase current represents balanced load; PF 0..1",
            "model":"sqrt(3)*Vac*mean(IA,IB,IC)*PF/1000, kW",
            "uses_observed_power_for_fit":False,
            "single_control_system_measurements_not_independently_calibrated":True,
            "source_sheet_order_not_exact_UTC":True,
            "full_sample":metric(rows),
            "earlier_source_sheets":metric(first),
            "later_source_sheets_untouched":metric(last),
            "split_is_evaluation_only_no_training":True,
            "later_source_first_sheet_index":last[0]["source_sheet_number"],
        },
        "known_physics_gaps":[
            "No measured inlet air mass flow or reliable fuel lower heating value",
            "Fuel mass rate in kg/h and compressor pressure PCD in barg exist but cannot alone determine heat rate or turbine work",
            "T5 and T7 station naming not proven equivalent to four-station Brayton T3/T4; TIT absent",
            "Ambient pressure and OEM map/geometry not reported by original 50-channel workbook",
            "No independently verified generator/instrument covariance or actual net-to-gross power boundary",
            "Original sheet names contain dates/shifts but are not authenticated synchronized UTC timestamps",
            "Some source values exceed plausible instrument/nameplate domains; exclusions are disclosed",
        ],
        "gas_turbine_solver_physical_accuracy_verified":False,
        "generator_meter_independent_accuracy_verified":False,
        "fault_or_life_prediction_verified":False,
        "purpose":"Original field-data provenance and first-principles generator electrical consistency only",
        "raw_source_redistribution_license":"CC BY 4.0, source attribution required",
        "predictions_csv_sha256":sha(ledger.read_bytes()),
    }
    (out/"readiness_and_electrical_consistency.json").write_text(json.dumps(
        report,indent=2,sort_keys=True,allow_nan=False)+"\n",encoding="utf-8")
    print("REAL ORIGINAL 5.68-MW GT field readings, pinned XLSX SHA",ORIGINAL_SHA256)
    print("Shifts",ORIGINAL_WORKSHEETS,"valid electrical rows",len(rows),
          "excluded",sum(discarded.values()))
    print("Electrical identity holdout RMSE kW",
          round(report["observed_generator_power_consistency"]["later_source_sheets_untouched"]["rmse_kW"],3))
    print("No independently verified Brayton thermodynamic accuracy claimed.")
    return report


if __name__=="__main__":
    run()
