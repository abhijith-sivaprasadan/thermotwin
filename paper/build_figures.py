"""Create paper-only figures from archived release-CI JSON without modifying ThermoTwin."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
DATA=ROOT/'evidence'/'raw'
DEST=ROOT/'evidence'/'figures'
DEST.mkdir(parents=True,exist_ok=True)
x=json.loads((DATA/'if97_benchmark.json').read_text())
p=[v['pressure_bar'] for v in x['cases']]
fig,ax=plt.subplots(figsize=(8.2,4.7))
for k,title in [('h_liq_kJ_kg','Saturated liquid'),('h_vap_kJ_kg','Saturated vapour'),('h_superheat_50K_kJ_kg','Superheated (+50 K)')]:
 ax.plot(p,[v['signed_error'][k] for v in x['cases']],marker='o',label=title)
ax.set_xscale('log');ax.axhline(0,linewidth=.9,alpha=.5)
ax.set_xlabel('Pressure (bar, log scale)');ax.set_ylabel('ThermoTwin − CoolProp IF97 enthalpy (kJ/kg)')
ax.legend(fontsize=9);ax.grid(alpha=.22);fig.tight_layout();fig.savefig(DEST/'figure1_property_enthalpy_errors.png',dpi=170);plt.close(fig)
fig,ax=plt.subplots(figsize=(8.2,4.3))
ax.plot(p,[v['signed_error']['T_sat_K'] for v in x['cases']],marker='o')
ax.set_xscale('log');ax.axhline(0,linewidth=.9,alpha=.5)
ax.set_xlabel('Pressure (bar, log scale)');ax.set_ylabel('ThermoTwin − CoolProp IF97 saturation T (K)')
ax.grid(alpha=.22);fig.tight_layout();fig.savefig(DEST/'figure2_temperature_errors.png',dpi=170);plt.close(fig)
print('generated',list(f.name for f in DEST.glob('*.png')))
