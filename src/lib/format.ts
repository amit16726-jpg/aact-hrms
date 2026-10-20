/** Display helpers. Dates are shown dd/MM/yyyy; money in OMR with 3 decimals; digits stay Western in both languages. */

export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return iso;
  return `${m[3]}/${m[2]}/${m[1]}`;
}

export function fmtDateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Muscat', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false,
  }).formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  return `${get('day')}/${get('month')}/${get('year')} ${get('hour')}:${get('minute')}`;
}

/** Today's date in Muscat as YYYY-MM-DD (built from parts, not a locale string). */
export function todayMuscat(now: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Muscat', year: 'numeric', month: '2-digit', day: '2-digit' })
    .formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

export function addDays(iso: string, days: number): string {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return dt.toISOString().slice(0, 10);
}

export function fmtMoney(v: number | string | null | undefined, decimals = 3): string {
  if (v === null || v === undefined || v === '') return '—';
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n)) return '—';
  return n.toLocaleString('en-US', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
}

export function fmtPct(v: number | string | null | undefined): string {
  if (v === null || v === undefined || v === '') return '—';
  const n = Number(v);
  return Number.isFinite(n) ? `${n.toFixed(n % 1 === 0 ? 0 : 1)}%` : '—';
}

/** Accepts "350", "350.5", "1,250.250" → number with ≤ 3 decimals, or null when invalid. */
export function parseMoney(s: string): number | null {
  const t = s.replace(/,/g, '').trim();
  if (t === '') return null;
  if (!/^\d{1,9}(\.\d{1,3})?$/.test(t)) return null;
  return Number(t);
}

export type Bucket = 'EXPIRED' | 'D30' | 'D60' | 'D90' | 'LATER';

export function bucketOf(daysLeft: number | null | undefined): Bucket | null {
  if (daysLeft === null || daysLeft === undefined) return null;
  if (daysLeft < 0) return 'EXPIRED';
  if (daysLeft <= 30) return 'D30';
  if (daysLeft <= 60) return 'D60';
  if (daysLeft <= 90) return 'D90';
  return 'LATER';
}

export function initials(name: string | null | undefined): string {
  if (!name) return '?';
  const parts = name.trim().split(/\s+/).filter(Boolean);
  const first = parts[0]?.[0] ?? '';
  const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
  return (first + last).toUpperCase();
}
