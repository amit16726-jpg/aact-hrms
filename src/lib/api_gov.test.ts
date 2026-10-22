import { describe, expect, it } from 'vitest';
import { absencePct, csvToRows, hoursText, missingColumns, normDate, spfCsv, turnoverPct, type SpfReport } from './api_gov';

describe('import files', () => {
  it('reads CSV with headings, normalises dates and drops empty cells', () => {
    const { headers, rows } = csvToRows('﻿employee_no,full_name_en,join_date,date_of_birth,mobile\r\nA-1,"Ravi, Kumar",01/03/2021,1990-05-20,\r\n,,,,\r\n');
    expect(headers).toEqual(['employee_no', 'full_name_en', 'join_date', 'date_of_birth', 'mobile']);
    expect(rows).toEqual([{ employee_no: 'A-1', full_name_en: 'Ravi, Kumar', join_date: '2021-03-01', date_of_birth: '1990-05-20' }]);
  });
  it('dates in DD/MM/YYYY become ISO; other text is left alone', () => {
    expect(normDate('5/7/2024')).toBe('2024-07-05');
    expect(normDate('2024-07-05')).toBe('2024-07-05');
    expect(normDate('n/a')).toBe('n/a');
  });
  it('lists required columns that are missing', () => {
    expect(missingColumns('EMPLOYEES', ['full_name_en', 'Nationality', 'join_date'])).toEqual(['department_code', 'job_code', 'category_code']);
    expect(missingColumns('SALARIES', ['employee_no', 'basic'])).toEqual([]);
    expect(missingColumns('EMPLOYEES', ['full_name_en', 'nationality', 'join_date', 'Department', 'designation', 'category'])).toEqual([]);
  });
});

describe('executive figures', () => {
  it('turnover = leavers / average headcount', () => {
    expect(turnoverPct([{ headcount: 100, leavers: 2 }, { headcount: 100, leavers: 3 }])).toBe(5);
    expect(turnoverPct([])).toBeNull();
    expect(turnoverPct([{ headcount: 0, leavers: 0 }])).toBeNull();
  });
  it('absence rate', () => {
    expect(absencePct({ absent_days: 3, worked_days: 200 })).toBe(1.5);
    expect(absencePct({ absent_days: 0, worked_days: 0 })).toBeNull();
  });
  it('breach clock text', () => {
    expect(hoursText(53.4)).toBe('2 d 5 h');
    expect(hoursText(5)).toBe('5 h');
    expect(hoursText(-8.2)).toBe('-8 h');
    expect(hoursText(30, 'ar')).toBe('1 يوم 6 ساعة');
  });
});

describe('SPF schedule', () => {
  it('one column per contribution, totals per employee', () => {
    const r: SpfReport = {
      run: { id: 'r', month: '2026-09', status: 'PAID', final: true }, entity: { code: 'AACT', name_en: 'AACT', name_ar: null, cr_number: null, spf_employer_no: '123' },
      rows: [{ employee_id: 'e', employee_no: 'A-1', full_name_en: 'Salim', full_name_ar: null, nationality: 'OM', is_omani: true, civil_number: '1234', paid_days: 30, wage: 1000,
        lines: { SPF_EE_OLD_AGE: 75, SPF_ER_OLD_AGE: 110 }, employee_total: 75, employer_total: 110 }],
      totals: { SPF_EE_OLD_AGE: 75, SPF_ER_OLD_AGE: 110 },
      codes: [{ code: 'SPF_ER_OLD_AGE', name_en: '', name_ar: '', kind: 'EMPLOYER' }, { code: 'SPF_EE_OLD_AGE', name_en: '', name_ar: '', kind: 'DEDUCTION' }],
    };
    const c = spfCsv(r);
    expect(c.headers.slice(7, 9)).toEqual(['SPF_EE_OLD_AGE', 'SPF_ER_OLD_AGE']);
    expect(c.rows[0]).toEqual(['A-1', 'Salim', '1234', 'OM', 'Y', 30, 1000, 75, 110, 75, 110]);
  });
});
