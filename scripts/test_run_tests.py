"""Regression tests for the native-test runner's completeness gate."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import run_tests


class RunnerTests(unittest.TestCase):
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
