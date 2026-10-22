import { rpc } from './api';
import type { Lang } from './api';
import type { ExecDashboard } from './api_gov';

// ---------------------------------------------------------------------------
// Types returned by the server
// ---------------------------------------------------------------------------
export type ReportGroup = 'WORKFORCE' | 'PAYROLL' | 'TIME' | 'COMPLIANCE' | 'TALENT' | 'AUDIT';
export type ReportParam = 'entity' | 'as_of' | 'from_to' | 'month' | 'run' | 'department' | 'pay_group' | 'nationality_group' | 'days'
  | 'leave_type' | 'cycle' | 'table';
export type ColType = 'text' | 'int' | 'num' | 'money' | 'pct' | 'date';
export interface ReportDef {
  code: string; grp: ReportGroup; sort: number; perm: string; money: boolean; sensitive: boolean; params: ReportParam[];
  name_en: string; name_ar: string; desc_en: string; desc_ar: string;
}
export interface ReportCatalog {
  reports: ReportDef[]; can_schedule: boolean; board_pack: boolean; audit_tables: string[] | null;
  cycles: { id: string; entity_id: string; name: string; period_end: string }[] | null;
  runs: { id: string; entity_id: string; month: string; pay_group: 'NMG' | 'MG'; status: string }[] | null;
}
export interface ReportColumn { k: string; en: string; ar: string; t: ColType; s?: 1 }
export type ReportRow = Record<string, string | number | null>;
export interface ReportResult {
  code: string; name_en: string; name_ar: string; group: ReportGroup; money: boolean; sensitive: boolean;
  columns: ReportColumn[]; rows: ReportRow[]; meta: { run_id?: string; month?: string; pay_group?: string; status?: string; pay_date?: string | null };
  generated_at: string; generated_by: string | null;
  entity: { id: string; code: string; name_en: string; name_ar: string | null; cr_number: string | null } | null;
  department: { name_en: string; name_ar: string | null } | null;
}
export type ReportParams = Record<string, string | number | null | undefined>;
export interface ReportSchedule {
  id: string; code: string; name: string | null; params: ReportParams; recipients: string[]; day_of_month: number; is_active: boolean;
  last_sent_on: string | null; created_by_name: string | null; report_en: string; report_ar: string;
  recipient_names: { user_id: string; name: string | null }[];
}
export interface Recipient { user_id: string; name: string; email: string; perms: string[] }
export interface BoardPack {
  exec: ExecDashboard; entity: { code: string; name_en: string; name_ar: string | null }; generated_at: string; generated_by: string | null;
  payroll_month: string | null; payroll_by_department: { name_en: string; name_ar: string; headcount: number; cost: number }[] | null;
  expiries_by_type: { name_en: string; name_ar: string | null; expired: number; d30: number; d90: number }[];
  leavers_by_type: { type: string; n: number }[];
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------
const clean = (p: ReportParams) => Object.fromEntries(Object.entries(p).filter(([, v]) => v !== '' && v !== null && v !== undefined));
export const repapi = {
  catalog: () => rpc<ReportCatalog>('hr_report_catalog'),
  run: (code: string, params: ReportParams) => rpc<ReportResult>('hr_run_report', { p_code: code, p: clean(params) }),
  boardPack: (entityId: string) => rpc<BoardPack>('hr_board_pack', { p_entity: entityId }),
  schedules: () => rpc<ReportSchedule[]>('hr_list_report_schedules'),
  schedule: (id: string) => rpc<ReportSchedule>('hr_get_report_schedule', { p_id: id }),
  saveSchedule: (s: { id?: string; code: string; name: string | null; params: ReportParams; recipients: string[]; day_of_month: number; is_active?: boolean }) =>
    rpc<ReportSchedule>('hr_save_report_schedule', { p: { ...s, params: clean(s.params) } }),
  setScheduleActive: (id: string, active: boolean) => rpc<ReportSchedule>('hr_set_report_schedule_active', { p_id: id, p_active: active }),
  recipients: () => rpc<Recipient[]>('hr_report_recipients'),
};

// ---------------------------------------------------------------------------
// Helpers (pure — unit tested)
// ---------------------------------------------------------------------------
export const GROUPS: ReportGroup[] = ['WORKFORCE', 'PAYROLL', 'TIME', 'COMPLIANCE', 'TALENT', 'AUDIT'];

/** Readable labels for the codes reports return (status, type …). Unknown upper-case codes become "End of contract" style text. */
const CODES: Record<string, [string, string]> = {
  APPROVED: ['Approved', 'معتمد'], PENDING: ['Pending', 'قيد الاعتماد'], PENDING_MANAGER: ['With manager', 'لدى المدير'], PENDING_HR: ['With HR', 'لدى الموارد البشرية'],
  REJECTED: ['Rejected', 'مرفوض'], CANCELLED: ['Cancelled', 'ملغى'], SUPERSEDED: ['Superseded', 'مستبدل'], PAID: ['Paid', 'مدفوع'], PREPARED: ['Prepared', 'معد'],
  DRAFT: ['Draft', 'مسودة'], CALCULATED: ['Calculated', 'محسوب'], VERIFIED: ['Verified', 'مدقق'], ACTIVE: ['Active', 'على رأس العمل'], PROBATION: ['Probation', 'تحت التجربة'],
  NOTICE: ['Notice period', 'فترة الإنذار'], SUSPENDED: ['Suspended', 'موقوف'], SEPARATED: ['Left', 'غادر'], OPEN: ['Open', 'مفتوح'], CLOSED: ['Closed', 'مغلق'],
  COMPLETED: ['Completed', 'مكتمل'], ISSUED: ['Issued', 'مسلم'], RETURNED: ['Returned', 'مرتجع'], DONE: ['Done', 'منجز'], FILLED: ['Filled', 'مشغول'], ON_HOLD: ['On hold', 'معلق'],
  RESIGNATION: ['Resignation', 'استقالة'], TERMINATION: ['Termination', 'إنهاء خدمة'], END_OF_CONTRACT: ['End of contract', 'انتهاء العقد'], RETIREMENT: ['Retirement', 'تقاعد'],
  DEATH: ['Death', 'وفاة'], OTHER: ['Other', 'أخرى'], EARNING: ['Earning', 'استحقاق'], DEDUCTION: ['Deduction', 'استقطاع'], EMPLOYER: ['Employer', 'صاحب العمل'],
  LOAN: ['Loan', 'قرض'], ADVANCE: ['Advance', 'سلفة'], M: ['Male', 'ذكر'], F: ['Female', 'أنثى'], Yes: ['Yes', 'نعم'], No: ['No', 'لا'],
  Omani: ['Omani', 'عماني'], Expatriate: ['Expatriate', 'وافد'], WORKDAY: ['Working day', 'يوم عمل'], REST_DAY: ['Rest day', 'يوم راحة'], HOLIDAY: ['Public holiday', 'عطلة رسمية'],
  FIRST_AID: ['First aid', 'إسعافات أولية'], MEDICAL: ['Medical treatment', 'علاج طبي'], LOST_TIME: ['Lost time', 'إصابة مع انقطاع'], PERMANENT: ['Permanent', 'دائمة'], FATAL: ['Fatal', 'وفاة'],
  INVESTIGATION: ['Investigation', 'تحقيق'], PROPOSED: ['Proposed', 'مقترح'], DECIDED: ['Decided', 'تم البت'], DISMISSED: ['Dismissed', 'حفظت'],
  INSERT: ['Added', 'إضافة'], UPDATE: ['Changed', 'تعديل'], DELETE: ['Removed', 'حذف'], NMG: ['NMG', 'غير إداريين'], MG: ['MG', 'إداريون'],
  FIXED_TERM: ['Fixed term', 'محدد المدة'], INDEFINITE: ['Indefinite', 'غير محدد المدة'], JOIN: ['Joining', 'التعيين'], INCREMENT: ['Increment', 'علاوة'],
  PROMOTION: ['Promotion', 'ترقية'], ADJUSTMENT: ['Adjustment', 'تعديل'], CORRECTION: ['Correction', 'تصحيح'], REHIRE: ['Rehire', 'إعادة تعيين'],
  SELF: ['Self-assessment', 'التقييم الذاتي'], MANAGER: ['With manager', 'لدى المدير'], HR: ['With HR', 'لدى الموارد البشرية'], ACK: ['Employee to acknowledge', 'بانتظار إقرار الموظف'],
  PAY: ['Pay', 'أجر'], TIME_OFF: ['Time off', 'وقت راحة'],
};
export function codeLabel(v: string, lang: Lang): string {
  const hit = CODES[v];
  if (hit) return lang === 'ar' ? hit[1] : hit[0];
  if (/^[A-Z][A-Z0-9_]{2,}$/.test(v)) { const s = v.toLowerCase().replace(/_/g, ' '); return s.charAt(0).toUpperCase() + s.slice(1); }
  return v;
}

const n3 = (v: number) => v.toLocaleString('en-US', { minimumFractionDigits: 3, maximumFractionDigits: 3 });
const n2 = (v: number) => v.toLocaleString('en-US', { maximumFractionDigits: 2 });
/** "2026-09-30" → "30/09/2026" (dd/MM/yyyy, as everywhere in the app). */
export function ddmmyyyy(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : iso;
}
/** A cell as text for the screen and the PDF. */
export function cellText(v: string | number | null | undefined, t: ColType, lang: Lang): string {
  if (v === null || v === undefined || v === '') return '—';
  switch (t) {
    case 'money': return n3(Number(v));
    case 'num': return n2(Number(v));
    case 'int': return String(Math.round(Number(v)));
    case 'pct': return `${n2(Number(v))}%`;
    case 'date': return ddmmyyyy(String(v));
    default: return typeof v === 'string' ? codeLabel(v, lang) : String(v);
  }
}
/** Totals of the columns marked for summing (null when nothing to sum). */
export function reportTotals(columns: ReportColumn[], rows: ReportRow[]): Record<string, number> | null {
  const cols = columns.filter((c) => c.s);
  if (!cols.length || !rows.length) return null;
  const out: Record<string, number> = {};
  for (const c of cols) {
    const sum = rows.reduce((a, r) => a + (r[c.k] === null || r[c.k] === undefined ? 0 : Number(r[c.k])), 0);
    out[c.k] = c.t === 'money' ? Math.round(sum * 1000) / 1000 : Math.round(sum * 100) / 100;
  }
  return out;
}
function iso(d: Date): string { return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; }
/** Relative periods stored on a schedule ('PREV_MONTH', 'THIS_MONTH', 'YTD') become real dates on the day it is opened. */
export function resolvePeriod(params: ReportParams, today: Date = new Date()): ReportParams {
  const p = { ...params };
  const period = p.period;
  delete p.period;
  if (!period) return p;
  const y = today.getFullYear(), m = today.getMonth();
  let from: Date, to: Date;
  if (period === 'PREV_MONTH') { from = new Date(y, m - 1, 1); to = new Date(y, m, 0); }
  else if (period === 'YTD') { from = new Date(y, 0, 1); to = today; }
  else { from = new Date(y, m, 1); to = today; }
  p.from = iso(from); p.to = iso(to); p.month = iso(from).slice(0, 7);
  if (period === 'PREV_MONTH') p.as_of = iso(to);
  return p;
}
/** File name such as "AACT_P01_Payroll-register_2026-09.xlsx". */
export function reportFileName(r: Pick<ReportResult, 'code' | 'name_en' | 'entity' | 'meta'>, params: ReportParams, ext: string): string {
  const period = r.meta?.month ?? (params.month as string | undefined) ?? (params.to as string | undefined) ?? (params.as_of as string | undefined) ?? '';
  const slug = r.name_en.replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return [r.entity?.code ?? 'HRMS', r.code, slug, period].filter(Boolean).join('_') + '.' + ext;
}
/** One line describing the filters, for report headers. */
export function filterLine(r: ReportResult, params: ReportParams, lang: Lang, lbl: (k: string) => string): string {
  const parts: string[] = [];
  if (r.meta?.month) parts.push(`${lbl('rp.run')}: ${r.meta.month} · ${r.meta.pay_group ?? ''} · ${codeLabel(r.meta.status ?? '', lang)}`);
  if (params.from && params.to) parts.push(`${ddmmyyyy(String(params.from))} – ${ddmmyyyy(String(params.to))}`);
  else if (params.as_of) parts.push(`${lbl('rp.as_of')} ${ddmmyyyy(String(params.as_of))}`);
  if (params.month && !r.meta?.month && !params.from) parts.push(String(params.month));
  if (r.department) parts.push(lang === 'ar' ? (r.department.name_ar ?? r.department.name_en) : r.department.name_en);
  if (params.pay_group) parts.push(String(params.pay_group));
  if (params.nationality_group) parts.push(codeLabel(params.nationality_group === 'OMANI' ? 'Omani' : 'Expatriate', lang));
  if (params.days) parts.push(`${params.days} ${lbl('rp.days_short')}`);
  return parts.join('  ·  ');
}
