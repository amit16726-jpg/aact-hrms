-- AACT HRMS — Phase 5 (recruitment & onboarding) database tests.
-- Runs after 10–40 (uses their users and masters: user_mgr is linked to emp_mgr, who manages emp_w).

set client_min_messages = warning;
reset role;
do $$
begin
  insert into hr.employee_categories(entity_id, code, name_en, pay_basis) values (tst.id('ent'), 'DAILY', 'Daily-paid workers', 'DAILY')
  on conflict (entity_id, code) do nothing;
  perform tst.put('cat_daily', (select id from hr.employee_categories where entity_id = tst.id('ent') and code = 'DAILY'));
end $$;
grant execute on all functions in schema tst to authenticated;
set role authenticated;

-- ===========================================================================
-- 1. Requisitions: who may raise, Omani-only rule, approval by someone else
-- ===========================================================================
do $$
declare r jsonb;
begin
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_save_requisition(%L)', jsonb_build_object('department_id', tst.id('dep_prod'), 'job_title_id', tst.id('job_op'),
    'justification', 'Need more operators for line 2')), 'line manager');

  perform tst.as_user('mgr');
  perform tst.expect_error(format('select public.hr_save_requisition(%L)', jsonb_build_object('department_id', tst.id('dep_prod'), 'job_title_id', tst.id('job_op'),
    'justification', 'short')), 'at least 10');
  r := public.hr_save_requisition(jsonb_build_object('department_id', tst.id('dep_prod'), 'job_title_id', tst.id('job_op'), 'grade_id', tst.id('gr_w1'),
    'category_id', tst.id('cat_staff'), 'positions', 2, 'salary_min', '200', 'salary_max', '300', 'justification', 'Second shift on line 2 from January'));
  perform tst.check(r->>'status' = 'PENDING' and r->>'ref_no' ~ '^REQ-[0-9]{4}-0001$', 'requisition raised by the line manager: ' || (r->>'ref_no'));
  perform tst.check(r->'omanisation'->'entity' ? 'pct' and (r->'omanisation'->>'pct_if_expat') is not null, 'Omanisation check shown before hiring');
  perform tst.check(not (r->>'can_decide')::boolean, 'the requester cannot approve');
  perform tst.put('req1', (r->>'id')::uuid);
  perform tst.expect_error(format('select public.hr_decide_requisition(%L, true)', tst.id('req1')), 'NOT_ALLOWED|permission');

  perform tst.as_user('hro');
  r := public.hr_save_requisition(jsonb_build_object('department_id', tst.id('dep_hr'), 'job_title_id', tst.id('job_hro'), 'category_id', tst.id('cat_staff'),
    'positions', 1, 'nationality_rule', 'ANY', 'justification', 'Replacement for the HR officer who resigned'));
  perform tst.check(r->>'nationality_rule' = 'OMANI_ONLY', 'an Omani-only job forces the Omani-only rule');
  perform tst.put('req2', (r->>'id')::uuid);

  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_decide_requisition(%L, false, '''')', tst.id('req1')), 'reason for rejecting');
  r := public.hr_decide_requisition(tst.id('req1'), true, 'Budgeted');
  perform tst.check(r->>'status' = 'APPROVED', 'approved by HR manager');
  perform public.hr_decide_requisition(tst.id('req2'), true, null);
  r := public.hr_save_requisition(jsonb_build_object('department_id', tst.id('dep_prod'), 'job_title_id', tst.id('job_mgr'), 'category_id', tst.id('cat_staff'),
    'justification', 'Deputy production manager for expansion'));
  perform tst.put('req3', (r->>'id')::uuid);
  perform tst.expect_error(format('select public.hr_decide_requisition(%L, true)', tst.id('req3')), 'SELF_APPROVAL');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'requisitions') = 0, 'own requisition is not a task for the HR manager');
end $$;

-- ===========================================================================
-- 2. Candidates and applications
-- ===========================================================================
do $$
declare a jsonb; c jsonb;
begin
  perform tst.as_user('aud');
  perform tst.check(jsonb_array_length(public.hr_list_requisitions('{}'::jsonb)) = 3, 'auditor sees requisitions (read only)');
  perform tst.expect_error('select public.hr_save_candidate(''{"full_name_en":"X Y","nationality":"IN"}''::jsonb)', 'NOT_ALLOWED|permission');

  perform tst.as_user('hro');
  c := public.hr_save_candidate(jsonb_build_object('full_name_en','Arjun Nair','nationality','IN','gender','M','date_of_birth','1994-05-10',
    'email','arjun.nair@example.com','phone','+91 98470 11111','passport_no','p1234567','in_oman', false, 'experience_years', 6, 'source','AGENCY'));
  perform tst.check(c->>'passport_no' = 'P1234567' and not (c->>'in_oman')::boolean, 'candidate saved');
  perform tst.put('cand1', (c->>'id')::uuid);
  perform tst.expect_error('select public.hr_save_candidate(''{"full_name_en":"Someone Else","nationality":"IN","email":"ARJUN.NAIR@example.com"}''::jsonb)', 'DUPLICATE');

  perform tst.expect_error(format('select public.hr_add_application(%L)', jsonb_build_object('requisition_id', tst.id('req2'), 'candidate_id', tst.id('cand1'))), 'OMANI_ONLY');
  perform tst.expect_error(format('select public.hr_add_application(%L)', jsonb_build_object('requisition_id', tst.id('req3'), 'candidate_id', tst.id('cand1'))), 'approved, open');
  a := public.hr_add_application(jsonb_build_object('requisition_id', tst.id('req1'), 'candidate_id', tst.id('cand1')));
  perform tst.check(a->>'stage' = 'APPLIED' and (a->>'probation_max_months')::int = 3, 'application created; monthly category allows 3 months probation');
  perform tst.put('app1', (a->>'id')::uuid);
  perform tst.expect_error(format('select public.hr_add_application(%L)', jsonb_build_object('requisition_id', tst.id('req1'), 'candidate_id', tst.id('cand1'))), 'DUPLICATE');

  a := public.hr_add_application(jsonb_build_object('requisition_id', tst.id('req2'), 'candidate', jsonb_build_object('full_name_en','Huda Al Saadi','full_name_ar','هدى السعدية',
         'nationality','OM','gender','F','date_of_birth','1998-02-01','civil_number','12345678','phone','+968 9000 2222','email','huda.s@example.com')));
  perform tst.check((a->'candidate'->>'in_oman')::boolean and (a->>'is_omani')::boolean, 'Omani candidate added inline (in Oman by default)');
  perform tst.put('app2', (a->>'id')::uuid);

  -- a returning former employee (same civil number as emp_w)
  c := public.hr_save_candidate(jsonb_build_object('full_name_en','Ravi Kumar','nationality','IN','civil_number','rc998877','in_oman', true));
  a := public.hr_add_application(jsonb_build_object('requisition_id', tst.id('req1'), 'candidate_id', c->>'id'));
  perform tst.check(a->>'prior_employee_id' = tst.id('emp_w')::text, 'former employee recognised');
  perform tst.put('app3', (a->>'id')::uuid);

  perform tst.expect_error(format('select public.hr_move_application(%L, ''REJECTED'')', tst.id('app3')), 'Give a reason');
  perform tst.expect_error(format('select public.hr_move_application(%L, ''HIRED'')', tst.id('app3')), 'automatically');
  a := public.hr_move_application(tst.id('app1'), 'SHORTLISTED');
  perform tst.check(a->>'stage' = 'SHORTLISTED', 'shortlisted');
end $$;

-- ===========================================================================
-- 3. Interviews: the line manager interviews and records feedback
-- ===========================================================================
do $$
declare a jsonb; i jsonb;
begin
  perform tst.as_user('hro');
  a := public.hr_schedule_interview(jsonb_build_object('application_id', tst.id('app1'), 'scheduled_at', (now() + interval '2 days')::text,
         'mode','VIDEO', 'location','Teams', 'interviewer_id', tst.id('user_mgr')));
  perform tst.check(a->>'stage' = 'INTERVIEW' and jsonb_array_length(a->'interviews') = 1, 'interview scheduled; stage moves to interview');
  perform tst.put('int1', (a->'interviews'->0->>'id')::uuid);
  -- a past interview not yet recorded becomes a task for the interviewer
  a := public.hr_schedule_interview(jsonb_build_object('application_id', tst.id('app2'), 'scheduled_at', (now() - interval '1 hour')::text,
         'interviewer_id', tst.id('user_mgr')));
  perform tst.put('int2', (a->'interviews'->0->>'id')::uuid);

  perform tst.as_user('mgr');
  perform tst.check(jsonb_array_length(public.hr_my_interviews()) = 2, 'manager sees the interviews assigned to him');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'interviews') = 1, 'the overdue interview is a task');
  a := public.hr_get_application(tst.id('app1'));
  perform tst.check(a->'candidate'->>'email' is null and a->'candidate'->>'full_name_en' = 'Arjun Nair', 'interviewer sees the candidate without contact details');
  perform tst.check(jsonb_array_length(a->'offers') = 0, 'interviewer does not see offers');
  perform tst.check(public.hr_get_application(tst.id('app3'))->>'id' = tst.id('app3')::text, 'the requesting manager sees candidates on his requisition');
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_get_application(%L)', tst.id('app3')), 'NOT_ALLOWED|cannot see');
  perform tst.as_user('mgr');
  perform tst.expect_error(format('select public.hr_record_interview(%L, %L)', tst.id('int1'), '{"status":"DONE","rating":4,"recommendation":"HIRE","feedback":"ok"}'), 'at least 10');
  a := public.hr_record_interview(tst.id('int1'), '{"status":"DONE","rating":4,"recommendation":"HIRE","feedback":"Strong on machine set-up; good safety awareness."}'::jsonb);
  perform tst.check((a->>'avg_rating')::numeric = 4, 'feedback recorded');
  a := public.hr_record_interview(tst.id('int2'), '{"status":"DONE","rating":5,"recommendation":"HIRE","feedback":"Excellent knowledge of Oman labour procedures."}'::jsonb);
  perform tst.expect_error(format('select public.hr_record_interview(%L, %L)', tst.id('int1'), '{"status":"DONE","rating":3,"recommendation":"MAYBE","feedback":"changing my mind"}'), 'NOT_PENDING');
end $$;

-- ===========================================================================
-- 4. Offers: probation limits (Labour Law), Omani-only, basic required, approval by another person
-- ===========================================================================
do $$
declare a jsonb; o jsonb; v_start date := (now() at time zone 'Asia/Muscat')::date + 30;
begin
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_save_offer(%L)', jsonb_build_object('application_id', tst.id('app1'), 'start_date', v_start, 'category_id', tst.id('cat_staff'),
    'contract_months', 24, 'probation_months', 4, 'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','250')))), 'at most 3 month');
  perform tst.expect_error(format('select public.hr_save_offer(%L)', jsonb_build_object('application_id', tst.id('app1'), 'start_date', v_start, 'category_id', tst.id('cat_daily'),
    'contract_months', 24, 'probation_months', 3, 'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','250')))), 'at most 2 month');
  perform tst.expect_error(format('select public.hr_save_offer(%L)', jsonb_build_object('application_id', tst.id('app1'), 'start_date', v_start, 'category_id', tst.id('cat_staff'),
    'contract_months', 24, 'probation_months', 3, 'lines', jsonb_build_array(jsonb_build_object('code','HOUSING','amount','80')))), 'basic salary');
  perform tst.expect_error(format('select public.hr_save_offer(%L)', jsonb_build_object('application_id', tst.id('app1'), 'start_date', v_start, 'category_id', tst.id('cat_staff'),
    'job_title_id', tst.id('job_hro'), 'contract_months', 24, 'probation_months', 3, 'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','250')))), 'OMANI_ONLY');
  perform tst.expect_error(format('select public.hr_save_offer(%L)', jsonb_build_object('application_id', tst.id('app1'), 'start_date', v_start, 'category_id', tst.id('cat_staff'),
    'contract_type','FIXED_TERM', 'probation_months', 3, 'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','250')))), 'contract length');
  perform tst.expect_error(format('select public.hr_save_offer(%L)', jsonb_build_object('application_id', tst.id('app3'), 'start_date', v_start, 'category_id', tst.id('cat_staff'),
    'contract_months', 12, 'probation_months', 1, 'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','250')))), 'only once with the same employer');

  a := public.hr_save_offer(jsonb_build_object('application_id', tst.id('app1'), 'start_date', v_start, 'category_id', tst.id('cat_staff'),
    'contract_type','FIXED_TERM', 'contract_months', 24, 'probation_months', 3, 'notice_days', 30, 'benefits', 'Return air ticket every two years; shared accommodation',
    'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','250'), jsonb_build_object('code','HOUSING','amount','80'), jsonb_build_object('code','TRANSPORT','amount','0'))));
  o := a->'offers'->0;
  perform tst.check(a->>'stage' = 'OFFER' and o->>'status' = 'PENDING' and (o->>'gross')::numeric = 330, 'offer prepared: gross 330 (zero lines dropped)');
  perform tst.check(jsonb_array_length(o->'lines') = 2 and o->>'ref_no' ~ '^OFR-', 'offer lines named; reference ' || (o->>'ref_no'));
  perform tst.put('ofr1', (o->>'id')::uuid);
  perform tst.expect_error(format('select public.hr_save_offer(%L)', jsonb_build_object('application_id', tst.id('app1'), 'start_date', v_start, 'category_id', tst.id('cat_staff'),
    'contract_months', 24, 'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','250')))), 'PENDING_EXISTS');
  perform tst.expect_error(format('select public.hr_offer_response(%L, true)', tst.id('ofr1')), 'Only an approved offer');

  perform tst.as_user('hrm');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'offers') = 1, 'HR manager has the offer to approve');
  a := public.hr_decide_offer(tst.id('ofr1'), true, 'Within band');
  perform tst.check(a->'offers'->0->>'status' = 'APPROVED', 'offer approved');
  o := public.hr_get_offer(tst.id('ofr1'));
  perform tst.check(o->'candidate'->>'full_name_en' = 'Arjun Nair' and o ? 'settings', 'printable offer has candidate and signatory settings');

  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_offer_response(%L, false, '''')', tst.id('ofr1')), 'reason the candidate gave');
  a := public.hr_offer_response(tst.id('ofr1'), true, 'Signed copy received');
  perform tst.check(a->'offers'->0->>'status' = 'ACCEPTED' and jsonb_array_length(a->'onboarding') = 9, 'accepted: expatriate-abroad checklist of 9 steps');
  perform tst.check((select (x->>'due_date')::date from jsonb_array_elements(a->'onboarding') x where x->>'code' = 'LABOUR_CLEARANCE') = v_start - 45,
                    'work permit due 45 days before the start');

  -- Omani candidate for the Omani-only job: one-month probation
  a := public.hr_save_offer(jsonb_build_object('application_id', tst.id('app2'), 'start_date', v_start, 'category_id', tst.id('cat_staff'),
    'contract_type','INDEFINITE', 'probation_months', 1, 'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','700'), jsonb_build_object('code','HOUSING','amount','150'))));
  perform tst.put('ofr2', (a->'offers'->0->>'id')::uuid);
  perform tst.as_user('hrm');
  perform public.hr_decide_offer(tst.id('ofr2'), true, null);
  perform tst.as_user('hro');
  a := public.hr_offer_response(tst.id('ofr2'), true, null);
  perform tst.check(jsonb_array_length(a->'onboarding') = 4, 'Omani checklist of 4 steps (with SPF registration)');
end $$;

-- ===========================================================================
-- 5. Hiring creates the employee, proposed salary, contract; fills the requisition
-- ===========================================================================
do $$
declare a jsonb; v_emp uuid; v_start date := (now() at time zone 'Asia/Muscat')::date + 30; t jsonb;
begin
  perform tst.as_user('hro');
  a := public.hr_hire(tst.id('ofr1'), jsonb_build_object('manager_id', tst.id('emp_mgr'), 'location_id', tst.id('loc')));
  v_emp := (a->>'new_employee_id')::uuid;
  perform tst.check(a->>'stage' = 'HIRED' and v_emp is not null and a->>'employee_no' like 'AACT-%', 'hired as ' || coalesce(a->>'employee_no','?'));
  perform tst.put('hire1', v_emp);
  perform tst.expect_error(format('select public.hr_hire(%L)', tst.id('ofr1')), 'Already hired');
  a := public.hr_hire(tst.id('ofr2'), jsonb_build_object('manager_id', tst.id('emp_mgr')));
  perform tst.put('hire2', (a->>'new_employee_id')::uuid);
  -- onboarding steps
  t := (select x from jsonb_array_elements(a->'onboarding') x where x->>'code' = 'SPF_REGISTRATION');
  perform tst.expect_error(format('select public.hr_set_onboarding_task(%L, ''NOT_NEEDED'')', t->>'id'), 'not needed');
  a := public.hr_set_onboarding_task((t->>'id')::uuid, 'DONE', 'SPF number 123 (test)');
  perform tst.check((select x->>'status' from jsonb_array_elements(a->'onboarding') x where x->>'code' = 'SPF_REGISTRATION') = 'DONE', 'step ticked');
  perform tst.check(jsonb_array_length(public.hr_list_onboarding('{}'::jsonb)) = 2, 'two people in onboarding');
end $$;

reset role;
do $$
declare v_start date := hr.today() + 30;
begin
  perform tst.check((select status from hr.employees where id = tst.id('hire1')) = 'PROBATION', 'new employee on probation');
  perform tst.check((select probation_end_date from hr.employees where id = tst.id('hire1')) = (v_start + interval '3 months' - interval '1 day')::date, 'probation ends after 3 months');
  perform tst.check((select join_date from hr.employees where id = tst.id('hire1')) = v_start, 'joining date = offer start');
  perform tst.check((select status from hr.compensation_revisions where employee_id = tst.id('hire1')) = 'PENDING', 'salary proposed for approval (not approved by HR officer)');
  perform tst.check((select total_monthly from hr.compensation_revisions where employee_id = tst.id('hire1')) = 330, 'proposed salary 330');
  perform tst.check((select end_date from hr.employee_contracts where employee_id = tst.id('hire1') and status = 'ACTIVE') = (v_start + interval '24 months' - interval '1 day')::date,
                    'two-year fixed-term contract recorded');
  perform tst.check((select status from hr.job_requisitions where id = tst.id('req2')) = 'FILLED', 'one-position requisition filled');
  perform tst.check((select status from hr.job_requisitions where id = tst.id('req1')) = 'APPROVED', 'two-position requisition stays open');
  perform tst.check((select count(*) from hr.onboarding_tasks where employee_id = tst.id('hire1')) = 9, 'checklist linked to the employee');
  perform tst.check((select employee_id from hr.candidates where id = tst.id('cand1')) = tst.id('hire1'), 'candidate linked to the employee');
  perform tst.check(exists (select 1 from hr.audit_log where table_name = 'job_offers'), 'offers are audited');
end $$;
set role authenticated;

-- ===========================================================================
-- 6. Probation tracker, extension within the legal maximum, reminders
-- ===========================================================================
do $$
declare v jsonb; m jsonb; v_start date := (now() at time zone 'Asia/Muscat')::date + 30;
begin
  perform tst.as_user('mgr');
  v := public.hr_list_probation();
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'employee_id' = tst.id('hire1')::text), 'manager sees his new hire on probation');
  perform tst.as_user('hro');
  v := public.hr_list_probation();
  m := (select x from jsonb_array_elements(v) x where x->>'employee_id' = tst.id('hire2')::text);
  perform tst.check((m->>'max_end')::date = (v_start + interval '3 months' - interval '1 day')::date, 'legal maximum shown');
  perform tst.expect_error(format('select public.hr_extend_probation(%L, %L)', tst.id('hire2'),
    jsonb_build_object('probation_end_date', v_start + 100, 'reason', 'Needs more time on payroll')), 'PROBATION_LIMIT');
  v := public.hr_extend_probation(tst.id('hire2'), jsonb_build_object('probation_end_date', (v_start + interval '2 months' - interval '1 day')::date,
       'reason', 'Needs more time on the payroll module'));
  perform tst.check((select (x->>'probation_end_date')::date from jsonb_array_elements(v) x where x->>'employee_id' = tst.id('hire2')::text)
                    = (v_start + interval '2 months' - interval '1 day')::date, 'probation extended within the limit');
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_list_probation()', 'NOT_ALLOWED|cannot see');
end $$;

reset role;
do $$
declare n int;
begin
  update hr.employees set join_date = hr.today() - 60, original_join_date = hr.today() - 60, probation_end_date = hr.today() + 5 where id = tst.id('hire1');
  n := hr.probation_reminders();
  perform tst.check(n >= 2, 'probation reminder sent to HR manager and line manager (' || n || ')');
  perform tst.check(exists (select 1 from hr.notifications where user_id = tst.id('user_mgr') and ref_key like 'PROB:' || tst.id('hire1') || '%'), 'line manager reminded');
  perform tst.check(hr.probation_reminders() = 0, 'no duplicate reminders');
end $$;
set role authenticated;

-- ===========================================================================
-- 7. Settings, dashboard, withdraw
-- ===========================================================================
do $$
declare v jsonb; a jsonb;
begin
  perform tst.as_user('hro');
  perform tst.expect_error('select public.hr_save_recruitment_settings(''{"probation_reminder_days":7}''::jsonb)', 'NOT_ALLOWED|permission');
  perform tst.as_user('hrm');
  perform tst.expect_error('select public.hr_save_recruitment_settings(''{"probation_monthly_max_months":4}''::jsonb)', '0–3');
  v := public.hr_save_recruitment_settings('{"probation_reminder_days":7}'::jsonb);
  perform tst.check((v->>'probation_reminder_days')::int = 7 and v->'onboarding' ? 'OMANI', 'settings saved, checklists kept');
  v := public.hr_time_dashboard();
  perform tst.check((v->'recruitment'->>'open_requisitions')::int = 1 and (v->'recruitment'->>'open_positions')::int = 1, 'dashboard: one open position left');

  -- withdraw an offer before hiring
  perform tst.as_user('hro');
  a := public.hr_move_application(tst.id('app3'), 'WITHDRAWN', 'Took another job');
  perform tst.check(a->>'stage' = 'WITHDRAWN', 'candidate withdrawn');
  perform tst.expect_error(format('select public.hr_set_requisition_status(%L, ''CANCELLED'')', tst.id('req1')), 'Give a reason');
  v := public.hr_set_requisition_status(tst.id('req1'), 'ON_HOLD', 'Budget freeze until Q1');
  perform tst.check(v->>'status' = 'ON_HOLD', 'requisition on hold');
end $$;

reset role;
select 'ALL RECRUITMENT TESTS PASSED' as result;
