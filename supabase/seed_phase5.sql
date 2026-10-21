-- AACT HRMS — Phase 5 dummy data (recruitment & onboarding). DUMMY DATA ONLY: never run on the company server.
-- Runs after seed.sql … seed_phase4.sql. Uses the real API as the demo users: the line manager raises a requisition,
-- HR approves, the HR officer adds candidates and prepares offers, the HR manager approves offers, the manager interviews.
-- Contains no DROP or DELETE statements. Stops if requisitions already exist.

do $p5$
declare
  mgr uuid; hro uuid; hrm uuid; v_fail int := 0; r jsonb; a jsonb; v_req1 uuid; v_req2 uuid; v_req3 uuid;
  v_dept uuid; v_qc uuid; v_hrd uuid; v_job uuid; v_qci uuid; v_hroj uuid; v_cat uuid; v_wrk uuid; v_loc uuid; v_mgr_emp uuid;
  v_app uuid; v_ofr uuid; v_today date := (now() at time zone 'Asia/Muscat')::date; x record; n int := 0;
begin
  if exists (select 1 from hr.job_requisitions) then raise notice 'Phase 5 dummy data: requisitions already exist — nothing done.'; return; end if;
  select id into mgr from auth.users where email = 'manager@aact.test';
  select id into hro from auth.users where email = 'hr.officer@aact.test';
  select id into hrm from auth.users where email = 'hr.manager@aact.test';
  if mgr is null or hro is null or hrm is null then raise notice 'Phase 5 dummy data: demo logins missing — nothing done.'; return; end if;
  select employee_id into v_mgr_emp from hr.user_profiles where user_id = mgr;
  select id into v_dept from hr.departments where code = 'PROD' limit 1;
  select id into v_qc from hr.departments where code = 'QC' limit 1;
  select id into v_hrd from hr.departments where code = 'HR' limit 1;
  select id into v_job from hr.job_titles where code = 'OPR' limit 1;
  select id into v_qci from hr.job_titles where code = 'QCI' limit 1;
  select id into v_hroj from hr.job_titles where code = 'HRO' limit 1;
  select id into v_cat from hr.employee_categories where code = 'STAFF' limit 1;
  select id into v_wrk from hr.employee_categories where code = 'WRK' limit 1;
  select id into v_loc from hr.locations where code = 'SOHAR' limit 1;
  if v_dept is null or v_job is null or v_cat is null then raise notice 'Phase 5 dummy data: demo masters missing — nothing done.'; return; end if;

  -- 1. requisitions: machine operators (raised by the line manager), a quality inspector, an HR officer (Omani-only job)
  perform set_config('request.jwt.claim.sub', mgr::text, false);
  begin
    r := public.hr_save_requisition(jsonb_build_object('department_id', v_dept, 'job_title_id', v_job, 'category_id', coalesce(v_wrk, v_cat), 'location_id', v_loc,
           'positions', 3, 'salary_min', '220', 'salary_max', '320', 'target_date', (v_today + 45)::text,
           'justification', 'Second shift on line 2 starts in January; three operators needed (demo).'));
    v_req1 := (r->>'id')::uuid;
  exception when others then raise notice 'requisition 1: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', hro::text, false);
  begin
    r := public.hr_save_requisition(jsonb_build_object('department_id', coalesce(v_qc, v_dept), 'job_title_id', coalesce(v_qci, v_job), 'category_id', v_cat,
           'positions', 1, 'nationality_rule', 'OMANI_PREFERRED', 'salary_min', '450', 'salary_max', '600',
           'justification', 'New ISO 9001 audit requirement: one more quality inspector (demo).'));
    v_req2 := (r->>'id')::uuid;
    if v_hroj is not null then
      r := public.hr_save_requisition(jsonb_build_object('department_id', coalesce(v_hrd, v_dept), 'job_title_id', v_hroj, 'category_id', v_cat,
             'positions', 1, 'justification', 'Additional HR officer for recruitment and onboarding (demo).'));
      v_req3 := (r->>'id')::uuid;   -- left waiting for approval
    end if;
  exception when others then raise notice 'requisitions 2/3: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  begin
    perform public.hr_decide_requisition(v_req1, true, 'Budgeted for 2027 (demo)');
    perform public.hr_decide_requisition(v_req2, true, null);
  exception when others then raise notice 'approvals: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 2. candidates in different stages
  perform set_config('request.jwt.claim.sub', hro::text, false);
  for x in select * from (values
      (1, 'Arjun Nair', null, 'IN', 'M', '1994-05-10', 'arjun.nair.demo@example.com', '+91 98470 11111', false, 6.0, 'AGENCY', 'ITI fitter'),
      (2, 'Mohammed Rafiq', null, 'BD', 'M', '1991-11-02', 'm.rafiq.demo@example.com', '+968 9123 4400', true, 8.0, 'REFERRAL', 'Diploma, mechanical'),
      (3, 'Said Al Balushi', 'سعيد البلوشي', 'OM', 'M', '1999-03-21', 'said.b.demo@example.com', '+968 9221 7788', true, 2.0, 'MOL_PORTAL', 'Diploma, industrial maintenance'),
      (4, 'Ramesh Thapa', null, 'NP', 'M', '1996-07-15', 'ramesh.t.demo@example.com', '+977 984 1234567', false, 4.0, 'AGENCY', 'Machine operator certificate'),
      (5, 'Joseph D''Souza', null, 'IN', 'M', '1989-01-30', 'joseph.d.demo@example.com', '+968 9333 1212', true, 11.0, 'WALK_IN', 'BSc')) v(k, en, ar, nat, g, dob, em, ph, inom, xp, src, q)
  loop
    begin
      a := public.hr_add_application(jsonb_build_object('requisition_id', v_req1, 'candidate', jsonb_build_object('full_name_en', x.en, 'full_name_ar', x.ar,
             'nationality', x.nat, 'gender', x.g, 'date_of_birth', x.dob, 'email', x.em, 'phone', x.ph, 'in_oman', x.inom, 'experience_years', x.xp,
             'source', x.src, 'qualification', x.q, 'civil_number', case when x.nat = 'OM' then '99' || lpad(x.k::text, 6, '0') end)));
      v_app := (a->>'id')::uuid;
      if x.k = 1 then         -- interviewed, offer accepted, onboarding started
        a := public.hr_schedule_interview(jsonb_build_object('application_id', v_app, 'scheduled_at', (now() - interval '6 days')::text, 'mode', 'VIDEO', 'location', 'Teams', 'interviewer_id', mgr));
        perform set_config('request.jwt.claim.sub', mgr::text, false);
        perform public.hr_record_interview((a->'interviews'->0->>'id')::uuid, '{"status":"DONE","rating":4,"recommendation":"HIRE","feedback":"Good machine set-up skills and safety awareness (demo)."}'::jsonb);
        perform set_config('request.jwt.claim.sub', hro::text, false);
        a := public.hr_save_offer(jsonb_build_object('application_id', v_app, 'start_date', (v_today + 40)::text, 'category_id', coalesce(v_wrk, v_cat), 'location_id', v_loc,
               'contract_type', 'FIXED_TERM', 'contract_months', 24, 'probation_months', 3, 'notice_days', 30, 'valid_until', (v_today + 10)::text,
               'benefits', 'Return air ticket every two years; shared accommodation and transport (demo)',
               'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','240'), jsonb_build_object('code','HOUSING','amount','60'), jsonb_build_object('code','TRANSPORT','amount','20'))));
        v_ofr := (a->'offers'->0->>'id')::uuid;
        perform set_config('request.jwt.claim.sub', hrm::text, false);
        perform public.hr_decide_offer(v_ofr, true, 'Within band (demo)');
        perform set_config('request.jwt.claim.sub', hro::text, false);
        a := public.hr_offer_response(v_ofr, true, 'Signed copy received by e-mail (demo)');
        perform public.hr_set_onboarding_task((select t.id from hr.onboarding_tasks t where t.application_id = v_app and t.code = 'LABOUR_CLEARANCE'), 'DONE', 'Work permit application submitted (demo)');
      elsif x.k = 2 then      -- offer waiting for the HR manager
        a := public.hr_schedule_interview(jsonb_build_object('application_id', v_app, 'scheduled_at', (now() - interval '3 days')::text, 'interviewer_id', mgr));
        perform set_config('request.jwt.claim.sub', mgr::text, false);
        perform public.hr_record_interview((a->'interviews'->0->>'id')::uuid, '{"status":"DONE","rating":5,"recommendation":"HIRE","feedback":"Very experienced; already in Oman, can transfer quickly (demo)."}'::jsonb);
        perform set_config('request.jwt.claim.sub', hro::text, false);
        perform public.hr_save_offer(jsonb_build_object('application_id', v_app, 'start_date', (v_today + 21)::text, 'category_id', coalesce(v_wrk, v_cat), 'location_id', v_loc,
               'contract_type', 'FIXED_TERM', 'contract_months', 24, 'probation_months', 3,
               'lines', jsonb_build_array(jsonb_build_object('code','BASIC','amount','280'), jsonb_build_object('code','HOUSING','amount','60'))));
      elsif x.k = 3 then      -- Omani candidate: interview scheduled with the line manager tomorrow
        perform public.hr_schedule_interview(jsonb_build_object('application_id', v_app, 'scheduled_at', (now() + interval '1 day')::text, 'mode', 'IN_PERSON',
               'location', 'Sohar factory, meeting room 1', 'interviewer_id', mgr));
      elsif x.k = 4 then
        perform public.hr_move_application(v_app, 'SHORTLISTED', null);
      else
        perform public.hr_move_application(v_app, 'REJECTED', 'Salary expectation well above the range (demo)');
      end if;
      n := n + 1;
    exception when others then raise notice 'candidate %: %', x.en, sqlerrm; v_fail := v_fail + 1; end;
    perform set_config('request.jwt.claim.sub', hro::text, false);
  end loop;

  -- 3. one Omani candidate for the quality-inspector position
  begin
    perform public.hr_add_application(jsonb_build_object('requisition_id', v_req2, 'candidate', jsonb_build_object('full_name_en', 'Maryam Al Riyami',
      'full_name_ar', 'مريم الريامية', 'nationality', 'OM', 'gender', 'F', 'date_of_birth', '1997-09-09', 'email', 'maryam.r.demo@example.com',
      'phone', '+968 9555 3434', 'civil_number', '99000006', 'experience_years', 3, 'qualification', 'BSc Chemistry', 'source', 'WEBSITE')));
  exception when others then raise notice 'QC candidate: %', sqlerrm; v_fail := v_fail + 1; end;

  perform set_config('request.jwt.claim.sub', '', false);
  raise notice 'Phase 5 dummy data loaded: % requisitions, % candidates, % interviews, % offers, % onboarding steps, % steps skipped.',
    (select count(*) from hr.job_requisitions), (select count(*) from hr.candidates), (select count(*) from hr.interviews),
    (select count(*) from hr.job_offers), (select count(*) from hr.onboarding_tasks), v_fail;
end
$p5$;
