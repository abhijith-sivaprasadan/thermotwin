#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"${MAKE:-make}" all
exec "${PYTHON:-python3}" scripts/run_pipeline.py "$@"
