-- AACT HRMS — Phase 4 (self-service & letters) database tests.
-- Runs after 10_priority1, 20_phase2 and 30_payroll (uses their users: user_emp is linked to employee emp_w,
-- whose line manager emp_mgr is linked to user_mgr). Every business call goes through the public API as "authenticated".

set client_min_messages = warning;
reset role;

-- Fixture: make sure the employee has an approved salary and a bank account to change
do $$
declare r uuid;
begin
  if hr.comp_on(tst.id('emp_w'), hr.today()) is null then
    insert into hr.compensation_revisions(employee_id, effective_from, reason, status, total_monthly, proposed_by, decided_by, decided_at)
    values (tst.id('emp_w'), hr.today() - 60, 'JOIN', 'APPROVED', 650, tst.id('user_hro'), tst.id('user_hrm'), now()) returning id into r;
    insert into hr.compensation_lines(revision_id, employee_id, component_code, amount)
    values (r, tst.id('emp_w'), 'BASIC', 500), (r, tst.id('emp_w'), 'HOUSING', 150);
  end if;
  update hr.employee_bank_accounts set status = 'SUPERSEDED' where employee_id = tst.id('emp_w') and status = 'PENDING';
  update hr.user_profiles set email = 'emp@aact.test' where user_id = tst.id('user_emp');
  update hr.employees set mobile = coalesce(mobile, '+968 9000 0001') where id = tst.id('emp_w');
end $$;
grant execute on all functions in schema tst to authenticated;
set role authenticated;

-- ===========================================================================
-- 1. Portal and profile change requests
-- ===========================================================================
do $$
declare v jsonb; c jsonb; v_old text;
begin
  perform tst.as_user('emp');
  v := public.hr_my_portal();
  perform tst.check((v->>'linked')::boolean, 'employee sees the portal');
  perform tst.check(v->'employee'->>'employee_id' = tst.id('emp_w')::text, 'portal shows own record');
  perform tst.check(v->'profile_fields' ? 'mobile' and not (v->'profile_fields' ? 'full_name_en'), 'only safe fields are self-service');
  v_old := v->'employee'->>'mobile';

  perform tst.expect_error('select public.hr_request_change(''{"kind":"PROFILE","changes":{}}''::jsonb)', 'NO_CHANGE');
  perform tst.expect_error('select public.hr_request_change(''{"kind":"PROFILE","changes":{"mobile":"abc"}}''::jsonb)', 'INVALID_PHONE');
  perform tst.expect_error('select public.hr_request_change(''{"kind":"PROFILE","changes":{"personal_email":"nope"}}''::jsonb)', 'INVALID_EMAIL');
  perform tst.expect_error('select public.hr_request_change(''{"kind":"PROFILE","changes":{"mobile":""}}''::jsonb)', 'cannot be removed');
  -- a field outside the list is ignored, not changed
  perform tst.expect_error('select public.hr_request_change(''{"kind":"PROFILE","changes":{"full_name_en":"Hacker"}}''::jsonb)', 'NO_CHANGE');

  c := public.hr_request_change(jsonb_build_object('kind','PROFILE','changes', jsonb_build_object('mobile','+968 9999 0000','city','Sohar','address_country','om'),
                                'reason','Moved to Sohar'));
  perform tst.check(c->>'status' = 'PENDING' and (c->>'due_date')::date = (now() at time zone 'Asia/Muscat')::date + 45, 'request pending with the 45-day PDPL due date');
  perform tst.check(c->'changes'->'mobile'->>'old' is not distinct from v_old and c->'changes'->'mobile'->>'new' = '+968 9999 0000', 'old and new values kept');
  perform tst.check(c->'changes'->'address_country'->>'new' = 'OM', 'country code normalised');
  perform tst.check(not (c->>'can_decide')::boolean and (c->>'can_cancel')::boolean, 'employee can cancel but not decide');
  perform tst.put('chg1', (c->>'id')::uuid);
  perform tst.expect_error('select public.hr_request_change(''{"kind":"PROFILE","changes":{"city":"Nizwa"}}''::jsonb)', 'PENDING_EXISTS');
  perform tst.expect_error(format('select public.hr_decide_change(%L, true)', tst.id('chg1')), 'NOT_ALLOWED|permission');

  -- HR officer sees it as a task and approves
  perform tst.as_user('hro');
  v := public.hr_list_my_tasks();
  perform tst.check(jsonb_array_length(v->'changes') = 1, 'HR officer has the change request as a task');
  perform tst.check((public.hr_time_dashboard()->'tasks'->>'changes')::int = 1, 'dashboard counts it');
  perform tst.expect_error(format('select public.hr_decide_change(%L, false, '''')', tst.id('chg1')), 'reason for rejecting');
  c := public.hr_decide_change(tst.id('chg1'), true, 'Checked');
  perform tst.check(c->>'status' = 'APPROVED', 'approved');
  perform tst.expect_error(format('select public.hr_decide_change(%L, true)', tst.id('chg1')), 'NOT_PENDING');
end $$;

reset role;
do $$
begin
  perform tst.check((select mobile from hr.employees where id = tst.id('emp_w')) = '+968 9999 0000', 'mobile updated on approval');
  perform tst.check((select city from hr.employees where id = tst.id('emp_w')) = 'Sohar', 'city updated on approval');
  perform tst.check(exists (select 1 from hr.employee_events where employee_id = tst.id('emp_w') and event_type = 'PERSONAL_UPDATE'
                            and details->>'request_id' = tst.id('chg1')::text), 'history event written');
  perform tst.check(exists (select 1 from hr.notifications where user_id = tst.id('user_emp') and ref_key = 'CHGD:' || tst.id('chg1')), 'employee told');
  perform tst.check(exists (select 1 from hr.audit_log where table_name = 'change_requests'), 'change requests are audited');
end $$;
set role authenticated;

-- ===========================================================================
-- 2. Emergency contacts, bank change (HR check then Finance), correction, cancel
-- ===========================================================================
do $$
declare c jsonb; v jsonb;
begin
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_request_change(''{"kind":"EMERGENCY","contacts":[]}''::jsonb)', 'at least one');
  c := public.hr_request_change(jsonb_build_object('kind','EMERGENCY','contacts', jsonb_build_array(
         jsonb_build_object('name','Priya Kumar','relationship','Spouse','phone','+91 98450 00000','is_next_of_kin', true),
         jsonb_build_object('name','Anil Kumar','relationship','Brother','phone','+968 9000 1111'))));
  perform tst.put('chg2', (c->>'id')::uuid);

  perform tst.expect_error('select public.hr_request_change(''{"kind":"BANK","bank_name":"BM","account_name":"R K","account_number":"12"}''::jsonb)', 'Account number');
  c := public.hr_request_change(jsonb_build_object('kind','BANK','bank_name','Bank Muscat','account_name','Ravi Kumar',
         'account_number','0301 0000 9999','iban','OM810180000001299123456','swift_code','bmusomrx'));
  perform tst.check(c->'changes'->>'account_number' = '030100009999' and c->'changes'->>'swift_code' = 'BMUSOMRX', 'bank details normalised');
  perform tst.put('chg3', (c->>'id')::uuid);

  perform tst.expect_error('select public.hr_request_change(''{"kind":"CORRECTION","reason":"wrong"}''::jsonb)', 'at least 10');
  c := public.hr_request_change(jsonb_build_object('kind','CORRECTION','field','date_of_birth','reason','My date of birth is 2 July 1992, not 1 July.'));
  perform tst.put('chg4', (c->>'id')::uuid);
  c := public.hr_request_change(jsonb_build_object('kind','CORRECTION','reason','Second correction request is allowed at the same time.'));
  c := public.hr_cancel_change((c->>'id')::uuid);
  perform tst.check(c->>'status' = 'CANCELLED', 'employee cancels own request');

  -- the auditor sees bank details masked
  perform tst.as_user('aud');
  v := (select x from jsonb_array_elements(public.hr_list_change_requests('PENDING')) x where x->>'id' = tst.id('chg3')::text);
  perform tst.check(v->'changes'->>'account_number' like '%9999' and v->'changes'->>'account_number' like '•%', 'bank number masked for the auditor');
  perform tst.check(v->'changes'->>'iban' is null, 'IBAN hidden from the auditor');

  perform tst.as_user('hro');
  perform public.hr_decide_change(tst.id('chg2'), true, null);
  perform tst.expect_error(format('select public.hr_decide_change(%L, true, null)', tst.id('chg4')), 'what was corrected');
  perform public.hr_decide_change(tst.id('chg4'), true, 'Date of birth corrected from the civil card.');
  c := public.hr_decide_change(tst.id('chg3'), true, 'Bank letter seen');
  perform tst.check(c->>'status' = 'APPROVED', 'bank request checked by HR');
end $$;

reset role;
do $$
declare v_bank uuid;
begin
  perform tst.check((select count(*) from hr.emergency_contacts where employee_id = tst.id('emp_w') and is_active) = 2, 'emergency contacts replaced');
  select result_ref into v_bank from hr.change_requests where id = tst.id('chg3');
  perform tst.check(v_bank is not null, 'bank row created');
  perform tst.check((select status from hr.employee_bank_accounts where id = v_bank) = 'PENDING', 'bank change waits for Finance');
  perform tst.check((select requested_by from hr.employee_bank_accounts where id = v_bank) = tst.id('user_emp'), 'the employee is the bank requester');
  perform tst.put('bank_new', v_bank);
end $$;
set role authenticated;

do $$
declare v jsonb;
begin
  perform tst.as_user('fin');
  v := public.hr_decide_bank(tst.id('bank_new'), true, 'OK');
  perform tst.as_user('emp');
  v := public.hr_my_portal();
  perform tst.check(v->'bank'->>'account' like '%3456', 'portal shows the new bank account, masked');
  perform tst.check(not (v->>'bank_pending')::boolean, 'nothing pending');
  perform tst.check(jsonb_array_length(v->'changes') = 5, 'portal lists all my requests');
end $$;

-- ===========================================================================
-- 3. Letters: request → prepare → approve; separation of duties; salary privacy; verification
-- ===========================================================================
do $$
declare l jsonb; v jsonb;
begin
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_request_letter(''{"letter_type":"EXPERIENCE"}''::jsonb)', 'when you leave');
  perform tst.expect_error('select public.hr_request_letter(''{"letter_type":"NOC"}''::jsonb)', 'what the no-objection is for');
  perform tst.expect_error(format('select public.hr_request_letter(%L)', jsonb_build_object('letter_type','SALARY_CERT','employee_id', tst.id('emp_mgr'))), 'only request letters for yourself');
  l := public.hr_request_letter(jsonb_build_object('letter_type','SALARY_CERT','addressee','Bank Muscat','purpose','Personal loan','language','BOTH'));
  perform tst.check(l->>'status' = 'REQUESTED' and (l->>'include_salary')::boolean, 'salary certificate requested; always states salary');
  perform tst.put('ltr1', (l->>'id')::uuid);
  perform tst.expect_error('select public.hr_request_letter(''{"letter_type":"SALARY_CERT"}''::jsonb)', 'PENDING_EXISTS');
  l := public.hr_request_letter(jsonb_build_object('letter_type','NOC','details', jsonb_build_object('destination','India','from_date','2026-12-01','to_date','2026-12-20'),
                                'purpose','Annual leave travel'));
  perform tst.put('ltr2', (l->>'id')::uuid);

  -- officer prepares; cannot approve; manager (salary reader) approves
  perform tst.as_user('hro');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'letters') = 2, 'officer has two letters to prepare');
  l := public.hr_prepare_letter(tst.id('ltr1'), jsonb_build_object('addressee','The Manager, Bank Muscat, Sohar'));
  perform tst.check(l->>'status' = 'PREPARED' and l->>'addressee' = 'The Manager, Bank Muscat, Sohar', 'prepared with edits');
  perform tst.check(not (l->>'can_approve')::boolean, 'preparer cannot approve');
  perform tst.expect_error(format('select public.hr_decide_letter(%L, true)', tst.id('ltr1')), 'NOT_ALLOWED|permission');
  v := public.hr_get_letter(tst.id('ltr1'));
  perform tst.check(v->'preview'->'salary' is null or v->'preview'->>'salary' is null, 'officer (no salary access) sees no salary in the preview');
  l := public.hr_prepare_letter(tst.id('ltr2'), '{}'::jsonb);

  perform tst.as_user('hrm');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'letters') = 2, 'manager has two letters to approve');
  l := public.hr_decide_letter(tst.id('ltr1'), true, null);
  perform tst.check(l->>'status' = 'ISSUED' and l->>'ref_no' ~ '/HR/[0-9]{4}/0001$', 'issued with reference ' || coalesce(l->>'ref_no','?'));
  perform tst.check((l->'snapshot'->'salary'->>'gross')::numeric > 0, 'salary stated in the snapshot');
  perform tst.check(l->'snapshot'->>'full_name_en' = 'Ravi Kumar', 'employee name captured');
  perform tst.check(length(l->>'verify_code') = 12, 'HR sees the verification code');
  l := public.hr_decide_letter(tst.id('ltr2'), true, 'OK');
  perform tst.check(l->>'ref_no' ~ '/0002$', 'numbers run in sequence');

  -- the employee sees the letter and its code; others without access cannot
  perform tst.as_user('emp');
  v := public.hr_get_letter(tst.id('ltr1'));
  perform tst.check(length(v->>'verify_code') = 12, 'employee sees the 12-character verification code');
  perform tst.check((v->'snapshot'->'salary'->>'basic')::numeric = 500 or (v->'snapshot'->'salary'->>'basic')::numeric > 0, 'employee sees own salary on the letter');
  perform set_config('tst.code', v->>'verify_code', false);
  perform set_config('tst.ref', v->>'ref_no', false);
  perform tst.as_user('nobody');
  perform tst.expect_error(format('select public.hr_get_letter(%L)', tst.id('ltr1')), 'NOT_ALLOWED|cannot');

  -- the officer sees the issued letter without the salary
  perform tst.as_user('hro');
  v := public.hr_get_letter(tst.id('ltr1'));
  perform tst.check(v->'snapshot'->'salary' is null and (v->>'salary_hidden')::boolean, 'salary hidden from the officer after issue');
end $$;

-- Public check (no login at all)
reset role;
grant usage on schema tst to anon, service_role;
grant execute on all functions in schema tst to anon, service_role;
grant select on all tables in schema tst to anon, service_role;
set role anon;
do $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  v := public.hr_verify_letter(current_setting('tst.ref'), current_setting('tst.code'));
  perform tst.check((v->>'valid')::boolean and v->>'full_name_en' = 'Ravi Kumar' and v->>'letter_type' = 'SALARY_CERT', 'letter verifies without login');
  perform tst.check(v->'salary' is null and v->>'civil_number' is null, 'verification reveals no salary or ID number');
  v := public.hr_verify_letter(current_setting('tst.ref'), 'ABCDEFGHJKLM');
  perform tst.check(not (v->>'valid')::boolean, 'wrong code does not verify');
end $$;
do $$
begin
  perform public.hr_my_portal();
  raise exception 'TEST FAILED: anon could call hr_my_portal';
exception when insufficient_privilege then null;
end $$;
reset role;
do $$
begin
  perform tst.check(has_function_privilege('anon', 'public.hr_verify_letter(text,text)', 'execute'), 'anon may verify letters');
  perform tst.check(not has_function_privilege('anon', 'public.hr_get_letter(uuid)', 'execute'), 'anon may not read letters');
  perform tst.check(not has_function_privilege('authenticated', 'public.mail_claim_batch(integer)', 'execute'), 'users cannot claim the mail queue');
  perform tst.check(has_function_privilege('service_role', 'public.mail_claim_batch(integer)', 'execute'), 'the edge function can');
end $$;
set role authenticated;

do $$
declare l jsonb; v jsonb;
begin
  -- revoke: verification then reports it withdrawn
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_revoke_letter(%L, '''')', tst.id('ltr2')), 'reason');
  l := public.hr_revoke_letter(tst.id('ltr2'), 'Travel cancelled');
  perform tst.check((l->>'revoked')::boolean, 'letter withdrawn');
  v := public.hr_verify_letter('NONSENSE', 'X');
  perform tst.check(not (v->>'valid')::boolean, 'nonsense input is rejected quietly');

  -- HR starts and prepares a letter for someone else in one step; the same person still cannot approve it
  perform tst.as_user('hrm');
  l := public.hr_request_letter(jsonb_build_object('employee_id', tst.id('emp_mgr'), 'letter_type','EMPLOYMENT','prepare', true, 'language','EN'));
  perform tst.check(l->>'status' = 'PREPARED', 'prepared directly by HR');
  perform tst.expect_error(format('select public.hr_decide_letter(%L, true)', l->>'id'), 'cannot approve');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_decide_letter(%L, false, '''')', l->>'id'), 'reason for rejecting');
  l := public.hr_decide_letter((l->>'id')::uuid, false, 'Wrong employee');
  perform tst.check(l->>'status' = 'REJECTED', 'rejected by another person');

  -- experience letter can be started by HR for an active employee only through HR
  l := public.hr_request_letter(jsonb_build_object('employee_id', tst.id('emp_w'), 'letter_type','EXPERIENCE'));
  perform tst.check(l->>'status' = 'REQUESTED', 'HR may start an experience letter');
  l := public.hr_cancel_letter((l->>'id')::uuid);
  perform tst.check(l->>'status' = 'CANCELLED', 'cancelled');

  -- HR cannot prepare or approve their own letters (user_mgr is linked and has no HR rights; test the rule via SELF check)
  perform tst.as_user('emp');
  v := public.hr_list_letters();
  perform tst.check(jsonb_array_length(v) = 3 and not (v->0 ? 'snapshot'), 'employee lists only own letters, without the full content');
end $$;

-- ===========================================================================
-- 4. Manager team view, PDPL export, e-mail outbox
-- ===========================================================================
do $$
declare v jsonb; m jsonb;
begin
  perform tst.as_user('mgr');
  v := public.hr_my_team();
  m := (select x from jsonb_array_elements(v) x where x->>'employee_id' = tst.id('emp_w')::text);
  perform tst.check(m is not null and (m->>'direct')::boolean, 'manager sees the direct report');
  perform tst.as_user('emp');
  perform tst.check(jsonb_array_length(public.hr_my_team()) = 0, 'an employee has no team');

  v := public.hr_my_data_export();
  perform tst.check(v->'employee'->>'id' = tst.id('emp_w')::text and jsonb_array_length(v->'letters') = 3 and v ? 'bank_accounts', 'PDPL export complete');
  perform tst.as_user('aud');
  perform tst.expect_error('select public.hr_my_data_export()', 'NOT_LINKED');

  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_email_settings()', 'NOT_ALLOWED|permission');
  v := public.hr_set_my_email_pref(false);
  perform tst.check(not (v->>'email_opt_in')::boolean, 'employee opts out');
  v := public.hr_set_my_email_pref(true);

  perform tst.as_user('admin');
  perform tst.expect_error('select public.hr_save_email_settings(''{"enabled":true,"app_url":"ftp://x"}''::jsonb)', 'https');
  v := public.hr_save_email_settings('{"enabled":true,"app_url":"https://hr.aact.om/","sender_name":"AACT HR"}'::jsonb);
  perform tst.check((v->'settings'->>'enabled')::boolean and v->'settings'->>'app_url' = 'https://hr.aact.om', 'e-mail switched on');
end $$;

reset role;
do $$
declare v jsonb; v_id uuid; n int;
begin
  perform hr.notify(tst.id('user_emp'), 'INFO', 'NORMAL', 'Test title', 'عنوان', 'Body', 'نص', '/me', 'MAILTEST:1');
  select count(*) into n from hr.email_outbox where user_id = tst.id('user_emp') and subject = 'Test title';
  perform tst.check(n = 1, 'notification queued as e-mail');
  perform tst.check((select body_text from hr.email_outbox where user_id = tst.id('user_emp') and subject = 'Test title') like '%https://hr.aact.om/me%', 'e-mail carries the link');
  update hr.user_profiles set email_opt_in = false where user_id = tst.id('user_emp');
  perform hr.notify(tst.id('user_emp'), 'INFO', 'NORMAL', 'Second', 'ثاني', null, null, null, 'MAILTEST:2');
  perform tst.check(not exists (select 1 from hr.email_outbox where subject = 'Second'), 'opted-out user gets no e-mail');
  update hr.user_profiles set email_opt_in = true where user_id = tst.id('user_emp');
end $$;
set role service_role;
do $$
declare v jsonb; m jsonb; n int;
begin
  v := public.mail_claim_batch(50);
  perform tst.check(jsonb_array_length(v) >= 1, 'edge function claims queued mail');
  for m in select * from jsonb_array_elements(v) loop
    perform public.mail_mark((m->>'id')::uuid, (m->>'subject') <> 'Test title', case when m->>'subject' = 'Test title' then 'Graph 503' end);
  end loop;
  perform tst.check(jsonb_array_length(public.mail_claim_batch(50)) = 0, 'nothing left to claim right away (failed mail retries after 10 minutes)');
end $$;
reset role;
do $$
begin
  perform tst.check((select status from hr.email_outbox where subject = 'Test title') = 'FAILED', 'failure recorded');
  perform tst.check((select last_error from hr.email_outbox where subject = 'Test title') = 'Graph 503', 'error kept');
  perform tst.check(not exists (select 1 from hr.audit_log where table_name = 'email_outbox'), 'the mail queue is not audited (no noise)');
end $$;
set role authenticated;
do $$
declare v jsonb;
begin
  perform tst.as_user('admin');
  v := public.hr_email_test();
  perform tst.check((v->'queue'->>'failed')::int = 1 and (v->'queue'->>'queued')::int >= 1, 'admin sees the queue');
  v := public.hr_save_email_settings('{"enabled":false}'::jsonb);
end $$;

reset role;
select 'ALL SELF-SERVICE TESTS PASSED' as result;
