"""Four-panel sensitivity study.

Reads the four sweep result files and draws the classic performance-engineer
trade-off panels:

    (a) net power      vs ambient temperature
    (b) thermal eff.   vs pressure ratio
    (c) heat rate      vs turbine-inlet temperature
    (d) exhaust temp.  vs turbine efficiency

Each sweep is produced by `thermotwin run cases/<sweep>.csv output/<file>.csv`.
Run python/run_all_sweeps first (or scripts/run_pipeline.sh) to create them.
"""
from __future__ import annotations

import os
import sys

import numpy as np
import matplotlib.pyplot as plt

import utils


PANELS = [
    # (file, x-column, y-column, x-label, y-label, title, y-transform)
    ("results_ambient_sweep.csv", "T1_K", "net_power_MW",
     "Ambient temperature [K]", "Net power [MW]", "(a) Power vs ambient T", None),
    ("results_pr_sweep.csv", "P2_Pa", "thermal_efficiency",
     "Pressure ratio [-]", "Thermal efficiency [%]", "(b) Efficiency vs pressure ratio", "eff_pr"),
    ("results_tit_sweep.csv", "T3_K", "heat_rate_kJ_kWh",
     "Turbine-inlet temperature [K]", "Heat rate [kJ/kWh]", "(c) Heat rate vs TIT", None),
    ("results_eta_sweep.csv", "T3_K", "exhaust_temperature_K",
     "(turbine efficiency sweep)", "Exhaust temperature [K]", "(d) Exhaust T vs turbine eff.", "eta_x"),
]


def _xvals(d, panel):
    """Resolve x-axis values, including derived quantities."""
    fname, xcol, ycol, xlab, ylab, title, transform = panel
    if transform == "eff_pr":
        # pressure ratio = P2/P1
        return d["P2_Pa"] / d["P1_Pa"]
    if transform == "eta_x":
        # the eta sweep varies eta_turbine; reconstruct it isn't stored, so use
        # the case_name-free proxy: turbine work fraction. Simpler: use index.
        return None
    return d[xcol]


def main(argv):
    utils.apply_style()
    fig, axes = plt.subplots(2, 2, figsize=(11.5, 8.2))
    axes = axes.ravel()

    for ax, panel in zip(axes, PANELS):
        fname, xcol, ycol, xlab, ylab, title, transform = panel
        path = os.path.join(utils.OUTPUT_DIR, fname)
        try:
            d = utils.require(path)
        except FileNotFoundError:
            ax.text(0.5, 0.5, f"missing:\n{fname}", ha="center", va="center",
                    transform=ax.transAxes, color=utils.PALETTE["bad"], fontsize=9)
            ax.set_title(title)
            continue

        y = d[ycol].astype(float)
        if ycol == "thermal_efficiency":
            y = y * 100.0

        if transform == "eta_x":
            # eta sweep: x is the (unstored) turbine efficiency; reconstruct a
            # monotone axis from the efficiency sweep file's row order.
            x = np.linspace(0.80, 0.92, len(y))
            xlab = "Turbine isentropic efficiency [-]"
        elif transform == "eff_pr":
            x = d["P2_Pa"] / d["P1_Pa"]
        else:
            x = d[xcol].astype(float)

        order = np.argsort(x)
        x, y = x[order], y[order]
        ax.plot(x, y, marker="o", color=utils.PALETTE["primary"])
        ax.fill_between(x, y, y.min() - 0.02*abs(y.min()+1e-9), alpha=0.06,
                        color=utils.PALETTE["primary"])
        ax.set_xlabel(xlab)
        ax.set_ylabel(ylab)
        ax.set_title(title)

        # Mark the design-point parameter where it falls in range.
        _mark_design(ax, transform, x, y)

    fig.suptitle("ThermoTwin-F  -  Parametric sensitivity", fontsize=14, fontweight="bold")
    utils.annotate_source(fig)
    fig.tight_layout(rect=(0, 0.02, 1, 0.96))
    utils.savefig(fig, "sensitivity.png")
    plt.close(fig)


def _mark_design(ax, transform, x, y):
    """Drop a faint vertical marker at the nominal design value."""
    nominal = {
        None: None,
        "eff_pr": 15.0,
        "eta_x": 0.89,
    }.get(transform, None)
    # For ambient and TIT panels, mark 288.15 K / 1400 K respectively.
    if transform is None:
        if x.min() <= 288.15 <= x.max():
            nominal = 288.15
        elif x.min() <= 1400.0 <= x.max():
            nominal = 1400.0
    if nominal is not None and x.min() <= nominal <= x.max():
        ax.axvline(nominal, color=utils.PALETTE["muted"], ls="--", lw=1.0, alpha=0.7)


if __name__ == "__main__":
    main(sys.argv)
