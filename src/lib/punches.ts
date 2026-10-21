/** Reading attendance-device export files (CSV / TXT) into punches: [{ref, at 'YYYY-MM-DD HH:MM:SS', dir}]. */

export type Delim = ',' | ';' | '\t' | '|';
export type DateFmt = 'YMD' | 'DMY' | 'MDY';

export function detectDelimiter(text: string): Delim {
  const sample = text.split(/\r?\n/).slice(0, 10).join('\n');
  const counts: [Delim, number][] = ([',', ';', '\t', '|'] as Delim[]).map((d) => [d, sample.split(d).length - 1]);
  counts.sort((a, b) => b[1] - a[1]);
  return counts[0][1] > 0 ? counts[0][0] : ',';
}

/** RFC-4180 style parser: quotes, doubled quotes, CR/LF, a leading BOM. Empty lines are dropped. */
export function parseCsv(text: string, delim?: Delim): string[][] {
  const d = delim ?? detectDelimiter(text);
  const src = text.replace(/^﻿/, '');
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (quoted) {
      if (c === '"') {
        if (src[i + 1] === '"') { cell += '"'; i++; } else quoted = false;
      } else cell += c;
      continue;
    }
    if (c === '"' && cell === '') { quoted = true; continue; }
    if (c === d) { row.push(cell); cell = ''; continue; }
    if (c === '\n' || c === '\r') {
      if (c === '\r' && src[i + 1] === '\n') i++;
      row.push(cell); cell = '';
      if (row.some((x) => x.trim() !== '')) rows.push(row.map((x) => x.trim()));
      row = [];
      continue;
    }
    cell += c;
  }
  row.push(cell);
  if (row.some((x) => x.trim() !== '')) rows.push(row.map((x) => x.trim()));
  return rows;
}

const pad = (n: number) => String(n).padStart(2, '0');

function validYmd(y: number, m: number, d: number): boolean {
  if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1) return false;
  return d <= new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** '20/10/2026', '2026-10-20', '10/20/2026', '20.10.26' → '2026-10-20' (null when not a date). */
export function parseDate(s: string, fmt: DateFmt): string | null {
  const m = /^(\d{1,4})[/.-](\d{1,2})[/.-](\d{1,4})$/.exec(s.trim());
  if (!m) return null;
  let y: number; let mo: number; let d: number;
  const a = Number(m[1]), b = Number(m[2]), c = Number(m[3]);
  if (m[1].length === 4) { y = a; mo = b; d = c; }
  else if (fmt === 'MDY') { mo = a; d = b; y = c; }
  else { d = a; mo = b; y = c; }
  if (y < 100) y += 2000;
  return validYmd(y, mo, d) ? `${y}-${pad(mo)}-${pad(d)}` : null;
}

/** '7:05', '07:05:30', '7:05 PM', '19.05' → 'HH:MM:SS' (null when not a time). */
export function parseTime(s: string): string | null {
  const m = /^(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?\s*([AaPp][Mm])?$/.exec(s.trim());
  if (!m) return null;
  let h = Number(m[1]);
  const mi = Number(m[2]), se = Number(m[3] ?? 0);
  if (m[4]) {
    if (h < 1 || h > 12) return null;
    const pm = m[4].toLowerCase() === 'pm';
    if (h === 12) h = pm ? 12 : 0; else if (pm) h += 12;
  }
  if (h > 23 || mi > 59 || se > 59) return null;
  return `${pad(h)}:${pad(mi)}:${pad(se)}`;
}

/** '20/10/2026 07:05', '2026-10-20T07:05:00', '20/10/2026 7:05 PM' → 'YYYY-MM-DD HH:MM:SS'. */
export function parseDateTime(s: string, fmt: DateFmt): string | null {
  const t = s.trim().replace('T', ' ').replace(/\s+/g, ' ');
  const i = t.indexOf(' ');
  if (i < 0) return null;
  const date = parseDate(t.slice(0, i), fmt);
  const time = parseTime(t.slice(i + 1));
  return date && time ? `${date} ${time}` : null;
}

/** Device direction words and codes. ZKTeco-style exports use 0 = check-in, 1 = check-out. */
export function parseDirection(s: string | undefined): 'IN' | 'OUT' | null {
  const v = (s ?? '').trim().toLowerCase().replace(/[\s_/-]+/g, '');
  if (!v) return null;
  if (['in', 'i', 'checkin', 'cin', 'entry', 'clockin', '0', 'دخول'].includes(v)) return 'IN';
  if (['out', 'o', 'checkout', 'cout', 'exit', 'clockout', '1', 'خروج'].includes(v)) return 'OUT';
  return null;
}

export interface PunchMap {
  ref: number; datetime: number | null; date: number | null; time: number | null; dir: number | null; fmt: DateFmt; header: boolean;
}
export interface PunchRow { line: number; ref: string; at: string; dir: 'IN' | 'OUT' | null }
export interface BadRow { line: number; problem: 'ref' | 'date' | 'time' }

export function buildPunches(rows: string[][], m: PunchMap): { ok: PunchRow[]; bad: BadRow[] } {
  const ok: PunchRow[] = [];
  const bad: BadRow[] = [];
  rows.forEach((r, i) => {
    if (m.header && i === 0) return;
    const line = i + 1;
    const ref = (r[m.ref] ?? '').trim();
    if (!ref) { bad.push({ line, problem: 'ref' }); return; }
    let at: string | null;
    if (m.datetime !== null) {
      at = parseDateTime(r[m.datetime] ?? '', m.fmt);
      if (!at) { bad.push({ line, problem: 'date' }); return; }
    } else {
      const d = parseDate(r[m.date ?? -1] ?? '', m.fmt);
      if (!d) { bad.push({ line, problem: 'date' }); return; }
      const t = parseTime(r[m.time ?? -1] ?? '');
      if (!t) { bad.push({ line, problem: 'time' }); return; }
      at = `${d} ${t}`;
    }
    ok.push({ line, ref, at, dir: m.dir !== null ? parseDirection(r[m.dir]) : null });
  });
  return { ok, bad };
}

/** Best guess of the columns from a header row. */
export function guessMap(header: string[]): Partial<PunchMap> {
  const find = (re: RegExp) => { const i = header.findIndex((h) => re.test(h.toLowerCase())); return i >= 0 ? i : null; };
  const dt = find(/date.?time|datetime|timestamp|checktime|punch.?time/);
  return {
    ref: find(/emp|staff|user|ac.?no|badge|card|id|no\b|number/) ?? 0,
    datetime: dt,
    date: dt === null ? find(/date/) : null,
    time: dt === null ? find(/time/) : null,
    dir: find(/in.?out|state|status|direction|type/),
  };
}
