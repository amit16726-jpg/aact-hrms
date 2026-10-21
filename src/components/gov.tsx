import { useState } from 'react';
import { useI18n } from '../i18n';
import { Badge } from './ui';
import type { DsrStatus, Risk } from '../lib/api_gov';

export function DsrBadge({ s }: { s: DsrStatus }) {
  const { t } = useI18n();
  return <Badge tone={s === 'COMPLETED' ? 'ok' : s === 'REJECTED' ? undefined : s === 'IN_PROGRESS' ? 'info' : 'warn'}>{t(`ds.${s}`)}</Badge>;
}

export function RiskBadge({ r }: { r: Risk }) {
  const { t } = useI18n();
  return <Badge tone={r === 'HIGH' ? 'bad' : r === 'MEDIUM' ? 'warn' : undefined}>{t(`br.r_${r}`)}</Badge>;
}

const fmt = (v: number) => (Math.abs(v) >= 1000 ? `${(v / 1000).toFixed(v >= 10000 ? 0 : 1)}k` : String(Math.round(v * 10) / 10));
const monthLabel = (m: string, lang: 'en' | 'ar') =>
  new Date(`${m}-01T00:00:00Z`).toLocaleDateString(lang === 'ar' ? 'ar-OM' : 'en-GB', { month: 'short', timeZone: 'UTC' });

/**
 * Single-series monthly chart (bars for amounts/counts, a line for a rate). One series → no legend; the panel title names it.
 * Hover/focus shows the exact value; the same numbers are available in the table below the chart.
 */
export function MonthChart({ data, kind = 'bar', unit = '', label, max }: {
  data: { month: string; value: number | null }[]; kind?: 'bar' | 'line'; unit?: string; label: string; max?: number;
}) {
  const { lang } = useI18n();
  const [hover, setHover] = useState<number | null>(null);
  const W = 600; const H = 200; const padL = 36; const padB = 22; const padT = 12; const padR = 8;
  const vals = data.map((d) => d.value ?? 0);
  const top = max ?? Math.max(1, ...vals) * 1.1;
  const iw = W - padL - padR; const ih = H - padT - padB;
  const bw = iw / Math.max(data.length, 1);
  const y = (v: number) => padT + ih - (v / top) * ih;
  const ticks = [0, top / 2, top];
  const pts = data.map((d, i) => (d.value == null ? null : [padL + bw * i + bw / 2, y(d.value)] as const));
  const path = pts.reduce((acc, p, i) => (p ? `${acc}${acc && pts[i - 1] ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}` : acc), '');
  const h = hover != null ? data[hover] : null;
  return (
    <figure className="mchart" aria-label={label}>
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label} preserveAspectRatio="none" onMouseLeave={() => setHover(null)}>
        {ticks.map((tv, i) => (
          <g key={i}>
            <line x1={padL} x2={W - padR} y1={y(tv)} y2={y(tv)} className="mchart-grid" />
            <text x={padL - 6} y={y(tv) + 4} className="mchart-axis" textAnchor="end">{fmt(tv)}</text>
          </g>))}
        {kind === 'bar' && data.map((d, i) => {
          const v = d.value ?? 0; const x = padL + bw * i + bw * 0.18; const w = bw * 0.64; const yy = y(v);
          return <path key={d.month} className={`mchart-bar${hover === i ? ' on' : ''}`}
            d={v > 0 ? `M${x},${padT + ih} V${yy + 4} Q${x},${yy} ${x + 4},${yy} H${x + w - 4} Q${x + w},${yy} ${x + w},${yy + 4} V${padT + ih} Z` : ''} />;
        })}
        {kind === 'line' && <path d={path} className="mchart-line" />}
        {kind === 'line' && pts.map((p, i) => p && <circle key={i} cx={p[0]} cy={p[1]} r={hover === i ? 5 : 3.5} className="mchart-dot" />)}
        {data.map((d, i) => (
          <g key={`h${d.month}`}>
            <rect x={padL + bw * i} y={padT} width={bw} height={ih} fill="transparent" tabIndex={0}
              onMouseEnter={() => setHover(i)} onFocus={() => setHover(i)} onBlur={() => setHover(null)}>
              <title>{`${monthLabel(d.month, lang)} ${d.month.slice(0, 4)}: ${d.value == null ? '—' : d.value.toLocaleString()}${unit}`}</title>
            </rect>
            {(i % 2 === 0 || data.length <= 6) && <text x={padL + bw * i + bw / 2} y={H - 6} className="mchart-axis" textAnchor="middle">{monthLabel(d.month, lang)}</text>}
          </g>))}
      </svg>
      <figcaption className="mchart-tip" aria-live="polite">{h ? <><span className="muted">{monthLabel(h.month, lang)} {h.month.slice(0, 4)}</span> <b className="num">{h.value == null ? '—' : h.value.toLocaleString()}{unit}</b></> : ' '}</figcaption>
    </figure>
  );
}

/** Horizontal bars for a breakdown (departments, nationalities); value labels in ink, not the bar colour. */
export function BreakdownBars({ rows, label }: { rows: { name: string; value: number; sub?: string }[]; label: string }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  return (
    <ul className="hbars" aria-label={label}>
      {rows.map((r) => (
        <li key={r.name}>
          <span className="hbars-name">{r.name}{r.sub && <span className="sub">{r.sub}</span>}</span>
          <span className="hbars-track"><span className="hbars-fill" style={{ width: `${(r.value / max) * 100}%` }} /></span>
          <b className="num">{r.value}</b>
        </li>))}
    </ul>
  );
}
