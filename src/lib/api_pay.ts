import { rpc, type Json } from './api';
import type { EmpBrief, TimeRule } from './api_time';

// ---------------------------------------------------------------------------
// Phase 3 — payroll & end of service: types returned by the server
// ---------------------------------------------------------------------------
export type PayRuleCode = 'SPF_OMANI' | 'SPF_EXPAT' | 'GRATUITY' | 'SAVINGS_EXPAT' | 'DEDUCTIONS' | 'INCOME_TAX' | 'PAY_BASIS';
export interface PayRule extends Omit<TimeRule, 'code'> { code: PayRuleCode }

export type RunStatus = 'DRAFT' | 'CALCULATED' | 'VERIFIED' | 'APPROVED' | 'PAID';
export interface RunTotals {
  employees?: number; earnings?: number; deductions?: number; net?: number; employer_cost?: number; basic?: number;
  spf_employee?: number; spf_employer?: number; overtime?: number; eosb?: number; loans?: number; omani?: number; expat?: number;
}
export interface PayrollRun {
  id: string; entity_id: string; period_start: string; month: string; pay_date: string | null; status: RunStatus; calc_count: number;
  calculated_at: string | null; verified_at: string | null; approved_at: string | null; paid_at: string | null;
  calculated_by_name: string | null; verified_by_name: string | null; approved_by_name: string | null; paid_by_name: string | null;
  return_note: string | null; reopen_reason: string | null; notes: string | null; totals: RunTotals; warning_count: number;
  entity_code: string; entity_en: string; entity_ar: string | null; attendance_locked: boolean;
  pay_group?: 'NMG' | 'MG';
  can_calculate: boolean; can_verify: boolean; can_approve: boolean; can_return: boolean; can_pay: boolean; can_reopen: boolean; can_export_bank: boolean;
}
export interface PayslipBrief {
  id: string; run_id: string; employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null;
  department_en: string | null; department_ar: string | null; job_en: string | null; job_ar: string | null; cost_centre: string | null;
  nationality: string; is_omani: boolean; days_in_period: number; employed_days: number; paid_days: number; unpaid_days: number;
  basic: number; gross_fixed: number; total_earnings: number; total_deductions: number; employer_cost: number; net: number;
  bank_name: string | null; swift_code: string | null; account_masked: string | null; has_bank: boolean; warnings: string[];
}
export interface PayLine {
  id: string; code: string; name_en: string; name_ar: string; kind: 'EARNING' | 'DEDUCTION' | 'EMPLOYER'; amount: number;
  qty: number | null; rate: number | null; gl_account: string | null; ref_id: string | null; sort: number;
}
export interface Payslip extends PayslipBrief {
  account_number: string | null; iban: string | null; month: string; period_start: string; pay_date: string | null; run_status: RunStatus;
  entity_en: string; entity_ar: string | null; entity_cr: string | null; lines: PayLine[];
}
export interface CodeTotal { code: string; name_en: string; name_ar: string; kind: PayLine['kind']; amount: number; employees: number; sort: number }
export interface RunDetail extends PayrollRun {
  payslips: PayslipBrief[]; by_code: CodeTotal[]; pending_inputs: { adjustments: number; loans: number };
}
export interface MyPayslip { id: string; month: string; pay_date: string | null; status: RunStatus; net: number; total_earnings: number; total_deductions: number }

export interface Loan extends EmpBrief {
  id: string; kind: 'LOAN' | 'ADVANCE'; amount: number; installment: number; first_month: string; reason: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED' | 'CLOSED' | 'CANCELLED'; proposed_at: string; decided_at: string | null; decision_note: string | null;
  repaid: number; outstanding: number; months_left: number | null; proposed_by_name: string | null; decided_by_name: string | null;
  can_decide: boolean; can_cancel: boolean; repayments: { month: string; amount: number; kind: 'PAYROLL' | 'SETTLEMENT' }[];
}
export type AdjCode = 'BONUS' | 'COMMISSION' | 'ARREARS' | 'ALLOWANCE' | 'OTHER_EARN' | 'PENALTY' | 'DAMAGE' | 'OTHER_DED';
export interface PayAdjustment extends EmpBrief {
  id: string; period_start: string; month: string; kind: 'EARNING' | 'DEDUCTION'; code: AdjCode; amount: number; reason: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED'; proposed_at: string; decided_at: string | null; decision_note: string | null;
  proposed_by_name: string | null; decided_by_name: string | null; can_decide: boolean;
}
export interface GratuityDetail {
  applies: boolean; total: number; service_days: number; old_years: number; new_years: number; old_amount: number; new_amount: number;
  basic?: number; cutoff?: string; below_minimum?: boolean;
}
export interface SettlementOther { label: string; kind: 'EARNING' | 'DEDUCTION'; amount: string }
export interface SettlementCalc {
  employee_id: string; last_working_date: string; basic: number; gross: number; gratuity: number; gratuity_detail: GratuityDetail;
  leave_days: number; leave_partial_accrual: number; leave_pay: number; notice_days: number; notice_pay: number; loan_recovery: number;
  loans: { id: string; kind: string; outstanding: number }[]; other_earnings: number; other_deductions: number; other: SettlementOther[];
  net: number; daily_gross: number; warnings: string[];
}
export type SettlementReason = 'RESIGNATION' | 'TERMINATION' | 'END_OF_CONTRACT' | 'RETIREMENT' | 'DEATH' | 'OTHER';
export interface Settlement extends EmpBrief {
  id: string; last_working_date: string; reason: SettlementReason; notice_days: number; basic: number; gross: number; gratuity: number;
  leave_days: number; leave_pay: number; notice_pay: number; loan_recovery: number; other_earnings: number; other_deductions: number;
  net: number; details: SettlementCalc; note: string | null; status: 'PREPARED' | 'APPROVED' | 'PAID' | 'CANCELLED';
  prepared_at: string; approved_at: string | null; paid_at: string | null; decision_note: string | null;
  join_date: string; nationality: string; civil_number: string | null; job_en: string | null; job_ar: string | null;
  entity_en: string; entity_ar: string | null; prepared_by_name: string | null; approved_by_name: string | null;
  can_decide: boolean; can_cancel: boolean; can_pay: boolean;
}
export interface SettlementPreview extends EmpBrief, SettlementCalc { join_date: string; nationality: string }
export interface GratuityRow extends EmpBrief, GratuityDetail { join_date: string; nationality: string; status: string }

export interface PayrollSetup {
  entities: { id: string; code: string; name_en: string; name_ar: string | null; cr_number: string | null; spf_employer_no: string | null;
    wps_bank_code: string | null; wps_account: string | null; wps_payer_cr: string | null }[];
  components: { code: string; name_en: string; name_ar: string; kind: 'EARNING' | 'DEDUCTION'; is_basic: boolean; gl_account: string | null;
    spf_base: boolean; is_active: boolean }[];
  gl: Record<string, string>;
  pay_day: string | null;
}
export interface WpsData {
  employer_cr: string | null; payer_cr: string | null; bank_code: string | null; account: string | null; year: number; month: number; pay_date: string | null;
  rows: { employee_no: string; id_type: 'C' | 'P'; id: string; name: string; bank: string | null; account: string | null; days: number; net: number;
    basic: number; extra_hours: number; extra_income: number; deductions: number; social_security: number; has_bank: boolean }[];
}
export interface JournalData {
  month: string; status: RunStatus; gl: Record<string, string>; net: number; employer_cost: number; spf_employer: number; eosb: number;
  lines: { account: string; cost_centre: string; code: string; name: string; kind: PayLine['kind']; side: 'DR' | 'CR'; amount: number }[];
}
export interface RegisterData {
  month: string; codes: { code: string; name_en: string; kind: PayLine['kind']; sort: number }[];
  rows: { employee_no: string; name: string; department: string | null; paid_days: number; unpaid_days: number; earnings: number;
    deductions: number; net: number; employer_cost: number; amounts: Record<string, number> | null }[];
}
export interface SpfData {
  month: string; employer_no: string | null;
  rows: { employee_no: string; name: string; civil_number: string | null; is_omani: boolean; wage: number | null; employee: number; employer: number;
    lines: Record<string, number> | null }[];
}
export interface ParallelReport {
  loaded: number;
  rows: { employee_no: string; name: string | null; system_gross: number | null; system_net: number | null; legacy_gross: number | null;
    legacy_net: number | null; diff: number | null; status: 'MATCH' | 'DIFF' | 'ONLY_LEGACY' | 'ONLY_SYSTEM'; note: string | null }[];
}
export interface EmployeePayroll { payslips: MyPayslip[]; loans: Loan[]; gratuity: GratuityDetail | null }

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------
export const papi = {
  listPayRules: () => rpc<PayRule[]>('hr_list_pay_rules'),
  proposePayRule: (p: Json) => rpc<PayRule[]>('hr_propose_pay_rule', { p }),
  decidePayRule: (id: string, approve: boolean, note: string | null) => rpc<PayRule[]>('hr_decide_pay_rule', { p_id: id, p_approve: approve, p_note: note }),

  setup: () => rpc<PayrollSetup>('hr_payroll_setup'),
  saveSetup: (p: Json) => rpc<PayrollSetup>('hr_save_payroll_setup', { p }),

  listRuns: (entityId: string | null, year: number | null) => rpc<PayrollRun[]>('hr_list_payroll_runs', { p_entity: entityId, p_year: year }),
  createRun: (entityId: string, month: string, payDate: string | null, payGroup: 'NMG' | 'MG' = 'NMG') =>
    rpc<PayrollRun>('hr_create_payroll_run', { p_entity: entityId, p_month: month, p_pay_date: payDate, p_pay_group: payGroup }),
  calculate: (id: string) => rpc<PayrollRun>('hr_calculate_payroll', { p_run: id }),
  verify: (id: string, note: string | null) => rpc<PayrollRun>('hr_verify_payroll', { p_run: id, p_note: note }),
  approve: (id: string, note: string | null) => rpc<PayrollRun>('hr_approve_payroll', { p_run: id, p_note: note }),
  returnRun: (id: string, note: string) => rpc<PayrollRun>('hr_return_payroll', { p_run: id, p_note: note }),
  markPaid: (id: string) => rpc<PayrollRun>('hr_mark_payroll_paid', { p_run: id }),
  reopen: (id: string, reason: string) => rpc<PayrollRun>('hr_reopen_payroll', { p_run: id, p_reason: reason }),
  getRun: (id: string) => rpc<RunDetail>('hr_get_payroll_run', { p_run: id }),
  getPayslip: (id: string) => rpc<Payslip>('hr_get_payslip', { p_id: id }),
  myPayslips: () => rpc<MyPayslip[]>('hr_my_payslips'),
  employeePayroll: (employeeId: string) => rpc<EmployeePayroll>('hr_employee_payroll', { p_employee: employeeId }),
  exportWps: (id: string) => rpc<WpsData>('hr_payroll_export', { p_run: id, p_kind: 'WPS' }),
  exportJournal: (id: string) => rpc<JournalData>('hr_payroll_export', { p_run: id, p_kind: 'JOURNAL' }),
  exportRegister: (id: string) => rpc<RegisterData>('hr_payroll_export', { p_run: id, p_kind: 'REGISTER' }),
  exportSpf: (id: string) => rpc<SpfData>('hr_payroll_export', { p_run: id, p_kind: 'SPF' }),
  saveParallel: (id: string, rows: Json[], replace: boolean) =>
    rpc<{ loaded: number; errors: { row: number; message: string }[] }>('hr_save_parallel', { p_run: id, p: { rows, replace } }),
  parallelReport: (id: string) => rpc<ParallelReport>('hr_parallel_report', { p_run: id }),

  listLoans: (p: Json) => rpc<Loan[]>('hr_list_loans', { p }),
  proposeLoan: (p: Json) => rpc<Loan>('hr_propose_loan', { p }),
  decideLoan: (id: string, approve: boolean, note: string | null) => rpc<Loan>('hr_decide_loan', { p_id: id, p_approve: approve, p_note: note }),
  cancelLoan: (id: string, reason: string | null) => rpc<Loan>('hr_cancel_loan', { p_id: id, p_reason: reason }),

  listAdjustments: (p: Json) => rpc<PayAdjustment[]>('hr_list_pay_adjustments', { p }),
  proposeAdjustments: (rows: Json[]) => rpc<{ proposed: number; errors: { row: number; message: string }[] }>('hr_propose_pay_adjustments', { p: { rows } }),
  decideAdjustments: (ids: string[], approve: boolean, note: string | null) =>
    rpc<{ decided: number }>('hr_decide_pay_adjustments', { p_ids: ids, p_approve: approve, p_note: note }),

  previewSettlement: (p: Json) => rpc<SettlementPreview>('hr_preview_settlement', { p }),
  saveSettlement: (p: Json) => rpc<Settlement>('hr_save_settlement', { p }),
  decideSettlement: (id: string, approve: boolean, note: string | null) => rpc<Settlement>('hr_decide_settlement', { p_id: id, p_approve: approve, p_note: note }),
  cancelSettlement: (id: string, reason: string | null) => rpc<Settlement>('hr_cancel_settlement', { p_id: id, p_reason: reason }),
  markSettlementPaid: (id: string) => rpc<Settlement>('hr_mark_settlement_paid', { p_id: id }),
  listSettlements: (p: Json) => rpc<Settlement[]>('hr_list_settlements', { p }),
  getSettlement: (id: string) => rpc<Settlement>('hr_get_settlement', { p_id: id }),

  gratuityReport: (entityId: string | null, asOf: string | null) => rpc<{ as_of: string; rows: GratuityRow[] }>('hr_gratuity_report', { p_entity: entityId, p_as_of: asOf }),
};

// ---------------------------------------------------------------------------
// WPS salary information file (Central Bank of Oman SIF layout; AACT's bank template governs — check with the bank)
// ---------------------------------------------------------------------------
const csvCell = (v: unknown) => { const s = v === null || v === undefined ? '' : String(v); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
const money = (n: number) => (Math.round(n * 1000) / 1000).toFixed(3);

export function buildWpsSif(d: WpsData): { name: string; text: string; skipped: string[] } {
  const ok = d.rows.filter((r) => r.has_bank && r.account);
  const skipped = d.rows.filter((r) => !(r.has_bank && r.account)).map((r) => r.employee_no);
  const total = ok.reduce((s, r) => s + r.net, 0);
  const head = ['Employer CR-NO', 'Payer CR-NO', 'Payer Bank Short Name', 'Payer Account Number', 'Salary Year', 'Salary Month',
    'Total Salaries', 'Number Of Records', 'Payment Type'];
  const emp = [d.employer_cr ?? '', d.payer_cr ?? '', d.bank_code ?? '', d.account ?? '', d.year, String(d.month).padStart(2, '0'),
    money(total), ok.length, 'Salary'];
  const colHead = ['Employee ID Type', 'Employee ID', 'Reference Number', 'Employee Name', 'Employee BIC Code', 'Employee Account',
    'Salary Frequency', 'Number Of Working days', 'Net Salary', 'Basic Salary', 'Extra Hours', 'Extra Income', 'Deductions',
    'Social Security Deductions', 'Notes / Comments'];
  const lines = [head, emp, colHead, ...ok.map((r) => [r.id_type, r.id, r.employee_no, r.name, r.bank ?? '', r.account ?? '', 'M',
    Math.round(r.days), money(r.net), money(r.basic), r.extra_hours, money(r.extra_income), money(r.deductions), money(r.social_security), ''])];
  const date = (d.pay_date ?? `${d.year}-${String(d.month).padStart(2, '0')}-01`).replace(/-/g, '');
  return { name: `SIF_${d.employer_cr ?? 'CR'}_${d.bank_code ?? 'BANK'}_${date}_001.csv`, text: lines.map((l) => l.map(csvCell).join(',')).join('\r\n') + '\r\n', skipped };
}

/** Bank files are sent without a byte-order mark (some bank portals reject it). */
export function downloadText(name: string, text: string, bom = false): void {
  const blob = new Blob([(bom ? '\ufeff' : '') + text], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
