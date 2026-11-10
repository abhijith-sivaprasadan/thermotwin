#!/usr/bin/env bash
# Compatibility wrapper: Make owns the module dependency graph.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
targets=(all)
options=()
for arg in "$@"; do
    case "$arg" in
        --tests) targets+=(tests) ;;
        --debug) options+=(PROFILE=debug) ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
exec "${MAKE:-make}" "FC=${FC:-gfortran}" "${options[@]}" "${targets[@]}"
