#!/usr/bin/env python3
"""Optional TESPy Rankine reference fixture; NOT ThermoTwin model validation.

The independent fixture deliberately uses TESPy 0.11.2 and records both
selected (MW) and SI (W) power values. A successful solve is not evidence
that a different power-cycle model has been validated.
Reference: https://tespy.readthedocs.io/en/stable/basic_tutorials/rankine_cycle.html
"""
import argparse
import json
import math
from importlib.metadata import version
from pathlib import Path


def summarize_powers(turbine_W, pump_W, turbine_MW, pump_MW):
    """Validate dimensions/signs and return independently checkable powers.

    TESPy uses the generator sign convention for turbine output (negative)
    and pump input (positive); this fixture specifies network power in MW.
    Bounds are specific to the 10 kg/s, 150 bar, 600 C teaching example,
    not a general acceptance criterion for real equipment.
    """
    values = (turbine_W, pump_W, turbine_MW, pump_MW)
    if not all(math.isfinite(x) for x in values):
        raise ValueError("TESPy power results contain non-finite values")
    for label, watts, megawatts in (
        ("turbine", turbine_W, turbine_MW),
        ("pump", pump_W, pump_MW),
    ):
        if not math.isclose(watts / 1e6, megawatts, rel_tol=1e-8, abs_tol=1e-8):
            raise ValueError(f"{label} W/MW discrepancy: check TESPy unit settings")
    if turbine_W >= 0.0 or pump_W <= 0.0:
        raise ValueError("Unexpected TESPy turbine/pump power sign convention")
    net_W = -turbine_W - pump_W
    net_MW = net_W / 1e6
    if not 5.0 <= net_MW <= 25.0:
        raise ValueError(f"Implausible illustrative Rankine net power: {net_MW:g} MW")
    return {
        "turbine_power_W_signed": turbine_W,
        "pump_power_W_signed": pump_W,
        "turbine_power_MW_signed": turbine_MW,
        "pump_power_MW_signed": pump_MW,
        "net_power_W_magnitude": net_W,
        "net_power_MW_magnitude": net_MW,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("build/tespy_rankine_reference.json"))
    opts = parser.parse_args()

    from tespy.components import (
        CycleCloser, Pump, Condenser, Turbine, SimpleHeatExchanger, Source, Sink
    )
    from tespy.connections import Connection
    from tespy.networks import Network

    net = Network()
    net.units.set_defaults(
        temperature="degC", pressure="bar", enthalpy="kJ/kg",
        power="MW", heat="MW"
    )
    close = CycleCloser("closer")
    heater = SimpleHeatExchanger("steam generator")
    cond = Condenser("condenser")
    turb = Turbine("turbine")
    pump = Pump("pump")
    source = Source("cooling source")
    sink = Sink("cooling sink")
    c1 = Connection(close, "out1", turb, "in1")
    c2 = Connection(turb, "out1", cond, "in1")
    c3 = Connection(cond, "out1", pump, "in1")
    c4 = Connection(pump, "out1", heater, "in1")
    c0 = Connection(heater, "out1", close, "in1")
    c11 = Connection(source, "out1", cond, "in2")
    c12 = Connection(cond, "out2", sink, "in1")
    net.add_conns(c1, c2, c3, c4, c0, c11, c12)
    cond.set_attr(pr1=1, pr2=0.98)
    heater.set_attr(pr=0.9)
    turb.set_attr(eta_s=0.9)
    pump.set_attr(eta_s=0.75)
    c11.set_attr(T=20, p=1.2, fluid={"water": 1})
    c12.set_attr(T=30)
    c1.set_attr(T=600, p=150, m=10, fluid={"water": 1})
    c2.set_attr(p=0.1)
    net.solve(mode="design")
    if not net.converged:
        raise ValueError("TESPy did not converge; reference result invalid")

    powers = summarize_powers(
        float(turb.P.val_SI), float(pump.P.val_SI),
        float(turb.P.val), float(pump.P.val)
    )
    vals = {
        "study": "standalone Rankine reference fixture, NOT ThermoTwin validation",
        "tespy_version": version("tespy"),
        "network_converged": True,
        "power_convention": "turbine output negative; pump input positive",
        "selected_power_unit": "MW",
        "si_power_unit": "W",
        "inputs": {
            "live_steam_C": 600, "live_steam_bar": 150, "steam_kg_per_s": 10,
            "condenser_bar": 0.1, "turbine_eta_s": 0.9, "pump_eta_s": 0.75,
            "heater_pressure_ratio": 0.9, "condenser_hot_pressure_ratio": 1.0,
            "condenser_cold_pressure_ratio": 0.98,
            "cooling_water_inlet_C": 20, "cooling_water_outlet_C": 30,
            "cooling_water_inlet_bar": 1.2
        },
        **powers,
    }
    opts.output.parent.mkdir(parents=True, exist_ok=True)
    opts.output.write_text(json.dumps(vals, indent=2) + "\n", encoding="utf-8")
    print(f"Standalone TESPy Rankine reference saved: {opts.output}")
    print(f"Net electrical-equivalent cycle output: {powers['net_power_MW_magnitude']:.6f} MW")
    print("This is not a matched-boundary or measured-plant validation.")


if __name__ == "__main__":
    main()
