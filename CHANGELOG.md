# Changelog

## 1.6.0 — 25 Oct 2026 — Phase 6: people operations

- **Performance** (`Performance`): appraisal cycles per company (draft → open → closed). Opening a cycle creates a review for everyone
  employed at the period end, with the line manager at that date as reviewer and a standard goal list. Steps: employee self-assessment
  (self-ratings only) → line manager (ratings 1–5, weighted overall rating, comments) → HR finalises (someone other than the reviewer)
  or returns → employee acknowledges with an optional comment. Everyone's reviews, my team, my reviews; tasks on the approvals page.
- **Improvement plans** (poor-performance notice): written plan with the areas to improve and the support given; the improvement period
  must be **at least 6 months** (Labour Law) and "not improved" can be recorded only after it ends. The employee acknowledges receipt.
- **Training** (`Training`): course catalogue (category, certificate validity, mandatory flag); records for many employees at once with
  expiry worked out from the validity; renewals supersede the old certificate. **Certificates join the expiry tracker and the daily
  expiry alerts.** Missing-mandatory-course list. Employees see their own records (without cost).
- **Discipline** (`Discipline`, sensitive, every view logged): case → investigation (employee asked for a written response) → proposed
  penalty → decision by a person who neither opened nor proposed it. Penalty limits are company policy (default 5 days' wage deduction,
  5 days' suspension) and a deduction becomes a one-off payroll deduction waiting for Finance approval (25 % limit applies there).
  The employee sees the case (without internal notes), responds and may appeal.
- **Assets & PPE** (`Assets & PPE`): item catalogue (PPE, uniform, IT, tools, vehicles, keys, cards; returnable or consumable; cost;
  replacement interval); issue to many employees at once; return with condition; damage or loss can propose a salary recovery
  (Finance approves). Overdue returns flagged.
- **Housing & transport** (`Housing & transport`): accommodation and bus routes with capacity, rooms/beds or pick-up points; moving
  someone ends the previous assignment of the same kind.
- **Work injuries** (`Work injuries`): register with severity, days lost, root cause, corrective action and Social Protection Fund
  reporting; serious injuries alert HR; report deadline (default 7 days, configurable) and overdue flag; closing needs the corrective
  action and, except first aid, the report date.
- **Exit workflow** (`Exits`): start an exit (resignation, termination, end of contract, retirement) — the notice rule (**30 days for
  monthly-paid, 15 for others**, unless pay in lieu or on probation) and **non-compete ≤ 2 years** are enforced, and the notice is
  recorded on the employee. Clearance list built automatically: items still with the employee (ticked when received back),
  housing/transport, standard steps, and expatriate (resident card, work permit, air ticket) or Omani (SPF) steps. Exit interview;
  completing the exit separates the employee on the last working day; cancelling withdraws the notice.
- **HR policy limits** in Settings (deduction and suspension limits, injury reporting deadline); legal values shown with their basis.
- Dashboard panel for people operations; approvals for reviews, disciplinary decisions and case responses.
- Dummy data `supabase/seed_phase6.sql`.

## 1.5.0 — 24 Oct 2026 — Phase 5: recruitment and onboarding

- **Requisitions** (`Recruitment`): raised by HR or by a line manager for his department; approved by someone else (`REC_APPROVE`).
  Reason (new, replacement, temporary), positions, salary range, needed-by date. An Omani-only job forces "Omani only".
- **Omanisation check before hiring:** each requisition shows the company and department ratio, the target, and the ratio if the
  positions are filled by Omanis or by expatriates, with a warning when expatriates would take the company below its target.
- **Candidates and pipeline:** candidate register (duplicate check by ID number and e-mail), pipeline per requisition
  (applied → shortlisted → interview → offer → hired / rejected / withdrawn); non-Omanis cannot be added to Omani-only positions;
  former employees are recognised.
- **Interviews:** scheduled with any user as interviewer (notified); the interviewer records rating, recommendation and feedback and sees
  the candidate without contact details; overdue feedback is a task.
- **Offers:** prepared by HR, approved by another person; contract type and length, notice, benefits, salary lines. **Probation is
  limited by law** — at most 3 months for monthly-paid categories and 2 months for others, and none for someone who has worked for the
  company before (once with the same employer). Printable bilingual offer letter with signature blocks.
- **Onboarding checklists** created when the offer is accepted, by case: expatriate from abroad (work permit, visa, flight,
  accommodation, induction, medical, MoL contract, resident card, bank), expatriate already in Oman, Omani (SPF registration);
  due dates counted from the start date; editable in settings.
- **Hire in one step:** the accepted offer creates the employee (numbering, duplicate and Omani-only rules as usual), proposes the salary
  for approval, records the contract and moves the checklist to the employee; the requisition closes when all positions are filled.
- **Probation tracker** (`Probation`): days left, legal maximum, confirm, extend within the maximum; daily reminders to HR and the line
  manager before the end date.
- Approvals page, menu badge and dashboard include requisitions, offers and interview feedback; dashboard shows open positions,
  candidates in progress, people joining in 30 days, overdue onboarding steps and probations ending.
- Dummy data `supabase/seed_phase5.sql`: three requisitions, six candidates at different stages, interviews, an accepted offer with
  onboarding started and an offer waiting for approval.

## 1.4.0 — 23 Oct 2026 — Phase 4: self-service and letters

- **My HR** (`/me`) for every employee with a login: job, manager, leave balance, next leave, last payslip, documents expiring in 90 days,
  quick actions, letters ready, and all their requests in one place.
- **Change requests HR approves** (maker-checker, never by the person concerned):
  - personal and contact details (preferred name, mobile, phones, personal e-mail, marital status, address) — old and new values shown;
  - emergency contacts (the new list replaces the old one on approval);
  - salary bank account — HR checks it, then Finance approves it as for any bank change;
  - correction of anything else (name, date of birth, ID number …) with the **45-day answer date** of the Personal Data Protection Law.
  Approved details are written to the employee record with a history entry; the employee is notified.
- **Letters:** salary certificate, employment letter (salary optional), no-objection certificate (travel or another activity) and
  experience letter. Requested by the employee or started by HR → prepared by an HR officer → approved by someone else who may see salaries.
  Issued letters get a running reference (e.g. `AACT/HR/2026/0001`), a 12-character verification code and a frozen snapshot of what they
  state; printable in English, Arabic or both side by side; can be withdrawn with a reason.
- **Public letter check** (`/verify`, no login): a bank or embassy enters the reference and code and sees whether the letter is genuine or
  withdrawn — no salary or ID number is shown.
- **My team** (`/team`) for line managers: today's attendance, who is on leave, items waiting for them, expiring documents, probation dates.
- **Requests and letters** page for HR, with letter settings (signatory, footer, verification address). Approvals page, menu badge and
  dashboard include change requests and letters.
- **PDPL:** employees can download a copy of all data held about them (logged in the access log) and ask for corrections.
- **E-mail through Microsoft 365:** every notification can also be e-mailed (per-company switch, per-user opt-out in Settings). Messages are
  queued in the database and sent by the `send-mail` edge function through Microsoft Graph; failures are retried and shown to the
  administrator with a test button.
- Dummy data `supabase/seed_phase4.sql`: an issued salary certificate, a NOC waiting for approval, letter requests and change requests.

## 1.3.0 — 22 Oct 2026 — Phase 3: payroll and end of service

- **Payroll rules, dated with their legal source** (`Payroll rules`; changes need a second person's approval):
  - Social Protection Fund, Omani: employer 14.5 % (old age 11, work injury 1, job security 0.5, maternity 1, sick leave 1 from 19 Jul 2026),
    employee 8 % (old age 7.5, job security 0.5); old age and work injury capped at OMR 3,000;
  - Social Protection Fund, expatriates: employer 2 % (maternity 1, sick leave 1) from 19 Jul 2026; work injury seeded at 0 until the date is confirmed;
  - end-of-service gratuity for expatriates (Art. 61): service to 31 Jul 2023 at 15 days a year for the first 3 years and 30 days after,
    service from 1 Aug 2023 at one month's basic a year; minimum service configurable;
  - expatriate savings fund 9 % of basic from 19 Jul 2027 and personal income tax 5 % above OMR 42,000 from 2028 — both built in and switched off;
  - deduction limit 25 % of the wage (Art. 95–96); pay basis (daily rate = monthly / 30, hourly = daily / 8, what counts as unpaid).
- **Payroll runs per company per month:** calculate → verify → approve → paid by three different people; nobody verifies or approves a run that
  contains their own salary; a run is calculated only after the attendance month is locked; return for correction, reopen with a reason.
- **Calculation:** approved salary structure prorated for joiners, leavers and mid-month increments; unpaid absence and unpaid leave; sick leave
  at 75 / 50 / 35 / 0 % after 21 days; overtime at the basic hourly or daily rate; approved one-off items; loan instalments that never take net
  pay below zero; SPF lines; gratuity accrual; warnings for missing salary or bank account and for capped deductions. Amounts to the baisa.
- **Payslips in English and Arabic**, printable; employees see their own once the run is approved (`My payslips`) and get a notification.
- **Exports:** WPS salary information file (Central Bank of Oman layout, no byte-order mark), journal for Finance by GL account and cost
  centre (balanced), payroll register, SPF contribution report.
- **Parallel run:** upload the current payroll's net pay per employee and see matches and differences before going live.
- **Loans and advances** with maker-checker, repayment schedule, automatic recovery; **one-off pay items** (bonus, commission, arrears,
  penalty, damage …) with bulk CSV and bulk approval.
- **Final settlement:** gratuity split at 31 Jul 2023, annual leave not taken (including the part month), notice pay in lieu, loan recovery,
  extra items; maker-checker; printable bilingual statement; approval closes loans and pays out the leave balance.
- **Gratuity provision report**, **payroll set-up** (employer CR, SPF number, payer bank and account, GL accounts, SPF flags per component).
- Approvals page, menu badge and dashboard include payroll runs, loans, one-off items, settlements and payroll rule changes; employee file
  Pay tab shows payslips, loans and accrued gratuity.
- Dummy data `supabase/seed_phase3.sql`: two payroll months (one paid, one approved), loans, one-off items, a parallel-run file and a
  settlement waiting for approval. `seed_phase2.sql` now covers ten weeks of punches.
- Tests: `tests/db/30_payroll.sql` (hand-checked figures for SPF ceiling, sick tiers, proration, split salary, deduction cap, gratuity, chain,
  loans, settlement), WPS file unit tests, 12 new screens in the visual check.

## 1.2.0 — 21 Oct 2026 — Phase 2: attendance and leave

- **Oman time rules, configurable and dated** (`Oman time rules` page; change = proposal + second-person approval):
  - working hours 8 h a day / 40 h a week, 60-minute break after 6 continuous hours (Labour Law RD 53/2023, Art. 70);
  - Ramadan hours 6 h a day / 30 h a week, applied by assigning a Ramadan shift with an end date (no religion is stored);
  - weekly rest of 2 consecutive days (Art. 77);
  - overtime premiums day 25 % / night 50 % / rest day 100 %, 12 h daily cap, night 21:00–05:00 (Art. 71);
  - overtime without consent 50 % / 75 % / 200 %, 15 inventory days a year (Art. 72);
  - attendance policy: late grace, punch windows, minimum gap.
- **Shifts and rosters:** shifts per company with rest days, break and grace; checked against the rules in force;
  bulk assignment with dates; a temporary (Ramadan) assignment splits the normal one, which resumes automatically.
- **Holidays and Ramadan dates** per year, per company or all companies.
- **Punch import:** CSV/TXT from any attendance device, column mapping with auto-detection, day/month order,
  separate or combined date and time, IN/OUT column; employees by number, device id or civil number; 5000-row chunks;
  duplicate-safe; history with per-row errors; device-id register.
- **Attendance:** daily view, month grid (P/L/A/V/H/R/M/N/W), employee month with punches; late / early / worked / extra minutes;
  a day in progress shows as present and becomes "missing punch" only after its punch window closes (hourly re-check job).
- **Corrections and overtime requests:** employee → line manager → HR, self-approval refused; overtime pay hours / days
  calculated from the rules; time-off option; Ministry notification flag for non-consent overtime.
- **Leave:** 15 Oman leave types with legal minimums (annual 30, sick tiers 100/75/50/35/0 % per Art. 82, maternity 98, paternity 7,
  marriage 3, bereavement, Hajj, exam, emergency, unpaid …); eligibility by service, gender, nationality; half days; event dates;
  medical certificate upload; balances with monthly accrual from the opening date, carry-forward and year-end lapse;
  two-year annual-leave reminder; air-ticket status; team calendar.
- **Leave administration:** balances report and export, opening-balance CSV import, adjustments with bulk approval, leave-type editor
  (cannot go below the legal minimum), accrual run and year close.
- **Months and payroll inputs:** lock / unlock a completed month (reason required to unlock); payroll input summary
  (present, absent, missing, late, leave by type, unpaid, overtime) with CSV export. Locked months refuse changes.
- **Approvals page** now also lists leave, corrections, overtime, balance adjustments and time-rule changes; line managers see their team's;
  menu badge counts them. Dashboard: attendance today, my leave, away in the next 14 days, waiting decisions.
  Employee file: new "Time and leave" tab.
- **Dummy data** `supabase/seed_phase2.sql` (runs after `seed.sql`): shifts, rosters, six weeks of punches, leave history,
  opening balances and accrual, corrections, overtime, waiting requests at each stage, a locked month.
- Tests: `tests/db/20_phase2.sql` (12 sections), punch-file parser unit tests, 22 new screens in the visual check.

## 1.1.0 — 21 Oct 2026 — local development environment

- Local Supabase stack via the Supabase CLI (pinned 2.121.0, PostgreSQL 17): `npm run local:setup`, `db:start`, `db:reset`, `db:stop`.
- Dummy data `supabase/seed.sql` (generated by `scripts/gen-seed.py`): 60 employees, 7 demo logins (one per role),
  documents in every expiry band, missing documents, pending approvals, dummy Omanisation target. Refuses to run on a database with employees.
- `.env.development.local` written automatically for `npm run dev`; production builds never read it.
- Environment label in the app (LOCAL / TEST); none on production.
- Password rule matches Supabase Auth: 10+ characters with upper case, lower case and a digit.
- Plain-PostgreSQL tests moved from `supabase/tests` to `tests/db`.
- Guides: `docs/LOCAL-DEVELOPMENT.md`, `docs/ENVIRONMENTS.md`.

## 1.0.2 — 20 Oct 2026 — dependency security update

- `npm audit`: 8 findings → 0. React Router 7.18.4 (fixes an open-redirect advisory in the shipped app);
  Vite 7.3.7, Vitest 5.0.5, @vitejs/plugin-react 5.2.0 (development tools only).
- Router future-flag warnings removed (v7 behaviour is now the default).
- Needs Node.js 20.19+ or 22.12+.
- `.gitattributes` (LF line endings); `*.tsbuildinfo` no longer committed.

## 1.0.1 — 20 Oct 2026 — live install

- Installed on the live Supabase project; full test suite passed on live and rolled back.
- Hardening migration `20261020001000_hardening.sql`: indexes on 22 foreign keys; Supabase's `rls_auto_enable` helper closed to API roles.

## 1.0.0 — 20 Oct 2026 — Priority 1: HR foundation

- **Organisation masters:**
  - companies, locations, cost centres and departments;
  - grades with salary bands;
  - job titles with Ministry profession code and Omani-only flag;
  - employee categories;
  - document types.
- **Employee master** in English and Arabic, with duplicate checks and automatic numbering.
- **Effective-dated job history** (transfer, promotion, correction) and lifecycle actions: confirm, notice, suspend, separate, rehire.
- **Contracts** with versions.
- **Salary structure and bank account**, each proposed by one person and approved by another.
- **Documents:**
  - versions, renewal and second-person verification;
  - cancellation with a reason;
  - mandatory checklist;
  - private file storage.
- **Expiry tracker and reminders:**
  - expired / 30 / 60 / 90 days for documents and contracts;
  - daily scan;
  - missing-documents report.
- **Omanisation:**
  - ratios by company, department, job and profession code;
  - targets with source and maker-checker;
  - Omani-only exceptions;
  - what-if planner.
- **Dashboards** for HR, line managers and employees.
- **Administration:** users and roles, settings, audit trail and sensitive-data access log.
