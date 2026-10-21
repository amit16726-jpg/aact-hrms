import { rpc, type Json } from './api';
import type { EmpBrief } from './api_time';
import type { LetterSettings } from './api_ss';
import { fmtMoney } from './format';

// ---------------------------------------------------------------------------
// Phase 5 — recruitment & onboarding: types returned by the server
// ---------------------------------------------------------------------------
export type ReqStatusRec = 'PENDING' | 'APPROVED' | 'REJECTED' | 'ON_HOLD' | 'FILLED' | 'CANCELLED';
export type NatRule = 'ANY' | 'OMANI_ONLY' | 'OMANI_PREFERRED';
export type Stage = 'APPLIED' | 'SHORTLISTED' | 'INTERVIEW' | 'OFFER' | 'HIRED' | 'REJECTED' | 'WITHDRAWN';
export type OfferStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'ACCEPTED' | 'DECLINED' | 'WITHDRAWN';
export const STAGES: Stage[] = ['APPLIED', 'SHORTLISTED', 'INTERVIEW', 'OFFER', 'HIRED', 'REJECTED', 'WITHDRAWN'];

export interface OmaniRow { total: number; omani: number; expat: number; pct: number | null; target_pct: number | null; meets_target: boolean | null; omanis_needed: number | null }
export interface HireOmanisation {
  job_omani_only: boolean; job_omani_only_source: string | null; entity: OmaniRow; department: OmaniRow;
  pct_if_omani: number | null; pct_if_expat: number | null; expat_breaks_target: boolean; target_pct: number | null;
}
export interface Requisition {
  id: string; ref_no: string; entity_id: string; entity_code: string; department_id: string; department_en: string; department_ar: string | null;
  job_title_id: string; job_en: string; job_ar: string | null; job_omani_only: boolean; grade_id: string | null; grade_en: string | null; grade_ar: string | null;
  category_id: string | null; category_en: string | null; category_ar: string | null; location_id: string | null;
  positions: number; reason: 'NEW' | 'REPLACEMENT' | 'TEMPORARY'; replaces_employee_id: string | null; replaces_name: string | null;
  employment_type: string; nationality_rule: NatRule; salary_min: number | null; salary_max: number | null; target_date: string | null;
  justification: string; status: ReqStatusRec; requested_by_name: string | null; requested_at: string; decided_by_name: string | null;
  decided_at: string | null; decision_note: string | null; closed_reason: string | null; hired: number; in_pipeline: number;
  can_decide: boolean; can_edit: boolean; can_manage: boolean;
}
export interface AppBrief {
  id: string; requisition_id: string; candidate_id: string; stage: Stage; stage_at: string; rejection_reason: string | null; employee_id: string | null;
  full_name_en: string; full_name_ar: string | null; nationality: string; is_omani: boolean; in_oman: boolean; source: string;
  experience_years: number | null; interviews: number; avg_rating: number | null; offer_status: OfferStatus | null;
}
export interface RequisitionFull extends Requisition { omanisation: HireOmanisation; applications: AppBrief[] }
export interface Candidate {
  id: string; full_name_en: string; full_name_ar: string | null; nationality: string; nationality_en: string | null; nationality_ar: string | null;
  is_omani: boolean; gender: 'M' | 'F' | null; date_of_birth: string | null; email: string | null; phone: string | null; civil_number: string | null;
  passport_no: string | null; in_oman: boolean; current_employer: string | null; experience_years: number | null; qualification: string | null;
  source: string; notes: string | null; employee_id: string | null; created_at: string; applications?: number | (AppBrief & { requisition_ref: string; job_en: string; job_ar: string | null })[]; active?: number;
}
export interface Interview {
  id: string; application_id: string; scheduled_at: string; mode: 'IN_PERSON' | 'PHONE' | 'VIDEO'; location: string | null; interviewer_id: string;
  interviewer_name: string | null; status: 'SCHEDULED' | 'DONE' | 'CANCELLED' | 'NO_SHOW'; rating: number | null; recommendation: 'HIRE' | 'MAYBE' | 'NO' | null;
  feedback: string | null; recorded_at: string | null; can_record: boolean; can_cancel: boolean;
  full_name_en?: string; full_name_ar?: string | null; job_en?: string; job_ar?: string | null; requisition_ref?: string;
}
export interface OfferLine { code: string; name_en: string; name_ar: string; amount: number; is_basic: boolean }
export interface Offer {
  id: string; ref_no: string; application_id: string; job_title_id: string; job_en: string; job_ar: string | null; department_id: string;
  department_en: string; department_ar: string | null; grade_id: string | null; category_id: string; category_en: string; category_ar: string | null;
  location_id: string | null; location_en: string | null; location_ar: string | null; start_date: string; contract_type: 'FIXED_TERM' | 'INDEFINITE';
  contract_months: number | null; probation_months: number; notice_days: number; benefits: string | null; valid_until: string | null;
  lines: OfferLine[]; gross: number | null; status: OfferStatus; prepared_by_name: string | null; prepared_at: string; approved_by_name: string | null;
  approved_at: string | null; decision_note: string | null; response_at: string | null; response_note: string | null;
  can_decide: boolean; can_edit: boolean; can_respond: boolean; can_withdraw: boolean; can_hire: boolean;
  full_name_en?: string; full_name_ar?: string | null;
}
export interface OfferFull extends Offer { candidate: Candidate; entity_en: string; entity_ar: string | null; entity_cr: string | null; settings: LetterSettings | null; today: string }
export interface OnboardingTask {
  id: string; code: string; title_en: string; title_ar: string; due_date: string | null; status: 'PENDING' | 'DONE' | 'NOT_NEEDED'; note: string | null;
  done_by_name: string | null; done_at: string | null; overdue: boolean;
}
export interface Application extends Omit<AppBrief, 'interviews'> {
  candidate: Candidate; requisition: Requisition; prior_employee_id: string | null; probation_max_months: number;
  interviews: Interview[]; offers: Offer[]; onboarding: OnboardingTask[]; can_manage: boolean;
  new_employee_id?: string; employee_no?: string;
}
export interface OnboardingRow {
  application_id: string; full_name_en: string; full_name_ar: string | null; nationality: string; employee_id: string | null; stage: Stage;
  job_en: string; job_ar: string | null; start_date: string; offer_ref: string; total: number; done: number; overdue: number;
  next: { title_en: string; title_ar: string; due_date: string | null } | null;
}
export interface ProbationRow extends EmpBrief {
  join_date: string; probation_end_date: string | null; days_left: number | null; overdue: boolean; job_en: string | null; job_ar: string | null;
  manager_en: string | null; manager_ar: string | null; max_end: string; can_decide: boolean;
}
export interface ChecklistStep { code: string; en: string; ar: string; days: number }
export interface RecSettings {
  probation_monthly_max_months: number; probation_other_max_months: number; probation_legal_basis: string; probation_reminder_days: number;
  onboarding: Record<'EXPAT_ABROAD' | 'EXPAT_IN_OMAN' | 'OMANI', ChecklistStep[]>;
}
export interface Interviewer { user_id: string; name: string; email: string | null; job_en: string | null; job_ar: string | null }

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------
export const recapi = {
  listRequisitions: (p: Json) => rpc<Requisition[]>('hr_list_requisitions', { p }),
  getRequisition: (id: string) => rpc<RequisitionFull>('hr_get_requisition', { p_id: id }),
  saveRequisition: (p: Json) => rpc<RequisitionFull>('hr_save_requisition', { p }),
  decideRequisition: (id: string, approve: boolean, note: string | null) => rpc<RequisitionFull>('hr_decide_requisition', { p_id: id, p_approve: approve, p_note: note }),
  setRequisitionStatus: (id: string, status: string, reason: string | null) => rpc<RequisitionFull>('hr_set_requisition_status', { p_id: id, p_status: status, p_reason: reason }),

  listCandidates: (q: string) => rpc<Candidate[]>('hr_list_candidates', { p: { q } }),
  getCandidate: (id: string) => rpc<Candidate>('hr_get_candidate', { p_id: id }),
  saveCandidate: (p: Json) => rpc<Candidate>('hr_save_candidate', { p }),
  addApplication: (p: Json) => rpc<Application>('hr_add_application', { p }),
  moveApplication: (id: string, stage: Stage, reason: string | null) => rpc<Application>('hr_move_application', { p_id: id, p_stage: stage, p_reason: reason }),
  getApplication: (id: string) => rpc<Application>('hr_get_application', { p_id: id }),

  interviewers: () => rpc<Interviewer[]>('hr_rec_interviewers'),
  scheduleInterview: (p: Json) => rpc<Application>('hr_schedule_interview', { p }),
  recordInterview: (id: string, p: Json) => rpc<Application>('hr_record_interview', { p_id: id, p }),
  myInterviews: () => rpc<Interview[]>('hr_my_interviews'),

  saveOffer: (p: Json) => rpc<Application>('hr_save_offer', { p }),
  decideOffer: (id: string, approve: boolean, note: string | null) => rpc<Application>('hr_decide_offer', { p_id: id, p_approve: approve, p_note: note }),
  offerResponse: (id: string, accepted: boolean, note: string | null) => rpc<Application>('hr_offer_response', { p_id: id, p_accepted: accepted, p_note: note }),
  withdrawOffer: (id: string, reason: string) => rpc<Application>('hr_withdraw_offer', { p_id: id, p_reason: reason }),
  getOffer: (id: string) => rpc<OfferFull>('hr_get_offer', { p_id: id }),

  setTask: (id: string, status: OnboardingTask['status'], note: string | null) => rpc<Application>('hr_set_onboarding_task', { p_id: id, p_status: status, p_note: note }),
  listOnboarding: (openOnly: boolean) => rpc<OnboardingRow[]>('hr_list_onboarding', { p: { open_only: openOnly } }),
  hire: (offerId: string, p: Json) => rpc<Application>('hr_hire', { p_offer: offerId, p }),

  listProbation: () => rpc<ProbationRow[]>('hr_list_probation'),
  extendProbation: (employeeId: string, p: Json) => rpc<ProbationRow[]>('hr_extend_probation', { p_employee: employeeId, p }),

  settings: () => rpc<RecSettings>('hr_recruitment_settings'),
  saveSettings: (p: Json) => rpc<RecSettings>('hr_save_recruitment_settings', { p }),
};

// ---------------------------------------------------------------------------
// Offer letter wording (English and Arabic)
// ---------------------------------------------------------------------------
export interface OfferText { title: string; greeting: string; intro: string; terms: { label: string; value: string }[]; salary: { label: string; amount: string }[]; total: string; closing: string[]; accept: string }

const d = (iso: string | null | undefined) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : '—');
const money = (n: number | null | undefined) => fmtMoney(n ?? 0, 3);

export function offerText(o: Pick<OfferFull, 'job_en' | 'job_ar' | 'department_en' | 'department_ar' | 'location_en' | 'location_ar' | 'start_date' | 'contract_type'
  | 'contract_months' | 'probation_months' | 'notice_days' | 'benefits' | 'valid_until' | 'lines' | 'gross' | 'entity_en' | 'entity_ar'>,
  c: Pick<Candidate, 'full_name_en' | 'full_name_ar' | 'gender'>, lang: 'en' | 'ar'): OfferText {
  const f = c.gender === 'F';
  if (lang === 'en') {
    const hon = c.gender === 'M' ? 'Mr. ' : c.gender === 'F' ? 'Ms. ' : '';
    const terms = [
      { label: 'Position', value: o.job_en },
      { label: 'Department', value: o.department_en },
      ...(o.location_en ? [{ label: 'Work location', value: o.location_en }] : []),
      { label: 'Start date', value: d(o.start_date) },
      { label: 'Contract', value: o.contract_type === 'FIXED_TERM' ? `Fixed term, ${o.contract_months} months` : 'Unlimited (indefinite) term' },
      { label: 'Probation', value: o.probation_months ? `${o.probation_months} month${o.probation_months > 1 ? 's' : ''}` : 'None' },
      { label: 'Notice period', value: `${o.notice_days} days` },
      ...(o.benefits ? [{ label: 'Other benefits', value: o.benefits }] : []),
    ];
    return {
      title: 'Offer of Employment', greeting: `Dear ${hon}${c.full_name_en},`,
      intro: `We are pleased to offer you employment with ${o.entity_en} on the following terms, subject to the laws of the Sultanate of Oman and, for non-Omani nationals, to the issue of the work permit and residence.`,
      terms, salary: o.lines.map((l) => ({ label: l.name_en, amount: money(l.amount) })), total: money(o.gross),
      closing: [
        'Working hours, leave and end-of-service benefits are as set out in the Oman Labour Law and company policy. The full terms will be stated in the employment contract registered with the Ministry of Labour.',
        o.valid_until ? `This offer is valid until ${d(o.valid_until)}. Please sign below to confirm your acceptance.` : 'Please sign below to confirm your acceptance.',
      ],
      accept: 'I accept this offer on the terms above.',
    };
  }
  const hon = c.gender === 'M' ? 'السيد/ ' : c.gender === 'F' ? 'السيدة/ ' : '';
  const g = (m: string, fem: string) => (f ? fem : m);
  const iso = (x: string) => `⁨${x}⁩`;
  const terms = [
    { label: 'الوظيفة', value: o.job_ar || o.job_en },
    { label: 'القسم', value: o.department_ar || o.department_en },
    ...(o.location_en ? [{ label: 'مكان العمل', value: o.location_ar || o.location_en }] : []),
    { label: 'تاريخ المباشرة', value: d(o.start_date) },
    { label: 'العقد', value: o.contract_type === 'FIXED_TERM' ? `محدد المدة، ${o.contract_months} شهراً` : 'غير محدد المدة' },
    { label: 'فترة التجربة', value: !o.probation_months ? 'لا يوجد' : o.probation_months === 1 ? 'شهر واحد' : o.probation_months === 2 ? 'شهران' : `${o.probation_months} أشهر` },
    { label: 'مدة الإخطار', value: `${o.notice_days} يوماً` },
    ...(o.benefits ? [{ label: 'مزايا أخرى', value: iso(o.benefits) }] : []),
  ];
  return {
    title: 'عرض عمل', greeting: `${g('عزيزي', 'عزيزتي')} ${hon}${c.full_name_ar || c.full_name_en}،`,
    intro: `يسرنا أن نعرض ${g('عليك', 'عليكِ')} العمل لدى ${o.entity_ar || o.entity_en} وفق الشروط الآتية، مع مراعاة قوانين سلطنة عمان، وبالنسبة لغير العمانيين بشرط صدور ترخيص العمل والإقامة.`,
    terms, salary: o.lines.map((l) => ({ label: l.name_ar || l.name_en, amount: money(l.amount) })), total: money(o.gross),
    closing: [
      'تكون ساعات العمل والإجازات ومكافأة نهاية الخدمة وفق قانون العمل العماني وسياسة الشركة، وتُذكر الشروط كاملة في عقد العمل المسجل لدى وزارة العمل.',
      o.valid_until ? `هذا العرض ساري حتى ${d(o.valid_until)}. يرجى التوقيع أدناه لتأكيد القبول.` : 'يرجى التوقيع أدناه لتأكيد القبول.',
    ],
    accept: 'أوافق على هذا العرض وفق الشروط المذكورة أعلاه.',
  };
}

/** Pipeline columns shown on the requisition (closed stages are listed below them). */
export const OPEN_STAGES: Stage[] = ['APPLIED', 'SHORTLISTED', 'INTERVIEW', 'OFFER'];
export function groupByStage(apps: AppBrief[]): Record<Stage, AppBrief[]> {
  const out = Object.fromEntries(STAGES.map((s) => [s, [] as AppBrief[]])) as Record<Stage, AppBrief[]>;
  for (const a of apps) out[a.stage].push(a);
  return out;
}

/** Offer form helper: earning lines with an amount, basic first. */
export function offerLines(rows: { code: string; amount: string }[]): { code: string; amount: string }[] {
  return rows.filter((r) => r.code && r.amount.trim() !== '' && Number(r.amount) > 0).map((r) => ({ code: r.code, amount: r.amount.trim() }));
}
