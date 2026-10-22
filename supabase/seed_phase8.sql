-- AACT HRMS — 1.9.0 dummy data: management (MG) pay group.
-- DUMMY DATA ONLY: never run on the company server. Runs after seed.sql … seed_phase7.sql.
-- The demo administrator and demo Finance user form the management payroll team; the four department heads become MG.
-- Uses the real API. Contains no destructive statements. Stops if anyone is already in the MG pay group.

do $p8$
declare adm uuid; fin uuid; v_fail int := 0; v_log text := ''; x record; n int := 0;
begin
  if exists (select 1 from hr.employees where pay_group = 'MG') then raise notice 'MG dummy data: already present — nothing done.'; return; end if;
  select id into adm from auth.users where email = 'admin@aact.test';
  select id into fin from auth.users where email = 'finance@aact.test';
  if adm is null or fin is null then raise notice 'MG dummy data: demo logins missing — nothing done.'; return; end if;

  perform set_config('request.jwt.claim.sub', adm::text, false);
  begin
    perform public.hr_set_user_roles(adm, (select array_agg(role_code) from hr.user_roles where user_id = adm and revoked_at is null) || array['MG_PAYROLL']);
    perform public.hr_set_mg_access(fin, true);
  exception when others then v_log := v_log || 'team: ' || sqlerrm || ' | '; v_fail := v_fail + 1; end;

  for x in select e.id, e.full_name_en from hr.employees e
           where e.full_name_en in ('Salim Al Harthy', 'Fatma Al Balushi', 'Anil Sharma', 'Khalid Al Hinai') and e.status <> 'SEPARATED' loop
    begin
      perform public.hr_set_pay_group(x.id, 'MG', 'Department head on a management contract (demo)');
      n := n + 1;
    exception when others then v_log := v_log || x.full_name_en || ': ' || sqlerrm || ' | '; v_fail := v_fail + 1; end;
  end loop;

  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('demo.seed_phase8', v_log || format('%s MG employees, %s team members, %s steps skipped', n,
    (select count(*) from hr.users_with_perm('MG_PAY')), v_fail), false);
  raise notice 'MG dummy data: %', current_setting('demo.seed_phase8');
end
$p8$;
