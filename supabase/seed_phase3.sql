-- AACT HRMS — Phase 3 dummy data (payroll). DUMMY DATA ONLY: never run on the company server.
-- Runs after seed.sql and seed_phase2.sql. Uses the real API as the demo users, so the three-person chain is respected:
-- HR officer calculates, HR manager verifies, Finance approves. Contains no DROP statements. Stops if payroll runs exist.

do $p3$
declare
  hrm uuid; hro uuid; fin uuid; v_fail int := 0; ent record; e record; r jsonb; v_run uuid;
  v_today date := (now() at time zone 'Asia/Muscat')::date;
  v_m0 date := date_trunc('month', (now() at time zone 'Asia/Muscat')::date)::date;
  v_prev date; v_prev2 date; v_id uuid; n int := 0;
begin
  if exists (select 1 from hr.payroll_runs) then raise notice 'Phase 3 dummy data: payroll runs already exist — nothing done.'; return; end if;
  if not exists (select 1 from hr.shifts) then raise notice 'Phase 3 dummy data: load seed_phase2.sql first.'; return; end if;
  select id into hrm from auth.users where email = 'hr.manager@aact.test';
  select id into hro from auth.users where email = 'hr.officer@aact.test';
  select id into fin from auth.users where email = 'finance@aact.test';
  if hrm is null or hro is null or fin is null then raise notice 'Phase 3 dummy data: demo logins missing — nothing done.'; return; end if;
  v_prev := (v_m0 - interval '1 month')::date;
  v_prev2 := (v_m0 - interval '2 months')::date;

  -- 1. set-up (dummy employer numbers) — Finance
  perform set_config('request.jwt.claim.sub', fin::text, false);
  begin
    perform public.hr_save_payroll_setup(jsonb_build_object(
      'entities', (select jsonb_agg(jsonb_build_object('id', le.id, 'cr_number', coalesce(le.cr_number, '1000' || lpad(le.rn::text, 3, '0')),
                     'spf_employer_no', 'SPF-DEMO-' || le.code, 'wps_bank_code', 'BMCT', 'wps_account', '0301' || lpad(le.rn::text, 9, '0'),
                     'wps_payer_cr', null)) from (select x.*, row_number() over (order by x.code) as rn from hr.legal_entities x) le),
      'components', (select jsonb_agg(jsonb_build_object('code', c.code, 'gl_account', case c.code when 'BASIC' then '5101' when 'HOUSING' then '5102'
                       when 'TRANSPORT' then '5103' when 'FIXED_DED' then '4901' else '5109' end, 'spf_base', true)) from hr.pay_components c)));
  exception when others then raise notice 'setup: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 2. loans and advances: two approved (deducted from two months ago), one waiting
  for e in select emp.id, emp.employee_no, row_number() over (order by md5('loan' || emp.employee_no)) as rn from hr.employees emp
           where emp.status = 'ACTIVE' and emp.nationality <> 'OM' and exists (select 1 from hr.compensation_revisions c where c.employee_id = emp.id and c.status = 'APPROVED')
           order by md5('loan' || emp.employee_no) limit 3 loop
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      r := public.hr_propose_loan(jsonb_build_object('employee_id', e.id, 'kind', case when e.rn = 2 then 'ADVANCE' else 'LOAN' end,
             'amount', case e.rn when 1 then '600' when 2 then '150' else '400' end, 'installment', case e.rn when 1 then '100' when 2 then '150' else '80' end,
             'first_month', to_char(case when e.rn = 3 then v_m0 else v_prev2 end, 'YYYY-MM'),
             'reason', case e.rn when 1 then 'Family wedding (demo)' when 2 then 'Rent deposit (demo)' else 'Car repair (demo)' end));
      if e.rn < 3 then
        perform set_config('request.jwt.claim.sub', fin::text, false);
        perform public.hr_decide_loan((r->>'id')::uuid, true, 'Within policy (demo)');
      end if;
    exception when others then raise notice 'loan %: %', e.employee_no, sqlerrm; v_fail := v_fail + 1; end;
  end loop;

  -- 3. one-off items: approved bonus and commission for last month; a penalty waiting for this month
  perform set_config('request.jwt.claim.sub', hro::text, false);
  begin
    r := public.hr_propose_pay_adjustments(jsonb_build_object('rows', (
      select jsonb_agg(x) from (
        select jsonb_build_object('employee_id', emp.id, 'month', to_char(v_prev, 'YYYY-MM'), 'code', 'BONUS', 'amount', '75', 'reason', 'Safety award (demo)') x
        from hr.employees emp where emp.status = 'ACTIVE' order by md5('bonus' || emp.employee_no) limit 4) t)));
    r := public.hr_propose_pay_adjustments(jsonb_build_object('rows', jsonb_build_array(
      jsonb_build_object('employee_no', (select employee_no from hr.employees e2 join hr.employee_assignments a on a.employee_id = e2.id and a.effective_to is null
                                         join hr.departments d on d.id = a.department_id where d.code = 'SALES' and e2.status = 'ACTIVE' order by e2.employee_no limit 1),
                         'month', to_char(v_prev, 'YYYY-MM'), 'code', 'COMMISSION', 'amount', '220.500', 'reason', 'Quarterly sales commission (demo)'))));
    perform set_config('request.jwt.claim.sub', fin::text, false);
    perform public.hr_decide_pay_adjustments(array(select id from hr.payroll_adjustments where status = 'PENDING'), true, 'OK (demo)');
    perform set_config('request.jwt.claim.sub', hro::text, false);
    r := public.hr_propose_pay_adjustments(jsonb_build_object('rows', (
      select jsonb_agg(jsonb_build_object('employee_id', emp.id, 'month', to_char(v_m0, 'YYYY-MM'), 'code', 'PENALTY', 'amount', '20',
                                          'reason', 'Late three times (demo)'))
      from (select id from hr.employees where status = 'ACTIVE' order by md5('pen' || employee_no) limit 1) emp)));
  exception when others then raise notice 'items: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 4. lock the month before last (attendance) and run two payroll months
  for ent in select id, code from hr.legal_entities loop
    perform set_config('request.jwt.claim.sub', hrm::text, false);
    begin
      if not hr.attendance_locked(ent.id, v_prev2) then perform public.hr_lock_period(ent.id, to_char(v_prev2, 'YYYY-MM')); end if;
    exception when others then raise notice 'lock %: %', ent.code, sqlerrm; v_fail := v_fail + 1; end;
    -- month before last: calculated → verified → approved → paid
    begin
      perform set_config('request.jwt.claim.sub', hro::text, false);
      r := public.hr_create_payroll_run(ent.id, to_char(v_prev2, 'YYYY-MM'), null); v_run := (r->>'id')::uuid;
      perform public.hr_calculate_payroll(v_run);
      perform set_config('request.jwt.claim.sub', hrm::text, false);
      perform public.hr_verify_payroll(v_run, 'Checked against attendance summary (demo)');
      perform set_config('request.jwt.claim.sub', fin::text, false);
      perform public.hr_approve_payroll(v_run, 'Approved (demo)');
      perform public.hr_mark_payroll_paid(v_run);
    exception when others then raise notice 'run % %: %', ent.code, to_char(v_prev2, 'YYYY-MM'), sqlerrm; v_fail := v_fail + 1; end;
    -- last month: calculated → verified → approved (bank file ready, not yet paid)
    begin
      perform set_config('request.jwt.claim.sub', hro::text, false);
      r := public.hr_create_payroll_run(ent.id, to_char(v_prev, 'YYYY-MM'), null); v_run := (r->>'id')::uuid;
      perform public.hr_calculate_payroll(v_run);
      perform set_config('request.jwt.claim.sub', hrm::text, false);
      perform public.hr_verify_payroll(v_run, 'Checked (demo)');
      perform set_config('request.jwt.claim.sub', fin::text, false);
      perform public.hr_approve_payroll(v_run, 'Approved (demo)');
      -- parallel run: "current payroll" figures equal to ours except two differences
      perform set_config('request.jwt.claim.sub', hro::text, false);
      perform public.hr_save_parallel(v_run, jsonb_build_object('replace', true, 'rows', (
        select jsonb_agg(jsonb_build_object('employee_no', s.employee_no,
                 'net', (s.net + case when s.rn in (3, 11) then 12.5 else 0 end)::text,
                 'note', case when s.rn in (3, 11) then 'Old system rounds overtime (demo)' end))
        from (select p.*, row_number() over (order by p.employee_no) as rn from hr.payslips p where p.run_id = v_run) s)));
    exception when others then raise notice 'run % %: %', ent.code, to_char(v_prev, 'YYYY-MM'), sqlerrm; v_fail := v_fail + 1; end;
  end loop;

  -- 5. a final settlement waiting for approval for the employee serving notice
  for e in select emp.id, emp.employee_no, emp.last_working_date from hr.employees emp where emp.status = 'NOTICE' limit 1 loop
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      perform public.hr_save_settlement(jsonb_build_object('employee_id', e.id, 'last_working_date', coalesce(e.last_working_date, v_today + 30)::text,
        'reason', 'RESIGNATION', 'notice_days', 0, 'note', 'Resignation accepted; notice served in full (demo)',
        'other', jsonb_build_array(jsonb_build_object('label', 'Air ticket in cash (demo)', 'kind', 'EARNING', 'amount', '180'))));
    exception when others then raise notice 'settlement %: %', e.employee_no, sqlerrm; v_fail := v_fail + 1; end;
  end loop;

  perform set_config('request.jwt.claim.sub', '', false);
  raise notice 'Phase 3 dummy data loaded: % runs, % payslips, % loans, % one-off items, % settlements, % steps skipped.',
    (select count(*) from hr.payroll_runs), (select count(*) from hr.payslips), (select count(*) from hr.employee_loans),
    (select count(*) from hr.payroll_adjustments), (select count(*) from hr.final_settlements), v_fail;
end
$p3$;
