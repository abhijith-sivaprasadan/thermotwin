"""Regression tests for the native-test runner's completeness gate."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import run_tests
import subprocess


class RunnerTests(unittest.TestCase):
    def test_process_failure_is_reported(self):
        with patch.object(run_tests.subprocess, "run", side_effect=OSError("cannot execute")):
            ok, output = run_tests.run_binary(Path("invalid"))
        self.assertFalse(ok)
        self.assertIn("cannot execute", output)

    def test_hanging_test_is_reported(self):
        with patch.object(run_tests.subprocess, "run", side_effect=subprocess.TimeoutExpired("test", 120)):
            ok, output = run_tests.run_binary(Path("hanging"))
        self.assertFalse(ok)
        self.assertIn("timed out", output)

    def test_explicit_executable_is_used(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "test").mkdir()
            (root / "test/test_one.f90").touch()
            build = root / "custom"
            (build / "tests").mkdir(parents=True)
            suffix = ".exe" if run_tests.os.name == "nt" else ""
            (build / "tests" / ("test_one" + suffix)).touch()
            exe = root / ("renamed" + suffix)
            exe.touch()
            with patch.object(run_tests, "ROOT", root), patch.object(run_tests, "run_binary", return_value=(True, "")) as run:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(run_tests.main(["--build-dir", str(build), "--exe", str(exe)]), 0)
                self.assertEqual(run.call_args.args, (exe, "selftest"))

    def test_missing_build_fails_without_running_selftest(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(run_tests.subprocess, "run") as run:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(run_tests.main(["--build-dir", directory]), 1)
                run.assert_not_called()

    def test_partial_build_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            test_dir = Path(directory) / "tests"
            test_dir.mkdir()
            (test_dir / "test_unrelated.exe").touch()
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(run_tests.main(["--build-dir", directory]), 1)


if __name__ == "__main__":
    unittest.main()
