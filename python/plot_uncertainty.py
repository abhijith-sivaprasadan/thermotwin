"""Uncertainty visualisation.

Left  : nominal vs Monte-Carlo mean with 95% interval for the three KPIs.
Right : a tornado chart of deterministic bias sensitivities.

Usage:
    python python/plot_uncertainty.py
"""
from __future__ import annotations

import os
import sys

import numpy as np
import matplotlib.pyplot as plt

import utils


def main(argv):
    utils.apply_style()
    u = utils.require(os.path.join(utils.OUTPUT_DIR, "results_uncertainty.csv"))
    b = utils.require(os.path.join(utils.OUTPUT_DIR, "results_bias_sensitivity.csv"))

    quantity = np.array([str(q) for q in u["quantity"]])
    nominal = u["nominal"].astype(float)
    mean = u["mean"].astype(float)
    sigma = u["sigma"].astype(float)
    p025 = u["p2_5"].astype(float)
    p975 = u["p97_5"].astype(float)

    fig, (axL, axR) = plt.subplots(1, 2, figsize=(12, 5))

    # --- Left: normalised KPI distributions (relative to nominal) -------
    labels = {"net_power_MW": "Net power", "thermal_efficiency": "Efficiency",
              "heat_rate_kJ_kWh": "Heat rate"}
    y = np.arange(len(quantity))
    rel_mean = 100.0 * (mean - nominal) / np.abs(nominal)
    rel_lo = 100.0 * (p025 - nominal) / np.abs(nominal)
    rel_hi = 100.0 * (p975 - nominal) / np.abs(nominal)

    axL.errorbar(rel_mean, y, xerr=[rel_mean - rel_lo, rel_hi - rel_mean],
                 fmt="o", color=utils.PALETTE["primary"], capsize=5, lw=2,
                 label="MC mean & 95% interval")
    axL.axvline(0.0, color=utils.PALETTE["muted"], ls="--", lw=1, label="Nominal")
    axL.set_yticks(y)
    axL.set_yticklabels([labels.get(q, q) for q in quantity])
    axL.set_xlabel("Deviation from nominal [%]")
    axL.set_title("KPI uncertainty (Monte Carlo)")
    axL.legend(loc="best")
    for yi, m_, s_ in zip(y, mean, sigma):
        axL.text(rel_hi[yi] + 0.05, yi, f"σ={s_:.3g}", va="center", fontsize=8,
                 color=utils.PALETTE["ink"])

    # --- Right: tornado of bias sensitivities (effect on power) ---------
    chan = np.array([str(c) for c in b["channel"]])
    dpow = b["dPower_MW"].astype(float)
    order = np.argsort(np.abs(dpow))
    chan, dpow = chan[order], dpow[order]
    colors = [utils.PALETTE["good"] if v >= 0 else utils.PALETTE["bad"] for v in dpow]
    axR.barh(np.arange(len(chan)), dpow, color=colors, edgecolor="white")
    axR.set_yticks(np.arange(len(chan)))
    axR.set_yticklabels([c.replace("_", " ") for c in chan])
    axR.axvline(0.0, color=utils.PALETTE["ink"], lw=1)
    axR.set_xlabel("Δ net power for applied bias [MW]")
    axR.set_title("Bias sensitivity (tornado)")
    for i, v in enumerate(dpow):
        axR.text(v + (0.02 if v >= 0 else -0.02), i, f"{v:+.2f}",
                 va="center", ha="left" if v >= 0 else "right", fontsize=8)

    fig.suptitle("ThermoTwin-F  -  Measurement uncertainty propagation",
                 fontsize=14, fontweight="bold")
    utils.annotate_source(fig)
    fig.tight_layout(rect=(0, 0.02, 1, 0.95))
    utils.savefig(fig, "uncertainty.png")
    plt.close(fig)


if __name__ == "__main__":
    main(sys.argv)
