"""Plot the design-point solution: station temperatures and the energy split.

Usage:
    python python/plot_design_point.py [results_design_point.csv]
"""
from __future__ import annotations

import os
import sys

import numpy as np
import matplotlib.pyplot as plt

import utils


def main(argv):
    utils.apply_style()
    path = argv[1] if len(argv) > 1 else os.path.join(utils.OUTPUT_DIR, "results_design_point.csv")
    d = utils.require(path)

    # Single design point -> take row 0.
    i = 0
    T = [d["T1_K"][i], d["T2_K"][i], d["T3_K"][i], d["T4_K"][i]]
    stations = ["1\ninlet", "2\ncomp out", "3\nturb in", "4\nexhaust"]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.6))

    # --- Left: station temperatures -------------------------------------
    bars = ax1.bar(stations, T, color=utils.SERIES_COLORS[:4], width=0.62, edgecolor="white")
    ax1.set_ylabel("Stagnation temperature [K]")
    ax1.set_title("Station temperatures")
    for b, t in zip(bars, T):
        ax1.text(b.get_x() + b.get_width()/2, t + 12, f"{t:.0f} K",
                 ha="center", va="bottom", fontsize=9, color=utils.PALETTE["ink"])
    ax1.set_ylim(0, max(T) * 1.18)

    # --- Right: where the fuel energy goes ------------------------------
    fuel = d["heat_input_MW"][i]
    net = d["net_power_MW"][i]
    exhaust = d["exhaust_energy_MW"][i]
    other = max(fuel - net - exhaust, 0.0)   # losses + combustor inefficiency

    labels = ["Net electrical", "Exhaust sensible", "Losses + other"]
    vals = [net, exhaust, other]
    colors = [utils.PALETTE["good"], utils.PALETTE["secondary"], utils.PALETTE["muted"]]
    wedges, _texts, autotexts = ax2.pie(
        vals, labels=None, colors=colors, autopct=lambda p: f"{p*fuel/100:.1f} MW",
        startangle=90, counterclock=False,
        wedgeprops=dict(width=0.42, edgecolor="white"))
    for at in autotexts:
        at.set_fontsize(9)
        at.set_color(utils.PALETTE["ink"])
    ax2.set_title(f"Fuel energy disposition  (input {fuel:.1f} MW)")
    ax2.legend(wedges, [f"{l}  ({v:.1f} MW)" for l, v in zip(labels, vals)],
               loc="center", bbox_to_anchor=(0.5, -0.08), ncol=1)
    eff = d["thermal_efficiency"][i] * 100.0
    ax2.text(0, 0, f"{eff:.1f}%\nthermal", ha="center", va="center",
             fontsize=12, fontweight="bold", color=utils.PALETTE["primary"])

    fig.suptitle("ThermoTwin-F  -  Design-point summary", fontsize=13, fontweight="bold")
    utils.annotate_source(fig)
    fig.tight_layout(rect=(0, 0.02, 1, 0.96))
    utils.savefig(fig, "design_point.png")
    plt.close(fig)


if __name__ == "__main__":
    main(sys.argv)
