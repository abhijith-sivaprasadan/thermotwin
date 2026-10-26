#!/usr/bin/env python3
"""Optional TESPy Rankine reference fixture, not a ThermoTwin head-to-head test.

Based on the publicly documented configuration at
https://tespy.readthedocs.io/en/stable/basic_tutorials/rankine_cycle.html
Run with tespy==0.11.2.
"""
import argparse
import json
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=Path("build/tespy_rankine_reference.json"))
    opts=parser.parse_args()
    from tespy.components import CycleCloser, Pump, Condenser, Turbine, SimpleHeatExchanger, Source, Sink
    from tespy.connections import Connection
    from tespy.networks import Network

    net=Network()
    net.units.set_defaults(temperature="degC", pressure="bar", enthalpy="kJ/kg", power="MW", heat="MW")
    close=CycleCloser("closer")
    heater=SimpleHeatExchanger("steam generator")
    cond=Condenser("condenser")
    turb=Turbine("turbine")
    pump=Pump("pump")
    source=Source("cooling source")
    sink=Sink("cooling sink")
    c1=Connection(close,"out1",turb,"in1")
    c2=Connection(turb,"out1",cond,"in1")
    c3=Connection(cond,"out1",pump,"in1")
    c4=Connection(pump,"out1",heater,"in1")
    c0=Connection(heater,"out1",close,"in1")
    c11=Connection(source,"out1",cond,"in2")
    c12=Connection(cond,"out2",sink,"in1")
    net.add_conns(c1,c2,c3,c4,c0,c11,c12)
    cond.set_attr(pr1=1,pr2=0.98)
    heater.set_attr(pr=0.9)
    turb.set_attr(eta_s=0.9)
    pump.set_attr(eta_s=0.75)
    c11.set_attr(T=20,p=1.2,fluid={"water":1})
    c12.set_attr(T=30)
    c1.set_attr(T=600,p=150,m=10,fluid={"water":1})
    c2.set_attr(p=0.1)
    net.solve(mode="design")
    vals={"study":"independent Rankine reference case, NOT ThermoTwin validation",
          "inputs":{"live_steam_C":600,"live_steam_bar":150,"steam_kg_per_s":10,
                    "condenser_bar":0.1,"turbine_eta_s":0.9,"pump_eta_s":0.75},
          "turbine_power_W_signed":float(turb.P.val),
          "pump_power_W_signed":float(pump.P.val)}
    vals["net_power_MW_magnitude"]=(abs(vals["turbine_power_W_signed"])-abs(vals["pump_power_W_signed"]))/1e6
    if vals["net_power_MW_magnitude"]<=0:
        raise ValueError("TESPy reference returned non-physical net power")
    opts.output.parent.mkdir(parents=True,exist_ok=True)
    opts.output.write_text(json.dumps(vals,indent=2)+"\n",encoding="utf-8")
    print(f"Independent TESPy Rankine reference saved: {opts.output}")


if __name__=="__main__":
    main()
