"""Input-validation regression tests; generated rows below are NOT field data."""
import csv
import io
import zipfile
import unittest
from scripts.fetch_uci_gt551 import (
    YEAR_COUNTS, VARIABLES, load_package, parse_annual_csv,
)


def annual_csv(year, missing=False):
    stream = io.StringIO()
    writer = csv.DictWriter(stream, fieldnames=VARIABLES)
    writer.writeheader()
    normal = {
        "AT": 15, "AP": 1013, "AH": 60, "AFDP": 4,
        "GTEP": 25, "TIT": 1080, "TAT": 546, "TEY": 133,
        "CDP": 12, "CO": 2, "NOX": 65,
    }
    for i in range(YEAR_COUNTS[year] - (1 if missing else 0)):
        writer.writerow(normal)
    return stream.getvalue().encode("utf-8")


class UCI551ImportTests(unittest.TestCase):
    def test_shape_and_original_year_order(self):
        rows, digest = parse_annual_csv(annual_csv(2011), 2011)
        self.assertEqual(len(rows), 7411)
        self.assertEqual(rows[0]["TIT"], 1080)
        self.assertEqual(len(digest), 64)

    def test_missing_row_rejected(self):
        with self.assertRaisesRegex(ValueError, "expected"):
            parse_annual_csv(annual_csv(2011, missing=True), 2011)

    def test_bad_units_not_guessed_from_schema(self):
        # The original CDP values must NOT be converted to Pa automatically:
        # documentation says mbar but recorded magnitudes are ambiguous.
        rows, _ = parse_annual_csv(annual_csv(2011), 2011)
        self.assertEqual(rows[0]["CDP"], 12.0)

    def test_missing_original_year_rejected(self):
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w") as archive:
            archive.writestr("original/gt_2011.csv", annual_csv(2011))
        with self.assertRaisesRegex(ValueError, "missing annual CSV"):
            load_package(out.getvalue())


if __name__ == "__main__":
    unittest.main()
