#!/usr/bin/env bash
# Run every reference scenario through the simulator and fail on any
# failed assertion. Usage: scripts/run_scenarios.sh [path-to-thermotwin]
set -euo pipefail

exe="${1:-./thermotwin}"
status=0

for scn in cases/scenarios/*.scn; do
    echo
    if ! "$exe" scenario run "$scn"; then
        status=1
    fi
done

if [ "$status" -ne 0 ]; then
    echo
    echo "SCENARIO SUITE: FAIL"
    exit 1
fi
echo
echo "SCENARIO SUITE: PASS"
