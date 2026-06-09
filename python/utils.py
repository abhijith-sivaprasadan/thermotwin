"""Shared helpers for ThermoTwin-F post-processing.

Centralises the CSV reader and a single, professional plot style so every
figure in the project looks consistent. No third-party CSV libraries are used
beyond the standard library + numpy, keeping the toolchain light.
"""
from __future__ import annotations

import csv
import os
from typing import Dict, List

import numpy as np
import matplotlib as mpl
import matplotlib.pyplot as plt

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUTPUT_DIR = os.path.join(ROOT, "output")
FIGURE_DIR = os.path.join(OUTPUT_DIR, "figures")


def ensure_figure_dir() -> str:
    os.makedirs(FIGURE_DIR, exist_ok=True)
    return FIGURE_DIR


# ---------------------------------------------------------------------------
# A restrained, presentation-grade colour palette (deep teal / amber / slate).
# Deliberately not the matplotlib defaults so the figures read as bespoke.
# ---------------------------------------------------------------------------
PALETTE = {
    "primary":   "#0B6E78",   # deep teal
    "secondary": "#C8772E",   # amber
    "accent":    "#3A5A7A",   # slate blue
    "muted":     "#8A8F98",   # grey
    "good":      "#2E7D5B",   # green
    "bad":       "#B5453B",   # brick red
    "ink":       "#1F2933",   # near-black text
    "grid":      "#D7DBE0",
}
SERIES_COLORS = [
    PALETTE["primary"], PALETTE["secondary"], PALETTE["accent"],
    PALETTE["good"], PALETTE["bad"], PALETTE["muted"],
]


def apply_style() -> None:
    """Apply the project-wide matplotlib style."""
    mpl.rcParams.update({
        "figure.facecolor": "white",
        "axes.facecolor": "white",
        "axes.edgecolor": PALETTE["ink"],
        "axes.labelcolor": PALETTE["ink"],
        "axes.titlecolor": PALETTE["ink"],
        "axes.titlesize": 12,
        "axes.titleweight": "bold",
        "axes.labelsize": 10.5,
        "axes.linewidth": 1.0,
        "axes.grid": True,
        "grid.color": PALETTE["grid"],
        "grid.linewidth": 0.8,
        "grid.alpha": 0.9,
        "xtick.color": PALETTE["ink"],
        "ytick.color": PALETTE["ink"],
        "xtick.labelsize": 9.5,
        "ytick.labelsize": 9.5,
        "legend.frameon": False,
        "legend.fontsize": 9.5,
        "font.size": 10.5,
        "lines.linewidth": 2.0,
        "lines.markersize": 5.5,
        "figure.dpi": 120,
        "savefig.dpi": 150,
        "savefig.bbox": "tight",
    })


# ---------------------------------------------------------------------------
# CSV reading
# ---------------------------------------------------------------------------
def read_csv(path: str) -> Dict[str, np.ndarray]:
    """Read a ThermoTwin-F results CSV into a dict of columns.

    Numeric columns are returned as float arrays; non-numeric columns
    (case_name, status, ...) are returned as object arrays of strings.
    """
    with open(path, newline="") as fh:
        reader = csv.reader(fh)
        rows = [r for r in reader if r and not r[0].lstrip().startswith("#")]
    if not rows:
        raise ValueError(f"No data in {path}")

    header = [h.strip() for h in rows[0]]
    body = rows[1:]
    cols: Dict[str, list] = {h: [] for h in header}
    for r in body:
        for h, v in zip(header, r):
            cols[h].append(v.strip())

    out: Dict[str, np.ndarray] = {}
    for h, vals in cols.items():
        try:
            out[h] = np.array([float(v) for v in vals])
        except ValueError:
            out[h] = np.array(vals, dtype=object)
    return out


def require(path: str) -> Dict[str, np.ndarray]:
    """Read a CSV, raising a clear error if the file is missing."""
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"Expected results file not found:\n  {path}\n"
            "Run the corresponding ThermoTwin-F mode first (see README)."
        )
    return read_csv(path)


def savefig(fig, name: str) -> str:
    """Save a figure into output/figures and return its path."""
    ensure_figure_dir()
    path = os.path.join(FIGURE_DIR, name)
    fig.savefig(path)
    print(f"  wrote {os.path.relpath(path, ROOT)}")
    return path


def annotate_source(fig, text: str = "ThermoTwin-F - educational model, not validated against a specific engine") -> None:
    """Add a small honest provenance note to a figure."""
    fig.text(0.005, 0.005, text, fontsize=7, color=PALETTE["muted"], ha="left", va="bottom")
