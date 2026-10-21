import { rpc, type Json } from './api';
import type { ChangeReq, Letter } from './api_ss';
import type { Interview, Offer, Requisition } from './api_rec';
import type { Loan, PayAdjustment, PayRule, PayrollRun, Settlement } from './api_pay';

// ---------------------------------------------------------------------------
// Phase 2 — attendance & leave: types returned by the server
// ---------------------------------------------------------------------------
export interface EmpBrief {
  employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; entity_id: string;
  department_en: string | null; department_ar: string | null;
}

export type RuleCode = 'WORK_HOURS' | 'RAMADAN_HOURS' | 'WEEKLY_REST' | 'OVERTIME' | 'OVERTIME_NO_CONSENT' | 'ATTENDANCE';
export interface TimeRule {
  id: string; code: RuleCode; value: Record<string, number | string>; effective_from: string; effective_to: string | null;
  rule_basis: 'LEGAL' | 'COMPANY_POLICY'; legal_basis: string; status: 'PENDING' | 'APPROVED' | 'REJECTED';
  proposed_by_name: string | null; proposed_at: string; decided_by_name: string | null; decided_at: string | null;
  decision_note: string | null; can_decide: boolean;
}

export interface Shift {
  id: string; entity_id: string; code: string; name_en: string; name_ar: string | null; start_time: string; end_time: string;
  break_minutes: number; grace_minutes: number | null; rest_days: number[]; is_ramadan: boolean; notes: string | null;
  is_active: boolean; net_minutes: number; weekly_minutes: number; crosses_midnight: boolean; assigned: number;
}
export interface ShiftAssignment extends EmpBrief {
  id: string; shift_id: string; shift_code: string; shift_name_en: string; shift_name_ar: string | null;
  effective_from: string; effective_to: string | null; notes: string | null; created_by_name: string | null; created_at: string;
}

export interface Holiday {
  id: string; entity_id: string | null; holiday_date: string; name_en: string; name_ar: string | null; kind: 'PUBLIC' | 'COMPANY';
  source_reference: string | null; is_active: boolean; created_by_name: string | null;
}
export interface RamadanPeriod { id: string; start_date: string; end_date: string; name_en: string; name_ar: string | null; notes: string | null }

export type AttStatus = 'PRESENT' | 'ABSENT' | 'LEAVE' | 'HOLIDAY' | 'REST' | 'MISSING_PUNCH' | 'NO_SHIFT';
export interface AttDay {
  employee_id: string; work_date: string; status: AttStatus; shift_id: string | null; shift_code: string | null;
  shift_name_en: string | null; shift_name_ar: string | null; sched_start: string | null; sched_end: string | null;
  sched_minutes: number; first_in: string | null; last_out: string | null; punch_count: number; worked_minutes: number;
  late_minutes: number; early_minutes: number; extra_minutes: number; leave_type: string | null; leave_name_en: string | null;
  leave_name_ar: string | null; leave_fraction: number; worked_off_day: boolean; is_ramadan: boolean;
  holiday_en: string | null; holiday_ar: string | null; pending_correction: boolean; overtime_minutes: number; locked: boolean;
}
export type AttRow = AttDay & EmpBrief;
export interface AttDayView {
  date: string; rows: AttRow[];
  counts: { present: number; absent: number; missing: number; late: number; leave: number; off: number; no_shift: number };
}
export interface AttMonth extends EmpBrief {
  month: string; locked: boolean; days: AttDay[]; shift: Shift | null;
  totals: { scheduled_days: number; present: number; absent: number; missing: number; leave_days: number; late_count: number;
    late_minutes: number; worked_minutes: number; worked_off_days: number };
}
export interface GridRow extends EmpBrief {
  days: Record<string, string> | null; present: number; absent: number; missing: number; late: number; leave: number;
}
export interface AttGrid { month: string; days_in_month: number; locked: boolean; rows: GridRow[] }
export interface SummaryRow extends EmpBrief {
  scheduled_days: number; present_days: number; absent_days: number; missing_punch_days: number; late_minutes: number;
  holidays: number; leave: Record<string, number>; unpaid_leave_days: number; ot_pay_hours: number; ot_pay_days: number;
  ot_time_off_requests: number;
}

export type ReqStatus = 'PENDING_MANAGER' | 'PENDING_HR' | 'APPROVED' | 'REJECTED' | 'CANCELLED';
export interface Correction extends EmpBrief {
  id: string; work_date: string; punch_in: string | null; punch_out: string | null; out_next_day: boolean; reason: string;
  status: ReqStatus; requested_by_name: string | null; requested_at: string; manager_decided_by_name: string | null;
  decided_by_name: string | null; decided_at: string | null; decision_note: string | null; can_decide: boolean; can_cancel: boolean;
}
export interface Overtime extends EmpBrief {
  id: string; work_date: string; start_time: string; end_time: string; end_next_day: boolean; minutes: number; day_minutes: number;
  night_minutes: number; day_kind: 'WORKDAY' | 'REST_DAY' | 'HOLIDAY'; basis: 'CONSENT' | 'INVENTORY' | 'EMERGENCY';
  employee_consent: boolean; comp_choice: 'PAY' | 'TIME_OFF'; rates: Record<string, number | string>; pay_hours: number;
  pay_days: number; reason: string; authority_notified: boolean; status: ReqStatus; requested_by_name: string | null;
  requested_at: string; decided_by_name: string | null; decided_at: string | null; decision_note: string | null;
  can_decide: boolean; can_cancel: boolean;
}

export interface Period {
  month: string; period_start: string; status: 'OPEN' | 'LOCKED'; locked_by_name: string | null; locked_at: string | null;
  unlocked_by_name: string | null; unlocked_at: string | null; unlock_reason: string | null; can_lock: boolean; pending: number;
}
export interface PunchBatch {
  id: string; entity_id: string | null; file_name: string | null; ref_kind: string; rows_total: number; rows_imported: number;
  rows_duplicate: number; rows_error: number; error_count?: number; errors?: { row: number; ref: string | null; message: string }[];
  date_from: string | null; date_to: string | null; created_by_name: string | null; created_at: string;
}
export interface DeviceUser extends EmpBrief { device_code: string; device_user_id: string }
export interface Punch { id: string; time: string; date: string; direction: 'IN' | 'OUT' | null; source: string }

export interface LeaveType {
  code: string; name_en: string; name_ar: string; category: 'STATUTORY' | 'COMPANY'; pay_mode: 'FULL' | 'TIERED' | 'UNPAID';
  pay_tiers: { from: number; to: number; pct: number }[]; paid_by: 'EMPLOYER' | 'FUND' | 'NONE'; quota_days: number | null;
  legal_min_days: number | null; quota_period: 'YEAR' | 'EVENT' | 'ONCE' | 'NONE'; accrual: 'MONTHLY' | 'NONE';
  count_mode: 'CALENDAR' | 'CALENDAR_EXCL_HOLIDAYS' | 'WORKING'; min_service_months: number; carry_forward_max: number | null;
  gender: 'ALL' | 'M' | 'F'; nationality: 'ALL' | 'OMANI' | 'EXPAT'; requires_document: boolean; needs_event_date: boolean;
  event_window_days: number | null; max_before_event_days: number | null; allow_half_day: boolean; allow_negative: boolean;
  ticket_eligible: boolean; rule_basis: 'LEGAL' | 'COMPANY_POLICY'; legal_basis: string | null; notes: string | null;
  sort: number; is_active: boolean;
}
export interface Balance {
  leave_type: string; name_en: string; name_ar: string; quota_period: LeaveType['quota_period']; accrual: LeaveType['accrual'];
  quota_days: number | null; entitled: number | null; used: number; pending: number; available: number | null; as_of: string;
  pay_mode: LeaveType['pay_mode']; requires_document: boolean; needs_event_date: boolean; allow_half_day: boolean;
  ticket_eligible: boolean; min_service_months: number; max_before_event_days: number | null; event_window_days: number | null;
  eligible_from: string;
}
export interface LedgerRow { entry_date: string; leave_type: string; days: number; kind: string; note: string | null }
export interface Balances extends EmpBrief {
  as_of: string; gender: 'M' | 'F' | null; is_omani: boolean; join_date: string; balances: Balance[];
  annual_taken_24m: number; ledger: LedgerRow[];
}
export interface BalanceRow extends EmpBrief, Omit<Balance, 'requires_document' | 'needs_event_date' | 'allow_half_day' | 'ticket_eligible' | 'min_service_months' | 'max_before_event_days' | 'event_window_days' | 'eligible_from' | 'pay_mode'> {
  join_date: string; status: string; taken_24m: number; two_year_rule_due: boolean;
}
export interface LeaveReq extends EmpBrief {
  id: string; leave_type: string; name_en: string; name_ar: string; pay_mode: LeaveType['pay_mode']; start_date: string;
  end_date: string; half_day: boolean; days: number; event_date: string | null; reason: string | null; document_id: string | null;
  requires_document: boolean; document_name: string | null; status: ReqStatus; pay_breakdown: { pct: number; days: number }[] | null;
  ticket_requested: boolean; ticket_status: 'NONE' | 'REQUESTED' | 'ISSUED' | 'CASH' | 'DECLINED';
  requested_by_name: string | null; requested_at: string; manager_decided_by_name: string | null; manager_decided_at: string | null;
  manager_note: string | null; decided_by_name: string | null; decided_at: string | null; decision_note: string | null;
  cancelled_by_name: string | null; cancelled_at: string | null; cancel_reason: string | null;
  can_decide: boolean; can_cancel: boolean; can_attach: boolean; balance: Balance | null;
}
export interface LeaveCalRow extends EmpBrief {
  leave: { id: string; leave_type: string; name_en: string; name_ar: string; status: ReqStatus; half_day: boolean; from_day: number; to_day: number }[] | null;
}
export interface LeaveCal { month: string; days_in_month: number; holidays: { day: number; name_en: string; name_ar: string | null }[]; rows: LeaveCalRow[] }
export interface Adjustment extends EmpBrief {
  id: string; leave_type: string; name_en: string; name_ar: string; kind: 'OPENING' | 'ADJUSTMENT'; days: number; effective_date: string;
  reason: string; status: 'PENDING' | 'APPROVED' | 'REJECTED'; proposed_by_name: string | null; proposed_at: string;
  decided_by_name: string | null; decided_at: string | null; decision_note: string | null; can_decide: boolean;
}
export interface MyTasks {
  leave: LeaveReq[]; corrections: Correction[]; overtime: Overtime[]; adjustments: Adjustment[]; rules: TimeRule[]; count: number;
  pay_rules: PayRule[]; payroll: PayrollRun[]; loans: Loan[]; pay_adjustments: PayAdjustment[]; settlements: Settlement[];
  changes?: ChangeReq[]; letters?: Letter[]; requisitions?: Requisition[]; offers?: Offer[]; interviews?: Interview[];
}
export interface TimeDash {
  today?: { date: string; present: number; absent: number; missing: number; late: number; leave: number; off: number; scope: 'ALL' | 'TEAM' };
  away_next_14?: (EmpBrief & { leave_type: string; name_en: string; name_ar: string; start_date: string; end_date: string; status: ReqStatus })[];
  mine?: { today: AttDay | null; annual: Balance | null; sick: Balance | null; pending: number;
    next_leave: { leave_type: string; name_en: string; name_ar: string; start_date: string; end_date: string; status: ReqStatus } | null;
    last_payslip?: { id: string; month: string; net: number } | null; requests_open?: number; letters_ready?: number };
  tasks: { leave: number; corrections: number; overtime: number; adjustments: number; rules: number; count: number;
    payroll?: number; loans?: number; pay_adjustments?: number; settlements?: number; changes?: number; letters?: number;
    requisitions?: number; offers?: number; interviews?: number };
  payroll?: PayrollRun | null;
  recruitment?: { open_requisitions: number; open_positions: number; in_pipeline: number; joining_30: number; onboarding_overdue: number; probation_due_30: number };
}

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------
export const tapi = {
  listTimeRules: () => rpc<TimeRule[]>('hr_list_time_rules'),
  proposeTimeRule: (p: Json) => rpc<TimeRule[]>('hr_propose_time_rule', { p }),
  decideTimeRule: (id: string, approve: boolean, note: string | null) => rpc<TimeRule[]>('hr_decide_time_rule', { p_id: id, p_approve: approve, p_note: note }),

  listShifts: (entityId: string | null) => rpc<Shift[]>('hr_list_shifts', { p_entity: entityId }),
  saveShift: (p: Json) => rpc<Shift>('hr_save_shift', { p }),
  listShiftAssignments: (p: Json) => rpc<ShiftAssignment[]>('hr_list_shift_assignments', { p }),
  assignShift: (p: Json) => rpc<{ assigned: number }>('hr_assign_shift', { p }),

  listHolidays: (year: number, entityId: string | null) => rpc<{ holidays: Holiday[]; ramadan: RamadanPeriod[] }>('hr_list_holidays', { p_year: year, p_entity: entityId }),
  saveHoliday: (p: Json) => rpc<{ holidays: Holiday[]; ramadan: RamadanPeriod[] }>('hr_save_holiday', { p }),
  saveRamadan: (p: Json) => rpc<{ holidays: Holiday[]; ramadan: RamadanPeriod[] }>('hr_save_special_period', { p }),

  listDeviceUsers: (entityId: string | null) => rpc<DeviceUser[]>('hr_list_device_users', { p_entity: entityId }),
  setDeviceUser: (p: Json) => rpc<DeviceUser[]>('hr_set_device_user', { p }),
  importPunches: (p: Json) => rpc<PunchBatch>('hr_import_punches', { p }),
  listPunchBatches: (entityId: string | null) => rpc<PunchBatch[]>('hr_list_punch_batches', { p_entity: entityId }),
  listPunches: (employeeId: string, date: string) => rpc<Punch[]>('hr_list_punches', { p_employee: employeeId, p_date: date }),
  recompute: (p: Json) => rpc<{ days: number }>('hr_recompute_attendance', { p }),

  attendanceDay: (p: Json) => rpc<AttDayView>('hr_attendance_day', { p }),
  attendanceMonth: (employeeId: string, month: string) => rpc<AttMonth>('hr_attendance_month', { p_employee: employeeId, p_month: month }),
  attendanceGrid: (p: Json) => rpc<AttGrid>('hr_attendance_grid', { p }),
  attendanceSummary: (p: Json) => rpc<{ month: string; locked: boolean; rows: SummaryRow[] }>('hr_attendance_summary', { p }),

  requestCorrection: (p: Json) => rpc<Correction>('hr_request_correction', { p }),
  decideCorrection: (id: string, approve: boolean, note: string | null) => rpc<Correction>('hr_decide_correction', { p_id: id, p_approve: approve, p_note: note }),
  cancelCorrection: (id: string) => rpc<Correction>('hr_cancel_correction', { p_id: id }),
  listCorrections: (p: Json) => rpc<Correction[]>('hr_list_corrections', { p }),

  requestOvertime: (p: Json) => rpc<Overtime>('hr_request_overtime', { p }),
  decideOvertime: (id: string, approve: boolean, note: string | null) => rpc<Overtime>('hr_decide_overtime', { p_id: id, p_approve: approve, p_note: note }),
  cancelOvertime: (id: string) => rpc<Overtime>('hr_cancel_overtime', { p_id: id }),
  setOvertimeNotified: (id: string) => rpc<Overtime>('hr_set_overtime_notified', { p_id: id }),
  listOvertime: (p: Json) => rpc<Overtime[]>('hr_list_overtime', { p }),

  listPeriods: (entityId: string, year: number) => rpc<Period[]>('hr_list_periods', { p_entity: entityId, p_year: year }),
  lockPeriod: (entityId: string, month: string) => rpc<Period[]>('hr_lock_period', { p_entity: entityId, p_month: month }),
  unlockPeriod: (entityId: string, month: string, reason: string) => rpc<Period[]>('hr_unlock_period', { p_entity: entityId, p_month: month, p_reason: reason }),

  listLeaveTypes: () => rpc<LeaveType[]>('hr_list_leave_types'),
  saveLeaveType: (p: Json) => rpc<LeaveType>('hr_save_leave_type', { p }),
  leaveBalances: (employeeId: string, on?: string | null) => rpc<Balances>('hr_leave_balances', { p_employee: employeeId, p_on: on ?? null }),
  listLeaveBalances: (p: Json) => rpc<BalanceRow[]>('hr_list_leave_balances', { p }),
  requestLeave: (p: Json) => rpc<LeaveReq>('hr_request_leave', { p }),
  attachLeaveDocument: (id: string, p: Json) => rpc<LeaveReq>('hr_attach_leave_document', { p_request: id, p }),
  decideLeave: (id: string, approve: boolean, note: string | null) => rpc<LeaveReq>('hr_decide_leave', { p_id: id, p_approve: approve, p_note: note }),
  cancelLeave: (id: string, reason: string | null) => rpc<LeaveReq>('hr_cancel_leave', { p_id: id, p_reason: reason }),
  setTicketStatus: (id: string, status: string) => rpc<LeaveReq>('hr_set_ticket_status', { p_id: id, p_status: status }),
  listLeaveRequests: (p: Json) => rpc<{ total: number; rows: LeaveReq[] }>('hr_list_leave_requests', { p }),
  leaveCalendar: (p: Json) => rpc<LeaveCal>('hr_leave_calendar', { p }),
  proposeAdjustments: (rows: Json[]) => rpc<{ proposed: number; errors: { row: number; message: string }[] }>('hr_propose_leave_adjustments', { p: { rows } }),
  decideAdjustments: (ids: string[], approve: boolean, note: string | null) =>
    rpc<{ decided: number }>('hr_decide_leave_adjustments', { p_ids: ids, p_approve: approve, p_note: note }),
  listAdjustments: (p: Json) => rpc<Adjustment[]>('hr_list_leave_adjustments', { p }),
  runAccrual: (through: string | null) => rpc<{ created: number; through: string }>('hr_run_leave_accrual', { p_through: through }),
  closeYear: (year: number) => rpc<{ lapsed: number; year: number }>('hr_close_leave_year', { p_year: year }),

  myTasks: () => rpc<MyTasks>('hr_list_my_tasks'),
  timeDashboard: () => rpc<TimeDash>('hr_time_dashboard'),
};
