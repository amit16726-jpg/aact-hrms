import { describe, expect, it } from 'vitest';
import { changedFields, letterText, verifyUrl, type LetterSnapshot } from './api_ss';

const snap: LetterSnapshot = {
  employee_no: 'AACT-00002', full_name_en: 'Ravi Kumar', full_name_ar: 'رافي كومار', gender: 'M', nationality_en: 'Indian', nationality_ar: 'هندي',
  is_omani: false, civil_number: 'RC998877', join_date: '2020-08-01', status: 'ACTIVE', last_working_date: null, separated: false,
  job_en: 'Machine Operator', job_ar: 'مشغل آلات', department_en: 'Production', department_ar: 'الإنتاج',
  entity_en: 'AACT Industries LLC', entity_ar: 'شركة أ.أ.س.ت للصناعات', entity_cr: '1234567', entity_code: 'AACT',
  salary: { basic: 500, gross: 1650.5, lines: [{ code: 'BASIC', name_en: 'Basic salary', name_ar: 'الراتب الأساسي', amount: 500 },
    { code: 'HOUSING', name_en: 'Housing allowance', name_ar: 'بدل السكن', amount: 1150.5 }] },
};
const base = { addressee: 'Bank Muscat', purpose: 'a personal loan', details: {} };

describe('letter wording', () => {
  it('salary certificate in English states the job, ID, salary breakdown and purpose', () => {
    const x = letterText({ ...base, letter_type: 'SALARY_CERT' }, snap, 'en');
    expect(x.title).toBe('Salary Certificate');
    expect(x.salutation).toBe('To: Bank Muscat');
    expect(x.paragraphs[0]).toBe('This is to certify that Mr. Ravi Kumar, Indian national, holder of resident card number RC998877, has been employed by AACT Industries LLC since 01/08/2020 and currently holds the position of Machine Operator in the Production department.');
    expect(x.paragraphs[1]).toContain('OMR 1,650.500');
    expect(x.paragraphs[2]).toContain('for the purpose of a personal loan');
    expect(x.salary).toEqual([{ label: 'Basic salary', amount: '500.000' }, { label: 'Housing allowance', amount: '1,150.500' }]);
    expect(x.total).toBe('1,650.500');
  });

  it('salary certificate in Arabic uses the right gender and the civil card for Omanis', () => {
    const x = letterText({ ...base, letter_type: 'SALARY_CERT' }, { ...snap, gender: 'F', is_omani: true, civil_number: '11223344', nationality_ar: 'عمانية' }, 'ar');
    expect(x.title).toBe('شهادة راتب');
    expect(x.salutation).toBe('السادة/ \u2068Bank Muscat\u2069 المحترمين');
    expect(x.paragraphs[0]).toContain('السيدة/ رافي كومار');
    expect(x.paragraphs[0]).toContain('حاملة البطاقة المدنية رقم 11223344');
    expect(x.paragraphs[0]).toContain('تعمل لديها منذ 01/08/2020 وتشغل حالياً وظيفة مشغل آلات في قسم الإنتاج');
    expect(x.paragraphs[1]).toContain('راتبها');
    expect(x.closing).toBe('وتفضلوا بقبول فائق الاحترام،');
  });

  it('an employment letter without salary has no salary table', () => {
    const x = letterText({ addressee: null, purpose: null, details: {}, letter_type: 'EMPLOYMENT' }, { ...snap, salary: null }, 'en');
    expect(x.salutation).toBe('To whom it may concern');
    expect(x.salary).toBeNull();
    expect(x.paragraphs).toHaveLength(2);
    expect(x.paragraphs[1]).toBe('This certificate is issued at his request, without any liability on the part of the company.');
  });

  it('experience letter covers the full period for someone who has left', () => {
    const left = { ...snap, separated: true, last_working_date: '2026-09-30', status: 'SEPARATED' };
    const en = letterText({ ...base, letter_type: 'EXPERIENCE' }, left, 'en');
    expect(en.paragraphs[0]).toContain('was employed by AACT Industries LLC from 01/08/2020 to 30/09/2026 as Machine Operator');
    expect(en.paragraphs[en.paragraphs.length - 1]).toBe('We wish him every success.');
    expect(en.salary).toBeNull();
    const ar = letterText({ ...base, letter_type: 'EXPERIENCE' }, left, 'ar');
    expect(ar.paragraphs[0]).toContain('عمل لديها في الفترة من 01/08/2020 إلى 30/09/2026');
  });

  it('NOC for travel names the destination and dates in both languages', () => {
    const l = { addressee: 'Embassy of India', purpose: 'annual leave', letter_type: 'NOC' as const, details: { destination: 'India', from_date: '2026-12-01', to_date: '2026-12-20' } };
    const en = letterText(l, snap, 'en');
    expect(en.title).toBe('No Objection Certificate');
    expect(en.paragraphs[0]).toContain('has no objection to Mr. Ravi Kumar');
    expect(en.paragraphs[0]).toContain('travelling to India from 01/12/2026 to 20/12/2026 for the purpose of annual leave.');
    expect(en.paragraphs[1]).toBe('He remains in our employment.');
    const ar = letterText(l, snap, 'ar');
    expect(ar.paragraphs[0]).toContain('من سفر السيد/ رافي كومار');
    expect(ar.paragraphs[0]).toContain('إلى \u2068India\u2069 خلال الفترة من 01/12/2026 إلى 20/12/2026 لغرض \u2068annual leave\u2069');
  });
});

describe('verification address and changed fields', () => {
  it('uses the configured address or this site', () => {
    expect(verifyUrl('https://hr.aact.om/', 'http://localhost:5173', 'AACT/HR/2026/0001', 'ABCD')).toBe('https://hr.aact.om/verify?ref=AACT%2FHR%2F2026%2F0001&code=ABCD');
    expect(verifyUrl('', 'http://localhost:5173', 'R', 'C')).toBe('http://localhost:5173/verify?ref=R&code=C');
  });
  it('sends only what changed, trimming blanks', () => {
    expect(changedFields({ mobile: '+968 1', city: null, wilayat: 'Sohar' }, { mobile: '+968 1 ', city: ' Muscat', wilayat: '' }))
      .toEqual({ city: 'Muscat', wilayat: '' });
  });
});
