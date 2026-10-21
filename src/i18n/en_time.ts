/** Phase 2 — attendance & leave (English). Arabic in ar_time.ts must have the same keys. */
export const enTime = {
  // navigation
  'tnav.group': 'Time and leave', 'tnav.attendance': 'Attendance', 'tnav.overtime': 'Overtime', 'tnav.leave': 'Leave',
  'tnav.leave_admin': 'Leave balances and types', 'tnav.shifts': 'Shifts and rosters', 'tnav.calendar': 'Holidays and Ramadan',
  'tnav.import': 'Import punches', 'tnav.periods': 'Months and payroll inputs', 'tnav.rules': 'Oman time rules',

  // weekdays (ISO 1 = Monday)
  'wd.1': 'Mon', 'wd.2': 'Tue', 'wd.3': 'Wed', 'wd.4': 'Thu', 'wd.5': 'Fri', 'wd.6': 'Sat', 'wd.7': 'Sun',

  // attendance statuses
  'ast.PRESENT': 'Present', 'ast.ABSENT': 'Absent', 'ast.LEAVE': 'On leave', 'ast.HOLIDAY': 'Holiday', 'ast.REST': 'Rest day',
  'ast.MISSING_PUNCH': 'Missing punch', 'ast.NO_SHIFT': 'No shift', 'ast.LATE': 'Late', 'ast.EXCEPTION': 'Exceptions only',

  // request statuses
  'rst.PENDING_MANAGER': 'Waiting for manager', 'rst.PENDING_HR': 'Waiting for HR', 'rst.APPROVED': 'Approved',
  'rst.REJECTED': 'Rejected', 'rst.CANCELLED': 'Cancelled', 'rst.PENDING': 'Waiting',

  // month grid
  'grid.P': 'Present', 'grid.L': 'Late', 'grid.A': 'Absent', 'grid.V': 'Leave', 'grid.H': 'Holiday', 'grid.R': 'Rest day',
  'grid.M': 'Missing punch', 'grid.N': 'No shift', 'grid.W': 'Waiting leave', 'grid.legend': 'Key',

  // attendance
  'att.title': 'Attendance', 'att.tab_day': 'Day', 'att.tab_month': 'Month', 'att.tab_employee': 'One employee',
  'att.tab_corrections': 'Corrections', 'att.date': 'Date', 'att.shift': 'Shift', 'att.scheduled': 'Scheduled', 'att.in': 'In',
  'att.out': 'Out', 'att.worked': 'Worked', 'att.late': 'Late', 'att.early': 'Left early', 'att.extra': 'Beyond shift',
  'att.overtime': 'Approved overtime', 'att.present': 'Present', 'att.absent': 'Absent', 'att.missing': 'Missing punch',
  'att.leave': 'On leave', 'att.off': 'Rest or holiday', 'att.no_shift': 'No shift', 'att.all_statuses': 'All statuses',
  'att.request_correction': 'Request correction', 'att.request_overtime': 'Request overtime', 'att.recompute': 'Recalculate',
  'att.recompute_done': 'Recalculated {n} days.', 'att.locked': 'Locked',
  'att.locked_hint': 'This month is locked for payroll. HR must unlock it before anything changes.',
  'att.pending_correction': 'Correction waiting',
  'att.no_rows': 'No attendance for this day yet. Import punches and assign shifts first.', 'att.month': 'Month',
  'att.totals': 'Month totals', 'att.worked_off': 'Worked on a rest day or holiday', 'att.ramadan': 'Ramadan', 'att.punches': 'Punches',
  'att.late_count': 'Late days', 'att.choose_employee': 'Choose an employee to see the month.', 'att.scheduled_days': 'Scheduled days',
  'att.worked_hours': 'Hours worked', 'att.leave_days': 'Leave days', 'att.prev': 'Previous month', 'att.next': 'Next month',
  'att.no_punches': 'No punches for this day.', 'att.show_exceptions': 'Show exceptions only', 'att.my_title': 'My attendance',

  // corrections
  'cor.title': 'Attendance corrections', 'cor.new': 'Request a correction', 'cor.in_time': 'In time', 'cor.out_time': 'Out time',
  'cor.out_next_day': 'Out time is on the next day', 'cor.hint': 'Give the missing time. It is added as a manual punch only after approval.',
  'cor.done': 'Correction sent for approval.', 'cor.none': 'No corrections.', 'cor.withdraw': 'Withdraw',

  // overtime
  'ot.title': 'Overtime', 'ot.new': 'Request overtime', 'ot.work_date': 'Work date', 'ot.start': 'Start', 'ot.end': 'End',
  'ot.end_next_day': 'Ends on the next day', 'ot.basis': 'Basis', 'ot.b_CONSENT': 'With the employee’s consent',
  'ot.b_INVENTORY': 'Inventory or year-end work (no consent, at most 15 days a year)',
  'ot.b_EMERGENCY': 'Accident, perishable goods or urgent work (no consent)',
  'ot.consent': 'The employee agrees to this overtime', 'ot.comp': 'Compensation', 'ot.comp_PAY': 'Pay',
  'ot.comp_TIME_OFF': 'Time off instead', 'ot.kind': 'Day', 'ot.k_WORKDAY': 'Working day', 'ot.k_REST_DAY': 'Rest day',
  'ot.k_HOLIDAY': 'Public holiday', 'ot.minutes': 'Duration', 'ot.night': 'Night', 'ot.pay_hours': 'Paid hours',
  'ot.pay_days': 'Paid days',
  'ot.rules_hint': 'Paid at the basic hourly wage plus {day} % by day and {night} % at night ({ns}–{ne}). The working day including overtime may not exceed {cap} hours. Work on a rest day or holiday earns the day’s wage plus {rest} %, or a day off.',
  'ot.emergency_hint': 'Overtime without consent must be reported to the Ministry of Labour within 24 hours.',
  'ot.notified': 'Ministry notified', 'ot.mark_notified': 'Mark Ministry notified', 'ot.done': 'Overtime sent for approval.',
  'ot.none': 'No overtime requests.', 'ot.withdraw': 'Withdraw', 'ot.not_notified': 'Ministry not yet notified',

  // shifts
  'sh.title': 'Shifts and rosters', 'sh.new': 'New shift', 'sh.edit': 'Edit shift', 'sh.start': 'Start', 'sh.end': 'End',
  'sh.break': 'Break (minutes)', 'sh.grace': 'Late grace (minutes)', 'sh.grace_hint': 'Leave empty to use the company default.',
  'sh.rest_days': 'Weekly rest days', 'sh.ramadan': 'Ramadan shift (6 hours a day)', 'sh.net': 'Hours a day', 'sh.weekly': 'Hours a week',
  'sh.assigned': 'Employees now', 'sh.assign': 'Assign employees', 'sh.assign_title': 'Assign shift {code}', 'sh.from': 'From',
  'sh.to': 'To (empty = open-ended)', 'sh.employees': 'Employees', 'sh.add_employee': 'Add employee',
  'sh.assigned_done': '{n} employees assigned.', 'sh.on_shift': 'Employees on this shift',
  'sh.law_hint': 'Limits in force: {daily} h a day and {weekly} h a week ({rd} h and {rw} h in Ramadan); at least {rest} consecutive rest days; a {brk}-minute break when a shift is longer than {cont} hours.',
  'sh.crosses': 'ends next day', 'sh.none': 'No shifts yet.',
  'sh.temp_hint': 'For Ramadan, assign the Ramadan shift with an end date. The normal shift resumes the next day automatically.',
  'sh.history': 'Shift history',

  // calendar
  'cal.title': 'Holidays and Ramadan', 'cal.year': 'Year', 'cal.holidays': 'Public and company holidays', 'cal.new_holiday': 'Add holiday',
  'cal.edit_holiday': 'Edit holiday', 'cal.kind': 'Kind', 'cal.k_PUBLIC': 'Public holiday', 'cal.k_COMPANY': 'Company holiday',
  'cal.source': 'Source (announcement)', 'cal.remove': 'Remove', 'cal.removed': 'Holiday removed.', 'cal.ramadan': 'Ramadan',
  'cal.new_ramadan': 'Add Ramadan dates', 'cal.first_day': 'First day', 'cal.last_day': 'Last day',
  'cal.hint': 'Enter holidays as the Ministry of Labour announces them. Eid holidays are announced after moon sighting.',
  'cal.none': 'No holidays entered for this year.', 'cal.all_companies': 'All companies', 'cal.no_ramadan': 'No Ramadan dates entered for this year.',

  // import
  'imp.title': 'Import punches', 'imp.file': 'Punch file (CSV or TXT)',
  'imp.file_hint': 'Export from the attendance device software, one punch per row.', 'imp.ref_kind': 'Employees identified by',
  'imp.rk_EMPLOYEE_NO': 'Employee number', 'imp.rk_DEVICE_ID': 'Device user id', 'imp.rk_CIVIL': 'Civil or resident card number',
  'imp.device': 'Device code', 'imp.col_ref': 'Employee column', 'imp.col_datetime': 'Date and time column', 'imp.col_date': 'Date column',
  'imp.col_time': 'Time column', 'imp.col_dir': 'In/Out column', 'imp.none_col': '— none —', 'imp.date_format': 'Date order',
  'imp.f_DMY': 'Day/Month/Year', 'imp.f_MDY': 'Month/Day/Year', 'imp.f_YMD': 'Year-Month-Day', 'imp.has_header': 'First row is a header',
  'imp.separate': 'Date and time are in separate columns', 'imp.preview': 'Preview (first 8 punches)', 'imp.rows_ok': '{n} punches ready',
  'imp.rows_bad': '{n} rows cannot be read', 'imp.import': 'Import {n} punches', 'imp.done': 'Imported {ok}; {dup} were already there; {err} with errors.',
  'imp.history': 'Recent imports', 'imp.errors': 'Errors', 'imp.devices': 'Device ids', 'imp.device_user': 'Device user id',
  'imp.set_device': 'Save device id', 'imp.none': 'No imports yet.', 'imp.line': 'Line', 'imp.problem': 'Problem',
  'imp.p_ref': 'No employee reference', 'imp.p_date': 'Date not readable', 'imp.p_time': 'Time not readable', 'imp.rows': 'Rows',
  'imp.imported': 'Imported', 'imp.duplicates': 'Already there', 'imp.period': 'Dates', 'imp.device_saved': 'Device id saved.',

  // periods / payroll inputs
  'per.title': 'Months and payroll inputs', 'per.lock': 'Lock month', 'per.unlock': 'Unlock', 'per.LOCKED': 'Locked', 'per.OPEN': 'Open',
  'per.pending': '{n} waiting', 'per.lock_title': 'Lock {m}?',
  'per.lock_body': 'Attendance, overtime and leave for this month will be frozen for payroll. Requests still waiting must be decided first.',
  'per.unlock_title': 'Unlock {m}', 'per.summary': 'Payroll inputs for {m}', 'per.export': 'Export payroll inputs',
  'per.present': 'Present', 'per.absent': 'Absent', 'per.missing': 'Missing punch', 'per.late_min': 'Late (min)', 'per.holidays': 'Holidays',
  'per.unpaid': 'Unpaid leave', 'per.leave': 'Leave days', 'per.ot_hours': 'OT paid hours', 'per.ot_days': 'OT paid days',
  'per.scheduled': 'Scheduled days', 'per.locked_by': 'Locked by', 'per.locked_done': 'Month locked.', 'per.unlocked_done': 'Month unlocked.',

  // rules
  'rule.title': 'Oman time rules',
  'rule.hint': 'Values used for hours, overtime and attendance. A change starts on a date and needs a second person’s approval.',
  'rule.WORK_HOURS': 'Working hours', 'rule.RAMADAN_HOURS': 'Ramadan hours', 'rule.WEEKLY_REST': 'Weekly rest',
  'rule.OVERTIME': 'Overtime with consent', 'rule.OVERTIME_NO_CONSENT': 'Overtime without consent', 'rule.ATTENDANCE': 'Attendance policy',
  'rk.daily_max_hours': 'Hours a day', 'rk.weekly_max_hours': 'Hours a week', 'rk.break_minutes': 'Break (minutes)',
  'rk.max_continuous_hours': 'Longest stretch without a break (hours)', 'rk.min_consecutive_days': 'Consecutive rest days',
  'rk.day_premium': 'Day premium', 'rk.night_premium': 'Night premium', 'rk.rest_day_premium': 'Rest-day premium',
  'rk.max_total_daily_hours': 'Hours a day including overtime', 'rk.night_start': 'Night starts', 'rk.night_end': 'Night ends',
  'rk.max_inventory_days_per_year': 'Inventory days a year', 'rk.late_grace_minutes': 'Late grace (minutes)',
  'rk.window_before_minutes': 'Punches counted before the shift (min)', 'rk.window_after_minutes': 'Punches counted after the shift (min)',
  'rk.min_minutes_between_punches': 'Minimum minutes between in and out',
  'rule.propose': 'Propose a change', 'rule.basis': 'Basis', 'rule.legal': 'Legal basis or reference',
  'rule.proposed': 'Change proposed. A second person must approve it.', 'rule.current': 'In force', 'rule.future': 'Scheduled',
  'rule.past': 'Ended', 'rule.pending': 'Waiting', 'rule.LEGAL': 'Law', 'rule.COMPANY_POLICY': 'Company policy',

  // leave
  'lv.title': 'Leave', 'lv.tab_mine': 'My leave', 'lv.tab_requests': 'Requests', 'lv.tab_calendar': 'Calendar',
  'lv.my_balances': 'My balances', 'lv.request': 'Request leave', 'lv.request_for': 'Request leave for an employee', 'lv.type': 'Leave type',
  'lv.start': 'From', 'lv.end': 'To', 'lv.half_day': 'Half day', 'lv.event_date': 'Event date',
  'lv.event_hint': 'Date of the birth (or expected birth), marriage or death.', 'lv.ticket': 'Request the air ticket for this leave',
  'lv.days': 'Days', 'lv.available': 'Available', 'lv.entitled': 'Entitled', 'lv.used': 'Used', 'lv.pending': 'Waiting',
  'lv.unlimited': 'No fixed limit', 'lv.per_event': '{n} days per event', 'lv.once': '{n} days, once', 'lv.per_year': '{n} days a year',
  'lv.accrues': '{n} days a year, accrued monthly', 'lv.not_eligible_yet': 'Available from {d}', 'lv.attach': 'Attach document',
  'lv.attach_title': 'Attach a supporting document', 'lv.doc_kind': 'Document', 'lv.doc_MEDICAL_CERT': 'Medical certificate',
  'lv.doc_LEAVE_SUPPORT': 'Other supporting document', 'lv.attached': 'Document attached.', 'lv.needs_doc': 'Needs a supporting document',
  'lv.no_doc': 'No document yet', 'lv.pay': 'Pay', 'lv.pay_tiers': 'Pay by day', 'lv.done': 'Leave request sent.',
  'lv.cancel_title': 'Cancel this leave?', 'lv.withdraw': 'Withdraw', 'lv.none': 'No leave requests.', 'lv.all_types': 'All types',
  'lv.decided_by': 'Decided by', 'lv.calendar_hint': 'Approved and waiting leave', 'lv.show_all': 'Show everyone',
  'lv.ticket_status': 'Ticket', 'lv.tk_NONE': '—', 'lv.tk_REQUESTED': 'Requested', 'lv.tk_ISSUED': 'Issued', 'lv.tk_CASH': 'Paid in cash',
  'lv.tk_DECLINED': 'Declined', 'lv.set_ticket': 'Update ticket',
  'lv.two_year': 'Less than 30 days of annual leave taken in the last 2 years (Labour Law Art. 81).',
  'lv.taken_24m': 'Annual leave in 24 months', 'lv.ledger': 'Balance history', 'lv.lk_OPENING': 'Opening balance', 'lv.lk_ACCRUAL': 'Accrual',
  'lv.lk_TAKEN': 'Leave taken', 'lv.lk_REVERSAL': 'Leave cancelled', 'lv.lk_ADJUSTMENT': 'Adjustment', 'lv.lk_CARRY_EXPIRY': 'Lapsed above carry-forward',
  'lv.paid_by_FUND': 'Paid by the Social Protection Fund', 'lv.mine_none': 'Your account is not linked to an employee record.',
  'lv.days_count': '{n} days', 'lv.half': 'half day', 'lv.event': 'Event', 'lv.cancel_reason': 'Reason for cancelling',

  // leave administration
  'la.title': 'Leave balances and types', 'la.tab_balances': 'Balances', 'la.tab_adjust': 'Adjustments', 'la.tab_types': 'Leave types',
  'la.tab_year': 'Accrual and year end', 'la.two_year_only': 'Only employees due under the 2-year rule', 'la.propose': 'Propose adjustment',
  'la.opening': 'Import opening balances', 'la.kind': 'Kind', 'la.k_OPENING': 'Opening balance', 'la.k_ADJUSTMENT': 'Adjustment',
  'la.days': 'Days (+ adds, − deducts)', 'la.effective': 'Effective date', 'la.proposed': '{n} adjustments sent for approval.',
  'la.errors': '{n} rows were not accepted', 'la.approve_selected': 'Approve selected', 'la.reject_selected': 'Reject selected',
  'la.csv_hint': 'CSV columns: employee_no, leave_type, days, effective_date (YYYY-MM-DD), reason. Opening balances use the leave opening date.',
  'la.opening_date': 'Leave opening date',
  'la.opening_date_hint': 'Accrual starts in this month. Enter opening balances as at this date. It cannot change once accruals exist.',
  'la.run_accrual': 'Run monthly accrual', 'la.accrual_done': '{n} accrual entries added up to {d}.', 'la.close_year': 'Close year {y}',
  'la.close_done': '{n} balances above the carry-forward limit lapsed.',
  'la.close_body': 'Annual leave above the carry-forward limit on 31 December will lapse.', 'la.edit_type': 'Edit leave type',
  'la.quota': 'Days', 'la.period': 'Period', 'la.qp_YEAR': 'Per year', 'la.qp_EVENT': 'Per event', 'la.qp_ONCE': 'Once in service',
  'la.qp_NONE': 'No limit', 'la.pay_mode': 'Pay', 'la.pm_FULL': 'Full pay', 'la.pm_TIERED': 'Tiered by day', 'la.pm_UNPAID': 'Unpaid',
  'la.paid_by': 'Paid by', 'la.pbb_EMPLOYER': 'Employer', 'la.pbb_FUND': 'Social Protection Fund', 'la.pbb_NONE': '—', 'la.accrual': 'Accrual',
  'la.ac_MONTHLY': 'Monthly', 'la.ac_NONE': 'None', 'la.count_mode': 'Counting', 'la.cm_CALENDAR': 'Calendar days',
  'la.cm_CALENDAR_EXCL_HOLIDAYS': 'Calendar days without public holidays', 'la.cm_WORKING': 'Working days',
  'la.min_service': 'Minimum service (months)', 'la.carry': 'Carry forward (max days)', 'la.gender': 'Applies to', 'la.g_ALL': 'Everyone',
  'la.g_M': 'Men', 'la.g_F': 'Women', 'la.nat': 'Nationality', 'la.n_ALL': 'All', 'la.n_OMANI': 'Omanis', 'la.n_EXPAT': 'Expatriates',
  'la.req_doc': 'Needs a supporting document', 'la.event': 'Needs an event date', 'la.half': 'Half days allowed',
  'la.negative': 'Allow a negative balance', 'la.ticket': 'Air ticket for expatriates', 'la.legal': 'Legal basis',
  'la.legal_min': 'Legal minimum: {n} days', 'la.new_type': 'New company leave type', 'la.none_pending': 'Nothing waiting.',
  'la.opening_saved': 'Opening date saved.', 'la.choose_csv': 'Choose CSV file',

  // approvals
  'apt.leave': 'Leave requests', 'apt.corrections': 'Attendance corrections', 'apt.overtime': 'Overtime', 'apt.adjustments': 'Leave balance adjustments',
  'apt.rules': 'Time rule changes', 'apt.stage_manager': 'Line-manager approval', 'apt.stage_hr': 'HR approval', 'apt.none': 'Nothing waiting.',

  // dashboard
  'dt.today': 'Attendance today', 'dt.team_today': 'My team today', 'dt.mine_today': 'My attendance today', 'dt.my_leave': 'My leave',
  'dt.annual_left': '{n} days of annual leave available', 'dt.sick_used': '{n} sick-leave days used this year',
  'dt.away': 'Away in the next 14 days', 'dt.nobody_away': 'Nobody is away in the next 14 days.', 'dt.tasks': 'Waiting for your decision',
  'dt.tasks_leave': '{n} leave requests', 'dt.tasks_corrections': '{n} attendance corrections', 'dt.tasks_overtime': '{n} overtime requests',
  'dt.tasks_adjustments': '{n} leave balance adjustments', 'dt.tasks_rules': '{n} time rule changes', 'dt.next_leave': 'Next leave',
  'dt.no_punch_today': 'No punch yet today.', 'dt.waiting_requests': '{n} of my requests waiting',

  // employee tab
  'et.tab': 'Time and leave', 'et.shift': 'Current shift', 'et.no_shift': 'No shift assigned', 'et.this_month': 'This month',
  'et.recent_leave': 'Leave requests', 'et.device': 'Device id', 'et.assign_shift': 'Change shift',

  // errors
  'err.PERIOD_LOCKED': 'This month is locked for payroll.', 'err.HOURS_LIMIT': 'This goes over the working-hours limit.',
  'err.REST_RULE': 'The weekly rest rule is not met.', 'err.BREAK_RULE': 'A rest break is required.',
  'err.CONSENT_REQUIRED': 'The employee’s consent is required.', 'err.BALANCE': 'There is not enough leave balance.',
  'err.NOT_ELIGIBLE': 'This leave does not apply to the employee (yet).', 'err.LEGAL_MINIMUM': 'This is below the legal minimum.',
  'err.INVALID_TIME': 'A time is not valid.', 'err.OVERLAP': 'This overlaps an existing record.',
};

export type TimeKey = keyof typeof enTime;
