"""Remove build products only after validating every requested target."""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate(paths: list[str]) -> list[Path]:
    targets = []
    for value in paths:
        path = Path(value).resolve()
        if path == ROOT or ROOT not in path.parents:
            raise ValueError(f"Refusing to clean outside the repository: {path}")
        if path.is_dir() and path != ROOT / "build" and ROOT / "build" not in path.parents:
            raise ValueError(f"Only directories under build/ may be removed: {path}")
        if not path.is_dir() and path.suffix not in ("", ".exe"):
            raise ValueError(f"Not an executable/build directory: {path}")
        if not path.is_dir() and ROOT / "build" not in path.parents and not path.name.startswith("thermotwin"):
            raise ValueError(f"Not a ThermoTwin executable: {path}")
        targets.append(path)
    return targets


def main(argv: list[str]) -> int:
    try:
        targets = validate(argv)
        for path in targets:
            if path.is_dir():
                shutil.rmtree(path)
            elif path.exists():
                path.unlink()
    except (ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
