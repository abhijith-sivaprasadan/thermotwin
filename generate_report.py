#!/usr/bin/env python3
"""
ThermoTwin-F Shift Report Generator
Usage: python generate_report.py <shift_data_tXXXX.csv>

Generates a multi-page PDF report with:
  Page 1 — Title + KPI dashboard
  Page 2 — Day-ahead Gantt (GT/BESS/SoC/margin)
  Page 3 — Stochastic price fan + DA economics
  Page 4 — Fleet UC merit-order dispatch
  Page 5 — GT P2 optimizer (HR curve + margin)
  Page 6 — Compressor wash ROI analysis
  Page 7 — Frequency history + Pareto fronts
  Page 8 — Operations Gantt + shift summary table
"""

import sys
import os
import textwrap
from datetime import datetime
import numpy as np

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.gridspec import GridSpec

# ─── ISA-101 OLED dark palette ───────────────────────────────────────────────
BG         = '#0a0a0a'
PANEL      = '#141414'
PANEL_ALT  = '#1c1c1c'
GREEN      = '#00E864'
LIME       = '#30D158'
AMBER      = '#FF9500'
RED        = '#FF3B30'
CYAN       = '#32ADE6'
BLUE       = '#0A84FF'
MUTED      = '#909090'
INK        = '#E5E5E7'
DIM        = '#484848'
BORDER     = '#2a2a2a'


def parse_csv(filepath):
    """Parse section-based CSV → {section_name: (header_list, [row_list])}."""
    sections = {}
    current = None
    header = None
    rows = []
    with open(filepath, encoding='utf-8') as f:
        for raw in f:
            line = raw.rstrip('\n').rstrip('\r')
            if not line or line.startswith('#'):
                continue
            if line.startswith('[') and line.endswith(']'):
                if current is not None:
                    sections[current] = (header, rows)
                current = line[1:-1]
                header = None
                rows = []
            elif header is None and current is not None:
                header = [c.strip() for c in line.split(',')]
            else:
                rows.append([c.strip() for c in line.split(',')])
    if current is not None:
        sections[current] = (header, rows)
    return sections


def to_dict(header, rows):
    """SUMMARY section (field, value, unit) → {field: float}."""
    d = {}
    for row in rows:
        if len(row) >= 2:
            try:
                d[row[0]] = float(row[1])
            except ValueError:
                d[row[0]] = row[1]
    return d


def to_arrays(header, rows):
    """Numeric section → {col: np.ndarray}. Non-numeric kept as list."""
    if not header or not rows:
        return {}
    cols = header
    raw = {c: [] for c in cols}
    for row in rows:
        for j, col in enumerate(cols):
            if j < len(row):
                raw[col].append(row[j])
    result = {}
    for c, vals in raw.items():
        try:
            result[c] = np.array([float(v) for v in vals])
        except ValueError:
            result[c] = vals
    return result


def section_records(sections, name):
    """Return a section as a list of dict rows, preserving string values."""
    if name not in sections:
        return []
    header, rows = sections[name]
    if not header:
        return []
    records = []
    for row in rows:
        rec = {}
        for i, col in enumerate(header):
            rec[col] = row[i] if i < len(row) else ''
        records.append(rec)
    return records


def clean_label(value):
    return str(value).replace('_', ' ').strip()


def display_value(value, unit=''):
    value = str(value).strip()
    unit = str(unit).strip()
    try:
        f = float(value)
        if abs(f) >= 1000:
            value = f'{f:,.0f}'
        elif abs(f) >= 100:
            value = f'{f:.1f}'
        elif abs(f) >= 10:
            value = f'{f:.2f}'
        else:
            value = f'{f:.3f}'
    except ValueError:
        pass
    if unit and unit != '-':
        return f'{value} {unit}'
    return value


def dark_style(ax):
    ax.set_facecolor(PANEL)
    ax.tick_params(colors=MUTED, labelsize=8)
    ax.xaxis.label.set_color(MUTED)
    ax.yaxis.label.set_color(MUTED)
    ax.title.set_color(INK)
    for sp in ax.spines.values():
        sp.set_color(BORDER)


def new_fig(figsize=(11, 8.5)):
    return plt.figure(figsize=figsize, facecolor=BG)


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_report.py <shift_data.csv>")
        sys.exit(1)
    csv_path = sys.argv[1]
    if not os.path.exists(csv_path):
        print(f"File not found: {csv_path}")
        sys.exit(1)

    base = os.path.splitext(csv_path)[0]
    pdf_path = base + '.pdf'

    sections = parse_csv(csv_path)
    meta  = to_dict(*sections['REPORT_META']) if 'REPORT_META' in sections else {}
    summ  = to_dict(*sections['SUMMARY'])   if 'SUMMARY'      in sections else {}
    da    = to_arrays(*sections['DA_SCHEDULE'])  if 'DA_SCHEDULE'  in sections else {}
    gto   = to_arrays(*sections['GT_OPTIMIZER']) if 'GT_OPTIMIZER' in sections else {}
    fleet = to_arrays(*sections['FLEET_UC'])     if 'FLEET_UC'     in sections else {}
    hist  = to_arrays(*sections['HISTORY'])      if 'HISTORY'      in sections else {}
    active_rows = section_records(sections, 'ACTIVE_SCREEN')
    advisory_rows = section_records(sections, 'ADVISORY')
    alarms = []
    if 'ALARMS' in sections:
        _, arows = sections['ALARMS']
        alarms = [(r[0], r[1]) for r in arows if len(r) >= 2]

    g = lambda key, default=0.0: float(summ.get(key, default))

    with PdfPages(pdf_path) as pdf:

        # ══════════════════════════════════════════════════════════════════════
        # PAGE 1 — Branded operations brief + active-screen context
        # ══════════════════════════════════════════════════════════════════════
        fig = new_fig()
        elapsed_h = g('elapsed_s') / 3600.0
        active_screen = str(meta.get('active_screen', 'HMI active screen'))
        severity = str(meta.get('advisory_severity', 'NORMAL')).strip().upper()
        sev_col = RED if severity in ('CRITICAL', 'HIGH') else (AMBER if severity == 'ADVISORY' else GREEN)
        fig.text(0.5, 0.95, 'ThermoTwin-F', fontsize=30, color=CYAN, ha='center',
                 fontweight='bold', fontfamily='monospace')
        fig.text(0.5, 0.90, 'Plant Operations Report', fontsize=15, color=INK, ha='center')
        fig.text(0.5, 0.865, f"Active screen: {active_screen}  |  Advisory: {severity}",
                 fontsize=10, color=sev_col, ha='center', fontfamily='monospace')
        fig.text(0.5, 0.835, f"Generated {datetime.now().strftime('%Y-%m-%d %H:%M')}  "
                 f"|  Elapsed {elapsed_h:.2f} h  |  Zone {meta.get('power_zone', 'n/a')}  "
                 f"|  {os.path.basename(csv_path)}",
                 fontsize=8, color=DIM, ha='center')

        freq = g('frequency_Hz', 50.0)
        hr   = g('gt_heat_rate_kJ_kWh', 9200.0)
        net  = g('da_revenue_usd') - g('da_cost_usd')
        kpis = [
            ('Frequency',      f'{freq:.4f} Hz',
             GREEN if abs(freq - 50) < 0.1 else (AMBER if abs(freq - 50) < 0.5 else RED)),
            ('GT Dispatch',    f"{g('gas_power_MW'):.1f} MW",   CYAN),
            ('BESS SoC',       f"{g('battery_soc_pct'):.1f} %", BLUE),
            ('Heat Rate',      f'{hr:.0f} kJ/kWh',
             GREEN if hr < 9400 else (AMBER if hr < 9700 else RED)),
            ('DA Net Margin',  f'${net:+.0f}',
             GREEN if net > 0 else RED),
            ('LP Gap',         f"{g('da_gap_pct'):.1f} %",
             GREEN if g('da_gap_pct') < 5 else AMBER),
            ('Wash HR Gap',    f"{g('wash_hr_gap_pct'):.2f} %",
             GREEN if g('wash_hr_gap_pct') < 2 else (AMBER if g('wash_hr_gap_pct') < 5 else RED)),
            ('System LMP',     f"${g('fleet_lmp_usd_MWh'):.1f}/MWh",  CYAN),
            ('Reserve MW',     f"{g('reserve_MW'):.1f} MW",
             GREEN if g('reserve_MW') > 10 else RED),
        ]
        x0s = [0.05, 0.37, 0.69]
        y0s = [0.70, 0.56, 0.42]
        for idx, (label, val, col) in enumerate(kpis):
            cx, cy = x0s[idx % 3], y0s[idx // 3]
            ax = fig.add_axes([cx, cy, 0.27, 0.10])
            ax.set_facecolor(PANEL_ALT)
            ax.set_xlim(0, 1); ax.set_ylim(0, 1); ax.axis('off')
            ax.add_patch(mpatches.Rectangle((0, 0), 0.04, 1, fc=col, ec='none',
                                            transform=ax.transAxes))
            ax.text(0.08, 0.75, label, fontsize=8, color=MUTED, va='top',
                    fontfamily='monospace', transform=ax.transAxes)
            ax.text(0.08, 0.20, val, fontsize=13, color=col, va='bottom',
                    fontweight='bold', fontfamily='monospace', transform=ax.transAxes)
            for sp in ax.spines.values():
                sp.set_color(BORDER)

        ax_active = fig.add_axes([0.05, 0.06, 0.43, 0.31])
        ax_active.set_facecolor(PANEL)
        ax_active.axis('off')
        ax_active.text(0.02, 0.94, 'Active Screen Data', fontsize=9, color=MUTED,
                       fontfamily='monospace', va='top', transform=ax_active.transAxes)
        if active_rows:
            shown = 0
            for rec in active_rows:
                metric = clean_label(rec.get('metric', ''))
                if metric.lower() in ('screen', 'zone'):
                    continue
                val = display_value(rec.get('value', ''), rec.get('unit', ''))
                if not metric or shown >= 9:
                    continue
                y = 0.80 - shown * 0.085
                ax_active.text(0.04, y, metric[:28], fontsize=7.5, color=MUTED,
                               fontfamily='monospace', transform=ax_active.transAxes)
                ax_active.text(0.58, y, val[:24], fontsize=8.2, color=INK,
                               fontfamily='monospace', transform=ax_active.transAxes)
                shown += 1
        else:
            ax_active.text(0.5, 0.5, 'No active-screen section in CSV',
                           fontsize=9, color=DIM, ha='center', va='center',
                           fontfamily='monospace', transform=ax_active.transAxes)
        for sp in ax_active.spines.values():
            sp.set_color(BORDER)

        ax_adv = fig.add_axes([0.52, 0.06, 0.43, 0.31])
        ax_adv.set_facecolor(PANEL)
        ax_adv.axis('off')
        ax_adv.text(0.02, 0.94, 'Operator Advisory', fontsize=9, color=MUTED,
                    fontfamily='monospace', va='top', transform=ax_adv.transAxes)
        ax_adv.text(0.96, 0.94, severity, fontsize=8, color=sev_col, ha='right',
                    fontfamily='monospace', va='top', transform=ax_adv.transAxes)
        if advisory_rows:
            y = 0.80
            for rec in advisory_rows[:5]:
                text = str(rec.get('text', '')).strip()
                for wrapped in textwrap.wrap(text, width=58)[:2]:
                    ax_adv.text(0.04, y, wrapped, fontsize=7.4, color=INK,
                                fontfamily='monospace', transform=ax_adv.transAxes)
                    y -= 0.075
                    if y < 0.15:
                        break
                if y < 0.15:
                    break
        elif alarms:
            for j, (sev, desc) in enumerate(alarms[:4]):
                col = RED if 'CRITICAL' in sev else (AMBER if 'HIGH' in sev else CYAN)
                ax_adv.text(0.04, 0.80 - j * 0.15, f'[{sev}] {desc}',
                            fontsize=7.6, color=col, va='top', fontfamily='monospace',
                            transform=ax_adv.transAxes)
        else:
            ax_adv.text(0.5, 0.50, 'No active alarms - system healthy',
                        fontsize=10, color=GREEN, ha='center', va='center',
                        fontfamily='monospace', transform=ax_adv.transAxes)
        for sp in ax_adv.spines.values():
            sp.set_color(BORDER)

        pdf.savefig(fig, bbox_inches='tight'); plt.close(fig)

        # ══════════════════════════════════════════════════════════════════════
        # PAGE 2 — Day-ahead Gantt (GT/BESS/SoC/margin)
        # ══════════════════════════════════════════════════════════════════════
        if da and 'hour' in da:
            hours   = da['hour'].astype(int)
            p_gt    = da.get('p_gt_MW',     np.zeros_like(da['hour']))
            p_bess  = da.get('p_bess_MW',   np.zeros_like(da['hour']))
            soc     = da.get('soc_MWh',     np.zeros_like(da['hour']))
            price   = da.get('price_usd_MWh', np.zeros_like(da['hour']))
            demand  = da.get('demand_MW',   np.zeros_like(da['hour']))
            commit  = da.get('commit',      np.ones_like(da['hour']))
            plo     = da.get('price_lo',    price * 0.85)
            phi     = da.get('price_hi',    price * 1.15)

            fig = new_fig()
            gs = GridSpec(4, 1, figure=fig, hspace=0.10,
                          left=0.09, right=0.95, top=0.92, bottom=0.07)

            ax1 = fig.add_subplot(gs[0])
            dark_style(ax1)
            gt_colors = [GREEN if c else DIM for c in commit]
            ax1.bar(hours, np.where(commit.astype(bool), p_gt, 0),
                    width=0.65, color=gt_colors, alpha=0.85, edgecolor=BORDER, lw=0.4,
                    label='GT')
            ax1.bar(hours, np.where(p_bess > 0, p_bess, 0), width=0.65,
                    color=GREEN, alpha=0.55, bottom=np.where(commit.astype(bool), p_gt, 0),
                    label='BESS discharge')
            ax1.bar(hours, np.where(p_bess < 0, p_bess, 0), width=0.65,
                    color=BLUE, alpha=0.55, label='BESS charge')
            ax1.step(hours, demand, color=AMBER, lw=1.2, where='mid', label='Demand')
            ax1.set_ylabel('MW', fontsize=8); ax1.set_xticks(hours[::2])
            ax1.set_title('Day-Ahead Dispatch (GT + BESS vs Demand)', color=INK, fontsize=11, pad=3)
            ax1.legend(fontsize=7, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK,
                       loc='upper right', ncol=4)

            ax2 = fig.add_subplot(gs[1])
            dark_style(ax2)
            ax2.fill_between(hours, plo, phi, alpha=0.20, color=AMBER)
            ax2.plot(hours, phi, color=AMBER, lw=0.6, ls='--', alpha=0.6, label='P95')
            ax2.plot(hours, plo, color=BLUE,  lw=0.6, ls='--', alpha=0.6, label='P5')
            ax2.plot(hours, price, color=AMBER, lw=1.8, label='DA price')
            ax2.set_ylabel('$/MWh', fontsize=8); ax2.set_xticks(hours[::2])
            ax2.legend(fontsize=7, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK, ncol=3)

            ax3 = fig.add_subplot(gs[2])
            dark_style(ax3)
            ax3.plot(hours, soc, color=BLUE, lw=1.8, marker='o', ms=3, label='SoC')
            if soc.max() > 0:
                ax3.axhline(soc.max() * 0.95, color=GREEN, lw=0.7, ls='--', alpha=0.5)
                ax3.axhline(soc.max() * 0.05, color=RED,   lw=0.7, ls='--', alpha=0.5)
            ax3.set_ylabel('BESS MWh', fontsize=8); ax3.set_xticks(hours[::2])

            ax4 = fig.add_subplot(gs[3])
            dark_style(ax4)
            net_margin = price * demand - p_gt * g('fuel_price_usd_gj', 8.0) * \
                         g('gt_heat_rate_kJ_kWh', 9200.0) / 1000.0
            bar_colors = [GREEN if v >= 0 else RED for v in net_margin]
            ax4.bar(hours, net_margin, width=0.65, color=bar_colors, alpha=0.85,
                    edgecolor=BORDER, lw=0.3)
            ax4.axhline(0, color=MUTED, lw=0.8)
            ax4.set_ylabel('$/h margin', fontsize=8)
            ax4.set_xlabel('Hour (1–24)', fontsize=8); ax4.set_xticks(hours[::2])

            pdf.savefig(fig, bbox_inches='tight'); plt.close(fig)

        # ══════════════════════════════════════════════════════════════════════
        # PAGE 3 — Stochastic price fan + DA economics summary
        # ══════════════════════════════════════════════════════════════════════
        fig = new_fig()
        gs = GridSpec(2, 3, figure=fig, hspace=0.45, wspace=0.30,
                      left=0.08, right=0.96, top=0.90, bottom=0.08)

        ax = fig.add_subplot(gs[0, :])
        dark_style(ax)
        if da and 'hour' in da:
            ax.fill_between(hours, plo, phi, alpha=0.20, color=AMBER, label='P5–P95 fan')
            ax.plot(hours, phi, color=AMBER, lw=0.7, ls='--', alpha=0.7)
            ax.plot(hours, plo, color=BLUE,  lw=0.7, ls='--', alpha=0.7)
            ax.plot(hours, price, color=AMBER, lw=2.0, label='Base DA price')
            for t in range(len(hours)):
                if commit[t]:
                    ax.axvspan(hours[t] - 0.5, hours[t] + 0.5, alpha=0.06, color=GREEN)
        ax.set_ylabel('$/MWh', fontsize=9); ax.set_xlabel('Hour', fontsize=9)
        ax.set_title('Stochastic Price Fan  (AR ±15%·√t/24)', color=INK, fontsize=11)
        ax.legend(fontsize=8, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK)

        # Cost/Revenue bar (bottom-left pair)
        ax2 = fig.add_subplot(gs[1, 0:2])
        dark_style(ax2)
        cost_v = g('da_cost_usd'); rev_v = g('da_revenue_usd')
        net_v  = rev_v - cost_v
        bars = ax2.bar(['GT Cost', 'Revenue', 'Net Margin'],
                       [cost_v, rev_v, net_v],
                       color=[RED, CYAN, GREEN if net_v >= 0 else RED],
                       edgecolor=BORDER, alpha=0.85)
        ax2.axhline(0, color=MUTED, lw=0.8)
        for bar, val in zip(bars, [cost_v, rev_v, net_v]):
            ax2.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + abs(cost_v) * 0.02,
                     f'${val:+.0f}', ha='center', fontsize=8, color=INK, fontfamily='monospace')
        ax2.set_ylabel('USD', fontsize=9)
        ax2.set_title('DA Economics Summary', color=INK, fontsize=10)

        # LP Gap gauge (bottom-right)
        ax3 = fig.add_subplot(gs[1, 2])
        dark_style(ax3); ax3.axis('off')
        gap = g('da_gap_pct')
        gap_col = GREEN if gap < 5 else (AMBER if gap < 15 else RED)
        ax3.text(0.5, 0.72, 'LP Duality Gap', fontsize=9, color=MUTED,
                 ha='center', transform=ax3.transAxes)
        ax3.text(0.5, 0.42, f'{gap:.2f} %', fontsize=22, color=gap_col,
                 ha='center', va='center', fontweight='bold', fontfamily='monospace',
                 transform=ax3.transAxes)
        ax3.text(0.5, 0.14, 'N_SOC=50  N_PGT=20\nMINLP via DP', fontsize=7, color=DIM,
                 ha='center', transform=ax3.transAxes)

        fig.suptitle('Day-Ahead Economics & Stochastic Scenarios', color=INK, fontsize=13, y=0.97)
        pdf.savefig(fig, bbox_inches='tight'); plt.close(fig)

        # ══════════════════════════════════════════════════════════════════════
        # PAGE 4 — Fleet UC merit-order dispatch
        # ══════════════════════════════════════════════════════════════════════
        fig = new_fig()
        gs = GridSpec(2, 2, figure=fig, hspace=0.42, wspace=0.32,
                      left=0.10, right=0.95, top=0.88, bottom=0.08)

        ax1 = fig.add_subplot(gs[0, :])
        dark_style(ax1)
        if fleet and 'unit_id' in fleet:
            unit_ids  = fleet['unit_id']
            names     = [fleet['name'][i] if 'name' in fleet else f'U{i+1}'
                         for i in range(len(unit_ids))]
            costs     = fleet.get('cost_usd_MWh',      np.zeros(len(unit_ids)))
            caps      = fleet.get('capacity_MW',        np.zeros(len(unit_ids)))
            dispatch  = fleet.get('dispatch_MW',        np.zeros(len(unit_ids)))
            online    = fleet.get('online',             np.ones(len(unit_ids)))
            order     = np.argsort(costs)
            y_pos     = np.arange(len(order))
            ax1.barh(y_pos, caps[order], height=0.38, color=DIM, alpha=0.35, label='Capacity')
            bar_cols = [GREEN if online[i] else RED for i in order]
            ax1.barh(y_pos, dispatch[order], height=0.38, color=bar_cols, alpha=0.90,
                     label='Dispatched')
            ax1.set_yticks(y_pos)
            ax1.set_yticklabels([names[int(i)] if isinstance(names, list) else f'U{i}'
                                 for i in order],
                                color=INK, fontsize=9)
            ax1.set_xlabel('MW', fontsize=9)
            ax1.set_title('Fleet Merit-Order Economic Dispatch', color=INK, fontsize=11)
            for j, i in enumerate(order):
                ax1.text(caps[i] + 1, j, f'${costs[i]:.1f}/MWh',
                         va='center', color=AMBER, fontsize=8, fontfamily='monospace')
            ax1.legend(fontsize=8, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK)

        # Cost vs reserve scatter (bottom-left, simulated)
        ax2 = fig.add_subplot(gs[1, 0])
        dark_style(ax2)
        if fleet and 'capacity_MW' in fleet:
            caps_f  = fleet['capacity_MW']
            costs_f = fleet['cost_usd_MWh']
            online_f = fleet.get('online', np.ones(len(caps_f)))
            total_cap = float(np.dot(caps_f, online_f))
            d_scan = np.linspace(10, total_cap, 40)
            fc_arr, res_arr = [], []
            for d in d_scan:
                rem = d; fc = 0.0
                idx_s = np.argsort(costs_f)
                for ii in idx_s:
                    if not online_f[ii]: continue
                    take = min(float(caps_f[ii]), rem)
                    fc += take * float(costs_f[ii])
                    rem -= take
                fc_arr.append(fc); res_arr.append(max(0.0, total_cap - d))
            sc = ax2.scatter(res_arr, fc_arr, c=d_scan, cmap='plasma', s=28,
                             edgecolors=BORDER, lw=0.3)
            plt.colorbar(sc, ax=ax2, label='Demand (MW)',
                         fraction=0.04, pad=0.02).ax.tick_params(colors=MUTED, labelsize=6)
            ax2.scatter([g('reserve_MW')], [g('fleet_uc_total_cost_h')],
                        color=GREEN, s=90, marker='D', zorder=10, label='Operating point')
            ax2.set_xlabel('Reserve margin (MW)', fontsize=9)
            ax2.set_ylabel('Fleet cost ($/h)',    fontsize=9)
            ax2.set_title('Fleet Cost vs Reserve Pareto', color=INK, fontsize=10)
            ax2.legend(fontsize=7, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK)

        # Fleet KPIs (bottom-right)
        ax3 = fig.add_subplot(gs[1, 1]); dark_style(ax3); ax3.axis('off')
        kv = [('System LMP',    f"${g('fleet_lmp_usd_MWh'):.1f}/MWh", CYAN),
              ('Total cost/h',  f"${g('fleet_uc_total_cost_h'):.0f}",  GREEN),
              ('Marginal unit', f"{int(g('fleet_marginal_unit', 1))}",  MUTED),
              ('Fleet MW',      f"{g('fleet_total_MW'):.1f}",          LIME)]
        for j, (k, v, col) in enumerate(kv):
            ax3.text(0.05, 0.80 - j * 0.22, k, fontsize=8, color=MUTED,
                     transform=ax3.transAxes, fontfamily='monospace')
            ax3.text(0.05, 0.65 - j * 0.22, v, fontsize=12, color=col,
                     fontweight='bold', transform=ax3.transAxes, fontfamily='monospace')

        fig.suptitle('Fleet Unit Commitment & Economic Dispatch', color=INK, fontsize=13, y=0.95)
        pdf.savefig(fig, bbox_inches='tight'); plt.close(fig)

        # ══════════════════════════════════════════════════════════════════════
        # PAGE 5 — GT P2 optimizer (HR curve + margin curve)
        # ══════════════════════════════════════════════════════════════════════
        fig = new_fig()
        gs = GridSpec(1, 2, figure=fig, wspace=0.28,
                      left=0.09, right=0.96, top=0.88, bottom=0.10)

        ax1 = fig.add_subplot(gs[0])
        dark_style(ax1)
        if gto and 'power_MW' in gto:
            pwr_g  = gto['power_MW']
            hr_g   = gto.get('heat_rate_kJ_kWh', np.full_like(pwr_g, 9200.0))
            margin_g = gto.get('margin_usd_h',   np.zeros_like(pwr_g))
            ax1.plot(pwr_g, hr_g, color=AMBER, lw=2.0, marker='o', ms=4, label='HR curve')
            ax1.axhline(9200, color=GREEN, lw=0.9, ls='--', alpha=0.7, label='Clean 9200')
            ax1.axhline(g('gt_heat_rate_kJ_kWh', 9200), color=RED, lw=1.0, ls=':',
                        label=f"Current {g('gt_heat_rate_kJ_kWh', 9200):.0f}")
            if len(margin_g) > 0:
                bi = int(np.argmax(margin_g))
                ax1.plot(pwr_g[bi], hr_g[bi], 'o', color=GREEN, ms=10, zorder=5,
                         label=f'P2 optimum {pwr_g[bi]:.0f} MW')
                ax1.axvline(pwr_g[bi], color=GREEN, lw=0.8, ls='--', alpha=0.5)
        ax1.set_xlabel('Power output (MW)', fontsize=9)
        ax1.set_ylabel('Heat rate (kJ/kWh)', fontsize=9)
        ax1.set_title('GT Heat Rate Curve', color=INK, fontsize=11)
        ax1.legend(fontsize=8, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK)

        ax2 = fig.add_subplot(gs[1])
        dark_style(ax2)
        if gto and 'power_MW' in gto:
            m_colors = [GREEN if m >= 0 else RED for m in margin_g]
            ax2.bar(range(len(pwr_g)), margin_g, color=m_colors, alpha=0.85,
                    edgecolor=BORDER, lw=0.4)
            ax2.axhline(0, color=MUTED, lw=0.8)
            if len(margin_g) > 0:
                bi = int(np.argmax(margin_g))
                ax2.bar(bi, margin_g[bi], color=LIME, alpha=1.0, edgecolor=GREEN, lw=1.5)
            ax2.set_xlabel('Scan-point index (0 = 30% load)', fontsize=9)
            ax2.set_ylabel('Net margin ($/h)', fontsize=9)
            ax2.set_title('P2 Margin Curve', color=INK, fontsize=11)
            ax2.text(0.97, 0.97, f"Best margin\n${g('gt_opt_best_margin'):.0f}/h",
                     transform=ax2.transAxes, ha='right', va='top', color=GREEN,
                     fontsize=9, fontfamily='monospace')

        fig.suptitle('GT P2 Economic Dispatch Optimizer', color=INK, fontsize=13, y=0.95)
        pdf.savefig(fig, bbox_inches='tight'); plt.close(fig)

        # ══════════════════════════════════════════════════════════════════════
        # PAGE 6 — Compressor wash ROI
        # ══════════════════════════════════════════════════════════════════════
        fig = new_fig()
        gs = GridSpec(2, 2, figure=fig, hspace=0.45, wspace=0.30,
                      left=0.09, right=0.95, top=0.88, bottom=0.09)

        hr_gap      = g('wash_hr_gap_pct')
        daily_save  = g('wash_daily_saving_usd')
        breakeven   = g('wash_breakeven_days', 999.0)
        wash_cost   = 2500.0
        hr_col = GREEN if hr_gap < 2 else (AMBER if hr_gap < 5 else RED)

        # Gauge (top-left)
        ax1 = fig.add_subplot(gs[0, 0])
        dark_style(ax1)
        theta = np.linspace(np.pi, 0, 180)
        ax1.fill_between(np.cos(theta), np.sin(theta) * 0.55, np.sin(theta),
                         alpha=0.12, color=DIM)
        frac = min(hr_gap / 10.0, 1.0)
        tf = np.linspace(np.pi, np.pi - frac * np.pi, 90)
        ax1.fill_between(np.cos(tf), np.sin(tf) * 0.55, np.sin(tf), color=hr_col, alpha=0.85)
        ax1.text(0, 0.18, f'{hr_gap:.2f} %', fontsize=16, ha='center', va='center',
                 color=hr_col, fontweight='bold', fontfamily='monospace')
        ax1.text(0, -0.08, 'Fouling / Clean HR', fontsize=7, ha='center', color=MUTED)
        ax1.set_xlim(-1.25, 1.25); ax1.set_ylim(-0.2, 1.1); ax1.axis('off')
        ax1.set_title('Compressor Fouling', color=INK, fontsize=10)

        # ROI breakeven curve (top-right)
        ax2 = fig.add_subplot(gs[0, 1])
        dark_style(ax2)
        horizon = max(60.0, breakeven * 1.8 if breakeven < 500 else 90.0)
        days = np.linspace(0, horizon, 300)
        ax2.plot(days, days * daily_save, color=GREEN, lw=2.0, label='Cumulative saving')
        ax2.axhline(wash_cost, color=RED, lw=1.5, ls='--',
                    label=f'Wash cost ${wash_cost:.0f}')
        if breakeven < 500:
            ax2.axvline(breakeven, color=AMBER, lw=1.5, ls=':',
                        label=f'Breakeven {breakeven:.1f} d')
        ax2.set_xlabel('Days since wash', fontsize=9)
        ax2.set_ylabel('USD', fontsize=9)
        ax2.set_title('Wash ROI Breakeven', color=INK, fontsize=10)
        ax2.legend(fontsize=7, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK)

        # Fuel penalty KPI (bottom-left)
        ax3 = fig.add_subplot(gs[1, 0]); dark_style(ax3); ax3.axis('off')
        ax3.text(0.5, 0.74, 'Daily Fuel Penalty', fontsize=9, color=MUTED,
                 ha='center', transform=ax3.transAxes)
        ax3.text(0.5, 0.44, f'${daily_save:.0f} / day', fontsize=18, color=hr_col,
                 ha='center', va='center', fontweight='bold', fontfamily='monospace',
                 transform=ax3.transAxes)
        ax3.text(0.5, 0.16, f"HR {g('gt_heat_rate_kJ_kWh'):.0f}  vs  clean 9200 kJ/kWh",
                 fontsize=7, color=DIM, ha='center', transform=ax3.transAxes)

        # Recommendation (bottom-right)
        ax4 = fig.add_subplot(gs[1, 1]); dark_style(ax4); ax4.axis('off')
        if hr_gap > 5:
            rec, rec_col = 'WASH RECOMMENDED', RED
        elif hr_gap > 2:
            rec, rec_col = 'MONITOR CLOSELY', AMBER
        else:
            rec, rec_col = 'NOMINAL — OK', GREEN
        ax4.text(0.5, 0.68, rec, fontsize=11, color=rec_col, ha='center',
                 fontweight='bold', fontfamily='monospace', transform=ax4.transAxes)
        if breakeven < 500:
            ax4.text(0.5, 0.40, f'Breakeven in {breakeven:.1f} days', fontsize=9,
                     color=MUTED, ha='center', transform=ax4.transAxes)
        ax4.set_title('Wash Decision', color=INK, fontsize=10)

        fig.suptitle('Compressor Washing ROI Analysis', color=INK, fontsize=13, y=0.95)
        pdf.savefig(fig, bbox_inches='tight'); plt.close(fig)

        # ══════════════════════════════════════════════════════════════════════
        # PAGE 7 — Frequency history + GT cost/CO₂ Pareto
        # ══════════════════════════════════════════════════════════════════════
        fig = new_fig()
        gs = GridSpec(2, 2, figure=fig, hspace=0.42, wspace=0.30,
                      left=0.09, right=0.96, top=0.88, bottom=0.09)

        ax1 = fig.add_subplot(gs[0, :])
        dark_style(ax1)
        if hist and 'freq_Hz' in hist:
            sidx = hist.get('sample_idx', np.arange(1, len(hist['freq_Hz']) + 1))
            freq_h  = hist['freq_Hz']
            demand_h = hist.get('demand_MW', np.zeros_like(freq_h))
            ax1.plot(sidx, freq_h, color=GREEN, lw=0.8, alpha=0.9, label='Frequency')
            for lv, col in [(50.2, AMBER), (49.8, AMBER), (49.5, RED), (50.5, RED)]:
                ax1.axhline(lv, color=col, lw=0.6, ls=':', alpha=0.5)
            ax1.axhline(50.0, color=MUTED, lw=0.6, ls='--', alpha=0.4)
            ax1b = ax1.twinx()
            ax1b.plot(sidx, demand_h, color=CYAN, lw=0.7, alpha=0.5)
            ax1b.set_ylabel('Demand (MW)', color=CYAN, fontsize=8)
            ax1b.tick_params(colors=CYAN, labelsize=7)
            ax1.set_xlabel('Sample (250 ms ticks)', fontsize=9)
            ax1.set_ylabel('Frequency (Hz)', fontsize=9)
            ax1.set_title('Frequency History — last 60 s  (240 samples × 250 ms)',
                          color=INK, fontsize=11)
            ax1.legend(fontsize=7, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK)

        # GT cost vs CO₂ Pareto (bottom-left)
        ax2 = fig.add_subplot(gs[1, 0])
        dark_style(ax2)
        if gto and 'power_MW' in gto:
            pwr_g  = gto['power_MW']
            hr_g   = gto.get('heat_rate_kJ_kWh', np.full_like(pwr_g, 9200.0))
            margin_g = gto.get('margin_usd_h',   np.zeros_like(pwr_g))
            fp  = g('fuel_price_usd_gj', 8.0)
            # CO₂: natural gas ~55.5 tCO₂/TJ → kg/MWh = 55500/1000 * hr_kJ_kWh / 3600
            co2_rate = pwr_g * hr_g * 55.5 / (50000.0 * 1000.0) * 3600.0
            fuel_cost = pwr_g * hr_g * fp / 1000.0
            sc = ax2.scatter(co2_rate, fuel_cost, c=pwr_g, cmap='viridis',
                             s=45, edgecolors=BORDER, lw=0.4, zorder=4)
            plt.colorbar(sc, ax=ax2, label='Power (MW)',
                         fraction=0.04, pad=0.02).ax.tick_params(colors=MUTED, labelsize=6)
            if len(margin_g) > 0:
                bi = int(np.argmax(margin_g))
                ax2.scatter(co2_rate[bi], fuel_cost[bi], color=GREEN, s=120,
                            marker='*', zorder=10, label='P2 optimum')
            ax2.set_xlabel('CO₂ rate (t/h)', fontsize=9)
            ax2.set_ylabel('Fuel cost ($/h)', fontsize=9)
            ax2.set_title('GT Cost vs CO₂ Pareto', color=INK, fontsize=10)
            ax2.legend(fontsize=7, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK)

        # Efficiency curve (bottom-right)
        ax3 = fig.add_subplot(gs[1, 1])
        dark_style(ax3)
        if gto and 'power_MW' in gto:
            eta = 3600.0 / hr_g * 100.0  # thermal efficiency %
            ax3.plot(pwr_g, eta, color=LIME, lw=2, marker='o', ms=4, label='η thermal %')
            ax3.set_xlabel('Power output (MW)', fontsize=9)
            ax3.set_ylabel('Thermal efficiency (%)', fontsize=9)
            ax3.set_title('GT Efficiency vs Load', color=INK, fontsize=10)
            ax3.legend(fontsize=7, facecolor=PANEL, edgecolor=BORDER, labelcolor=INK)

        fig.suptitle('System History & GT Pareto Fronts', color=INK, fontsize=13, y=0.95)
        pdf.savefig(fig, bbox_inches='tight'); plt.close(fig)

        # ══════════════════════════════════════════════════════════════════════
        # PAGE 8 — Operations Gantt + shift summary table
        # ══════════════════════════════════════════════════════════════════════
        fig = new_fig()
        gs = GridSpec(3, 1, figure=fig, hspace=0.38,
                      left=0.14, right=0.96, top=0.90, bottom=0.06)

        # Alarm timeline Gantt
        ax1 = fig.add_subplot(gs[0])
        dark_style(ax1)
        elapsed = g('elapsed_s', 3600.0)
        ax1.set_xlim(0, elapsed); ax1.set_xlabel('Elapsed (s)', fontsize=9)
        ax1.set_title('Active Alarm Summary', color=INK, fontsize=11)
        if alarms:
            ax1.set_ylim(-0.5, len(alarms) - 0.5)
            ax1.set_yticks(range(len(alarms)))
            ax1.set_yticklabels([f'[{s}] {d}' for s, d in alarms],
                                color=INK, fontsize=7, fontfamily='monospace')
            for j, (sev, desc) in enumerate(alarms):
                col = RED if 'CRITICAL' in sev else (AMBER if 'HIGH' in sev else CYAN)
                ax1.barh(j, elapsed, height=0.55, color=col, alpha=0.45)
        else:
            ax1.set_ylim(0, 1)
            ax1.text(0.5, 0.5, 'No active alarms — system healthy',
                     ha='center', va='center', color=GREEN, fontsize=11,
                     fontfamily='monospace', transform=ax1.transAxes)

        # Day-ahead commitment + BESS Gantt
        ax2 = fig.add_subplot(gs[1])
        dark_style(ax2)
        if da and 'hour' in da:
            ax2.set_xlim(0, 24); ax2.set_ylim(-0.5, 1.5)
            ax2.set_yticks([0, 1]); ax2.set_yticklabels(['BESS', 'GT'], color=INK, fontsize=9)
            ax2.set_xlabel('Hour', fontsize=9)
            ax2.set_title('Day-Ahead Commitment Gantt', color=INK, fontsize=11)
            for t in range(len(hours)):
                if commit[t]:
                    ax2.barh(1, 1, height=0.45, left=hours[t] - 1,
                             color=GREEN, alpha=0.85, edgecolor=BORDER, lw=0.3)
                bess_v = p_bess[t] if 'p_bess' in dir() else 0.0
                if hasattr(p_bess, '__len__') and t < len(p_bess):
                    bess_v = p_bess[t]
                if bess_v > 0.5:
                    ax2.barh(0, 1, height=0.45, left=hours[t] - 1,
                             color=GREEN, alpha=0.8, edgecolor=BORDER, lw=0.3)
                elif bess_v < -0.5:
                    ax2.barh(0, 1, height=0.45, left=hours[t] - 1,
                             color=BLUE, alpha=0.7, edgecolor=BORDER, lw=0.3)

        # Summary stats table
        ax3 = fig.add_subplot(gs[2]); dark_style(ax3); ax3.axis('off')
        gt_hrs = int(np.sum(commit)) if da and 'commit' in da else 0
        stats = [
            ['GT Committed Hours',     f'{gt_hrs} / 24 h'],
            ['DA Revenue',             f"${g('da_revenue_usd'):.0f}"],
            ['DA GT Cost',             f"${g('da_cost_usd'):.0f}"],
            ['Net Margin',             f"${g('da_revenue_usd') - g('da_cost_usd'):+.0f}"],
            ['LP Duality Gap',         f"{g('da_gap_pct'):.1f} %"],
            ['Re-dispatch Saving',     f"${g('da_redispatch_saving_usd'):.0f}"],
            ['GT Dispatch',            f"{g('gas_dispatch_pct'):.0f} % ({g('gas_power_MW'):.1f} MW)"],
            ['GT Heat Rate',           f"{g('gt_heat_rate_kJ_kWh'):.0f} kJ/kWh"],
            ['Compressor Fouling',     f"{g('wash_hr_gap_pct'):.2f} %"],
            ['Wash Breakeven',         f"{g('wash_breakeven_days'):.1f} days"],
            ['BESS SoC',               f"{g('battery_soc_pct'):.1f} %"],
            ['P2 Best Margin',         f"${g('gt_opt_best_margin'):.0f}/h"],
        ]
        col_widths = [0.52, 0.44]
        tbl = ax3.table(cellText=stats, colLabels=['Metric', 'Value'],
                        cellLoc='left', loc='center',
                        colWidths=col_widths,
                        cellColours=[[PANEL_ALT, PANEL_ALT]] * len(stats),
                        colColours=[DIM, DIM])
        tbl.auto_set_font_size(False); tbl.set_fontsize(9)
        for (row, col), cell in tbl.get_celld().items():
            cell.set_edgecolor(BORDER)
            if row == 0:
                cell.set_text_props(color=MUTED, fontweight='bold')
            else:
                cell.set_text_props(color=INK if col == 0 else GREEN)
        ax3.set_title('Shift Summary Statistics', color=INK, fontsize=11)

        fig.suptitle('Operations Gantt & Shift Summary', color=INK, fontsize=13, y=0.96)
        pdf.savefig(fig, bbox_inches='tight'); plt.close(fig)

    print(f'Report saved: {pdf_path}')


if __name__ == '__main__':
    main()
