#!/usr/bin/env python3
"""Fail-closed Windows GUI acceptance collector: PDF + full machine-readable ZIP.

Use --source on the Windows runner AFTER the real native GUI has been executed.
Never interpret simulator traces as industrial measurements or physical validation.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import platform
import re
import shutil
import sys
import zipfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

PRIMARY = [
    "01-original-overview", "02-original-turbine", "03-original-alarms",
    "04-original-alarms-stress", "05-controls-bottom", "06-equipment",
    "07-trip-sequence", "08-trip-events", "09-alarm-surge-map",
    "10-alarm-oil-no-data", "11-alarm-frequency", "12-instructor-running",
    "13-instructor-frozen", "14-instructor-oil-trip", "15-instructor-restored",
]
NATIVE_IDS = (
    [f"navigation_{n:02d}" for n in range(1, 17)]
    + [f"slider_{n:02d}" for n in range(1, 7)]
    + ["toggle_auto_balance", "toggle_roi", "toggle_fcr", "cycle_theme",
       "toggle_colour_safe", "toggle_nav_rail", "toggle_alarm_audio_flag",
       "cycle_alarm_gain", "scenario_next", "scenario_prev"]
    + [f"scenario_load_{n:02d}" for n in range(1, 16)]
    + ["native_export_invoked", "native_png_export_invoked"]
)
ADDITIONAL_GATES = [
    ("process_clean_exit", "process"),
    ("native_matrix_complete", "evidence"),
    ("debug_log_integrity", "logs"),
    ("telemetry_integrity", "measurements"),
    ("native_measurements_integrity", "measurements"),
    ("hmi_shift_csv_export", "export"),
    ("hmi_native_png_export", "export"),
    ("hmi_operations_pdf_generator", "export"),
    ("original_screenshot_set", "visual"),
    ("full_screen_render_set", "visual"),
]
UNTESTED = [
    ("all_15_scenarios_complete_horizons", "scenario", "Only source load and first tick exercised"),
    ("full_GUI_15_scenario_replay_control", "scenario", "Entire start/step/pause/end timelines not exercised"),
    ("mouse_hit_targets_all_controls", "mouse", "Six sliders tested via real key handler; not every mouse coordinate"),
    ("all_DPI_scaling_100_125_150", "visual", "Native 1024 and virtual 1536 images; DPI matrix not exercised"),
    ("real_OPC_UA_client_tag_and_rate", "integration", "Offline executable; no genuine OPC UA server/client acceptance"),
    ("audible_speaker_output", "hardware", "No physical device and listener verification"),
    ("HMI_PDF_button_process", "export", "Existing GUI PDF button not invoked by acceptance mode"),
    ("clean_room_binary_distribution", "distribution", "Windows runner build is not independent end-user installation"),
    ("industrial_predictive_validation", "physics", "No matched, independently metered industrial turbine test set"),
    ("plant_trip_and_restart_safety", "safety", "Research simulator trip logic; not protective-system qualification"),
]
FIELD_UNITS = {
    "elapsed_s": "s", "demand_MW": "MW", "renewable_MW": "MW",
    "storage_request_MW": "MW", "gas_dispatch_pct": "%",
    "ambient_C": "deg C", "TIT_K": "K", "frequency_Hz": "Hz",
    "gas_power_MW": "MW", "supply_MW": "MW", "imbalance_MW": "MW",
    "battery_soc_pct": "%",
}
SCOPE_NOTICE = (
    "AUTOMATED SIMULATOR GUI SOFTWARE ACCEPTANCE ONLY. Native telemetry is "
    "modelled/simulated, NOT physical plant measurements. Screen-image existence "
    "does not prove layout readability or click accuracy. This report is not "
    "a Siemens Energy, OEM, ASME, ISO or industrial safety acceptance certificate."
)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for part in iter(lambda: stream.read(1 << 20), b""):
            h.update(part)
    return h.hexdigest()


def read_csv(path: Path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def find_images(path: Path, prefix: str, extension: str):
    return sorted(path.glob(f"{prefix}*.{extension}"))


def add_test(results, ident, category, status, details, evidence=""):
    assert status in ("PASS", "FAIL", "NOT_TESTED")
    results.append(dict(id=ident, category=category, status=status,
                        details=str(details).replace("\n", " | "), evidence=evidence))


def check_png(path: Path, min_width=1024, min_height=720) -> tuple[bool, str]:
    try:
        from PIL import Image
        with Image.open(path) as image:
            width, height = image.size
            image.verify()
        return (width >= min_width and height >= min_height,
                f"{width}x{height} px; SHA256 {sha256(path)[:16]}")
    except (OSError, ValueError) as exc:
        return False, f"Cannot decode PNG: {exc}"


def make_pdf(output: Path, results, context, field_stats, evidence, debug_lines):
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer,
                                    Table, TableStyle, KeepTogether, PageBreak)

    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(name="SmallBodyQA", parent=styles["BodyText"],
                              fontName="Helvetica", fontSize=8.1, leading=11.5,
                              spaceAfter=4))
    styles.add(ParagraphStyle(name="TinyQA", parent=styles["BodyText"],
                              fontName="Helvetica", fontSize=7, leading=9))
    styles.add(ParagraphStyle(name="HeadingQA", parent=styles["Heading2"],
                              fontName="Helvetica-Bold", fontSize=12,
                              spaceBefore=13, spaceAfter=6))
    title_style = ParagraphStyle(name="TitleQA", parent=styles["Title"],
                                 fontName="Helvetica-Bold", fontSize=19,
                                 alignment=TA_CENTER)
    def esc(value):
        import html
        return html.escape(str(value)).replace("\n", "<br/>")

    def p(value, style="TinyQA"):
        return Paragraph(esc(value), styles[style])

    def table(headers, rows, widths):
        data = [[p(s) for s in headers]]
        data += [[p(v) for v in row] for row in rows]
        t = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e8edf3")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#1b2635")),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LINEBELOW", (0, 0), (-1, 0), 0.6, colors.HexColor("#8994a4")),
            ("LINEBELOW", (0, 1), (-1, -1), 0.22, colors.HexColor("#dce1e6")),
            ("LEFTPADDING", (0, 0), (-1, -1), 5),
            ("RIGHTPADDING", (0, 0), (-1, -1), 5),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        return t

    counts = Counter(x["status"] for x in results)
    story = [Paragraph("ThermoTwin-F", title_style),
             Paragraph("Native Windows GUI acceptance and evidence record",
                       styles["Heading2"]), Spacer(1, 6),
             p(SCOPE_NOTICE, "SmallBodyQA"), Spacer(1, 5)]
    overall = "FAIL" if counts["FAIL"] else "INCOMPLETE" if counts["NOT_TESTED"] else "PASS"
    story.append(table(["Decision", "Passed", "Failed", "Not tested", "Total"],
                       [(overall, counts["PASS"], counts["FAIL"],
                         counts["NOT_TESTED"], len(results))],
                       [38*mm, 28*mm, 28*mm, 32*mm, 27*mm]))
    story += [Spacer(1, 8), p(
        "PASS means the specified automated assertion was observed, not that an "
        "industrial guarantee or human-factors acceptance is satisfied.",
        "SmallBodyQA")]
    story.append(Paragraph("Run identity", styles["HeadingQA"]))
    story.append(table(["Field", "Recorded value"],
                       [(key, value) for key, value in context.items()],
                       [46*mm, 107*mm]))
    story.append(Paragraph("Results by category", styles["HeadingQA"]))
    categories = sorted(set(x["category"] for x in results))
    story.append(table(["Category", "PASS", "FAIL", "NOT_TESTED"],
                       [(cat, *[sum(x["category"] == cat and x["status"] == st
                                    for x in results)
                                for st in ("PASS", "FAIL", "NOT_TESTED")])
                        for cat in categories],
                       [66*mm, 28*mm, 28*mm, 31*mm]))
    failures = [r for r in results if r["status"] == "FAIL"]
    story.append(Paragraph("Failures and limitations", styles["HeadingQA"]))
    if failures:
        story.append(table(["Test", "Observed failure"],
                           [(x["id"], x["details"]) for x in failures],
                           [54*mm, 99*mm]))
    else:
        story.append(p("No automatically asserted failure recorded. "
                       "NOT_TESTED items remain unverified.", "SmallBodyQA"))
    not_tested = [x for x in results if x["status"] == "NOT_TESTED"]
    story.append(Paragraph("Explicitly untested / incomplete gates", styles["HeadingQA"]))
    story.append(table(["Gate", "Why not certified"],
                       [(x["id"], x["details"]) for x in not_tested],
                       [57*mm, 96*mm]))
    story.append(Paragraph("Recorded simulator measurement ranges", styles["HeadingQA"]))
    if field_stats:
        story.append(table(["Signal", "Unit", "Min", "Max", "Mean", "Samples"],
                           [(k, FIELD_UNITS.get(k, "-"), f"{v['min']:.5g}",
                             f"{v['max']:.5g}", f"{v['mean']:.5g}", v["n"])
                            for k, v in field_stats.items()],
                           [49*mm, 18*mm, 24*mm, 24*mm, 23*mm, 15*mm]))
    else:
        story.append(p("No valid native telemetry was available.", "SmallBodyQA"))
    story.append(p("The complete time-series trace, per-test values and original "
                   "native export are included in the ZIP as CSV files.",
                   "SmallBodyQA"))
    story.append(Paragraph("Full automated assertion ledger", styles["HeadingQA"]))
    story.append(table(["ID", "Category", "Status", "Evidence / detail"],
                       [(x["id"], x["category"], x["status"], x["details"])
                        for x in results],
                       [43*mm, 23*mm, 23*mm, 64*mm]))
    story.append(Paragraph("Evidence inventory", styles["HeadingQA"]))
    story.append(table(["File / folder", "Contents"],
                       [("native_qa_results.csv", "Original in-process assertion outcomes"),
                        ("native_qa_measurements.csv", "In-process state at every test checkpoint"),
                        ("gui_telemetry.csv", "125-ms model timer samples with units in header"),
                        ("gui_debug.log", "Complete native startup, action and shutdown trace"),
                        ("gui-acceptance-*.log", "Complete compiler and Windows harness output"),
                        ("shift_data_t*.csv", "Original native full multi-section shift export"),
                        ("shift_data_t*.pdf", "Original HMI operations PDF generator output"),
                        ("screenshots/*.png", "Native GUI captured and exported image files"),
                        ("GUI_VISUAL_DEFECTS.json", "Reviewed known visual defects blocking acceptance"),
                        ("test_results.csv / json", "Normalized status ledger and metadata"),
                        ("evidence_sha256.csv", "Cryptographic digest and byte size of every evidence file"),
                        ("report.pdf", "This summarized technical report")],
                       [58*mm, 95*mm]))
    story.append(Paragraph("Native debug log excerpt", styles["HeadingQA"]))
    excerpt = (debug_lines[:8] + (["[...middle lines in ZIP...]"] if len(debug_lines)>20 else [])
               + debug_lines[-12:])
    for line in excerpt:
        story.append(p(line[:170], "TinyQA"))
    story += [Spacer(1, 6), p("Generated from the source files listed above. "
                               "Absence of a measurement is not replaced by a synthetic value.",
                               "SmallBodyQA")]
    doc = SimpleDocTemplate(str(output), pagesize=(210*mm, 297*mm),
                            leftMargin=22*mm, rightMargin=22*mm,
                            topMargin=19*mm, bottomMargin=18*mm,
                            title="ThermoTwin-F native GUI acceptance report",
                            author="Automated ThermoTwin-F evidence collector")
    def footer(canvas, document):
        canvas.saveState()
        canvas.setFont("Helvetica", 7)
        canvas.drawString(22*mm, 11*mm, "ThermoTwin-F | simulator software QA | not industrial qualification")
        canvas.drawRightString(190*mm, 11*mm, f"Page {document.page}")
        canvas.restoreState()
    doc.build(story, onFirstPage=footer, onLaterPages=footer)


def collect(source: Path, target: Path, args):
    target.mkdir(parents=True, exist_ok=True)
    results = []
    original = source / "native_qa_results.csv"
    matrix = {}
    if original.is_file():
        try:
            for row in read_csv(original):
                ident = row.get("id", "")
                if ident in matrix:
                    raise ValueError(f"duplicate assertion ID: {ident}")
                if row.get("status") not in ("PASS", "FAIL"):
                    raise ValueError(f"invalid native assertion status for {ident}")
                matrix[ident] = row
        except (OSError, ValueError, csv.Error) as exc:
            add_test(results, "native_matrix_schema", "evidence", "FAIL", str(exc))
            matrix = {}
    for ident in NATIVE_IDS:
        row = matrix.get(ident)
        add_test(results, ident, row["category"] if row else "native",
                 row["status"] if row else "FAIL",
                 f"observed={row['observed']}; expected={row['expected']}"
                 if row else "Expected native assertion missing",
                 "native_qa_results.csv")

    proc_ok = args.qa_exit_code == 0
    add_test(results, "process_clean_exit", "process",
             "PASS" if proc_ok else "FAIL",
             f"GUI PowerShell harness exit code {args.qa_exit_code}")
    add_test(results, "native_matrix_complete", "evidence",
             "PASS" if set(NATIVE_IDS) == set(matrix) else "FAIL",
             f"Native IDs {len(matrix)}; expected {len(NATIVE_IDS)}; "
             f"unexpected {sorted(set(matrix)-set(NATIVE_IDS))[:10]}")

    logpath = Path(args.debug_log)
    loglines = logpath.read_text(encoding="utf-8", errors="replace").splitlines() \
        if logpath.is_file() else []
    debug_ok = (bool(loglines) and
                any("QA ACCEPTANCE: native matrix finished" in s for s in loglines) and
                any("WM_DESTROY" in s for s in loglines) and
                not any("QA FAIL:" in s for s in loglines))
    add_test(results, "debug_log_integrity", "logs",
             "PASS" if debug_ok else "FAIL",
             f"{len(loglines)} native log lines; QA FAIL occurrences="
             f"{sum('QA FAIL:' in s for s in loglines)}; completed marker={debug_ok}")

    telemetry_rows = []
    field_stats = {}
    try:
        telemetry_rows = read_csv(source / "gui_telemetry.csv")
        if len(telemetry_rows) < 110:
            raise ValueError(f"Only {len(telemetry_rows)} timer samples")
        tick = [int(row["tick"]) for row in telemetry_rows]
        if tick != list(range(1, len(tick)+1)):
            raise ValueError("Timer tick sequence noncontiguous")
        for key in FIELD_UNITS:
            values = [float(row[key]) for row in telemetry_rows]
            if not all(math.isfinite(x) for x in values):
                raise ValueError(f"{key} contains NaN or infinity")
            field_stats[key] = dict(n=len(values), min=min(values),
                                    max=max(values), mean=sum(values)/len(values))
        if field_stats["frequency_Hz"]["min"] <= 0:
            raise ValueError("Nonphysical simulated frequency")
        add_test(results, "telemetry_integrity", "measurements", "PASS",
                 f"{len(telemetry_rows)} contiguous native timer samples")
    except (OSError, ValueError, KeyError, csv.Error) as exc:
        add_test(results, "telemetry_integrity", "measurements", "FAIL", str(exc))
        field_stats = {}

    try:
        measurement_rows = read_csv(source / "native_qa_measurements.csv")
        if len(measurement_rows) < 37:
            raise ValueError(f"Only {len(measurement_rows)} checkpoint records")
        for row in measurement_rows:
            for key in FIELD_UNITS:
                if key in row and not math.isfinite(float(row[key])):
                    raise ValueError(f"nonfinite {key} at {row.get('test_id')}")
        add_test(results, "native_measurements_integrity", "measurements", "PASS",
                 f"{len(measurement_rows)} native model state checkpoints")
    except (OSError, ValueError, KeyError, csv.Error) as exc:
        add_test(results, "native_measurements_integrity", "measurements", "FAIL", str(exc))

    shift_files = sorted(Path(args.repo).glob("shift_data_t*.csv"))
    valid_exports = [p for p in shift_files if
                     p.stat().st_size > 1000 and
                     all(x in p.read_text(encoding="utf-8", errors="replace")
                         for x in ("[REPORT_META]", "[ACTIVE_SCREEN]",
                                   "[HISTORY]", "[SCIENTIFIC_ANALYSIS]"))]
    add_test(results, "hmi_shift_csv_export", "export",
             "PASS" if valid_exports else "FAIL",
             f"{len(valid_exports)} original structured shift export(s) verified")

    native_png_files = sorted((Path(args.repo) / "output").glob("screen_f*.png"))
    good_native_png = [p for p in native_png_files if check_png(p)[0]]
    add_test(results, "hmi_native_png_export", "export",
             "PASS" if good_native_png else "FAIL",
             f"{len(good_native_png)} actual HMI screen PNG export(s) decoded")
    pdf_exports = sorted(Path(args.repo).glob("shift_data_t*.pdf"))
    good_pdf_exports = []
    try:
        from pypdf import PdfReader
        for p in pdf_exports:
            if p.stat().st_size > 3000 and len(PdfReader(str(p)).pages) >= 5:
                good_pdf_exports.append(p)
    except (ImportError, OSError, ValueError) as exc:
        add_test(results, "pdf_generator_parser_error", "export", "FAIL", str(exc))
    add_test(results, "hmi_operations_pdf_generator", "export",
             "PASS" if good_pdf_exports else "FAIL",
             f"{len(good_pdf_exports)} original HMI operations PDF(s) with >=5 pages")

    original_ok = True
    for label in PRIMARY:
        for ending in (".png", "-1536.png"):
            path = source / (label + ending)
            valid, desc = check_png(path) if path.is_file() else (False, "missing")
            original_ok = original_ok and valid
            add_test(results, f"capture_{label}{ending}", "visual",
                     "PASS" if valid else "FAIL", desc,
                     f"screenshots/{path.name}")
    add_test(results, "original_screenshot_set", "visual",
             "PASS" if original_ok else "FAIL", "30 original native captures")

    all_screens_ok = True
    for n in range(1, 17):
        path = source / f"screen-{n:02d}-1536.png"
        valid, desc = check_png(path) if path.is_file() else (False, "missing")
        all_screens_ok = all_screens_ok and valid
        add_test(results, f"capture_screen_{n:02d}", "visual",
                 "PASS" if valid else "FAIL", desc, f"screenshots/{path.name}")
    add_test(results, "full_screen_render_set", "visual",
             "PASS" if all_screens_ok else "FAIL", "16 original 1536 px screen draws")

    defect_file = Path(args.repo) / "docs" / "GUI_VISUAL_DEFECTS.json"
    try:
        defects = json.loads(defect_file.read_text(encoding="utf-8"))
        if defects.get("schema") != "thermotwin.gui-visual-defects.v1":
            raise ValueError("Visual defect register schema mismatch")
        for defect in defects["known_defects"]:
            evidence_path = source / str(defect["evidence"])
            issue_status = defect.get("status")
            if issue_status == "OPEN":
                state = "FAIL"
            elif issue_status == "RESOLVED":
                state = "NOT_TESTED"  # closing a register does not prove current render
            else:
                raise ValueError("Invalid known defect status")
            add_test(results, defect["id"], "visual_review",
                     state, f"{issue_status} {defect['viewport']}: "
                     f"{defect['observation']} | screenshot_file_exists={evidence_path.is_file()}",
                     f"screenshots/{defect['evidence']}")
    except (OSError, ValueError, KeyError, TypeError) as exc:
        add_test(results, "visual_defect_register_integrity", "visual_review",
                 "FAIL", f"Visual defect register not verified: {exc}")

    for ident, cat, why in UNTESTED:
        add_test(results, ident, cat, "NOT_TESTED", why)

    context = {
        "Generated (UTC)": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        "Git commit": args.sha,
        "GitHub run": args.run_url or "local",
        "Windows runner": platform.platform(),
        "Build outcome": args.build_exit_code,
        "GUI harness exit": args.qa_exit_code,
        "GUI executable": "thermotwin-gui-offline.exe",
        "Evidence type": "simulator model states / native UI interactions",
    }
    with (target / "test_results.csv").open("w", newline="", encoding="utf-8") as fd:
        writer = csv.DictWriter(fd, fieldnames=["id", "category", "status", "details", "evidence"])
        writer.writeheader()
        writer.writerows(results)
    metadata = dict(schema="thermotwin.gui-acceptance.v1", context=context,
                    notice=SCOPE_NOTICE, summary=dict(Counter(r["status"] for r in results)),
                    tests=results, native_csv_rows=len(matrix),
                    telemetry_rows=len(telemetry_rows),
                    real_plant_measurements=False, industrial_acceptance=False)
    (target / "test_results.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")

    evidence = target / "evidence"
    evidence.mkdir(exist_ok=True)
    screenshots = evidence / "screenshots"
    screenshots.mkdir(exist_ok=True)
    for p in sorted(source.glob("*.csv")):
        shutil.copy2(p, evidence / p.name)
    if defect_file.is_file():
        shutil.copy2(defect_file, evidence / "GUI_VISUAL_DEFECTS.json")
    for p in sorted(source.glob("*.png")):
        shutil.copy2(p, screenshots / p.name)
    for p in shift_files + pdf_exports:
        shutil.copy2(p, evidence / p.name)
    for p in native_png_files:
        shutil.copy2(p, screenshots / ("hmi-export-" + p.name))
    if logpath.exists():
        shutil.copy2(logpath, evidence / "gui_debug.log")
    for name in ("gui-acceptance-build.log", "gui-acceptance-runner.log", "gui-acceptance-operations-pdf.log"):
        p = Path(args.repo) / "build" / name
        if p.is_file():
            shutil.copy2(p, evidence / name)
    for p in sorted(source.glob("*.jpg")):
        shutil.copy2(p, screenshots / p.name)
    (target / "README.txt").write_text(
        SCOPE_NOTICE + "\n\n"
        "report.pdf: human-readable decision, QA assertions, measurements and limits.\n"
        "test_results.csv/json: complete declared PASS/FAIL/NOT_TESTED ledger.\n"
        "evidence/: original native CSV, compiler/GUI logs, raw trace and screenshots.\n"
        "evidence_sha256.csv: checksum of each archived input/output.\n"
        "Known unresolved visually reviewed defects are recorded as FAIL until fixed.\n"
        "A missing item is a failure or NOT_TESTED, never a silent PASS.\n",
        encoding="utf-8")

    pdf = target / "report.pdf"
    make_pdf(pdf, results, context, field_stats, evidence, loglines)
    checkrows = []
    for p in sorted(target.rglob("*")):
        if p.is_file() and p.name not in ("evidence_sha256.csv",) and p.suffix != ".zip":
            checkrows.append((p.relative_to(target).as_posix(), p.stat().st_size, sha256(p)))
    with (target / "evidence_sha256.csv").open("w", newline="", encoding="utf-8") as fd:
        writer = csv.writer(fd)
        writer.writerow(["relative_path", "bytes", "sha256"])
        writer.writerows(checkrows)

    archive = target / "thermotwin-gui-acceptance.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=6) as z:
        for p in sorted(target.rglob("*")):
            if p.is_file() and p != archive:
                z.write(p, p.relative_to(target).as_posix())

    # Fail the verifier only AFTER the PDF/ZIP have been generated.
    count = Counter(r["status"] for r in results)
    print(json.dumps(dict(report=str(pdf), archive=str(archive),
                          summary=dict(count), native=len(matrix),
                          screenshots=len(list(screenshots.glob("*.png")))), indent=2))
    return 1 if count["FAIL"] else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="build/gui-visual-qa")
    parser.add_argument("--out", default="build/gui-acceptance")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--debug-log", default="gui_debug.log")
    parser.add_argument("--sha", default=os.getenv("GITHUB_SHA", "local/unknown"))
    parser.add_argument("--run-url", default="")
    parser.add_argument("--qa-exit-code", type=int, default=1)
    parser.add_argument("--build-exit-code", type=int, default=0)
    args = parser.parse_args()
    try:
        return collect(Path(args.source), Path(args.out), args)
    except Exception as exc:
        # Make an honest minimal failure artifact even if report creation fails.
        out = Path(args.out)
        out.mkdir(parents=True, exist_ok=True)
        (out / "collector_failure.txt").write_text(
            f"GUI acceptance collector failed: {type(exc).__name__}: {exc}\n",
            encoding="utf-8")
        raise


if __name__ == "__main__":
    sys.exit(main())
