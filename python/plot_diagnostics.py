"""Diagnostics: how well the inverse solver recovers the true degradation.

Usage:
    python python/plot_diagnostics.py [results_diagnostics.csv]
"""
from __future__ import annotations

import os
import sys

import numpy as np
import matplotlib.pyplot as plt

import utils


PRETTY = {
    "delta_eta_compressor": "Compressor\nfouling (Δη)",
    "delta_mdot_fraction": "Mass-flow\nloss (Δṁ/ṁ)",
    "delta_eta_turbine": "Turbine\nerosion (Δη)",
    "delta_dP_combustor": "Combustor\nΔP rise",
}


def main(argv):
    utils.apply_style()
    path = argv[1] if len(argv) > 1 else os.path.join(utils.OUTPUT_DIR, "results_diagnostics.csv")
    d = utils.require(path)

    params = [str(p) for p in d["parameter"]]
    true = d["true_value"].astype(float)
    est = d["estimated_value"].astype(float)

    fig, (axL, axR) = plt.subplots(1, 2, figsize=(12, 5))

    # --- Left: grouped bars true vs estimated ---------------------------
    x = np.arange(len(params))
    w = 0.38
    axL.bar(x - w/2, true, width=w, color=utils.PALETTE["accent"], label="True", edgecolor="white")
    axL.bar(x + w/2, est, width=w, color=utils.PALETTE["secondary"], label="Estimated", edgecolor="white")
    axL.set_xticks(x)
    axL.set_xticklabels([PRETTY.get(p, p) for p in params], fontsize=8.5)
    axL.set_ylabel("Degradation magnitude [-]")
    axL.set_title("Recovered degradation parameters")
    axL.legend()
    for xi, (tv, ev) in enumerate(zip(true, est)):
        axL.text(xi - w/2, tv + 0.0003, f"{tv:.3f}", ha="center", va="bottom", fontsize=7.5)
        axL.text(xi + w/2, ev + 0.0003, f"{ev:.3f}", ha="center", va="bottom", fontsize=7.5)

    # --- Right: parity plot ---------------------------------------------
    lim = max(true.max(), est.max()) * 1.15
    axR.plot([0, lim], [0, lim], color=utils.PALETTE["muted"], ls="--", lw=1, label="perfect recovery")
    axR.scatter(true, est, s=80, color=utils.PALETTE["primary"], zorder=3, edgecolor="white")
    for p, tv, ev in zip(params, true, est):
        axR.annotate(p.replace("delta_", "Δ").replace("_", " "),
                     (tv, ev), textcoords="offset points", xytext=(8, -2), fontsize=7.5)
    axR.set_xlim(0, lim)
    axR.set_ylim(0, lim)
    axR.set_xlabel("True value [-]")
    axR.set_ylabel("Estimated value [-]")
    axR.set_title("Parity: estimated vs true")
    axR.legend(loc="upper left")
    axR.set_aspect("equal", adjustable="box")

    fig.suptitle("ThermoTwin-F  -  Inverse diagnostics", fontsize=14, fontweight="bold")
    utils.annotate_source(fig)
    fig.tight_layout(rect=(0, 0.02, 1, 0.95))
    utils.savefig(fig, "diagnostics.png")
    plt.close(fig)


if __name__ == "__main__":
    main(sys.argv)
