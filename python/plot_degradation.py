"""Degradation comparison: grouped bars of key KPIs across degradation levels.

Usage:
    python python/plot_degradation.py [results_degradation.csv]
"""
from __future__ import annotations

import os
import sys

import numpy as np
import matplotlib.pyplot as plt

import utils


def main(argv):
    utils.apply_style()
    path = argv[1] if len(argv) > 1 else os.path.join(utils.OUTPUT_DIR, "results_degradation.csv")
    d = utils.require(path)

    modes = [str(m) for m in d["degradation_mode"]]
    power = d["net_power_MW"].astype(float)
    eff = d["thermal_efficiency"].astype(float) * 100.0
    hr = d["heat_rate_kJ_kWh"].astype(float)
    texh = d["exhaust_temperature_K"].astype(float)

    fig, axes = plt.subplots(1, 2, figsize=(11.5, 4.8))

    # --- Left: power and efficiency (twin axis) -------------------------
    ax = axes[0]
    x = np.arange(len(modes))
    w = 0.38
    b1 = ax.bar(x - w/2, power, width=w, color=utils.PALETTE["primary"], label="Net power [MW]", edgecolor="white")
    ax.set_ylabel("Net power [MW]", color=utils.PALETTE["primary"])
    ax.set_ylim(0, power.max()*1.18)
    ax.set_xticks(x)
    ax.set_xticklabels(modes)
    for b, v in zip(b1, power):
        ax.text(b.get_x()+b.get_width()/2, v+0.2, f"{v:.1f}", ha="center", va="bottom", fontsize=8)

    ax2 = ax.twinx()
    b2 = ax2.bar(x + w/2, eff, width=w, color=utils.PALETTE["secondary"], label="Efficiency [%]", edgecolor="white")
    ax2.set_ylabel("Thermal efficiency [%]", color=utils.PALETTE["secondary"])
    ax2.set_ylim(0, eff.max()*1.18)
    ax2.grid(False)
    for b, v in zip(b2, eff):
        ax2.text(b.get_x()+b.get_width()/2, v+0.2, f"{v:.1f}", ha="center", va="bottom", fontsize=8)
    ax.set_title("Power & efficiency vs degradation")

    # --- Right: heat rate and exhaust temperature -----------------------
    ax = axes[1]
    b3 = ax.bar(x - w/2, hr, width=w, color=utils.PALETTE["accent"], label="Heat rate [kJ/kWh]", edgecolor="white")
    ax.set_ylabel("Heat rate [kJ/kWh]", color=utils.PALETTE["accent"])
    ax.set_ylim(hr.min()*0.96, hr.max()*1.04)
    ax.set_xticks(x)
    ax.set_xticklabels(modes)

    ax2 = ax.twinx()
    ax2.plot(x, texh, marker="o", color=utils.PALETTE["bad"], label="Exhaust T [K]")
    ax2.set_ylabel("Exhaust temperature [K]", color=utils.PALETTE["bad"])
    ax2.grid(False)
    ax.set_title("Heat rate & exhaust temperature")
    ax.annotate("washing recovers compressor,\nnot turbine erosion",
                xy=(3, hr[3]), xytext=(1.4, hr.max()*1.02),
                fontsize=8, color=utils.PALETTE["ink"],
                arrowprops=dict(arrowstyle="->", color=utils.PALETTE["muted"], lw=1))

    fig.suptitle("ThermoTwin-F  -  Degradation impact", fontsize=14, fontweight="bold")
    utils.annotate_source(fig)
    fig.tight_layout(rect=(0, 0.02, 1, 0.95))
    utils.savefig(fig, "degradation.png")
    plt.close(fig)


if __name__ == "__main__":
    main(sys.argv)
