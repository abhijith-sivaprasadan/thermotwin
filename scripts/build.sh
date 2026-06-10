#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build.sh - compile ThermoTwin-F with gfortran (fpm-free fallback).
#
# This mirrors what `fpm build` does but needs no network and no fpm install.
# Modules are compiled in dependency order into build/, then linked into
# the `thermotwin` executable at the project root.
#
# Usage:
#   ./scripts/build.sh           # build the main app
#   ./scripts/build.sh --tests   # also build the unit-test programs
#   ./scripts/build.sh --debug   # add bounds-checking / debug flags
# ---------------------------------------------------------------------------
set -euo pipefail

# Resolve project root (this script lives in scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

SRC=src
APP=app
TEST=test
BUILD=build
mkdir -p "${BUILD}"

FC=${FC:-gfortran}
FFLAGS_COMMON="-J ${BUILD} -I ${BUILD} -ffree-line-length-none -std=f2008"
FFLAGS_RELEASE="-O2"
FFLAGS_DEBUG="-O0 -g -fcheck=all -fbacktrace -Wall -Wextra -fimplicit-none"

BUILD_TESTS=0
FFLAGS_MODE="${FFLAGS_RELEASE}"
for arg in "$@"; do
    case "$arg" in
        --tests) BUILD_TESTS=1 ;;
        --debug) FFLAGS_MODE="${FFLAGS_DEBUG}" ;;
        *) echo "unknown option: $arg" ; exit 1 ;;
    esac
done

FFLAGS="${FFLAGS_COMMON} ${FFLAGS_MODE}"
echo "Compiler : ${FC}"
echo "Flags    : ${FFLAGS}"
echo

# Compilation order respects the module dependency graph.
MODULES=(
    precision_kinds
    constants
    types
    utilities
    fluid_properties
    ambient
    compressor
    combustor
    turbine
    shaft_generator
    cycle_solver
    degradation
    transient_thermal
    sensor_model
    uncertainty_analysis
    diagnostics_solver
    csv_io
    sensitivity_driver
    off_design
    hrsg
    steam_cycle
    tag_bus
    engine_state
    fleet_dispatch
    grid_dynamics
    dispatch_agc
    plant_economics
    engine_core
    scenario_runner
)

OBJS=()
echo "Compiling modules..."
for m in "${MODULES[@]}"; do
    echo "  [FC] ${m}.f90"
    if [[ -f "${SRC}/${m}.f90" ]]; then
        source_path="${SRC}/${m}.f90"
    else
        source_path="${SRC}/engine/${m}.f90"
    fi
    ${FC} ${FFLAGS} -c "${source_path}" -o "${BUILD}/${m}.o"
    OBJS+=("${BUILD}/${m}.o")
done

echo "Compiling and linking main application..."
${FC} ${FFLAGS} -c "${APP}/main.f90" -o "${BUILD}/main.o"
${FC} ${FFLAGS} "${OBJS[@]}" "${BUILD}/main.o" -o thermotwin
echo "  -> ./thermotwin"

if [[ "${BUILD_TESTS}" -eq 1 ]]; then
    echo
    echo "Building unit tests..."
    mkdir -p "${BUILD}/tests"
    for tsrc in "${TEST}"/test_*.f90; do
        [ -e "${tsrc}" ] || continue
        tname="$(basename "${tsrc}" .f90)"
        echo "  [FC] ${tname}"
        # Object goes in build/ (so build/tests/ holds only executables);
        # the include path covers test/ for test_assert.inc.
        ${FC} ${FFLAGS} -I "${TEST}" -c "${tsrc}" -o "${BUILD}/${tname}.o"
        ${FC} ${FFLAGS} "${OBJS[@]}" "${BUILD}/${tname}.o" -o "${BUILD}/tests/${tname}"
    done
    echo "  test binaries in ${BUILD}/tests/"
fi

echo
echo "Build complete."
