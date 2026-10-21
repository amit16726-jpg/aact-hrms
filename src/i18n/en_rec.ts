/** Phase 5 — recruitment & onboarding (English). Arabic in ar_rec.ts must have the same keys. */
export const enRec = {
  // navigation
  'rnav.group': 'Recruitment', 'rnav.recruitment': 'Recruitment', 'rnav.probation': 'Probation',

  // page & tabs
  'rc.title': 'Recruitment', 'rc.hint': 'Positions to fill, candidates, interviews, offers and onboarding.',
  'rc.years': '{n} yrs experience', 'rc.tab_reqs': 'Requisitions', 'rc.tab_candidates': 'Candidates', 'rc.tab_interviews': 'Interviews', 'rc.tab_onboarding': 'Onboarding', 'rc.tab_settings': 'Settings',

  // requisitions
  'rq2.new': 'New requisition', 'rq2.edit': 'Change requisition', 'rq2.ref': 'Reference', 'rq2.job': 'Position', 'rq2.positions': 'Positions',
  'rq2.reason': 'Reason', 'rq2.r_NEW': 'New position', 'rq2.r_REPLACEMENT': 'Replacement', 'rq2.r_TEMPORARY': 'Temporary need',
  'rq2.replaces': 'Replacing', 'rq2.nat_rule': 'Nationality', 'rq2.n_ANY': 'Any nationality', 'rq2.n_OMANI_ONLY': 'Omani only', 'rq2.n_OMANI_PREFERRED': 'Omani preferred',
  'rq2.salary_range': 'Basic salary range (OMR)', 'rq2.salary_min': 'Minimum', 'rq2.salary_max': 'Maximum', 'rq2.target_date': 'Needed by',
  'rq2.justification': 'Why is this position needed?', 'rq2.employment_type': 'Employment type',
  'rq2.st_PENDING': 'Waiting for approval', 'rq2.st_APPROVED': 'Open', 'rq2.st_REJECTED': 'Rejected', 'rq2.st_ON_HOLD': 'On hold',
  'rq2.st_FILLED': 'Filled', 'rq2.st_CANCELLED': 'Cancelled', 'rq2.filter_open': 'Open and waiting',
  'rq2.none': 'No requisitions.', 'rq2.filled_of': '{h} of {n} hired', 'rq2.pipeline': '{n} in progress', 'rq2.saved': 'Requisition sent for approval.',
  'rq2.hold': 'Put on hold', 'rq2.reopen': 'Reopen', 'rq2.cancel': 'Cancel requisition', 'rq2.approve_title': 'Approve requisition', 'rq2.reject_title': 'Reject requisition',
  'rq2.omani_only_job': 'This job is reserved for Omanis ({s}).',
  'rq2.omanisation': 'Omanisation check', 'rq2.om_now': 'Company now', 'rq2.om_target': 'Target', 'rq2.om_if_omani': 'If filled by Omanis', 'rq2.om_if_expat': 'If filled by expatriates',
  'rq2.om_dept': 'Department now', 'rq2.om_breaks': 'Filling this with expatriates would take the company below its Omanisation target.',
  'rq2.om_no_target': 'No approved target', 'rq2.details': 'Details', 'rq2.requested': 'Requested by {n} on {d}',

  // candidates & pipeline
  'cd.new': 'New candidate', 'cd.add': 'Add candidate', 'cd.existing': 'Existing candidate', 'cd.search_ph': 'Name, e-mail, phone or ID number',
  'cd.name_en': 'Name (English)', 'cd.name_ar': 'Name (Arabic)', 'cd.nationality': 'Nationality', 'cd.gender': 'Gender', 'cd.dob': 'Date of birth',
  'cd.email': 'E-mail', 'cd.phone': 'Phone', 'cd.civil': 'Civil / resident card no.', 'cd.passport': 'Passport no.', 'cd.in_oman': 'Already living in Oman',
  'cd.employer': 'Current employer', 'cd.experience': 'Experience (years)', 'cd.qualification': 'Qualification', 'cd.source': 'Source', 'cd.notes': 'Notes',
  'cd.s_REFERRAL': 'Referral', 'cd.s_AGENCY': 'Agency', 'cd.s_WEBSITE': 'Website', 'cd.s_WALK_IN': 'Walk-in', 'cd.s_INTERNAL': 'Internal', 'cd.s_MOL_PORTAL': 'Ministry of Labour portal', 'cd.s_OTHER': 'Other',
  'cd.none': 'No candidates.', 'cd.applications': '{n} application(s)', 'cd.abroad': 'Abroad', 'cd.prior': 'Has worked for the company before — no probation allowed.',
  'cd.added': 'Candidate added.', 'cd.hired_as': 'Hired as employee',
  'stg.APPLIED': 'Applied', 'stg.SHORTLISTED': 'Shortlisted', 'stg.INTERVIEW': 'Interview', 'stg.OFFER': 'Offer', 'stg.HIRED': 'Hired', 'stg.REJECTED': 'Rejected', 'stg.WITHDRAWN': 'Withdrawn',
  'ap2.move': 'Move to', 'ap2.reject': 'Reject', 'ap2.withdraw': 'Withdrawn', 'ap2.closed': 'Not progressing', 'ap2.stage': 'Stage', 'ap2.rating': 'Rating',
  'ap2.open_full': 'Open', 'ap2.back_req': 'Requisition {r}',

  // interviews
  'iv.schedule': 'Schedule interview', 'iv.when': 'Date and time', 'iv.mode': 'Type', 'iv.m_IN_PERSON': 'In person', 'iv.m_PHONE': 'Phone', 'iv.m_VIDEO': 'Video',
  'iv.location': 'Place or link', 'iv.interviewer': 'Interviewer', 'iv.record': 'Record result', 'iv.cancel': 'Cancel interview',
  'iv.st_SCHEDULED': 'Scheduled', 'iv.st_DONE': 'Done', 'iv.st_CANCELLED': 'Cancelled', 'iv.st_NO_SHOW': 'Did not attend',
  'iv.rating': 'Rating (1–5)', 'iv.recommendation': 'Recommendation', 'iv.r_HIRE': 'Hire', 'iv.r_MAYBE': 'Maybe', 'iv.r_NO': 'Do not hire',
  'iv.feedback': 'Feedback', 'iv.no_show': 'Did not attend', 'iv.none': 'No interviews.', 'iv.mine': 'My interviews', 'iv.candidate': 'Candidate',

  // offers
  'of.new': 'Prepare offer', 'of.edit': 'Change offer', 'of.title': 'Offer', 'of.start': 'Start date', 'of.contract': 'Contract', 'of.c_FIXED_TERM': 'Fixed term', 'of.c_INDEFINITE': 'Unlimited',
  'of.months': 'Length (months)', 'of.probation': 'Probation (months)', 'of.probation_max': 'Maximum {n} month(s) for this category (Labour Law).',
  'of.notice': 'Notice (days)', 'of.category': 'Category', 'of.grade': 'Grade', 'of.location': 'Work location', 'of.salary': 'Monthly salary (OMR)',
  'of.benefits': 'Other benefits', 'of.benefits_ph': 'e.g. return air ticket every two years, accommodation, transport', 'of.valid_until': 'Offer valid until',
  'of.gross': 'Gross', 'of.st_PENDING': 'Waiting for approval', 'of.st_APPROVED': 'Approved — send to candidate', 'of.st_REJECTED': 'Rejected',
  'of.st_ACCEPTED': 'Accepted', 'of.st_DECLINED': 'Declined', 'of.st_WITHDRAWN': 'Withdrawn',
  'of.approve_title': 'Approve offer', 'of.reject_title': 'Reject offer', 'of.accepted': 'Candidate accepted', 'of.declined': 'Candidate declined',
  'of.accept_q': 'Record that the candidate accepted? The onboarding checklist will be created.', 'of.decline_reason': 'Reason the candidate gave',
  'of.withdraw': 'Withdraw offer', 'of.print': 'Print offer', 'of.prepared_by': 'Prepared by {n}', 'of.approved_by': 'Approved by {n}', 'of.saved': 'Offer sent for approval.',
  'of.signature_candidate': 'Candidate signature and date', 'of.signature_company': 'For the company',

  // onboarding & hire
  'ob.title': 'Onboarding checklist', 'ob.due': 'Due', 'ob.done': 'Done', 'ob.not_needed': 'Not needed', 'ob.reopen': 'Reopen', 'ob.why_not': 'Why is this step not needed?',
  'ob.st_PENDING': 'To do', 'ob.st_DONE': 'Done', 'ob.st_NOT_NEEDED': 'Not needed', 'ob.progress': '{d} of {t} done', 'ob.overdue': '{n} overdue', 'ob.next': 'Next',
  'ob.none': 'Nobody is being onboarded.', 'ob.show_all': 'Include completed',
  'hr2.hire': 'Create employee', 'hr2.hire_title': 'Create the employee record', 'hr2.hint': 'The employee is created from the accepted offer: joining date, job, probation and contract. The salary is sent for approval as usual.',
  'hr2.manager': 'Reports to', 'hr2.employee_no': 'Employee number (blank = automatic)', 'hr2.work_email': 'Work e-mail', 'hr2.shift': 'Shift / roster code',
  'hr2.exception': 'Reason for the Omani-only exception', 'hr2.duplicate': 'This is a different person with the same name and date of birth',
  'hr2.done': 'Employee {n} created. The salary is waiting for approval.', 'hr2.open_employee': 'Open employee file',

  // probation
  'pb.title': 'Probation', 'pb.hint': 'Employees on probation. Confirm them or end the employment before the end date.',
  'pb.ends': 'Ends', 'pb.left': '{n} days left', 'pb.overdue': 'Ended {n} days ago — decide now', 'pb.max': 'Legal maximum', 'pb.confirm': 'Confirm',
  'pb.confirm_q': 'Confirm {n} as a permanent employee?', 'pb.extend': 'Extend', 'pb.extend_title': 'Extend probation', 'pb.new_end': 'New end date',
  'pb.reason': 'Reason', 'pb.none': 'Nobody is on probation.', 'pb.confirmed': 'Employee confirmed.', 'pb.extended': 'Probation extended.', 'pb.joined': 'Joined',

  // settings
  'rs.title': 'Recruitment settings', 'rs.probation': 'Probation limits', 'rs.monthly': 'Monthly-paid (max 3)', 'rs.other': 'Others (max 2)',
  'rs.reminder': 'Remind this many days before probation ends', 'rs.basis': 'Legal basis', 'rs.checklists': 'Onboarding checklists',
  'rs.k_EXPAT_ABROAD': 'Expatriate coming from abroad', 'rs.k_EXPAT_IN_OMAN': 'Expatriate already in Oman', 'rs.k_OMANI': 'Omani',
  'rs.step_code': 'Code', 'rs.step_en': 'Step (English)', 'rs.step_ar': 'Step (Arabic)', 'rs.step_days': 'Days from start', 'rs.add_step': 'Add step', 'rs.remove': 'Remove',

  // dashboard & approvals
  'rd.recruitment': 'Recruitment', 'rd.open_positions': 'Open positions', 'rd.in_pipeline': 'Candidates in progress', 'rd.joining_30': 'Joining in 30 days',
  'rd.onboarding_overdue': 'Onboarding steps overdue', 'rd.probation_30': 'Probation ending in 30 days',
  'rd.tasks_requisitions': '{n} requisition(s) to approve', 'rd.tasks_offers': '{n} offer(s) to approve', 'rd.tasks_interviews': '{n} interview(s) to record',
  'rap.requisitions': 'Requisitions to approve', 'rap.offers': 'Offers to approve', 'rap.interviews': 'Interviews waiting for your feedback',
  'err.PROBATION_LIMIT': 'The probation period is longer than the law allows.',
};
export type RecKey = keyof typeof enRec;
