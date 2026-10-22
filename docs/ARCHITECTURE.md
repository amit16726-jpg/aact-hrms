# AACT HRMS — architecture, delivery plan and open legal points

Status: **Priority 1 (HR foundation) built, tested and installed on the live Supabase project `nbseyccerlzerkmcwknw` — 20 Oct 2026.** Not yet approved for live employee data.

## 1. Starting point

There was no existing repository for AACT, so a new one was created. The stack is the one already proven on
ViaanBooks, so the same people can maintain both:

| Layer | Choice | Why |
|---|---|---|
| Database | Supabase (PostgreSQL 17), own project "AACT Payroll Project" (`nbseyccerlzerkmcwknw`) | managed backups, auth and private file storage; row-level security |
| Business logic | `public.hr_*` SQL functions (SECURITY DEFINER) over tables in a closed `hr` schema | every rule and permission is enforced on the server, inside one transaction |
| Front end | React 18 + TypeScript + Vite, static stylesheet, no UI framework | small bundle, no animated layers (the 12-Oct Android freeze lesson) |
| Hosting | Vercel (git push deploys) | as for ViaanBooks |
| Languages | English and Arabic, right-to-left; IBM Plex Sans + IBM Plex Sans Arabic bundled (works offline) | |

## 2. Security model

- **Tables are not reachable from the browser.** All tables live in schema `hr`, which the API does not expose.
  The browser role (`authenticated`) has no table or schema privileges; RLS is enabled with no policies as a second wall.
- **Every call goes through a `public.hr_*` function** that checks the signed-in user's permissions first.
  The anonymous role can call none of them.
- **Roles → permissions** (19 permissions, 7 roles) are data, shown on Users and roles. A role removed is revoked, not deleted.
- **Field-level restriction.**
  - Line managers see their team (direct and indirect) with limited fields only — no date of birth, civil number, address, salary or documents.
  - Employees see only their own record.
  - Salary, bank and medical/disciplinary documents each need their own permission.
  - Bank numbers are masked for roles that may request but not read them, and masked in the audit trail.
- **Maker-checker (segregation of duties).** The database refuses self-approval:
  - salary revisions (`proposed_by <> decided_by`, and nobody approves their own salary);
  - bank account changes;
  - Omanisation targets;
  - document verification (the uploader cannot verify).
- **Legal rules need authority.** Marking a job Omani-only needs the rule-approval permission and a written source.
  Placing a non-Omani in such a job needs the exception permission, a reason, and is recorded.
- **Audit trail.** A trigger on every `hr` table records who changed what (old and new values).
  Viewing salary, bank details and documents is written to a separate access log.
- **Files.** Private bucket `hr-documents`; path `<employee>/<type>/<random>`. Storage policies use the same rules as the
  API. Files are never overwritten or deleted by the app — a renewal is a new version. Downloads use 2-minute signed links.
- **First administrator.** The first signed-in user can claim super-administrator once, while none exists.
  After everyone has an account, turn off public sign-ups in Supabase Auth.

## 3. Data model (Priority 1)

| Area | Tables |
|---|---|
| Organisation | `legal_entities`, `locations`, `cost_centres`, `departments` (tree), `grades` (salary band), `job_titles` (Ministry profession code, Omani-only flag + source), `employee_categories` (pay basis, counts for Omanisation), `countries` |
| Employee | `employees`, `emergency_contacts`, `employee_events` (join, confirm, transfer, promotion, notice, separation, rehire …) |
| Effective dating | `employee_assignments` — department, job, grade, category, location, cost centre, manager, shift per period; periods cannot overlap (exclusion constraint) |
| Contracts | `employee_contracts` — versions; a new one supersedes the active one |
| Pay (restricted) | `pay_components`, `compensation_revisions` + `compensation_lines` — proposed, then approved; history kept |
| Bank (restricted) | `employee_bank_accounts` — requested, then approved; previous account superseded |
| Documents | `document_types` (mandatory for Omani / expatriate / all, alert days, sensitive), `employee_documents` (versions, verification, cancellation) |
| Compliance | `omanisation_targets` (scope, %, effective dates, legal or policy, source, maker-checker), `omanisation_exceptions`, `notifications` |
| Control | `roles`, `permissions`, `role_permissions`, `user_profiles`, `user_roles`, `settings`, `audit_log`, `access_log` |

Nothing historic is deleted: leavers keep their records; corrections are recorded as corrections.

## 4. What Priority 1 does

- **Organisation masters** for one or more companies.
- **Employee master** in English and Arabic, with duplicate checks (civil / resident-card number, and same name + date of birth + nationality).
- **Automatic employee numbers** (`AACT-00001`, prefix and digits configurable).
- **Effective-dated job changes:** transfer, promotion, future-dated moves, and corrections of the current record.
- **Lifecycle:** confirm after probation, notice, suspend and reinstate, separation (closes the job and the contract), rehire (keeps history).
- **Contracts:** fixed-term or indefinite, with versions.
- **Salary structure:** proposed and approved; grade-band warning; history.
- **Bank account:** requested and approved; masked where needed.
- **Documents:** upload, renewal as a new version, verification by a second person, cancellation with a reason, and a per-employee mandatory checklist.
- **Expiry tracker:** documents and fixed-term contracts, banded expired / 30 / 60 / 90 days.
- **Reminders:** in-app, one per alert threshold, expired items escalated as high priority; daily scan at 07:00 Muscat via pg_cron.
- **Missing-documents report.**
- **Omanisation:** ratio by company, department, job title and profession code against approved targets; Omanis still needed; non-Omanis in Omani-only jobs; a what-if planner.
- **Dashboards by role:** HR / Finance, line manager (team expiries) and employee (own documents).
- **Exports and printing:** CSV export (Excel-safe, Arabic-safe); print stylesheet.
- **Audit:** audit trail viewer and sensitive-data access log.

## 5. Tests run (20 Oct 2026)

- **Database:** `tests/db/10_priority1.sql`, about 120 assertions, run as the real `authenticated` role switching between 8 users. Covers:
  - bootstrap and roles;
  - direct table access refused;
  - masters and the department-cycle guard;
  - duplicates;
  - Omani-only enforcement;
  - effective dating and overlap refusal;
  - manager, team and self visibility;
  - salary and bank maker-checker and masking;
  - storage policies;
  - document versions and sensitive hiding;
  - expiry buckets, missing documents and notification de-duplication;
  - Omanisation ratio, target closing and self-approval refusal;
  - confirm, notice, separation and rehire;
  - audit masking.

  **All pass**; migrations re-run cleanly.
- **Live project (20 Oct 2026):**
  - all 10 migrations applied;
  - the same test suite run on live inside one transaction that rolls itself back — **all passed**, and afterwards 0 employees, 0 users, 0 files and no test schema were left behind;
  - anonymous role: no access to any `hr_*` function; signed-in role: functions only, no `hr` schema or table access;
  - bucket `hr-documents` private; daily expiry scan scheduled (03:00 UTC = 07:00 Muscat).
- **Supabase advisors after hardening:**
  - security: only by-design notices ("RLS enabled, no policy" on closed `hr` tables; signed-in users can run the `hr_*` API functions, each of which checks permissions itself);
  - performance: only "unused index" notices, expected on an empty database.
- **Front end:**
  - TypeScript strict: 0 errors.
  - 23 unit and render tests pass: money, Muscat date, buckets, CSV, Omanisation arithmetic, diff, error codes, Arabic/English key parity, manager view, dialog Esc/back.
  - Production build OK.
- **Screens:** 7 screens × English/Arabic × phone (390 px)/desktop (1440 px). No page errors, no console errors, no sideways scroll.

## 6. Points that need human confirmation before go-live

Nothing below is hard-coded. Each is a setting, a master record, or a rule with a source field.

1. **Omanisation targets.** No percentages are seeded. Enter each from the Ministry of Labour decision that applies to AACT's activity, with its number and date, and have a second person approve it.
2. **Omani-only professions.** Mark job titles Omani-only only from the current Ministerial decision list (decision number in "Source"), and tick "verified".
3. **Counting basis.** Confirm which categories count for Omanisation (trainees, part-time, secondees …) — set per employee category.
4. **Mandatory documents and alert days.** The defaults are company-policy suggestions:
   - Omanis: civil ID;
   - expatriates: resident card, visa and work permit;
   - everyone: signed contract.

   Confirm them and the reminder days (e.g. 90/60/30).
5. **Probation and notice.** Entered per contract. Check them against the Labour Law (Royal Decree 53/2023) and its executive regulations; the app does not impose limits beyond 0–365 days.
6. **Personal data.** Retention periods and the lawful basis for holding medical and disciplinary records must be confirmed under Oman's Personal Data Protection Law (Royal Decree 6/2022) before live data is loaded.
7. **Bank / WPS file format, SPF contributions, end-of-service:** Priority 3 — not built; formats and rates must come from the bank and the official sources.

## 7. Delivery plan

| Phase | Scope | Depends on |
|---|---|---|
| **P1 — done** | foundation above | — |
| P2 | shifts and rosters, attendance import (biometric file/API), manual punches with approval, overtime requests, leave types/accruals/balances, leave and attendance approvals, public holidays, attendance lock | P1 |
| P3 | payroll periods, calculation engine, statutory rule configuration (SPF etc., verified), payslips, bank/WPS file, payroll approval chain, journal export to Finance, reconciliations, parallel run | P1, P2, confirmed rules |
| P4 | employee and manager self-service portal, recruitment and onboarding, performance and training, welfare and assets, executive analytics | P1–P3 |
| UAT | data migration rehearsal, parallel payroll, security review, backup/restore drill | all |

## 8. Known limitations of P1

- Roles apply across all companies (no per-company role scope yet).
- E-mail notifications are not sent yet; notifications are in-app. Needs an e-mail provider key.
- No integration with Ministry of Labour or ROP systems: documents and statuses are entered and uploaded by HR, by design.
- Employee self-service changes (an employee correcting his own details) are P4. Today HR edits on the employee's behalf.

## 9. Phase 4 — self-service and letters (v1.4.0)

- **Employees never write to their own record.** Every self-service change is a `hr.change_requests` row decided by someone with
  `SS_APPROVE` who is neither the requester nor the employee (database check `decided_by <> requested_by`). Only ten contact fields can be
  changed this way (`hr.ss_profile_fields()`); anything else is a free-text correction that HR handles and closes with a note.
- **Bank changes keep two checks:** HR approves the request, which creates a *pending* bank row with the employee as requester; Finance
  (`BANK_APPROVE`) gives the final approval exactly as before.
- **Letters:** prepared (`LETTER_PREPARE`) and approved (`LETTER_APPROVE`) by different people (database check), never for oneself; a
  letter that states a salary can only be approved by someone with `EMP_SALARY_READ`, and the salary is hidden from other HR viewers.
  The issued content is frozen in `hr.letters.snapshot` so later changes never alter an issued letter.
- **Public verification** `hr_verify_letter(ref, code)` is the only function granted to `anon` (kept by `hr.secure_api()`); it needs
  the reference *and* a 12-character random code and returns only type, date, company and name.
- **E-mail queue** `hr.email_outbox` is filled by a trigger on notifications and read only by `mail_claim_batch` / `mail_mark`, which
  are executable by `service_role` only (the edge function); signed-in users and `anon` cannot read it.
- **PDPL:** `hr_my_data_export()` returns everything held about the signed-in employee and is written to `hr.access_log`;
  correction requests carry a due date 45 days after the request.
- Tests: `tests/db/40_selfservice.sql` (requests, separation of duties, bank masking, letter numbering and privacy, anonymous checks,
  mail queue privileges and retry) and unit tests for the bilingual letter wording and the Microsoft Graph sender.

## 10. Phase 5 — recruitment and onboarding (v1.5.0)

- Requisitions and offers are maker-checker (`decided_by <> requested_by`, `approved_by <> prepared_by` checks in the tables).
- Interviewers and requesting managers see only the applications they are involved in (`hr.can_see_application`), without the
  candidate's contact details or the offer.
- Probation limits come from `hr.settings.recruitment` (monthly-paid 3 months, others 2, editable only downwards) and are enforced on
  the offer, at hire and on extension; probation is refused for a former employee of the same company.
- Hiring reuses the employee, salary and contract APIs, so numbering, duplicate checks, the Omani-only rule (with exception approval)
  and salary approval apply unchanged.
- Open point: confirm the exact Labour Law article for probation before go-live (stored as text in the settings).
- Tests: `tests/db/50_recruitment.sql`; unit tests for the offer wording.

## 11. Phase 6 — people operations (v1.6.0)

- New tables: `perf_cycles`, `perf_reviews`, `perf_plans`, `training_courses`, `training_records`, `disciplinary_cases`, `asset_items`,
  `asset_issues`, `facilities`, `facility_assignments`, `work_injuries`, `exit_cases`, `exit_tasks` — all audited, RLS on, reached only
  through `public.hr_*` functions.
- Legal and policy values live in `hr.settings.hr_policies` with their legal basis (improvement period 6 months, notice 30/15 days,
  non-compete 24 months, discipline limits, injury reporting days, exit clearance steps); read with `hr.policy()` / `hr.policy_num()`.
- Maker-checker: HR finalises a review only if it is not the reviewer; a disciplinary decision needs `DISC_APPROVE` and a person who
  neither opened nor proposed the case (also a table check). Money effects (disciplinary deduction, damage recovery) are created as
  `payroll_adjustments` in PENDING status, so Finance approval and the payroll deduction limit apply.
- Disciplinary cases are sensitive: list views by employee are written to `access_log` (`DISCIPLINE`); employees see their own cases
  without internal notes once the investigation starts.
- Training certificates are a third source in `hr.expiry_items` (latest completed record per employee and course), so they appear in
  the expiry tracker and the daily expiry notifications.
- Exits call `hr_change_status` (NOTICE, SEPARATE, WITHDRAW_NOTICE), so the employee record, contracts and assignments close exactly as
  with a manual separation.
- Open points: confirm the discipline limits against the company's MoL-approved regulation and the SPF work-injury reporting deadline.
- Tests: `tests/db/60_workforce.sql`; unit tests in `src/lib/api_wf.test.ts`.

## 12. Phase 7 — governance, reports and the server (v1.7.0)

- New tables: `privacy_notices` (versioned; one published), `consents` (one current row per user and purpose), `dsr_requests`,
  `data_breaches`, `processing_activities`, `import_batches`. Deadlines come from `hr.settings.pdpl` (45 days, 72 hours) with the
  legal basis stored beside them.
- Maker-checker: a privacy notice is published by someone other than its preparer; data-subject requests can be completed only after
  the identity is confirmed; breaches close only with containment and either the Ministry notification time or a reason.
- Statutory reports read the same functions as the Omanisation page (`hr.omanisation_population`) and the payslip lines written by
  the payroll calculation (`SPF_EE_*`, `SPF_ER_*`), so figures always agree with payroll.
- `hr_import` calls the normal API (`hr_save_employee`, `hr_save_document`, `hr_propose_compensation`) row by row inside
  sub-transactions; a trial run rolls the whole batch back but keeps the per-row results.
- Server: see `deploy/README-SERVER.md`. Migrations on the server are applied by `deploy/scripts/apply-migrations.sh`, recorded in
  `aact_admin.migrations` with a checksum.
- Tests: `tests/db/70_governance.sql`, `tests/deploy/test-scripts.sh`, `src/lib/api_gov.test.ts`.

## 13. Management (MG) pay confidentiality (v1.9.0)

- `hr.employees.pay_group` and `hr.payroll_runs.pay_group`: `NMG` (default) or `MG`. One payroll run per company, month and pay group.
- Permission `MG_PAY` belongs only to role `MG_PAYROLL`. A trigger on `hr.role_permissions` silently skips `MG_PAY` for any
  other role, so a later "give the super administrator every permission" statement cannot leak it. **Future migrations must
  not try to grant `MG_PAY` to another role.**
- Central checks (`20261027000100_mg_pay.sql`): `hr.money_ok(employee)`, `hr.require_money(employee)`, `hr.run_ok(group)`,
  `hr.require_run(run)`, `hr.money_users(perm, employee, group)` / `hr.notify_money(...)` for notifications, `hr.audit_ok(row)` for the audit trail.
  Every function that reads or writes salary, bank, payslips, loans, pay items, settlements, gratuity or salary letters calls them.
  Self-service (the employee's own payslips, salary and letters) is unchanged.
- Team membership: `hr_set_user_roles` refuses to add or remove `MG_PAYROLL` unless the caller holds `MG_PAY` (or nobody does yet);
  members use `hr_list_mg_access` / `hr_set_mg_access`.
- Known limits: job offers and requisitions still show the offered salary to recruiters (prepare offers for MG posts inside the team);
  a payroll run's totals still include every payslip in it, which is why MG staff are paid in their own run.

## 14. Report centre and security hardening (v1.13.0)

- Catalogue `hr.report_defs` (code, group, permission, money / sensitive flags, filters, names). One function `hr.rpt_<code>(p jsonb)`
  per report returns `{columns, rows, meta}`; columns carry key, English and Arabic labels, type (text, int, num, money, pct, date) and a
  sum flag. `public.hr_run_report(code, params)` is the only entry point: permission check, MG checks inside each report
  (`hr.money_ok`, `hr.run_ok`, `hr.require_run`), access-log row for money and sensitive reports.
- Common helpers: `hr.rp_people` (visible employees with their job on a date and the standard filters), `hr.rp_run` (run asked for, else
  latest calculated run of the company and pay group), `hr.rp_entity`.
- Files are made in the browser: Excel with exceljs, PDF by laying out A4 pages in HTML and rendering them (html-to-image + jsPDF) so
  Arabic shaping and right-to-left are exactly as on screen, PowerPoint with pptxgenjs (native charts). Libraries load on demand.
- Scheduled reports: `hr.report_schedules`; daily job `hr.send_due_report_schedules()` (pg_cron 02:15 UTC) sends notifications (and
  e-mails through the outbox) with a link `/reports?schedule=<id>`; recipients must hold the report's permission at sending time.
- Two-step sign-in: `hr.mfa_state()` = OK / CHALLENGE / SETUP from `auth.mfa_factors` and the JWT `aal` claim; `hr.require_user`,
  `hr.require_perm` and `hr.has_perm` refuse until the second step is passed; policy in `hr.settings.mfa` (required + roles).
- Automatic sign-out: `hr.settings.session_idle_minutes`, enforced in the browser (`src/lib/idle.ts`), shared across tabs.

