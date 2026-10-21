-- AACT HRMS — Phase 6 (performance, training, discipline, assets, housing & transport, injuries, exit) database tests.
-- Runs after 10–50 (uses their users and masters: user_mgr is linked to emp_mgr, who manages emp_w; user_emp is emp_w).

set client_min_messages = warning;
-- Runs as the database owner so the checks can read the hr tables directly; the API functions still check
-- permissions from the logged-in user (request.jwt.claim.sub). Grants for the authenticated role are checked at the end.
reset role;

-- ===========================================================================
-- 1. Performance cycle: self-assessment → manager → HR → employee acknowledges
-- ===========================================================================
do $$
declare c jsonb; r jsonb; v_cycle uuid; v_rev uuid; t jsonb;
begin
  perform tst.as_user('mgr');
  perform tst.expect_error(format('select public.hr_save_perf_cycle(%L)', jsonb_build_object('entity_id', tst.id('ent'), 'name', 'X',
    'period_start', tst.today() - 180, 'period_end', tst.today() - 1)), 'NOT_ALLOWED|permission');

  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_save_perf_cycle(%L)', jsonb_build_object('entity_id', tst.id('ent'), 'name', 'H1',
    'period_start', tst.today(), 'period_end', tst.today() - 10)), 'ends before');
  c := public.hr_save_perf_cycle(jsonb_build_object('entity_id', tst.id('ent'), 'name', 'Mid-year review', 'period_start', tst.today() - 180,
    'period_end', tst.today() - 1, 'due_date', tst.today() + 30));
  v_cycle := (select (x->>'id')::uuid from jsonb_array_elements(c) x where x->>'name' = 'Mid-year review');
  perform tst.put('cycle1', v_cycle);
  perform tst.as_user('emp');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_list_perf_cycles()) x where (x->>'id')::uuid = v_cycle), 'draft cycle hidden from employees');

  perform tst.as_user('hrm');
  c := public.hr_open_perf_cycle(v_cycle, '[{"title":"Output per shift","weight":2},{"title":"Safety rules","weight":1},{"title":""}]'::jsonb);
  perform tst.check(exists (select 1 from jsonb_array_elements(c) x where (x->>'id')::uuid = v_cycle and x->>'status' = 'OPEN' and (x->>'reviews')::int >= 2), 'cycle opened with reviews');
  perform tst.expect_error(format('select public.hr_open_perf_cycle(%L)', v_cycle), 'already open');
  select id into v_rev from hr.perf_reviews where cycle_id = v_cycle and employee_id = tst.id('emp_w');
  perform tst.check(v_rev is not null and (select reviewer_id from hr.perf_reviews where id = v_rev) = tst.id('emp_mgr'), 'review for Ravi with his line manager as reviewer');
  perform tst.check(jsonb_array_length((select goals from hr.perf_reviews where id = v_rev)) = 2, 'empty goal titles ignored');
  perform tst.put('rev_w', v_rev);

  -- employee: self-assessment; cannot set the manager's rating
  perform tst.as_user('emp');
  t := public.hr_list_my_tasks();
  perform tst.check(exists (select 1 from jsonb_array_elements(t->'reviews') x where (x->>'id')::uuid = v_rev), 'self-assessment is a task for the employee');
  perform tst.expect_error(format('select public.hr_save_perf_review(%L, %L)', v_rev, '{"step":"MANAGER"}'), 'NOT_ALLOWED|line manager');
  r := public.hr_save_perf_review(v_rev, '{"step":"SELF","submit":true,"self_comments":"Met the targets","goals":[{"title":"Output per shift","weight":2,"self_rating":4,"rating":5},{"title":"Safety rules","weight":1,"self_rating":5}]}'::jsonb);
  perform tst.check(r->>'status' = 'MANAGER' and (r->'goals'->0->>'rating') is null and (r->'goals'->0->>'self_rating')::int = 4, 'self-assessment submitted; manager rating not settable by employee');

  -- an HR officer (no employee link, no PERF_MANAGE) cannot act as the reviewer
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_save_perf_review(%L, %L)', v_rev, '{"step":"MANAGER"}'), 'NOT_ALLOWED');
  perform tst.expect_error(format('select public.hr_get_perf_review(%L)', v_rev), 'NOT_ALLOWED');
  -- manager
  perform tst.as_user('mgr');
  perform tst.expect_error(format('select public.hr_save_perf_review(%L, %L)', v_rev, '{"step":"MANAGER","submit":true,"manager_comments":"Good work overall this half","goals":[{"title":"Output per shift","weight":2,"rating":4},{"title":"Safety rules","weight":1}]}'), 'Rate every goal');
  perform tst.expect_error(format('select public.hr_save_perf_review(%L, %L)', v_rev, '{"step":"MANAGER","submit":true,"goals":[{"title":"Output per shift","weight":2,"rating":9}]}'), '1 to 5');
  r := public.hr_save_perf_review(v_rev, '{"step":"MANAGER","submit":true,"manager_comments":"Good work overall this half","goals":[{"title":"Output per shift","weight":2,"rating":4},{"title":"Safety rules","weight":1,"rating":5}]}'::jsonb);
  perform tst.check(r->>'status' = 'HR' and (r->>'overall_rating')::numeric = 4.33, 'weighted rating 4.33: ' || (r->>'overall_rating'));
  perform tst.check((r->'goals'->0->>'self_rating')::int = 4, 'employee self-rating kept');

  -- HR finalises (someone other than the reviewer), employee acknowledges
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_save_perf_review(%L, %L)', v_rev, '{"step":"FINALISE"}'), 'NOT_ALLOWED|permission');
  perform tst.as_user('hrm');
  r := public.hr_save_perf_review(v_rev, '{"step":"FINALISE","hr_comments":"Agreed"}'::jsonb);
  perform tst.check(r->>'status' = 'ACK', 'finalised by HR');
  perform tst.as_user('emp');
  r := public.hr_get_perf_review(v_rev);
  perform tst.check((r->>'can_ack')::boolean and r->>'hr_comments' = 'Agreed', 'employee sees the final review');
  r := public.hr_save_perf_review(v_rev, '{"step":"ACK","employee_comment":"Thank you"}'::jsonb);
  perform tst.check(r->>'status' = 'DONE' and r->>'acknowledged_at' is not null, 'acknowledged');
  perform tst.as_user('aud');
  perform tst.expect_error(format('select public.hr_get_perf_review(%L)', v_rev), 'NOT_ALLOWED');
  perform tst.as_user('hrm');
  perform public.hr_close_perf_cycle(v_cycle);
  perform tst.expect_error(format('select public.hr_save_perf_review(%L, %L)', (select id from hr.perf_reviews where cycle_id = v_cycle and status <> 'DONE' limit 1), '{"step":"MANAGER"}'), 'not open');
end $$;

-- ===========================================================================
-- 2. Improvement plan: at least 6 months to improve
-- ===========================================================================
do $$
declare x jsonb;
begin
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_issue_perf_plan(%L)', jsonb_build_object('employee_id', tst.id('emp_om'), 'areas', 'Output below target for 3 months')), 'NOT_ALLOWED');
  perform tst.as_user('mgr');
  perform tst.expect_error(format('select public.hr_issue_perf_plan(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'ends_on', tst.today() + 90,
    'areas', 'Output below target for 3 months')), 'PIP_TOO_SHORT');
  x := public.hr_issue_perf_plan(jsonb_build_object('employee_id', tst.id('emp_w'), 'review_id', tst.id('rev_w'), 'areas', 'Output below target for 3 months', 'support', 'Buddy on line 1'));
  perform tst.check((x->>'ends_on')::date = (tst.today() + interval '6 months')::date and x->>'status' = 'ACTIVE', 'plan defaults to 6 months');
  perform tst.put('pip1', (x->>'id')::uuid);
  perform tst.expect_error(format('select public.hr_issue_perf_plan(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'areas', 'Another plan for the same')), 'PENDING_EXISTS');
  perform tst.as_user('emp');
  x := public.hr_ack_perf_plan(tst.id('pip1'));
  perform tst.check(x->>'acknowledged_at' is not null, 'employee acknowledged the plan');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_close_perf_plan(%L, %L, %L)', tst.id('pip1'), 'NOT_IMPROVED', 'No improvement seen at all'), 'PIP_TOO_SHORT');
  x := public.hr_close_perf_plan(tst.id('pip1'), 'IMPROVED', 'Output back on target since last month');
  perform tst.check(x->>'status' = 'IMPROVED', 'plan closed as improved');
end $$;

-- ===========================================================================
-- 3. Training and certificate expiry
-- ===========================================================================
do $$
declare c jsonb; r jsonb; v_course uuid;
begin
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_save_course(''{"code":"FIRE","name_en":"Fire safety"}''::jsonb)', 'NOT_ALLOWED|permission');
  perform tst.as_user('hro');
  c := public.hr_save_course('{"code":"fire","name_en":"Fire safety","category":"SAFETY","validity_months":12,"mandatory":true}'::jsonb);
  v_course := (select (x->>'id')::uuid from jsonb_array_elements(c) x where x->>'code' = 'FIRE');
  perform tst.check(v_course is not null, 'course code upper-cased');
  perform tst.expect_error('select public.hr_save_course(''{"code":"FIRE","name_en":"Fire again"}''::jsonb)', 'DUPLICATE');
  perform tst.expect_error(format('select public.hr_save_training(%L)', jsonb_build_object('course_id', v_course, 'employee_ids', '[]'::jsonb, 'completed_on', tst.today())), 'at least one employee');
  r := public.hr_save_training(jsonb_build_object('course_id', v_course, 'employee_ids', jsonb_build_array(tst.id('emp_w'), tst.id('emp_mgr')),
    'completed_on', tst.today() - 350, 'certificate_no', 'FS-1'));
  perform tst.check((r->>'saved')::int = 2, 'recorded for two employees');
  perform tst.check(exists (select 1 from hr.expiry_items(tst.today()) x where x.source = 'TRAINING' and x.employee_id = tst.id('emp_w') and x.days_left = 15),
    'certificate appears in the expiry tracker (15 days left)');
  perform tst.check(exists (select 1 from jsonb_array_elements(public.hr_training_gaps()) g where (g->>'employee_id')::uuid = tst.id('emp_om')), 'mandatory course missing for Fatma');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_training_gaps()) g where (g->>'employee_id')::uuid = tst.id('emp_w')), 'no gap for Ravi');
  -- renewal supersedes the old certificate
  perform public.hr_save_training(jsonb_build_object('course_id', v_course, 'employee_ids', jsonb_build_array(tst.id('emp_w')), 'completed_on', tst.today() - 1));
  perform tst.check((select count(*) from hr.expiry_items(tst.today()) x where x.source = 'TRAINING' and x.employee_id = tst.id('emp_w')) = 1
    and (select days_left from hr.expiry_items(tst.today()) x where x.source = 'TRAINING' and x.employee_id = tst.id('emp_w')) > 300, 'only the latest certificate tracked');
  perform tst.as_user('emp');
  r := public.hr_list_training('{}'::jsonb);
  perform tst.check(jsonb_array_length(r) = 2 and not exists (select 1 from jsonb_array_elements(r) x where (x->>'employee_id')::uuid <> tst.id('emp_w')), 'employee sees only own training');
  perform tst.check((r->0->>'cost') is null, 'cost hidden from the employee');
end $$;

-- ===========================================================================
-- 4. Discipline: right to respond, penalty limits, decision by someone else, deduction to payroll
-- ===========================================================================
do $$
declare d jsonb; v_case uuid; v_adj uuid;
begin
  perform tst.as_user('aud');
  perform tst.expect_error(format('select public.hr_save_case(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'category', 'SAFETY',
    'incident_date', tst.today() - 3, 'description', 'Not wearing a helmet on the shop floor')), 'NOT_ALLOWED|permission');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_save_case(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'category', 'SAFETY',
    'incident_date', tst.today() + 3, 'description', 'Not wearing a helmet on the shop floor')), 'not in the future');
  d := public.hr_save_case(jsonb_build_object('employee_id', tst.id('emp_w'), 'category', 'SAFETY', 'incident_date', tst.today() - 3,
    'description', 'Not wearing a helmet on the shop floor (second time)'));
  v_case := (d->>'id')::uuid;
  perform tst.check(d->>'status' = 'DRAFT' and d->>'ref_no' ~ '^DC-[0-9]{4}-0001$', 'case opened: ' || (d->>'ref_no'));
  perform tst.put('case1', v_case);

  perform tst.as_user('emp');
  perform tst.check(jsonb_array_length(public.hr_list_cases('{}'::jsonb)) = 0, 'employee does not see a draft case');
  perform tst.as_user('hro');
  d := public.hr_case_action(v_case, 'INVESTIGATE');
  perform tst.check(d->>'status' = 'INVESTIGATION', 'investigation started');
  perform tst.expect_error(format('select public.hr_case_action(%L, %L, %L)', v_case, 'PROPOSE', '{"penalty":"WRITTEN_WARNING"}'), 'RESPONSE_MISSING');

  perform tst.as_user('emp');
  d := public.hr_list_cases('{}'::jsonb)->0;
  perform tst.check((d->>'can_respond')::boolean and d->>'investigation_notes' is null and d->>'opened_by_name' is null, 'employee sees the case without internal notes');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'my_cases') = 1, 'response is a task for the employee');
  d := public.hr_respond_case(v_case, 'The helmet strap was broken and I asked stores for a new one.');
  perform tst.check(d->>'employee_response' is not null, 'employee responded');
  perform tst.expect_error(format('select public.hr_respond_case(%L, %L)', v_case, 'Another response text'), 'not waiting');

  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_case_action(%L, %L, %L)', v_case, 'PROPOSE', '{"penalty":"DEDUCTION","days":10}'), 'PENALTY_LIMIT');
  d := public.hr_case_action(v_case, 'PROPOSE', '{"penalty":"DEDUCTION","days":2}'::jsonb);
  perform tst.check(d->>'status' = 'PROPOSED' and (d->>'proposed_days')::numeric = 2, 'deduction of 2 days proposed');
  perform tst.expect_error(format('select public.hr_case_action(%L, %L)', v_case, 'DECIDE'), 'NOT_ALLOWED|permission');

  perform tst.as_user('hrm');
  perform tst.check(exists (select 1 from jsonb_array_elements(public.hr_list_my_tasks()->'cases') x where (x->>'id')::uuid = v_case), 'decision is a task for the HR manager');
  d := public.hr_case_action(v_case, 'DECIDE', '{"note":"Second offence"}'::jsonb);
  v_adj := (d->>'adjustment_id')::uuid;
  perform tst.check(d->>'status' = 'DECIDED' and d->>'penalty' = 'DEDUCTION' and v_adj is not null, 'decided with a payroll deduction');
  perform tst.check((select amount from hr.payroll_adjustments where id = v_adj) = round(2 * hr.daily_gross(tst.id('emp_w'), tst.today()), 3)
    and (select status || code from hr.payroll_adjustments where id = v_adj) = 'PENDINGPENALTY', 'deduction = 2 days of gross, waiting for Finance');

  perform tst.as_user('fin');
  perform tst.check(exists (select 1 from jsonb_array_elements(public.hr_list_my_tasks()->'pay_adjustments') x where (x->>'id')::uuid = v_adj), 'Finance approves the deduction');

  perform tst.as_user('emp');
  d := public.hr_respond_case(v_case, 'I appeal: stores confirmed my request for a new helmet.');
  perform tst.check(d->>'appeal' is not null, 'appeal recorded');
  perform tst.as_user('aud');
  d := public.hr_get_case(v_case);
  perform tst.check(d->>'opened_by_name' is not null and jsonb_typeof(d->'history') = 'array', 'auditor can read the full case');
  perform tst.check(not (d->>'can_decide')::boolean and not (d->>'can_edit')::boolean, 'auditor read-only');
end $$;

-- the opener cannot decide; a case can be dropped with a reason
do $$
declare d jsonb;
begin
  perform tst.as_user('hrm');
  d := public.hr_save_case(jsonb_build_object('employee_id', tst.id('emp_om'), 'category', 'ATTENDANCE', 'incident_date', tst.today() - 1,
    'description', 'Late by two hours without informing'));
  perform public.hr_case_action((d->>'id')::uuid, 'INVESTIGATE');
  d := public.hr_case_action((d->>'id')::uuid, 'PROPOSE', '{"penalty":"VERBAL_WARNING","no_response_confirmed":true}'::jsonb);
  perform tst.expect_error(format('select public.hr_case_action(%L, %L)', d->>'id', 'DECIDE'), 'SELF_APPROVAL');
  perform tst.expect_error(format('select public.hr_case_action(%L, %L, %L)', d->>'id', 'DISMISS', '{}'), 'reason');
  d := public.hr_case_action((d->>'id')::uuid, 'DISMISS', '{"note":"Bus breakdown confirmed"}'::jsonb);
  perform tst.check(d->>'status' = 'DISMISSED', 'case dropped');
end $$;

-- ===========================================================================
-- 5. Assets & PPE, accommodation
-- ===========================================================================
do $$
declare r jsonb; v_item uuid; v_fac uuid;
begin
  perform tst.as_user('hro');
  r := public.hr_save_asset_item('{"code":"HELMET","name_en":"Safety helmet","category":"PPE","unit_cost":"5.500","replace_months":24}'::jsonb);
  v_item := (select (x->>'id')::uuid from jsonb_array_elements(r) x where x->>'code' = 'HELMET');
  perform public.hr_save_asset_item('{"code":"GLOVES","name_en":"Work gloves","category":"PPE","returnable":false}'::jsonb);
  r := public.hr_issue_asset(jsonb_build_object('item_id', v_item, 'employee_ids', jsonb_build_array(tst.id('emp_w')), 'serial_no', 'H-001', 'due_return_on', tst.today() - 1));
  perform tst.check((r->>'issued')::int = 1, 'helmet issued');
  perform public.hr_issue_asset(jsonb_build_object('item_id', (select id from hr.asset_items where code = 'GLOVES'), 'employee_ids', jsonb_build_array(tst.id('emp_w')), 'qty', 2));
  perform tst.check((select status from hr.asset_issues where employee_id = tst.id('emp_w') and item_id = (select id from hr.asset_items where code = 'GLOVES')) = 'CONSUMED', 'consumables are not tracked for return');
  perform tst.put('issue_helmet', (select id from hr.asset_issues where employee_id = tst.id('emp_w') and item_id = v_item));
  perform tst.as_user('emp');
  r := public.hr_list_asset_issues('{}'::jsonb);
  perform tst.check(jsonb_array_length(r) = 2 and exists (select 1 from jsonb_array_elements(r) x where (x->>'overdue')::boolean), 'employee sees own items; overdue flagged');
  perform tst.expect_error(format('select public.hr_return_asset(%L, %L)', tst.id('issue_helmet'), '{}'), 'NOT_ALLOWED|permission');

  perform tst.as_user('hro');
  r := public.hr_save_facility(jsonb_build_object('entity_id', tst.id('ent'), 'kind', 'ACCOMMODATION', 'code', 'SOH-A1', 'name_en', 'Sohar camp room A1', 'capacity', 1));
  v_fac := (r->0->>'id')::uuid;
  r := public.hr_assign_facility(jsonb_build_object('facility_id', v_fac, 'employee_id', tst.id('emp_w'), 'place', 'Bed 1'));
  perform tst.check((r->0->>'occupied')::int = 1, 'Ravi assigned');
  perform tst.expect_error(format('select public.hr_assign_facility(%L)', jsonb_build_object('facility_id', v_fac, 'employee_id', tst.id('emp_om'))), 'FULL');
end $$;

-- ===========================================================================
-- 6. Work injuries
-- ===========================================================================
do $$
declare w jsonb; n int;
begin
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_list_injuries()', 'NOT_ALLOWED');
  perform tst.as_user('hro');
  w := public.hr_save_injury(jsonb_build_object('employee_id', tst.id('emp_w'), 'occurred_at', (now() - interval '10 days')::text, 'location', 'Line 2',
    'description', 'Hand caught in the conveyor guard', 'severity', 'LOST_TIME', 'lost_days', 3, 'body_part', 'Left hand'));
  perform tst.check(w->>'ref_no' ~ '^INJ-' and (w->>'report_overdue')::boolean, 'serious injury not reported within 7 days is flagged');
  perform tst.put('inj1', (w->>'id')::uuid);
  select count(*) into n from hr.notifications where ref_key = 'INJ:' || (w->>'id') and user_id = tst.id('user_hrm');
  perform tst.check(n = 1, 'HR manager alerted about a serious injury');
  perform tst.expect_error(format('select public.hr_close_injury(%L)', tst.id('inj1')), 'corrective action');
  w := public.hr_save_injury(w || jsonb_build_object('corrective_action', 'Guard replaced and interlock fitted', 'spf_reported_on', tst.today() - 2, 'spf_reference', 'SPF-123'));
  perform tst.check(not (w->>'report_overdue')::boolean, 'reported');
  w := public.hr_close_injury(tst.id('inj1'));
  perform tst.check(w->>'status' = 'CLOSED', 'injury closed');
end $$;

-- ===========================================================================
-- 7. Exit: notice rule, clearance list, asset return ticks the step, cancel and complete
-- ===========================================================================
do $$
declare x jsonb; v_exit uuid; t jsonb; v_lwd date;
begin
  perform tst.as_user('mgr');
  perform tst.expect_error(format('select public.hr_start_exit(%L)', jsonb_build_object('employee_id', tst.id('emp_w'))), 'NOT_ALLOWED|permission');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_start_exit(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'exit_type', 'RESIGNATION',
    'last_working_date', tst.today() + 10)), 'NOTICE_SHORT');
  perform tst.expect_error(format('select public.hr_start_exit(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'exit_type', 'RESIGNATION',
    'last_working_date', tst.today() + 30, 'non_compete_months', 30)), 'at most 24');
  x := public.hr_exit_preview(tst.id('emp_w'));
  perform tst.check((x->>'min_notice_days')::int = 30 and (x->>'open_assets')::int = 1 and (x->>'facilities')::int = 1 and x->>'open_exit' is null, 'exit preview');
  x := public.hr_start_exit(jsonb_build_object('employee_id', tst.id('emp_w'), 'exit_type', 'RESIGNATION', 'last_working_date', tst.today() + 30,
    'reason', 'Going home', 'non_compete_months', 12));
  v_exit := (x->>'id')::uuid;
  perform tst.check(x->>'employee_status' = 'NOTICE' and (x->>'notice_days')::int = 30, 'notice recorded on the employee');
  perform tst.check(exists (select 1 from jsonb_array_elements(x->'tasks') e where e->>'code' = 'ASSET_1' and (e->>'ref_id')::uuid = tst.id('issue_helmet'))
    and exists (select 1 from jsonb_array_elements(x->'tasks') e where e->>'code' like 'ACCOMMODATION_%')
    and exists (select 1 from jsonb_array_elements(x->'tasks') e where e->>'code' = 'WORK_PERMIT_CANCEL')
    and not exists (select 1 from jsonb_array_elements(x->'tasks') e where e->>'code' = 'SPF_END'), 'clearance list: helmet, room, expat steps');
  perform tst.check(not exists (select 1 from jsonb_array_elements(x->'tasks') e where e->>'title_en' like '%gloves%'), 'consumables not in the clearance list');
  perform tst.expect_error(format('select public.hr_start_exit(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'exit_type', 'RESIGNATION', 'last_working_date', tst.today() + 30)), 'PENDING_EXISTS|already');
  perform tst.expect_error(format('select public.hr_exit_task(%L, %L)', (select id from hr.exit_tasks where exit_id = v_exit and code = 'ASSET_1'), 'DONE'), 'Receive the item');
  perform tst.expect_error(format('select public.hr_exit_task(%L, %L)', (select id from hr.exit_tasks where exit_id = v_exit and code = 'AIR_TICKET'), 'NOT_NEEDED'), 'why');

  -- damaged helmet: recovery proposal + step ticked
  perform tst.expect_error(format('select public.hr_return_asset(%L, %L)', tst.id('issue_helmet'), '{"condition":"GOOD","recover_amount":"5"}'), 'damaged or lost');
  perform public.hr_return_asset(tst.id('issue_helmet'), '{"condition":"DAMAGED","recover_amount":"5.500","notes":"Shell cracked, not repairable"}'::jsonb);
  perform tst.check((select status from hr.exit_tasks where exit_id = v_exit and code = 'ASSET_1') = 'DONE', 'returning the helmet ticked the step');
  perform tst.check((select code || amount::text from hr.payroll_adjustments where id = (select recovery_adjustment_id from hr.asset_issues where id = tst.id('issue_helmet'))) = 'DAMAGE5.500', 'recovery deduction proposed');

  x := public.hr_save_exit_interview(v_exit, '{"reason_code":"FAMILY","would_return":true,"rating":4,"comments":"Good team"}'::jsonb);
  perform tst.check((select status from hr.exit_tasks where exit_id = v_exit and code = 'EXIT_INTERVIEW') = 'DONE', 'exit interview ticks its step');
  perform tst.expect_error(format('select public.hr_complete_exit(%L)', v_exit), 'STEPS_OPEN');

  -- withdrawn resignation
  x := public.hr_cancel_exit(v_exit, 'Employee withdrew the resignation');
  perform tst.check(x->>'status' = 'CANCELLED' and (select status from hr.employees where id = tst.id('emp_w')) = 'ACTIVE', 'cancelled; employee active again');

  -- end of contract (no notice minimum) completed today
  x := public.hr_start_exit(jsonb_build_object('employee_id', tst.id('emp_om'), 'exit_type', 'END_OF_CONTRACT', 'notice_given_on', tst.today() - 5, 'last_working_date', tst.today()));
  v_exit := (x->>'id')::uuid;
  perform tst.check(exists (select 1 from jsonb_array_elements(x->'tasks') e where e->>'code' = 'SPF_END')
    and not exists (select 1 from jsonb_array_elements(x->'tasks') e where e->>'code' = 'WORK_PERMIT_CANCEL'), 'Omani steps');
  for t in select jsonb_array_elements(x->'tasks') loop
    perform public.hr_exit_task((t->>'id')::uuid, 'NOT_NEEDED', 'Test run');
  end loop;
  x := public.hr_complete_exit(v_exit);
  perform tst.check(x->>'status' = 'COMPLETED' and (select status from hr.employees where id = tst.id('emp_om')) = 'SEPARATED', 'exit completed; employee separated');
  perform tst.as_user('hrm');
  perform tst.check(jsonb_array_length(public.hr_list_exits('{}'::jsonb)) = 2, 'exit list');
  perform tst.check((public.hr_time_dashboard()->'workforce'->>'exits_open')::int = 0, 'dashboard workforce block');
end $$;

do $$
declare f record; n int := 0;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.proname in ('hr_list_perf_cycles','hr_save_perf_cycle','hr_open_perf_cycle','hr_close_perf_cycle','hr_list_perf_reviews',
             'hr_get_perf_review','hr_save_perf_review','hr_list_perf_plans','hr_issue_perf_plan','hr_close_perf_plan','hr_ack_perf_plan','hr_list_courses',
             'hr_save_course','hr_list_training','hr_save_training','hr_cancel_training','hr_training_gaps','hr_list_cases','hr_save_case','hr_case_action',
             'hr_respond_case','hr_get_case','hr_list_asset_items','hr_save_asset_item','hr_list_asset_issues','hr_issue_asset','hr_return_asset',
             'hr_list_facilities','hr_save_facility','hr_assign_facility','hr_end_facility','hr_list_injuries','hr_save_injury','hr_close_injury',
             'hr_list_exits','hr_get_exit','hr_start_exit','hr_exit_task','hr_save_exit_interview','hr_complete_exit','hr_cancel_exit',
             'hr_hr_policies','hr_save_hr_policies','hr_exit_preview') loop
    perform tst.check(has_function_privilege('authenticated', f.sig, 'execute'), 'authenticated may call ' || f.sig);
    perform tst.check(not has_function_privilege('anon', f.sig, 'execute'), 'anon may not call ' || f.sig);
    n := n + 1;
  end loop;
  perform tst.check(n = 44, 'all 44 workforce API functions exist: ' || n);
  perform tst.check(not has_schema_privilege('authenticated', 'hr', 'usage'), 'hr schema stays closed');
end $$;

select 'ALL WORKFORCE TESTS PASSED' as result;
