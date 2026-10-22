-- AACT HRMS — 1.13.0 report centre: database tests.
-- Runs after 10–90 (uses their companies, people, payroll runs, leave, cases …).
-- Every report is run for every company as the administrator and as Finance; none may fail.
-- Then: permissions, MG confidentiality inside reports, access log, schedules and the board pack.

set client_min_messages = warning;
reset role;

-- give the administrator every report permission except MG_PAY (as on a real system the super administrator has no MG pay)
insert into hr.role_permissions(role_code, perm_code) select 'SUPER_ADMIN', code from hr.permissions where code <> 'MG_PAY' on conflict do nothing;

do $$
declare d record; e record; v jsonb; n int := 0; v_err text := ''; v_p jsonb;
begin
  perform tst.as_user('admin');
  for e in select id, code from hr.legal_entities loop
    for d in select * from hr.report_defs order by sort loop
      v_p := jsonb_build_object('entity_id', e.id, 'from', '2025-01-01', 'to', '2026-12-31', 'as_of', '2026-10-01', 'month', '2026-07', 'days', 3650);
      begin
        v := public.hr_run_report(d.code, v_p);
        if jsonb_typeof(v->'rows') <> 'array' or jsonb_typeof(v->'columns') <> 'array' then raise exception 'bad shape'; end if;
        -- every row key must be a declared column
        if exists (select 1 from jsonb_array_elements(v->'rows') r, jsonb_object_keys(r) k
                    where not exists (select 1 from jsonb_array_elements(v->'columns') c where c->>'k' = k)) then
          raise exception 'row has an undeclared column';
        end if;
        n := n + 1;
      exception when others then
        if sqlerrm like 'NOT_FOUND: No calculated payroll run%' then n := n + 1;   -- companies without payroll
        else v_err := v_err || d.code || '@' || e.code || ': ' || sqlerrm || E'\n'; end if;
      end;
    end loop;
  end loop;
  perform tst.check(v_err = '', 'all reports run: ' || v_err);
  perform tst.check(n >= (select count(*) from hr.report_defs) * 3, 'reports run for every company: ' || n);
end $$;

do $$
declare v jsonb; v_ent uuid := (select id from hr.legal_entities where code = 'MGT'); v_run uuid;
begin
  -- the payroll test company has data in the register and the SPF schedule
  perform tst.as_user('fin');
  v := public.hr_run_report('P01', jsonb_build_object('entity_id', tst.id('pent')));
  perform tst.check(jsonb_array_length(v->'rows') > 0, 'payroll register has rows');
  perform tst.check((v->'meta'->>'run_id') is not null and v->'meta'->>'pay_group' = 'NMG', 'run meta returned');
  perform tst.check(exists (select 1 from hr.access_log where data_kind = 'REPORT' and detail like 'P01%' and user_id = tst.id('user_fin')), 'money report logged');
  v := public.hr_run_report('W01', jsonb_build_object('entity_id', tst.id('pent'), 'as_of', '2026-09-30'));
  perform tst.check((select sum((r->>'total')::int) from jsonb_array_elements(v->'rows') r) > 0, 'headcount report counts people');

  -- MG confidentiality: Finance (no MG_PAY) never sees MG money in reports; the MG run is refused
  v := public.hr_run_report('P14', jsonb_build_object('entity_id', v_ent, 'as_of', '2026-07-31'));
  perform tst.check(not exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'employee_no' = 'MGT-001'), 'salary listing hides MG staff from Finance');
  select id into v_run from hr.payroll_runs where entity_id = v_ent and pay_group = 'MG' limit 1;
  if v_run is not null then
    perform tst.expect_error(format('select public.hr_run_report(''P01'', %L::jsonb)', jsonb_build_object('run_id', v_run)), 'MG_ONLY');
  end if;
  perform tst.as_user('mg1');
  v := public.hr_run_report('P14', jsonb_build_object('entity_id', v_ent, 'as_of', '2026-07-31'));
  perform tst.check(exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'employee_no' = 'MGT-001'), 'management payroll team sees MG salaries');

  -- permissions: an employee cannot run HR reports; HR without payroll cannot run money reports
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_run_report(''W02'', ''{}''::jsonb)', 'NOT_ALLOWED|permission');
  perform tst.check(jsonb_array_length(public.hr_report_catalog()->'reports') = 0, 'employee catalogue is empty');
  perform tst.as_user('mgr');
  perform tst.expect_error('select public.hr_run_report(''P01'', ''{}''::jsonb)', 'NOT_ALLOWED|permission');
  perform tst.expect_error('select public.hr_run_report(''NOPE'', ''{}''::jsonb)', 'NOT_FOUND');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_report_catalog()->'reports') r where (r->>'money')::boolean),
    'line manager catalogue has no money reports');
  perform tst.as_user('admin');
  perform tst.expect_error('select public.hr_run_report(''W03'', ''{"from":"2026-05-01","to":"2026-04-01"}''::jsonb)', 'end date is before');
end $$;

-- schedules
do $$
declare v jsonb; v_id uuid; n int;
begin
  perform tst.as_user('hro');
  perform tst.expect_error('select public.hr_list_report_schedules()', 'NOT_ALLOWED|permission');
  perform tst.as_user('admin');
  perform tst.expect_error(format('select public.hr_save_report_schedule(%L::jsonb)', jsonb_build_object('code', 'P01', 'day_of_month', 5,
            'recipients', jsonb_build_array(tst.id('user_mgr')))), 'may not see');
  perform tst.expect_error(format('select public.hr_save_report_schedule(%L::jsonb)', jsonb_build_object('code', 'W01', 'day_of_month', 30,
            'recipients', jsonb_build_array(tst.id('user_hro')))), 'between 1 and 28');
  v := public.hr_save_report_schedule(jsonb_build_object('code', 'W01', 'name', 'Monthly headcount', 'day_of_month', 5,
         'params', jsonb_build_object('entity_id', tst.id('ent')), 'recipients', jsonb_build_array(tst.id('user_hro'), tst.id('user_hrm'))));
  v_id := (v->>'id')::uuid;
  perform tst.check(jsonb_array_length(v->'recipient_names') = 2, 'schedule saved with recipients');
  n := hr.send_due_report_schedules('2026-11-05');
  perform tst.check(n = 2, 'two reminders sent on the day: ' || n);
  perform tst.check(hr.send_due_report_schedules('2026-11-05') = 0, 'not sent twice on the same day');
  perform tst.check(hr.send_due_report_schedules('2026-11-06') = 0, 'nothing on other days');
  perform tst.check(exists (select 1 from hr.notifications where user_id = tst.id('user_hro') and kind = 'REPORT' and link = '/reports?schedule=' || v_id), 'reminder links to the schedule');
  perform tst.as_user('hro');
  perform tst.check((public.hr_get_report_schedule(v_id)->>'code') = 'W01', 'recipient can open the schedule');
  perform tst.as_user('fin');
  perform tst.expect_error(format('select public.hr_get_report_schedule(%L)', v_id), 'NOT_FOUND');
  perform tst.as_user('admin');
  v := public.hr_set_report_schedule_active(v_id, false);
  perform tst.check(not (v->>'is_active')::boolean, 'schedule switched off');
  perform tst.check(hr.send_due_report_schedules('2026-12-05') = 0, 'switched-off schedule sends nothing');
end $$;

-- board pack
do $$
declare v jsonb;
begin
  perform tst.as_user('admin');
  v := public.hr_board_pack(tst.id('ent'));
  perform tst.check(v ? 'exec' and jsonb_typeof(v->'expiries_by_type') = 'array' and (v->'entity'->>'code') is not null, 'board pack data');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_board_pack(%L)', tst.id('ent')), 'NOT_ALLOWED|permission');
end $$;

-- every report function is reachable only through hr_run_report
do $$
begin
  perform tst.check(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'hr' and p.proname like 'rpt\_%' and has_function_privilege('authenticated', p.oid, 'execute')), 'report functions not callable directly');
  perform tst.check((select count(*) from hr.report_defs) = (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'hr' and p.proname like 'rpt\_%'), 'one function per report');
end $$;

select 'ALL REPORT TESTS PASSED' as result;
