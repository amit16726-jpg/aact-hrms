/** Pure Omanisation arithmetic (shared by the scenario planner and its tests). */
export interface Scenario { hireOmani: number; hireExpat: number; leaveOmani: number; leaveExpat: number; replaceExpat: number }

export interface Projection { total: number; omani: number; pct: number | null; needed: number | null; meets: boolean | null }

const clampInt = (n: number) => (Number.isFinite(n) && n > 0 ? Math.floor(n) : 0);

export function ratio(omani: number, total: number): number | null {
  return total > 0 ? Math.round((10000 * omani) / total) / 100 : null;
}

/** Omanis still needed to reach the target with the headcount unchanged: ceil(target% × total) − omani, never below 0. */
export function omanisNeeded(omani: number, total: number, targetPct: number | null | undefined): number | null {
  if (targetPct === null || targetPct === undefined || total <= 0) return null;
  // small epsilon so 60% of 5 = 3 exactly, not 3.0000000004 → 4
  return Math.max(0, Math.ceil((targetPct * total) / 100 - 1e-9) - omani);
}

export function project(current: { total: number; omani: number }, s: Scenario, targetPct: number | null | undefined): Projection {
  const leaveOmani = Math.min(clampInt(s.leaveOmani), current.omani);
  const expatNow = current.total - current.omani;
  const leaveExpat = Math.min(clampInt(s.leaveExpat), expatNow);
  const replace = Math.min(clampInt(s.replaceExpat), expatNow - leaveExpat);
  const omani = current.omani - leaveOmani + clampInt(s.hireOmani) + replace;
  const expat = expatNow - leaveExpat - replace + clampInt(s.hireExpat);
  const total = omani + expat;
  const pct = ratio(omani, total);
  const needed = omanisNeeded(omani, total, targetPct);
  return { total, omani, pct, needed, meets: pct === null || targetPct === null || targetPct === undefined ? null : pct >= targetPct };
}
