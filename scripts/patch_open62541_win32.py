#!/usr/bin/env python3
"""Patch the pinned open62541 amalgam header for a native Win32 build.

Avoid Unix-specific sed syntax so make download-opcua works in PowerShell,
cmd.exe, MSYS2 and Unix shells with the same Python implementation.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

_REQUIRED = (
    (b"#define UA_ARCHITECTURE_POSIX", b"/* #undef UA_ARCHITECTURE_POSIX */"),
    (b"/* #undef UA_ARCHITECTURE_WIN32 */", b"#define UA_ARCHITECTURE_WIN32"),
)
_OPTIONAL = (
    (b"#define UA_ENABLE_ENCRYPTION_MBEDTLS", b"/* #undef UA_ENABLE_ENCRYPTION_MBEDTLS */"),
)


def patch_header_bytes(raw: bytes) -> bytes:
    """Return idempotently patched header, failing closed on unknown architecture."""
    for before, after in (*_REQUIRED, *_OPTIONAL):
        before_re = re.compile(b"^" + re.escape(before) + b"(?P<eol>\r?)$", re.MULTILINE)
        after_re = re.compile(b"^" + re.escape(after) + b"\r?$", re.MULTILINE)
        old_count = len(before_re.findall(raw))
        new_count = len(after_re.findall(raw))
        if old_count + new_count > 1:
            raise ValueError(f"Ambiguous or duplicate open62541 directive: {before.decode()}")
        if old_count == 1:
            raw = before_re.sub(lambda match: after + match.group("eol"), raw, count=1)
        elif new_count == 0 and (before, after) in _REQUIRED:
            raise ValueError(f"Unsupported open62541 header: missing {before.decode()}")
    return raw


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("header", nargs="?", type=Path, default=Path("gui/open62541.h"))
    args = parser.parse_args()
    if not args.header.is_file():
        parser.error(f"Missing header: {args.header}; run make download-opcua first")
    original = args.header.read_bytes()
    patched = patch_header_bytes(original)
    if patched != original:
        args.header.write_bytes(patched)
        print(f"Updated Windows architecture flags in {args.header}")
    else:
        print(f"Windows architecture flags already correct in {args.header}")


if __name__ == "__main__":
    main()
