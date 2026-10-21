import { describe, expect, it } from 'vitest';
import { addDays, bucketOf, fmtDate, fmtMoney, fmtPct, initials, parseMoney, passwordOk, todayMuscat } from './format';
import { csvCell, toCsv } from './csv';
import { omanisNeeded, project, ratio } from './omanisation';
import { diffRows } from './diff';
import { parseError } from './errors';
import { en } from '../i18n/en';
import { ar } from '../i18n/ar';

describe('format', () => {
  it('shows dates as dd/MM/yyyy', () => {
    expect(fmtDate('2026-10-20')).toBe('20/10/2026');
    expect(fmtDate('2026-10-20T08:00:00Z')).toBe('20/10/2026');
    expect(fmtDate(null)).toBe('—');
  });
  it('uses the Muscat calendar day, not UTC', () => {
    // 22:30 UTC on 19 Oct is 02:30 on 20 Oct in Muscat (UTC+4)
    expect(todayMuscat(new Date('2026-10-19T22:30:00Z'))).toBe('2026-10-20');
    expect(todayMuscat(new Date('2026-10-19T19:59:00Z'))).toBe('2026-10-19');
  });
  it('adds days across month and year ends', () => {
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01');
    expect(addDays('2028-03-01', -1)).toBe('2028-02-29');
  });
  it('formats OMR with 3 decimals', () => {
    expect(fmtMoney(425.5)).toBe('425.500');
    expect(fmtMoney('1250.25')).toBe('1,250.250');
    expect(fmtMoney(null)).toBe('—');
  });
  it('parses money strictly', () => {
    expect(parseMoney('350')).toBe(350);
    expect(parseMoney('1,250.250')).toBe(1250.25);
    expect(parseMoney('12.3456')).toBeNull();
    expect(parseMoney('-5')).toBeNull();
    expect(parseMoney('abc')).toBeNull();
    expect(parseMoney('')).toBeNull();
  });
  it('buckets expiry days like the server', () => {
    expect(bucketOf(-1)).toBe('EXPIRED');
    expect(bucketOf(0)).toBe('D30');
    expect(bucketOf(30)).toBe('D30');
    expect(bucketOf(31)).toBe('D60');
    expect(bucketOf(60)).toBe('D60');
    expect(bucketOf(90)).toBe('D90');
    expect(bucketOf(91)).toBe('LATER');
    expect(bucketOf(null)).toBeNull();
  });
  it('percent and initials', () => {
    expect(fmtPct(50)).toBe('50%');
    expect(fmtPct(33.333)).toBe('33.3%');
    expect(initials('Salim Al Harthy')).toBe('SH');
    expect(initials('')).toBe('?');
  });
});

describe('csv', () => {
  it('neutralises formulas but keeps negative numbers', () => {
    expect(csvCell('=SUM(A1)')).toBe("'=SUM(A1)");
    expect(csvCell('+968 9123')).toBe("'+968 9123");
    expect(csvCell('-5')).toBe('-5');
    expect(csvCell('@cmd')).toBe("'@cmd");
  });
  it('quotes commas, quotes and new lines', () => {
    expect(csvCell('a,b')).toBe('"a,b"');
    expect(csvCell('say "hi"')).toBe('"say ""hi"""');
    expect(toCsv(['x', 'y'], [[1, null], ['سالم', 'a\nb']])).toBe('x,y\r\n1,\r\nسالم,"a\nb"');
  });
});

describe('omanisation', () => {
  it('ratio and Omanis needed (matches the database test: 2 of 4 at 60% → 1 more)', () => {
    expect(ratio(2, 4)).toBe(50);
    expect(ratio(0, 0)).toBeNull();
    expect(omanisNeeded(2, 4, 60)).toBe(1);
    expect(omanisNeeded(3, 5, 60)).toBe(0); // exactly 60% — no rounding drift
    expect(omanisNeeded(5, 5, 60)).toBe(0);
    expect(omanisNeeded(1, 4, null)).toBeNull();
  });
  it('projects hires, departures and replacements', () => {
    const p = project({ total: 4, omani: 2 }, { hireOmani: 1, hireExpat: 0, leaveOmani: 0, leaveExpat: 0, replaceExpat: 1 }, 60);
    expect(p).toEqual({ total: 5, omani: 4, pct: 80, needed: 0, meets: true });
  });
  it('never removes more people than exist', () => {
    const p = project({ total: 3, omani: 1 }, { hireOmani: 0, hireExpat: 0, leaveOmani: 9, leaveExpat: 9, replaceExpat: 9 }, 50);
    expect(p.total).toBe(0);
    expect(p.pct).toBeNull();
  });
  it('ignores negative and fractional inputs', () => {
    const p = project({ total: 10, omani: 3 }, { hireOmani: -4, hireExpat: 2.7, leaveOmani: 0, leaveExpat: 0, replaceExpat: 0 }, 35);
    expect(p).toEqual({ total: 12, omani: 3, pct: 25, needed: 2, meets: false });
  });
});

describe('diff', () => {
  it('lists changed fields only, ignoring bookkeeping columns', () => {
    const d = diffRows({ id: '1', mobile: '1', city: 'Sohar', updated_at: 'x' }, { id: '1', mobile: '2', city: 'Sohar', updated_at: 'y', wilayat: 'Liwa' });
    expect(d).toEqual([{ key: 'mobile', from: '1', to: '2' }, { key: 'wilayat', from: null, to: 'Liwa' }]);
  });
});

describe('errors', () => {
  it('splits server codes from messages', () => {
    const e = parseError({ message: 'SELF_APPROVAL: You proposed this revision; someone else must approve it.' });
    expect(e.code).toBe('SELF_APPROVAL');
    expect(e.detail).toMatch(/someone else/);
  });
  it('recognises network and permission errors', () => {
    expect(parseError(new Error('Failed to fetch')).code).toBe('NETWORK');
    expect(parseError({ message: 'permission denied for table employees' }).code).toBe('NOT_ALLOWED');
    expect(parseError('weird').code).toBe('UNKNOWN');
  });
});

describe('translations', () => {
  const vars = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(',');
  it('Arabic has every English key with the same placeholders', () => {
    for (const k of Object.keys(en) as (keyof typeof en)[]) {
      expect(ar[k], k).toBeTruthy();
      expect(vars(ar[k]), k).toBe(vars(en[k]));
    }
    expect(Object.keys(ar).length).toBe(Object.keys(en).length);
  });
  it('every server error code used in the database has a message', () => {
    const codes = ['NOT_SIGNED_IN', 'NOT_ALLOWED', 'NOT_FOUND', 'REQUIRED', 'INVALID', 'INVALID_DATE', 'INVALID_EMAIL', 'INVALID_PHONE',
      'INVALID_AMOUNT', 'INVALID_NUMBER', 'INVALID_ID', 'DUPLICATE', 'DUPLICATE_DOCUMENT', 'POSSIBLE_DUPLICATE', 'OMANI_ONLY',
      'SELF_APPROVAL', 'PENDING_EXISTS', 'OVERLAP', 'ADMIN_EXISTS'];
    for (const c of codes) expect(`err.${c}` in en, c).toBe(true);
  });
});

describe('passwordOk (matches Supabase Auth policy)', () => {
  it('needs 10+ characters with upper, lower and a digit', () => {
    expect(passwordOk('Demo@AACT2026')).toBe(true);
    expect(passwordOk('Abcdefgh12')).toBe(true);
    expect(passwordOk('Abcdefg12')).toBe(false);   // 9 characters
    expect(passwordOk('abcdefgh12')).toBe(false);  // no upper case
    expect(passwordOk('ABCDEFGH12')).toBe(false);  // no lower case
    expect(passwordOk('Abcdefghij')).toBe(false);  // no digit
  });
});
