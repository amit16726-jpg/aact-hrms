/** Phase 7 — privacy, statutory reports, executive dashboard, data import (English). Arabic in ar_gov.ts must have the same keys. */
export const enGov = {
  'gnav.group': 'Reports & governance', 'gnav.exec': 'Executive dashboard', 'gnav.mol': 'Localisation report (MoL)', 'gnav.spf': 'SPF contributions',
  'gnav.privacy': 'Data protection', 'gnav.import': 'Import data',

  // privacy admin
  'pd.title': 'Data protection (PDPL)', 'pd.hint': 'Privacy notice, consents, data-subject requests, breach log, processing register and retention.',
  'pd.tab_overview': 'Overview', 'pd.tab_notice': 'Privacy notice', 'pd.tab_consents': 'Consents', 'pd.tab_requests': 'Requests', 'pd.tab_breaches': 'Breaches',
  'pd.tab_register': 'Processing register', 'pd.tab_retention': 'Retention', 'pd.tab_settings': 'Settings',
  'pd.notice_v': 'Notice version {v}', 'pd.no_notice': 'No privacy notice published yet.', 'pd.acks': '{n} of {u} users acknowledged',
  'pd.dsr_open': 'Open requests', 'pd.dsr_overdue': 'Overdue requests', 'pd.br_open': 'Open breaches', 'pd.br_overdue': 'Not notified within 72 hours',
  'pd.act': 'Processing activities', 'pd.act_unrev': 'Not reviewed in 12 months', 'pd.cand_due': 'Candidates past retention',
  'pd.n_st_DRAFT': 'Draft', 'pd.n_st_PUBLISHED': 'Published', 'pd.n_st_RETIRED': 'Retired', 'pd.new_version': 'New version', 'pd.edit_notice': 'Edit draft',
  'pd.publish': 'Publish', 'pd.publish_q': 'Publish this version? Everyone with a login will be asked to read and acknowledge it.',
  'pd.title_en': 'Title (English)', 'pd.title_ar': 'Title (Arabic)', 'pd.body_en': 'Text (English)', 'pd.body_ar': 'Text (Arabic)', 'pd.prepared': 'Prepared by {n}',
  'pd.published': 'Published by {n} on {d}', 'pd.ack_count': '{n} acknowledged', 'pd.ack_col': 'Notice acknowledged', 'pd.not_ack': 'Not yet',
  'pc.PHOTO_DIRECTORY': 'Photo in the staff directory', 'pc.MARKETING_MEDIA': 'Photos or videos in company publicity', 'pc.BIOMETRIC': 'Fingerprint / face attendance',
  'pc.HEALTH_DATA': 'Health information beyond legal requirements', 'pc.TRANSFER_ABROAD': 'Transfer of data outside Oman',
  'dk.ACCESS': 'Access (copy of my data)', 'dk.CORRECTION': 'Correction', 'dk.ERASURE': 'Erasure', 'dk.RESTRICTION': 'Restrict processing', 'dk.OBJECTION': 'Objection',
  'dk.PORTABILITY': 'Data in a portable format', 'dk.WITHDRAW_CONSENT': 'Withdraw consent', 'dk.COMPLAINT': 'Complaint',
  'ds.OPEN': 'Received', 'ds.IN_PROGRESS': 'In progress', 'ds.COMPLETED': 'Answered', 'ds.REJECTED': 'Refused',
  'dr.new': 'Record request', 'dr.ref': 'Reference', 'dr.requester': 'Requester', 'dr.contact': 'Contact', 'dr.kind': 'Request', 'dr.details': 'Details',
  'dr.received': 'Received on', 'dr.due': 'Reply by', 'dr.identity': 'Identity confirmed', 'dr.left': '{n} days left', 'dr.overdue': '{n} days overdue',
  'dr.close': 'Close', 'dr.complete': 'Answered', 'dr.reject': 'Refused', 'dr.outcome': 'What was done / reason', 'dr.none': 'No requests.', 'dr.employee': 'Employee (if any)',
  'br.new': 'Record breach', 'br.ref': 'Reference', 'br.discovered': 'Discovered', 'br.occurred': 'Happened (if known)', 'br.description': 'What happened',
  'br.data_kinds': 'Data involved', 'br.people': 'People affected', 'br.risk': 'Risk to people', 'br.r_LOW': 'Low', 'br.r_MEDIUM': 'Medium', 'br.r_HIGH': 'High',
  'br.containment': 'Containment action', 'br.contained': 'Contained at', 'br.notified': 'Ministry notified at', 'br.reference': 'Ministry reference',
  'br.not_notified': 'Why notification is not required', 'br.subjects': 'Affected people told at', 'br.deadline': 'Notify by {d}', 'br.left': '{h} left',
  'br.overdue': 'Deadline passed', 'br.late': 'Notified late', 'br.st_OPEN': 'Open', 'br.st_CLOSED': 'Closed', 'br.close': 'Close', 'br.none': 'No breaches recorded.',
  'br.hint': 'Record every incident, even small ones. The Ministry (MTCIT) must be told within {h} hours unless there is no risk to people.',
  'ra.new': 'Add activity', 'ra.code': 'Code', 'ra.name_en': 'Name (English)', 'ra.name_ar': 'Name (Arabic)', 'ra.purpose': 'Purpose', 'ra.basis': 'Legal basis',
  'lb.CONTRACT': 'Employment contract', 'lb.LEGAL_OBLIGATION': 'Legal obligation', 'lb.CONSENT': 'Consent', 'lb.VITAL_INTEREST': 'Vital interest',
  'lb.PUBLIC_INTEREST': 'Public interest', 'lb.LEGITIMATE_INTEREST': 'Legitimate interest',
  'ra.subjects': 'Whose data', 'ra.categories': 'Which data', 'ra.sensitive': 'Includes sensitive data', 'ra.recipients': 'Shared with', 'ra.transfer': 'Transfer outside Oman',
  'ra.retention': 'Kept for', 'ra.security': 'Security measures', 'ra.owner': 'Responsible', 'ra.reviewed': 'Reviewed {d}', 'ra.active': 'In use',
  'rt.rule': 'Records', 'rt.months': 'Keep (months)', 'rt.basis': 'Basis', 'rt.due': 'Past retention', 'rt.review': 'Review and archive',
  'rt.anonymise': 'Anonymise selected', 'rt.anonymise_q': 'Anonymise {n} candidate(s)? Names and contact details are blanked permanently.',
  'rt.done': '{n} candidate(s) anonymised.', 'rt.candidates': 'Candidates past retention', 'rt.none': 'Nothing past retention.',
  'ps.dpo_name': 'Data protection contact', 'ps.dpo_email': 'Contact e-mail', 'ps.saved': 'Settings saved.', 'ps.legal': 'Legal deadlines',

  // my privacy
  'mp.notice': 'Privacy notice', 'mp.ack': 'I have read this notice', 'mp.acked': 'You acknowledged version {v} on {d}.', 'mp.none': 'The company has not published its privacy notice yet.',
  'mp.consents': 'Optional consents', 'mp.consent_hint': 'These are optional. You can change them at any time; this does not affect anything done before.',
  'mp.yes': 'I agree', 'mp.no': 'I do not agree', 'mp.request': 'Make a request about my data', 'mp.request_hint': 'HR must reply within {n} days.',
  'mp.my_requests': 'My data requests', 'mp.sent': 'Request sent.', 'mp.saved': 'Saved.',

  // reports
  'ml.title': 'Localisation (Omanisation) report', 'ml.hint': 'Workforce by profession and nationality, for the Ministry of Labour. Every opening of this report is logged.',
  'ml.as_of': 'As of', 'ml.est_no': 'MoL establishment no.', 'ml.cr': 'CR no.', 'ml.professions': 'By profession', 'ml.employees': 'Employees',
  'ml.profession': 'Profession code', 'ml.omani_only': 'Omani only', 'ml.violation': '{n} expatriate(s) in an Omani-only job', 'ml.total': 'Total', 'ml.omani': 'Omani',
  'ml.expat': 'Expatriate', 'ml.pct': 'Omani %', 'ml.target': 'Target {p}%', 'ml.export': 'Export employee list', 'ml.export_prof': 'Export professions', 'ml.nat': 'Nationality', 'ml.basic': 'Basic salary',
  'sp.title': 'Social Protection Fund contributions', 'sp.hint': 'Monthly contribution schedule from the approved payroll run.', 'sp.run': 'Payroll month',
  'sp.not_final': 'This run is not approved yet — figures may change.', 'sp.employer_no': 'SPF employer no.', 'sp.wage': 'Contribution wage', 'sp.ee': 'Employee share',
  'sp.er': 'Employer share', 'sp.total_due': 'Total payable to the Fund', 'sp.none': 'No contributions in this run.', 'sp.no_runs': 'No payroll runs yet.', 'sp.export': 'Export CSV',
  'sp.omanis': 'Omani employees', 'sp.expats': 'Expatriates (employer-only items)',

  // executive
  'xd.title': 'Executive dashboard', 'xd.hint': 'Workforce, Omanisation, cost and risk at a glance — last 12 months.',
  'xd.absence_col': 'Absence', 'xd.headcount': 'Headcount', 'xd.omani': 'Omanisation', 'xd.turnover': 'Turnover (12 months)', 'xd.absence': 'Absence (last month)', 'xd.tenure': 'Average service',
  'xd.age': 'Average age', 'xd.female': 'Women', 'xd.years': '{n} yrs', 'xd.trend_head': 'Headcount, joiners and leavers', 'xd.trend_om': 'Omanisation %',
  'xd.trend_cost': 'Payroll cost (OMR, approved runs)', 'xd.trend_ot': 'Approved overtime hours', 'xd.joiners': 'Joiners', 'xd.leavers': 'Leavers',
  'xd.by_dept': 'By department', 'xd.by_nat': 'By nationality', 'xd.risks': 'Risks and liabilities', 'xd.docs_expired': 'Documents expired',
  'xd.docs_30': 'Documents expiring in 30 days', 'xd.open_pos': 'Open positions', 'xd.injuries': 'Work injuries this year', 'xd.lost_days': 'Days lost to injury',
  'xd.cases': 'Open disciplinary cases', 'xd.exits': 'Exits in progress', 'xd.gratuity': 'End-of-service liability (expatriates)', 'xd.probation': 'On probation', 'xd.notice': 'Serving notice',

  // import
  'im.title': 'Import data', 'im.hint': 'Move employees, documents and opening salaries from the old system. Save the spreadsheet as "CSV UTF-8", check it with a trial run, then import.',
  'im.kind': 'What to import', 'im.k_EMPLOYEES': 'Employees', 'im.k_DOCUMENTS': 'Documents (passport, visa, resident card…)', 'im.k_SALARIES': 'Opening salaries (sent for approval)',
  'im.template': 'Download template', 'im.file': 'CSV file', 'im.rows': '{n} rows read', 'im.missing': 'Missing columns: {c}', 'im.check': 'Trial run (no changes)',
  'im.run': 'Import', 'im.run_q': 'Import {n} rows? Rows with errors are skipped.', 'im.result': '{ok} ok, {f} with errors', 'im.dry': 'Trial run — nothing was saved.',
  'im.saved': 'Imported — {ok} rows saved.', 'im.row': 'Row', 'im.key': 'Record', 'im.message': 'Problem', 'im.history': 'Previous imports', 'im.trial': 'Trial',
  'im.order': 'Order: 1) masters (departments, jobs, grades, categories, locations) in Organisation, 2) employees — managers first, 3) documents, 4) opening salaries, 5) opening leave balances (Leave → Balances → Import).',
  'im.salary_note': 'Opening salaries are proposals: a second person approves them in Approvals as usual.',

  'err.NOT_LINKED_PRIV': 'Your login is not linked to an employee record.',
};
export type GovKey = keyof typeof enGov;
