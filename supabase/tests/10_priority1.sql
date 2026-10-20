-- AACT HRMS — Priority 1 database tests.
-- Runs as the real "authenticated" role (what the app uses), switching the signed-in user.
-- Local: psql -f supabase/tests/10_priority1.sql   |   Live: run inside BEGIN … ROLLBACK.
\set ON_ERROR_STOP on
set client_min_messages = warning;

create schema if not exists tst;
create table if not exists tst.ids (k text primary key, v uuid);
create or replace function tst.as_user(p text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce((select v::text from tst.ids where k = 'user_' || p), ''), false);
end $$;
create or replace function tst.id(p text) returns uuid language sql as $$ select v from tst.ids where k = p $$;
create or replace function tst.put(p text, v uuid) returns void language sql as $$
  insert into tst.ids values (p, v) on conflict (k) do update set v = excluded.v $$;
create or replace function tst.expect_error(p_sql text, p_pattern text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'TEST FAILED: expected error matching "%" from: %', p_pattern, p_sql;
exception when others then
  if sqlerrm like 'TEST FAILED%' then raise; end if;
  if sqlerrm !~* p_pattern then
    raise exception 'TEST FAILED: expected "%" but got "%" from: %', p_pattern, sqlerrm, p_sql;
  end if;
end $$;
create or replace function tst.check(p_ok boolean, p_what text) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then raise exception 'TEST FAILED: %', p_what; end if;
end $$;
grant usage on schema tst to authenticated;
grant all on all tables in schema tst to authenticated;
grant execute on all functions in schema tst to authenticated;

-- Users (as the platform would create them)
insert into tst.ids values
 ('user_admin', '00000000-0000-0000-0000-00000000a001'), ('user_hrm', '00000000-0000-0000-0000-00000000a002'),
 ('user_hro',   '00000000-0000-0000-0000-00000000a003'), ('user_fin', '00000000-0000-0000-0000-00000000a004'),
 ('user_aud',   '00000000-0000-0000-0000-00000000a005'), ('user_mgr', '00000000-0000-0000-0000-00000000a006'),
 ('user_emp',   '00000000-0000-0000-0000-00000000a007'), ('user_nobody','00000000-0000-0000-0000-00000000a008')
on conflict do nothing;
insert into auth.users(id, email)
select v, substr(k, 6) || '@aact.test' from tst.ids where k like 'user_%' on conflict do nothing;

set role authenticated;

-- ===========================================================================
-- 1. Bootstrap, roles, direct table access
-- ===========================================================================
do $$
declare v jsonb;
begin
  perform tst.as_user('admin');
  v := public.hr_me();
  perform tst.check(not (v->>'admin_exists')::boolean, 'no admin before claim');
  v := public.hr_claim_first_admin();
  perform tst.check(v->'roles' ? 'SUPER_ADMIN', 'admin claimed');
  perform tst.as_user('hrm');
  perform tst.expect_error('select public.hr_claim_first_admin()', 'ADMIN_EXISTS');
  perform tst.expect_error('select public.hr_set_user_roles(tst.id(''user_hrm''), array[''SUPER_ADMIN''])', 'NOT_ALLOWED');

  perform tst.as_user('admin');
  perform public.hr_set_user_roles(tst.id('user_hrm'), array['HR_MANAGER']);
  perform public.hr_set_user_roles(tst.id('user_hro'), array['HR_OFFICER']);
  perform public.hr_set_user_roles(tst.id('user_fin'), array['FINANCE']);
  perform public.hr_set_user_roles(tst.id('user_aud'), array['AUDITOR']);
  perform public.hr_set_user_roles(tst.id('user_mgr'), array['MANAGER','EMPLOYEE']);
  perform public.hr_set_user_roles(tst.id('user_emp'), array['EMPLOYEE']);
  perform tst.expect_error('select public.hr_set_user_roles(tst.id(''user_admin''), array[''HR_MANAGER''])', 'own administrator');
  perform tst.expect_error('select public.hr_set_user_active(tst.id(''user_admin''), false)', 'own account');

  perform tst.as_user('hro');
  v := public.hr_me();
  perform tst.check(v->'permissions' ? 'EMP_WRITE' and not (v->'permissions' ? 'SALARY_APPROVE'), 'HR officer permissions');
  perform tst.expect_error('select public.hr_list_users()', 'NOT_ALLOWED');

  perform tst.as_user('nobody');
  perform tst.expect_error('select public.hr_list_master(''department'')', 'NOT_ALLOWED');
  perform tst.check((public.hr_list_employees('{}')->>'total')::int = 0, 'user without roles sees no employees');
end $$;

-- the app role cannot reach the tables directly
do $$
begin
  perform tst.as_user('admin');
  perform tst.expect_error('select count(*) from hr.employees', 'permission denied');
  perform tst.expect_error('select hr.has_perm(''EMP_READ'')', 'permission denied');
end $$;

-- ===========================================================================
-- 2. Organisation masters
-- ===========================================================================
do $$
declare v jsonb; v_ent uuid;
begin
  perform tst.as_user('hrm');
  v := public.hr_save_master('entity', '{"code":"AACT","name_en":"AACT Industries LLC","name_ar":"شركة أ.أ.س.ت","cr_number":"1234567"}');
  v_ent := (v->>'id')::uuid; perform tst.put('ent', v_ent);
  perform tst.expect_error(format('select public.hr_save_master(''entity'', %L)', '{"code":"AACT","name_en":"Dup"}'), 'DUPLICATE');

  perform tst.put('loc', (public.hr_save_master('location', jsonb_build_object('entity_id', v_ent, 'code','SOHAR','name_en','Sohar factory','location_type','FACTORY'))->>'id')::uuid);
  perform tst.put('cc_prod', (public.hr_save_master('cost_centre', jsonb_build_object('entity_id', v_ent, 'code','CC100','name_en','Production'))->>'id')::uuid);
  perform tst.put('cc_adm', (public.hr_save_master('cost_centre', jsonb_build_object('entity_id', v_ent, 'code','CC200','name_en','Administration'))->>'id')::uuid);
  perform tst.put('dep_ops', (public.hr_save_master('department', jsonb_build_object('entity_id', v_ent, 'code','OPS','name_en','Operations','cost_centre_id', tst.id('cc_prod')))->>'id')::uuid);
  perform tst.put('dep_prod', (public.hr_save_master('department', jsonb_build_object('entity_id', v_ent, 'code','PROD','name_en','Production','parent_id', tst.id('dep_ops'), 'cost_centre_id', tst.id('cc_prod')))->>'id')::uuid);
  perform tst.put('dep_hr', (public.hr_save_master('department', jsonb_build_object('entity_id', v_ent, 'code','HR','name_en','Human Resources','cost_centre_id', tst.id('cc_adm')))->>'id')::uuid);
  -- department under itself (via its child) is refused
  perform tst.expect_error(format('select public.hr_save_master(''department'', %L)',
            jsonb_build_object('id', tst.id('dep_ops'), 'parent_id', tst.id('dep_prod'))), 'under itself');
  -- single-column update works
  v := public.hr_save_master('department', jsonb_build_object('id', tst.id('dep_hr'), 'name_ar', 'الموارد البشرية'));
  perform tst.check(v->>'name_ar' = 'الموارد البشرية', 'single column update');

  perform tst.put('gr_w1', (public.hr_save_master('grade', jsonb_build_object('entity_id', v_ent, 'code','W1','name_en','Worker 1','level',1,'min_basic',150,'max_basic',300))->>'id')::uuid);
  perform tst.put('gr_m1', (public.hr_save_master('grade', jsonb_build_object('entity_id', v_ent, 'code','M1','name_en','Manager 1','level',5,'min_basic',1200,'max_basic',2500))->>'id')::uuid);
  perform tst.expect_error(format('select public.hr_save_master(''grade'', %L)',
            jsonb_build_object('entity_id', v_ent, 'code','BAD','name_en','Bad','min_basic',500,'max_basic',100)), 'INVALID');

  perform tst.put('job_op', (public.hr_save_master('job_title', jsonb_build_object('entity_id', v_ent, 'code','OPR','name_en','Machine operator','profession_code','8122'))->>'id')::uuid);
  perform tst.put('job_mgr', (public.hr_save_master('job_title', jsonb_build_object('entity_id', v_ent, 'code','PMGR','name_en','Production manager','profession_code','1321'))->>'id')::uuid);
  -- Omani-only needs a source and RULES_APPROVE
  perform tst.expect_error(format('select public.hr_save_master(''job_title'', %L)',
            jsonb_build_object('entity_id', v_ent, 'code','HRO','name_en','HR officer','omani_only', true)), 'INVALID');
  perform tst.put('job_hro', (public.hr_save_master('job_title', jsonb_build_object('entity_id', v_ent, 'code','HRO','name_en','HR officer',
            'omani_only', true, 'omani_only_source', 'TEST decision ref', 'profession_code','2423'))->>'id')::uuid);
  perform tst.put('cat_staff', (public.hr_save_master('category', jsonb_build_object('entity_id', v_ent, 'code','STAFF','name_en','Monthly staff'))->>'id')::uuid);
  perform tst.put('cat_trainee', (public.hr_save_master('category', jsonb_build_object('entity_id', v_ent, 'code','TRN','name_en','Trainee (not counted)','counts_for_omanisation', false))->>'id')::uuid);

  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_save_master(''job_title'', %L)',
            jsonb_build_object('id', tst.id('job_op'), 'omani_only', true, 'omani_only_source','x')), 'RULES_APPROVE|NOT_ALLOWED');
  perform tst.expect_error(format('select public.hr_save_master(''location'', %L)',
            jsonb_build_object('entity_id', tst.id('ent'), 'code','X','name_en','X')), 'NOT_ALLOWED');
  perform tst.check(jsonb_array_length(public.hr_list_master('department', tst.id('ent'))) = 3, 'list departments');
end $$;

-- ===========================================================================
-- 3. Employees and assignments
-- ===========================================================================
do $$
declare v jsonb; v_mgr uuid; v_w uuid;
begin
  perform tst.as_user('hro');
  v := public.hr_save_employee(jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Salim Al Harthy', 'full_name_ar', 'سالم الحارثي', 'nationality', 'OM',
    'gender','M', 'date_of_birth','1985-03-12', 'join_date','2020-01-05', 'civil_number','11223344',
    'work_email','salim@aact.test', 'mobile','+968 9123 4567',
    'assignment', jsonb_build_object('department_id', tst.id('dep_prod'), 'job_title_id', tst.id('job_mgr'),
                  'grade_id', tst.id('gr_m1'), 'category_id', tst.id('cat_staff'), 'location_id', tst.id('loc'))));
  v_mgr := (v->'employee'->>'id')::uuid; perform tst.put('emp_mgr', v_mgr);
  perform tst.check(v->'employee'->>'employee_no' = 'AACT-00001', 'generated employee number');
  perform tst.check(v->'employee'->>'status' = 'ACTIVE', 'no probation → active');
  perform tst.check(v->'current_assignment'->>'cost_centre_id' = tst.id('cc_prod')::text, 'cost centre defaults from department');

  v := public.hr_save_employee(jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Ravi Kumar', 'nationality', 'IN', 'gender','M',
    'date_of_birth','1992-07-01', 'join_date', (current_date - 60)::text, 'probation_end_date', (current_date + 20)::text,
    'civil_number','RC998877',
    'assignment', jsonb_build_object('department_id', tst.id('dep_prod'), 'job_title_id', tst.id('job_op'),
                  'grade_id', tst.id('gr_w1'), 'category_id', tst.id('cat_staff'), 'manager_id', v_mgr)));
  v_w := (v->'employee'->>'id')::uuid; perform tst.put('emp_w', v_w);
  perform tst.check(v->'employee'->>'status' = 'PROBATION', 'probation status');

  -- duplicates
  perform tst.expect_error(format('select public.hr_save_employee(%L)', jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'ravi kumar', 'nationality','IN', 'date_of_birth','1992-07-01',
    'join_date', current_date::text, 'assignment', jsonb_build_object('department_id', tst.id('dep_prod'),
    'job_title_id', tst.id('job_op'), 'category_id', tst.id('cat_staff')))), 'POSSIBLE_DUPLICATE');
  perform tst.expect_error(format('select public.hr_save_employee(%L)', jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Another Person', 'nationality','IN', 'civil_number','rc998877',
    'join_date', current_date::text, 'assignment', jsonb_build_object('department_id', tst.id('dep_prod'),
    'job_title_id', tst.id('job_op'), 'category_id', tst.id('cat_staff')))), 'civil / resident card');
  -- validation
  perform tst.expect_error(format('select public.hr_save_employee(%L)', jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Bad Mail', 'nationality','IN', 'work_email','not-an-email',
    'join_date', current_date::text, 'assignment', '{}'::jsonb)), 'INVALID_EMAIL');
  perform tst.expect_error(format('select public.hr_save_employee(%L)', jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'No Dept', 'nationality','IN', 'join_date', current_date::text,
    'assignment', '{}'::jsonb)), 'Department is required');
  perform tst.expect_error(format('select public.hr_save_employee(%L)', jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Bad Date', 'nationality','IN', 'join_date', '2026-02-30',
    'assignment', '{}'::jsonb)), 'INVALID_DATE');

  -- Omani-only job: expatriate refused, HR officer cannot approve the exception
  perform tst.expect_error(format('select public.hr_save_employee(%L)', jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Ahmed Expat', 'nationality','EG', 'join_date', current_date::text,
    'assignment', jsonb_build_object('department_id', tst.id('dep_hr'), 'job_title_id', tst.id('job_hro'),
    'category_id', tst.id('cat_staff')))), 'OMANI_ONLY');
  perform tst.expect_error(format('select public.hr_save_employee(%L)', jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Ahmed Expat', 'nationality','EG', 'join_date', current_date::text,
    'exception_reason', 'Temporary cover while recruitment is open',
    'assignment', jsonb_build_object('department_id', tst.id('dep_hr'), 'job_title_id', tst.id('job_hro'),
    'category_id', tst.id('cat_staff')))), 'EXCEPTION_APPROVE|NOT_ALLOWED');

  -- Omani worker, and an Omani trainee (not counted for Omanisation)
  perform tst.put('emp_om', (public.hr_save_employee(jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Fatma Al Balushi', 'nationality','OM', 'gender','F', 'join_date','2024-02-01',
    'assignment', jsonb_build_object('department_id', tst.id('dep_hr'), 'job_title_id', tst.id('job_hro'),
                  'category_id', tst.id('cat_staff'), 'manager_id', v_mgr)))->'employee'->>'id')::uuid);
  perform tst.put('emp_trn', (public.hr_save_employee(jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Hamad Trainee', 'nationality','OM', 'join_date','2025-09-01',
    'assignment', jsonb_build_object('department_id', tst.id('dep_prod'), 'job_title_id', tst.id('job_op'),
                  'category_id', tst.id('cat_trainee'))))->'employee'->>'id')::uuid);

  -- HR manager may place an expatriate with a recorded exception
  perform tst.as_user('hrm');
  v := public.hr_save_employee(jsonb_build_object(
    'entity_id', tst.id('ent'), 'full_name_en', 'Ahmed Expat', 'nationality','EG', 'join_date', current_date::text,
    'exception_reason', 'Temporary cover while recruitment is open',
    'assignment', jsonb_build_object('department_id', tst.id('dep_hr'), 'job_title_id', tst.id('job_hro'),
    'category_id', tst.id('cat_staff'))));
  perform tst.put('emp_exc', (v->'employee'->>'id')::uuid);
  perform tst.check(jsonb_array_length(v->'omanisation_exceptions') = 1, 'exception recorded');
  perform tst.check(v->'current_assignment'->>'omanisation_exception_id' is not null, 'assignment linked to exception');

  -- links for self-service tests
  perform tst.as_user('admin');
  perform public.hr_link_user_employee(tst.id('user_mgr'), v_mgr);
  perform public.hr_link_user_employee(tst.id('user_emp'), v_w);
  perform tst.expect_error(format('select public.hr_link_user_employee(%L, %L)', tst.id('user_hro'), v_w), 'already linked');
end $$;

do $$
declare v jsonb; v_from date := current_date + 10;
begin
  perform tst.as_user('hro');
  -- transfer from a future date: current record closes the day before
  v := public.hr_add_assignment(tst.id('emp_w'), jsonb_build_object('effective_from', v_from::text, 'reason','TRANSFER',
         'department_id', tst.id('dep_ops'), 'notes','Moved to operations'));
  perform tst.check(jsonb_array_length(v->'assignments') = 2, 'two assignment periods');
  perform tst.check((v->'assignments'->1->>'effective_to')::date = v_from - 1, 'previous period closed day before');
  perform tst.check(v->'current_assignment'->>'department_id' = tst.id('dep_prod')::text, 'today still in production');
  perform tst.check(v->'assignments'->0->>'job_title_id' = tst.id('job_op')::text, 'unchanged fields carried over');
  perform tst.expect_error(format('select public.hr_add_assignment(%L, %L)', tst.id('emp_w'),
            jsonb_build_object('effective_from', (v_from - 1)::text, 'reason','TRANSFER')), 'must start after');
  perform tst.expect_error(format('select public.hr_add_assignment(%L, %L)', tst.id('emp_w'),
            jsonb_build_object('reason','CORRECTION', 'shift_code','B')), 'Explain the correction');
  v := public.hr_add_assignment(tst.id('emp_w'), jsonb_build_object('reason','CORRECTION', 'shift_code','B', 'notes','Shift was keyed wrong'));
  perform tst.check(v->'assignments'->0->>'shift_code' = 'B', 'correction updates the open period');
  -- manager loop refused
  perform tst.expect_error(format('select public.hr_add_assignment(%L, %L)', tst.id('emp_mgr'),
            jsonb_build_object('reason','CORRECTION', 'manager_id', tst.id('emp_w'), 'notes','loop')), 'already reports');
  -- the database itself refuses overlapping periods
  reset role;
  perform tst.expect_error(format('insert into hr.employee_assignments(employee_id, effective_from, department_id, job_title_id, category_id) values (%L, %L, %L, %L, %L)',
            tst.id('emp_w'), current_date, tst.id('dep_prod'), tst.id('job_op'), tst.id('cat_staff')), 'no_overlap|conflicting key');
  set role authenticated;
end $$;

-- ===========================================================================
-- 4. Visibility: HR, manager (team, limited fields), employee (self), finance
-- ===========================================================================
do $$
declare v jsonb;
begin
  perform tst.as_user('emp');
  v := public.hr_list_employees('{}');
  perform tst.check((v->>'total')::int = 1 and v->'rows'->0->>'id' = tst.id('emp_w')::text, 'employee sees only himself');
  v := public.hr_get_employee(tst.id('emp_w'));
  perform tst.check(v->>'access' = 'SELF' and v->'employee' ? 'date_of_birth', 'self sees own full record');
  perform tst.expect_error(format('select public.hr_get_employee(%L)', tst.id('emp_mgr')), 'cannot see this employee');

  perform tst.as_user('mgr');
  v := public.hr_list_employees('{}');
  perform tst.check((v->>'total')::int = 3, 'manager sees himself + 2 reports');
  v := public.hr_get_employee(tst.id('emp_w'));
  perform tst.check(v->>'access' = 'TEAM', 'team access');
  perform tst.check(not (v->'employee' ? 'date_of_birth') and not (v->'employee' ? 'civil_number'), 'team view hides personal data');
  perform tst.check(jsonb_array_length(v->'events') = 0, 'team view hides history');
  perform tst.expect_error(format('select public.hr_get_compensation(%L)', tst.id('emp_w')), 'salary');
  perform tst.expect_error(format('select public.hr_list_employee_documents(%L)', tst.id('emp_w')), 'documents');
  perform tst.expect_error(format('select public.hr_save_employee(%L)', jsonb_build_object('id', tst.id('emp_w'), 'mobile','+96899999999')), 'NOT_ALLOWED');

  perform tst.as_user('hro');
  v := public.hr_list_employees('{"nationality":"OMANI","sort":"name"}');
  perform tst.check((v->>'total')::int = 3, 'Omani filter');
  v := public.hr_list_employees('{"search":"ravi"}');
  perform tst.check((v->>'total')::int = 1, 'search by name');
  v := public.hr_list_employees('{"search":"rc9988"}');
  perform tst.check((v->>'total')::int = 1, 'HR can search by resident card');
  v := public.hr_list_employees(jsonb_build_object('department_id', tst.id('dep_prod'), 'limit', 1));
  perform tst.check((v->>'total')::int = 3 and jsonb_array_length(v->'rows') = 1, 'department filter + paging');
end $$;

-- ===========================================================================
-- 5. Compensation (maker-checker)
-- ===========================================================================
do $$
declare v jsonb; v_rev uuid;
begin
  perform tst.as_user('hro');
  v := public.hr_propose_compensation(tst.id('emp_w'), jsonb_build_object('effective_from', (current_date - 60)::text,
         'reason','JOIN', 'lines', jsonb_build_array(
            jsonb_build_object('component_code','BASIC','amount','350.000'),
            jsonb_build_object('component_code','HOUSING','amount','75.500'),
            jsonb_build_object('component_code','TRANSPORT','amount','0'))));
  v_rev := (v->>'revision_id')::uuid; perform tst.put('rev1', v_rev);
  perform tst.check(v->'warnings'->0->>'code' = 'OUTSIDE_GRADE_BAND', 'grade band warning (350 > 300)');
  perform tst.check((v->'compensation'->'pending'->>'total_monthly')::numeric = 425.5, 'gross total');
  perform tst.check(jsonb_array_length(v->'compensation'->'pending'->'lines') = 2, 'zero allowance dropped');
  perform tst.expect_error(format('select public.hr_propose_compensation(%L, %L)', tst.id('emp_w'),
            jsonb_build_object('effective_from', current_date::text, 'lines', jsonb_build_array(jsonb_build_object('component_code','BASIC','amount','1'))))
          , 'PENDING_EXISTS');
  perform tst.expect_error(format('select public.hr_decide_compensation(%L, true)', v_rev), 'NOT_ALLOWED');

  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_propose_compensation(%L, %L)', tst.id('emp_om'),
            jsonb_build_object('effective_from', '2024-02-01', 'lines', jsonb_build_array(jsonb_build_object('component_code','BASIC','amount','12.3456'))))
          , 'INVALID_AMOUNT');
  v := public.hr_decide_compensation(v_rev, true, 'Per offer letter');
  perform tst.check((v->'current'->>'total_monthly')::numeric = 425.5, 'approved revision is current');

  -- the approver cannot approve what he proposed
  v := public.hr_propose_compensation(tst.id('emp_om'), jsonb_build_object('effective_from','2024-02-01','reason','JOIN',
         'lines', jsonb_build_array(jsonb_build_object('component_code','BASIC','amount','600'))));
  perform tst.expect_error(format('select public.hr_decide_compensation(%L, true)', (v->>'revision_id')), 'SELF_APPROVAL');
  perform tst.put('rev2', (v->>'revision_id')::uuid);

  -- finance reads, cannot approve; employee reads own; manager cannot read team
  perform tst.as_user('fin');
  v := public.hr_get_compensation(tst.id('emp_w'));
  perform tst.check(v->'current' is not null, 'finance reads salary');
  perform tst.expect_error(format('select public.hr_decide_compensation(%L, true)', tst.id('rev2')), 'NOT_ALLOWED');
  perform tst.as_user('emp');
  v := public.hr_get_compensation(tst.id('emp_w'));
  perform tst.check(v->>'access' = 'SELF' and (v->'current'->>'total_monthly')::numeric = 425.5, 'employee reads own salary');
  perform tst.check(v->'pending' = 'null'::jsonb or v->'pending' is null, 'employee does not see pending proposals');
  perform tst.as_user('admin');
  perform public.hr_decide_compensation(tst.id('rev2'), false, 'Wrong date');
  perform tst.as_user('hrm');
  perform tst.check(public.hr_get_compensation(tst.id('emp_om'))->'current' = 'null'::jsonb, 'rejected revision not current');
end $$;

-- ===========================================================================
-- 6. Bank account (maker-checker, masking)
-- ===========================================================================
do $$
declare v jsonb; v_id uuid;
begin
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_request_bank_change(%L, %L)', tst.id('emp_w'),
            '{"bank_name":"Bank Muscat","account_name":"Ravi Kumar","account_number":"12"}'), 'Account number');
  v := public.hr_request_bank_change(tst.id('emp_w'), '{"bank_name":"Bank Muscat","account_name":"Ravi Kumar","account_number":"0301 0123 4567 8901","iban":"OM81 0270 0000 1234 5678 901","swift_code":"BMUSOMRX"}');
  perform tst.check((v->'pending'->>'masked')::boolean and v->'pending'->>'account_number' like '%8901'
                    and v->'pending'->>'account_number' not like '0301%', 'HR officer sees masked number');
  v_id := (v->'pending'->>'id')::uuid;
  perform tst.expect_error(format('select public.hr_decide_bank(%L, true)', v_id), 'NOT_ALLOWED');
  perform tst.as_user('fin');
  v := public.hr_decide_bank(v_id, true, 'Checked bank letter');
  perform tst.check(v->'current'->>'account_number' = '0301012345678901', 'finance sees full approved number');
  perform tst.as_user('emp');
  perform tst.check(public.hr_get_bank(tst.id('emp_w'))->'current'->>'iban' = 'OM810270000012345678901', 'employee sees own IBAN');
  perform tst.as_user('aud');
  perform tst.expect_error(format('select public.hr_get_bank(%L)', tst.id('emp_w')), 'bank');
end $$;

-- ===========================================================================
-- 7. Documents, versions, storage policies, expiry, missing
-- ===========================================================================
do $$
declare v jsonb; v_p uuid; v_path text; v_path2 text; v_med text; n int;
begin
  v_path := tst.id('emp_w') || '/PASSPORT/aaaa1111.pdf';
  v_path2 := tst.id('emp_w') || '/PASSPORT/bbbb2222.pdf';
  v_med := tst.id('emp_w') || '/MEDICAL_FITNESS/cccc3333.pdf';

  -- storage policies: HR officer may upload, the employee may not
  perform tst.as_user('emp');
  perform tst.expect_error(format('insert into storage.objects(bucket_id, name) values (''hr-documents'', %L)', v_path), 'row-level security');
  perform tst.as_user('hro');
  insert into storage.objects(bucket_id, name) values ('hr-documents', v_path), ('hr-documents', v_path2), ('hr-documents', v_med);
  perform tst.expect_error(format('insert into storage.objects(bucket_id, name) values (''hr-documents'', %L)',
            tst.id('emp_w') || '/NOT_A_TYPE/x.pdf'), 'row-level security');

  perform tst.expect_error(format('select public.hr_save_document(%L, %L)', tst.id('emp_w'),
            '{"doc_type":"PASSPORT","doc_number":"Z1234567"}'), 'Expiry date is required');
  perform tst.expect_error(format('select public.hr_save_document(%L, %L)', tst.id('emp_w'),
            jsonb_build_object('doc_type','PASSPORT','doc_number','Z1234567','expiry_date', (current_date+20)::text,
                               'file_path', tst.id('emp_om') || '/PASSPORT/x.pdf')), 'not uploaded for this employee');
  v := public.hr_save_document(tst.id('emp_w'), jsonb_build_object('doc_type','PASSPORT','doc_number','Z1234567',
         'issue_date','2018-05-01','expiry_date', (current_date+20)::text, 'issuing_authority','Govt of India',
         'file_path', v_path, 'file_name','passport.pdf','mime_type','application/pdf','file_size', 120000));
  v_p := (v->>'id')::uuid;
  perform tst.check(v->>'bucket' = 'D30' and (v->>'days_left')::int = 20, 'expiry bucket');
  perform tst.expect_error(format('select public.hr_save_document(%L, %L)', tst.id('emp_w'),
            jsonb_build_object('doc_type','PASSPORT','doc_number','Z9','expiry_date', (current_date+900)::text)), 'DUPLICATE_DOCUMENT');
  perform tst.expect_error(format('select public.hr_verify_document(%L)', v_p), 'SELF_APPROVAL');

  -- replace = new version, old one superseded
  v := public.hr_save_document(tst.id('emp_w'), jsonb_build_object('replace_id', v_p, 'doc_type','PASSPORT','doc_number','Z7654321',
         'issue_date', (current_date-1)::text, 'expiry_date', (current_date+3650)::text, 'file_path', v_path2));
  perform tst.check((v->>'version')::int = 2, 'version 2');
  perform tst.put('doc_pass2', (v->>'id')::uuid);
  perform tst.expect_error(format('select public.hr_verify_document(%L)', v_p), 'Only a current document');
  v := public.hr_list_employee_documents(tst.id('emp_w'), true);
  perform tst.check(jsonb_array_length(v->'documents') = 2, 'history keeps old version');
  v := public.hr_list_employee_documents(tst.id('emp_w'), false);
  perform tst.check(jsonb_array_length(v->'documents') = 1, 'one current passport');

  perform public.hr_save_document(tst.id('emp_w'), jsonb_build_object('doc_type','RESIDENT_CARD','doc_number','RC998877',
         'expiry_date', (current_date - 5)::text));
  perform public.hr_save_document(tst.id('emp_w'), jsonb_build_object('doc_type','WORK_PERMIT','doc_number','WP-1',
         'expiry_date', (current_date + 45)::text));
  perform public.hr_save_contract(tst.id('emp_w'), jsonb_build_object('contract_type','FIXED_TERM',
         'start_date', (current_date-60)::text, 'end_date', (current_date+75)::text, 'probation_days', 90, 'notice_days', 30));

  -- HR officer has no DOC_SENSITIVE: medical document saved but not visible to him
  v := public.hr_save_document(tst.id('emp_w'), jsonb_build_object('doc_type','MEDICAL_FITNESS','doc_number','MF-1',
         'expiry_date', (current_date + 15)::text, 'file_path', v_med));
  perform tst.put('doc_med', (v->>'id')::uuid);
  v := public.hr_list_employee_documents(tst.id('emp_w'), false);
  perform tst.check(not exists (select 1 from jsonb_array_elements(v->'documents') d where d->>'doc_type' = 'MEDICAL_FITNESS'),
                    'sensitive document hidden from HR officer');
  perform tst.expect_error(format('select public.hr_document_file(%L)', tst.id('doc_med')), 'cannot open');
  select count(*) into n from storage.objects where name = v_med;
  perform tst.check(n = 0, 'storage hides sensitive file from HR officer');
  select count(*) into n from storage.objects where name = v_path2;
  perform tst.check(n = 1, 'storage shows normal file to HR officer');

  perform tst.as_user('hrm');
  perform tst.check((public.hr_document_file(tst.id('doc_med'))->>'file_path') = v_med, 'HR manager opens sensitive file');
  perform tst.check(public.hr_verify_document(tst.id('doc_pass2'))->>'verified_by_name' = 'hrm', 'verified by a second person');
end $$;

do $$
declare v jsonb; n int;
begin
  -- expiry list: HR sees all; the manager sees the team's non-sensitive items; the employee sees his own
  perform tst.as_user('hrm');
  v := public.hr_list_expiries('{"within_days":90}');
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'doc_type' = 'RESIDENT_CARD' and x->>'bucket' = 'EXPIRED'), 'expired resident card listed');
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'source' = 'CONTRACT' and x->>'bucket' = 'D90'), 'contract end listed');
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'doc_type' = 'MEDICAL_FITNESS'), 'HR manager sees medical expiry');
  perform tst.check(not exists (select 1 from jsonb_array_elements(v) x where x->>'doc_type' = 'PASSPORT'), 'renewed passport not listed');

  perform tst.as_user('mgr');
  v := public.hr_list_expiries('{"within_days":90}');
  perform tst.check(jsonb_array_length(v) = 3, 'manager sees 3 team items (resident card, work permit, contract)');
  perform tst.check(not exists (select 1 from jsonb_array_elements(v) x where x->>'doc_number' is not null), 'manager does not see document numbers');

  perform tst.as_user('hro');
  v := public.hr_list_missing_documents('{}');
  -- Ravi (expat): visa missing; Ahmed (expat): resident card, visa, work permit, contract; Omanis: civil ID, contract …
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'employee_id' = tst.id('emp_w')::text and x->>'doc_type' = 'EMPLOYMENT_VISA'), 'missing visa found');
  perform tst.check(not exists (select 1 from jsonb_array_elements(v) x where x->>'employee_id' = tst.id('emp_w')::text and x->>'doc_type' = 'WORK_PERMIT'), 'work permit present');
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'employee_id' = tst.id('emp_om')::text and x->>'doc_type' = 'CIVIL_ID'), 'Omani civil ID missing');
  perform tst.check(not exists (select 1 from jsonb_array_elements(v) x where x->>'employee_id' = tst.id('emp_om')::text and x->>'doc_type' = 'RESIDENT_CARD'), 'resident card not required for Omani');
  v := public.hr_list_employee_documents(tst.id('emp_w'));
  perform tst.check(exists (select 1 from jsonb_array_elements(v->'checklist') c where c->>'doc_type' = 'RESIDENT_CARD' and c->>'status' = 'EXPIRED'), 'checklist shows expired');

  -- notifications: one per item per threshold, never repeated
  n := (public.hr_run_expiry_scan()->>'created')::int;
  perform tst.check(n > 0, 'scan created notifications');
  perform tst.check((public.hr_run_expiry_scan()->>'created')::int = 0, 'second scan creates none');
  perform tst.as_user('emp');
  v := public.hr_list_notifications();
  perform tst.check((v->>'unread')::int >= 4, 'employee notified about own items');
  perform tst.check(exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'priority' = 'HIGH'), 'expired escalates as HIGH');
  v := public.hr_mark_notifications_read(null);
  perform tst.check((v->>'unread')::int = 0, 'mark all read');
  perform tst.as_user('mgr');
  v := public.hr_list_notifications();
  perform tst.check(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'title_en' like 'Medical%'), 'manager not told about medical');
  perform tst.as_user('hro');
  v := public.hr_list_notifications();
  perform tst.check(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'title_en' like 'Medical%'), 'HR officer not told about medical');
end $$;

-- ===========================================================================
-- 8. Omanisation: ratios, targets (maker-checker), exceptions
-- ===========================================================================
do $$
declare v jsonb; t uuid;
begin
  perform tst.as_user('hrm');
  v := public.hr_get_omanisation(tst.id('ent'));
  -- counted: Salim (OM), Ravi (IN), Fatma (OM), Ahmed (EG); trainee excluded → 2 / 4
  perform tst.check((v->'overall'->>'total')::int = 4 and (v->'overall'->>'omani')::int = 2, 'counted population');
  perform tst.check((v->'overall'->>'pct')::numeric = 50.00, 'ratio 50%');
  perform tst.check(v->'overall'->>'target_pct' is null, 'no target until approved');
  perform tst.check(jsonb_array_length(v->'omani_only_placements') = 1, 'expatriate in Omani-only job listed');

  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_propose_omanisation_target(%L)', jsonb_build_object('entity_id', tst.id('ent'),
            'scope_type','ENTITY','target_pct', 60, 'effective_from','2026-01-01','rule_basis','LEGAL')), 'source');
  v := public.hr_propose_omanisation_target(jsonb_build_object('entity_id', tst.id('ent'), 'scope_type','ENTITY',
         'target_pct', 60, 'effective_from','2026-01-01', 'rule_basis','COMPANY_POLICY', 'source_reference','Board resolution TEST-1'));
  t := (v->0->>'id')::uuid;
  perform tst.expect_error(format('select public.hr_decide_omanisation_target(%L, true)', t), 'NOT_ALLOWED');
  perform tst.as_user('hrm');
  perform public.hr_decide_omanisation_target(t, true, 'OK');
  v := public.hr_get_omanisation(tst.id('ent'));
  perform tst.check((v->'overall'->>'target_pct')::numeric = 60 and (v->'overall'->>'omanis_needed')::int = 1
                    and not (v->'overall'->>'meets_target')::boolean, 'target applied: 1 more Omani needed');

  -- HR manager proposes; cannot approve his own
  v := public.hr_propose_omanisation_target(jsonb_build_object('entity_id', tst.id('ent'), 'scope_type','DEPARTMENT',
         'scope_id', tst.id('dep_hr'), 'target_pct', 100, 'effective_from','2026-01-01', 'rule_basis','COMPANY_POLICY',
         'source_reference','HR policy TEST-2'));
  t := (select (x->>'id')::uuid from jsonb_array_elements(v) x where x->>'status' = 'PENDING');
  perform tst.expect_error(format('select public.hr_decide_omanisation_target(%L, true)', t), 'SELF_APPROVAL');
  perform tst.as_user('admin');
  perform public.hr_decide_omanisation_target(t, true, null);
  -- a later entity target closes the earlier one
  perform tst.as_user('hro');
  v := public.hr_propose_omanisation_target(jsonb_build_object('entity_id', tst.id('ent'), 'scope_type','ENTITY',
         'target_pct', 65, 'effective_from', (current_date + 1)::text, 'rule_basis','COMPANY_POLICY', 'source_reference','Board resolution TEST-3'));
  t := (select (x->>'id')::uuid from jsonb_array_elements(v) x where x->>'status' = 'PENDING');
  perform tst.as_user('hrm');
  v := public.hr_decide_omanisation_target(t, true, null);
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'source_reference' = 'Board resolution TEST-1'
                    and (x->>'effective_to')::date = current_date), 'earlier target closed the day before');
  v := public.hr_get_omanisation(tst.id('ent'));
  perform tst.check((v->'overall'->>'target_pct')::numeric = 60, 'today still uses 60%');
  perform tst.check(exists (select 1 from jsonb_array_elements(v->'by_department') d where d->>'code' = 'HR'
                    and (d->>'target_pct')::numeric = 100 and (d->>'omanis_needed')::int = 1), 'department target');

  perform tst.as_user('fin');
  perform tst.check(public.hr_dashboard() ? 'compliance', 'finance sees compliance on dashboard');
  perform tst.check((public.hr_dashboard()->'workforce'->>'headcount')::int = 5, 'headcount 5');
  perform tst.as_user('emp');
  v := public.hr_dashboard();
  perform tst.check(not (v ? 'workforce') and v ? 'me', 'employee dashboard is personal only');
end $$;

-- ===========================================================================
-- 9. Lifecycle: confirm, notice, separate, rehire
-- ===========================================================================
do $$
declare v jsonb;
begin
  perform tst.as_user('hro');
  v := public.hr_change_status(tst.id('emp_w'), jsonb_build_object('action','CONFIRM','date', current_date::text));
  perform tst.check(v->'employee'->>'status' = 'ACTIVE', 'confirmed');
  perform tst.expect_error(format('select public.hr_change_status(%L, %L)', tst.id('emp_w'), '{"action":"CONFIRM"}'), 'probation');
  v := public.hr_change_status(tst.id('emp_trn'), jsonb_build_object('action','NOTICE','date', current_date::text,
         'last_working_date', (current_date + 30)::text, 'separation_type','RESIGNATION'));
  perform tst.check(v->'employee'->>'status' = 'NOTICE', 'notice');
  v := public.hr_change_status(tst.id('emp_trn'), jsonb_build_object('action','SEPARATE','date', current_date::text));
  perform tst.check(v->'employee'->>'status' = 'SEPARATED' and v->'current_assignment'->>'effective_to' = current_date::text, 'separated, assignment closed');
  perform tst.expect_error(format('select public.hr_add_assignment(%L, %L)', tst.id('emp_trn'), '{"reason":"TRANSFER","effective_from":"2030-01-01"}'), 'has left');
  perform tst.expect_error(format('select public.hr_change_status(%L, %L)', tst.id('emp_trn'),
            jsonb_build_object('action','REHIRE','date', current_date::text)), 'after the leaving date');
  v := public.hr_change_status(tst.id('emp_trn'), jsonb_build_object('action','REHIRE','date', (current_date + 1)::text,
         'assignment', jsonb_build_object('department_id', tst.id('dep_prod'), 'job_title_id', tst.id('job_op'), 'category_id', tst.id('cat_staff'))));
  perform tst.check(v->'employee'->>'status' = 'ACTIVE' and v->'employee'->>'original_join_date' = '2025-09-01'
                    and jsonb_array_length(v->'assignments') = 2, 'rehired, history kept');
  perform tst.check(exists (select 1 from jsonb_array_elements(v->'events') x where x->>'event_type' = 'REHIRE'), 'rehire event');
  -- separating the employee with the exception revokes it
  perform tst.as_user('hrm');
  v := public.hr_change_status(tst.id('emp_exc'), jsonb_build_object('action','SEPARATE','date', current_date::text, 'separation_type','END_OF_CONTRACT'));
  perform tst.check(v->'omanisation_exceptions'->0->>'status' = 'REVOKED', 'exception revoked on separation');
end $$;

-- ===========================================================================
-- 10. Audit trail and access log
-- ===========================================================================
do $$
declare v jsonb;
begin
  perform tst.as_user('aud');
  v := public.hr_list_audit(jsonb_build_object('employee_id', tst.id('emp_w')));
  perform tst.check((v->>'total')::int > 5, 'audit rows for employee');
  perform tst.check(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'user_id' is null), 'every change has a user');
  perform tst.check(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'table_name' = 'employee_bank_accounts'),
                    'auditor without bank permission does not see bank audit');
  v := public.hr_list_access_log(jsonb_build_object('employee_id', tst.id('emp_w')));
  perform tst.check(exists (select 1 from jsonb_array_elements(v) r where r->>'data_kind' = 'SALARY'), 'salary views logged');
  perform tst.check(exists (select 1 from jsonb_array_elements(v) r where r->>'data_kind' = 'SENSITIVE_DOCUMENT'), 'sensitive file access logged');
  perform tst.as_user('hro');
  perform tst.expect_error('select public.hr_list_audit()', 'NOT_ALLOWED');
  perform tst.as_user('admin');
  v := public.hr_list_audit('{"table_name":"employee_bank_accounts"}');
  perform tst.check(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->'new_data'->>'account_number' like '0301%'),
                    'bank numbers masked in audit');
end $$;

reset role;
select 'ALL PRIORITY 1 TESTS PASSED' as result;
