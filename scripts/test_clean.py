"""Check the cleanup boundary without deleting any repository files."""
import unittest
import clean


class CleanTests(unittest.TestCase):
    def test_protected_paths_rejected(self):
        for path in (clean.ROOT, clean.ROOT.parent, clean.ROOT / "src", clean.ROOT / ".git", clean.ROOT / "README.md"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                clean.validate([str(path)])

    def test_all_targets_validated_before_removal(self):
        with self.assertRaises(ValueError):
            clean.validate([str(clean.ROOT / "build"), str(clean.ROOT.parent)])

    def test_build_products_allowed(self):
        paths = [clean.ROOT / "build", clean.ROOT / "thermotwin.exe"]
        self.assertEqual(clean.validate([str(p) for p in paths]), paths)


if __name__ == "__main__":
    unittest.main()
