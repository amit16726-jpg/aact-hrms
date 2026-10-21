import { describe, expect, it } from 'vitest';
import { groupByStage, offerLines, offerText, type AppBrief } from './api_rec';

const offer = {
  job_en: 'Machine operator', job_ar: 'مشغل آلة', department_en: 'Production', department_ar: 'الإنتاج', location_en: 'Sohar factory', location_ar: 'مصنع صحار',
  start_date: '2026-11-20', contract_type: 'FIXED_TERM' as const, contract_months: 24, probation_months: 3, notice_days: 30,
  benefits: 'Return air ticket every two years', valid_until: '2026-11-05', gross: 330, entity_en: 'AACT Industries LLC', entity_ar: 'شركة أ.أ.س.ت للصناعات',
  lines: [{ code: 'BASIC', name_en: 'Basic salary', name_ar: 'الراتب الأساسي', amount: 250, is_basic: true },
    { code: 'HOUSING', name_en: 'Housing allowance', name_ar: 'بدل السكن', amount: 80, is_basic: false }],
};

describe('offer letter wording', () => {
  it('English states every term, the salary and the validity', () => {
    const x = offerText(offer, { full_name_en: 'Arjun Nair', full_name_ar: null, gender: 'M' }, 'en');
    expect(x.greeting).toBe('Dear Mr. Arjun Nair,');
    expect(x.terms.map((t) => t.label)).toEqual(['Position', 'Department', 'Work location', 'Start date', 'Contract', 'Probation', 'Notice period', 'Other benefits']);
    expect(x.terms.find((t) => t.label === 'Contract')?.value).toBe('Fixed term, 24 months');
    expect(x.terms.find((t) => t.label === 'Probation')?.value).toBe('3 months');
    expect(x.terms.find((t) => t.label === 'Start date')?.value).toBe('20/11/2026');
    expect(x.salary).toEqual([{ label: 'Basic salary', amount: '250.000' }, { label: 'Housing allowance', amount: '80.000' }]);
    expect(x.total).toBe('330.000');
    expect(x.closing[1]).toContain('valid until 05/11/2026');
  });
  it('Arabic uses the right gender, Arabic plurals and isolates typed text', () => {
    const x = offerText({ ...offer, probation_months: 2, contract_type: 'INDEFINITE', contract_months: null }, { full_name_en: 'Huda Al Saadi', full_name_ar: 'هدى السعدية', gender: 'F' }, 'ar');
    expect(x.greeting).toBe('عزيزتي السيدة/ هدى السعدية،');
    expect(x.intro).toContain('عليكِ');
    expect(x.terms.find((t) => t.label === 'فترة التجربة')?.value).toBe('شهران');
    expect(x.terms.find((t) => t.label === 'العقد')?.value).toBe('غير محدد المدة');
    expect(x.terms.find((t) => t.label === 'مزايا أخرى')?.value).toBe('⁨Return air ticket every two years⁩');
  });
  it('no probation and no benefits', () => {
    const x = offerText({ ...offer, probation_months: 0, benefits: null, valid_until: null, location_en: null, location_ar: null }, { full_name_en: 'A B', full_name_ar: null, gender: null }, 'en');
    expect(x.greeting).toBe('Dear A B,');
    expect(x.terms.find((t) => t.label === 'Probation')?.value).toBe('None');
    expect(x.terms.some((t) => t.label === 'Other benefits' || t.label === 'Work location')).toBe(false);
  });
});

describe('pipeline helpers', () => {
  it('groups applications by stage', () => {
    const a = (id: string, stage: AppBrief['stage']) => ({ id, stage } as AppBrief);
    const g = groupByStage([a('1', 'APPLIED'), a('2', 'OFFER'), a('3', 'APPLIED'), a('4', 'REJECTED')]);
    expect(g.APPLIED.map((x) => x.id)).toEqual(['1', '3']);
    expect(g.OFFER).toHaveLength(1);
    expect(g.HIRED).toHaveLength(0);
  });
  it('keeps only salary lines with a positive amount', () => {
    expect(offerLines([{ code: 'BASIC', amount: ' 250 ' }, { code: 'HOUSING', amount: '' }, { code: 'TRANSPORT', amount: '0' }, { code: '', amount: '5' }]))
      .toEqual([{ code: 'BASIC', amount: '250' }]);
  });
});
