#!/usr/bin/env python3
"""Regression checks: reject malformed gas-turbine input cases, not just garbage."""
from __future__ import annotations

import argparse
import csv
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "cases" / "design_point.csv"


def run_case(executable: Path, name: str, header: str, data: str, accepted: bool) -> None:
    with tempfile.TemporaryDirectory(prefix="ttf-csv-") as dirname:
        folder = Path(dirname)
        case = folder / "input.csv"
        output = folder / "output.csv"
        case.write_text(header + "\n" + data + "\n", encoding="utf-8")
        proc = subprocess.run(
            [str(executable), "run", str(case), str(output)],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        if (proc.returncode == 0) != accepted:
            raise AssertionError(
                f"{name}: expected success={accepted}; returncode={proc.returncode}; "
                f"output={proc.stdout[-1600:]} {proc.stderr[-1600:]}"
            )
        if accepted and (not output.exists() or "net_power_MW" not in output.read_text()):
            raise AssertionError(f"{name}: accepted case did not produce result CSV")
        if not accepted and output.exists():
            raise AssertionError(f"{name}: invalid input wrote a result CSV")
    print(f"PASS {name}: {'accepted' if accepted else 'rejected'}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    args = parser.parse_args()
    exe = args.executable.resolve()
    if not exe.is_file():
        parser.error(f"compiled CLI not found: {exe}")
    rows = [
        line for line in SOURCE.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith(("#", "!"))
    ]
    header, sample = rows[0], rows[1]
    data = next(csv.reader([sample]))
    names = header.split(",")
    assert len(data) == len(names) == 18

    run_case(exe, "good-baseline", header, sample, True)
    run_case(exe, "header-swapped", ",".join(names[:2][::-1] + names[2:]), sample, False)
    run_case(exe, "missing-column", header, ",".join(data[:-1]), False)
    run_case(exe, "extra-column", header, ",".join([*data, "unexpected"]), False)

    for name, idx, replacement in [
        ("missing-ambient-temperature", 1, ""),
        ("missing-fuel-LHV", 11, ""),
        ("nan-ambient", 1, "NaN"),
        ("infinite-inlet-pressure", 2, "Infinity"),
        ("malformed-heat-rate-input", 11, "unparseable"),
        ("missing-identifier", 0, ""),
        ("missing-degradation-mode", 17, ""),
    ]:
        altered = list(data)
        altered[idx] = replacement
        run_case(exe, name, header, ",".join(altered), False)

    print("PASS: all engineering-input schema and finite-value checks")


if __name__ == "__main__":
    main()
