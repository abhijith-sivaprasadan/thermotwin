#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_pipeline.sh - end-to-end demonstration.
#
# Builds the simulator, runs every analysis mode to produce the output CSVs,
# then runs the Python post-processing to produce figures and the PDF report.
#
#   ./scripts/run_pipeline.sh
#
# Requires: gfortran, python3 with numpy + matplotlib.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

echo "============================================================"
echo " ThermoTwin-F : full pipeline"
echo "============================================================"

echo
echo "[1/4] Building simulator..."
./scripts/build.sh

echo
echo "[2/4] Verifying physics (selftest)..."
./thermotwin selftest

echo
echo "[3/4] Running all analysis modes..."
mkdir -p output
# Design point + four sweeps (each sweep CSV is just a batch of operating points).
./thermotwin run cases/design_point.csv          output/results_design_point.csv
./thermotwin run cases/ambient_sweep.csv          output/results_ambient_sweep.csv
./thermotwin run cases/pressure_ratio_sweep.csv   output/results_pr_sweep.csv
./thermotwin run cases/TIT_sweep.csv              output/results_tit_sweep.csv
./thermotwin run cases/efficiency_sweep.csv       output/results_eta_sweep.csv
# Scenario modes (each takes the first row of its file as the baseline machine).
./thermotwin degradation cases/degradation_cases.csv
./thermotwin transient   cases/transient_baseline.csv
./thermotwin uncertainty cases/uncertainty_baseline.csv
./thermotwin diagnostics cases/diagnostics_baseline.csv

echo
echo "[4/4] Post-processing (figures + PDF report)..."
cd python
python3 report_generator.py
cd "${ROOT}"

echo
echo "============================================================"
echo " Done."
echo "   Results CSVs : output/*.csv"
echo "   Figures      : output/figures/*.png"
echo "   Report       : output/ThermoTwin-F_report.pdf"
echo "============================================================"
