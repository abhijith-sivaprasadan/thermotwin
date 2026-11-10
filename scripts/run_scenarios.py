"""Run every bundled scenario with a fresh process and optional CSV recording."""
from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ROOT / ("thermotwin.exe" if os.name == "nt" else "thermotwin"))
    parser.add_argument("--record-dir", type=Path)
    args = parser.parse_args()
    exe = args.exe.resolve()
    if args.record_dir:
        args.record_dir = args.record_dir.resolve()
        args.record_dir.mkdir(parents=True, exist_ok=True)
    scenarios = sorted((ROOT / "cases/scenarios").glob("*.scn"))
    if not exe.is_file() or not scenarios:
        parser.error("Build the CLI first; the executable and bundled scenarios must exist.")
    failed = 0
    for scenario in scenarios:
        command = [str(exe), "scenario", "run", str(scenario)]
        if args.record_dir:
            command += ["--record", str(args.record_dir / (scenario.stem + ".csv"))]
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
            ok = result.returncode == 0
            output = result.stdout + result.stderr
        except (OSError, subprocess.TimeoutExpired) as exc:
            ok, output = False, str(exc)
        print(f"{'PASS' if ok else 'FAIL'}  {scenario.name}")
        if not ok:
            print(output)
            failed += 1
    print(f"SCENARIOS: {len(scenarios) - failed} passed, {failed} failed")
    return int(failed > 0)


if __name__ == "__main__":
    raise SystemExit(main())
