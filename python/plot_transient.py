"""Transient metal-temperature response for startup / load-ramp / shutdown.

Usage:
    python python/plot_transient.py [results_transient.csv]
"""
from __future__ import annotations

import os
import sys

import numpy as np
import matplotlib.pyplot as plt

import utils


def main(argv):
    utils.apply_style()
    path = argv[1] if len(argv) > 1 else os.path.join(utils.OUTPUT_DIR, "results_transient.csv")
    d = utils.require(path)

    schedule = np.array([str(s) for s in d["schedule"]])
    t = d["time_s"].astype(float)
    tgas = d["T_gas_K"].astype(float)
    tmetal = d["T_metal_K"].astype(float)

    schedules = ["startup", "load_ramp", "shutdown"]
    titles = ["Cold start", "Load ramp", "Shutdown"]

    fig, axes = plt.subplots(1, 3, figsize=(13.5, 4.4), sharey=True)
    for ax, sch, title in zip(axes, schedules, titles):
        m = schedule == sch
        tt = t[m] / 60.0   # minutes
        ax.plot(tt, tgas[m], color=utils.PALETTE["secondary"], ls="--", label="Gas (drive)")
        ax.plot(tt, tmetal[m], color=utils.PALETTE["primary"], label="Metal node")
        ax.fill_between(tt, tmetal[m], tgas[m], color=utils.PALETTE["muted"], alpha=0.10)
        ax.set_xlabel("Time [min]")
        ax.set_title(title)
        ax.legend(loc="best")
        # Thermal lag annotation: peak gradient point.
        if sch == "startup" and m.sum() > 2:
            grad = np.gradient(tmetal[m], t[m])
            k = int(np.argmax(grad))
            ax.annotate("steepest\nmetal rise", xy=(tt[k], tmetal[m][k]),
                        xytext=(tt[k]+8, tmetal[m][k]-120), fontsize=8,
                        color=utils.PALETTE["ink"],
                        arrowprops=dict(arrowstyle="->", color=utils.PALETTE["muted"]))
    axes[0].set_ylabel("Temperature [K]")

    fig.suptitle("ThermoTwin-F  -  Transient hot-section thermal response (lumped node)",
                 fontsize=13, fontweight="bold")
    utils.annotate_source(fig)
    fig.tight_layout(rect=(0, 0.02, 1, 0.95))
    utils.savefig(fig, "transient.png")
    plt.close(fig)


if __name__ == "__main__":
    main(sys.argv)
