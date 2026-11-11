#!/usr/bin/env python3
"""Independent Python replay of ThermoTwin-F's recorded active-power ledger.

Reads real simulator CSV output, independently checks per-tick power/energy
identities and integrates frequency. It does NOT validate turbine or grid
physics against field data. Standard-library only; deterministic fixture.
"""
from __future__ import annotations

import argparse
import csv
import math
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# The inertia coefficient is measured in MW*s/Hz, not kinetic energy MW*s.
# The coefficient is independently re-derived from stored energy every tick.
ETA = 0.92
BATTERY_CAP_MWH = 30.0
INVERTER_MW = 20.0
EPS_MW = 1e-4
EPS_HZ = 1e-4
EPS_MWH = 2e-5


def near(label: str, got: float, expected: float, tol: float, time: float) -> None:
    if not math.isfinite(got) or abs(got - expected) > tol:
        raise AssertionError(
            f"t={time:.2f}s {label}: got {got:.9g}, expected {expected:.9g}, tolerance {tol}"
        )


def verify(rows: list[dict[str, str]]) -> int:
    if len(rows) < 20:
        raise AssertionError("Recorder too short to validate timestep dynamics")
    required = {
        "time_s", "frequency_Hz", "nominal_frequency_Hz", "ROCOF_Hz_s",
        "demand_MW", "served_demand_MW", "ufls_shed_MW", "supply_MW",
        "imbalance_MW", "plant_power_MW", "renewable_actual_MW",
        "storage_MW", "battery_energy_MWh", "BESS_primary_MW",
        "gfm_synth_MW", "effective_gas_dispatch_pct", "governor_delta_MW",
        "static_served_demand_MW", "grid_damping_load_MW",
        "grid_damping_MW_per_Hz", "grid_stored_inertia_MWs",
        "grid_swing_MW_s_per_Hz", "grid_model_valid",
    }
    missing = required.difference(rows[0])
    if missing:
        raise AssertionError(f"Flight recorder missing fields: {sorted(missing)}")

    for index, raw in enumerate(rows):
        v = {field: float(raw[field]) for field in required}
        if not all(math.isfinite(x) for x in v.values()):
            raise AssertionError(f"Nonfinite recorder value at row {index}")
        t = v["time_s"]
        near("static UFLS demand", v["demand_MW"] - v["ufls_shed_MW"],
             v["static_served_demand_MW"], EPS_MW, t)
        near("frequency-sensitive load booked as actual demand",
             v["static_served_demand_MW"] + v["grid_damping_load_MW"],
             v["served_demand_MW"], EPS_MW, t)
        near("derived inertia in MW*s/Hz",
             2.0*v["grid_stored_inertia_MWs"]/v["nominal_frequency_Hz"],
             v["grid_swing_MW_s_per_Hz"], EPS_MW, t)
        if v["grid_model_valid"] != 1.0:
            raise AssertionError(f"Invalid grid physics at t={t:.2f}s")
        # This scenario is single-GT simple cycle with no P2X or CCS.
        near("one physical supply sum",
             v["plant_power_MW"] + v["renewable_actual_MW"] + v["storage_MW"],
             v["supply_MW"], EPS_MW, t)
        near("served-load MW imbalance", v["supply_MW"] - v["served_demand_MW"],
             v["imbalance_MW"], EPS_MW, t)
        near("independent dimensional swing RHS",
             v["imbalance_MW"] / v["grid_swing_MW_s_per_Hz"],
             v["ROCOF_Hz_s"], EPS_HZ, t)
        if abs(v["storage_MW"]) > INVERTER_MW + EPS_MW:
            raise AssertionError(f"Inverter MW exceeded at t={t:.2f}s")
        if not (-EPS_MWH <= v["battery_energy_MWh"] <= BATTERY_CAP_MWH + EPS_MWH):
            raise AssertionError(f"Battery capacity violated at t={t:.2f}s")
        if not (-1e-6 <= v["effective_gas_dispatch_pct"] <= 100.0 + 1e-6):
            raise AssertionError(f"Effective turbine dispatch violated at t={t:.2f}s")
        if index == 0:
            continue

        previous = {field: float(rows[index - 1][field]) for field in required}
        # Frequency-sensitive load is evaluated before frequency advances;
        # the row therefore uses the previous row's f, not the reported
        # post-integration frequency of this row.
        expected_damping = v["grid_damping_MW_per_Hz"] * (
            previous["frequency_Hz"] - v["nominal_frequency_Hz"]
        )
        near("frequency-dependent load from previous-frequency state",
             v["grid_damping_load_MW"], max(-v["static_served_demand_MW"],
                 expected_damping), EPS_MW, t)
        dt = t - previous["time_s"]
        if dt <= 0.0:
            raise AssertionError(f"Time not strictly increasing at t={t}")
        f_new = min(
            v["nominal_frequency_Hz"] + 3.0,
            max(
                v["nominal_frequency_Hz"] - 3.0,
                previous["frequency_Hz"] + v["ROCOF_Hz_s"] * dt,
            ),
        )
        near("independent frequency integration", v["frequency_Hz"], f_new, EPS_HZ, t)

        power = v["storage_MW"]
        e_expected = previous["battery_energy_MWh"]
        if power >= 0.0:
            e_expected -= power * dt / (3600.0 * ETA)
        else:
            e_expected -= power * dt * ETA / 3600.0
        near("independent signed battery MWh integration",
             v["battery_energy_MWh"], e_expected, EPS_MWH, t)
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    args = parser.parse_args()
    exe = args.executable.resolve()
    if not exe.is_file():
        raise SystemExit(f"Missing simulator binary: {exe}")
    with tempfile.TemporaryDirectory(prefix="ttf-grid-ledger-") as scratch:
        output = Path(scratch) / "flight.csv"
        subprocess.run(
            [str(exe), "scenario", "run",
             str(ROOT / "cases/scenarios/grid_energy_replay.scn"),
             "--record", str(output)],
            cwd=ROOT,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        with output.open(newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        checked = verify(rows)
        # Independent checker must reject an internally inconsistent flight
        # recorder, not merely run successfully on generated model outputs.
        for field, offset in [("battery_energy_MWh", 0.1), ("supply_MW", 1.0),
                              ("ROCOF_Hz_s", 1.0),
                              ("grid_swing_MW_s_per_Hz", 2.0),
                              ("grid_damping_load_MW", 1.0)]:
            altered = [dict(row) for row in rows]
            altered[3][field] = str(float(altered[3][field]) + offset)
            try:
                verify(altered)
            except AssertionError:
                pass
            else:
                raise AssertionError(f"Tampered {field} escaped independent validator")
    print(f"PASS independently replayed {checked} grid samples: MW, Hz/s, MWh, bounds")
    print("NOTE: arithmetic/reference test only; no OEM/field validation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
