import { rpc, type Json } from './api';
import { parseCsv } from './punches';

// ---------------------------------------------------------------------------
// Phase 7 — privacy (PDPL), statutory reports, executive dashboard, data import
// ---------------------------------------------------------------------------
export interface PrivacyNotice {
  id: string; version: number; title_en: string; title_ar: string; body_en: string; body_ar: string; status: 'DRAFT' | 'PUBLISHED' | 'RETIRED';
  prepared_by_name: string | null; published_by_name: string | null; published_at: string | null; acknowledged: number; updated_at: string;
}
export type ConsentPurpose = 'PHOTO_DIRECTORY' | 'MARKETING_MEDIA' | 'BIOMETRIC' | 'HEALTH_DATA' | 'TRANSFER_ABROAD';
export const CONSENT_PURPOSES: ConsentPurpose[] = ['PHOTO_DIRECTORY', 'MARKETING_MEDIA', 'BIOMETRIC', 'HEALTH_DATA', 'TRANSFER_ABROAD'];
export type DsrKind = 'ACCESS' | 'CORRECTION' | 'ERASURE' | 'RESTRICTION' | 'OBJECTION' | 'PORTABILITY' | 'WITHDRAW_CONSENT' | 'COMPLAINT';
export const DSR_KINDS: DsrKind[] = ['ACCESS', 'CORRECTION', 'ERASURE', 'RESTRICTION', 'OBJECTION', 'PORTABILITY', 'WITHDRAW_CONSENT', 'COMPLAINT'];
export interface MyPrivacy {
  notice: { version: number; title_en: string; title_ar: string; body_en: string; body_ar: string; published_at: string } | null;
  acknowledged_at: string | null; consents: { purpose: ConsentPurpose; given: boolean; given_at: string }[];
  requests: { id: string; ref_no: string; kind: DsrKind; received_on: string; due_on: string; status: DsrStatus; outcome: string | null }[]; dsr_days: number;
}
export interface ConsentRow {
  user_id: string; name: string; name_ar: string | null; employee_no: string | null; employee_id: string | null; notice_version: number | null;
  acknowledged_at: string | null; consents: Partial<Record<ConsentPurpose, boolean>>;
}
export type DsrStatus = 'OPEN' | 'IN_PROGRESS' | 'COMPLETED' | 'REJECTED';
export interface Dsr {
  id: string; ref_no: string; employee_id: string | null; employee_no: string | null; candidate_id: string | null; requester_name: string; contact: string | null;
  kind: DsrKind; details: string; received_on: string; due_on: string; identity_checked: boolean; status: DsrStatus; outcome: string | null;
  days_left: number; overdue: boolean; created_by_name: string | null; closed_by_name: string | null; closed_at: string | null;
}
export type Risk = 'LOW' | 'MEDIUM' | 'HIGH';
export interface Breach {
  id: string; ref_no: string; discovered_at: string; occurred_at: string | null; description: string; data_kinds: string | null; people_affected: number | null;
  risk: Risk; containment: string | null; contained_at: string | null; authority_notified_at: string | null; authority_reference: string | null;
  not_notified_reason: string | null; subjects_notified_at: string | null; status: 'OPEN' | 'CLOSED'; deadline: string; hours_left: number;
  overdue: boolean; notified_late: boolean; created_by_name: string | null; closed_by_name: string | null;
}
export type LegalBasis = 'CONTRACT' | 'LEGAL_OBLIGATION' | 'CONSENT' | 'VITAL_INTEREST' | 'PUBLIC_INTEREST' | 'LEGITIMATE_INTEREST';
export const LEGAL_BASES: LegalBasis[] = ['CONTRACT', 'LEGAL_OBLIGATION', 'CONSENT', 'VITAL_INTEREST', 'PUBLIC_INTEREST', 'LEGITIMATE_INTEREST'];
export interface Activity {
  id: string; code: string; name_en: string; name_ar: string | null; purpose: string; legal_basis: LegalBasis; data_subjects: string; data_categories: string;
  sensitive: boolean; recipients: string | null; transfer_outside_oman: string | null; retention: string | null; security: string | null;
  system_owner: string | null; is_active: boolean; reviewed_at: string | null;
}
export interface RetentionRule { code: string; en: string; ar: string; months: number; basis: string; due?: number | null; action?: 'ANONYMISE' | 'REVIEW' }
export interface RetentionReport { rules: RetentionRule[]; candidates: { id: string; full_name_en: string; nationality: string; updated_at: string }[] }
export interface PdplSettings { dsr_days: number; dsr_legal_basis: string; breach_hours: number; breach_legal_basis: string; controller: string; dpo_name: string | null; dpo_email: string | null; retention: RetentionRule[] }
export interface PdplOverview {
  notice_version: number | null; notice_published_at: string | null; users: number; acknowledged: number; dsr_open: number; dsr_overdue: number;
  breaches_open: number; breaches_overdue: number; activities: number; activities_unreviewed: number; candidates_due: number; settings: Omit<PdplSettings, 'retention'>;
}

export interface OmaniRowLite { total: number; omani: number; pct: number | null; target_pct: number | null; meets_target: boolean | null }
export interface MolReport {
  entity: { id: string; code: string; name_en: string; name_ar: string | null; cr_number: string | null; mol_establishment_no: string | null };
  as_of: string; overall: OmaniRowLite; show_salary: boolean;
  by_profession: { profession_code: string | null; job_en: string; job_ar: string | null; omani_only: boolean; total: number; omani: number; expat: number; pct: number | null; expat_in_omani_only: number }[];
  employees: { employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; nationality: string; gender: string | null; date_of_birth: string | null;
    civil_number: string | null; passport_no: string | null; resident_card_no: string | null; job_en: string; job_ar: string | null; profession_code: string | null; omani_only: boolean;
    department_en: string | null; department_ar: string | null; join_date: string; status: string; contract_type: string | null; contract_end: string | null;
    mol_registration_no: string | null; basic: number | null }[];
}
export interface SpfReport {
  run: { id: string; month: string; status: string; final: boolean };
  entity: { code: string; name_en: string; name_ar: string | null; cr_number: string | null; spf_employer_no: string | null };
  rows: { employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; nationality: string; is_omani: boolean; civil_number: string | null;
    paid_days: number; wage: number | null; lines: Record<string, number>; employee_total: number; employer_total: number }[];
  totals: Record<string, number>; codes: { code: string; name_en: string; name_ar: string; kind: 'DEDUCTION' | 'EMPLOYER' }[];
}
export interface ExecMonth { month: string; headcount: number; joiners: number; leavers: number; omani_pct: number | null; overtime_hours: number; absent_days: number; worked_days: number; payroll_cost: number | null }
export interface ExecDashboard {
  as_of: string; months: ExecMonth[]; show_pay: boolean;
  snapshot: { headcount: number; omani: number; female: number; probation: number; notice: number; avg_tenure_years: number | null; avg_age: number | null };
  by_department: { name_en: string; name_ar: string | null; total: number; omani: number }[];
  by_nationality: { code: string; name_en: string | null; name_ar: string | null; total: number }[];
  risks: { documents_expired: number; documents_30: number; open_positions: number; injuries_ytd: number; lost_days_ytd: number; open_cases: number; exits_open: number; gratuity_liability: number | null };
}
export type ImportKind = 'EMPLOYEES' | 'DOCUMENTS' | 'SALARIES';
export interface ImportResult { batch_id: string; dry_run: boolean; total: number; ok: number; failed: number; results: { row: number; ok: boolean; key: string | null; message?: string; id?: string }[] }
export interface ImportBatch { id: string; kind: ImportKind; file_name: string | null; dry_run: boolean; rows_total: number; rows_ok: number; rows_failed: number; created_by_name: string | null; created_at: string }

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------
export const govapi = {
  overview: () => rpc<PdplOverview>('hr_pdpl_overview'),
  listNotices: () => rpc<PrivacyNotice[]>('hr_list_notices'),
  saveNotice: (p: Json) => rpc<PrivacyNotice>('hr_save_notice', { p }),
  publishNotice: (id: string) => rpc<PrivacyNotice>('hr_publish_notice', { p_id: id }),
  myPrivacy: () => rpc<MyPrivacy>('hr_my_privacy'),
  ackNotice: () => rpc<MyPrivacy>('hr_ack_notice'),
  setConsent: (purpose: ConsentPurpose, given: boolean) => rpc<MyPrivacy>('hr_set_consent', { p_purpose: purpose, p_given: given }),
  listConsents: () => rpc<ConsentRow[]>('hr_list_consents'),
  submitDsr: (kind: DsrKind, details: string) => rpc<MyPrivacy>('hr_submit_dsr', { p_kind: kind, p_details: details }),
  listDsr: (p: Json) => rpc<Dsr[]>('hr_list_dsr', { p }),
  saveDsr: (p: Json) => rpc<Dsr>('hr_save_dsr', { p }),
  closeDsr: (id: string, status: 'COMPLETED' | 'REJECTED', outcome: string) => rpc<Dsr>('hr_close_dsr', { p_id: id, p_status: status, p_outcome: outcome }),
  listBreaches: () => rpc<Breach[]>('hr_list_breaches'),
  saveBreach: (p: Json) => rpc<Breach>('hr_save_breach', { p }),
  closeBreach: (id: string) => rpc<Breach>('hr_close_breach', { p_id: id }),
  listActivities: () => rpc<Activity[]>('hr_list_activities'),
  saveActivity: (p: Json) => rpc<Activity[]>('hr_save_activity', { p }),
  retention: () => rpc<RetentionReport>('hr_retention_report'),
  anonymise: (ids: string[]) => rpc<{ anonymised: number }>('hr_anonymise_candidates', { p_ids: ids }),
  settings: () => rpc<PdplSettings>('hr_pdpl_settings'),
  saveSettings: (p: Json) => rpc<PdplSettings>('hr_save_pdpl_settings', { p }),

  molReport: (entityId: string, asOf: string | null) => rpc<MolReport>('hr_mol_report', { p_entity: entityId, p_as_of: asOf }),
  spfReport: (runId: string) => rpc<SpfReport>('hr_spf_report', { p_run: runId }),
  execDashboard: (entityId: string) => rpc<ExecDashboard>('hr_exec_dashboard', { p_entity: entityId }),

  importRows: (kind: ImportKind, rows: Record<string, string>[], dryRun: boolean, fileName: string | null) =>
    rpc<ImportResult>('hr_import', { p_kind: kind, p_rows: rows, p_dry_run: dryRun, p_file_name: fileName }),
  listImports: () => rpc<ImportBatch[]>('hr_list_imports'),
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
/** Column headings for each import file (first row of the template). */
export const IMPORT_COLUMNS: Record<ImportKind, string[]> = {
  EMPLOYEES: ['employee_no', 'full_name_en', 'full_name_ar', 'nationality', 'gender', 'date_of_birth', 'marital_status', 'civil_number', 'mobile', 'personal_email',
    'work_email', 'join_date', 'probation_end_date', 'company_code', 'department_code', 'job_code', 'grade_code', 'category_code', 'location_code',
    'manager_employee_no', 'employment_type', 'shift_code', 'pay_group'],
  DOCUMENTS: ['employee_no', 'doc_type', 'doc_number', 'issue_date', 'expiry_date', 'issuing_authority', 'issue_place', 'notes'],
  SALARIES: ['employee_no', 'effective_from', 'BASIC', 'HRA', 'EAIR12', 'EAIR24', 'EFOOD', 'ESPL', 'ETRA', 'ESUALL', 'EFLIFT', 'EDUST', 'AUTL', 'notes'],
};
export const IMPORT_EXAMPLE: Record<ImportKind, string[]> = {
  EMPLOYEES: ['9001', 'Example Person', '', 'IN', 'M', '20/05/1990', 'MARRIED', '', '+968 9123 4567', '', '', '01/03/2021', '', 'AACT', 'Plant 1', 'Operator', '', 'NMG', '', '', 'FULL_TIME', '', 'NMG'],
  DOCUMENTS: ['9001', 'PASSPORT', 'Z1234567', '2020-01-10', '2030-01-09', 'Government of India', 'Muscat', ''],
  SALARIES: ['9001', '01/03/2021', '250.000', '60.000', '', '', '', '', '20.000', '', '', '', '', 'Opening salary'],
};

/** Accepts DD/MM/YYYY or YYYY-MM-DD (as Excel often saves either); returns ISO or the original text. */
export function normDate(s: string): string {
  const t = s.trim();
  const m = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/.exec(t);
  if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  return t;
}

/** CSV text → row objects keyed by the (trimmed) heading; date-like columns normalised; empty cells dropped. */
export function csvToRows(text: string): { headers: string[]; rows: Record<string, string>[] } {
  const grid = parseCsv(text);
  if (grid.length === 0) return { headers: [], rows: [] };
  const headers = grid[0].map((h) => h.trim().replace(/^﻿/, ''));
  const rows = grid.slice(1).map((r) => {
    const o: Record<string, string> = {};
    headers.forEach((h, i) => {
      const v = (r[i] ?? '').trim();
      if (h && v !== '') o[h] = /(_date|_from|^date_of_birth)$/.test(h) ? normDate(v) : v;
    });
    return o;
  }).filter((o) => Object.keys(o).length > 0);
  return { headers, rows };
}

/** Required headings missing from an uploaded file ("a|b" = either heading will do; the first is reported). */
export function missingColumns(kind: ImportKind, headers: string[]): string[] {
  const req: Record<ImportKind, string[]> = {
    EMPLOYEES: ['full_name_en', 'nationality', 'join_date', 'department_code|department', 'job_code|designation|job_title', 'category_code|category'],
    DOCUMENTS: ['employee_no', 'doc_type'],
    SALARIES: ['employee_no', 'BASIC'],
  };
  const have = new Set(headers.map((h) => h.toLowerCase()));
  return req[kind].filter((c) => !c.split('|').some((x) => have.has(x.toLowerCase()))).map((c) => c.split('|')[0]);
}

/** Labour turnover for the last 12 months: leavers ÷ average headcount × 100. */
export function turnoverPct(months: Pick<ExecMonth, 'headcount' | 'leavers'>[]): number | null {
  if (!months.length) return null;
  const avg = months.reduce((s, m) => s + m.headcount, 0) / months.length;
  if (avg === 0) return null;
  return Math.round((months.reduce((s, m) => s + m.leavers, 0) / avg) * 1000) / 10;
}

/** Absence rate: absent days ÷ scheduled working days × 100 (1 decimal). */
export function absencePct(m: Pick<ExecMonth, 'absent_days' | 'worked_days'>): number | null {
  return m.worked_days > 0 ? Math.round((m.absent_days / m.worked_days) * 1000) / 10 : null;
}

/** Hours left before the 72-hour deadline, as "2 d 5 h" / "-3 h" text (Arabic units when asked). */
export function hoursText(h: number, lang: 'en' | 'ar' = 'en'): string {
  const [d, hr] = lang === 'ar' ? ['يوم', 'ساعة'] : ['d', 'h'];
  const sign = h < 0 ? '-' : '';
  const a = Math.abs(Math.round(h));
  return a >= 24 ? `${sign}${Math.floor(a / 24)} ${d} ${a % 24} ${hr}` : `${sign}${a} ${hr}`;
}

/** SPF schedule as CSV rows (one row per employee, a column per contribution code). */
export function spfCsv(r: SpfReport): { headers: string[]; rows: (string | number | null)[][] } {
  const codes = r.codes.map((c) => c.code).sort();
  const headers = ['Employee no', 'Name', 'Civil / ID no', 'Nationality', 'Omani', 'Paid days', 'Contribution wage', ...codes, 'Employee total', 'Employer total'];
  const rows = r.rows.map((x) => [x.employee_no, x.full_name_en, x.civil_number, x.nationality, x.is_omani ? 'Y' : 'N', x.paid_days, x.wage,
    ...codes.map((c) => x.lines[c] ?? 0), x.employee_total, x.employer_total]);
  return { headers, rows };
}
