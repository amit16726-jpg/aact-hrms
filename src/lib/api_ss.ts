import { rpc, type Json } from './api';
import type { Balance, EmpBrief } from './api_time';
import { fmtMoney } from './format';

// ---------------------------------------------------------------------------
// Phase 4 — self-service & letters: types returned by the server
// ---------------------------------------------------------------------------
export type ChangeKind = 'PROFILE' | 'EMERGENCY' | 'BANK' | 'CORRECTION';
export type ChangeStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'CANCELLED';
export interface Contact { name: string; relationship: string; phone: string; alt_phone?: string | null; address?: string | null; is_next_of_kin?: boolean }
export interface ChangeReq extends EmpBrief {
  id: string; kind: ChangeKind; reason: string | null; status: ChangeStatus;
  changes: Record<string, { old: string | null; new: string | null }> & { contacts?: Contact[]; previous?: Contact[]; field?: string | null;
    bank_name?: string; branch?: string | null; account_name?: string; account_number?: string; iban?: string | null; swift_code?: string | null };
  requested_by_name: string | null; requested_at: string; due_date: string; overdue: boolean;
  decided_by_name: string | null; decided_at: string | null; decision_note: string | null; can_decide: boolean; can_cancel: boolean;
}

export type LetterType = 'SALARY_CERT' | 'EXPERIENCE' | 'NOC' | 'EMPLOYMENT';
export type LetterLang = 'EN' | 'AR' | 'BOTH';
export type LetterStatus = 'REQUESTED' | 'PREPARED' | 'ISSUED' | 'REJECTED' | 'CANCELLED';
export interface LetterSalaryLine { code: string; name_en: string; name_ar: string | null; amount: number }
export interface LetterSnapshot {
  employee_no: string; full_name_en: string; full_name_ar: string; gender: 'M' | 'F' | null; nationality_en: string | null; nationality_ar: string | null;
  is_omani: boolean; civil_number: string | null; join_date: string; status: string; last_working_date: string | null; separated: boolean;
  job_en: string | null; job_ar: string | null; department_en: string | null; department_ar: string | null;
  entity_en: string; entity_ar: string; entity_cr: string | null; entity_code: string;
  salary?: { basic: number; gross: number; lines: LetterSalaryLine[] } | null;
}
export interface NocDetails { destination?: string; activity?: string; from_date?: string; to_date?: string }
export interface Letter extends EmpBrief {
  id: string; letter_type: LetterType; language: LetterLang; addressee: string | null; purpose: string | null; details: NocDetails;
  include_salary: boolean; status: LetterStatus; requested_by_name: string | null; requested_at: string; self_requested: boolean;
  prepared_by_name: string | null; prepared_at: string | null; approved_by_name: string | null; approved_at: string | null; decision_note: string | null;
  ref_no: string | null; verify_code: string | null; issue_date: string | null; snapshot?: LetterSnapshot | null; salary_hidden: boolean;
  revoked: boolean; revoked_at: string | null; revoke_reason: string | null;
  can_prepare: boolean; can_approve: boolean; can_cancel: boolean; can_revoke: boolean;
}
export interface LetterSettings {
  signatory_en: string; signatory_ar: string; signatory_name_en: string; signatory_name_ar: string; footer_en: string; footer_ar: string; verify_base_url: string;
}
export interface LetterFull extends Letter { settings: LetterSettings | null; preview: LetterSnapshot | null }
export interface LetterCheck {
  valid: boolean; revoked?: boolean; ref_no?: string; letter_type?: LetterType; issue_date?: string;
  full_name_en?: string; full_name_ar?: string; entity_en?: string; entity_ar?: string;
}

export interface Portal {
  linked: boolean;
  employee?: EmpBrief & {
    preferred_name: string | null; marital_status: string | null; personal_email: string | null; work_email: string | null; mobile: string | null;
    alt_phone: string | null; address_line: string | null; city: string | null; wilayat: string | null; governorate: string | null; address_country: string | null;
    date_of_birth: string | null; gender: 'M' | 'F' | null; nationality: string; civil_number: string | null; join_date: string; status: string;
    probation_end_date: string | null; last_working_date: string | null; job_en: string | null; job_ar: string | null; manager_en: string | null; manager_ar: string | null;
  };
  emergency_contacts?: Contact[];
  bank?: { bank_name: string; account: string } | null; bank_pending?: boolean;
  annual?: Balance | null; sick?: Balance | null; leave_pending?: number;
  next_leave?: { name_en: string; name_ar: string; start_date: string; end_date: string; status: string } | null;
  last_payslip?: { id: string; month: string; net: number } | null;
  expiring?: { name_en: string; name_ar: string; expiry_date: string; days_left: number; bucket: string }[];
  changes?: ChangeReq[]; letters?: Letter[]; profile_fields?: string[];
}

export interface TeamMember extends EmpBrief {
  direct: boolean; status: string; mobile: string | null; work_email: string | null; job_en: string | null; job_ar: string | null; probation_end_date: string | null;
  today: { status: string; late_minutes: number; first_in: string | null } | null;
  on_leave: { name_en: string; name_ar: string; end_date: string } | null; pending: number; expiring: number;
}

export interface EmailAdmin {
  settings: { enabled: boolean; app_url: string; sender_name: string };
  queue: { queued: number; sent: number; failed: number };
  recent: { id: string; to_email: string; subject: string; status: string; attempts: number; last_error: string | null; created_at: string; sent_at: string | null }[];
}
export interface EmailPref { email_opt_in: boolean; email: string | null; sending_enabled: boolean }

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------
export const ssapi = {
  portal: () => rpc<Portal>('hr_my_portal'),
  dataExport: () => rpc<Record<string, unknown>>('hr_my_data_export'),
  requestChange: (p: Json) => rpc<ChangeReq>('hr_request_change', { p }),
  cancelChange: (id: string) => rpc<ChangeReq>('hr_cancel_change', { p_id: id }),
  listChanges: (status: string | null, employeeId: string | null = null) => rpc<ChangeReq[]>('hr_list_change_requests', { p_status: status, p_employee: employeeId }),
  decideChange: (id: string, approve: boolean, note: string | null) => rpc<ChangeReq>('hr_decide_change', { p_id: id, p_approve: approve, p_note: note }),

  requestLetter: (p: Json) => rpc<Letter>('hr_request_letter', { p }),
  prepareLetter: (id: string, p: Json) => rpc<Letter>('hr_prepare_letter', { p_id: id, p }),
  decideLetter: (id: string, approve: boolean, note: string | null) => rpc<Letter>('hr_decide_letter', { p_id: id, p_approve: approve, p_note: note }),
  cancelLetter: (id: string) => rpc<Letter>('hr_cancel_letter', { p_id: id }),
  revokeLetter: (id: string, reason: string) => rpc<Letter>('hr_revoke_letter', { p_id: id, p_reason: reason }),
  listLetters: (status: string | null, employeeId: string | null = null) => rpc<Letter[]>('hr_list_letters', { p_status: status, p_employee: employeeId }),
  getLetter: (id: string) => rpc<LetterFull>('hr_get_letter', { p_id: id }),
  verifyLetter: (ref: string, code: string) => rpc<LetterCheck>('hr_verify_letter', { p_ref: ref, p_code: code }),
  letterSettings: () => rpc<LetterSettings>('hr_letter_settings'),
  saveLetterSettings: (p: Json) => rpc<LetterSettings>('hr_save_letter_settings', { p }),

  myTeam: () => rpc<TeamMember[]>('hr_my_team'),

  emailSettings: () => rpc<EmailAdmin>('hr_email_settings'),
  saveEmailSettings: (p: Json) => rpc<EmailAdmin>('hr_save_email_settings', { p }),
  emailTest: () => rpc<EmailAdmin>('hr_email_test'),
  myEmailPref: () => rpc<EmailPref>('hr_my_email_pref'),
  setMyEmailPref: (on: boolean) => rpc<EmailPref>('hr_set_my_email_pref', { p_on: on }),
};

// ---------------------------------------------------------------------------
// Letter wording (English and Arabic), built from the snapshot taken at issue
// ---------------------------------------------------------------------------
export interface LetterText { title: string; salutation: string; paragraphs: string[]; salary: { label: string; amount: string }[] | null; total: string | null; closing: string }

const d = (iso: string | null | undefined) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : '');
const money = (n: number | null | undefined) => fmtMoney(n ?? 0, 3);

export function letterText(l: Pick<Letter, 'letter_type' | 'addressee' | 'purpose' | 'details'>, s: LetterSnapshot, lang: 'en' | 'ar'): LetterText {
  const f = s.gender === 'F';
  const det = l.details ?? {};
  const purpose = l.purpose?.trim() || '';
  const sal = s.salary && (l.letter_type === 'SALARY_CERT' || l.letter_type === 'EMPLOYMENT') ? s.salary : null;
  if (lang === 'en') {
    const hon = s.gender === 'M' ? 'Mr. ' : s.gender === 'F' ? 'Ms. ' : '';
    const he = f ? 'she' : s.gender === 'M' ? 'he' : 'they';
    const his = f ? 'her' : s.gender === 'M' ? 'his' : 'their';
    const him = f ? 'her' : s.gender === 'M' ? 'him' : 'them';
    const has = s.gender ? 'has' : 'have';
    const cap = (x: string) => x.charAt(0).toUpperCase() + x.slice(1);
    const who = `${hon}${s.full_name_en}${s.nationality_en ? `, ${s.nationality_en} national` : ''}${s.civil_number ? `, holder of ${s.is_omani ? 'civil number' : 'resident card number'} ${s.civil_number}` : ''}`;
    const job = `${s.job_en ?? ''}${s.department_en ? ` in the ${s.department_en} department` : ''}`.trim();
    const title = { SALARY_CERT: 'Salary Certificate', EXPERIENCE: 'Experience Certificate', NOC: 'No Objection Certificate', EMPLOYMENT: 'Employment Certificate' }[l.letter_type];
    const p: string[] = [];
    if (l.letter_type === 'NOC') {
      const what = det.destination ? `travelling to ${det.destination}` : `${det.activity ?? ''}`;
      const when = det.from_date && det.to_date ? ` from ${d(det.from_date)} to ${d(det.to_date)}` : det.from_date ? ` from ${d(det.from_date)}` : '';
      p.push(`${s.entity_en} has no objection to ${who}, employed with us as ${job} since ${d(s.join_date)}, ${what}${when}${purpose ? ` for the purpose of ${purpose}` : ''}.`);
      p.push(`${cap(he)} remain${s.gender ? 's' : ''} in our employment.`);
    } else if (l.letter_type === 'EXPERIENCE' || s.separated) {
      const to = s.last_working_date ? `to ${d(s.last_working_date)}` : 'to date';
      p.push(`This is to certify that ${who}, ${s.separated ? 'was' : 'has been'} employed by ${s.entity_en} from ${d(s.join_date)} ${to} as ${job}.`);
      if (sal) p.push(`${cap(his)} gross monthly salary is OMR ${money(sal.gross)}, made up as follows:`);
      if (l.letter_type === 'EXPERIENCE') p.push(`We wish ${him} every success.`);
      else p.push(`This certificate is issued at ${his} request${purpose ? ` for the purpose of ${purpose}` : ''}, without any liability on the part of the company.`);
    } else {
      p.push(`This is to certify that ${who}, ${has} been employed by ${s.entity_en} since ${d(s.join_date)} and currently hold${s.gender ? 's' : ''} the position of ${job}.`);
      if (sal) p.push(`${cap(his)} current gross monthly salary is OMR ${money(sal.gross)}, made up as follows:`);
      p.push(`This certificate is issued at ${his} request${purpose ? ` for the purpose of ${purpose}` : ''}, without any liability on the part of the company.`);
    }
    return {
      title, salutation: l.addressee?.trim() ? `To: ${l.addressee.trim()}` : 'To whom it may concern', paragraphs: p,
      salary: sal ? sal.lines.map((x) => ({ label: x.name_en, amount: money(x.amount) })) : null, total: sal ? money(sal.gross) : null,
      closing: 'Yours faithfully,',
    };
  }
  // Arabic — text typed by people (addressee, purpose, place) may be English: isolate it so the line order stays right
  const iso = (x: string) => (x ? `\u2068${x}\u2069` : '');
  const hon = s.gender === 'M' ? 'السيد/ ' : s.gender === 'F' ? 'السيدة/ ' : '';
  const g = (m: string, fem: string) => (f ? fem : m);
  const who = `${hon}${s.full_name_ar}${s.nationality_ar ? ` (الجنسية: ${s.nationality_ar})` : ''}${s.civil_number ? `، ${g('حامل', 'حاملة')} ${s.is_omani ? 'البطاقة المدنية' : 'بطاقة الإقامة'} رقم ${s.civil_number}` : ''}`;
  const job = `${s.job_ar ?? ''}${s.department_ar ? ` في قسم ${s.department_ar}` : ''}`.trim();
  const title = { SALARY_CERT: 'شهادة راتب', EXPERIENCE: 'شهادة خبرة', NOC: 'شهادة عدم ممانعة', EMPLOYMENT: 'شهادة عمل' }[l.letter_type];
  const forPurpose = purpose ? ` لغرض ${iso(purpose)}` : '';
  const p: string[] = [];
  if (l.letter_type === 'NOC') {
    const when = det.from_date && det.to_date ? ` خلال الفترة من ${d(det.from_date)} إلى ${d(det.to_date)}` : det.from_date ? ` اعتباراً من ${d(det.from_date)}` : '';
    const act = det.destination ? `سفر ${who} إلى ${iso(det.destination)}` : `قيام ${who} بـ${iso(det.activity ?? '')}`;
    p.push(`لا مانع لدى ${s.entity_ar} من ${act}${when}${forPurpose}، ${g('علماً بأنه يعمل', 'علماً بأنها تعمل')} لدينا بوظيفة ${job} منذ ${d(s.join_date)}.`);
    p.push(`${g('ولا يزال على رأس عمله', 'ولا تزال على رأس عملها')} لدينا.`);
  } else if (l.letter_type === 'EXPERIENCE' || s.separated) {
    const to = s.last_working_date ? `إلى ${d(s.last_working_date)}` : 'وحتى تاريخه';
    p.push(`تشهد ${s.entity_ar} بأن ${who} ${s.separated ? g('عمل', 'عملت') : g('يعمل', 'تعمل')} لديها في الفترة من ${d(s.join_date)} ${to} بوظيفة ${job}.`);
    if (sal) p.push(`ويبلغ إجمالي ${g('راتبه', 'راتبها')} الشهري ${money(sal.gross)} ريال عماني، وتفاصيله كالآتي:`);
    if (l.letter_type === 'EXPERIENCE') p.push(`ونتمنى ${g('له', 'لها')} التوفيق.`);
    else p.push(`وقد أُعطيت هذه الشهادة بناءً على ${g('طلبه', 'طلبها')}${forPurpose} دون أدنى مسؤولية على الشركة.`);
  } else {
    p.push(`تشهد ${s.entity_ar} بأن ${who} ${g('يعمل', 'تعمل')} لديها منذ ${d(s.join_date)} ${g('ويشغل', 'وتشغل')} حالياً وظيفة ${job}.`);
    if (sal) p.push(`ويبلغ إجمالي ${g('راتبه', 'راتبها')} الشهري الحالي ${money(sal.gross)} ريال عماني، وتفاصيله كالآتي:`);
    p.push(`وقد أُعطيت هذه الشهادة بناءً على ${g('طلبه', 'طلبها')}${forPurpose} دون أدنى مسؤولية على الشركة.`);
  }
  return {
    title, salutation: l.addressee?.trim() ? `السادة/ ${iso(l.addressee.trim())} المحترمين` : 'إلى من يهمه الأمر', paragraphs: p,
    salary: sal ? sal.lines.map((x) => ({ label: x.name_ar || x.name_en, amount: money(x.amount) })) : null, total: sal ? money(sal.gross) : null,
    closing: 'وتفضلوا بقبول فائق الاحترام،',
  };
}

/** The address printed on a letter for checking it online. */
export function verifyUrl(base: string | null | undefined, origin: string, ref: string, code: string) {
  const b = (base && /^https?:\/\//.test(base) ? base : origin).replace(/\/+$/, '');
  return `${b}/verify?ref=${encodeURIComponent(ref)}&code=${encodeURIComponent(code)}`;
}

/** Profile fields an employee may change through a request, with their translation keys. */
export const SS_FIELDS = ['preferred_name', 'mobile', 'alt_phone', 'personal_email', 'marital_status', 'address_line', 'city', 'wilayat', 'governorate', 'address_country'] as const;
export type SsField = typeof SS_FIELDS[number];

/** Only the fields whose value actually changed (blank and missing are the same). */
export function changedFields(before: Partial<Record<SsField, string | null>>, after: Partial<Record<SsField, string>>): Partial<Record<SsField, string>> {
  const out: Partial<Record<SsField, string>> = {};
  for (const k of SS_FIELDS) {
    if (!(k in after)) continue;
    const a = (after[k] ?? '').trim();
    const b = (before[k] ?? '').trim();
    if (a !== b) out[k] = a;
  }
  return out;
}
