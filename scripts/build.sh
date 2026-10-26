#!/usr/bin/env bash
# Compatibility wrapper: delegate to the verified Makefile dependency graph.
# Older hand-maintained module lists were incomplete for the current engine.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
want_tests=0
want_debug=0
for arg in "$@"; do
  case "$arg" in
    --tests) want_tests=1 ;;
    --debug) want_debug=1 ;;
    *) echo "Unsupported argument: $arg" >&2; exit 2 ;;
  esac
done
target=(all)
if [ "$want_tests" -eq 1 ]; then target+=(tests); fi
if [ "$want_debug" -eq 1 ]; then
  # Fully isolated build to avoid stale objects from different compilation flags.
  make BUILD=build/legacy-debug EXE=build/legacy-debug/thermotwin \
    "FFLAGS=-J build/legacy-debug -I build/legacy-debug -ffree-line-length-none -std=f2008 -O0 -g -fcheck=all -fbacktrace -Wall -Wextra -fimplicit-none" "${target[@]}"
else
  make "${target[@]}"
fi
