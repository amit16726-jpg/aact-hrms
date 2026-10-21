-- AACT HRMS — Phase 7 (privacy, statutory reports, executive dashboard, data import) database tests.
-- Runs after 10–60. Runs as the database owner; the API functions check permissions from request.jwt.claim.sub.

set client_min_messages = warning;
reset role;

-- ===========================================================================
-- 1. Privacy notice: second person publishes; employees acknowledge; optional consents
-- ===========================================================================
do $$
declare n jsonb; m jsonb; v_id uuid;
begin
  perform tst.check((select count(*) from hr.privacy_notices where status = 'DRAFT' and version = 1) = 1, 'template notice installed as draft version 1');
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_list_notices()', 'NOT_ALLOWED|permission');
  m := public.hr_my_privacy();
  perform tst.check(m->'notice' = 'null'::jsonb and (m->>'dsr_days')::int = 45, 'no notice published yet; 45-day reply period');
  perform tst.expect_error('select public.hr_ack_notice()', 'NOT_FOUND');

  perform tst.as_user('hrm');
  perform tst.expect_error('select public.hr_save_notice(''{"title_en":"X","title_ar":"س","body_en":"short","body_ar":"قصير"}''::jsonb)', 'at least 100');
  n := public.hr_save_notice(jsonb_build_object('title_en', 'Employee privacy notice', 'title_ar', 'إشعار الخصوصية',
         'body_en', repeat('We process your personal data to run your employment contract. ', 3), 'body_ar', repeat('نعالج بياناتك الشخصية لتنفيذ عقد عملك. ', 4)));
  perform tst.check((n->>'version')::int = 2 and n->>'status' = 'DRAFT', 'new draft is version 2');
  v_id := (n->>'id')::uuid;
  perform tst.expect_error(format('select public.hr_publish_notice(%L)', v_id), 'SELF_APPROVAL');
  perform tst.as_user('admin');
  n := public.hr_publish_notice(v_id);
  perform tst.check(n->>'status' = 'PUBLISHED', 'published by a second person');
  perform tst.check(exists (select 1 from hr.notifications where ref_key = 'NOTICE:2' and user_id = tst.id('user_emp')), 'employees asked to read it');
  perform tst.expect_error(format('select public.hr_save_notice(%L)', jsonb_build_object('id', v_id, 'title_en', 'x', 'title_ar', 'x', 'body_en', repeat('x', 120), 'body_ar', repeat('x', 120))), 'Only a draft');

  perform tst.as_user('emp');
  m := public.hr_my_privacy();
  perform tst.check((m->'notice'->>'version')::int = 2 and m->>'acknowledged_at' is null, 'employee sees the published notice');
  m := public.hr_ack_notice();
  m := public.hr_ack_notice();
  perform tst.check(m->>'acknowledged_at' is not null and (select count(*) from hr.consents where user_id = tst.id('user_emp') and purpose = 'NOTICE') = 1, 'acknowledged once');
  m := public.hr_set_consent('PHOTO_DIRECTORY', true);
  m := public.hr_set_consent('PHOTO_DIRECTORY', false);
  perform tst.check(jsonb_array_length(m->'consents') = 1 and not (m->'consents'->0->>'given')::boolean, 'consent withdrawn; one current record');
  perform tst.expect_error('select public.hr_set_consent(''NOTICE'', true)', 'Unknown purpose');

  perform tst.as_user('aud');
  perform tst.check((public.hr_pdpl_overview()->>'acknowledged')::int = 1, 'auditor sees acknowledgement count');
  perform tst.check(exists (select 1 from jsonb_array_elements(public.hr_list_consents()) c where (c->>'user_id')::uuid = tst.id('user_emp') and (c->>'notice_version')::int = 2), 'consent register');
end $$;

-- ===========================================================================
-- 2. Data-subject requests (45 days)
-- ===========================================================================
do $$
declare m jsonb; d jsonb; v_id uuid;
begin
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_submit_dsr(''ACCESS'', ''short'')', 'at least 10');
  m := public.hr_submit_dsr('ACCESS', 'Please send me a copy of all my personal data.');
  perform tst.check(jsonb_array_length(m->'requests') = 1 and (m->'requests'->0->>'due_on')::date = tst.today() + 45, 'request recorded, due in 45 days');
  v_id := (m->'requests'->0->>'id')::uuid;
  perform tst.check(exists (select 1 from hr.notifications where ref_key = 'DSR:' || v_id and user_id = tst.id('user_hrm')), 'privacy manager notified');

  perform tst.as_user('aud');
  perform tst.check(jsonb_array_length(public.hr_list_dsr('{"status":"OPEN"}'::jsonb)) = 1, 'auditor sees open requests');
  perform tst.expect_error(format('select public.hr_close_dsr(%L, %L, %L)', v_id, 'COMPLETED', 'Sent the export'), 'NOT_ALLOWED|permission');

  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_close_dsr(%L, %L, %L)', v_id, 'COMPLETED', 'done'), 'at least 15');
  d := public.hr_close_dsr(v_id, 'COMPLETED', 'Data export sent by e-mail on request date.');
  perform tst.check(d->>'status' = 'COMPLETED' and exists (select 1 from hr.notifications where ref_key = 'DSRC:' || v_id), 'answered; employee told');

  d := public.hr_save_dsr(jsonb_build_object('requester_name', 'Former candidate', 'contact', 'x@example.com', 'kind', 'ERASURE',
         'details', 'Please erase my CV and details.', 'received_on', tst.today() - 50));
  perform tst.check((d->>'overdue')::boolean and (d->>'days_left')::int = -5, 'late request flagged overdue');
  perform tst.expect_error(format('select public.hr_close_dsr(%L, %L, %L)', d->>'id', 'COMPLETED', 'Erased all candidate details'), 'identity');
  d := public.hr_close_dsr((d->>'id')::uuid, 'REJECTED', 'Identity could not be confirmed after two reminders.');
  perform tst.check(d->>'status' = 'REJECTED', 'refused with reason');
end $$;

-- ===========================================================================
-- 3. Breach log (72 hours)
-- ===========================================================================
do $$
declare b jsonb;
begin
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_save_breach(%L)', jsonb_build_object('discovered_at', now(), 'risk', 'LOW', 'description', 'Laptop lost in a taxi with payroll files')), 'NOT_ALLOWED|permission');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_save_breach(%L)', jsonb_build_object('discovered_at', now() + interval '1 hour', 'risk', 'LOW', 'description', 'Laptop lost in a taxi with payroll files')), 'not in the future');
  b := public.hr_save_breach(jsonb_build_object('discovered_at', now() - interval '80 hours', 'risk', 'HIGH', 'people_affected', 59,
         'description', 'Payroll spreadsheet e-mailed to an external address by mistake.', 'data_kinds', 'Names, salaries, bank accounts'));
  perform tst.check(b->>'ref_no' ~ '^BR-' and (b->>'overdue')::boolean, 'breach older than 72 hours without notification is overdue');
  perform tst.expect_error(format('select public.hr_close_breach(%L)', b->>'id'), 'contained');
  b := public.hr_save_breach(b || jsonb_build_object('containment', 'Recipient confirmed deletion in writing.', 'contained_at', now() - interval '70 hours',
         'authority_notified_at', now() - interval '2 hours', 'authority_reference', 'MTCIT-123'));
  perform tst.check(not (b->>'overdue')::boolean and (b->>'notified_late')::boolean, 'notified, but late');
  perform tst.expect_error(format('select public.hr_close_breach(%L)', b->>'id'), 'affected people');
  b := public.hr_save_breach(b || jsonb_build_object('subjects_notified_at', now() - interval '1 hour'));
  b := public.hr_close_breach((b->>'id')::uuid);
  perform tst.check(b->>'status' = 'CLOSED', 'breach closed');
end $$;

-- ===========================================================================
-- 4. Processing register, retention and candidate anonymisation
-- ===========================================================================
do $$
declare r jsonb; v_old uuid; v_new uuid;
begin
  perform tst.as_user('hrm');
  perform tst.check(jsonb_array_length(public.hr_list_activities()) >= 6, 'register pre-filled');
  r := public.hr_save_activity('{"code":"cctv","name_en":"CCTV","purpose":"Security of premises","legal_basis":"LEGITIMATE_INTEREST","data_subjects":"Employees, visitors","data_categories":"Video images"}'::jsonb);
  perform tst.check(exists (select 1 from jsonb_array_elements(r) a where a->>'code' = 'CCTV' and (a->>'reviewed_at')::date = tst.today()), 'activity added');
  perform tst.expect_error('select public.hr_save_activity(''{"code":"CCTV","name_en":"x","purpose":"x","legal_basis":"CONSENT","data_subjects":"x","data_categories":"x"}''::jsonb)', 'DUPLICATE');

  perform tst.as_user('hro');
  v_old := (public.hr_save_candidate('{"full_name_en":"Old Applicant","nationality":"IN","email":"old.applicant@example.com","phone":"+968 9000 1111"}'::jsonb)->>'id')::uuid;
  v_new := (public.hr_save_candidate('{"full_name_en":"New Applicant","nationality":"IN","email":"new.applicant@example.com"}'::jsonb)->>'id')::uuid;
  perform set_config('session_replication_role', 'replica', true);   -- skip the updated_at trigger to simulate an old record
  update hr.candidates set updated_at = now() - interval '13 months' where id = v_old;
  perform set_config('session_replication_role', 'origin', true);
  perform tst.as_user('hrm');
  r := public.hr_retention_report();
  perform tst.check(exists (select 1 from jsonb_array_elements(r->'candidates') c where (c->>'id')::uuid = v_old)
    and not exists (select 1 from jsonb_array_elements(r->'candidates') c where (c->>'id')::uuid = v_new), 'only the old candidate is past retention');
  perform tst.check(exists (select 1 from jsonb_array_elements(r->'rules') x where x->>'code' = 'EX_EMPLOYEE' and x ? 'due'), 'rules with counts');
  perform tst.expect_error(format('select public.hr_anonymise_candidates(%L)', jsonb_build_array(v_new)), 'not past the retention');
  r := public.hr_anonymise_candidates(jsonb_build_array(v_old));
  perform tst.check((r->>'anonymised')::int = 1 and (select full_name_en || coalesce(email, '') from hr.candidates where id = v_old) = 'Anonymised candidate', 'candidate anonymised');
  r := public.hr_save_pdpl_settings('{"dpo_name":"HR Manager","dpo_email":"privacy@aact.test","retention":[{"code":"CANDIDATE","en":"Candidates","ar":"المرشحون","months":6,"basis":"Consent"}]}'::jsonb);
  perform tst.check(r->>'dpo_email' = 'privacy@aact.test' and hr.retention_months('CANDIDATE') = 6, 'settings saved');
  perform tst.expect_error('select public.hr_save_pdpl_settings(''{"retention":[{"code":"X","months":0}]}''::jsonb)', '1–600');
end $$;

-- ===========================================================================
-- 5. Statutory reports and executive dashboard
-- ===========================================================================
do $$
declare r jsonb; v_run uuid := (select id from hr.payroll_runs where status = 'PAID' order by period_start desc limit 1); v_sum numeric;
begin
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_mol_report(%L)', tst.id('ent')), 'NOT_ALLOWED|permission');
  perform tst.expect_error(format('select public.hr_spf_report(%L)', v_run), 'NOT_ALLOWED|permission');
  perform tst.expect_error(format('select public.hr_exec_dashboard(%L)', tst.id('ent')), 'NOT_ALLOWED|permission');

  perform tst.as_user('hrm');
  r := public.hr_mol_report(tst.id('ent'));
  perform tst.check(jsonb_array_length(r->'by_profession') >= 1 and exists (select 1 from jsonb_array_elements(r->'employees') e where (e->>'employee_id')::uuid = tst.id('emp_w')),
    'localisation report lists professions and employees');
  perform tst.check((r->>'show_salary')::boolean and r->'overall' ? 'pct', 'salary shown to HR manager; overall ratio included');
  perform tst.check(exists (select 1 from hr.access_log where data_kind = 'MOL_REPORT'), 'report access logged');

  perform tst.as_user('fin');
  r := public.hr_spf_report(v_run);
  perform tst.check((r->'run'->>'final')::boolean and jsonb_array_length(r->'rows') >= 1, 'SPF schedule from the paid run');
  perform tst.check(exists (select 1 from jsonb_array_elements(r->'rows') x where (x->>'employee_id')::uuid = tst.id('p1') and (x->>'is_omani')::boolean
    and (x->'lines'->>'SPF_EE_OLD_AGE')::numeric > 0 and (x->>'employer_total')::numeric > (x->>'employee_total')::numeric), 'Omani row has employee and employer shares');
  select sum((x->>'employee_total')::numeric + (x->>'employer_total')::numeric) into v_sum from jsonb_array_elements(r->'rows') x;
  perform tst.check(v_sum = (select sum(value::numeric) from jsonb_each_text(r->'totals')), 'rows add up to the totals');

  r := public.hr_exec_dashboard(tst.id('ent'));
  perform tst.check(jsonb_array_length(r->'months') = 12 and (r->'snapshot'->>'headcount')::int > 0 and (r->>'show_pay')::boolean, 'executive dashboard: 12 months, snapshot, pay shown');
  perform tst.check(r->'risks' ? 'gratuity_liability', 'risks block');
end $$;

-- ===========================================================================
-- 6. Data import: dry run changes nothing; real run creates; documents and opening salaries
-- ===========================================================================
do $$
declare r jsonb; v_rows jsonb; v_before int := (select count(*) from hr.employees);
begin
  perform tst.as_user('hro');
  perform tst.expect_error('select public.hr_import(''EMPLOYEES'', ''[{}]''::jsonb)', 'NOT_ALLOWED|permission');
  perform tst.as_user('hrm');
  v_rows := jsonb_build_array(
    jsonb_build_object('employee_no', 'IMP-001', 'full_name_en', 'Imported Worker', 'nationality', 'in', 'gender', 'm', 'date_of_birth', '1990-01-15',
      'join_date', '2019-03-01', 'department_code', 'prod', 'job_code', 'OPR', 'grade_code', 'W1', 'category_code', 'STAFF', 'location_code', 'SOHAR',
      'manager_employee_no', (select employee_no from hr.employees where id = tst.id('emp_mgr')), 'employment_type', 'FULL_TIME'),
    jsonb_build_object('employee_no', 'IMP-002', 'full_name_en', 'Bad Department', 'nationality', 'IN', 'join_date', '2020-01-01',
      'department_code', 'NOPE', 'job_code', 'OPR', 'category_code', 'STAFF'),
    jsonb_build_object('employee_no', 'IMP-003', 'full_name_en', 'Bad Manager', 'nationality', 'IN', 'join_date', '2020-01-01',
      'department_code', 'PROD', 'job_code', 'OPR', 'category_code', 'STAFF', 'manager_employee_no', 'ZZZ-999'));
  r := public.hr_import('EMPLOYEES', v_rows, true, 'employees.csv');
  perform tst.check((r->>'ok')::int = 1 and (r->>'failed')::int = 2 and (r->>'dry_run')::boolean, 'dry run: 1 good row, 2 errors');
  perform tst.check(exists (select 1 from jsonb_array_elements(r->'results') x where x->>'message' like '%departments code "NOPE"%'), 'clear message for an unknown code');
  perform tst.check(exists (select 1 from jsonb_array_elements(r->'results') x where x->>'message' like '%manager employee number "ZZZ-999"%'), 'clear message for an unknown manager');
  perform tst.check((select count(*) from hr.employees) = v_before, 'dry run created nothing');

  r := public.hr_import('EMPLOYEES', jsonb_build_array(v_rows->0), false, 'employees.csv');
  perform tst.check((r->>'ok')::int = 1 and exists (select 1 from hr.employees where employee_no = 'IMP-001' and status = 'ACTIVE'), 'employee imported');

  r := public.hr_import('DOCUMENTS', '[{"employee_no":"imp-001","doc_type":"passport","doc_number":"Z1234567","issue_date":"2020-01-01","expiry_date":"2030-01-01"},
                                       {"employee_no":"IMP-001","doc_type":"PASSPORT"}]'::jsonb, false);
  perform tst.check((r->>'ok')::int = 1 and (r->>'failed')::int = 1, 'document imported; incomplete row rejected');
  r := public.hr_import('SALARIES', '[{"employee_no":"IMP-001","BASIC":"300","HOUSING":"50"},{"employee_no":"IMP-001","NOSUCH":"10"}]'::jsonb, false);
  perform tst.check((r->>'ok')::int = 1 and (select status from hr.compensation_revisions where employee_id = (select id from hr.employees where employee_no = 'IMP-001')) = 'PENDING',
    'opening salary proposed for approval');
  perform tst.check(jsonb_array_length(public.hr_list_imports()) = 4, 'import history kept (including the dry run)');
end $$;

do $$
declare f record; n int := 0;
begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.proname in ('hr_list_notices','hr_save_notice','hr_publish_notice','hr_my_privacy','hr_ack_notice','hr_set_consent',
             'hr_list_consents','hr_list_dsr','hr_submit_dsr','hr_save_dsr','hr_close_dsr','hr_list_breaches','hr_save_breach','hr_close_breach',
             'hr_list_activities','hr_save_activity','hr_retention_report','hr_anonymise_candidates','hr_pdpl_settings','hr_save_pdpl_settings',
             'hr_pdpl_overview','hr_mol_report','hr_spf_report','hr_exec_dashboard','hr_import','hr_list_imports') loop
    perform tst.check(has_function_privilege('authenticated', f.sig, 'execute') and not has_function_privilege('anon', f.sig, 'execute'), 'grants for ' || f.sig);
    n := n + 1;
  end loop;
  perform tst.check(n = 26, 'all 26 Phase 7 API functions exist: ' || n);
end $$;

select 'ALL GOVERNANCE TESTS PASSED' as result;
