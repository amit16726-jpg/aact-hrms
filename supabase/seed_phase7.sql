-- AACT HRMS — Phase 7 dummy data (privacy notice, consents, data-subject requests, breach log).
-- DUMMY DATA ONLY: never run on the company server. Runs after seed.sql … seed_phase6.sql.
-- Uses the real API as the demo users. Contains no destructive statements. Stops if a notice is already published.

do $p7$
declare hrm uuid; emp uuid; adm uuid; v_fail int := 0; r jsonb; v_id uuid; v_emp2 uuid;
begin
  if exists (select 1 from hr.privacy_notices where status <> 'DRAFT') then raise notice 'Phase 7 dummy data: a privacy notice is already published — nothing done.'; return; end if;
  select id into hrm from auth.users where email = 'hr.manager@aact.test';
  select id into emp from auth.users where email = 'employee@aact.test';
  select id into adm from auth.users where email = 'admin@aact.test';
  if hrm is null or emp is null or adm is null then raise notice 'Phase 7 dummy data: demo logins missing — nothing done.'; return; end if;

  -- the template notice (version 1) is published by the HR manager; the employee acknowledges it and answers the optional consents
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  begin
    perform public.hr_publish_notice((select id from hr.privacy_notices where version = 1));
    perform public.hr_save_pdpl_settings('{"dpo_name":"HR Manager (demo)","dpo_email":"privacy@aact.test"}'::jsonb);
  exception when others then raise notice 'notice: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', emp::text, false);
  begin
    perform public.hr_ack_notice();
    perform public.hr_set_consent('PHOTO_DIRECTORY', true);
    perform public.hr_set_consent('MARKETING_MEDIA', false);
    perform public.hr_submit_dsr('ACCESS', 'Please send me a copy of the personal data you hold about me (demo).');
  exception when others then raise notice 'employee: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', adm::text, false);
  begin
    perform public.hr_ack_notice();
  exception when others then raise notice 'admin ack: %', sqlerrm; v_fail := v_fail + 1; end;

  -- requests recorded by HR, and the breach log
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  begin
    select id into v_emp2 from hr.employees where status = 'SEPARATED' order by separation_date desc nulls last limit 1;
    r := public.hr_save_dsr(jsonb_build_object('employee_id', v_emp2, 'contact', 'Letter received at reception', 'kind', 'CORRECTION',
      'details', 'Former employee asks to correct the spelling of his name on the experience letter (demo).', 'received_on', (now() at time zone 'Asia/Muscat')::date - 20,
      'identity_checked', true));
    perform public.hr_close_dsr((r->>'id')::uuid, 'COMPLETED', 'Name corrected in the record; new experience letter issued (demo).');
    perform public.hr_save_dsr(jsonb_build_object('requester_name', 'Applicant (demo)', 'contact', 'applicant.demo@example.com', 'kind', 'ERASURE',
      'details', 'Asks us to erase his CV after an unsuccessful application (demo).', 'received_on', (now() at time zone 'Asia/Muscat')::date - 40));
    r := public.hr_save_breach(jsonb_build_object('discovered_at', now() - interval '30 days', 'occurred_at', now() - interval '31 days', 'risk', 'LOW', 'people_affected', 1,
      'description', 'Payslip of one employee printed to the wrong floor printer and collected by a colleague (demo).', 'data_kinds', 'Name, salary',
      'containment', 'Payslip recovered the same day; printer queue restricted to HR.', 'contained_at', now() - interval '30 days',
      'not_notified_reason', 'Single document, recovered within the hour, no risk to the employee (demo).'));
    perform public.hr_close_breach((r->>'id')::uuid);
    perform public.hr_save_breach(jsonb_build_object('discovered_at', now() - interval '20 hours', 'risk', 'MEDIUM', 'people_affected', 12,
      'description', 'Shared drive folder with visa copies was accessible to all staff for two days (demo).', 'data_kinds', 'Passport and visa copies',
      'containment', 'Folder permissions corrected; access log under review.', 'contained_at', now() - interval '18 hours'));
  exception when others then raise notice 'requests/breaches: %', sqlerrm; v_fail := v_fail + 1; end;

  perform set_config('request.jwt.claim.sub', '', false);
  raise notice 'Phase 7 dummy data loaded: notice v% published, % acknowledgements, % requests, % breaches, % steps skipped.',
    (select version from hr.privacy_notices where status = 'PUBLISHED'), (select count(*) from hr.consents where purpose = 'NOTICE'),
    (select count(*) from hr.dsr_requests), (select count(*) from hr.data_breaches), v_fail;
end
$p7$;
