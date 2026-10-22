/** "Lab, Plant 1،  Maint" → ["Lab", "Plant 1", "Maint"] (comma or Arabic comma, duplicates removed). */
export function splitAliases(v: unknown): string[] {
  const list = Array.isArray(v) ? v.map(String) : String(v ?? '').split(/[,،]/);
  const out: string[] = [];
  for (const x of list) { const s = x.trim().replace(/\s+/g, ' '); if (s && !out.some((o) => o.toLowerCase() === s.toLowerCase())) out.push(s); }
  return out;
}
