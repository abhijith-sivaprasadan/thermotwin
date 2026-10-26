#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run_tests.sh - build and run the full ThermoTwin-F unit-test suite.
#
# Equivalent in spirit to `fpm test`, but with no network/fpm dependency.
# Exits non-zero if any test fails (suitable for CI).
# ---------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

echo "Building library + tests..."
./scripts/build.sh --tests >/tmp/ttf_build.log 2>&1 || {
    echo "BUILD FAILED:"; cat /tmp/ttf_build.log; exit 2;
}

echo
echo "Running unit tests"
echo "=================="
pass=0
fail=0
for t in build/tests/test_*; do
    case "$t" in *.o) continue ;; esac
    name="$(basename "$t")"
    if "./$t" >/tmp/ttf_test.log 2>&1; then
        printf "  PASS  %s\n" "$name"
        pass=$((pass + 1))
    else
        printf "  FAIL  %s\n" "$name"
        sed 's/^/        /' /tmp/ttf_test.log
        fail=$((fail + 1))
    fi
done

echo
echo "Also running application selftest (physics verification)..."
if ./thermotwin selftest >/tmp/ttf_self.log 2>&1; then
    echo "  PASS  selftest"
    pass=$((pass + 1))
else
    echo "  FAIL  selftest"
    cat /tmp/ttf_self.log
    fail=$((fail + 1))
fi

echo
echo "SUMMARY: ${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ] || exit 1
