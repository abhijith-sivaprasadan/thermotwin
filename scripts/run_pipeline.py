"""Run the analysis suite and optional report into an isolated output directory."""
from __future__ import annotations

import argparse
import datetime
import hashlib
import importlib.util
import importlib.metadata
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ROOT / ("thermotwin.exe" if os.name == "nt" else "thermotwin"))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/analysis")
    parser.add_argument("--skip-report", action="store_true", help="Generate CSVs using only the Python standard library")
    args = parser.parse_args()
    exe, out = args.exe.resolve(), args.output_dir.resolve()
    if not exe.is_file():
        parser.error(f"Missing executable: {exe}. Run make first.")
    if not args.skip_report:
        missing = [name for name in ("numpy", "matplotlib") if importlib.util.find_spec(name) is None]
        if missing:
            parser.error(f"Missing {', '.join(missing)}. Install requirements.txt or use --skip-report.")
    out.mkdir(parents=True, exist_ok=True)
    # A failed rerun must not leave a previous success manifest behind.
    manifest_path = out / "run_manifest.json"
    manifest_path.unlink(missing_ok=True)
    environment = dict(os.environ, THERMOTWIN_OUTPUT_DIR=str(out), MPLBACKEND="Agg")
    commands = [[str(exe), "selftest"]]
    inputs = []
    outputs = []
    for case, result in (("design_point", "design_point"), ("ambient_sweep", "ambient_sweep"),
                         ("pressure_ratio_sweep", "pr_sweep"), ("TIT_sweep", "tit_sweep"),
                         ("efficiency_sweep", "eta_sweep")):
        path = ROOT / "cases" / (case + ".csv")
        inputs.append(path)
        output = out / ("results_" + result + ".csv")
        outputs.append(output)
        commands.append([str(exe), "run", str(path), str(output)])
    for mode, case in (("degradation", "degradation_cases"), ("transient", "transient_baseline"),
                       ("uncertainty", "uncertainty_baseline"), ("diagnostics", "diagnostics_baseline")):
        path = ROOT / "cases" / (case + ".csv")
        inputs.append(path)
        commands.append([str(exe), mode, str(path)])
        outputs.append(out / ("results_" + mode + ".csv"))
    outputs += [out / "results_degradation_deltas.csv", out / "results_bias_sensitivity.csv"]
    if not args.skip_report:
        commands.append([sys.executable, str(ROOT / "python/report_generator.py")])
    try:
        for command in commands:
            result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=300)
            print(result.stdout, end="")
            if result.returncode:
                print(result.stderr, file=sys.stderr)
                raise RuntimeError(f"Command failed ({result.returncode}): {command}")
        try:
            revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
            dirty = bool(subprocess.run(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=ROOT,
                                        capture_output=True, text=True, check=True).stdout.strip())
        except (OSError, subprocess.CalledProcessError):
            revision, dirty = None, None
        if not args.skip_report:
            outputs += sorted((out / "figures").glob("*.png")) + [out / "ThermoTwin-F_report.pdf"]
        manifest = {
            "schema_version": 1, "generated_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "git_revision": revision, "working_tree_dirty": dirty,
            "executable": str(exe), "executable_sha256": digest(exe),
            "python": platform.python_version(), "platform": platform.platform(),
            "report_dependencies": {name: importlib.metadata.version(name) for name in ("numpy", "matplotlib")}
                                   if not args.skip_report else {},
            "property_model": "constant (analysis CLI)",
            "uncertainty_seed": 20240601, "commands": commands,
            "inputs_sha256": {str(p.relative_to(ROOT)): digest(p) for p in inputs},
            "outputs_sha256": {str(p.relative_to(out)): digest(p) for p in outputs},
        }
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"Analysis complete: {out}\nProvenance: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
