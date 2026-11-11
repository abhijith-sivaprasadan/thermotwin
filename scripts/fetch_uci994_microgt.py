#!/usr/bin/env python3
"""Acquire original UCI #994 3 kW micro-gas-turbine time-series experiments.

Original data: eight genuine control-voltage / electrical-power time series,
with time IN SECONDS; this is NOT a scaled industrial 30 MW turbine.
DOI https://doi.org/10.24432/C58S4T; CC BY 4.0.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from hashlib import sha256
import io
import json
import math
from pathlib import Path
import re
from urllib.request import Request, urlopen
import zipfile

SOURCE = "https://archive.ics.uci.edu/dataset/994/micro+gas+turbine+electrical+energy+prediction"
URL = "https://archive.ics.uci.edu/static/public/994/micro+gas+turbine+electrical+energy+prediction.zip"
DOI = "10.24432/C58S4T"
TRAIN = (1, 9, 20, 21, 23, 24)
TEST = (4, 22)
EXPERIMENTS = set(TRAIN + TEST)
EXPECTED_TOTAL = 71225
MAX_ARCHIVE = 30_000_000
MAX_MEMBER = 20_000_000
COLUMNS = ("time", "input_voltage", "el_power")


def sha(raw: bytes) -> str:
    return sha256(raw).hexdigest()


def experiment_id(filename: str) -> int | None:
    name = Path(filename).name.lower()
    for pattern in (
        r"experiment[_-](\d+)(?:_short)?\.csv",
        r"ex[_-](\d+)\.csv",
        r"exp[_-](\d+)\.csv",
        r"(\d+)\.csv",
    ):
        result = re.fullmatch(pattern, name)
        if result:
            number = int(result.group(1))
            return number if number in EXPERIMENTS else None
    return None


def original_csv(raw: bytes, label: str) -> list[tuple[float, float, float]]:
    if len(raw) > MAX_MEMBER:
        raise ValueError("UCI 994 member exceeds declared maximum")
    try:
        decoded = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError("UCI original CSV is not UTF-8 text: " + label) from exc
    if len(decoded) < 40:
        raise ValueError("Source experiment CSV is too short: " + label)
    sample = decoded[:8192]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;|\t")
    except csv.Error as exc:
        raise ValueError("Cannot identify original UCI experiment CSV delimiter") from exc
    reader = csv.DictReader(io.StringIO(decoded), dialect=dialect)
    if reader.fieldnames is None:
        raise ValueError("Missing source CSV header")
    fieldnames = [name.strip() for name in reader.fieldnames]
    if set(COLUMNS) - set(fieldnames) or len(set(fieldnames)) != len(fieldnames):
        raise ValueError("Missing/duplicate original time/voltage/power fields: " + str(fieldnames))
    points = []
    prev_time = None
    for n, record in enumerate(reader, start=1):
        if None in record:
            raise ValueError("Ragged source row")
        try:
            t, u, y = [float(record[key]) for key in COLUMNS]
        except (TypeError, ValueError, KeyError) as exc:
            raise ValueError("Original UCI record contains invalid numbers") from exc
        if not all(map(math.isfinite, (t, u, y))):
            raise ValueError("Nonfinite original UCI 994 measurement")
        if t < 0 or u < -100 or u > 100 or y < -1000 or y > 10000:
            raise ValueError("Gross numerical outlier in source time/voltage/power")
        if prev_time is not None and not t > prev_time:
            raise ValueError("Non-increasing time within original source experiment")
        points.append((t, u, y))
        prev_time = t
    if not (5000 <= len(points) <= 13000):
        raise ValueError("Unexpected length for a published UCI 994 experiment")
    return points


def source_experiments(raw: bytes) -> dict[int, tuple[list, dict]]:
    if len(raw) > MAX_ARCHIVE:
        raise ValueError("Original source ZIP exceeds maximum download size")
    resolved = {}

    def visit(blob: bytes, label: str, level: int) -> None:
        if level > 2:
            raise ValueError("Archive nesting exceeds expected UCI package structure")
        try:
            archive = zipfile.ZipFile(io.BytesIO(blob))
        except zipfile.BadZipFile as exc:
            raise ValueError("Invalid original source ZIP: " + label) from exc
        for member in archive.infolist():
            if member.is_dir():
                continue
            if member.file_size > MAX_MEMBER:
                raise ValueError("UCI ZIP member too large")
            member_path = member.filename.replace("\\", "/")
            basename = Path(member_path).name.lower()
            if basename.startswith(".") or "__macosx" in member_path.lower():
                continue
            if basename.endswith(".zip"):
                visit(archive.read(member), label + "/" + member_path, level + 1)
            elif basename.endswith(".csv"):
                experiment = experiment_id(basename)
                if experiment is None:
                    raise ValueError("CSV not identifiable as a published experiment: " + member_path)
                if experiment in resolved:
                    raise ValueError("Duplicate UCI original experiment " + str(experiment))
                content = archive.read(member)
                points = original_csv(content, label + "/" + member_path)
                resolved[experiment] = (points, {
                    "original_archive_member": label + "/" + member_path,
                    "original_csv_sha256": sha(content),
                    "n": len(points),
                    "time_start_s": points[0][0],
                    "time_end_s": points[-1][0],
                })
    visit(raw, "uci994-original.zip", 0)
    if set(resolved) != EXPERIMENTS:
        raise ValueError("UCI 994 missing published experiments: " + str(sorted(EXPERIMENTS - set(resolved))))
    if sum(len(v[0]) for v in resolved.values()) != EXPECTED_TOTAL:
        raise ValueError("Original UCI micro GT total is not 71,225 measurements")
    for experiment, (_points, provenance) in resolved.items():
        path = provenance["original_archive_member"].lower()
        if "/train.zip/" in path and experiment in TEST:
            raise ValueError("Source archive mislabels a test experiment as training")
        if "/test.zip/" in path and experiment in TRAIN:
            raise ValueError("Source archive mislabels a training experiment as testing")
    return resolved


def run(argv=None) -> dict:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--original-zip", type=Path,
                        help="Replay from the original preserved ZIP without network")
    args = parser.parse_args(argv)
    if args.original_zip:
        raw = args.original_zip.read_bytes()
        retrieved = "archive-replay-no-network"
    else:
        request = Request(URL, headers={"User-Agent": "ThermoTwin-F-Open-Research/1.0"})
        with urlopen(request, timeout=60) as reply:
            if reply.status != 200:
                raise ValueError("Original UCI archive HTTP status " + str(reply.status))
            raw = reply.read(MAX_ARCHIVE + 1)
        retrieved = datetime.now(timezone.utc).isoformat()
    experiments = source_experiments(raw)
    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    (out / "uci994_original.zip").write_bytes(raw)
    manifest = {
        "schema": "thermotwin.uci994.original_micro_turbine.v1",
        "dataset_id": 994, "doi": DOI, "license": "CC BY 4.0",
        "source": SOURCE, "original_archive_url": URL,
        "original_zip_sha256": sha(raw), "retrieved_at": retrieved,
        "units": {"time": "seconds", "input_voltage": "volts", "el_power": "watts"},
        "plant_scale": "measured commercial micro-gas-turbine, nominal 3 kW",
        "not_30mw_reference_engine": True,
        "training_experiments": list(TRAIN), "untouched_test_experiments": list(TEST),
        "total_observations": EXPECTED_TOTAL, "experiments": {},
    }
    for experiment in sorted(EXPERIMENTS):
        points, metadata = experiments[experiment]
        name = f"experiment_{experiment}_audited.csv"
        with (out / name).open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(COLUMNS)
            writer.writerows(points)
        manifest["experiments"][str(experiment)] = {
            **metadata, "audited_csv": name,
            "audited_csv_sha256": sha((out / name).read_bytes()),
            "split": "train" if experiment in TRAIN else "test",
        }
    (out / "manifest.json").write_text(json.dumps(
        manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("UCI 994 ORIGINAL measured micro gas turbine: 8 independent experiments")
    print("Count:", EXPECTED_TOTAL, "original SHA256:", manifest["original_zip_sha256"])
    print("Train experiments:", TRAIN, "test experiments:", TEST)
    print("Reported source time (seconds); true field data, not an industrial OEM GT.")
    return manifest


if __name__ == "__main__":
    run()
