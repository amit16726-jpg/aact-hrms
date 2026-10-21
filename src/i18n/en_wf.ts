/** Phase 6 — performance, training, discipline, assets, housing & transport, injuries, exit (English). Arabic in ar_wf.ts must have the same keys. */
export const enWf = {
  // navigation
  'wnav.group': 'People operations', 'wnav.performance': 'Performance', 'wnav.training': 'Training', 'wnav.discipline': 'Discipline',
  'wnav.assets': 'Assets & PPE', 'wnav.facilities': 'Housing & transport', 'wnav.injuries': 'Work injuries', 'wnav.exits': 'Exits',

  // performance
  'pf.title': 'Performance', 'pf.hint': 'Appraisal cycles, reviews and improvement plans.',
  'pf.tab_mine': 'My reviews', 'pf.tab_team': 'My team', 'pf.tab_all': 'All reviews', 'pf.tab_cycles': 'Cycles', 'pf.tab_plans': 'Improvement plans',
  'pf.cycle': 'Cycle', 'pf.new_cycle': 'New cycle', 'pf.edit_cycle': 'Change cycle', 'pf.name': 'Name', 'pf.period': 'Review period',
  'pf.from': 'From', 'pf.to': 'To', 'pf.due': 'Due by', 'pf.self_review': 'Employees write a self-assessment first',
  'pf.cst_DRAFT': 'Draft', 'pf.cst_OPEN': 'Open', 'pf.cst_CLOSED': 'Closed', 'pf.open': 'Open cycle', 'pf.close': 'Close cycle',
  'pf.open_title': 'Open the cycle', 'pf.open_hint': 'A review is created for everyone employed at the end of the period. The line manager at that date is the reviewer.',
  'pf.std_goals': 'Standard goals (each review starts with these)', 'pf.goal': 'Goal', 'pf.weight': 'Weight', 'pf.add_goal': 'Add goal',
  'pf.close_q': 'Close the cycle? Reviews not finished stay as they are.', 'pf.reviews_n': '{d} of {n} done', 'pf.avg': 'Average rating',
  'pf.none_cycles': 'No appraisal cycles yet.', 'pf.none_reviews': 'No reviews.', 'pf.reviewer': 'Reviewer', 'pf.rating': 'Rating',
  'pf.st_SELF': 'Self-assessment', 'pf.st_MANAGER': 'Manager review', 'pf.st_HR': 'HR review', 'pf.st_ACK': 'Waiting for employee', 'pf.st_DONE': 'Completed',
  'pf.self_rating': 'Self', 'pf.mgr_rating': 'Manager', 'pf.comment': 'Comment', 'pf.self_comments': 'Employee\'s comments', 'pf.manager_comments': 'Manager\'s comments',
  'pf.hr_comments': 'HR comments', 'pf.employee_comment': 'Employee\'s final comment', 'pf.overall': 'Overall rating',
  'pf.save_draft': 'Save draft', 'pf.submit': 'Submit', 'pf.finalise': 'Finalise', 'pf.return': 'Return to manager', 'pf.ack': 'Acknowledge',
  'pf.submitted': 'Submitted.', 'pf.saved': 'Draft saved.', 'pf.acked': 'Review acknowledged.', 'pf.ack_hint': 'Acknowledging means you have read the review, not that you agree. Add your comment if you disagree.',
  'pf.scale': '1 = well below expectations · 3 = meets · 5 = far exceeds', 'pf.issue_plan': 'Issue improvement plan',

  // improvement plans
  'ip.title': 'Improvement plan', 'ip.new': 'New improvement plan', 'ip.areas': 'What must improve', 'ip.support': 'Support and training given',
  'ip.issued_on': 'Issued on', 'ip.ends_on': 'Improvement period ends', 'ip.min_hint': 'The law requires written notice and at least {n} months to improve before dismissal for poor performance.',
  'ip.st_ACTIVE': 'Active', 'ip.st_IMPROVED': 'Improved', 'ip.st_NOT_IMPROVED': 'Not improved', 'ip.st_CANCELLED': 'Cancelled',
  'ip.close': 'Record outcome', 'ip.outcome': 'Outcome', 'ip.outcome_note': 'Outcome details', 'ip.not_before': '"Not improved" can be recorded after {d}.',
  'ip.ack': 'I have received this plan', 'ip.acked': 'Acknowledged on {d}', 'ip.days_left': '{n} days left', 'ip.none': 'No improvement plans.', 'ip.issued': 'Plan issued.',

  // training
  'tr.title': 'Training', 'tr.hint': 'Courses, certificates and their expiry.',
  'tr.tab_records': 'Records', 'tr.tab_expiring': 'Expiring', 'tr.tab_gaps': 'Missing mandatory', 'tr.tab_courses': 'Courses',
  'tr.course': 'Course', 'tr.new_course': 'New course', 'tr.edit_course': 'Change course', 'tr.code': 'Code', 'tr.name_en': 'Name (English)', 'tr.name_ar': 'Name (Arabic)',
  'tr.provider': 'Provider', 'tr.category': 'Category', 'tr.validity': 'Certificate valid for (months)', 'tr.validity_none': 'Does not expire',
  'tr.mandatory': 'Mandatory for everyone', 'tr.active': 'In use', 'tr.c_SAFETY': 'Safety', 'tr.c_TECHNICAL': 'Technical', 'tr.c_COMPLIANCE': 'Compliance',
  'tr.c_SOFT_SKILLS': 'Soft skills', 'tr.c_GENERAL': 'General', 'tr.record': 'Record training', 'tr.employees': 'Employees', 'tr.add_emp': 'Add employee',
  'tr.status': 'Status', 'tr.st_PLANNED': 'Planned', 'tr.st_COMPLETED': 'Completed', 'tr.st_CANCELLED': 'Cancelled',
  'tr.planned_on': 'Planned for', 'tr.completed_on': 'Completed on', 'tr.expires_on': 'Expires on', 'tr.expires_auto': 'Worked out from the course validity when left empty.',
  'tr.certificate': 'Certificate no.', 'tr.score': 'Result', 'tr.cost': 'Cost (OMR)', 'tr.saved_n': '{n} record(s) saved.', 'tr.superseded': 'Renewed',
  'tr.none': 'No training records.', 'tr.no_gaps': 'Everyone has the mandatory courses.', 'tr.last_expired': 'Expired on', 'tr.never': 'Never done',
  'tr.completed_n': '{n} trained', 'tr.expiring_n': '{n} expiring in 60 days', 'tr.cancel_q': 'Cancel this training record?',

  // discipline
  'dc.title': 'Discipline', 'dc.hint': 'Disciplinary cases. Sensitive: every view is logged.', 'dc.my_hint': 'Cases about you. You have the right to respond in writing and to appeal.',
  'dc.new': 'Open case', 'dc.ref': 'Reference', 'dc.incident': 'Incident date', 'dc.category': 'Category', 'dc.description': 'What happened',
  'dc.cat_ATTENDANCE': 'Attendance', 'dc.cat_CONDUCT': 'Conduct', 'dc.cat_SAFETY': 'Safety', 'dc.cat_PERFORMANCE': 'Performance', 'dc.cat_POLICY': 'Company policy', 'dc.cat_OTHER': 'Other',
  'dc.st_DRAFT': 'Draft', 'dc.st_INVESTIGATION': 'Investigation', 'dc.st_PROPOSED': 'Decision pending', 'dc.st_DECIDED': 'Decided', 'dc.st_DISMISSED': 'Dropped',
  'dc.filter_open': 'Open cases', 'dc.none': 'No disciplinary cases.', 'dc.notes': 'Investigation notes (internal)', 'dc.investigate': 'Start investigation',
  'dc.investigate_q': 'Start the investigation? The employee will be asked for a written response.', 'dc.response': 'Employee\'s response', 'dc.no_response': 'No response yet.',
  'dc.propose': 'Propose penalty', 'dc.penalty': 'Penalty', 'dc.days': 'Days', 'dc.days_hint_DEDUCTION': 'Days of wage (up to {n}).', 'dc.days_hint_SUSPENSION': 'Days of suspension (up to {n}).',
  'dc.pen_NONE': 'No penalty', 'dc.pen_VERBAL_WARNING': 'Verbal warning', 'dc.pen_WRITTEN_WARNING': 'Written warning', 'dc.pen_FINAL_WARNING': 'Final warning',
  'dc.pen_DEDUCTION': 'Wage deduction', 'dc.pen_SUSPENSION': 'Suspension', 'dc.pen_TERMINATION': 'Termination',
  'dc.no_response_confirmed': 'The employee was asked and did not respond', 'dc.proposed': 'Proposed: {p}', 'dc.decide': 'Decide', 'dc.decide_hint': 'You may change the proposed penalty. A wage deduction goes to payroll for Finance approval.',
  'dc.return': 'Return for more investigation', 'dc.drop': 'Drop case', 'dc.drop_q': 'Drop this case?', 'dc.decision': 'Decision', 'dc.appeal': 'Appeal',
  'dc.respond': 'Write your response', 'dc.appeal_btn': 'Appeal the decision', 'dc.response_sent': 'Response sent.', 'dc.history': 'Earlier cases',
  'dc.to_payroll': 'Deduction sent to payroll for approval', 'dc.opened_by': 'Opened by {n}', 'dc.days_n': '{n} day(s)',

  // assets
  'as2.title': 'Assets & PPE', 'as2.hint': 'Safety equipment, uniforms, tools, IT equipment, keys and cards issued to employees.',
  'as2.tab_out': 'Issued', 'as2.tab_all': 'History', 'as2.tab_items': 'Items', 'as2.item': 'Item', 'as2.new_item': 'New item', 'as2.edit_item': 'Change item',
  'as2.cat_PPE': 'PPE', 'as2.cat_UNIFORM': 'Uniform', 'as2.cat_IT': 'IT equipment', 'as2.cat_TOOL': 'Tool', 'as2.cat_VEHICLE': 'Vehicle', 'as2.cat_KEY': 'Key', 'as2.cat_CARD': 'Access card', 'as2.cat_OTHER': 'Other',
  'as2.returnable': 'Must be returned', 'as2.unit_cost': 'Unit cost (OMR)', 'as2.replace': 'Replace every (months)', 'as2.issue': 'Issue', 'as2.qty': 'Quantity',
  'as2.serial': 'Serial / tag no.', 'as2.issued_on': 'Issued on', 'as2.due_return': 'Return by', 'as2.out_n': '{n} out', 'as2.return': 'Receive back',
  'as2.condition': 'Condition', 'as2.cond_GOOD': 'Good', 'as2.cond_WORN': 'Worn', 'as2.cond_DAMAGED': 'Damaged', 'as2.cond_LOST': 'Lost',
  'as2.recover': 'Recover from salary (OMR)', 'as2.recover_hint': 'Only for damage or loss. Goes to payroll for Finance approval; the 25% limit applies.',
  'as2.st_ISSUED': 'With employee', 'as2.st_RETURNED': 'Returned', 'as2.st_LOST': 'Lost', 'as2.st_CONSUMED': 'Consumable',
  'as2.overdue': 'Overdue', 'as2.replace_due': 'Replace by {d}', 'as2.none': 'Nothing issued.', 'as2.issued_n': 'Issued to {n} employee(s).', 'as2.returned': 'Received.',

  // facilities
  'fc.title': 'Housing & transport', 'fc.hint': 'Company accommodation and transport routes, with who is assigned.',
  'fc.k_ACCOMMODATION': 'Accommodation', 'fc.k_TRANSPORT': 'Transport', 'fc.new_ACCOMMODATION': 'New accommodation', 'fc.new_TRANSPORT': 'New route',
  'fc.edit': 'Change details', 'fc.code': 'Code', 'fc.name_en': 'Name (English)', 'fc.name_ar': 'Name (Arabic)', 'fc.address_ACCOMMODATION': 'Address', 'fc.address_TRANSPORT': 'Route',
  'fc.capacity': 'Capacity', 'fc.vehicle': 'Vehicle no.', 'fc.driver': 'Driver', 'fc.occupied': '{n} of {c}', 'fc.assign': 'Assign', 'fc.place_ACCOMMODATION': 'Room / bed',
  'fc.place_TRANSPORT': 'Pick-up point', 'fc.from': 'From', 'fc.end': 'End', 'fc.end_q': 'End this assignment today?', 'fc.none': 'Nothing set up yet.', 'fc.empty': 'Nobody assigned.',
  'fc.full': 'Full', 'fc.move_hint': 'Any current assignment of the same kind ends the day before.',

  // injuries
  'in.title': 'Work injuries', 'in.hint': 'Accidents at work, their investigation and reporting to the Social Protection Fund.',
  'in.new': 'Record injury', 'in.edit': 'Update injury', 'in.ref': 'Reference', 'in.when': 'When', 'in.location': 'Where', 'in.description': 'What happened',
  'in.type': 'Type of injury', 'in.body_part': 'Part of body', 'in.severity': 'Severity', 'in.lost_days': 'Days lost', 'in.witnesses': 'Witnesses',
  'in.root_cause': 'Root cause', 'in.corrective': 'Corrective action', 'in.spf_reported': 'Reported to the Social Protection Fund on', 'in.spf_ref': 'Fund reference',
  'in.sev_FIRST_AID': 'First aid', 'in.sev_MEDICAL': 'Medical treatment', 'in.sev_LOST_TIME': 'Lost time', 'in.sev_PERMANENT': 'Permanent disability', 'in.sev_FATAL': 'Fatal',
  'in.st_OPEN': 'Open', 'in.st_CLOSED': 'Closed', 'in.report_due': 'Report by {d}', 'in.overdue': 'Report overdue', 'in.reported': 'Reported {d}',
  'in.close': 'Close', 'in.close_q': 'Close this injury record?', 'in.none': 'No work injuries recorded.', 'in.saved': 'Injury saved.', 'in.basis': 'Reporting deadline: {n} days',

  // exits
  'ex.title': 'Exits', 'ex.hint': 'Resignations, terminations and contract ends: notice, clearance, exit interview, separation.',
  'ex.start': 'Start exit', 'ex.type': 'Type', 'ex.t_RESIGNATION': 'Resignation', 'ex.t_TERMINATION': 'Termination', 'ex.t_END_OF_CONTRACT': 'End of contract',
  'ex.t_RETIREMENT': 'Retirement', 'ex.t_OTHER': 'Other', 'ex.notice_given': 'Notice given on', 'ex.last_day': 'Last working day', 'ex.notice_days': 'Notice: {n} days',
  'ex.min_notice': 'Minimum notice for this employee: {n} days.', 'ex.short': 'The notice is {d} days — less than the {n} days required.', 'ex.pay_in_lieu': 'Pay in lieu of the missing notice',
  'ex.reason': 'Reason', 'ex.notice': 'Notice days (given / required)', 'ex.nc': 'Non-compete', 'ex.non_compete': 'Non-compete period (months, max {n})', 'ex.st_OPEN': 'In progress', 'ex.st_COMPLETED': 'Completed', 'ex.st_CANCELLED': 'Cancelled',
  'ex.clearance': 'Clearance', 'ex.steps': '{d} of {n} steps', 'ex.done': 'Done', 'ex.not_needed': 'Not needed', 'ex.reopen': 'Reopen', 'ex.why_not_needed': 'Why is this step not needed?',
  'ex.asset_hint': 'Receive the item in Assets & PPE to tick this step.', 'ex.interview': 'Exit interview', 'ex.record_interview': 'Record exit interview',
  'ex.reason_code': 'Main reason for leaving', 'ex.r_SALARY': 'Salary', 'ex.r_CAREER': 'Career growth', 'ex.r_FAMILY': 'Family', 'ex.r_MANAGER': 'Manager / team',
  'ex.r_WORKLOAD': 'Workload / hours', 'ex.r_RELOCATION': 'Relocation', 'ex.r_HEALTH': 'Personal reasons', 'ex.r_OTHER': 'Other',
  'ex.would_return': 'Would consider coming back', 'ex.rating': 'Overall experience (1–5)', 'ex.comments': 'Comments',
  'ex.complete': 'Complete exit', 'ex.complete_q': 'Complete the exit? The employee will be recorded as having left on {d}.', 'ex.cancel': 'Cancel exit',
  'ex.cancel_hint': 'If the employee is serving notice, the notice is withdrawn.', 'ex.settlement': 'Final settlement', 'ex.prepare_settlement': 'Prepare in Payroll',
  'ex.none': 'No exits.', 'ex.filter_open': 'In progress', 'ex.started': 'Exit started.', 'ex.completed': 'Exit completed.', 'ex.assets_out': '{n} item(s) still with the employee',

  // dashboard, approvals, settings
  'wd.title': 'People operations', 'wd.training_30': 'Certificates expiring in 30 days', 'wd.assets_overdue': 'Assets overdue', 'wd.injuries_open': 'Open injuries',
  'wd.injuries_unreported': 'Injuries not reported in time', 'wd.exits_open': 'Exits in progress', 'wd.plans_active': 'Active improvement plans',
  'wd.tasks_reviews': '{n} performance review(s)', 'wd.tasks_cases': '{n} disciplinary decision(s)', 'wd.tasks_my_cases': '{n} case(s) waiting for your response',
  'wap.reviews': 'Performance reviews for you', 'wap.cases': 'Disciplinary decisions', 'wap.my_cases': 'Please respond',
  'hp.title': 'HR policy limits', 'hp.hint': 'Change only with a dated management decision; each change is recorded in the audit trail.',
  'hp.ded': 'Maximum wage deduction per case (days)', 'hp.susp': 'Maximum suspension per case (days)', 'hp.injury': 'Injury reporting deadline (days)',
  'hp.fixed': 'Set by the Labour Law', 'hp.saved': 'Policy saved.',

  'err.PIP_TOO_SHORT': 'The improvement period is shorter than the law requires.', 'err.PENALTY_LIMIT': 'The penalty is above the allowed limit.',
  'err.RESPONSE_MISSING': 'The employee has not responded yet.', 'err.FULL': 'No free places left.', 'err.NOTICE_SHORT': 'The notice period is too short.',
  'err.STEPS_OPEN': 'Some clearance steps are still open.', 'err.NO_SALARY': 'No approved salary found.',
};
export type WfKey = keyof typeof enWf;
