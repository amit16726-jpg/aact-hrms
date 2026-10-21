import { describe, expect, it } from 'vitest';
import { addMonthsIso, daysBetween, deductionAmount, exitProgress, goalsRating, noticeCheck } from './api_wf';

describe('performance rating', () => {
  it('weights the manager ratings and ignores unrated goals', () => {
    expect(goalsRating([{ title: 'Output', weight: 2, rating: 4 }, { title: 'Safety', weight: 1, rating: 5 }])).toBe(4.33);
    expect(goalsRating([{ title: 'A', weight: null, rating: 3 }, { title: 'B', weight: '', rating: 4 }, { title: 'C', weight: 5, rating: null }])).toBe(3.5);
    expect(goalsRating([{ title: 'A', weight: 1, self_rating: 5 }])).toBeNull();
    expect(goalsRating([])).toBeNull();
  });
});

describe('dates', () => {
  it('adds months like Postgres (month end clamped)', () => {
    expect(addMonthsIso('2026-10-21', 6)).toBe('2027-04-21');
    expect(addMonthsIso('2026-08-31', 6)).toBe('2027-02-28');
    expect(addMonthsIso('2027-08-31', 6)).toBe('2028-02-29');
    expect(addMonthsIso('2026-01-15', -2)).toBe('2025-11-15');
  });
  it('counts days between dates', () => {
    expect(daysBetween('2026-10-21', '2026-11-20')).toBe(30);
    expect(daysBetween('2026-12-31', '2027-01-01')).toBe(1);
  });
});

describe('notice rule', () => {
  const base = { type: 'RESIGNATION' as const, given: '2026-10-21', last: '2026-10-31', minDays: 30, payInLieu: false, onProbation: false };
  it('flags short notice for resignation and termination', () => {
    expect(noticeCheck(base)).toEqual({ days: 10, short: true });
    expect(noticeCheck({ ...base, type: 'TERMINATION', last: '2026-11-20' })).toEqual({ days: 30, short: false });
    expect(noticeCheck({ ...base, minDays: 15, last: '2026-11-05' }).short).toBe(false);
  });
  it('does not apply with pay in lieu, on probation or at contract end', () => {
    expect(noticeCheck({ ...base, payInLieu: true }).short).toBe(false);
    expect(noticeCheck({ ...base, onProbation: true }).short).toBe(false);
    expect(noticeCheck({ ...base, type: 'END_OF_CONTRACT' }).short).toBe(false);
  });
});

describe('exit and discipline helpers', () => {
  it('counts closed clearance steps', () => {
    expect(exitProgress([{ status: 'DONE' }, { status: 'NOT_NEEDED' }, { status: 'PENDING' }, { status: 'PENDING' }])).toEqual({ done: 2, total: 4, pct: 50 });
    expect(exitProgress([])).toEqual({ done: 0, total: 0, pct: 0 });
  });
  it('deduction = days × gross ÷ 30 (3 decimals)', () => {
    expect(deductionAmount(425.5, 2)).toBe(28.366);
    expect(deductionAmount(300, 0.5)).toBe(5);
  });
});
