/** Field-level differences between two audit snapshots, ignoring bookkeeping columns. */
const IGNORE = new Set(['updated_at', 'created_at', 'id']);

export interface Change { key: string; from: unknown; to: unknown }

const same = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

export function diffRows(oldRow: Record<string, unknown> | null, newRow: Record<string, unknown> | null): Change[] {
  const keys = new Set([...Object.keys(oldRow ?? {}), ...Object.keys(newRow ?? {})]);
  const out: Change[] = [];
  for (const k of keys) {
    if (IGNORE.has(k)) continue;
    const a = oldRow?.[k];
    const b = newRow?.[k];
    if (!same(a, b)) out.push({ key: k, from: a ?? null, to: b ?? null });
  }
  return out.sort((x, y) => x.key.localeCompare(y.key));
}

export function show(v: unknown): string {
  if (v === null || v === undefined || v === '') return '—';
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}
