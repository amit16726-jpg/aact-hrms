-- =============================================================================
-- AACT HRMS — WIPE THE CLOUD TEST DATABASE and load the AACT masters.
-- Run ONCE in the Supabase SQL editor of the cloud TEST project (nbseyccerlzerkmcwknw).
-- It removes every employee, transaction, upload record, notification, audit entry and EVERY LOGIN,
-- puts settings and rules back to the installed defaults, then loads supabase/seed_masters.sql.
-- It cannot be undone. It refuses to run on a database holding non-demo employees (e.g. the company server).
-- After it finishes: open the app, create a new account, and claim the administrator role on the Setup page.
-- =============================================================================
begin;

do $$
begin
  if exists (select 1 from hr.employees)
     and not exists (select 1 from hr.employees where work_email ilike '%@aact.test') then
    raise exception 'STOP: this database has employees that are not demo data. This script is only for the cloud test project.';
  end if;
end $$;

-- 1. data (every table except installed settings, rules, roles and reference lists)
truncate table
  hr.access_log,
  hr.applications,
  hr.asset_issues,
  hr.asset_items,
  hr.attendance_corrections,
  hr.attendance_days,
  hr.attendance_periods,
  hr.audit_log,
  hr.candidates,
  hr.change_requests,
  hr.compensation_lines,
  hr.compensation_revisions,
  hr.consents,
  hr.cost_centres,
  hr.data_breaches,
  hr.departments,
  hr.device_users,
  hr.disciplinary_cases,
  hr.dsr_requests,
  hr.email_outbox,
  hr.emergency_contacts,
  hr.employee_assignments,
  hr.employee_bank_accounts,
  hr.employee_categories,
  hr.employee_contracts,
  hr.employee_documents,
  hr.employee_events,
  hr.employee_loans,
  hr.employees,
  hr.exit_cases,
  hr.exit_tasks,
  hr.facilities,
  hr.facility_assignments,
  hr.final_settlements,
  hr.grades,
  hr.import_batches,
  hr.interviews,
  hr.job_offers,
  hr.job_requisitions,
  hr.job_titles,
  hr.leave_adjustments,
  hr.leave_ledger,
  hr.leave_requests,
  hr.letter_counters,
  hr.letters,
  hr.loan_repayments,
  hr.locations,
  hr.notifications,
  hr.omanisation_exceptions,
  hr.omanisation_targets,
  hr.onboarding_tasks,
  hr.overtime_requests,
  hr.payroll_adjustments,
  hr.payroll_parallel,
  hr.payroll_runs,
  hr.payslip_lines,
  hr.payslips,
  hr.perf_cycles,
  hr.perf_plans,
  hr.perf_reviews,
  hr.punch_batches,
  hr.punches,
  hr.rec_counters,
  hr.shift_assignments,
  hr.shifts,
  hr.special_periods,
  hr.training_courses,
  hr.training_records,
  hr.user_profiles,
  hr.user_roles,
  hr.work_injuries
restart identity;

delete from hr.holidays where entity_id is not null;
delete from hr.legal_entities;
alter sequence hr.employee_no_seq restart with 1;

-- 2. rules: drop proposals made after installation, re-open the installed versions
delete from hr.time_rules where proposed_by is not null;
update hr.time_rules set effective_to = null where effective_to is not null;
delete from hr.pay_rules where proposed_by is not null;
update hr.privacy_notices set status = 'DRAFT', published_at = null, published_by = null, prepared_by = null;

-- 3. settings back to the installed defaults
delete from hr.settings where key not in ('currency', 'currency_decimals', 'date_format', 'default_language', 'email', 'employee_no_digits', 'employee_no_prefix', 'expiry_horizon_days', 'hr_policies', 'leave_opening_date', 'letters', 'pay_day', 'payroll_gl', 'pdpl', 'recruitment', 'time_zone');
insert into hr.settings(key, value) values ('currency', $j$"OMR"$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('currency_decimals', $j$3$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('date_format', $j$"dd/MM/yyyy"$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('default_language', $j$"en"$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('email', $j${"app_url": "", "enabled": false, "sender_name": "AACT HR"}$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('employee_no_digits', $j$5$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('employee_no_prefix', $j$"AACT-"$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('expiry_horizon_days', $j$90$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('hr_policies', $j${"exit_tasks": {"EXPAT": [{"ar": "إلغاء أو نقل الإقامة (شرطة عمان السلطانية)", "en": "Resident card / visa cancelled or transferred (Royal Oman Police)", "code": "RESIDENCE_CANCEL"}, {"ar": "إلغاء ترخيص العمل لدى وزارة العمل", "en": "Work permit cancelled with the Ministry of Labour", "code": "WORK_PERMIT_CANCEL"}, {"ar": "توفير تذكرة العودة", "en": "Return air ticket provided", "code": "AIR_TICKET"}], "OMANI": [{"ar": "إبلاغ صندوق الحماية الاجتماعية بانتهاء الخدمة", "en": "End of service reported to the Social Protection Fund", "code": "SPF_END"}], "COMMON": [{"ar": "تسليم العمل للمدير المباشر", "en": "Work handed over to the line manager", "code": "HANDOVER"}, {"ar": "إيقاف البريد وصلاحيات الأنظمة", "en": "E-mail and system access removed", "code": "IT_ACCESS"}, {"ar": "اعتماد التسوية النهائية وصرفها", "en": "Final settlement approved and paid", "code": "SETTLEMENT"}, {"ar": "إصدار شهادة الخبرة", "en": "Experience letter issued", "code": "EXPERIENCE_LETTER"}, {"ar": "إجراء مقابلة الخروج", "en": "Exit interview held", "code": "EXIT_INTERVIEW"}]}, "pip_min_months": 6, "pip_legal_basis": "Labour Law RD 53/2023 — poor performance: written notice and at least 6 months to improve before termination", "notice_other_days": 15, "injury_legal_basis": "Report work injuries to the Social Protection Fund (work-injury branch) — confirm the deadline", "injury_report_days": 7, "notice_legal_basis": "Labour Law RD 53/2023 — notice: 30 days for monthly-paid workers, 15 days for others (unless the contract gives more)", "notice_monthly_days": 30, "discipline_legal_basis": "Company disciplinary regulation approved by the Ministry of Labour — confirm the limits", "non_compete_max_months": 24, "non_compete_legal_basis": "Labour Law RD 53/2023 — non-compete clause: at most 2 years after the contract ends", "discipline_max_deduction_days": 5, "discipline_max_suspension_days": 5}$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('leave_opening_date', $j$null$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('letters', $j${"footer_ar": "", "footer_en": "", "signatory_ar": "مدير الموارد البشرية", "signatory_en": "HR Manager", "verify_base_url": "", "signatory_name_ar": "", "signatory_name_en": ""}$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('pay_day', $j$28$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('payroll_gl', $j${"spf_expense": "5120", "spf_payable": "2110", "eosb_expense": "5130", "eosb_provision": "2120", "salary_expense": "5100", "salary_payable": "2100", "loans_receivable": "1150", "overtime_expense": "5110", "deductions_income": "4900", "income_tax_payable": "2130"}$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('pdpl', $j${"dpo_name": null, "dsr_days": 45, "dpo_email": null, "retention": [{"ar": "سجلات الموظفين الذين تركوا العمل", "en": "Records of employees who have left", "code": "EX_EMPLOYEE", "basis": "Labour Law limitation and tax/SPF audits — confirm", "months": 120}, {"ar": "المرشحون الذين لم يُعيَّنوا", "en": "Candidates not hired", "code": "CANDIDATE", "basis": "Consent / legitimate interest — confirm", "months": 12}, {"ar": "بصمات الحضور الأصلية", "en": "Raw attendance punches", "code": "ATTENDANCE", "basis": "Payroll evidence — confirm", "months": 36}, {"ar": "سجل الاطلاع على البيانات الحساسة", "en": "Access log of sensitive data", "code": "ACCESS_LOG", "basis": "Accountability — confirm", "months": 60}], "controller": "AACT", "breach_hours": 72, "dsr_legal_basis": "PDPL Executive Regulation — reply to a data subject's request within 45 days", "breach_legal_basis": "PDPL Executive Regulation — notify the Ministry (MTCIT) of a personal data breach within 72 hours of becoming aware of it"}$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('recruitment', $j${"onboarding": {"OMANI": [{"ar": "التعريف بالسلامة وصرف معدات الوقاية", "en": "Safety induction and PPE issued", "code": "INDUCTION", "days": 0}, {"ar": "توقيع العقد وتسجيله في وزارة العمل", "en": "Contract signed and registered with the Ministry of Labour", "code": "CONTRACT_MOL", "days": 7}, {"ar": "التسجيل في صندوق الحماية الاجتماعية", "en": "Registered with the Social Protection Fund", "code": "SPF_REGISTRATION", "days": 7}, {"ar": "تسجيل حساب الراتب البنكي", "en": "Salary bank account recorded", "code": "BANK_ACCOUNT", "days": 30}], "EXPAT_ABROAD": [{"ar": "ترخيص العمل من وزارة العمل", "en": "Work permit (labour clearance) from the Ministry of Labour", "code": "LABOUR_CLEARANCE", "days": -45}, {"ar": "تأشيرة العمل من شرطة عمان السلطانية", "en": "Employment visa from Royal Oman Police", "code": "VISA", "days": -30}, {"ar": "تذكرة السفر والاستقبال عند الوصول", "en": "Air ticket and arrival pick-up", "code": "FLIGHT", "days": -7}, {"ar": "ترتيب السكن والمواصلات", "en": "Accommodation and transport arranged", "code": "ACCOMMODATION", "days": -3}, {"ar": "التعريف بالسلامة وصرف معدات الوقاية", "en": "Safety induction and PPE issued", "code": "INDUCTION", "days": 0}, {"ar": "الفحص الطبي", "en": "Medical fitness examination", "code": "MEDICAL", "days": 7}, {"ar": "توقيع العقد وتسجيله في وزارة العمل", "en": "Contract signed and registered with the Ministry of Labour", "code": "CONTRACT_MOL", "days": 7}, {"ar": "البصمة وبطاقة الإقامة (شرطة عمان السلطانية)", "en": "Fingerprints and resident card (Royal Oman Police)", "code": "RESIDENT_CARD", "days": 21}, {"ar": "فتح حساب بنكي للراتب وتسجيله", "en": "Salary bank account opened and recorded", "code": "BANK_ACCOUNT", "days": 30}], "EXPAT_IN_OMAN": [{"ar": "نقل الكفالة / ترخيص عمل جديد من وزارة العمل", "en": "Transfer / new work permit from the Ministry of Labour", "code": "LABOUR_CLEARANCE", "days": -21}, {"ar": "التعريف بالسلامة وصرف معدات الوقاية", "en": "Safety induction and PPE issued", "code": "INDUCTION", "days": 0}, {"ar": "الفحص الطبي", "en": "Medical fitness examination", "code": "MEDICAL", "days": 7}, {"ar": "توقيع العقد وتسجيله في وزارة العمل", "en": "Contract signed and registered with the Ministry of Labour", "code": "CONTRACT_MOL", "days": 7}, {"ar": "تحديث بطاقة الإقامة (شرطة عمان السلطانية)", "en": "Resident card updated (Royal Oman Police)", "code": "RESIDENT_CARD", "days": 21}, {"ar": "تسجيل حساب الراتب البنكي", "en": "Salary bank account recorded", "code": "BANK_ACCOUNT", "days": 30}]}, "probation_legal_basis": "Labour Law RD 53/2023 — probation: up to 3 months for monthly-paid workers, 2 months for others; once with the same employer", "probation_reminder_days": 14, "probation_other_max_months": 2, "probation_monthly_max_months": 3}$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
insert into hr.settings(key, value) values ('time_zone', $j$"Asia/Muscat"$j$::jsonb) on conflict (key) do update set value = excluded.value, updated_by = null, updated_at = now();
update hr.pay_components set gl_account = null, spf_base = true, is_active = true
 where code in ('BASIC','HOUSING','TRANSPORT','FOOD','TELEPHONE','UTILITY','SPECIAL','OTHER_ALLOW','FIXED_DED');

-- 4. every login (demo users and test accounts)
delete from auth.identities;
delete from auth.users;

-- 5. AACT masters (same as supabase/seed_masters.sql)

-- =============================================================================
-- AACT HRMS — company MASTERS (no personal data).
-- Built from AACT's NMG and MG staff lists: departments, designations, staff categories and pay components.
-- Safe to run on any database (laptop, cloud test, company server) and safe to run again:
-- it only adds what is missing and never overwrites changes made later in the app.
-- It contains NO employee names, dates of birth or salaries; those are loaded on the company server
-- through Settings → Data import (see docs/DATA-MIGRATION.md).
-- =============================================================================

-- ---------------------------------------------------------------- company
insert into hr.legal_entities(code, name_en, name_ar, country, currency)
values ('AACT', 'Al Anwar Ceramic Tiles Co. SAOG', 'شركة الأنوار لبلاط السيراميك ش.م.ع.ع', 'OM', 'OMR')
on conflict (code) do nothing;

-- ---------------------------------------------------------------- departments
-- NMG names kept as written in the NMG list; short MG names are aliases so either can be used in an import file.
insert into hr.departments(entity_id, code, name_en, name_ar, aliases)
select e.id, d.code, d.name_en, d.name_ar, d.aliases
from hr.legal_entities e
cross join (values
  ('ADMIN',  'Administration',    'الشؤون الإدارية',            array['Admin']),
  ('BODY',   'Body Preparation',  'تحضير العجينة',              array['Body', 'Body Prep']),
  ('DESIGN', 'DESIGN',            'التصميم',                    array['Design']),
  ('ELEC',   'Electrical',        'الكهرباء',                   array['Elect', 'Elec']),
  ('GLAZE',  'Glaze Preparation', 'تحضير التزجيج',              array['GP', 'Glaze', 'Glaze Prep']),
  ('HSE',    'HSE',               'الصحة والسلامة والبيئة',      array['Health Safety Environment']),
  ('LAB',    'Laboratory',        'المختبر',                    array['Lab']),
  ('MECH',   'Mechanical',        'الميكانيكا',                 array['Mech']),
  ('PACK',   'Packing',           'التعبئة والتغليف',            array['Pack']),
  ('PLANT1', 'PLANT1',            'المصنع 1',                   array['Plant 1']),
  ('PLANT2', 'PLANT2',            'المصنع 2',                   array['Plant 2']),
  ('PLANT3', 'PLANT3',            'المصنع 3',                   array['Plant 3']),
  ('PLANT4', 'PLANT4',            'المصنع 4',                   array['Plant 4']),
  ('PLANT5', 'PLANT5',            'المصنع 5',                   array['Plant 5']),
  ('P6',     'Project-P6',        'المشروع P6',                 array['Project P6', 'P6', 'Plant 6']),
  ('SORT',   'Sorting',           'الفرز',                      array['Sort']),
  ('STORES', 'Stores',            'المخازن',                    array['Store']),
  ('TFP',    'TFP PLANT',         'مصنع TFP',                   array['TFP']),
  ('WH',     'Warehouse',         'المستودع',                   array['WH']),
  ('ACCT',   'Accounts',          'الحسابات',                   array['Accounts', 'Account']),
  ('CEO',    'CEO Office',        'مكتب الرئيس التنفيذي',        array['CEO']),
  ('PUR',    'Purchase',          'المشتريات',                  array['Purchasing', 'Procurement']),
  ('DESP',   'Despatch',          'الإرسال والشحن',              array['Dispatch']),
  ('MAINT',  'Maintenance',       'الصيانة',                    array['Maint']),
  ('IT',     'IT',                'تقنية المعلومات',             array['Information Technology']),
  ('MKTG',   'Marketing',         'التسويق',                    array['Mktg', 'Sales and Marketing']),
  ('PROD',   'Production',        'الإنتاج',                    array['Prod']),
  ('HR',     'HR',                'الموارد البشرية',             array['Human Resources']),
  ('FIN',    'Finance',           'المالية',                    array['FC', 'Financial Controller']),
  ('IA',     'Internal Audit',    'التدقيق الداخلي',             array['Internal Auditor'])
) as d(code, name_en, name_ar, aliases)
where e.code = 'AACT'
on conflict (entity_id, code) do nothing;

-- ---------------------------------------------------------------- designations (job titles)
insert into hr.job_titles(entity_id, code, name_en, name_ar, aliases)
select e.id, j.code, j.name_en, j.name_ar, j.aliases
from hr.legal_entities e
cross join (values
  ('OPR',    'Operator',         'مشغل',            array['Opr']),
  ('JRSUP',  'Jr. Supervisor',   'مشرف مساعد',      array['Jr.Supervisor', 'Junior Supervisor']),
  ('SUP',    'Supervisor',       'مشرف',            array['Supvr']),
  ('SRSUP',  'Sr. Supervisor',   'مشرف أول',        array['Sr.Supervisor', 'Senior Supervisor']),
  ('FMN',    'Foreman',          'رئيس عمال',       array['Fore Man']),
  ('MGSTAFF','Management staff', 'موظف إداري',      array['MG', 'Staff'])
) as j(code, name_en, name_ar, aliases)
where e.code = 'AACT'
on conflict (entity_id, code) do nothing;

-- ---------------------------------------------------------------- staff categories (linked to the pay groups)
-- Importing a row with category MG puts the employee in the confidential MG pay group (management payroll team only).
insert into hr.employee_categories(entity_id, code, name_en, name_ar, pay_basis, counts_for_omanisation)
select e.id, c.code, c.name_en, c.name_ar, 'MONTHLY', true
from hr.legal_entities e
cross join (values
  ('NMG', 'Non-management staff', 'موظفون غير إداريين'),
  ('MG',  'Management staff',     'الموظفون الإداريون')
) as c(code, name_en, name_ar)
where e.code = 'AACT'
on conflict (entity_id, code) do nothing;

-- ---------------------------------------------------------------- pay components (AACT payroll codes)
-- SPF wage = basic + monthly allowances; the two air-ticket allowances do not count (confirm with the lawyer;
-- changeable in Payroll → Set-up). Names can be corrected in Payroll → Set-up.
insert into hr.pay_components(code, name_en, name_ar, kind, is_basic, sort, spf_base) values
  ('HRA',    'House rent allowance',                     'بدل السكن',                         'EARNING', false, 2,  true),
  ('ETRA',   'Transport allowance',                      'بدل النقل',                         'EARNING', false, 3,  true),
  ('EFOOD',  'Food allowance',                           'بدل الطعام',                        'EARNING', false, 4,  true),
  ('ESUALL', 'Utility allowance',                        'بدل المرافق',                       'EARNING', false, 5,  true),
  ('AUTL',   'Expat utility allowance',                  'بدل مرافق للوافدين',                'EARNING', false, 6,  true),
  ('ESPL',   'Special allowance',                        'بدل خاص',                           'EARNING', false, 7,  true),
  ('EFLIFT', 'Forklift allowance',                       'بدل الرافعة الشوكية',               'EARNING', false, 8,  true),
  ('EDUST',  'Dust allowance',                           'بدل الغبار',                        'EARNING', false, 9,  true),
  ('EAIR24', 'Air ticket allowance (up to 3 years)',     'بدل تذكرة السفر (حتى 3 سنوات)',      'EARNING', false, 10, false),
  ('EAIR12', 'Air ticket allowance (4th year onwards)',  'بدل تذكرة السفر (من السنة الرابعة)', 'EARNING', false, 11, false)
on conflict (code) do nothing;

-- the generic demo components are switched off (kept for history, hidden from new salaries)
update hr.pay_components set is_active = false
 where code in ('HOUSING','TRANSPORT','FOOD','TELEPHONE','UTILITY','SPECIAL','OTHER_ALLOW') and is_active;

-- ---------------------------------------------------------------- employee numbers: AACT-0472
update hr.settings set value = '4'::jsonb, updated_at = now()
 where key = 'employee_no_digits' and value = '5'::jsonb
   and not exists (select 1 from hr.employees);


-- 6. result
select (select count(*) from hr.employees) as employees, (select count(*) from auth.users) as logins,
       (select count(*) from hr.departments) as departments, (select count(*) from hr.job_titles) as designations,
       (select count(*) from hr.employee_categories) as categories,
       (select count(*) from hr.pay_components where is_active) as pay_components_in_use;

commit;
