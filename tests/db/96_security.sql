-- AACT HRMS — 1.13.0 security hardening: two-step sign-in and session settings.
set client_min_messages = warning;
reset role;

do $$
declare v jsonb;
begin
  -- without a factor nothing changes
  perform tst.as_user('hrm');
  perform tst.check(public.hr_me()->>'mfa_state' = 'OK', 'no factor: OK');
  -- once set up, a session that has not passed the second step is refused everywhere
  insert into auth.mfa_factors(user_id, status) values (tst.id('user_hrm'), 'verified');
  perform set_config('request.jwt.claims', '{"aal":"aal1"}', false);
  perform tst.check(public.hr_me()->>'mfa_state' = 'CHALLENGE', 'factor + aal1: challenge');
  perform tst.check((public.hr_me()->>'mfa_enrolled')::boolean, 'enrolled flag');
  perform tst.check(not hr.has_perm('EMP_READ'), 'no permissions before the second step');
  perform tst.expect_error('select public.hr_list_users()', 'MFA_REQUIRED');
  perform tst.expect_error('select public.hr_dashboard()', 'MFA_REQUIRED');
  perform set_config('request.jwt.claims', '{"aal":"aal2"}', false);
  perform tst.check(public.hr_me()->>'mfa_state' = 'OK' and hr.has_perm('EMP_READ'), 'aal2: full access again');

  -- requiring it for roles: the administrator must set it up first
  perform tst.as_user('admin');
  perform set_config('request.jwt.claims', '{"aal":"aal1"}', false);
  perform tst.expect_error($q$select public.hr_save_setting('mfa', '{"required": true, "roles": ["SUPER_ADMIN","HR_OFFICER"]}'::jsonb)$q$, 'yourself first');
  perform tst.expect_error($q$select public.hr_save_setting('mfa', '{"required": true, "roles": ["NOPE"]}'::jsonb)$q$, 'Unknown role');
  v := public.hr_save_setting('mfa', '{"required": true, "roles": ["HR_OFFICER"]}'::jsonb);
  perform tst.check((v->'mfa'->>'required')::boolean, 'policy saved');
  perform tst.as_user('hro');
  perform tst.check(public.hr_me()->>'mfa_state' = 'SETUP', 'HR officer without a factor must set it up');
  perform tst.expect_error('select public.hr_dashboard()', 'MFA_SETUP_REQUIRED');
  perform tst.as_user('fin');
  perform tst.check(public.hr_me()->>'mfa_state' = 'OK', 'roles outside the policy are not affected');
  perform tst.as_user('admin');
  v := public.hr_save_setting('mfa', '{"required": false, "roles": ["SUPER_ADMIN","HR_MANAGER","FINANCE","MG_PAYROLL"]}'::jsonb);

  -- automatic sign-out setting
  perform tst.expect_error($q$select public.hr_save_setting('session_idle_minutes', '2'::jsonb)$q$, 'between 5 and 480');
  v := public.hr_save_setting('session_idle_minutes', '20'::jsonb);
  perform tst.check((v->>'session_idle_minutes')::int = 20, 'idle minutes saved');
  perform tst.check((public.hr_me()->'settings'->>'session_idle_minutes')::int = 20, 'idle minutes reach the app');
end $$;

reset role;
delete from auth.mfa_factors;
select set_config('request.jwt.claims', '', false);
select 'ALL SECURITY TESTS PASSED' as result;
