-- AACT HRMS — Phase 3 (payroll & end of service) database tests.
-- Runs after 10_priority1.sql and 20_phase2.sql (uses their users). Builds its own company "PAYT" with three employees
-- so every expected figure can be worked out by hand. Every business call goes through the public API as "authenticated".

set client_min_messages = warning;
reset role;

-- ---------------------------------------------------------------------------
-- Fixture (as the platform / earlier phases would have left it)
-- ---------------------------------------------------------------------------
do $$
declare v_ent uuid; e1 uuid; e2 uuid; e3 uuid; e4 uuid; r uuid; hro uuid := tst.id('user_hro'); hrm uuid := tst.id('user_hrm');
begin
  insert into hr.legal_entities(code, name_en, name_ar, cr_number, wps_bank_code, wps_account)
  values ('PAYT', 'Payroll Test LLC', 'شركة اختبار الرواتب', '1234567', 'BMCT', '0301000000001') returning id into v_ent;
  perform tst.put('pent', v_ent);
  insert into hr.employees(entity_id, employee_no, full_name_en, nationality, gender, original_join_date, join_date, status, civil_number)
  values (v_ent, 'PAYT-001', 'Omani High Earner', 'OM', 'M', '2015-01-01', '2015-01-01', 'ACTIVE', '90000001') returning id into e1;
  insert into hr.employees(entity_id, employee_no, full_name_en, nationality, gender, original_join_date, join_date, status, civil_number)
  values (v_ent, 'PAYT-002', 'Expat Worker', 'IN', 'M', '2020-08-01', '2020-08-01', 'ACTIVE', '90000002') returning id into e2;
  insert into hr.employees(entity_id, employee_no, full_name_en, nationality, gender, original_join_date, join_date, status)
  values (v_ent, 'PAYT-003', 'Mid-month Joiner', 'PK', 'M', '2026-09-16', '2026-09-16', 'PROBATION') returning id into e3;
  insert into hr.employees(entity_id, employee_no, full_name_en, nationality, gender, original_join_date, join_date, status)
  values (v_ent, 'PAYT-004', 'Omani Old Timer', 'OM', 'M', '2010-01-01', '2010-01-01', 'ACTIVE') returning id into e4;
  perform tst.put('p1', e1); perform tst.put('p2', e2); perform tst.put('p3', e3); perform tst.put('p4', e4);
  -- approved salary structures
  insert into hr.compensation_revisions(id, employee_id, effective_from, reason, status, total_monthly, proposed_by, decided_by, decided_at)
  values (gen_random_uuid(), tst.id('p1'), '2015-01-01', 'JOIN', 'APPROVED', 5000, hro, hrm, now()) returning id into r;
  insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (r, tst.id('p1'), 'BASIC', 4000), (r, tst.id('p1'), 'HOUSING', 1000);
  insert into hr.compensation_revisions(employee_id, effective_from, reason, status, total_monthly, proposed_by, decided_by, decided_at)
  values (e2, '2020-08-01', 'JOIN', 'APPROVED', 450, hro, hrm, now()) returning id into r;
  insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (r, e2, 'BASIC', 300), (r, e2, 'HOUSING', 100), (r, e2, 'TRANSPORT', 50);
  insert into hr.compensation_revisions(employee_id, effective_from, reason, status, total_monthly, proposed_by, decided_by, decided_at)
  values (e3, '2026-09-16', 'JOIN', 'APPROVED', 300, hro, hrm, now()) returning id into r;
  insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (r, e3, 'BASIC', 300);
  -- e4: salary changes on 16 Sep (600 → 900); September is split
  insert into hr.compensation_revisions(employee_id, effective_from, reason, status, total_monthly, proposed_by, decided_by, decided_at)
  values (e4, '2010-01-01', 'JOIN', 'SUPERSEDED', 600, hro, hrm, now() - interval '1 day') returning id into r;
  insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (r, e4, 'BASIC', 600);
  insert into hr.compensation_revisions(employee_id, effective_from, reason, status, total_monthly, proposed_by, decided_by, decided_at)
  values (e4, '2026-09-16', 'INCREMENT', 'APPROVED', 900, hro, hrm, now()) returning id into r;
  insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (r, e4, 'BASIC', 900);
  -- bank accounts (e3 has none)
  insert into hr.employee_bank_accounts(employee_id, bank_name, account_name, account_number, iban, swift_code, effective_from, status, requested_by, decided_by, decided_at)
  values (tst.id('p1'), 'Bank Muscat', 'Omani High Earner', '0301000000111', 'OM000000000000000111', 'BMUSOMRX', '2015-01-01', 'APPROVED', hro, tst.id('user_fin'), now()),
         (e2, 'Bank Dhofar', 'Expat Worker', '0301000000222', 'OM000000000000000222', 'BDOFOMRU', '2020-08-01', 'APPROVED', hro, tst.id('user_fin'), now()),
         (e4, 'Bank Muscat', 'Omani Old Timer', '0301000000444', null, 'BMUSOMRX', '2010-01-01', 'APPROVED', hro, tst.id('user_fin'), now());
  -- September attendance for e2: two absences; sick leave 20 Aug – 13 Sep (25 days: days 22–25 = 10–13 Sep at 75 %)
  insert into hr.attendance_days(employee_id, work_date, status) values (e2, '2026-09-01', 'ABSENT'), (e2, '2026-09-02', 'ABSENT'), (e2, '2026-09-03', 'PRESENT');
  insert into hr.leave_requests(employee_id, leave_type, start_date, end_date, days, status, pay_breakdown, requested_by, decided_by, decided_at)
  values (e2, 'SICK', '2026-08-20', '2026-09-13', 25, 'APPROVED',
          hr.tier_breakdown((select pay_tiers from hr.leave_types where code = 'SICK'), 0, 25), hro, hrm, now());
  -- approved overtime: 2 h on a working day with consent → 2.5 pay hours
  insert into hr.overtime_requests(employee_id, work_date, start_at, end_at, minutes, day_kind, basis, employee_consent, comp_choice,
                                   pay_hours, reason, status, requested_by, decided_by, decided_at)
  values (e2, '2026-09-03', '2026-09-03 17:00+04', '2026-09-03 19:00+04', 120, 'WORKDAY', 'CONSENT', true, 'PAY', 2.5, 'Test overtime', 'APPROVED', hro, hrm, now());
  -- September attendance is locked; October is open
  insert into hr.attendance_periods(entity_id, period_start, status, locked_by, locked_at) values (v_ent, '2026-09-01', 'LOCKED', hrm, now());
end $$;
grant execute on all functions in schema tst to authenticated;

set role authenticated;

-- ===========================================================================
-- 1. Pure rules: gratuity split at 31 Jul 2023, sick tiers, SPF rule lookup
-- ===========================================================================
reset role;
do $$
declare g jsonb;
begin
  g := hr.gratuity_calc(tst.id('p2'), '2025-07-31', 300);
  perform tst.check((g->>'old_amount')::numeric = 450.000, 'old rule: 3 years × 15 days × 10 = 450 (got ' || (g->>'old_amount') || ')');
  perform tst.check((g->>'new_amount')::numeric between 600 and 601, 'new rule: ~2 years × one month (got ' || (g->>'new_amount') || ')');
  perform tst.check(not (hr.gratuity_calc(tst.id('p1'), '2025-07-31', 4000)->>'applies')::boolean, 'no gratuity accrual for Omanis (SPF)');
  perform tst.check((hr.gratuity_calc(tst.id('p3'), '2026-12-31', 300)->>'below_minimum')::boolean, 'below the minimum service: nothing due');
  perform tst.check(hr.tiered_unpaid_days(tst.id('p2'), '2026-09-01', '2026-09-30') = 1.00, 'sick days 22–25 at 75 % = 1 day of lost pay');
  perform tst.check(hr.tiered_unpaid_days(tst.id('p2'), '2026-08-01', '2026-08-31') = 0, 'August sick days all at 100 %');
  perform tst.check(hr.pnum(hr.pay_rule('SPF_OMANI', '2026-06-30'), 'er_sick') = 0 and hr.pnum(hr.pay_rule('SPF_OMANI', '2026-09-30'), 'er_sick') = 1,
                    'sick-leave branch starts 19 Jul 2026');
end $$;
set role authenticated;

-- ===========================================================================
-- 2. Pay rules: maker-checker
-- ===========================================================================
do $$
declare v jsonb; v_id uuid;
begin
  perform tst.as_user('hro');
  v := public.hr_propose_pay_rule(jsonb_build_object('code','DEDUCTIONS', 'effective_from','2030-01-01', 'legal_basis','Test change',
         'value', jsonb_build_object('max_pct', 20)));
  select (x->>'id')::uuid into v_id from jsonb_array_elements(v) x where x->>'status' = 'PENDING';
  perform tst.expect_error(format('select public.hr_propose_pay_rule(%L)', jsonb_build_object('code','DEDUCTIONS', 'effective_from','2031-01-01',
            'legal_basis','x', 'value', jsonb_build_object('max_pct', 10))), 'PENDING_EXISTS');
  perform tst.expect_error(format('select public.hr_propose_pay_rule(%L)', jsonb_build_object('code','SPF_OMANI', 'effective_from','2031-01-01',
            'legal_basis','x', 'value', jsonb_build_object('ceiling', 'lots'))), 'INVALID');
  perform tst.as_user('hrm');
  v := public.hr_decide_pay_rule(v_id, true, 'ok');
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'code' = 'DEDUCTIONS' and x->>'effective_to' = '2029-12-31'),
                    'previous value closed the day before the new one');
end $$;
do $$
begin
  perform tst.as_user('hrm');
  perform public.hr_propose_pay_rule(jsonb_build_object('code','PAY_BASIS', 'effective_from','2031-01-01', 'legal_basis','Self test',
         'rule_basis','COMPANY_POLICY', 'value', jsonb_build_object('days_divisor',30,'hours_per_day',8,'absent_unpaid',1,'missing_punch_unpaid',0,'fund_leave_unpaid',0)));
  perform tst.expect_error(format('select public.hr_decide_pay_rule(%L, true)',
            (select x->>'id' from jsonb_array_elements(public.hr_list_pay_rules()) x where x->>'code' = 'PAY_BASIS' and x->>'status' = 'PENDING')), 'SELF_APPROVAL');
end $$;

-- ===========================================================================
-- 3. Loans and one-off adjustments (maker-checker)
-- ===========================================================================
do $$
declare v jsonb;
begin
  perform tst.as_user('hro');
  v := public.hr_propose_loan(jsonb_build_object('employee_id', tst.id('p2'), 'kind','LOAN', 'amount','200', 'installment','50',
         'first_month','2026-09', 'reason','Family emergency'));
  perform tst.put('loan1', (v->>'id')::uuid);
  perform tst.check((v->>'months_left')::int = 4, 'four instalments');
  perform tst.expect_error(format('select public.hr_propose_loan(%L)', jsonb_build_object('employee_id', tst.id('p2'), 'amount','100',
            'installment','150', 'first_month','2026-09', 'reason','x y z')), 'INVALID_AMOUNT');
  perform tst.expect_error(format('select public.hr_decide_loan(%L, true)', tst.id('loan1')), 'NOT_ALLOWED');
  v := public.hr_propose_pay_adjustments(jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('employee_no','PAYT-002', 'month','2026-09', 'code','BONUS', 'amount','100', 'reason','Good work'),
         jsonb_build_object('employee_no','PAYT-002', 'month','2026-09', 'code','PENALTY', 'amount','200', 'reason','Damaged tool'),
         jsonb_build_object('employee_no','NOPE-9', 'month','2026-09', 'code','BONUS', 'amount','1', 'reason','xxx'),
         jsonb_build_object('employee_no','PAYT-002', 'month','2026-09', 'code','LOTTERY', 'amount','1', 'reason','xxx'))));
  perform tst.check((v->>'proposed')::int = 2 and jsonb_array_length(v->'errors') = 2, 'two adjustments proposed, two rows refused');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_decide_loan(%L, true)', tst.id('loan1')), 'NOT_ALLOWED');
  perform tst.as_user('fin');
  v := public.hr_decide_loan(tst.id('loan1'), true, 'Policy OK');
  perform tst.check(v->>'status' = 'APPROVED', 'finance approves the loan');
  perform public.hr_decide_pay_adjustments(array(select (x->>'id')::uuid from jsonb_array_elements(public.hr_list_pay_adjustments(
           jsonb_build_object('status','PENDING','month','2026-09'))) x where x->>'employee_no' = 'PAYT-002'), true, null);
end $$;

-- ===========================================================================
-- 4. Run: calculate → verify → approve, with hand-checked figures
-- ===========================================================================
do $$
declare v jsonb; r uuid; s jsonb; v_e2 jsonb; amt numeric;
begin
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_create_payroll_run(%L, %L)', tst.id('pent'), to_char(current_date + 40, 'YYYY-MM')), 'future');
  v := public.hr_create_payroll_run(tst.id('pent'), '2026-10');
  perform tst.expect_error(format('select public.hr_calculate_payroll(%L)', v->>'id'), 'ATTENDANCE_OPEN');
  v := public.hr_create_payroll_run(tst.id('pent'), '2026-09');
  r := (v->>'id')::uuid; perform tst.put('run_sep', r);
  perform tst.expect_error(format('select public.hr_create_payroll_run(%L, %L)', tst.id('pent'), '2026-09'), 'DUPLICATE');
  v := public.hr_calculate_payroll(r);
  perform tst.check(v->>'status' = 'CALCULATED' and (v->'totals'->>'employees')::int = 4, 'four payslips');

  v := public.hr_get_payroll_run(r);
  -- e1 Omani 4,000 + 1,000: SPF old age capped at 3,000
  select x into s from jsonb_array_elements(v->'payslips') x where x->>'employee_no' = 'PAYT-001';
  perform tst.check((s->>'total_earnings')::numeric = 5000 and (s->>'total_deductions')::numeric = 250 and (s->>'net')::numeric = 4750,
                    'Omani: 225 (7.5 % of 3,000) + 25 (0.5 % of 5,000) deducted');
  perform tst.check((s->>'employer_cost')::numeric = 485, 'Omani employer: 330 + 30 + 25 + 50 + 50 = 485 (got ' || (s->>'employer_cost') || ')');
  -- e2 expat 450: 2 days absent (30), sick at 75 % (15), OT 2.5 h × 1.25 (3.125), bonus 100, penalty capped at 25 % of 405 (101.25), loan 50
  select x into v_e2 from jsonb_array_elements(v->'payslips') x where x->>'employee_no' = 'PAYT-002';
  perform tst.check((v_e2->>'total_earnings')::numeric = 553.125, 'expat earnings 450 + 3.125 + 100 (got ' || (v_e2->>'total_earnings') || ')');
  perform tst.check((v_e2->>'total_deductions')::numeric = 196.25, 'expat deductions 30 + 15 + 101.25 + 50 (got ' || (v_e2->>'total_deductions') || ')');
  perform tst.check((v_e2->>'net')::numeric = 356.875, 'expat net 356.875');
  perform tst.check((v_e2->>'unpaid_days')::numeric = 3.00, '3 unpaid day-equivalents');
  perform tst.check((v_e2->>'employer_cost')::numeric = 33.1, 'expat employer: SPF 4.05 + 4.05, gratuity accrual 25');
  perform tst.check(v_e2->'warnings' @> '["Deduction PENALTY of 200.000 reduced to the 25 % limit."]'::jsonb
                    or exists (select 1 from jsonb_array_elements_text(v_e2->'warnings') w where w like 'Deduction PENALTY%25 % limit.'), 'cap warning');
  -- e3 joined 16 Sep: 15 of 30 days
  select x into s from jsonb_array_elements(v->'payslips') x where x->>'employee_no' = 'PAYT-003';
  perform tst.check((s->>'total_earnings')::numeric = 150 and (s->>'employed_days')::int = 15, 'joiner paid 15/30 of 300');
  perform tst.check(exists (select 1 from jsonb_array_elements_text(s->'warnings') w where w like 'No approved bank account%'), 'missing bank warned');
  -- e4 salary 600 → 900 from 16 Sep: 600 × 15/30 + 900 × 15/30 = 750
  select x into s from jsonb_array_elements(v->'payslips') x where x->>'employee_no' = 'PAYT-004';
  perform tst.check((s->>'total_earnings')::numeric = 750, 'mid-month increment split (got ' || (s->>'total_earnings') || ')');

  -- payslip lines
  s := public.hr_get_payslip((v_e2->>'id')::uuid);
  select (x->>'amount')::numeric into amt from jsonb_array_elements(s->'lines') x where x->>'code' = 'SICK_REDUCED';
  perform tst.check(amt = 15, 'sick reduced line 15');
  select (x->>'amount')::numeric into amt from jsonb_array_elements(s->'lines') x where x->>'code' = 'EOSB_ACCRUAL';
  perform tst.check(amt = 25, 'gratuity accrual 300 / 12');

  -- maker-checker on the run
  perform tst.expect_error(format('select public.hr_verify_payroll(%L)', r), 'NOT_ALLOWED');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_approve_payroll(%L)', r), 'NOT_ALLOWED');
  perform tst.as_user('fin');
  perform tst.expect_error(format('select public.hr_approve_payroll(%L)', r), 'not waiting');
  perform tst.as_user('hrm');
  v := public.hr_verify_payroll(r, 'Checked against register');
  perform tst.check(v->>'status' = 'VERIFIED', 'HR manager verifies');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_calculate_payroll(%L)', r), 'PERIOD_LOCKED');
end $$;

-- the late adjustment above is refused row by row (not raised): check the result shape
do $$
declare v jsonb;
begin
  perform tst.as_user('hro');
  v := public.hr_propose_pay_adjustments(jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('employee_no','PAYT-001','month','2026-09','code','BONUS','amount','1','reason','late bonus'))));
  perform tst.check((v->>'proposed')::int = 0 and v->'errors'->0->>'message' like '%already verified%', 'no adjustments once verified');
end $$;

-- approving a payroll that contains your own salary is refused
reset role;
update hr.user_profiles set employee_id = tst.id('p4') where user_id = tst.id('user_fin');
set role authenticated;
do $$
begin
  perform tst.as_user('fin');
  perform tst.expect_error(format('select public.hr_approve_payroll(%L)', tst.id('run_sep')), 'own salary');
end $$;
reset role;
update hr.user_profiles set employee_id = null where user_id = tst.id('user_fin');
set role authenticated;

do $$
declare v jsonb; r uuid := tst.id('run_sep');
begin
  perform tst.as_user('fin');
  v := public.hr_approve_payroll(r, 'Approved');
  perform tst.check(v->>'status' = 'APPROVED' and (v->>'can_export_bank')::boolean, 'finance approves; bank file available');
  perform tst.check((select (x->>'outstanding')::numeric from jsonb_array_elements(public.hr_list_loans(jsonb_build_object('employee_id', tst.id('p2')))) x) = 150,
                    'one instalment repaid on approval');
end $$;

-- ===========================================================================
-- 5. Exports, parallel run, reopen and pay
-- ===========================================================================
do $$
declare v jsonb; r uuid := tst.id('run_sep'); dr numeric; cr numeric;
begin
  perform tst.as_user('fin');
  v := public.hr_payroll_export(r, 'WPS');
  perform tst.check(jsonb_array_length(v->'rows') = 4 and v->>'bank_code' = 'BMCT', 'WPS: all four with net pay');
  perform tst.check((select (x->>'social_security')::numeric from jsonb_array_elements(v->'rows') x where x->>'employee_no' = 'PAYT-001') = 250, 'WPS social security column');
  perform tst.check((select count(*) from jsonb_array_elements(v->'rows') x where not (x->>'has_bank')::boolean) = 1, 'one row without bank flagged');
  v := public.hr_payroll_export(r, 'JOURNAL');
  select coalesce(sum((x->>'amount')::numeric) filter (where x->>'kind' = 'EARNING'), 0),
         coalesce(sum((x->>'amount')::numeric) filter (where x->>'kind' = 'DEDUCTION'), 0) into dr, cr from jsonb_array_elements(v->'lines') x;
  perform tst.check(dr - cr = (v->>'net')::numeric, 'journal: earnings − deductions = net pay');
  v := public.hr_payroll_export(r, 'SPF');
  perform tst.check(jsonb_array_length(v->'rows') = 4, 'SPF report rows');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_payroll_export(%L, %L)', r, 'WPS'), 'NOT_ALLOWED');
  v := public.hr_save_parallel(r, jsonb_build_object('replace', true, 'rows', jsonb_build_array(
         jsonb_build_object('employee_no','PAYT-001', 'net','4750'), jsonb_build_object('employee_no','PAYT-002', 'net','350.000'),
         jsonb_build_object('employee_no','OLD-9', 'net','100'), jsonb_build_object('employee_no','PAYT-003', 'net','abc'))));
  perform tst.check((v->>'loaded')::int = 3 and jsonb_array_length(v->'errors') = 1, 'parallel rows loaded');
  v := public.hr_parallel_report(r);
  perform tst.check((select x->>'status' from jsonb_array_elements(v->'rows') x where x->>'employee_no' = 'PAYT-001') = 'MATCH', 'match');
  perform tst.check((select (x->>'diff')::numeric from jsonb_array_elements(v->'rows') x where x->>'employee_no' = 'PAYT-002') = 6.875, 'difference shown');
  perform tst.check((select x->>'status' from jsonb_array_elements(v->'rows') x where x->>'employee_no' = 'OLD-9') = 'ONLY_LEGACY', 'only in old payroll');
  -- reopen undoes loan repayments
  perform tst.as_user('fin');
  perform tst.expect_error(format('select public.hr_reopen_payroll(%L, %L)', r, ''), 'REQUIRED');
  v := public.hr_reopen_payroll(r, 'Bonus amount wrong');
  perform tst.check(v->>'status' = 'DRAFT', 'reopened');
  perform tst.check((select (x->>'outstanding')::numeric from jsonb_array_elements(public.hr_list_loans(jsonb_build_object('employee_id', tst.id('p2')))) x) = 200,
                    'repayment undone');
  perform tst.as_user('hro');  perform public.hr_calculate_payroll(r);
  perform tst.as_user('fin');  perform tst.expect_error(format('select public.hr_return_payroll(%L, %L)', r, 'x'), 'REQUIRED');
  perform public.hr_return_payroll(r, 'Recheck overtime');
  perform tst.as_user('hro');  perform public.hr_calculate_payroll(r);
  perform tst.as_user('hrm');  perform public.hr_verify_payroll(r, null);
  perform tst.as_user('fin');  perform public.hr_approve_payroll(r, null);
  v := public.hr_mark_payroll_paid(r);
  perform tst.check(v->>'status' = 'PAID' and not (v->>'can_reopen')::boolean, 'paid runs cannot be reopened');
  perform tst.expect_error(format('select public.hr_reopen_payroll(%L, %L)', r, 'too late'), 'NOT_FOUND');
end $$;

-- ===========================================================================
-- 6. Employee sees own payslip only after approval; auditor reads; others cannot
-- ===========================================================================
reset role;
update hr.user_profiles set employee_id = tst.id('p2') where user_id = tst.id('user_nobody');
insert into hr.user_profiles(user_id, display_name, is_active, employee_id)
select tst.id('user_nobody'), 'Nobody', true, tst.id('p2') where not exists (select 1 from hr.user_profiles where user_id = tst.id('user_nobody'));
insert into hr.user_roles(user_id, role_code) values (tst.id('user_nobody'), 'EMPLOYEE') on conflict do nothing;
set role authenticated;
do $$
declare v jsonb; v_slip uuid;
begin
  perform tst.as_user('nobody');
  v := public.hr_my_payslips();
  perform tst.check(jsonb_array_length(v) = 1 and (v->0->>'net')::numeric = 356.875, 'employee sees own September payslip');
  v_slip := (v->0->>'id')::uuid;
  perform tst.check(public.hr_get_payslip(v_slip)->>'employee_no' = 'PAYT-002', 'opens own payslip');
  perform tst.expect_error(format('select public.hr_get_payroll_run(%L)', tst.id('run_sep')), 'NOT_ALLOWED');
  perform tst.check(jsonb_array_length(public.hr_employee_payroll(tst.id('p2'))->'payslips') = 1, 'own payroll history');
  perform tst.expect_error(format('select public.hr_employee_payroll(%L)', tst.id('p1')), 'NOT_ALLOWED');
end $$;
do $$
begin
  perform tst.as_user('aud');
  perform tst.check((public.hr_get_payroll_run(tst.id('run_sep'))->'totals'->>'employees')::int = 4, 'auditor reads the run');
  perform tst.check((select count(*) from jsonb_array_elements(public.hr_gratuity_report(tst.id('pent'), '2026-09-30')->'rows')) = 2,
                    'gratuity provision lists the two expatriates');
  perform tst.check(public.hr_payroll_setup()->'entities' is not null, 'auditor reads the set-up');
  perform tst.expect_error(format('select public.hr_save_payroll_setup(%L)', '{}'), 'NOT_ALLOWED');
  perform tst.expect_error(format('select public.hr_calculate_payroll(%L)', tst.id('run_sep')), 'NOT_ALLOWED');
  perform tst.put('slip_p1', (select (x->>'id')::uuid from jsonb_array_elements(public.hr_get_payroll_run(tst.id('run_sep'))->'payslips') x
                              where x->>'employee_no' = 'PAYT-001'));
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_get_payslip(%L)', tst.id('slip_p1')), 'NOT_ALLOWED');
end $$;

-- ===========================================================================
-- 7. Final settlement: gratuity, leave pay, loan recovery (maker-checker)
-- ===========================================================================
do $$
declare v jsonb; v_id uuid;
begin
  perform tst.as_user('hro');
  v := public.hr_preview_settlement(jsonb_build_object('employee_id', tst.id('p2'), 'last_working_date','2026-10-15', 'notice_days', 0));
  perform tst.check((v->'gratuity_detail'->>'old_amount')::numeric = 450, 'settlement gratuity: old part 450');
  perform tst.check((v->>'gratuity')::numeric > 1400 and (v->>'gratuity')::numeric < 1420, 'settlement gratuity total ~1,413 (got ' || (v->>'gratuity') || ')');
  perform tst.check((v->>'loan_recovery')::numeric = 150, 'outstanding loan recovered');
  perform tst.check((v->>'leave_partial_accrual')::numeric > 0, 'leave accrued for the part month');
  v := public.hr_save_settlement(jsonb_build_object('employee_id', tst.id('p2'), 'last_working_date','2026-10-15', 'reason','RESIGNATION',
         'notice_days', 0, 'other', jsonb_build_array(jsonb_build_object('label','Ticket allowance', 'kind','EARNING', 'amount','120'))));
  v_id := (v->>'id')::uuid;
  perform tst.check((v->>'other_earnings')::numeric = 120, 'extra line kept');
  perform tst.expect_error(format('select public.hr_save_settlement(%L)', jsonb_build_object('employee_id', tst.id('p2'), 'last_working_date','2026-10-15')), 'DUPLICATE');
  perform tst.expect_error(format('select public.hr_decide_settlement(%L, true)', v_id), 'NOT_ALLOWED');
  perform tst.as_user('fin');
  v := public.hr_decide_settlement(v_id, true, 'Checked');
  perform tst.check(v->>'status' = 'APPROVED', 'settlement approved');
  perform tst.check((select x->>'status' from jsonb_array_elements(public.hr_list_loans(jsonb_build_object('employee_id', tst.id('p2')))) x) = 'CLOSED',
                    'loan closed by the settlement');
  v := public.hr_mark_settlement_paid(v_id);
  perform tst.check(v->>'status' = 'PAID', 'settlement paid');
end $$;

-- ===========================================================================
-- 8. Tasks and dashboard include payroll
-- ===========================================================================
do $$
declare v jsonb; r jsonb;
begin
  perform tst.as_user('hro');
  r := public.hr_create_payroll_run(tst.id('pent'), '2026-08');
  reset role;
  insert into hr.attendance_periods(entity_id, period_start, status, locked_by, locked_at) values (tst.id('pent'), '2026-08-01', 'LOCKED', tst.id('user_hrm'), now());
  set role authenticated;
  perform tst.as_user('hro');
  perform public.hr_calculate_payroll((r->>'id')::uuid);
  perform tst.as_user('hrm');
  v := public.hr_list_my_tasks();
  perform tst.check(jsonb_array_length(v->'payroll') = 1, 'HR manager has a run to verify');
  perform tst.check((public.hr_time_dashboard()->'tasks'->>'payroll')::int = 1, 'dashboard counts it');
  perform tst.as_user('hro');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'payroll') = 0, 'the preparer has nothing to verify');
end $$;

reset role;
select 'ALL PAYROLL TESTS PASSED' as result;
