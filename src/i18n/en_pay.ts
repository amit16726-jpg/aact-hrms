/** Phase 3 — payroll & end of service (English). Arabic in ar_pay.ts must have the same keys. */
export const enPay = {
  // navigation
  'pnav.group': 'Payroll', 'pnav.runs': 'Payroll runs', 'pnav.loans': 'Loans and advances', 'pnav.adjustments': 'One-off pay items',
  'pnav.settlements': 'Final settlements', 'pnav.gratuity': 'Gratuity provision', 'pnav.rules': 'Payroll rules', 'pnav.setup': 'Payroll set-up',
  'pnav.my_payslips': 'My payslips',

  // run statuses
  'prs.DRAFT': 'Draft', 'prs.CALCULATED': 'Calculated', 'prs.VERIFIED': 'Verified', 'prs.APPROVED': 'Approved', 'prs.PAID': 'Paid',

  // runs list
  'pr.title': 'Payroll runs', 'pr.new': 'New payroll run', 'pr.month': 'Month', 'pr.pay_date': 'Pay date', 'pr.create': 'Create',
  'pr.none': 'No payroll runs yet. Lock the attendance month first, then create the run.', 'pr.employees': 'Employees',
  'pr.net': 'Net pay', 'pr.gross': 'Earnings', 'pr.deductions': 'Deductions', 'pr.employer_cost': 'Employer cost', 'pr.warnings': 'Warnings',
  'pr.chain': 'Calculated → verified → approved by three different people. Nobody verifies or approves a payroll with their own salary in it.',
  'pr.attendance_open': 'Attendance for this month is not locked yet.', 'pr.lock_attendance': 'Lock attendance',

  // run detail
  'pr.run_title': 'Payroll {m} — {c}', 'pr.calculate': 'Calculate', 'pr.recalculate': 'Recalculate', 'pr.verify': 'Verify',
  'pr.approve': 'Approve', 'pr.return': 'Return for correction', 'pr.mark_paid': 'Mark as paid', 'pr.reopen': 'Reopen',
  'pr.calculated_done': 'Payroll calculated.', 'pr.verified_done': 'Payroll verified.', 'pr.approved_done': 'Payroll approved. Employees can now see their payslips.',
  'pr.returned_done': 'Payroll returned.', 'pr.paid_done': 'Marked as paid.', 'pr.reopened_done': 'Payroll reopened.',
  'pr.return_title': 'Return the payroll for correction', 'pr.return_label': 'What must be corrected',
  'pr.reopen_title': 'Reopen the approved payroll', 'pr.reopen_body': 'Loan repayments from this run are undone. The run must be calculated, verified and approved again.',
  'pr.approve_title': 'Approve payroll {m}', 'pr.approve_body': 'Net pay {n} for {e} employees. Loan instalments are recorded as repaid and payslips are released.',
  'pr.verify_title': 'Verify payroll {m}',
  'pr.step_calc': 'Calculated', 'pr.step_verify': 'Verified', 'pr.step_approve': 'Approved', 'pr.step_paid': 'Paid',
  'pr.returned_note': 'Returned: {n}', 'pr.reopened_note': 'Reopened: {n}',
  'pr.pending_inputs': '{a} one-off items and {l} loans for this month are still waiting for approval — they are not included until approved.',
  'pr.tab_slips': 'Payslips', 'pr.tab_summary': 'Summary by item', 'pr.tab_exports': 'Exports', 'pr.tab_parallel': 'Parallel run',
  'pr.only_warnings': 'Only payslips with warnings', 'pr.search': 'Search employee', 'pr.no_bank': 'no bank',
  'pr.spf_ee': 'SPF (employees)', 'pr.spf_er': 'SPF (employer)', 'pr.overtime': 'Overtime', 'pr.eosb': 'End of service', 'pr.loans': 'Loan instalments',
  'pr.omani': 'Omani', 'pr.expat': 'Expatriate', 'pr.kind': 'Type', 'pr.amount': 'Amount', 'pr.count': 'Employees',
  'pr.k_EARNING': 'Earnings', 'pr.k_DEDUCTION': 'Deductions', 'pr.k_EMPLOYER': 'Employer contributions',

  // exports
  'px.wps': 'Bank salary file (WPS)', 'px.wps_hint': 'Salary information file in the Central Bank of Oman layout. Check the format with your bank once before the first live upload.',
  'px.wps_skipped': '{n} employees without an approved bank account were left out: {list}', 'px.wps_needs': 'Set the company CR number, bank code and account in Payroll set-up first.',
  'px.journal': 'Journal for Finance', 'px.journal_hint': 'Debits and credits by GL account and cost centre. Set the accounts in Payroll set-up.',
  'px.register': 'Payroll register', 'px.register_hint': 'One row per employee, one column per pay item.',
  'px.spf': 'Social Protection Fund report', 'px.spf_hint': 'Contributions per employee for the monthly Fund submission.',
  'px.download': 'Download', 'px.after_approval': 'Available after approval.',

  // parallel run
  'pp.title': 'Parallel run against the current payroll', 'pp.hint': 'Upload last month\'s output from the current payroll (CSV with employee_no and net; gross optional). Every net pay must match, or the difference must be explained, before the first live run.',
  'pp.upload': 'Upload CSV', 'pp.loaded': '{n} rows loaded.', 'pp.system': 'This system', 'pp.legacy': 'Current payroll', 'pp.diff': 'Difference',
  'pp.MATCH': 'Matches', 'pp.DIFF': 'Different', 'pp.ONLY_LEGACY': 'Only in current payroll', 'pp.ONLY_SYSTEM': 'Only in this system',
  'pp.summary': '{m} match, {d} differ, {o} missing on one side.', 'pp.none': 'Nothing loaded yet.',

  // payslip
  'ps.title': 'Payslip', 'ps.month': 'Month', 'ps.employee': 'Employee', 'ps.department': 'Department', 'ps.job': 'Job title',
  'ps.days': 'Days', 'ps.paid_days': 'Paid days', 'ps.unpaid_days': 'Unpaid days', 'ps.basic': 'Basic salary',
  'ps.earnings': 'Earnings', 'ps.deductions': 'Deductions', 'ps.employer': 'Paid by the employer (not deducted)', 'ps.net': 'Net pay',
  'ps.total_earnings': 'Total earnings', 'ps.total_deductions': 'Total deductions', 'ps.bank': 'Paid to', 'ps.qty': 'Qty', 'ps.rate': 'Rate',
  'ps.warnings': 'Notes for payroll', 'ps.print': 'Print payslip', 'ps.draft': 'Draft — not yet approved', 'ps.none': 'No payslips yet.',
  'ps.my_title': 'My payslips', 'ps.pay_date': 'Pay date', 'ps.open': 'Open', 'ps.history': 'Payslips',

  // loans
  'ln.title': 'Loans and advances', 'ln.new': 'New loan or advance', 'ln.kind': 'Type', 'ln.k_LOAN': 'Loan', 'ln.k_ADVANCE': 'Salary advance',
  'ln.amount': 'Amount', 'ln.installment': 'Monthly instalment', 'ln.first_month': 'First deduction month', 'ln.repaid': 'Repaid',
  'ln.outstanding': 'Outstanding', 'ln.months_left': 'Months left', 'ln.none': 'No loans.',
  'ln.st_PENDING': 'Waiting', 'ln.st_APPROVED': 'Repaying', 'ln.st_REJECTED': 'Rejected', 'ln.st_CLOSED': 'Repaid', 'ln.st_CANCELLED': 'Cancelled',
  'ln.st_OPEN': 'Waiting or repaying', 'ln.proposed': 'Loan proposed. A second person must approve it.', 'ln.cancel': 'Cancel',
  'ln.hint': 'Instalments are deducted in payroll from the first month and never take net pay below zero. A final settlement recovers the rest.',
  'ln.schedule': 'Repayments', 'ln.r_PAYROLL': 'Payroll', 'ln.r_SETTLEMENT': 'Final settlement', 'ln.limit_hint': 'Deductions for debts are limited to {p} % of the wage (Labour Law Art. 95–96); loan instalments follow the signed agreement.',

  // one-off items
  'pa.title': 'One-off pay items', 'pa.new': 'Add item', 'pa.code': 'Item', 'pa.import': 'Import CSV',
  'pa.c_BONUS': 'Bonus', 'pa.c_COMMISSION': 'Commission', 'pa.c_ARREARS': 'Arrears', 'pa.c_ALLOWANCE': 'One-off allowance', 'pa.c_OTHER_EARN': 'Other earning',
  'pa.c_PENALTY': 'Penalty', 'pa.c_DAMAGE': 'Damage recovery', 'pa.c_OTHER_DED': 'Other deduction',
  'pa.csv_hint': 'CSV columns: employee_no, month (YYYY-MM), code, amount, reason. Codes: BONUS, COMMISSION, ARREARS, ALLOWANCE, OTHER_EARN, PENALTY, DAMAGE, OTHER_DED.',
  'pa.proposed': '{n} items proposed. A second person must approve them.', 'pa.errors': '{n} rows could not be added',
  'pa.none': 'No items.', 'pa.approve_selected': 'Approve selected', 'pa.reject_selected': 'Reject selected',
  'pa.cap_hint': 'Penalties and damage recovery are capped in payroll at {p} % of the month\'s wage.',

  // settlements
  'st.title': 'Final settlements', 'st.new': 'New final settlement', 'st.last_day': 'Last working day', 'st.reason': 'Reason for leaving',
  'st.r_RESIGNATION': 'Resignation', 'st.r_TERMINATION': 'Termination', 'st.r_END_OF_CONTRACT': 'End of contract', 'st.r_RETIREMENT': 'Retirement',
  'st.r_DEATH': 'Death', 'st.r_OTHER': 'Other',
  'st.notice_days': 'Notice days paid in lieu', 'st.notice_hint': 'Positive: paid to the employee. Negative: recovered from the employee.',
  'st.preview': 'Work out', 'st.save': 'Save for approval', 'st.gratuity': 'End-of-service gratuity', 'st.gratuity_old': 'Service up to {d} (old rule)',
  'st.gratuity_new': 'Service from {d} (one month\'s basic per year)', 'st.years': '{n} years', 'st.no_gratuity': 'Omani employee — end of service is covered by the Social Protection Fund.',
  'st.below_min': 'Service is below the minimum for gratuity.',
  'st.leave': 'Annual leave not taken', 'st.leave_days': '{n} days × daily wage {r}', 'st.notice': 'Notice pay', 'st.loans': 'Loans and advances recovered',
  'st.other': 'Other items', 'st.add_line': 'Add item', 'st.label': 'Description', 'st.net': 'Net settlement', 'st.basic': 'Final basic salary',
  'st.gross': 'Final gross salary', 'st.service': 'Service', 'st.none': 'No settlements.', 'st.saved': 'Settlement saved. A second person must approve it.',
  'st.st_PREPARED': 'Waiting for approval', 'st.st_APPROVED': 'Approved', 'st.st_PAID': 'Paid', 'st.st_CANCELLED': 'Cancelled',
  'st.print': 'Print settlement', 'st.withdraw': 'Withdraw', 'st.mark_paid': 'Mark as paid', 'st.salary_note': 'Salary for the last month up to the last working day is paid through that month\'s payroll run.',
  'st.paid_done': 'Settlement marked as paid.', 'st.statement': 'Final settlement statement', 'st.signature': 'Received by the employee',

  // gratuity provision
  'gr.title': 'Gratuity provision', 'gr.as_of': 'As of', 'gr.total': 'Total provision', 'gr.join': 'Joined', 'gr.basic': 'Basic',
  'gr.old': 'Up to 31/07/2023', 'gr.new': 'From 01/08/2023', 'gr.amount': 'Gratuity due', 'gr.hint': 'Expatriate employees only (Labour Law Art. 61). Omani employees are covered by the Social Protection Fund.',
  'gr.none': 'No expatriate employees.',

  // rules
  'prl.title': 'Payroll rules', 'prl.hint': 'Rates and limits used by payroll. Each value starts on a date, cites its legal source and needs a second person\'s approval. Confirm the seeded values with the Social Protection Fund and your labour lawyer before going live.',
  'prl.SPF_OMANI': 'Social Protection Fund — Omani employees', 'prl.SPF_EXPAT': 'Social Protection Fund — expatriates', 'prl.GRATUITY': 'End-of-service gratuity (expatriates)',
  'prl.SAVINGS_EXPAT': 'Expatriate savings fund', 'prl.DEDUCTIONS': 'Deduction limit', 'prl.INCOME_TAX': 'Personal income tax', 'prl.PAY_BASIS': 'Pay calculation basis',
  'prk.er_old_age': 'Old age – employer %', 'prk.ee_old_age': 'Old age – employee %', 'prk.er_injury': 'Work injury – employer %',
  'prk.er_job_security': 'Job security – employer %', 'prk.ee_job_security': 'Job security – employee %', 'prk.er_maternity': 'Maternity – employer %',
  'prk.er_sick': 'Sick leave – employer %', 'prk.ceiling': 'Wage ceiling (OMR, 0 = none)', 'prk.cutoff': 'Old-rule cut-off date',
  'prk.old_first_years': 'Old rule: first years', 'prk.old_first_days': 'Old rule: days per year (first years)', 'prk.old_after_days': 'Old rule: days per year after',
  'prk.new_days': 'New rule: days per year', 'prk.min_service_months': 'Minimum service (months)', 'prk.employer_pct': 'Employer % of basic',
  'prk.active': 'Active (1 = yes, 0 = no)', 'prk.max_pct': 'Maximum % of wage', 'prk.rate_pct': 'Tax rate %', 'prk.annual_threshold': 'Annual threshold (OMR)',
  'prk.days_divisor': 'Days in a month for daily rate', 'prk.hours_per_day': 'Hours in a day for hourly rate', 'prk.absent_unpaid': 'Absence unpaid (1/0)',
  'prk.missing_punch_unpaid': 'Missing punch unpaid (1/0)', 'prk.fund_leave_unpaid': 'Fund-paid leave unpaid by employer (1/0)',

  // set-up
  'psu.title': 'Payroll set-up', 'psu.companies': 'Companies — bank salary file', 'psu.cr': 'CR number', 'psu.spf_no': 'SPF employer number',
  'psu.bank_code': 'Payer bank short name', 'psu.account': 'Payer account number', 'psu.payer_cr': 'Payer CR (if different)',
  'psu.components': 'Pay components', 'psu.active': 'In use', 'psu.components_hint': 'Correct a component name here. A component that is not in use is hidden from new salaries but kept on old payslips; the basic salary is always in use.', 'psu.gl': 'GL account', 'psu.spf_base': 'Counts for SPF', 'psu.basic': 'Basic',
  'psu.accounts': 'Journal accounts', 'psu.pay_day': 'Default pay day (day of month)', 'psu.saved': 'Set-up saved.',
  'psu.a_salary_payable': 'Salaries payable', 'psu.a_spf_payable': 'SPF payable', 'psu.a_eosb_provision': 'End-of-service provision',
  'psu.a_loans_receivable': 'Staff loans receivable', 'psu.a_salary_expense': 'Salaries expense', 'psu.a_overtime_expense': 'Overtime expense',
  'psu.a_spf_expense': 'SPF expense (employer)', 'psu.a_eosb_expense': 'End-of-service expense', 'psu.a_deductions_income': 'Deductions recovered',
  'psu.a_income_tax_payable': 'Income tax payable',

  // approvals & dashboard
  'pap.payroll': 'Payroll runs', 'pap.loans': 'Loans and advances', 'pap.adjustments': 'One-off pay items', 'pap.settlements': 'Final settlements',
  'pap.rules': 'Payroll rule changes', 'pap.open_run': 'Open run',
  'pd.payroll': 'Payroll', 'pd.last_run': 'Latest run: {m} — {s}', 'pd.my_last': 'Last payslip: {m}', 'pd.tasks_payroll': '{n} payroll runs',
  'pd.tasks_loans': '{n} loans or advances', 'pd.tasks_pay_adjustments': '{n} one-off pay items', 'pd.tasks_settlements': '{n} final settlements',
  'pd.gratuity': 'Gratuity accrued', 'pd.loans_open': 'Loans',

  'err.ATTENDANCE_OPEN': 'Lock the attendance month first, so payroll uses final figures.',
};
export type PayKey = keyof typeof enPay;
