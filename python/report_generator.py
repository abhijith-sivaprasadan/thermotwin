"""Assemble all ThermoTwin-F results into a single multi-page PDF report.

This turns a directory of CSVs and PNGs into a self-contained engineering
report - the kind of artefact you can attach to a job application or hand to a
reviewer. It regenerates every figure, then lays them out with a cover page,
a results-summary table, and an explicit assumptions/limitations page.

Usage:
    python python/report_generator.py
Output:
    output/ThermoTwin-F_report.pdf
"""
from __future__ import annotations

import datetime as _dt
import os
import sys

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

import utils

# Import the individual plot scripts so we can call them to (re)generate PNGs.
import plot_design_point
import plot_sensitivity
import plot_degradation
import plot_transient
import plot_uncertainty
import plot_diagnostics


FIGURES = [
    ("design_point.png", "Design-point summary"),
    ("sensitivity.png", "Parametric sensitivity"),
    ("degradation.png", "Degradation impact"),
    ("transient.png", "Transient thermal response"),
    ("uncertainty.png", "Measurement uncertainty"),
    ("diagnostics.png", "Inverse diagnostics"),
]


def _regenerate_all():
    """Best-effort regeneration of all figures; skip any with missing inputs."""
    for fn in (plot_design_point, plot_sensitivity, plot_degradation,
               plot_transient, plot_uncertainty, plot_diagnostics):
        try:
            fn.main([fn.__name__])
        except FileNotFoundError as e:
            print(f"  (skipping {fn.__name__}: {e})")


def _cover_page(pdf):
    fig = plt.figure(figsize=(8.27, 11.69))   # A4 portrait
    fig.patch.set_facecolor("white")
    ax = fig.add_axes([0, 0, 1, 1]); ax.axis("off")

    ax.add_patch(plt.Rectangle((0, 0.74), 1, 0.26, color=utils.PALETTE["primary"]))
    ax.text(0.07, 0.88, "ThermoTwin-F", fontsize=34, fontweight="bold", color="white")
    ax.text(0.07, 0.835, "Gas-Turbine Performance Simulator  -  Engineering Report",
            fontsize=13, color="white")

    today = _dt.date.today().isoformat()
    lines = [
        ("Model", "Open/simple Brayton cycle, single-shaft"),
        ("Working fluid", "Air-standard with separate hot-gas properties"),
        ("Analyses", "Design - off-design - degradation - transient - uncertainty - diagnostics"),
        ("Implementation", "Modern Fortran (2008), modular, unit-tested"),
        ("Post-processing", "Python / matplotlib"),
        ("Generated", today),
    ]
    y = 0.66
    for k, v in lines:
        ax.text(0.07, y, k, fontsize=11, fontweight="bold", color=utils.PALETTE["ink"])
        ax.text(0.32, y, v, fontsize=11, color=utils.PALETTE["ink"])
        y -= 0.038

    disclaimer = (
        "Scope and honesty note\n"
        "This is a non-proprietary educational simulator. It uses standard textbook "
        "thermodynamics and representative property values. It is NOT calibrated or "
        "validated against any specific commercial engine, and it is NOT compliant with "
        "ASME PTC 22 or ISO 2314. The verification self-test checks the code against an "
        "independent hand calculation; it does not constitute validation against hardware."
    )
    ax.add_patch(plt.Rectangle((0.07, 0.13), 0.86, 0.20, fill=True,
                               color=utils.PALETTE["grid"], alpha=0.5))
    ax.text(0.09, 0.305, disclaimer, fontsize=9.5, color=utils.PALETTE["ink"],
            va="top", wrap=True)

    ax.text(0.07, 0.06, "ThermoTwin-F", fontsize=9, color=utils.PALETTE["muted"])
    pdf.savefig(fig); plt.close(fig)


def _summary_table_page(pdf):
    fig = plt.figure(figsize=(8.27, 11.69))
    ax = fig.add_axes([0.08, 0.1, 0.84, 0.82]); ax.axis("off")
    ax.set_title("Design-point results summary", fontsize=15, fontweight="bold",
                 loc="left", color=utils.PALETTE["ink"], pad=18)

    path = os.path.join(utils.OUTPUT_DIR, "results_design_point.csv")
    try:
        d = utils.read_csv(path)
    except Exception:
        ax.text(0, 0.9, "results_design_point.csv not found - run the design case first.",
                color=utils.PALETTE["bad"]); pdf.savefig(fig); plt.close(fig); return

    i = 0
    rows = [
        ("Compressor outlet T2", f"{d['T2_K'][i]:.1f}", "K"),
        ("Turbine inlet T3 (TIT)", f"{d['T3_K'][i]:.1f}", "K"),
        ("Exhaust T4", f"{d['T4_K'][i]:.1f}", "K"),
        ("Pressure ratio", f"{d['P2_Pa'][i]/d['P1_Pa'][i]:.1f}", "-"),
        ("Fuel-air ratio", f"{d['fuel_air_ratio'][i]:.4f}", "-"),
        ("Air mass flow", f"{d['mdot_air_kg_s'][i]:.1f}", "kg/s"),
        ("Compressor power", f"{d['power_compressor_MW'][i]:.2f}", "MW"),
        ("Turbine power", f"{d['power_turbine_MW'][i]:.2f}", "MW"),
        ("Net electrical power", f"{d['net_power_MW'][i]:.2f}", "MW"),
        ("Heat input (fuel)", f"{d['heat_input_MW'][i]:.2f}", "MW"),
        ("Thermal efficiency", f"{100*d['thermal_efficiency'][i]:.2f}", "%"),
        ("Heat rate", f"{d['heat_rate_kJ_kWh'][i]:.0f}", "kJ/kWh"),
        ("Specific power", f"{d['specific_power_kW_per_kgps'][i]:.1f}", "kW/(kg/s)"),
        ("Exhaust energy", f"{d['exhaust_energy_MW'][i]:.2f}", "MW"),
    ]

    table = ax.table(
        cellText=[[r[0], r[1], r[2]] for r in rows],
        colLabels=["Quantity", "Value", "Unit"],
        colWidths=[0.6, 0.22, 0.18], cellLoc="left", loc="upper left")
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1, 1.5)
    for (row, col), cell in table.get_celld().items():
        cell.set_edgecolor(utils.PALETTE["grid"])
        if row == 0:
            cell.set_facecolor(utils.PALETTE["primary"])
            cell.set_text_props(color="white", fontweight="bold")
        elif row % 2 == 0:
            cell.set_facecolor("#F4F6F8")

    ax.text(0, -0.02,
            "Values from the constant-property model; see docs/verification.md for the "
            "independent hand calculation these reproduce.",
            transform=ax.transAxes, fontsize=8.5, color=utils.PALETTE["muted"])
    pdf.savefig(fig); plt.close(fig)


def _image_page(pdf, image_path, caption):
    if not os.path.exists(image_path):
        return
    img = plt.imread(image_path)
    h, w = img.shape[0], img.shape[1]
    fig = plt.figure(figsize=(8.27, 11.69))
    ax_img = fig.add_axes([0.06, 0.12, 0.88, 0.78]); ax_img.axis("off")
    ax_img.imshow(img)
    fig.text(0.06, 0.93, caption, fontsize=14, fontweight="bold", color=utils.PALETTE["ink"])
    fig.text(0.06, 0.06, "ThermoTwin-F engineering report", fontsize=8,
             color=utils.PALETTE["muted"])
    pdf.savefig(fig); plt.close(fig)


def _limitations_page(pdf):
    fig = plt.figure(figsize=(8.27, 11.69))
    ax = fig.add_axes([0.08, 0.08, 0.84, 0.86]); ax.axis("off")
    ax.text(0, 1.0, "Assumptions & limitations", fontsize=15, fontweight="bold",
            color=utils.PALETTE["ink"], va="top")
    items = [
        "Single-shaft open/simple Brayton cycle; no regeneration, intercooling or reheat.",
        "Constant specific heats by default (separate cold-air and hot-gas values). A "
        "temperature-dependent property option exists but is not the default.",
        "No compressor or turbine performance maps: off-design is represented by efficiency "
        "and boundary-condition changes, not by map-based matching.",
        "No turbine cooling-air bookkeeping; TIT is treated as the gas temperature entering "
        "the turbine.",
        "No detailed combustion chemistry or emissions (NOx/CO) model; combustion is a "
        "lumped energy balance with an efficiency.",
        "Transient model is a single lumped-capacitance metal node, not a spatially resolved "
        "thermal/FE model.",
        "Uncertainty and diagnostics are demonstrative: the objective function and weights "
        "are explicit choices, not a certified PTC-19.1 uncertainty budget.",
        "Not calibrated or validated against any specific commercial engine; not ASME PTC 22 "
        "or ISO 2314 compliant.",
    ]
    y = 0.93
    for it in items:
        ax.text(0.0, y, "-", fontsize=11, color=utils.PALETTE["secondary"], va="top")
        ax.text(0.03, y, it, fontsize=10.3, color=utils.PALETTE["ink"], va="top", wrap=True)
        y -= 0.085
    ax.text(0, 0.04,
            "These limitations are intentional for a transparent teaching/portfolio tool. "
            "Each is a natural avenue for extension (maps, real-gas properties, cooling "
            "flows, emissions, FE thermal models).",
            fontsize=9.5, color=utils.PALETTE["muted"], va="top")
    pdf.savefig(fig); plt.close(fig)


def main():
    utils.apply_style()
    print("Regenerating figures...")
    _regenerate_all()

    out_pdf = os.path.join(utils.OUTPUT_DIR, "ThermoTwin-F_report.pdf")
    os.makedirs(utils.OUTPUT_DIR, exist_ok=True)
    print("Assembling PDF report...")
    with PdfPages(out_pdf) as pdf:
        _cover_page(pdf)
        _summary_table_page(pdf)
        for fn, caption in FIGURES:
            _image_page(pdf, os.path.join(utils.FIGURE_DIR, fn), caption)
        _limitations_page(pdf)

        meta = pdf.infodict()
        meta["Title"] = "ThermoTwin-F Engineering Report"
        meta["Subject"] = "Gas-turbine performance simulation"
        meta["Creator"] = "ThermoTwin-F / matplotlib"

    print(f"  wrote {os.path.relpath(out_pdf, utils.ROOT)}")


if __name__ == "__main__":
    main()
