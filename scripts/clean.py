"""Conservatively delete only known ThermoTwin build products.

Called by "make clean" from the repository root. The verifier does not
depend on a build directory existing, so clean works on a fresh checkout.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
REPO_EXECUTABLES = frozenset((
    "thermotwin", "thermotwin.exe", "thermotwin-gui.exe",
    "thermotwin-gui-debug.exe",
))


def validate(paths: list[str]) -> list[Path]:
    if not paths:
        raise ValueError("No build targets specified")
    targets: list[Path] = []
    root = ROOT.resolve()
    build_root = (root / "build").resolve()
    for value in paths:
        if not value or not value.strip():
            raise ValueError("Empty cleanup target")
        path = Path(value).resolve()
        if path == root or root not in path.parents:
            raise ValueError(f"Refusing to clean outside the repository: {path}")
        in_build = path == build_root or build_root in path.parents
        is_named_executable = path.parent == root and path.name in REPO_EXECUTABLES
        if not (in_build or is_named_executable):
            raise ValueError(f"Not a permitted generated target: {path}")
        if path.is_dir() and is_named_executable:
            raise ValueError(f"Executable target is a directory: {path}")
        targets.append(path)
    return targets


def clean(paths: list[str]) -> None:
    # Validate ALL paths before deleting ANYTHING.
    for path in validate(paths):
        if path.is_symlink() or path.is_file():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)


def main(argv: list[str]) -> int:
    try:
        clean(argv)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
