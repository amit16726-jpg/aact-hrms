import { describe, expect, it } from 'vitest';
import { buildWpsSif, type WpsData } from './api_pay';

const data: WpsData = {
  employer_cr: '1234567', payer_cr: '1234567', bank_code: 'BMCT', account: '0301000000001', year: 2026, month: 9, pay_date: '2026-09-28',
  rows: [
    { employee_no: 'AACT-00001', id_type: 'C', id: '90000001', name: 'Salim Al Harthy', bank: 'BMUSOMRX', account: 'OM000000000000000111', days: 30,
      net: 2392.49, basic: 2594, extra_hours: 3.06, extra_income: 831.073, deductions: 0, social_security: 241.96, has_bank: true },
    { employee_no: 'AACT-00002', id_type: 'P', id: 'AACT-00002', name: 'Smith, "Joe"', bank: 'BDOFOMRU', account: '0301000000222', days: 27.5,
      net: 100.1, basic: 300, extra_hours: 0, extra_income: 150, deductions: 45, social_security: 0, has_bank: true },
    { employee_no: 'AACT-00003', id_type: 'C', id: '90000003', name: 'No Bank', bank: null, account: null, days: 30,
      net: 500, basic: 500, extra_hours: 0, extra_income: 0, deductions: 0, social_security: 0, has_bank: false },
  ],
};

describe('WPS salary information file', () => {
  const f = buildWpsSif(data);
  const lines = f.text.trim().split('\r\n');
  it('names the file after the employer CR, bank and pay date', () => {
    expect(f.name).toBe('SIF_1234567_BMCT_20260928_001.csv');
  });
  it('writes the employer record with totals of the rows that can be paid', () => {
    expect(lines[1]).toBe('1234567,1234567,BMCT,0301000000001,2026,09,2492.590,2,Salary');
  });
  it('leaves out employees without a bank account and reports them', () => {
    expect(lines.length).toBe(5);
    expect(f.skipped).toEqual(['AACT-00003']);
  });
  it('formats money with 3 decimals and quotes text with commas or quotes', () => {
    expect(lines[3]).toContain(',2392.490,2594.000,');
    expect(lines[4]).toContain('"Smith, ""Joe"""');
    expect(lines[4].split(',')[0]).toBe('P');
  });
  it('rounds working days to whole days', () => {
    expect(lines[4]).toContain(',M,28,');
  });
});
