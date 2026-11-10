#!/usr/bin/env python3
"""Fail-closed inventory of local Markdown links in this checkout.

Checks that relative targets in engineering documentation actually exist.
Not an anchor, remote URL, accessibility, or scientific claims audit.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

INLINE = re.compile(r'!?\[[^\]\n]*\]\(\s*(<[^>\n]+>|[^\s)]+)')
HTML = re.compile(r'\b(?:href|src)\s*=\s*["\x27]([^"\x27]+)["\x27]', re.I)
REMOTE = re.compile(r'^(?:[a-z][a-z0-9+.-]*:|//)', re.I)


def links_in_markdown(content: str):
    visible, fenced = [], False
    for line in content.splitlines():
        stripped = line.lstrip()
        if stripped.startswith((chr(96) * 3, "~" * 3)):
            fenced = not fenced
            continue
        if not fenced:
            visible.append(line)
    document = "\n".join(visible)
    for regex in (INLINE, HTML):
        for match in regex.finditer(document):
            yield match.group(1).strip("<>")


def scan(root: Path, sources: list[Path]):
    root = root.resolve()
    invalid = []
    for file in sources:
        for target in links_in_markdown(file.read_text(encoding="utf-8")):
            if not target or target.startswith("#") or REMOTE.match(target):
                continue
            url = urlsplit(target)
            if url.scheme or url.netloc or not url.path:
                continue
            decoded = unquote(url.path)
            if decoded.startswith("/"):
                destination = (root / decoded.lstrip("/")).resolve()
            else:
                destination = (file.parent / decoded).resolve()
            if destination != root and root not in destination.parents:
                invalid.append((file.relative_to(root).as_posix(), target,
                                "escapes repository"))
            elif not destination.exists():
                invalid.append((file.relative_to(root).as_posix(), target,
                                "missing local path"))
    return invalid


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    sources = [root / "README.md"]
    sources.extend(sorted((root / "docs").glob("*.md")))
    sources.extend(sorted((root / "cases").glob("README.md")))
    sources.extend(sorted((root / "gui").glob("README.md")))
    absent = [p for p in sources if not p.is_file()]
    if absent:
        raise SystemExit("Missing required documentation: " + str(absent))
    issues = scan(root, sources)
    for source, url, reason in issues:
        print(f"{source}: {reason}: {url}")
    print(f"Local Markdown link audit: {len(sources)} files, {len(issues)} unresolved paths")
    if issues:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
