import { describe, expect, it } from 'vitest';
import { collectAnswers, pct, type Question } from './api_eng';

const qs: Question[] = [
  { key: 'q1', kind: 'RATING', text_en: 'How happy are you?', text_ar: null, required: true, options: [] },
  { key: 'q2', kind: 'CHOICE', text_en: 'Best time?', text_ar: null, required: true, options: [{ en: '12:00', ar: null }, { en: '13:00', ar: null }] },
  { key: 'q3', kind: 'TEXT', text_en: 'Comments?', text_ar: null, required: false, options: [] },
];

describe('collectAnswers', () => {
  it('reports the first required question left empty', () => {
    expect(collectAnswers(qs, { q2: 1 }).missing).toBe('q1');
    expect(collectAnswers(qs, { q1: 4 }).missing).toBe('q2');
  });
  it('keeps choice 0 (the first option) as an answer', () => {
    const r = collectAnswers(qs, { q1: 5, q2: 0 });
    expect(r.missing).toBeNull();
    expect(r.answers).toEqual({ q1: 5, q2: 0 });
  });
  it('trims text and drops empty optional answers', () => {
    expect(collectAnswers(qs, { q1: 3, q2: 1, q3: '   ' }).answers).toEqual({ q1: 3, q2: 1 });
    expect(collectAnswers(qs, { q1: 3, q2: 1, q3: '  More fruit  ' }).answers.q3).toBe('More fruit');
  });
  it('treats a blank required text answer as missing', () => {
    const req: Question[] = [{ key: 'q1', kind: 'TEXT', text_en: 'Why?', text_ar: null, required: true, options: [] }];
    expect(collectAnswers(req, { q1: ' ' }).missing).toBe('q1');
  });
  it('falls back to positional keys', () => {
    const noKey = qs.map(({ key: _k, ...q }) => q as Question);
    expect(collectAnswers(noKey, { q1: 2, q2: 1 }).missing).toBeNull();
  });
});

describe('pct', () => {
  it('is a whole percent and safe for zero', () => {
    expect(pct(1, 3)).toBe(33);
    expect(pct(2, 3)).toBe(67);
    expect(pct(0, 0)).toBe(0);
  });
});
