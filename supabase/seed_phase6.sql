-- AACT HRMS — Phase 6 dummy data (performance, training, discipline, assets, housing & transport, injuries, exit).
-- DUMMY DATA ONLY: never run on the company server. Runs after seed.sql … seed_phase5.sql.
-- Uses the real API as the demo users; finds the demo people by name. Contains no destructive statements. Stops if appraisal cycles already exist.

-- Working list: current employees in employee-number order (the demo data numbers them differently on each install).
create temp table if not exists p6_rank as
  select id, row_number() over (order by employee_no) as rn from hr.employees where status <> 'SEPARATED';

do $p6$
declare
  hrm uuid; hro uuid; mgr uuid; emp uuid; v_fail int := 0; v_ent uuid; v_cycle uuid; r jsonb; x record; n int := 0;
  v_today date := (now() at time zone 'Asia/Muscat')::date; v_year int := extract(year from (now() at time zone 'Asia/Muscat'))::int;
  v_fire uuid; v_fork uuid; v_aid uuid; v_iso uuid; v_helmet uuid; v_shoes uuid; v_gloves uuid; v_laptop uuid; v_card uuid;
  v_campa uuid; v_campb uuid; v_route uuid; v_case uuid;
  e_ravi uuid; e_suresh uuid; e_hamad uuid; e_rajesh uuid; e_deepak uuid; e_asif uuid; e_bilal uuid; e_arun uuid; e_kamal uuid; e_salim uuid;
begin
  if exists (select 1 from hr.perf_cycles) then raise notice 'Phase 6 dummy data: appraisal cycles already exist — nothing done.'; return; end if;
  select id into hrm from auth.users where email = 'hr.manager@aact.test';
  select id into hro from auth.users where email = 'hr.officer@aact.test';
  select id into mgr from auth.users where email = 'manager@aact.test';
  select id into emp from auth.users where email = 'employee@aact.test';
  if hrm is null or hro is null or mgr is null or emp is null then raise notice 'Phase 6 dummy data: demo logins missing — nothing done.'; return; end if;
  select id into v_ent from hr.legal_entities order by created_at limit 1;
  select id into e_salim from hr.employees where full_name_en = 'Salim Al Harthy' order by employee_no limit 1;
  select id into e_suresh from hr.employees where full_name_en = 'Suresh Nair' order by employee_no limit 1;
  select id into e_hamad from hr.employees where full_name_en = 'Hamad Al Rawahi' order by employee_no limit 1;
  select id into e_rajesh from hr.employees where full_name_en = 'Rajesh Pillai' order by employee_no limit 1;
  select id into e_ravi from hr.employees where full_name_en = 'Ravi Kumar' order by employee_no limit 1;
  select id into e_deepak from hr.employees where full_name_en = 'Deepak Singh' order by employee_no limit 1;
  select id into e_asif from hr.employees where full_name_en = 'Asif Ali' order by employee_no limit 1;
  select id into e_kamal from hr.employees where full_name_en = 'Kamal Hossain' order by employee_no limit 1;
  select id into e_bilal from hr.employees where full_name_en = 'Bilal Ahmed' order by employee_no limit 1;
  select id into e_arun from hr.employees where full_name_en = 'Arun Das' order by employee_no limit 1;
  if v_ent is null or e_ravi is null or e_salim is null then raise notice 'Phase 6 dummy data: demo employees missing — nothing done.'; return; end if;

  -- 1. Performance: mid-year cycle opened by HR; Ravi's self-assessment sent; the line manager reviewed two of his team
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  begin
    r := public.hr_save_perf_cycle(jsonb_build_object('entity_id', v_ent, 'name', v_year || ' mid-year review', 'period_start', make_date(v_year, 1, 1),
           'period_end', make_date(v_year, 6, 30), 'due_date', v_today + 21, 'self_review', true));
    select id into v_cycle from hr.perf_cycles order by created_at desc limit 1;
    perform public.hr_open_perf_cycle(v_cycle, '[{"title":"Quality and accuracy of work","weight":2},{"title":"Productivity and targets","weight":2},{"title":"Safety and company rules","weight":1},{"title":"Teamwork and attendance","weight":1}]'::jsonb);
    perform public.hr_save_perf_cycle(jsonb_build_object('entity_id', v_ent, 'name', v_year || ' annual review', 'period_start', make_date(v_year, 1, 1),
           'period_end', make_date(v_year, 12, 31), 'due_date', make_date(v_year + 1, 1, 31)));   -- left as a draft
  exception when others then raise notice 'cycle: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', emp::text, false);
  begin
    perform public.hr_save_perf_review((select id from hr.perf_reviews where cycle_id = v_cycle and employee_id = e_ravi), jsonb_build_object('step', 'SELF', 'submit', true,
      'self_comments', 'Met the output target on line 2 every month; completed forklift training (demo).',
      'goals', '[{"title":"Quality and accuracy of work","weight":2,"self_rating":4},{"title":"Productivity and targets","weight":2,"self_rating":4},{"title":"Safety and company rules","weight":1,"self_rating":5},{"title":"Teamwork and attendance","weight":1,"self_rating":4}]'::jsonb));
  exception when others then raise notice 'self-assessment: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', mgr::text, false);
  begin
    perform public.hr_save_perf_review((select id from hr.perf_reviews where cycle_id = v_cycle and employee_id = e_suresh), jsonb_build_object('step', 'MANAGER', 'submit', true,
      'manager_comments', 'Strong supervisor; reduced scrap on line 2 by a third. Needs to delegate more (demo).',
      'goals', '[{"title":"Quality and accuracy of work","weight":2,"rating":5},{"title":"Productivity and targets","weight":2,"rating":4},{"title":"Safety and company rules","weight":1,"rating":4},{"title":"Teamwork and attendance","weight":1,"rating":3}]'::jsonb));
    perform public.hr_save_perf_review((select id from hr.perf_reviews where cycle_id = v_cycle and employee_id = e_hamad), jsonb_build_object('step', 'MANAGER', 'submit', true,
      'manager_comments', 'Reliable shift lead; meets targets consistently (demo).',
      'goals', '[{"title":"Quality and accuracy of work","weight":2,"rating":3},{"title":"Productivity and targets","weight":2,"rating":4},{"title":"Safety and company rules","weight":1,"rating":4},{"title":"Teamwork and attendance","weight":1,"rating":4}]'::jsonb));
    perform public.hr_save_perf_review((select id from hr.perf_reviews where cycle_id = v_cycle and employee_id = e_rajesh), jsonb_build_object('step', 'MANAGER', 'submit', false,
      'manager_comments', 'Draft — to discuss in the review meeting (demo).', 'goals', '[{"title":"Quality and accuracy of work","weight":2,"rating":4}]'::jsonb));
  exception when others then raise notice 'manager reviews: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  begin
    perform public.hr_save_perf_review((select id from hr.perf_reviews where cycle_id = v_cycle and employee_id = e_suresh), '{"step":"FINALISE","hr_comments":"Agreed. Nominate for the supervisor development programme (demo)."}'::jsonb);
    perform public.hr_issue_perf_plan(jsonb_build_object('employee_id', e_deepak, 'issued_on', v_today - 20,
      'areas', 'Output below the line-2 standard for three months; repeated late starts (demo).', 'support', 'Buddy operator on day shift; weekly review with the supervisor.'));
  exception when others then raise notice 'HR review / plan: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 2. Training courses and certificates (some expiring soon, one expired)
  perform set_config('request.jwt.claim.sub', hro::text, false);
  begin
    perform public.hr_save_course('{"code":"FIRE","name_en":"Fire safety and evacuation","name_ar":"السلامة من الحرائق والإخلاء","category":"SAFETY","validity_months":12,"mandatory":true,"provider":"Civil Defence approved trainer"}'::jsonb);
    perform public.hr_save_course('{"code":"FORKLIFT","name_en":"Forklift operation","name_ar":"تشغيل الرافعة الشوكية","category":"TECHNICAL","validity_months":36,"provider":"OPAL"}'::jsonb);
    perform public.hr_save_course('{"code":"FIRSTAID","name_en":"First aid at work","name_ar":"الإسعافات الأولية في العمل","category":"SAFETY","validity_months":24}'::jsonb);
    perform public.hr_save_course('{"code":"ISO9001","name_en":"ISO 9001 awareness","name_ar":"التوعية بمواصفة الأيزو 9001","category":"COMPLIANCE"}'::jsonb);
    select id into v_fire from hr.training_courses where code = 'FIRE';
    select id into v_fork from hr.training_courses where code = 'FORKLIFT';
    select id into v_aid from hr.training_courses where code = 'FIRSTAID';
    select id into v_iso from hr.training_courses where code = 'ISO9001';
    -- fire safety: most staff, in three batches (the oldest batch expires within weeks)
    perform public.hr_save_training(jsonb_build_object('course_id', v_fire, 'completed_on', v_today - 345, 'certificate_no', 'FS-B1', 'cost', '4.000',
      'employee_ids', (select jsonb_agg(id) from (select id from hr.employees where id in (select id from pg_temp.p6_rank where rn between 1 and 20) order by employee_no) q)));
    perform public.hr_save_training(jsonb_build_object('course_id', v_fire, 'completed_on', v_today - 120, 'certificate_no', 'FS-B2', 'cost', '4.000',
      'employee_ids', (select jsonb_agg(id) from (select id from hr.employees where id in (select id from pg_temp.p6_rank where rn between 21 and 45) order by employee_no) q)));
    perform public.hr_save_training(jsonb_build_object('course_id', v_fork, 'completed_on', v_today - 400, 'certificate_no', 'FL-2025', 'cost', '35.000',
      'employee_ids', jsonb_build_array(e_ravi, e_deepak, e_kamal, e_asif)));
    perform public.hr_save_training(jsonb_build_object('course_id', v_aid, 'completed_on', v_today - 760, 'certificate_no', 'FA-OLD',
      'employee_ids', jsonb_build_array(e_hamad)));
    perform public.hr_save_training(jsonb_build_object('course_id', v_aid, 'completed_on', v_today - 200, 'certificate_no', 'FA-2026',
      'employee_ids', jsonb_build_array(e_suresh, e_rajesh)));
    perform public.hr_save_training(jsonb_build_object('course_id', v_iso, 'completed_on', v_today - 90,
      'employee_ids', (select jsonb_agg(id) from (select id from hr.employees where id in (select id from pg_temp.p6_rank where rn between 1 and 16) order by employee_no) q)));
    perform public.hr_save_training(jsonb_build_object('course_id', v_fire, 'status', 'PLANNED', 'planned_on', v_today + 14,
      'employee_ids', (select jsonb_agg(id) from (select id from hr.employees where id in (select id from pg_temp.p6_rank where rn between 46 and 58) order by employee_no) q)));
  exception when others then raise notice 'training: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 3. Discipline: one under investigation, one waiting for the HR manager, one decided
  begin
    r := public.hr_save_case(jsonb_build_object('employee_id', e_deepak, 'category', 'ATTENDANCE', 'incident_date', v_today - 6,
      'description', 'Late for the morning shift four times this month without informing the supervisor (demo).'));
    perform public.hr_case_action((r->>'id')::uuid, 'INVESTIGATE');
    r := public.hr_save_case(jsonb_build_object('employee_id', e_asif, 'category', 'SAFETY', 'incident_date', v_today - 12,
      'description', 'Operated the press with the safety guard removed (demo).', 'investigation_notes', 'CCTV checked; supervisor statement taken.'));
    v_case := (r->>'id')::uuid;
    perform public.hr_case_action(v_case, 'INVESTIGATE');
    perform public.hr_case_action(v_case, 'PROPOSE', '{"penalty":"DEDUCTION","days":2,"no_response_confirmed":true}'::jsonb);
    r := public.hr_save_case(jsonb_build_object('employee_id', e_bilal, 'category', 'CONDUCT', 'incident_date', v_today - 30,
      'description', 'Argument with a colleague on the shop floor (demo).'));
    v_case := (r->>'id')::uuid;
    perform public.hr_case_action(v_case, 'INVESTIGATE');
    perform public.hr_case_action(v_case, 'PROPOSE', '{"penalty":"WRITTEN_WARNING","no_response_confirmed":true}'::jsonb);
    perform set_config('request.jwt.claim.sub', hrm::text, false);
    perform public.hr_case_action(v_case, 'DECIDE', '{"note":"First offence; written warning placed on file (demo)."}'::jsonb);
  exception when others then raise notice 'discipline: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 4. Assets & PPE
  perform set_config('request.jwt.claim.sub', hro::text, false);
  begin
    perform public.hr_save_asset_item('{"code":"HELMET","name_en":"Safety helmet","name_ar":"خوذة سلامة","category":"PPE","unit_cost":"4.500","replace_months":24}'::jsonb);
    perform public.hr_save_asset_item('{"code":"SHOES","name_en":"Safety shoes","name_ar":"حذاء سلامة","category":"PPE","unit_cost":"12.000","replace_months":12}'::jsonb);
    perform public.hr_save_asset_item('{"code":"GLOVES","name_en":"Work gloves (pair)","name_ar":"قفازات عمل (زوج)","category":"PPE","returnable":false,"unit_cost":"0.800"}'::jsonb);
    perform public.hr_save_asset_item('{"code":"COVERALL","name_en":"Coverall","name_ar":"بدلة عمل","category":"UNIFORM","unit_cost":"6.000","replace_months":12}'::jsonb);
    perform public.hr_save_asset_item('{"code":"LAPTOP","name_en":"Laptop","name_ar":"حاسوب محمول","category":"IT","unit_cost":"280.000"}'::jsonb);
    perform public.hr_save_asset_item('{"code":"CARD","name_en":"Access card","name_ar":"بطاقة دخول","category":"CARD","unit_cost":"2.000"}'::jsonb);
    select id into v_helmet from hr.asset_items where code = 'HELMET';
    select id into v_shoes from hr.asset_items where code = 'SHOES';
    select id into v_gloves from hr.asset_items where code = 'GLOVES';
    select id into v_laptop from hr.asset_items where code = 'LAPTOP';
    select id into v_card from hr.asset_items where code = 'CARD';
    for x in select id from hr.employees where id in (select id from pg_temp.p6_rank where rn between 17 and 41) loop
      perform public.hr_issue_asset(jsonb_build_object('item_id', v_helmet, 'employee_ids', jsonb_build_array(x.id), 'issued_on', v_today - 200));
      perform public.hr_issue_asset(jsonb_build_object('item_id', v_shoes, 'employee_ids', jsonb_build_array(x.id), 'issued_on', v_today - 200));
      n := n + 1;
    end loop;
    perform public.hr_issue_asset(jsonb_build_object('item_id', v_gloves, 'qty', 4, 'issued_on', v_today - 7,
      'employee_ids', (select jsonb_agg(id) from hr.employees where id in (select id from pg_temp.p6_rank where rn between 17 and 25))));
    perform public.hr_issue_asset(jsonb_build_object('item_id', v_laptop, 'employee_ids', jsonb_build_array(e_salim), 'serial_no', 'LT-0001', 'issued_on', v_today - 300));
    perform public.hr_issue_asset(jsonb_build_object('item_id', v_laptop, 'employee_ids', jsonb_build_array(e_arun), 'serial_no', 'LT-0007', 'issued_on', v_today - 250,
      'due_return_on', v_today - 2, 'notes', 'Temporary loan for the ERP project (demo)'));
    perform public.hr_issue_asset(jsonb_build_object('item_id', v_card, 'employee_ids', (select jsonb_agg(id) from hr.employees where status <> 'SEPARATED'), 'issued_on', v_today - 365));
  exception when others then raise notice 'assets: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 5. Accommodation and transport for expatriate production workers
  begin
    r := public.hr_save_facility(jsonb_build_object('entity_id', v_ent, 'kind', 'ACCOMMODATION', 'code', 'CAMP-A', 'name_en', 'Sohar labour camp — block A',
      'name_ar', 'سكن العمال في صحار — المبنى أ', 'address', 'Sohar Industrial Estate, road 12', 'capacity', 24));
    r := public.hr_save_facility(jsonb_build_object('entity_id', v_ent, 'kind', 'ACCOMMODATION', 'code', 'FLAT-1', 'name_en', 'Staff flat, Falaj Al Qabail',
      'name_ar', 'شقة الموظفين، فلج القبائل', 'capacity', 3));
    r := public.hr_save_facility(jsonb_build_object('entity_id', v_ent, 'kind', 'TRANSPORT', 'code', 'R1', 'name_en', 'Bus — camp to factory (day shift)',
      'name_ar', 'حافلة — السكن إلى المصنع (الوردية الصباحية)', 'address', 'Camp A 06:15 → Gate 2 06:40', 'capacity', 30, 'vehicle_no', '12345 AB'));
    select id into v_campa from hr.facilities where code = 'CAMP-A';
    select id into v_campb from hr.facilities where code = 'FLAT-1';
    select id into v_route from hr.facilities where code = 'R1';
    n := 0;
    for x in select e.id from hr.employees e where e.nationality <> 'OM' and e.id in (select id from pg_temp.p6_rank where rn between 17 and 55) order by e.employee_no limit 20 loop
      n := n + 1;
      perform public.hr_assign_facility(jsonb_build_object('facility_id', v_campa, 'employee_id', x.id, 'place', 'Room ' || ((n + 3) / 4) || ', bed ' || (((n - 1) % 4) + 1), 'from_date', v_today - 180));
      perform public.hr_assign_facility(jsonb_build_object('facility_id', v_route, 'employee_id', x.id, 'place', 'Camp A gate', 'from_date', v_today - 180));
    end loop;
    perform public.hr_assign_facility(jsonb_build_object('facility_id', v_campb, 'employee_id', e_arun, 'place', 'Room 2', 'from_date', v_today - 250));
  exception when others then raise notice 'facilities: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 6. Work injuries: a closed one, an open serious one not yet reported, a first-aid case
  begin
    r := public.hr_save_injury(jsonb_build_object('employee_id', e_kamal, 'occurred_at', (now() - interval '75 days')::text, 'location', 'Line 1, cutting station',
      'description', 'Cut on the right hand while changing a blade (demo).', 'injury_type', 'Laceration', 'body_part', 'Right hand', 'severity', 'MEDICAL', 'lost_days', 0,
      'root_cause', 'Blade changed without cut-resistant gloves.', 'corrective_action', 'Cut-resistant gloves issued; blade-change procedure updated and briefed.',
      'spf_reported_on', v_today - 72, 'spf_reference', 'SPF-WI-2026-0412'));
    perform public.hr_close_injury((r->>'id')::uuid);
    perform public.hr_save_injury(jsonb_build_object('employee_id', e_asif, 'occurred_at', (now() - interval '9 days')::text, 'location', 'Warehouse, rack B',
      'description', 'Foot crushed by a falling pallet while unloading (demo).', 'injury_type', 'Fracture', 'body_part', 'Left foot', 'severity', 'LOST_TIME', 'lost_days', 14,
      'witnesses', 'Ram Thapa, Jamal Mia', 'root_cause', 'Damaged pallet not removed from use.'));
    perform public.hr_save_injury(jsonb_build_object('employee_id', e_ravi, 'occurred_at', (now() - interval '2 days')::text, 'location', 'Line 2',
      'description', 'Minor burn on the forearm from a hot pipe (demo).', 'severity', 'FIRST_AID', 'corrective_action', 'Pipe insulation repaired.'));
  exception when others then raise notice 'injuries: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 7. Exit: Arun Das resigned (already serving notice) — clearance in progress
  begin
    r := public.hr_start_exit(jsonb_build_object('employee_id', e_arun, 'exit_type', 'RESIGNATION',
      'notice_given_on', (select notice_given_date from hr.employees where id = e_arun), 'last_working_date', (select last_working_date from hr.employees where id = e_arun),
      'reason', 'Returning to India for family reasons (demo).', 'pay_in_lieu', (select last_working_date - notice_given_date < 30 from hr.employees where id = e_arun)));
    perform public.hr_exit_task((select id from hr.exit_tasks where exit_id = (r->>'id')::uuid and code = 'HANDOVER'), 'DONE', 'Handover notes given to Hamad Al Rawahi');
    perform public.hr_save_exit_interview((r->>'id')::uuid, '{"reason_code":"FAMILY","would_return":true,"rating":4,"comments":"Good team; would come back if a role opens in Muscat (demo)."}'::jsonb);
  exception when others then raise notice 'exit: %', sqlerrm; v_fail := v_fail + 1; end;

  perform set_config('request.jwt.claim.sub', '', false);
  raise notice 'Phase 6 dummy data loaded: % reviews, % training records, % cases, % items issued, % housing/transport places, % injuries, % exits, % steps skipped.',
    (select count(*) from hr.perf_reviews), (select count(*) from hr.training_records), (select count(*) from hr.disciplinary_cases),
    (select count(*) from hr.asset_issues), (select count(*) from hr.facility_assignments), (select count(*) from hr.work_injuries),
    (select count(*) from hr.exit_cases), v_fail;
end
$p6$;
