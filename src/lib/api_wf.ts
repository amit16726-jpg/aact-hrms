import { rpc, type Json } from './api';
import type { EmpBrief } from './api_time';

// ---------------------------------------------------------------------------
// Phase 6 — performance, training, discipline, assets, housing & transport, injuries, exit
// ---------------------------------------------------------------------------
export type ReviewStatus = 'SELF' | 'MANAGER' | 'HR' | 'ACK' | 'DONE';
export const REVIEW_STEPS: ReviewStatus[] = ['SELF', 'MANAGER', 'HR', 'ACK', 'DONE'];
export interface Goal { title: string; weight: number | string | null; self_rating?: number | null; rating?: number | null; comment?: string | null }
export interface PerfCycle {
  id: string; entity_id: string; entity_code: string; name: string; period_start: string; period_end: string; due_date: string | null;
  self_review: boolean; status: 'DRAFT' | 'OPEN' | 'CLOSED'; reviews: number; done: number; by_status: Partial<Record<ReviewStatus, number>>;
  avg_rating: number | null; opened_at: string | null; closed_at: string | null;
}
export interface PerfPlan extends EmpBrief {
  id: string; review_id: string | null; issued_on: string; ends_on: string; areas: string; support: string | null;
  status: 'ACTIVE' | 'IMPROVED' | 'NOT_IMPROVED' | 'CANCELLED'; outcome_note: string | null; issued_by_name: string | null;
  closed_by_name: string | null; closed_at: string | null; acknowledged_at: string | null; days_left: number; can_close: boolean; can_ack: boolean;
}
export interface PerfReview extends EmpBrief {
  id: string; cycle_id: string; cycle_name: string; period_start: string; period_end: string; due_date: string | null; cycle_status: PerfCycle['status'];
  reviewer_id: string | null; reviewer_en: string | null; reviewer_ar: string | null; status: ReviewStatus; goals: Goal[];
  self_comments: string | null; manager_comments: string | null; hr_comments: string | null; overall_rating: number | null;
  employee_comment: string | null; acknowledged_at: string | null; is_mine: boolean; is_reviewer: boolean;
  can_self: boolean; can_manager: boolean; can_finalise: boolean; can_ack: boolean; plans?: PerfPlan[];
}

export type CourseCategory = 'SAFETY' | 'TECHNICAL' | 'COMPLIANCE' | 'SOFT_SKILLS' | 'GENERAL';
export const COURSE_CATEGORIES: CourseCategory[] = ['SAFETY', 'TECHNICAL', 'COMPLIANCE', 'SOFT_SKILLS', 'GENERAL'];
export interface Course {
  id: string; code: string; name_en: string; name_ar: string | null; provider: string | null; category: CourseCategory;
  validity_months: number | null; mandatory: boolean; is_active: boolean; completed: number; expiring_60: number;
}
export interface TrainingRecord extends EmpBrief {
  id: string; course_id: string; course_code: string; course_en: string; course_ar: string | null; category: CourseCategory; mandatory: boolean;
  status: 'PLANNED' | 'COMPLETED' | 'CANCELLED'; planned_on: string | null; completed_on: string | null; expires_on: string | null;
  days_left: number | null; certificate_no: string | null; score: string | null; cost: number | null; notes: string | null; superseded: boolean;
}
export interface TrainingGap extends EmpBrief { course_code: string; course_en: string; course_ar: string | null; last_expired: string | null }

export type CaseStatus = 'DRAFT' | 'INVESTIGATION' | 'PROPOSED' | 'DECIDED' | 'DISMISSED';
export type CaseCategory = 'ATTENDANCE' | 'CONDUCT' | 'SAFETY' | 'PERFORMANCE' | 'POLICY' | 'OTHER';
export const CASE_CATEGORIES: CaseCategory[] = ['ATTENDANCE', 'CONDUCT', 'SAFETY', 'PERFORMANCE', 'POLICY', 'OTHER'];
export type Penalty = 'VERBAL_WARNING' | 'WRITTEN_WARNING' | 'FINAL_WARNING' | 'DEDUCTION' | 'SUSPENSION' | 'TERMINATION' | 'NONE';
export const PENALTIES: Penalty[] = ['NONE', 'VERBAL_WARNING', 'WRITTEN_WARNING', 'FINAL_WARNING', 'DEDUCTION', 'SUSPENSION', 'TERMINATION'];
export interface DiscCase extends EmpBrief {
  id: string; ref_no: string; incident_date: string; category: CaseCategory; description: string; status: CaseStatus;
  investigation_notes: string | null; employee_response: string | null; response_at: string | null;
  proposed_penalty: Penalty | null; proposed_days: number | null; proposed_by_name: string | null;
  penalty: Penalty | null; penalty_days: number | null; decided_by_name: string | null; decided_at: string | null; decision_note: string | null;
  adjustment_id: string | null; appeal: string | null; appeal_at: string | null; opened_by_name: string | null; created_at: string;
  can_edit: boolean; can_propose: boolean; can_decide: boolean; can_respond: boolean;
  history?: { ref_no: string; incident_date: string; category: CaseCategory; penalty: Penalty | null; status: CaseStatus }[];
}

export type AssetCategory = 'PPE' | 'UNIFORM' | 'IT' | 'TOOL' | 'VEHICLE' | 'KEY' | 'CARD' | 'OTHER';
export const ASSET_CATEGORIES: AssetCategory[] = ['PPE', 'UNIFORM', 'IT', 'TOOL', 'VEHICLE', 'KEY', 'CARD', 'OTHER'];
export interface AssetItem {
  id: string; code: string; name_en: string; name_ar: string | null; category: AssetCategory; returnable: boolean;
  unit_cost: number | null; replace_months: number | null; is_active: boolean; issued: number;
}
export interface AssetIssue extends EmpBrief {
  id: string; item_id: string; item_code: string; item_en: string; item_ar: string | null; category: AssetCategory; returnable: boolean;
  unit_cost: number | null; qty: number; serial_no: string | null; issued_on: string; due_return_on: string | null;
  status: 'ISSUED' | 'RETURNED' | 'LOST' | 'CONSUMED'; returned_on: string | null; condition: 'GOOD' | 'WORN' | 'DAMAGED' | 'LOST' | null;
  recovery_adjustment_id: string | null; notes: string | null; overdue: boolean; replace_due: string | null; issued_by_name: string | null;
}

export type FacilityKind = 'ACCOMMODATION' | 'TRANSPORT';
export interface Occupant extends EmpBrief { assignment_id: string; place: string | null; from_date: string }
export interface Facility {
  id: string; entity_id: string; entity_code: string; kind: FacilityKind; code: string; name_en: string; name_ar: string | null;
  address: string | null; capacity: number; vehicle_no: string | null; driver_employee_id: string | null; driver_en: string | null;
  is_active: boolean; occupants: Occupant[]; occupied: number;
}

export type Severity = 'FIRST_AID' | 'MEDICAL' | 'LOST_TIME' | 'PERMANENT' | 'FATAL';
export const SEVERITIES: Severity[] = ['FIRST_AID', 'MEDICAL', 'LOST_TIME', 'PERMANENT', 'FATAL'];
export interface Injury extends EmpBrief {
  id: string; ref_no: string; occurred_at: string; location: string; description: string; injury_type: string | null; body_part: string | null;
  severity: Severity; lost_days: number; witnesses: string | null; root_cause: string | null; corrective_action: string | null;
  spf_reported_on: string | null; spf_reference: string | null; status: 'OPEN' | 'CLOSED'; report_due: string; report_overdue: boolean;
  created_by_name: string | null; closed_by_name: string | null; closed_at: string | null; can_edit: boolean;
}

export type ExitType = 'RESIGNATION' | 'TERMINATION' | 'END_OF_CONTRACT' | 'RETIREMENT' | 'OTHER';
export const EXIT_TYPES: ExitType[] = ['RESIGNATION', 'TERMINATION', 'END_OF_CONTRACT', 'RETIREMENT', 'OTHER'];
export interface ExitTask {
  id: string; code: string; title_en: string; title_ar: string; ref_id: string | null; status: 'PENDING' | 'DONE' | 'NOT_NEEDED';
  note: string | null; done_by_name: string | null; done_at: string | null;
}
export interface ExitInterview { reason_code: string | null; would_return: boolean; rating: number | null; comments: string | null; recorded_by: string | null; recorded_at: string }
export interface ExitCase extends EmpBrief {
  id: string; exit_type: ExitType; notice_given_on: string; last_working_date: string; notice_days: number; pay_in_lieu: boolean;
  reason: string | null; non_compete_months: number; status: 'OPEN' | 'COMPLETED' | 'CANCELLED'; interview: ExitInterview | null;
  completed_at: string | null; cancel_reason: string | null; min_notice_days: number; is_omani: boolean; employee_status: string;
  tasks?: ExitTask[]; done?: number; total?: number; settlement: { id: string; status: string; net: number } | null; open_assets: number;
  created_by_name: string | null; completed_by_name: string | null; can_manage: boolean;
}
export interface ExitPreview { employee_id: string; status: string; is_omani: boolean; min_notice_days: number; open_exit: string | null; open_assets: number; facilities: number; contract_end: string | null }
export interface HrPolicies {
  pip_min_months: number; pip_legal_basis: string; notice_monthly_days: number; notice_other_days: number; notice_legal_basis: string;
  non_compete_max_months: number; non_compete_legal_basis: string; discipline_max_deduction_days: number; discipline_max_suspension_days: number;
  discipline_legal_basis: string; injury_report_days: number; injury_legal_basis: string;
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------
export const wfapi = {
  listCycles: () => rpc<PerfCycle[]>('hr_list_perf_cycles'),
  saveCycle: (p: Json) => rpc<PerfCycle[]>('hr_save_perf_cycle', { p }),
  openCycle: (id: string, goals: { title: string; weight: number }[]) => rpc<PerfCycle[]>('hr_open_perf_cycle', { p_id: id, p_goals: goals }),
  closeCycle: (id: string) => rpc<PerfCycle[]>('hr_close_perf_cycle', { p_id: id }),
  listReviews: (p: Json) => rpc<PerfReview[]>('hr_list_perf_reviews', { p }),
  getReview: (id: string) => rpc<PerfReview>('hr_get_perf_review', { p_id: id }),
  saveReview: (id: string, p: Json) => rpc<PerfReview>('hr_save_perf_review', { p_id: id, p }),
  listPlans: () => rpc<PerfPlan[]>('hr_list_perf_plans'),
  issuePlan: (p: Json) => rpc<PerfPlan>('hr_issue_perf_plan', { p }),
  closePlan: (id: string, outcome: PerfPlan['status'], note: string) => rpc<PerfPlan>('hr_close_perf_plan', { p_id: id, p_outcome: outcome, p_note: note }),
  ackPlan: (id: string) => rpc<PerfPlan>('hr_ack_perf_plan', { p_id: id }),

  listCourses: () => rpc<Course[]>('hr_list_courses'),
  saveCourse: (p: Json) => rpc<Course[]>('hr_save_course', { p }),
  listTraining: (p: Json) => rpc<TrainingRecord[]>('hr_list_training', { p }),
  saveTraining: (p: Json) => rpc<{ saved: number }>('hr_save_training', { p }),
  cancelTraining: (id: string) => rpc<{ cancelled: number }>('hr_cancel_training', { p_id: id }),
  trainingGaps: () => rpc<TrainingGap[]>('hr_training_gaps'),

  listCases: (p: Json) => rpc<DiscCase[]>('hr_list_cases', { p }),
  getCase: (id: string) => rpc<DiscCase>('hr_get_case', { p_id: id }),
  saveCase: (p: Json) => rpc<DiscCase>('hr_save_case', { p }),
  caseAction: (id: string, action: 'INVESTIGATE' | 'PROPOSE' | 'DECIDE' | 'RETURN' | 'DISMISS', p: Json = {}) => rpc<DiscCase>('hr_case_action', { p_id: id, p_action: action, p }),
  respondCase: (id: string, text: string) => rpc<DiscCase>('hr_respond_case', { p_id: id, p_text: text }),

  listItems: () => rpc<AssetItem[]>('hr_list_asset_items'),
  saveItem: (p: Json) => rpc<AssetItem[]>('hr_save_asset_item', { p }),
  listIssues: (p: Json) => rpc<AssetIssue[]>('hr_list_asset_issues', { p }),
  issueAsset: (p: Json) => rpc<{ issued: number }>('hr_issue_asset', { p }),
  returnAsset: (id: string, p: Json) => rpc<AssetIssue>('hr_return_asset', { p_id: id, p }),

  listFacilities: (kind: FacilityKind) => rpc<Facility[]>('hr_list_facilities', { p_kind: kind }),
  saveFacility: (p: Json) => rpc<Facility[]>('hr_save_facility', { p }),
  assignFacility: (p: Json) => rpc<Facility[]>('hr_assign_facility', { p }),
  endFacility: (assignmentId: string, to: string | null) => rpc<Facility[]>('hr_end_facility', { p_assignment: assignmentId, p_to: to }),

  listInjuries: (p: Json) => rpc<Injury[]>('hr_list_injuries', { p }),
  saveInjury: (p: Json) => rpc<Injury>('hr_save_injury', { p }),
  closeInjury: (id: string) => rpc<Injury>('hr_close_injury', { p_id: id }),

  listExits: (p: Json) => rpc<ExitCase[]>('hr_list_exits', { p }),
  getExit: (id: string) => rpc<ExitCase>('hr_get_exit', { p_id: id }),
  exitPreview: (employeeId: string) => rpc<ExitPreview>('hr_exit_preview', { p_employee: employeeId }),
  startExit: (p: Json) => rpc<ExitCase>('hr_start_exit', { p }),
  exitTask: (id: string, status: ExitTask['status'], note: string | null) => rpc<ExitCase>('hr_exit_task', { p_id: id, p_status: status, p_note: note }),
  exitInterview: (id: string, p: Json) => rpc<ExitCase>('hr_save_exit_interview', { p_id: id, p }),
  completeExit: (id: string) => rpc<ExitCase>('hr_complete_exit', { p_id: id }),
  cancelExit: (id: string, reason: string) => rpc<ExitCase>('hr_cancel_exit', { p_id: id, p_reason: reason }),

  policies: () => rpc<HrPolicies>('hr_hr_policies'),
  savePolicies: (p: Json) => rpc<HrPolicies>('hr_save_hr_policies', { p }),
};

// ---------------------------------------------------------------------------
// Helpers (mirror the server rules so forms can warn before saving)
// ---------------------------------------------------------------------------
const num = (v: unknown): number | null => (v === null || v === undefined || v === '' || Number.isNaN(Number(v)) ? null : Number(v));

/** Weighted average of the manager's ratings, 2 decimals (same as hr.goals_rating). Null when nothing is rated. */
export function goalsRating(goals: Goal[]): number | null {
  let w = 0; let s = 0;
  for (const g of goals) {
    const r = num(g.rating);
    if (r === null) continue;
    const wt = num(g.weight) ?? 1;
    w += wt; s += wt * r;
  }
  return w === 0 ? null : Math.round((s / w) * 100) / 100;
}

/** ISO date plus whole months, clamped to the month end (2026-08-31 + 6 → 2027-02-28), like Postgres interval arithmetic. */
export function addMonthsIso(iso: string, months: number): string {
  const y = Number(iso.slice(0, 4)); const m = Number(iso.slice(5, 7)) - 1 + months; const d = Number(iso.slice(8, 10));
  const ty = y + Math.floor(m / 12); const tm = ((m % 12) + 12) % 12;
  const last = new Date(Date.UTC(ty, tm + 1, 0)).getUTCDate();
  return `${ty}-${String(tm + 1).padStart(2, '0')}-${String(Math.min(d, last)).padStart(2, '0')}`;
}

/** Days between two ISO dates (b − a). */
export function daysBetween(a: string, b: string): number {
  return Math.round((Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10)) - Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10))) / 86400000);
}

/** Notice check used by the start-exit form (same rule as hr_start_exit). */
export function noticeCheck(o: { type: ExitType; given: string; last: string; minDays: number; payInLieu: boolean; onProbation: boolean }): { days: number; short: boolean } {
  const days = o.given && o.last ? daysBetween(o.given, o.last) : 0;
  const applies = (o.type === 'RESIGNATION' || o.type === 'TERMINATION') && !o.payInLieu && !o.onProbation;
  return { days, short: applies && days < o.minDays };
}

/** Clearance progress: closed steps / all steps. */
export function exitProgress(tasks: Pick<ExitTask, 'status'>[]): { done: number; total: number; pct: number } {
  const total = tasks.length; const done = tasks.filter((x) => x.status !== 'PENDING').length;
  return { done, total, pct: total ? Math.round((done / total) * 100) : 0 };
}

/** Amount for a disciplinary deduction of n days (gross ÷ 30 per day, 3 decimals). */
export function deductionAmount(monthlyGross: number, days: number): number {
  return Math.round((Math.round((monthlyGross / 30) * 1000) / 1000) * days * 1000) / 1000;
}
