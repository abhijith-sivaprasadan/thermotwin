"""Exercise the built CLI's file contracts and failure paths in a temporary workspace."""
from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, type=Path)
    args = parser.parse_args()
    exe = args.exe.resolve()
    if not exe.is_file():
        parser.error(f"Missing executable: {exe}")
    lines = [s for s in (ROOT / "cases/design_point.csv").read_text().splitlines()
             if s.strip() and not s.lstrip().startswith(("#", "!"))]
    header, row = lines[0], lines[1]
    passed = failed = 0
    with tempfile.TemporaryDirectory(prefix="thermotwin-cli-") as directory:
        work = Path(directory)
        (work / "analysis").mkdir()
        env = dict(os.environ, THERMOTWIN_OUTPUT_DIR=str(work / "analysis"))

        def check(name, command, success, expected=None):
            nonlocal passed, failed
            try:
                result = subprocess.run([str(exe), *map(str, command)], cwd=work, env=env,
                                        capture_output=True, text=True, timeout=120)
                ok = (result.returncode == 0) == success
                output = result.stdout + result.stderr
                if expected:
                    ok = ok and expected in output
            except (OSError, subprocess.TimeoutExpired) as exc:
                ok, output = False, str(exc)
            print(f"{'PASS' if ok else 'FAIL'}  {name}")
            if ok:
                passed += 1
            else:
                failed += 1
                print(output)

        def case(text):
            path = work / "input.csv"
            path.write_text(text + "\n", encoding="utf-8")
            return path

        check("help", ["--help"], True, "scenario run")
        check("unknown mode", ["typo"], False, "unknown mode")
        check("missing input", ["run"], False)
        check("empty input argument", ["run", ""], False, "argument")
        check("overlong argument", ["run", "x" * 1100], False, "argument")
        check("extra arguments", ["run", ROOT / "cases/design_point.csv", "x.csv", "ignored"], False)
        check("missing file", ["run", "absent.csv"], False, "cannot open input")
        check("batch CSV", ["run", case(header + "\n" + row + "\n" + row), "batch.csv"], True)
        with (work / "batch.csv").open() as stream:
            records = list(csv.DictReader(stream))
        if len(records) != 2 or any(r["converged"].strip() != "1" for r in records):
            raise AssertionError("Batch must contain two converged operating points")
        check("header-only CSV", ["run", case(header)], False, "no data rows")
        check("reordered header", ["run", case(header.replace("ambient_T_K", "ambient_temp") + "\n" + row)], False, "header")
        check("missing column", ["run", case(header + "\n" + row.rsplit(",", 1)[0])], False, "fields")
        check("extra column", ["run", case(header + "\n" + row + ",extra")], False, "fields")
        for value in ("", "NaN", "Infinity", "1e999", "288 invalid", "288/", "1*288"):
            fields = row.split(",")
            fields[1] = value
            check(f"invalid numeric cell {value!r}", ["run", case(header + "\n" + ",".join(fields))], False)
        fields = row.split(",")
        fields[5] = "-100"
        check("negative air flow", ["run", case(header + "\n" + ",".join(fields))], False)
        fields = row.split(",")
        fields[8] = "750"
        check("unphysical cycle fails", ["run", case(header + "\n" + ",".join(fields)), "unphysical.csv"], False, "sanity")
        check("unphysical analysis baseline fails", ["degradation", work / "input.csv"], False, "invalid analysis baseline")
        check("default output override", ["run", case(header + "\n" + row)], True)
        if not (work / "analysis/results_run.csv").is_file():
            raise AssertionError("Default run output ignored THERMOTWIN_OUTPUT_DIR")
        check("unwritable results path", ["run", case(header + "\n" + row), "missing/result.csv"], False, "cannot write")
        check("isolated analysis outputs", ["degradation", ROOT / "cases/degradation_cases.csv"], True)
        if not (work / "analysis/results_degradation.csv").is_file():
            raise AssertionError("Analysis output directory override was ignored")

        def scenario(text, record=None):
            path = work / "input.scn"
            path.write_text(text + "\n", encoding="utf-8")
            command = ["scenario", "run", path]
            if record:
                command += ["--record", record]
            return command

        for text in ("duration -1", "duration 0", "dt 0", "dt NaN", "duration Infinity",
                     "duration 1\nat 2 assert_above demand_MW 0", "at -1 set demand_MW 2",
                     "at 1 assert_near frequency_Hz 50 -0.1", "duration 1\nat 1 set demand_MW 2",
                     "duration 1 ignored", "at 0 set demand_MW NaN", "at 0 set demand_MW 20 ignored"):
            check(f"invalid scenario {text!r}", scenario(text), False)
        check("unknown set target", scenario("duration 1\nat 0 set demand_typo 40"), False, "unknown set target")
        check("unknown command", scenario("duration 1\nat 0 command typo"), False, "unknown command")
        check("failed assertion", scenario("duration 1\nat 0.5 assert_above demand_MW 1000"), False, "FAIL")
        check("unwritable recorder", scenario("duration 1", "missing/trace.csv"), False, "cannot open recorder")
        check("last partial tick assertion executes", scenario("duration 0.6\ndt 0.25\nat 0.6 assert_above demand_MW 1000"), False, "FAIL")
        check("valid recorder", scenario("duration 1\nat 0.5 assert_above demand_MW 1", "trace.csv"), True, "1 assertions")
        check("duplicate record option", [*scenario("duration 1", "trace.csv"), "--record", "second.csv"], False)
        with (work / "trace.csv").open() as stream:
            records = list(csv.DictReader(stream))
        if len(records) != 4 or "frequency_Hz" not in records[0]:
            raise AssertionError("Recorder must contain one row per tick with engineering-unit headers")
    print(f"CLI: {passed} passed, {failed} failed")
    return int(failed > 0)


if __name__ == "__main__":
    raise SystemExit(main())
