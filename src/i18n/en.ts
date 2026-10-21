import { enTime } from './en_time';
import { enPay } from './en_pay';
import { enSs } from './en_ss';
import { enRec } from './en_rec';
import { enWf } from './en_wf';
import { enGov } from './en_gov';

const base = {
  'app.name': 'AACT HRMS',
  'app.tagline': 'People, documents and Omanisation in one place',

  // common
  'c.save': 'Save', 'c.saving': 'Saving…', 'c.cancel': 'Cancel', 'c.close': 'Close', 'c.edit': 'Edit', 'c.add': 'Add',
  'c.remove': 'Remove', 'c.search': 'Search', 'c.loading': 'Loading…', 'c.retry': 'Try again', 'c.yes': 'Yes', 'c.no': 'No',
  'c.all': 'All', 'c.none': 'None', 'c.back': 'Back', 'c.next': 'Next', 'c.previous': 'Previous', 'c.export': 'Export CSV',
  'c.print': 'Print', 'c.approve': 'Approve', 'c.reject': 'Reject', 'c.confirm': 'Confirm', 'c.open': 'Open',
  'c.active': 'Active', 'c.inactive': 'Inactive', 'c.status': 'Status', 'c.code': 'Code', 'c.name_en': 'Name (English)',
  'c.name_ar': 'Name (Arabic)', 'c.notes': 'Notes', 'c.date': 'Date', 'c.from': 'From', 'c.to': 'To', 'c.reason': 'Reason',
  'c.company': 'Company', 'c.required': 'Required', 'c.optional': 'optional', 'c.select': 'Choose…', 'c.details': 'Details',
  'c.history': 'History', 'c.current': 'Current', 'c.version': 'Version', 'c.by': 'By', 'c.on': 'On', 'c.total': 'Total',
  'c.page_of': 'Page {page} of {pages}', 'c.rows': '{n} records', 'c.saved': 'Saved', 'c.today': 'Today',
  'c.days': '{n} days', 'c.days_ago': '{n} days ago', 'c.in_days': 'in {n} days', 'c.view': 'View', 'c.download': 'Download',
  'c.yes_sure': 'Yes, continue', 'c.reason_required': 'Give a reason', 'c.not_set': 'Not set', 'c.language': 'Language',
  'c.english': 'English', 'c.arabic': 'العربية', 'c.signout': 'Sign out', 'c.filters': 'Filters', 'c.clear': 'Clear',
  'c.employee': 'Employee', 'c.department': 'Department', 'c.type': 'Type', 'c.number': 'Number',

  // nav
  'nav.dashboard': 'Dashboard', 'nav.employees': 'Employees', 'nav.my_record': 'My record', 'nav.approvals': 'Approvals',
  'nav.compliance': 'Compliance', 'nav.expiries': 'Expiry tracker', 'nav.missing': 'Missing documents',
  'nav.omanisation': 'Omanisation', 'nav.targets': 'Omanisation targets', 'nav.organisation': 'Organisation',
  'nav.admin': 'Administration', 'nav.users': 'Users and roles', 'nav.settings': 'Settings', 'nav.audit': 'Audit trail',
  'nav.notifications': 'Notifications', 'nav.menu': 'Menu',

  // auth
  'env.local': 'LOCAL – dummy data', 'env.test': 'not live data',
  'auth.signin': 'Sign in', 'auth.signup': 'Create account', 'auth.email': 'E-mail', 'auth.password': 'Password',
  'auth.full_name': 'Full name', 'auth.forgot': 'Forgot password?', 'auth.reset_send': 'Send reset link',
  'auth.reset_sent': 'If an account exists for that e-mail, a reset link is on its way.',
  'auth.signup_done': 'Account created. Check your e-mail to confirm it, then sign in.',
  'auth.have_account': 'Already have an account? Sign in', 'auth.no_account': 'New here? Create an account',
  'auth.new_password': 'New password', 'auth.set_password': 'Set password', 'auth.password_set': 'Password changed.',
  'auth.password_rule': 'At least 10 characters, with upper-case and lower-case letters and a number.',
  'auth.config_missing': 'The app is not connected to its database. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY and rebuild.',

  // setup / no access
  'setup.title': 'Waiting for access',
  'setup.body': 'You are signed in as {email}, but no role has been given to you yet. Ask the HR administrator to give you access.',
  'setup.first_title': 'Set up AACT HRMS',
  'setup.first_body': 'No administrator exists yet. As the first user you can become the super administrator, then give everyone else their roles.',
  'setup.claim': 'Make me the administrator', 'setup.inactive': 'Your account has been deactivated. Contact the HR administrator.',
  'setup.refresh': 'Check again',

  // dashboard
  'dash.title': 'Dashboard', 'dash.headcount': 'Headcount', 'dash.omani': 'Omani', 'dash.expat': 'Expatriate',
  'dash.probation': 'On probation', 'dash.notice': 'Serving notice', 'dash.joiners': 'Joined in 30 days',
  'dash.leavers': 'Left in 30 days', 'dash.runway': 'Document expiry', 'dash.runway_hint': 'Documents and contracts of current employees',
  'dash.missing': '{n} mandatory documents missing for {m} employees', 'dash.expiring_soon': 'Expiring in the next 30 days',
  'dash.nothing_expiring': 'Nothing expires in the next 30 days.', 'dash.by_department': 'Headcount by department',
  'dash.by_nationality': 'By nationality', 'dash.omanisation': 'Omanisation by company', 'dash.no_target': 'no approved target',
  'dash.approvals': 'Waiting for your approval', 'dash.approvals_none': 'Nothing waits for your approval.',
  'dash.salary_approvals': '{n} salary revisions', 'dash.bank_approvals': '{n} bank account changes',
  'dash.target_approvals': '{n} Omanisation targets', 'dash.probation_due': 'Probation ending in 30 days',
  'dash.my_job': 'My job', 'dash.my_documents': 'My documents expiring in 90 days', 'dash.team': 'My team ({n})',
  'dash.team_expiries': 'Team documents expiring in 60 days', 'dash.no_team_expiries': 'No team document expires in the next 60 days.',
  'dash.welcome': 'Welcome, {name}',

  // buckets
  'b.EXPIRED': 'Expired', 'b.D30': '30 days', 'b.D60': '31–60 days', 'b.D90': '61–90 days', 'b.LATER': 'Later',

  // employee status
  'st.PROBATION': 'Probation', 'st.ACTIVE': 'Active', 'st.NOTICE': 'Notice', 'st.SUSPENDED': 'Suspended', 'st.SEPARATED': 'Left',
  'st.CURRENT': 'Current employees', 'st.ALL': 'Everyone',

  // employees list
  'emp.title': 'Employees', 'emp.new': 'Add employee', 'emp.search_ph': 'Name, employee number, mobile…',
  'emp.no': 'Emp. no.', 'emp.name': 'Name', 'emp.job': 'Job title', 'emp.nationality': 'Nationality', 'emp.joined': 'Joined',
  'emp.location': 'Location', 'emp.manager': 'Manager', 'emp.omani_filter': 'Omani', 'emp.expat_filter': 'Expatriate',
  'emp.empty': 'No employees match these filters.', 'emp.empty_none': 'No employees yet. Add the first one.',

  // employee form
  'ef.title_new': 'Add employee', 'ef.personal': 'Personal details', 'ef.employment': 'Employment',
  'ef.full_name_en': 'Full name (English)', 'ef.full_name_ar': 'Full name (Arabic)', 'ef.preferred_name': 'Preferred name',
  'ef.dob': 'Date of birth', 'ef.gender': 'Gender', 'ef.male': 'Male', 'ef.female': 'Female', 'ef.marital': 'Marital status',
  'ef.SINGLE': 'Single', 'ef.MARRIED': 'Married', 'ef.DIVORCED': 'Divorced', 'ef.WIDOWED': 'Widowed',
  'ef.civil': 'Civil ID / resident card no.', 'ef.personal_email': 'Personal e-mail', 'ef.work_email': 'Work e-mail',
  'ef.mobile': 'Mobile', 'ef.alt_phone': 'Alternative phone', 'ef.address': 'Address', 'ef.city': 'City / town',
  'ef.wilayat': 'Wilayat', 'ef.governorate': 'Governorate', 'ef.address_country': 'Country of address',
  'ef.employee_no': 'Employee number', 'ef.employee_no_hint': 'Leave blank to number automatically.',
  'ef.join_date': 'Joining date', 'ef.probation_end': 'Probation ends', 'ef.probation_hint': 'Leave blank if there is no probation.',
  'ef.grade': 'Grade', 'ef.category': 'Category', 'ef.location': 'Work location', 'ef.cost_centre': 'Cost centre',
  'ef.cost_centre_hint': 'Blank uses the department\'s cost centre.', 'ef.manager': 'Reports to', 'ef.employment_type': 'Employment type',
  'ef.FULL_TIME': 'Full time', 'ef.PART_TIME': 'Part time', 'ef.TEMPORARY': 'Temporary', 'ef.TRAINEE': 'Trainee',
  'ef.shift': 'Shift / roster code', 'ef.duplicate_tick': 'This is a different person with the same name and date of birth',
  'ef.exception_reason': 'Reason for the Omani-only exception',
  'ef.exception_hint': 'This job is Omani-only. A non-Omani can be placed only with an approved exception.',
  'ef.create': 'Create employee', 'ef.created': 'Employee {no} created',

  // employee detail
  'ed.tab_profile': 'Profile', 'ed.tab_job': 'Job history', 'ed.tab_contract': 'Contract', 'ed.tab_pay': 'Salary',
  'ed.tab_bank': 'Bank', 'ed.tab_documents': 'Documents', 'ed.tab_history': 'History',
  'ed.team_view': 'You see the details a line manager needs. Personal, salary and document details are hidden.',
  'ed.edit_personal': 'Edit personal details', 'ed.emergency': 'Emergency contacts', 'ed.add_contact': 'Add contact',
  'ed.contact_name': 'Name', 'ed.relationship': 'Relationship', 'ed.phone': 'Phone', 'ed.next_of_kin': 'Next of kin',
  'ed.no_contacts': 'No emergency contact recorded.', 'ed.photo': 'Photo', 'ed.change_photo': 'Change photo',
  'ed.current_job': 'Current job', 'ed.change_job': 'Change job', 'ed.since': 'since {date}',
  'ed.service': 'Service', 'ed.first_joined': 'First joined', 'ed.linked_login': 'Login',
  'ed.no_login': 'No login linked', 'ed.exceptions': 'Omani-only exceptions', 'ed.revoke': 'Revoke',
  'ed.actions': 'Employment actions', 'ed.confirm': 'Confirm employment', 'ed.notice': 'Record notice',
  'ed.withdraw_notice': 'Withdraw notice', 'ed.suspend': 'Suspend', 'ed.reinstate': 'Reinstate', 'ed.separate': 'Record leaving',
  'ed.rehire': 'Rehire', 'ed.last_working': 'Last working day', 'ed.leaving_reason': 'Reason for leaving',
  'ed.RESIGNATION': 'Resignation', 'ed.TERMINATION': 'Termination', 'ed.END_OF_CONTRACT': 'End of contract',
  'ed.RETIREMENT': 'Retirement', 'ed.DEATH': 'Death', 'ed.OTHER': 'Other', 'ed.leaving_date': 'Leaving date',
  'ed.rehire_date': 'Rehire date', 'ed.separate_warn': 'This closes the job, ends the active contract and revokes any Omani-only exception.',

  // assignments
  'as.effective_from': 'Effective from', 'as.reason': 'Reason', 'as.TRANSFER': 'Transfer', 'as.PROMOTION': 'Promotion',
  'as.DEMOTION': 'Demotion', 'as.REORGANISATION': 'Reorganisation', 'as.CORRECTION': 'Correction of current record',
  'as.OTHER': 'Other', 'as.JOIN': 'Joining', 'as.REHIRE': 'Rehire', 'as.period': 'Period', 'as.open_ended': 'to date',
  'as.correction_hint': 'A correction changes the current record itself. Explain it in the notes.',
  'as.keep_hint': 'Fields you leave unchanged keep their current values.',

  // contract
  'co.none': 'No contract recorded.', 'co.new': 'New contract', 'co.correct': 'Correct details', 'co.type': 'Contract type',
  'co.FIXED_TERM': 'Fixed term', 'co.INDEFINITE': 'Indefinite', 'co.no': 'Contract number', 'co.start': 'Start date',
  'co.end': 'End date', 'co.probation_days': 'Probation (days)', 'co.notice_days': 'Notice (days)',
  'co.hours': 'Hours per week', 'co.mol': 'Ministry registration no.', 'co.document': 'Signed copy',
  'co.supersede_hint': 'A new contract replaces the active one; the old one stays in history.',
  'co.policy_hint': 'Probation and notice are taken from the contract. Check them against the Labour Law before saving.',
  'co.ACTIVE': 'Active', 'co.SUPERSEDED': 'Replaced', 'co.ENDED': 'Ended', 'co.CANCELLED': 'Cancelled',

  // pay
  'pay.current': 'Current salary', 'pay.none': 'No approved salary yet.', 'pay.propose': 'Propose a revision',
  'pay.component': 'Component', 'pay.amount': 'Amount (OMR)', 'pay.gross': 'Gross monthly', 'pay.deductions': 'Fixed deductions',
  'pay.pending': 'Waiting for approval', 'pay.scheduled': 'Approved, starts later', 'pay.grade_band': 'Grade {grade}: {min} – {max}',
  'pay.warning_band': 'The basic salary is outside the grade band. The approver will see this.',
  'pay.withdraw': 'Withdraw', 'pay.JOIN': 'On joining', 'pay.INCREMENT': 'Increment', 'pay.PROMOTION': 'Promotion',
  'pay.ADJUSTMENT': 'Adjustment', 'pay.CORRECTION': 'Correction', 'pay.REHIRE': 'Rehire', 'pay.proposed_by': 'Proposed by {name}',
  'pay.decided_by': 'Decided by {name}', 'pay.APPROVED': 'Approved', 'pay.PENDING': 'Pending', 'pay.REJECTED': 'Rejected',
  'pay.SUPERSEDED': 'Replaced', 'pay.approve_title': 'Approve salary revision', 'pay.reject_title': 'Reject salary revision',
  'pay.self_note': 'You proposed this revision, so someone else must approve it.',

  // bank
  'bk.current': 'Salary account', 'bk.none': 'No approved bank account.', 'bk.request': 'Request a change',
  'bk.bank': 'Bank', 'bk.branch': 'Branch', 'bk.holder': 'Account holder', 'bk.account': 'Account number', 'bk.iban': 'IBAN',
  'bk.swift': 'SWIFT / BIC', 'bk.pending': 'Change waiting for approval', 'bk.masked': 'Numbers are partly hidden for your role.',
  'bk.approve_title': 'Approve bank account change', 'bk.reject_title': 'Reject bank account change',
  'bk.check_hint': 'Check the new details against the bank letter before approving.',

  // documents
  'doc.add': 'Add document', 'doc.replace': 'Renew / replace', 'doc.correct': 'Correct details', 'doc.cancel': 'Cancel document',
  'doc.verify': 'Mark verified', 'doc.verified': 'Verified by {name}', 'doc.unverified': 'Not verified',
  'doc.type': 'Document type', 'doc.number': 'Document number', 'doc.title': 'Title / description', 'doc.issue': 'Issue date',
  'doc.expiry': 'Expiry date', 'doc.authority': 'Issued by', 'doc.place': 'Place of issue', 'doc.file': 'File',
  'doc.file_hint': 'PDF, JPG, PNG or WEBP, up to 10 MB.', 'doc.no_file': 'No file attached', 'doc.show_history': 'Show replaced and cancelled',
  'doc.empty': 'No documents recorded.', 'doc.checklist': 'Mandatory documents', 'doc.MISSING': 'Missing',
  'doc.EXPIRED': 'Expired', 'doc.EXPIRING': 'Expires soon', 'doc.OK': 'In order', 'doc.SUPERSEDED': 'Replaced',
  'doc.CANCELLED': 'Cancelled', 'doc.ACTIVE': 'Current', 'doc.sensitive': 'Restricted', 'doc.uploading': 'Uploading…',
  'doc.cancel_reason': 'Why is it being cancelled?', 'doc.replace_hint': 'The current version is kept in history as replaced.',
  'doc.sensitive_hidden': 'Medical and disciplinary documents are hidden for your role.',
  'doc.file_type': 'Choose a PDF, JPG, PNG or WEBP file.', 'doc.file_size': 'The file is larger than 10 MB.',

  // history
  'h.events': 'Employment events', 'h.changes': 'Field changes', 'h.no_events': 'No events yet.',
  'ev.JOIN': 'Joined', 'ev.CONFIRM': 'Confirmed', 'ev.TRANSFER': 'Transferred', 'ev.PROMOTION': 'Promoted', 'ev.DEMOTION': 'Demoted',
  'ev.REORGANISATION': 'Reorganised', 'ev.ASSIGNMENT_CORRECTION': 'Job record corrected', 'ev.SALARY_REVISION': 'Salary revised',
  'ev.BANK_CHANGE': 'Bank account changed', 'ev.CONTRACT': 'Contract', 'ev.NOTICE': 'Notice recorded',
  'ev.NOTICE_WITHDRAWN': 'Notice withdrawn', 'ev.SUSPEND': 'Suspended', 'ev.REINSTATE': 'Reinstated', 'ev.SEPARATION': 'Left',
  'ev.REHIRE': 'Rehired', 'ev.PERSONAL_UPDATE': 'Personal details updated', 'ev.OMANISATION_EXCEPTION': 'Omani-only exception',

  // compliance
  'cp.expiries_title': 'Expiry tracker', 'cp.within': 'Expiring within', 'cp.include_expired': 'Include expired',
  'cp.days_left': 'Days left', 'cp.expiry': 'Expires', 'cp.no_expiries': 'Nothing expires in this window.',
  'cp.scan': 'Send reminders now', 'cp.scan_done': '{n} new reminders sent.', 'cp.contract': 'Employment contract',
  'cp.missing_title': 'Missing mandatory documents', 'cp.no_missing': 'Every current employee has all mandatory documents.',
  'cp.missing_hint': 'Which documents are mandatory is set under Organisation → Document types.',

  // omanisation
  'om.title': 'Omanisation', 'om.as_of': 'As of', 'om.overall': 'Company ratio', 'om.target': 'Target', 'om.gap': 'Omanis needed',
  'om.meets': 'Meets target', 'om.below': 'Below target', 'om.no_target': 'No approved target',
  'om.basis': 'Counting basis', 'om.basis_text': 'Employees on the books on the date, in categories that count for Omanisation. Ratio = Omani ÷ total. Confirm this basis with the Ministry of Labour rules that apply to the company.',
  'om.by_department': 'By department', 'om.by_job': 'By job title', 'om.by_profession': 'By profession code',
  'om.placements': 'Non-Omanis in Omani-only jobs', 'om.no_placements': 'No non-Omani holds an Omani-only job.',
  'om.no_exception': 'No exception — must be resolved', 'om.scenario': 'Plan hires and departures',
  'om.scenario_hint': 'See how planned changes would move the ratio. Nothing is saved.',
  'om.hire_omani': 'Omanis to hire', 'om.hire_expat': 'Expatriates to hire', 'om.leave_omani': 'Omanis leaving',
  'om.leave_expat': 'Expatriates leaving', 'om.replace_expat': 'Expatriates replaced by Omanis',
  'om.projected': 'Projected ratio', 'om.projected_total': 'Projected headcount', 'om.still_needed': 'Still needed for target',
  'om.headcount': 'Headcount', 'om.ratio': 'Ratio',

  // targets
  'tg.title': 'Omanisation targets', 'tg.propose': 'Propose a target', 'tg.scope': 'Applies to', 'tg.ENTITY': 'Whole company',
  'tg.DEPARTMENT': 'Department', 'tg.JOB_TITLE': 'Job title', 'tg.PROFESSION_CODE': 'Profession code',
  'tg.pct': 'Target %', 'tg.basis': 'Basis', 'tg.LEGAL': 'Legal requirement', 'tg.COMPANY_POLICY': 'Company policy',
  'tg.source': 'Source', 'tg.source_hint': 'Ministry decision or circular number and date, or the internal policy reference.',
  'tg.PENDING': 'Waiting for approval', 'tg.APPROVED': 'Approved', 'tg.REJECTED': 'Rejected', 'tg.RETIRED': 'Retired',
  'tg.retire': 'Retire', 'tg.retire_title': 'Retire target', 'tg.empty': 'No targets recorded. Targets are never pre-filled: enter each one from its official source.',
  'tg.maker_checker': 'A target takes effect only after a second person approves it.',

  // approvals
  'ap.title': 'Approvals', 'ap.salary': 'Salary revisions', 'ap.bank': 'Bank account changes', 'ap.targets': 'Omanisation targets',
  'ap.none': 'Nothing is waiting.', 'ap.yours': 'Proposed by you — someone else approves', 'ap.open_employee': 'Open employee',
  'ap.decision_note': 'Note (required when rejecting)', 'ap.done_approve': 'Approved', 'ap.done_reject': 'Rejected',

  // organisation
  'org.title': 'Organisation', 'org.entity': 'Companies', 'org.location': 'Locations', 'org.cost_centre': 'Cost centres',
  'org.department': 'Departments', 'org.grade': 'Grades', 'org.job_title': 'Job titles', 'org.category': 'Employee categories',
  'org.document_type': 'Document types', 'org.new': 'New record', 'org.empty': 'Nothing here yet.',
  'org.choose_company': 'Choose a company first.', 'org.f_cr': 'CR number', 'org.f_mol': 'Ministry establishment no.',
  'org.f_sector': 'Sector', 'org.f_country': 'Country', 'org.f_currency': 'Currency', 'org.f_address': 'Address',
  'org.f_type': 'Type', 'org.f_city': 'City', 'org.f_governorate': 'Governorate', 'org.f_gl': 'GL code',
  'org.f_parent': 'Parent department', 'org.f_cost_centre': 'Cost centre', 'org.f_head': 'Head of department',
  'org.f_level': 'Level', 'org.f_min': 'Minimum basic (OMR)', 'org.f_max': 'Maximum basic (OMR)',
  'org.f_profession': 'Profession code (Ministry)', 'org.f_omani_only': 'Omani-only job', 'org.f_omani_source': 'Source of the restriction',
  'org.f_omani_verified': 'Verified against the official source', 'org.f_description': 'Job description',
  'org.f_qualifications': 'Required qualifications', 'org.f_pay_basis': 'Pay basis', 'org.f_counts': 'Counts for Omanisation',
  'org.f_category': 'Group', 'org.f_has_number': 'Has a number', 'org.f_has_expiry': 'Has an expiry date',
  'org.f_alert_days': 'Remind before expiry (days)', 'org.f_alert_hint': 'Comma-separated, e.g. 90, 60, 30',
  'org.f_applies': 'Required for', 'org.f_mandatory': 'Mandatory', 'org.f_multiple': 'More than one allowed',
  'org.f_sensitive': 'Restricted (medical / disciplinary)', 'org.f_rule_basis': 'Basis', 'org.f_rule_ref': 'Reference', 'org.f_sort': 'Order',
  'org.omani_only_rule': 'Changing the Omani-only flag needs the rule-approval permission and a source.',
  'loc.FACTORY': 'Factory', 'loc.OFFICE': 'Office', 'loc.WAREHOUSE': 'Warehouse', 'loc.SITE': 'Site', 'loc.ACCOMMODATION': 'Accommodation',
  'pb.MONTHLY': 'Monthly', 'pb.DAILY': 'Daily', 'pb.HOURLY': 'Hourly',
  'ap_to.ALL': 'Everyone', 'ap_to.OMANI': 'Omanis', 'ap_to.EXPAT': 'Expatriates',
  'dc.IDENTITY': 'Identity', 'dc.IMMIGRATION': 'Immigration', 'dc.EMPLOYMENT': 'Employment', 'dc.QUALIFICATION': 'Qualification',
  'dc.MEDICAL': 'Medical', 'dc.LICENCE': 'Licence', 'dc.POLICY': 'Policy', 'dc.DISCIPLINARY': 'Disciplinary', 'dc.OTHER': 'Other',

  // users
  'us.title': 'Users and roles', 'us.email': 'E-mail', 'us.name': 'Name', 'us.roles': 'Roles', 'us.employee': 'Employee record',
  'us.link': 'Link employee', 'us.unlink': 'Unlink', 'us.deactivate': 'Deactivate', 'us.activate': 'Activate',
  'us.edit_roles': 'Change roles', 'us.invite_hint': 'People create their own account on the sign-in page, then appear here. After everyone is in, turn off sign-ups in Supabase Auth.',
  'us.roles_matrix': 'What each role can do', 'us.you': 'you',

  // settings
  'set.title': 'Settings', 'set.numbering': 'Employee numbering', 'set.prefix': 'Prefix', 'set.digits': 'Digits',
  'set.example': 'Next numbers look like {ex}', 'set.horizon': 'Expiry horizon (days)', 'set.default_lang': 'Default language',
  'set.my_profile': 'My profile', 'set.display_name': 'Display name',

  // audit
  'au.title': 'Audit trail', 'au.table': 'Record type', 'au.action': 'Action', 'au.user': 'Changed by', 'au.when': 'When',
  'au.changes': 'Changes', 'au.access': 'Sensitive data viewed', 'au.INSERT': 'Created', 'au.UPDATE': 'Changed', 'au.DELETE': 'Removed',
  'au.empty': 'No changes recorded for these filters.', 'au.kind': 'Data viewed',

  // notifications
  'nt.title': 'Notifications', 'nt.mark_all': 'Mark all read', 'nt.empty': 'No notifications.', 'nt.unread': '{n} unread',

  // errors
  'err.NOT_SIGNED_IN': 'Your session has ended. Sign in again.',
  'err.NOT_ALLOWED': 'Your role does not allow this.',
  'err.NOT_FOUND': 'The record was not found. It may have been changed by someone else.',
  'err.REQUIRED': 'Something required is missing.',
  'err.INVALID': 'Some details are not valid.',
  'err.INVALID_DATE': 'A date is not valid.', 'err.INVALID_EMAIL': 'An e-mail address is not valid.',
  'err.INVALID_PHONE': 'A phone number is not valid.', 'err.INVALID_AMOUNT': 'An amount is not valid (use up to 3 decimals).',
  'err.INVALID_NUMBER': 'A number is not valid.', 'err.INVALID_ID': 'A reference is not valid.',
  'err.DUPLICATE': 'This already exists.', 'err.DUPLICATE_DOCUMENT': 'A current document of this type already exists — renew it instead.',
  'err.POSSIBLE_DUPLICATE': 'This looks like an existing employee.',
  'err.OMANI_ONLY': 'This job is reserved for Omanis.', 'err.SELF_APPROVAL': 'Someone other than you must approve this.',
  'err.PENDING_EXISTS': 'A request is already waiting for approval.', 'err.OVERLAP': 'This overlaps an approved record.',
  'err.ADMIN_EXISTS': 'An administrator already exists.', 'err.NETWORK': 'No connection to the server. Check the internet and try again.',
  'err.UNKNOWN': 'Something went wrong.',
};

export type BaseKey = keyof typeof base;
export const en = { ...base, ...enTime, ...enPay, ...enSs, ...enRec, ...enWf, ...enGov };
export type Key = keyof typeof en;
