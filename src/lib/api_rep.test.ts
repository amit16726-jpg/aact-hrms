import { describe, expect, it } from 'vitest';
import { cellText, codeLabel, ddmmyyyy, reportFileName, reportTotals, resolvePeriod, type ReportColumn } from './api_rep';

const cols: ReportColumn[] = [
  { k: 'name', en: 'Name', ar: 'الاسم', t: 'text' }, { k: 'n', en: 'N', ar: 'ع', t: 'int', s: 1 },
  { k: 'pay', en: 'Pay', ar: 'الراتب', t: 'money', s: 1 }, { k: 'pct', en: '%', ar: '%', t: 'pct' },
];

describe('report helpers', () => {
  it('formats cells by type', () => {
    expect(cellText(1234.5, 'money', 'en')).toBe('1,234.500');
    expect(cellText(12.345, 'num', 'en')).toBe('12.35');
    expect(cellText(7.6, 'int', 'en')).toBe('8');
    expect(cellText(33.3, 'pct', 'en')).toBe('33.3%');
    expect(cellText('2026-09-30', 'date', 'en')).toBe('30/09/2026');
    expect(cellText(null, 'money', 'en')).toBe('—');
    expect(cellText('APPROVED', 'text', 'ar')).toBe('معتمد');
    expect(cellText('Salim Al Harthy', 'text', 'en')).toBe('Salim Al Harthy');
  });
  it('turns unknown codes into words and keeps normal text', () => {
    expect(codeLabel('END_OF_CONTRACT', 'en')).toBe('End of contract');
    expect(codeLabel('BODY_PREP_X', 'en')).toBe('Body prep x');
    expect(codeLabel('PLANT1', 'en')).toBe('Plant1');
    expect(codeLabel('Packing', 'en')).toBe('Packing');
    expect(ddmmyyyy('bad')).toBe('bad');
  });
  it('totals only summed columns, money to the baisa', () => {
    const t = reportTotals(cols, [{ name: 'a', n: 2, pay: 100.1235, pct: 10 }, { name: 'b', n: 3, pay: 0.0005, pct: 20 }, { name: 'c', n: null, pay: null, pct: null }]);
    expect(t).toEqual({ n: 5, pay: 100.124 });
    expect(reportTotals(cols, [])).toBeNull();
    expect(reportTotals([cols[0]], [{ name: 'x' }])).toBeNull();
  });
  it('resolves relative periods of scheduled reports', () => {
    const d = new Date(2026, 9, 22); // 22 Oct 2026
    expect(resolvePeriod({ period: 'PREV_MONTH', entity_id: 'e' }, d)).toEqual({ entity_id: 'e', from: '2026-09-01', to: '2026-09-30', month: '2026-09', as_of: '2026-09-30' });
    expect(resolvePeriod({ period: 'THIS_MONTH' }, d)).toEqual({ from: '2026-10-01', to: '2026-10-22', month: '2026-10' });
    expect(resolvePeriod({ period: 'YTD' }, d)).toEqual({ from: '2026-01-01', to: '2026-10-22', month: '2026-01' });
    expect(resolvePeriod({ days: 30 }, d)).toEqual({ days: 30 });
    expect(resolvePeriod({ period: 'PREV_MONTH' }, new Date(2026, 0, 5))).toMatchObject({ from: '2025-12-01', to: '2025-12-31' });
  });
  it('builds safe file names', () => {
    const r = { code: 'P01', name_en: 'Payroll register', entity: { id: 'x', code: 'AACT', name_en: 'A', name_ar: null, cr_number: null }, meta: { month: '2026-09' } };
    expect(reportFileName(r, {}, 'xlsx')).toBe('AACT_P01_Payroll-register_2026-09.xlsx');
    expect(reportFileName({ ...r, name_en: 'End-of-service (gratuity) liability', meta: {} }, { as_of: '2026-10-01' }, 'pdf'))
      .toBe('AACT_P01_End-of-service-gratuity-liability_2026-10-01.pdf');
  });
});
