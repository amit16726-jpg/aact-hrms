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

describe('1.15.0 PDF and translation helpers', () => {
  it('accepts only PDFs up to 10 MB', async () => {
    const { checkPdf } = await import('./api_eng');
    expect(checkPdf({ name: 'circular.pdf', type: 'application/pdf', size: 1000 })).toBeNull();
    expect(checkPdf({ name: 'circular.PDF', type: '', size: 1000 })).toBeNull();
    expect(checkPdf({ name: 'photo.jpg', type: 'image/jpeg', size: 1000 })).toBe('FILE_TYPE');
    expect(checkPdf({ name: 'big.pdf', type: 'application/pdf', size: 10 * 1024 * 1024 + 1 })).toBe('FILE_SIZE');
    expect(checkPdf({ name: 'empty.pdf', type: 'application/pdf', size: 0 })).toBe('FILE_SIZE');
  });
  it('builds storage paths the database accepts', async () => {
    const { annPdfPath } = await import('./api_eng');
    expect(annPdfPath()).toMatch(/^ann\/[0-9a-f-]{36}\.pdf$/);
  });
  it('formats file sizes', async () => {
    const { fileSize } = await import('./api_eng');
    expect(fileSize(null)).toBe('');
    expect(fileSize(300)).toBe('1 KB');
    expect(fileSize(250 * 1024)).toBe('250 KB');
    expect(fileSize(1.5 * 1024 * 1024)).toBe('1.5 MB');
  });
  it('reads edge-function errors', async () => {
    const { functionError } = await import('./api_eng');
    const withBody = (status: number, body: string) => ({ name: 'FunctionsHttpError', context: new Response(body, { status }) });
    const e1 = await functionError(withBody(503, '{"error":"TRANSLATE_OFF: Translation is not set up."}'));
    expect([e1.code, e1.detail]).toEqual(['TRANSLATE_OFF', 'Translation is not set up.']);
    const e2 = await functionError(withBody(400, '{"error":"LIMIT: You have reached today\'s translation limit (100)."}'));
    expect(e2.code).toBe('LIMIT');
    expect((await functionError(withBody(404, 'Not found'))).code).toBe('TRANSLATE_OFF');
    expect((await functionError(withBody(500, 'oops'))).code).toBe('TRANSLATE_FAILED');
    expect((await functionError({ name: 'FunctionsFetchError', message: 'Failed to send a request' })).code).toBe('TRANSLATE_OFF');
  });
});
