-- AACT HRMS — Phase 4 dummy data (self-service & letters). DUMMY DATA ONLY: never run on the company server.
-- Runs after seed.sql, seed_phase2.sql and seed_phase3.sql. Uses the real API as the demo users, so the
-- separation of duties is respected: the employee asks, the HR officer prepares/decides, the HR manager approves letters.
-- Contains no DROP statements. Stops if letters already exist.

do $p4$
declare
  emp uuid; mgr uuid; hro uuid; hrm uuid; v_fail int := 0; r jsonb; v_id uuid;
begin
  if exists (select 1 from hr.letters) then raise notice 'Phase 4 dummy data: letters already exist — nothing done.'; return; end if;
  select id into emp from auth.users where email = 'employee@aact.test';
  select id into mgr from auth.users where email = 'manager@aact.test';
  select id into hro from auth.users where email = 'hr.officer@aact.test';
  select id into hrm from auth.users where email = 'hr.manager@aact.test';
  if emp is null or hro is null or hrm is null then raise notice 'Phase 4 dummy data: demo logins missing — nothing done.'; return; end if;
  if (select employee_id from hr.user_profiles where user_id = emp) is null then
    raise notice 'Phase 4 dummy data: employee@aact.test is not linked to an employee — nothing done.'; return;
  end if;

  -- 1. the employee: one issued salary certificate, one NOC waiting for approval, one employment letter just requested
  perform set_config('request.jwt.claim.sub', emp::text, false);
  begin
    r := public.hr_request_letter('{"letter_type":"SALARY_CERT","addressee":"The Manager, Bank Muscat, Sohar Branch","purpose":"personal loan application","language":"BOTH"}'::jsonb);
    perform set_config('request.jwt.claim.sub', hro::text, false);
    perform public.hr_prepare_letter((r->>'id')::uuid, '{}'::jsonb);
    perform set_config('request.jwt.claim.sub', hrm::text, false);
    perform public.hr_decide_letter((r->>'id')::uuid, true, 'Checked against the salary record (demo)');
  exception when others then raise notice 'salary certificate: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', emp::text, false);
  begin
    r := public.hr_request_letter(jsonb_build_object('letter_type','NOC','language','EN','addressee','Embassy of India, Muscat','purpose','annual leave',
           'details', jsonb_build_object('destination','India','from_date', (hr.today() + 40)::text, 'to_date', (hr.today() + 61)::text)));
    perform set_config('request.jwt.claim.sub', hro::text, false);
    perform public.hr_prepare_letter((r->>'id')::uuid, '{}'::jsonb);
  exception when others then raise notice 'NOC: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', emp::text, false);
  begin
    r := public.hr_request_letter('{"letter_type":"EMPLOYMENT","language":"AR","addressee":"شرطة عمان السلطانية","purpose":"تجديد رخصة القيادة"}'::jsonb);
  exception when others then raise notice 'employment letter: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 2. change requests: an approved address change, a pending phone change and a pending correction (PDPL)
  begin
    r := public.hr_request_change('{"kind":"PROFILE","changes":{"city":"Sohar","wilayat":"Sohar","governorate":"North Al Batinah"},"reason":"Moved house (demo)"}'::jsonb);
    perform set_config('request.jwt.claim.sub', hro::text, false);
    perform public.hr_decide_change((r->>'id')::uuid, true, 'OK (demo)');
    perform set_config('request.jwt.claim.sub', emp::text, false);
    r := public.hr_request_change('{"kind":"PROFILE","changes":{"alt_phone":"+968 9555 1234","personal_email":"ravi.k.demo@example.com"},"reason":"New personal number (demo)"}'::jsonb);
    r := public.hr_request_change('{"kind":"CORRECTION","field":"full_name_ar","reason":"My name in Arabic should be written رافي كومار (demo)."}'::jsonb);
  exception when others then raise notice 'changes: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 3. the line manager asks for an employment letter too (waiting for HR)
  if mgr is not null and (select employee_id from hr.user_profiles where user_id = mgr) is not null then
    perform set_config('request.jwt.claim.sub', mgr::text, false);
    begin
      r := public.hr_request_letter('{"letter_type":"EMPLOYMENT","include_salary":true,"addressee":"Oman Arab Bank","purpose":"credit card","language":"BOTH"}'::jsonb);
    exception when others then raise notice 'manager letter: %', sqlerrm; v_fail := v_fail + 1; end;
  end if;

  -- 4. letter settings (demo signatory)
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  begin
    perform public.hr_save_letter_settings('{"signatory_en":"HR Manager","signatory_ar":"مدير الموارد البشرية","signatory_name_en":"Demo HR Manager","signatory_name_ar":"مدير الموارد البشرية (تجريبي)","footer_en":"This is a demonstration letter with dummy data.","footer_ar":"هذا خطاب تجريبي ببيانات وهمية.","verify_base_url":""}'::jsonb);
  exception when others then raise notice 'letter settings: %', sqlerrm; v_fail := v_fail + 1; end;

  perform set_config('request.jwt.claim.sub', '', false);
  raise notice 'Phase 4 dummy data loaded: % letters (% issued), % change requests, % steps skipped.',
    (select count(*) from hr.letters), (select count(*) from hr.letters where status = 'ISSUED'), (select count(*) from hr.change_requests), v_fail;
end
$p4$;
