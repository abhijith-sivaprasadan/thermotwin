#!/usr/bin/env bash
set -euo pipefail
# Resolve an explicitly supplied executable before changing directories.
exe="${1:-}"
if [[ -n "$exe" ]]; then
    exe="$(cd "$(dirname "$exe")" && pwd)/$(basename "$exe")"
fi
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "$exe" ]]; then
    exec "${PYTHON:-python3}" scripts/run_scenarios.py --exe "$exe"
fi
exec "${MAKE:-make}" scenarios
