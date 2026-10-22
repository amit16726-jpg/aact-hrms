-- AACT HRMS — 1.10.0 AACT masters and the first real data load: database tests.
-- Runs after 10–80. Loads supabase/seed_masters.sql (twice: it must be safe to re-run) and imports
-- made-up people with the spellings found in AACT's NMG and MG staff lists.
-- Runs as the database owner; permissions are still enforced by the API functions (signed-in user via the JWT claim).

set client_min_messages = warning;
reset role;

-- earlier suites use their own test company coded AACT; move it aside so the real masters build a fresh company
update hr.legal_entities set code = 'AACT_T10' where code = 'AACT';

\ir ../../supabase/seed_masters.sql
\ir ../../supabase/seed_masters.sql

update hr.settings set value = '4'::jsonb where key = 'employee_no_digits';

do $$
declare v_ent uuid := (select id from hr.legal_entities where code = 'AACT');
begin
  perform tst.check(v_ent is not null, 'company AACT created');
  perform tst.check((select count(*) from hr.departments where entity_id = v_ent) = 30, '30 departments');
  perform tst.check((select count(*) from hr.job_titles where entity_id = v_ent) = 6, '6 designations');
  perform tst.check((select count(*) from hr.employee_categories where entity_id = v_ent) = 2, 'MG and NMG categories');
  perform tst.check((select count(*) from hr.pay_components where code in ('HRA','EAIR12','EAIR24','EFOOD','ESPL','ETRA','ESUALL','EFLIFT','EDUST','AUTL') and is_active) = 10,
    '10 AACT pay components');
  perform tst.check((select bool_and(not spf_base) from hr.pay_components where code in ('EAIR12','EAIR24')), 'air-ticket allowances do not count for SPF');
  perform tst.check((select bool_and(spf_base) from hr.pay_components where code in ('BASIC','HRA','EFOOD','ESPL','ETRA','ESUALL','EFLIFT','EDUST','AUTL')),
    'basic and monthly allowances count for SPF');
  perform tst.check(not exists (select 1 from hr.pay_components where code in ('HOUSING','TRANSPORT','TELEPHONE') and is_active), 'generic demo components switched off');
  perform tst.check(hr.match_key('Jr. Supervisor') = hr.match_key('jr.supervisor') and hr.match_key('Plant 1') = 'PLANT1', 'match key ignores spaces, dots and case');
  perform tst.check(hr.norm_date('12.05-1998') = '1998-05-12' and hr.norm_date('1/3/2021') = '2021-03-01' and hr.norm_date('2021-03-01') = '2021-03-01',
    'day-first dates understood');
  perform tst.expect_error('select hr.norm_date(''31/02/2020'')', 'does not exist');
  perform tst.check(hr.norm_employee_no('472') = 'AACT-0472' and hr.norm_employee_no('5') = 'AACT-0005' and hr.norm_employee_no('X-9') = 'X-9', 'plain numbers get the company format');
  perform tst.check(hr.norm_nationality('Omani') = 'OM' and hr.norm_nationality('in') = 'IN', 'OMANI means Oman');
end $$;


-- ===========================================================================
-- 1. Employees from the NMG list: names and short forms as written
-- ===========================================================================
do $$
declare r jsonb; v_rows jsonb; v_emp uuid; n_before int := (select count(*) from hr.employees);
begin
  perform tst.as_user('hrm');
  v_rows := jsonb_build_array(
    jsonb_build_object('employee_no', '472', 'full_name_en', 'Test Operator One', 'nationality', 'Omani', 'gender', 'M', 'date_of_birth', '12.05-1998',
      'join_date', '01/03/2021', 'company_code', 'AACT', 'department', 'Lab', 'designation', 'Jr.Supervisor', 'category', 'NMG'),
    jsonb_build_object('employee_no', '701', 'full_name_en', 'Test Operator Two', 'nationality', 'IN', 'join_date', '15-08-2019',
      'company_code', 'AACT', 'department', 'Plant 1', 'designation', 'Sr. Supervisor', 'category_code', 'nmg'),
    jsonb_build_object('employee_no', '5', 'full_name_en', 'Test Manager', 'nationality', 'IN', 'join_date', '01/01/2010',
      'company_code', 'AACT', 'department', 'Maint', 'designation', 'Management staff', 'category', 'MG'),
    jsonb_build_object('employee_no', '9', 'full_name_en', 'Bad Department', 'nationality', 'IN', 'join_date', '01/01/2020',
      'company_code', 'AACT', 'department', 'Nowhere', 'designation', 'Operator', 'category', 'NMG'));
  r := public.hr_import('EMPLOYEES', v_rows, true, 'nmg.csv');
  perform tst.check((r->>'ok')::int = 2 and (r->>'failed')::int = 2, 'dry run: 2 good rows, MG row and bad department rejected: ' || (r->'results')::text);
  perform tst.check(exists (select 1 from jsonb_array_elements(r->'results') x where x->>'message' like '%management payroll team%'), 'HR cannot import MG staff');
  perform tst.check(exists (select 1 from jsonb_array_elements(r->'results') x where x->>'message' like '%department "Nowhere"%'), 'unknown department named');
  perform tst.check((select count(*) from hr.employees) = n_before, 'dry run created nothing');

  r := public.hr_import('EMPLOYEES', jsonb_build_array(v_rows->0, v_rows->1), false, 'nmg.csv');
  perform tst.check((r->>'ok')::int = 2, 'two NMG employees imported');
  select id into v_emp from hr.employees where employee_no = 'AACT-0472';
  perform tst.check(v_emp is not null, 'number 472 stored as AACT-0472');
  perform tst.check((select nationality = 'OM' and date_of_birth = '1998-05-12' and join_date = '2021-03-01' and pay_group = 'NMG' from hr.employees where id = v_emp),
    'nationality, dates and pay group');
  perform tst.check((select d.code = 'LAB' and j.code = 'JRSUP' and c.code = 'NMG'
                       from hr.employee_assignments a join hr.departments d on d.id = a.department_id join hr.job_titles j on j.id = a.job_title_id
                       join hr.employee_categories c on c.id = a.category_id where a.employee_id = v_emp and a.effective_to is null),
    'Lab → Laboratory, Jr.Supervisor → Jr. Supervisor');
  perform tst.check((select d.code from hr.employee_assignments a join hr.departments d on d.id = a.department_id
                       join hr.employees e on e.id = a.employee_id where e.employee_no = 'AACT-0701' and a.effective_to is null) = 'PLANT1', 'Plant 1 → PLANT1');

  -- opening salary from the NMG sheet layout; Gross and name columns are ignored, plain number accepted
  r := public.hr_import('SALARIES', jsonb_build_array(jsonb_build_object('employee_no', '472', 'effective_from', '01/03/2021', 'BASIC', '250', 'HRA', '60',
         'EAIR24', '12.5', 'ETRA', '20', 'EFOOD', '', 'Gross', '342.5', 'Emp_Name', 'Test Operator One')), false);
  perform tst.check((r->>'ok')::int = 1, 'opening salary imported: ' || (r->'results')::text);
  perform tst.check((select count(*) from hr.compensation_lines l join hr.compensation_revisions v on v.id = l.revision_id
                      where v.employee_id = v_emp and v.status = 'PENDING') = 4, 'four salary lines, blanks and Gross skipped');
  perform tst.check((select total_monthly from hr.compensation_revisions where employee_id = v_emp and status = 'PENDING') = 342.5, 'total is the gross');
end $$;

reset role;
do $$
begin
  perform tst.check(hr.next_employee_no() = 'AACT-0702', 'next automatic number continues after the highest (AACT-0701): ' || hr.next_employee_no());
end $$;

-- ===========================================================================
-- 2. MG staff: only the management payroll team; the MG category places them in the MG pay group
-- ===========================================================================
do $$
begin
  perform tst.as_user('admin');
  perform public.hr_set_user_roles(tst.id('user_mg1'), array['MG_PAYROLL','EMPLOYEE','HR_MANAGER']);
end $$;
do $$
declare r jsonb;
begin
  perform tst.as_user('mg1');
  r := public.hr_import('EMPLOYEES', jsonb_build_array(jsonb_build_object('employee_no', '5', 'full_name_en', 'Test Manager', 'nationality', 'IN',
         'join_date', '1.1.2010', 'company_code', 'AACT', 'department', 'Maint', 'category', 'MG')), false, 'mg.csv');
  perform tst.check((r->>'ok')::int = 0, 'designation still required');
  r := public.hr_import('EMPLOYEES', jsonb_build_array(jsonb_build_object('employee_no', '5', 'full_name_en', 'Test Manager', 'nationality', 'IN',
         'join_date', '1.1.2010', 'company_code', 'AACT', 'department', 'Maint', 'designation', 'MG', 'category', 'MG')), false, 'mg.csv');
  perform tst.check((r->>'ok')::int = 1, 'MG staff imported by the team: ' || (r->'results')::text);
  perform tst.check((select pay_group from hr.employees where employee_no = 'AACT-0005') = 'MG', 'MG category → MG pay group');
  perform tst.check(exists (select 1 from hr.access_log l join hr.employees e on e.id = l.employee_id where e.employee_no = 'AACT-0005' and l.data_kind = 'PAY_GROUP'),
    'pay group change logged');
end $$;
do $$
declare r jsonb;
begin
  perform tst.as_user('hrm');
  r := public.hr_import('SALARIES', '[{"employee_no":"5","BASIC":"3000"}]'::jsonb, false);
  perform tst.check((r->>'failed')::int = 1 and (r->'results'->0->>'message') ~* 'management', 'HR cannot load an MG salary: ' || (r->'results')::text);
end $$;

-- ===========================================================================
-- 3. Masters: aliases editable; pay component names correctable; basic cannot be switched off
-- ===========================================================================
do $$
declare v jsonb; v_dep uuid := (select d.id from hr.departments d join hr.legal_entities e on e.id = d.entity_id where e.code = 'AACT' and d.code = 'GLAZE');
begin
  perform tst.as_user('hrm');
  v := public.hr_save_master('department', jsonb_build_object('id', v_dep, 'aliases', jsonb_build_array('GP', 'Glaze Prep', 'Glazing')));
  perform tst.check(v->'aliases' = '["GP", "Glaze Prep", "Glazing"]'::jsonb, 'department aliases saved');
  perform tst.check(hr.master_id('departments', (select id from hr.legal_entities where code = 'AACT'), 'glazing') = v_dep, 'new alias used by import');

  perform tst.as_user('fin');
  v := public.hr_save_payroll_setup(jsonb_build_object('components', jsonb_build_array(
         jsonb_build_object('code', 'ESUALL', 'name_en', 'Supervisor allowance', 'name_ar', 'بدل الإشراف', 'gl_account', '5104', 'spf_base', true),
         jsonb_build_object('code', 'ESPL', 'is_active', false))));
  perform tst.check((select name_en = 'Supervisor allowance' and gl_account = '5104' from hr.pay_components where code = 'ESUALL'), 'component renamed');
  perform tst.check((select not is_active from hr.pay_components where code = 'ESPL'), 'component switched off');
  perform tst.expect_error($q$select public.hr_save_payroll_setup('{"components":[{"code":"BASIC","is_active":false}]}'::jsonb)$q$, 'cannot be switched off');
  perform tst.expect_error($q$select public.hr_save_payroll_setup('{"components":[{"code":"HRA","name_en":" "}]}'::jsonb)$q$, 'English name');
  perform tst.as_user('hrm');
  perform tst.expect_error($q$select public.hr_save_payroll_setup('{"components":[{"code":"HRA","name_en":"x"}]}'::jsonb)$q$, 'NOT_ALLOWED|permission');
end $$;

reset role;
update hr.pay_components set is_active = true where code = 'ESPL';
select 'ALL MASTERS TESTS PASSED' as result;
