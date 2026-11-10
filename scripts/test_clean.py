"""Deletion guard tests use only empty temporary files; never project data."""
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from scripts import clean


class SafeCleanTests(unittest.TestCase):
    def test_rejects_important_and_outside_paths(self):
        root = clean.ROOT
        for path in (root, root.parent, root / "src", root / ".git",
                     root / "README.md", root / "output", root / "cases"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                clean.validate([str(path)])

    def test_rejects_ambiguous_unrelated_executable(self):
        with self.assertRaises(ValueError):
            clean.validate([str(clean.ROOT / "thermotwin-not-a-build.exe")])

    def test_absent_build_directory_is_permitted(self):
        # A fresh checkout has no build dir; validation must not depend on
        # whether the generated target exists.
        with patch.object(clean, "ROOT", Path(tempfile.gettempdir()) / "tt-clean-absent"):
            base = clean.ROOT
            # Absolute targets are used here so cwd is independent.
            self.assertEqual(clean.validate([str(base / "build"), str(base / "thermotwin")]),
                             [(base / "build").resolve(), (base / "thermotwin").resolve()])
            clean.clean([str(base / "build"), str(base / "thermotwin")])

    def test_validation_is_atomic(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "build").mkdir()
            artifact = root / "build" / "log.txt"
            artifact.write_text("one")
            with patch.object(clean, "ROOT", root):
                with self.assertRaises(ValueError):
                    clean.clean([str(artifact), str(root / "src")])
            self.assertEqual(artifact.read_text(), "one")

    def test_only_compiled_artifacts_are_deleted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            build = root / "build"
            build.mkdir()
            (build / "artifact.o").write_bytes(b"not source")
            (root / "thermotwin.exe").write_bytes(b"not source")
            (root / "README.md").write_text("retain")
            with patch.object(clean, "ROOT", root):
                clean.clean([str(build), str(root / "thermotwin.exe")])
            self.assertFalse(build.exists())
            self.assertFalse((root / "thermotwin.exe").exists())
            self.assertEqual((root / "README.md").read_text(), "retain")


if __name__ == "__main__":
    unittest.main()
