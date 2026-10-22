-- AACT HRMS — 1.9.0 management (MG) pay confidentiality: database tests.
-- Runs after 10–70. Builds its own company "MGT" with one management (MG) and one non-management (NMG) employee.

set client_min_messages = warning;
reset role;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
insert into tst.ids values
 ('user_mg1', '00000000-0000-0000-0000-00000000b001'), ('user_mg2', '00000000-0000-0000-0000-00000000b002'),
 ('user_mg3', '00000000-0000-0000-0000-00000000b003')
on conflict do nothing;
insert into auth.users(id, email)
select v, substr(k, 6) || '@aact.test' from tst.ids where k in ('user_mg1','user_mg2','user_mg3') on conflict do nothing;

do $$
declare v_ent uuid; m1 uuid; n1 uuid; r uuid; hro uuid := tst.id('user_hro'); hrm uuid := tst.id('user_hrm');
begin
  insert into hr.legal_entities(code, name_en, cr_number, wps_bank_code, wps_account)
  values ('MGT', 'MG Test LLC', '7654321', 'BMCT', '0301000000009') returning id into v_ent;
  perform tst.put('ment', v_ent);
  insert into hr.employees(entity_id, employee_no, full_name_en, nationality, gender, original_join_date, join_date, status)
  values (v_ent, 'MGT-001', 'General Manager', 'GB', 'M', '2018-01-01', '2018-01-01', 'ACTIVE') returning id into m1;
  insert into hr.employees(entity_id, employee_no, full_name_en, nationality, gender, original_join_date, join_date, status)
  values (v_ent, 'MGT-002', 'Line Worker', 'IN', 'M', '2021-01-01', '2021-01-01', 'ACTIVE') returning id into n1;
  perform tst.put('m1', m1); perform tst.put('n1', n1);
  insert into hr.compensation_revisions(employee_id, effective_from, reason, status, total_monthly, proposed_by, decided_by, decided_at)
  values (m1, '2018-01-01', 'JOIN', 'APPROVED', 6000, hro, hrm, now()) returning id into r;
  insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (r, m1, 'BASIC', 5000), (r, m1, 'HOUSING', 1000);
  insert into hr.compensation_revisions(employee_id, effective_from, reason, status, total_monthly, proposed_by, decided_by, decided_at)
  values (n1, '2021-01-01', 'JOIN', 'APPROVED', 400, hro, hrm, now()) returning id into r;
  insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (r, n1, 'BASIC', 300), (r, n1, 'HOUSING', 100);
  insert into hr.employee_bank_accounts(employee_id, bank_name, account_name, account_number, swift_code, effective_from, status, requested_by, decided_by, decided_at)
  values (m1, 'Bank Muscat', 'General Manager', '0301000000901', 'BMUSOMRX', '2018-01-01', 'APPROVED', hro, tst.id('user_fin'), now()),
         (n1, 'Bank Muscat', 'Line Worker', '0301000000902', 'BMUSOMRX', '2021-01-01', 'APPROVED', hro, tst.id('user_fin'), now());
  insert into hr.attendance_periods(entity_id, period_start, status, locked_by, locked_at) values (v_ent, '2026-07-01', 'LOCKED', hrm, now());
end $$;
grant execute on all functions in schema tst to authenticated;

-- ===========================================================================
-- 1. The permission belongs only to the Management payroll role; the team manages its own members
-- ===========================================================================
do $$
declare v jsonb;
begin
  perform tst.check(not exists (select 1 from hr.role_permissions where role_code = 'SUPER_ADMIN' and perm_code = 'MG_PAY'), 'super administrator does not get MG_PAY');
  insert into hr.role_permissions(role_code, perm_code) values ('HR_MANAGER', 'MG_PAY') on conflict do nothing;
  perform tst.check(not exists (select 1 from hr.role_permissions where perm_code = 'MG_PAY' and role_code <> 'MG_PAYROLL'), 'MG_PAY cannot be added to another role');

  perform tst.as_user('admin');
  perform public.hr_set_user_roles(tst.id('user_mg1'), array['MG_PAYROLL']);
  perform tst.check(exists (select 1 from hr.user_roles where user_id = tst.id('user_mg1') and role_code = 'MG_PAYROLL' and revoked_at is null), 'first member given by the administrator');
  perform tst.expect_error('select public.hr_set_user_roles(tst.id(''user_mg2''), array[''MG_PAYROLL''])', 'MG_ONLY');
  perform tst.expect_error('select public.hr_set_user_roles(tst.id(''user_mg1''), array[''EMPLOYEE''])', 'MG_ONLY');
  perform public.hr_set_user_roles(tst.id('user_mg1'), array['MG_PAYROLL','EMPLOYEE']);
  perform tst.check(exists (select 1 from hr.user_roles where user_id = tst.id('user_mg1') and role_code = 'EMPLOYEE' and revoked_at is null), 'other roles still managed on the Users page');
  perform tst.expect_error('select public.hr_list_mg_access()', 'NOT_ALLOWED|permission');

  perform tst.as_user('mg1');
  perform tst.expect_error('select public.hr_set_mg_access(tst.id(''user_mg1''), false)', 'own access');
  v := public.hr_set_mg_access(tst.id('user_mg2'), true);
  v := public.hr_set_mg_access(tst.id('user_mg3'), true);
  perform tst.check((select count(*) from jsonb_array_elements(v) x where (x->>'member')::boolean) = 3, 'team of three');
  perform tst.check(exists (select 1 from hr.notifications where user_id = tst.id('user_mg2') and ref_key like 'MGACC:' || tst.id('user_mg3') || ':%'), 'team told about a new member');
  perform tst.check(not exists (select 1 from hr.notifications where user_id = tst.id('user_admin') and ref_key like 'MGACC:%'), 'others are not told');
end $$;

-- ===========================================================================
-- 2. Pay group: only the team moves people; HR then loses every money item of that employee
-- ===========================================================================
do $$
declare v jsonb; m1 uuid := tst.id('m1'); n1 uuid := tst.id('n1');
begin
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_set_pay_group(%L, ''MG'', ''Senior management'')', m1), 'NOT_ALLOWED|permission');
  perform tst.as_user('mg1');
  perform tst.expect_error(format('select public.hr_set_pay_group(%L, ''MG'', ''x'')', m1), 'at least 5');
  perform tst.expect_error(format('select public.hr_set_pay_group(%L, ''XX'', ''Senior management'')', m1), 'Choose management');
  v := public.hr_set_pay_group(m1, 'MG', 'General manager — management contract');
  perform tst.check(v->'employee'->>'pay_group' = 'MG' and (v->'caps'->>'salary_read')::boolean, 'moved to MG; team still sees pay');
  perform tst.expect_error(format('select public.hr_set_pay_group(%L, ''MG'', ''Senior management'')', m1), 'already in this pay group');

  perform tst.as_user('hrm');
  v := public.hr_get_employee(m1);
  perform tst.check(v->'employee'->>'full_name_en' = 'General Manager' and not (v->'caps'->>'salary_read')::boolean
                    and not (v->'caps'->>'bank_read')::boolean and (v->'caps'->>'pay_restricted')::boolean, 'HR keeps the record but not pay or bank');
  v := public.hr_get_employee(n1);
  perform tst.check((v->'caps'->>'salary_read')::boolean and not (v->'caps'->>'pay_restricted')::boolean, 'NMG employee unchanged for HR');
  perform tst.check(public.hr_get_compensation(n1)->'current' is not null, 'HR still sees NMG salary');
  perform tst.expect_error(format('select public.hr_get_compensation(%L)', m1), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_get_bank(%L)', m1), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_employee_payroll(%L)', m1), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_propose_compensation(%L, %L)', m1,
    jsonb_build_object('effective_from', '2026-08-01', 'reason', 'INCREMENT', 'lines', jsonb_build_array(jsonb_build_object('component_code', 'BASIC', 'amount', 5500)))), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_request_bank_change(%L, %L)', m1,
    jsonb_build_object('bank_name', 'Bank Dhofar', 'account_name', 'GM', 'account_number', '0301999999')), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_propose_loan(%L)', jsonb_build_object('employee_id', m1, 'amount', 1000, 'installment', 100, 'first_month', '2026-09')), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_save_settlement(%L)', jsonb_build_object('employee_id', m1, 'last_working_date', '2026-10-31')), 'MG_ONLY');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_gratuity_report(tst.id('ment'))->'rows') x where (x->>'employee_id')::uuid = m1)
                    and exists (select 1 from jsonb_array_elements(public.hr_gratuity_report(tst.id('ment'))->'rows') x where (x->>'employee_id')::uuid = n1),
                    'gratuity report shows NMG only');
  v := public.hr_mol_report(tst.id('ment'));
  perform tst.check((select x->>'basic' from jsonb_array_elements(v->'employees') x where (x->>'employee_id')::uuid = m1) is null, 'no MG basic salary on the localisation report');
  v := public.hr_exec_dashboard(tst.id('ment'));
  perform tst.check((v->'risks'->>'gratuity_liability')::numeric = round((hr.gratuity_calc(n1, hr.today(), 300)->>'total')::numeric, 3),
                    'HR''s liability figure is the NMG employee''s gratuity only');

  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_request_letter(%L)', jsonb_build_object('employee_id', m1, 'letter_type', 'SALARY_CERT', 'language', 'EN')), 'MG_ONLY');
  v := public.hr_request_letter(jsonb_build_object('employee_id', m1, 'letter_type', 'NOC', 'language', 'EN', 'details', jsonb_build_object('destination', 'India')));
  perform tst.check(v->>'status' = 'REQUESTED', 'letters without salary still handled by HR');
  v := public.hr_propose_pay_adjustments(jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('employee_id', m1, 'month', '2026-09', 'code', 'BONUS', 'amount', 500, 'reason', 'Annual bonus'),
         jsonb_build_object('employee_id', n1, 'month', '2026-09', 'code', 'BONUS', 'amount', 50, 'reason', 'Safety award'))));
  perform tst.check((v->>'proposed')::int = 1 and v->'errors'->0->>'message' like '%management (MG)%', 'HR cannot add an MG pay item; NMG row accepted');
end $$;

-- ===========================================================================
-- 3. Money items created by the team stay inside the team
-- ===========================================================================
do $$
declare v jsonb; m1 uuid := tst.id('m1'); v_rev uuid; v_loan uuid;
begin
  perform tst.as_user('mg1');
  v := public.hr_propose_compensation(m1, jsonb_build_object('effective_from', '2026-08-01', 'reason', 'INCREMENT',
         'lines', jsonb_build_array(jsonb_build_object('component_code', 'BASIC', 'amount', 5500), jsonb_build_object('component_code', 'HOUSING', 'amount', 1000))));
  v_rev := (v->>'revision_id')::uuid;
  perform tst.check(exists (select 1 from hr.notifications where ref_key = 'SAL:' || v_rev and user_id = tst.id('user_mg2')), 'team approver notified');
  perform tst.check(not exists (select 1 from hr.notifications where ref_key = 'SAL:' || v_rev and user_id = tst.id('user_hrm')), 'HR approver not notified');
  v := public.hr_propose_loan(jsonb_build_object('employee_id', m1, 'amount', 1200, 'installment', 200, 'first_month', '2026-09', 'reason', 'Car'));
  v_loan := (v->>'id')::uuid;
  perform tst.check(not exists (select 1 from hr.notifications where ref_key = 'loan:' || v_loan and user_id = tst.id('user_fin')), 'loan with amount not sent to normal Finance');

  perform tst.as_user('hrm');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_list_pending_approvals()->'salary') x where (x->>'id')::uuid = v_rev), 'HR approvals list hides the MG revision');
  perform tst.check((public.hr_dashboard()->'approvals'->>'salary')::int = 0 or not exists (select 1 from hr.compensation_revisions r where r.id = v_rev and hr.money_ok(r.employee_id)),
                    'HR dashboard count excludes MG revision');
  perform tst.expect_error(format('select public.hr_decide_compensation(%L, true)', v_rev), 'MG_ONLY');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_list_loans('{}'::jsonb)) x where (x->>'id')::uuid = v_loan), 'HR loan list hides MG loans');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_list_pay_adjustments('{}'::jsonb)) x where (x->>'employee_id')::uuid = m1), 'HR pay item list hides MG items');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'loans') = 0 or not exists (select 1 from jsonb_array_elements(public.hr_list_my_tasks()->'loans') x where (x->>'id')::uuid = v_loan), 'no MG loan task for HR');

  perform tst.as_user('mg2');
  v := public.hr_decide_compensation(v_rev, true);
  perform tst.check(v->'scheduled'->0->>'id' = v_rev::text or v->'current'->>'id' = v_rev::text, 'approved inside the team');
  v := public.hr_decide_loan(v_loan, true);
  perform tst.check(v->>'status' = 'APPROVED', 'loan approved inside the team');

  perform tst.as_user('aud');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_list_audit(jsonb_build_object('employee_id', m1, 'limit', 500))->'rows') x
                                where x->>'table_name' in ('compensation_revisions','compensation_lines','employee_loans','employee_bank_accounts')),
                    'audit trail hides MG money rows from the auditor');
  perform tst.check(exists (select 1 from jsonb_array_elements(public.hr_list_audit(jsonb_build_object('employee_id', m1, 'limit', 500))->'rows') x
                            where x->>'table_name' = 'employees'), 'non-money changes of the MG employee stay visible');
end $$;

-- ===========================================================================
-- 4. Separate MG payroll run with its own approval chain
-- ===========================================================================
do $$
declare v jsonb; v_n uuid; v_m uuid; v_slip uuid;
begin
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_create_payroll_run(%L, ''2026-07'', null, ''MG'')', tst.id('ment')), 'MG_ONLY');
  v := public.hr_create_payroll_run(tst.id('ment'), '2026-07');
  v_n := (v->>'id')::uuid;
  perform tst.check(v->>'pay_group' = 'NMG', 'normal run is NMG');
  v := public.hr_calculate_payroll(v_n);
  perform tst.check((v->'totals'->>'employees')::int = 1, 'NMG run pays only the NMG employee');
  perform tst.check(not exists (select 1 from hr.payslips where run_id = v_n and employee_id = tst.id('m1')), 'no MG payslip in the NMG run');

  perform tst.as_user('mg1');
  perform tst.expect_error(format('select public.hr_set_pay_group(%L, ''MG'', ''Promoted to management'')', tst.id('n1')), 'PAYROLL_OPEN');
  v := public.hr_create_payroll_run(tst.id('ment'), '2026-07', null, 'MG');
  v_m := (v->>'id')::uuid;
  perform tst.expect_error(format('select public.hr_create_payroll_run(%L, ''2026-07'', null, ''MG'')', tst.id('ment')), 'DUPLICATE');
  v := public.hr_calculate_payroll(v_m);
  perform tst.check((v->'totals'->>'employees')::int = 1 and (v->'totals'->>'earnings')::numeric = 6000, 'MG run pays only the MG employee (6,000)');
  select id into v_slip from hr.payslips where run_id = v_m;

  perform tst.as_user('hrm');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_list_payroll_runs(tst.id('ment'), null)) x where (x->>'id')::uuid = v_m)
                    and exists (select 1 from jsonb_array_elements(public.hr_list_payroll_runs(tst.id('ment'), null)) x where (x->>'id')::uuid = v_n),
                    'HR sees the NMG run only');
  perform tst.expect_error(format('select public.hr_get_payroll_run(%L)', v_m), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_get_payslip(%L)', v_slip), 'NOT_ALLOWED');
  perform tst.expect_error(format('select public.hr_payroll_export(%L, ''REGISTER'')', v_m), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_spf_report(%L)', v_m), 'MG_ONLY');
  perform tst.expect_error(format('select public.hr_verify_payroll(%L)', v_m), 'MG_ONLY');

  perform tst.as_user('mg1');
  perform tst.expect_error(format('select public.hr_verify_payroll(%L)', v_m), 'SELF_APPROVAL');
  perform tst.as_user('mg2');
  v := public.hr_verify_payroll(v_m);
  perform tst.check(exists (select 1 from hr.notifications where ref_key like 'payroll-approve:' || v_m || ':%' and user_id = tst.id('user_mg3'))
                    and not exists (select 1 from hr.notifications where ref_key like 'payroll-approve:' || v_m || ':%' and user_id = tst.id('user_fin')),
                    'MG approval request goes to the team only');
  perform tst.as_user('mg3');
  v := public.hr_approve_payroll(v_m);
  perform tst.check(v->>'status' = 'APPROVED', 'MG run approved by a third team member');
  v := public.hr_payroll_export(v_m, 'WPS');
  perform tst.check(jsonb_array_length(v->'rows') = 1, 'separate bank file for MG');
end $$;

do $$
declare f record; n int := 0;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.proname in ('hr_set_pay_group','hr_list_mg_access','hr_set_mg_access','hr_create_payroll_run') loop
    perform tst.check(has_function_privilege('authenticated', f.sig, 'execute') and not has_function_privilege('anon', f.sig, 'execute'), 'grants for ' || f.sig);
    n := n + 1;
  end loop;
  perform tst.check(n = 4, 'MG API functions exist once each: ' || n);
end $$;

select 'ALL MG PAY TESTS PASSED' as result;
