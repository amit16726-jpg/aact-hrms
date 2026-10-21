/** Phase 4 — self-service & letters (English). Arabic in ar_ss.ts must have the same keys. */
export const enSs = {
  // navigation
  'snav.my_hr': 'My HR', 'snav.team': 'My team', 'snav.requests': 'Requests and letters',

  // My HR portal
  'me.title': 'My HR', 'me.hint': 'Your details, leave, payslips, letters and requests in one place.',
  'me.not_linked': 'Your login is not linked to an employee record yet. Ask HR to link it.',
  'me.tab_overview': 'Overview', 'me.tab_details': 'My details', 'me.tab_letters': 'Letters', 'me.tab_requests': 'My requests', 'me.tab_privacy': 'My data',
  'me.job': 'Job', 'me.manager': 'Line manager', 'me.joined': 'Joined', 'me.probation_until': 'Probation until {d}',
  'me.annual_left': 'Annual leave left', 'me.sick_used': 'Sick leave used', 'me.days': '{n} days', 'me.leave_pending': '{n} leave request(s) waiting',
  'me.next_leave': 'Next leave', 'me.last_payslip': 'Last payslip', 'me.no_payslip': 'No payslip yet.', 'me.open_leave': 'Leave',
  'me.open_payslips': 'All payslips', 'me.open_record': 'My full record', 'me.expiring': 'My documents expiring soon',
  'me.no_expiring': 'No document expires in the next 90 days.', 'me.expires_in': 'expires {d} ({n} days)', 'me.expired': 'expired {d}',
  'me.open_requests': '{n} request(s) in progress', 'me.letters_ready': 'Letters ready',
  'me.quick': 'Quick actions', 'me.q_leave': 'Apply for leave', 'me.q_letter': 'Request a letter', 'me.q_update': 'Update my details',
  'me.q_correction': 'Report wrong information',

  // details & change requests
  'me.personal': 'Personal and contact details', 'me.edit_request': 'Request a change', 'me.contacts': 'Emergency contacts',
  'me.contacts_request': 'Change emergency contacts', 'me.bank': 'Salary bank account', 'me.bank_none': 'No approved bank account.',
  'me.bank_request': 'Change bank account', 'me.bank_pending': 'A bank change is waiting for approval.',
  'me.locked_fields': 'Name, date of birth, nationality, ID number and job can only be changed by HR. If any of them is wrong, report it below.',
  'me.correction': 'Report wrong information', 'me.correction_hint': 'Tell HR what is wrong and what the correct information is. HR answers within 45 days, as required by the Personal Data Protection Law.',
  'me.correction_field': 'Which information?', 'me.correction_reason': 'What is wrong, and what is correct?',
  'me.change_sent': 'Request sent to HR.', 'me.no_change': 'Nothing was changed.', 'me.change_why': 'Reason (optional)',
  'me.bank_hint': 'HR checks the request and Finance approves the new account before salaries are paid to it. Keep a bank letter or card ready.',
  'me.contacts_hint': 'This list replaces your current emergency contacts once HR approves it.',
  'me.add_contact': 'Add another contact', 'me.remove_contact': 'Remove',

  // request statuses & kinds
  'rq.k_PROFILE': 'Personal details', 'rq.k_EMERGENCY': 'Emergency contacts', 'rq.k_BANK': 'Bank account', 'rq.k_CORRECTION': 'Correction',
  'rq.st_PENDING': 'Waiting for HR', 'rq.st_APPROVED': 'Approved', 'rq.st_REJECTED': 'Rejected', 'rq.st_CANCELLED': 'Cancelled',
  'rq.none': 'No requests.', 'rq.requested': 'Requested', 'rq.due': 'Answer due', 'rq.overdue': 'Overdue', 'rq.what': 'What changes',
  'rq.old': 'Now', 'rq.new': 'Requested', 'rq.cancel': 'Cancel request', 'rq.cancel_q': 'Cancel this request?', 'rq.decided': 'Decided by {n} on {d}',
  'rq.approve_title': 'Approve change request', 'rq.reject_title': 'Reject change request', 'rq.correction_note': 'Say what was corrected',
  'rq.bank_note': 'Approving sends the new account to Finance for the final approval.',
  'rq.title': 'Requests and letters', 'rq.hint': 'Changes employees asked for and letters to prepare or approve.',
  'rq.tab_changes': 'Change requests', 'rq.tab_letters': 'Letters', 'rq.tab_setup': 'Letter settings', 'rq.filter_open': 'Open',

  // letters
  'lt.SALARY_CERT': 'Salary certificate', 'lt.EXPERIENCE': 'Experience letter', 'lt.NOC': 'No objection certificate (NOC)', 'lt.EMPLOYMENT': 'Employment letter',
  'lt.h_SALARY_CERT': 'For a bank, embassy or landlord: states your job and salary.',
  'lt.h_EMPLOYMENT': 'Confirms you work here; salary only if you ask for it.',
  'lt.h_NOC': 'The company has no objection to travel or another activity.',
  'lt.h_EXPERIENCE': 'Issued when you leave: dates of service and job.',
  'lt.st_REQUESTED': 'Requested', 'lt.st_PREPARED': 'Prepared — waiting for approval', 'lt.st_ISSUED': 'Issued', 'lt.st_REJECTED': 'Rejected', 'lt.st_CANCELLED': 'Cancelled',
  'lt.revoked': 'Withdrawn', 'lt.new': 'Request a letter', 'lt.new_hr': 'New letter', 'lt.type': 'Letter', 'lt.language': 'Language',
  'lt.l_BOTH': 'English and Arabic', 'lt.l_EN': 'English', 'lt.l_AR': 'Arabic', 'lt.addressee': 'Addressed to', 'lt.addressee_ph': 'e.g. The Manager, Bank Muscat',
  'lt.purpose': 'Purpose', 'lt.purpose_ph': 'e.g. personal loan, visa application', 'lt.include_salary': 'State my salary', 'lt.include_salary_hr': 'State the salary',
  'lt.destination': 'Travel destination', 'lt.activity': 'Or another activity', 'lt.activity_ph': 'e.g. obtaining a driving licence',
  'lt.from': 'From', 'lt.to': 'To', 'lt.sent': 'Letter requested. HR will prepare it.', 'lt.none': 'No letters yet.',
  'lt.ref': 'Reference', 'lt.issued_on': 'Issued {d}', 'lt.view': 'View / print', 'lt.prepare': 'Prepare', 'lt.prepare_title': 'Prepare letter',
  'lt.prepared': 'Prepared and sent for approval.', 'lt.approve_issue': 'Approve and issue', 'lt.issued': 'Letter issued.',
  'lt.cancel': 'Cancel', 'lt.revoke': 'Withdraw', 'lt.revoke_title': 'Withdraw this letter', 'lt.revoke_hint': 'The online check will then show the letter as withdrawn.',
  'lt.prepare_now': 'Prepare it now (another person approves)', 'lt.salary_hidden': 'The salary is hidden for your role.',
  'lt.draft': 'DRAFT — not valid until approved', 'lt.verify_line': 'Check this letter at', 'lt.code': 'Verification code',
  'lt.signature': 'Signature and company stamp', 'lt.date': 'Date', 'lt.total': 'Total', 'lt.component': 'Component', 'lt.amount_omr': 'Amount (OMR)',
  'lt.no_salary': 'No approved salary to state.', 'lt.requested_by': 'Requested by {n}', 'lt.prepared_by': 'Prepared by {n}', 'lt.approved_by': 'Approved by {n}',
  'lt.cr': 'CR {n}', 'lt.withdrawn_banner': 'This letter has been withdrawn: {r}',

  // letter settings
  'ls.title': 'Letter settings', 'ls.hint': 'Who signs the letters and the address printed for checking them.',
  'ls.signatory_en': 'Signatory title (English)', 'ls.signatory_ar': 'Signatory title (Arabic)', 'ls.name_en': 'Signatory name (English)',
  'ls.name_ar': 'Signatory name (Arabic)', 'ls.footer_en': 'Footer (English)', 'ls.footer_ar': 'Footer (Arabic)',
  'ls.verify_url': 'Address for checking letters', 'ls.verify_hint': 'The public address of this system, e.g. https://hr.aact.om. Blank uses the current address.',

  // public verification
  'vf.title': 'Check an AACT letter', 'vf.hint': 'Enter the reference and the 12-character code printed at the bottom of the letter.',
  'vf.ref': 'Reference', 'vf.code': 'Verification code', 'vf.check': 'Check', 'vf.valid': 'This letter is genuine.',
  'vf.invalid': 'No letter matches this reference and code.', 'vf.revoked': 'This letter was issued but has since been withdrawn.',
  'vf.issued': 'Issued on {d}', 'vf.for': 'Employee', 'vf.by': 'Issued by', 'vf.signin': 'Sign in',

  // my team
  'tm.title': 'My team', 'tm.hint': 'The people who report to you, today.', 'tm.none': 'Nobody reports to you.', 'tm.direct': 'Direct',
  'tm.indirect': 'Through a manager', 'tm.today': 'Today', 'tm.on_leave': 'On leave until {d}', 'tm.pending': '{n} waiting for you',
  'tm.expiring': '{n} document(s) expiring', 'tm.probation': 'Probation ends {d}', 'tm.no_record': 'No attendance yet', 'tm.contact': 'Contact',
  'tm.counts': '{n} people · {p} present · {l} on leave',

  // privacy
  'pv.title': 'My personal data', 'pv.hint': 'Under the Personal Data Protection Law you may see the data held about you and ask for it to be corrected.',
  'pv.download': 'Download a copy of my data', 'pv.downloaded': 'Your data was downloaded.', 'pv.correct': 'Ask for a correction',
  'pv.what': 'The copy includes your personal details, job history, contracts, documents list, bank accounts, salary history, leave, payslips, requests and letters.',

  // e-mail
  'em.title': 'E-mail notifications (Microsoft 365)', 'em.hint': 'Send each notification by e-mail as well. Needs the send-mail function and the Microsoft 365 app details set on the server.',
  'em.enabled': 'Send e-mails', 'em.app_url': 'Address of this system (for links)', 'em.sender_name': 'Sender name',
  'em.queue': 'Queue', 'em.queued': 'Waiting', 'em.sent': 'Sent', 'em.failed': 'Failed', 'em.test': 'Send me a test e-mail', 'em.test_sent': 'Test e-mail queued.',
  'em.recent': 'Latest e-mails', 'em.none': 'Nothing sent yet.', 'em.to': 'To', 'em.subject': 'Subject',
  'em.my_pref': 'E-mail me my notifications', 'em.my_pref_hint': 'Approvals, decisions and reminders are also sent to {e}.', 'em.off_globally': 'E-mail sending is switched off for the company.',

  // dashboard & approvals
  'sd.tasks_changes': '{n} change request(s) to decide', 'sd.tasks_letters': '{n} letter(s) to prepare or approve',
  'sd.my_requests': '{n} of my requests in progress', 'sd.letters_ready': '{n} letter(s) ready for me',
  'err.NOT_LINKED': 'Your login is not linked to an employee record. Ask HR to link it.', 'err.NO_CHANGE': 'Nothing was changed.',
  'sap.changes': 'Change requests from employees', 'sap.letters': 'Letters', 'sap.open': 'Open',
};
export type SsKey = keyof typeof enSs;
