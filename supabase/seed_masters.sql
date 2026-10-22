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
