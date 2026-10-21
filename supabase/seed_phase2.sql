-- AACT HRMS — Phase 2 dummy data (attendance & leave). DUMMY DATA ONLY: never run on the company server.
-- Runs after seed.sql. Uses the real API functions as the demo users (maker-checker respected), so it also
-- exercises the rules. Every step is wrapped: a step that is refused is reported with a NOTICE and skipped.
-- Contains no DROP statements (the cloud SQL runner cancels those). Safe to re-run: it stops if shifts exist.
-- Dates are relative to "today" in Muscat, so the demo always shows the last ten weeks.

do $p2$
declare
  boss uuid; hrm uuid; hro uuid; mgr uuid; empu uuid;
  v_today date := (now() at time zone 'Asia/Muscat')::date;
  v_m0 date := date_trunc('month', (now() at time zone 'Asia/Muscat')::date)::date;
  v_prev date; v_open date; v_from date; v_assign date;
  ent record; e record; d date; s hr.shifts; sh jsonb; j jsonb; rows jsonb := '[]'::jsonb;
  v_day uuid; v_gen uuid; v_night uuid; v_ram uuid; v_target uuid;
  v_r float8; v_in timestamp; v_out timestamp; v_late int; v_ok int := 0; v_fail int := 0; v_n int;
  v_ids uuid[]; x record; v_id uuid; v_days int;
  v_ravi uuid; v_hamad uuid; v_rajesh uuid;

begin
  if exists (select 1 from hr.shifts) then
    raise notice 'Phase 2 dummy data: shifts already exist — nothing done.'; return;
  end if;
  if not exists (select 1 from hr.employees) then
    raise notice 'Phase 2 dummy data: no employees — load seed.sql first.'; return;
  end if;
  perform setseed(0.4242);

  select id into boss from auth.users where email = 'admin@aact.test';
  if boss is null then
    select ur.user_id into boss from hr.user_roles ur where ur.role_code = 'SUPER_ADMIN' and ur.revoked_at is null order by ur.granted_at limit 1;
  end if;
  select id into hrm  from auth.users where email = 'hr.manager@aact.test';
  select id into hro  from auth.users where email = 'hr.officer@aact.test';
  select id into mgr  from auth.users where email = 'manager@aact.test';
  select id into empu from auth.users where email = 'employee@aact.test';
  if hrm is null or hro is null then raise notice 'Phase 2 dummy data: demo HR logins missing — nothing done.'; return; end if;

  select id into v_ravi   from hr.employees where full_name_en = 'Ravi Kumar' limit 1;
  select id into v_hamad  from hr.employees where full_name_en = 'Hamad Al Rawahi' limit 1;
  select id into v_rajesh from hr.employees where full_name_en = 'Rajesh Pillai' limit 1;

  v_prev   := (v_m0 - interval '1 month')::date;
  v_open   := (v_m0 - interval '3 months')::date;
  v_from   := v_today - 75;
  v_assign := v_today - 75;

  -- 1. leave opening date (first accrual month) — admin setting
  perform set_config('request.jwt.claim.sub', boss::text, false);
  begin
    perform public.hr_save_setting('leave_opening_date', to_jsonb(v_open::text));
  exception when others then raise notice 'opening date: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 2. Ramadan 2026 (approximate dates, dummy) and shifts per company
  perform set_config('request.jwt.claim.sub', hro::text, false);
  begin
    perform public.hr_save_special_period(jsonb_build_object('start_date', '2026-02-18', 'end_date', '2026-03-19',
      'name_en', 'Ramadan 1447 (demo dates)', 'name_ar', 'رمضان 1447 (تواريخ تجريبية)', 'notes', 'Replace with the announced dates.'));
  exception when others then raise notice 'ramadan: %', sqlerrm; v_fail := v_fail + 1; end;

  for ent in select id, code from hr.legal_entities loop
    begin
      v_day := (public.hr_save_shift(jsonb_build_object('entity_id', ent.id, 'code', 'DAY', 'name_en', 'Day shift', 'name_ar', 'الوردية الصباحية',
                 'start_time', '07:00', 'end_time', '16:00', 'break_minutes', 60, 'rest_days', jsonb_build_array(5, 6), 'is_active', true))->>'id')::uuid;
      v_gen := (public.hr_save_shift(jsonb_build_object('entity_id', ent.id, 'code', 'GEN', 'name_en', 'Office hours', 'name_ar', 'الدوام المكتبي',
                 'start_time', '08:00', 'end_time', '17:00', 'break_minutes', 60, 'grace_minutes', 15, 'rest_days', jsonb_build_array(5, 6), 'is_active', true))->>'id')::uuid;
      v_night := (public.hr_save_shift(jsonb_build_object('entity_id', ent.id, 'code', 'NIGHT', 'name_en', 'Night shift', 'name_ar', 'الوردية الليلية',
                 'start_time', '22:00', 'end_time', '07:00', 'break_minutes', 60, 'rest_days', jsonb_build_array(5, 6), 'is_active', true))->>'id')::uuid;
      v_ram := (public.hr_save_shift(jsonb_build_object('entity_id', ent.id, 'code', 'RAM', 'name_en', 'Ramadan hours', 'name_ar', 'دوام رمضان',
                 'start_time', '08:00', 'end_time', '14:00', 'break_minutes', 0, 'rest_days', jsonb_build_array(5, 6), 'is_ramadan', true, 'is_active', true))->>'id')::uuid;
    exception when others then raise notice 'shifts for %: %', ent.code, sqlerrm; v_fail := v_fail + 1; continue; end;

    -- 3. assignments: office departments → GEN; operations → DAY, a few production operators → NIGHT
    for e in
      select emp.id, emp.employee_no, emp.join_date, dep.code as dept, (substring(emp.employee_no from '\d+$'))::int as no
      from hr.employees emp
      join hr.employee_assignments a on a.employee_id = emp.id and a.effective_from <= v_today and (a.effective_to is null or a.effective_to >= v_today)
      join hr.departments dep on dep.id = a.department_id
      where emp.entity_id = ent.id and emp.status <> 'SEPARATED'
      order by emp.employee_no
    loop
      v_target := case when e.dept in ('HR','FIN','SALES','ADMIN','OPS') then v_gen
                       when e.dept = 'PROD' and e.no % 5 = 0 then v_night else v_day end;
      begin
        perform public.hr_assign_shift(jsonb_build_object('shift_id', v_target, 'employee_ids', jsonb_build_array(e.id),
                'effective_from', greatest(v_assign, e.join_date)::text, 'notes', 'Demo roster'));
      exception when others then raise notice 'assign %: %', e.employee_no, sqlerrm; v_fail := v_fail + 1; end;
      -- 4. device ids for even employee numbers (so imports by device id can be tried)
      if e.no % 2 = 0 then
        begin
          perform public.hr_set_device_user(jsonb_build_object('employee_id', e.id, 'device_code', 'DEFAULT', 'device_user_id', (1000 + e.no)::text));
        exception when others then v_fail := v_fail + 1; end;
      end if;
    end loop;
  end loop;

  -- 5. opening annual-leave balances (proposed by HR officer, approved by HR manager)
  perform set_config('request.jwt.claim.sub', hro::text, false);
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', emp.id, 'leave_type', 'ANNUAL', 'kind', 'OPENING',
           'days', (round((4 + random() * 22) * 2) / 2)::text, 'effective_date', v_open::text, 'reason', 'Opening balance from the old system (demo)')), '[]'::jsonb)
    into j
  from hr.employees emp where emp.status <> 'SEPARATED' and emp.join_date < v_open;
  begin
    j := public.hr_propose_leave_adjustments(jsonb_build_object('rows', j));
    if jsonb_array_length(j->'errors') > 0 then raise notice 'opening balances: % rows refused, first: %', jsonb_array_length(j->'errors'), j->'errors'->0; end if;
  exception when others then raise notice 'opening balances: %', sqlerrm; v_fail := v_fail + 1; end;
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  select array_agg(id) into v_ids from hr.leave_adjustments where status = 'PENDING';
  if v_ids is not null then
    begin perform public.hr_decide_leave_adjustments(v_ids, true, 'Checked against the old leave register (demo)');
    exception when others then raise notice 'approve opening: %', sqlerrm; v_fail := v_fail + 1; end;
  end if;

  -- 6. monthly accrual up to the end of last month
  begin perform public.hr_run_leave_accrual(null);
  exception when others then raise notice 'accrual: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 7. past approved annual leave (inside the punch window, so attendance shows L)
  for e in
    select emp.id, emp.employee_no from hr.employees emp
    where emp.status in ('ACTIVE','NOTICE') and exists (select 1 from hr.shift_assignments sa where sa.employee_id = emp.id)
    order by md5(emp.employee_no) limit 10
  loop
    v_n := 3 + floor(random() * 4)::int;
    d := v_from + 3 + floor(random() * 30)::int;
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      v_id := (public.hr_request_leave(jsonb_build_object('employee_id', e.id, 'leave_type', 'ANNUAL', 'start_date', d::text,
               'end_date', (d + v_n)::text, 'reason', 'Annual leave (demo)'))->>'id')::uuid;
      perform set_config('request.jwt.claim.sub', hrm::text, false);
      perform public.hr_decide_leave(v_id, true, null);
      v_ok := v_ok + 1;
    exception when others then raise notice 'past leave %: %', e.employee_no, sqlerrm; v_fail := v_fail + 1; end;
  end loop;

  -- 8. punches for the last six weeks (+ today's arrivals), imported through the real import
  for e in
    select emp.id, emp.employee_no, emp.entity_id from hr.employees emp
    where emp.status <> 'SEPARATED' and exists (select 1 from hr.shift_assignments sa where sa.employee_id = emp.id)
    order by emp.employee_no
  loop
    for d in select g::date from generate_series(v_from, v_today, interval '1 day') g loop
      s := hr.shift_for(e.id, d);
      continue when s.id is null;
      continue when extract(isodow from d)::int = any(s.rest_days);
      continue when (hr.holiday_on(e.entity_id, d)).id is not null;
      continue when (hr.leave_on(e.id, d)).id is not null;
      v_r := random();
      continue when v_r < 0.035;                                   -- absent
      v_late := case when random() < 0.13 then 5 + floor(random() * 35)::int else -floor(random() * 15)::int end;
      v_in  := d + s.start_time + make_interval(mins => v_late);
      v_out := d + s.end_time + case when s.end_time <= s.start_time then interval '1 day' else interval '0' end
               + make_interval(mins => case when random() < 0.06 then 75 + floor(random() * 90)::int else floor(random() * 25)::int end);
      if v_in > (now() at time zone 'Asia/Muscat') then continue; end if;
      rows := rows || jsonb_build_object('ref', e.employee_no, 'at', to_char(v_in, 'YYYY-MM-DD HH24:MI'), 'dir', 'IN');
      if v_r >= 0.065 and v_out <= (now() at time zone 'Asia/Muscat') then           -- 3% forget to punch out
        rows := rows || jsonb_build_object('ref', e.employee_no, 'at', to_char(v_out, 'YYYY-MM-DD HH24:MI'), 'dir', 'OUT');
      end if;
    end loop;
    if jsonb_array_length(rows) > 4500 then
      perform set_config('request.jwt.claim.sub', hro::text, false);
      begin
        perform public.hr_import_punches(jsonb_build_object('file_name', 'demo-device-export.csv', 'ref_kind', 'EMPLOYEE_NO', 'rows', rows));
      exception when others then raise notice 'import: %', sqlerrm; v_fail := v_fail + 1; end;
      rows := '[]'::jsonb;
    end if;
  end loop;
  if jsonb_array_length(rows) > 0 then
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      perform public.hr_import_punches(jsonb_build_object('file_name', 'demo-device-export.csv', 'ref_kind', 'EMPLOYEE_NO', 'rows', rows));
    exception when others then raise notice 'import: %', sqlerrm; v_fail := v_fail + 1; end;
  end if;

  -- 9. attendance corrections: approved ones last month; one waiting for HR this month
  for x in
    select ad.employee_id, ad.work_date, ad.first_in, ad.sched_end, ad.shift_id from hr.attendance_days ad
    where ad.status = 'MISSING_PUNCH' and ad.work_date >= v_prev and ad.work_date < v_m0 order by md5(ad.employee_id::text || ad.work_date) limit 4
  loop
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      s := hr.shift_for(x.employee_id, x.work_date);
      v_id := (public.hr_request_correction(jsonb_build_object('employee_id', x.employee_id, 'work_date', x.work_date::text,
               'in_time', to_char(x.first_in at time zone 'Asia/Muscat', 'HH24:MI'), 'out_time', to_char(s.end_time, 'HH24:MI'),
               'out_next_day', s.end_time <= s.start_time, 'reason', 'Forgot to punch out; supervisor confirmed (demo)'))->>'id')::uuid;
      perform set_config('request.jwt.claim.sub', hrm::text, false);
      perform public.hr_decide_correction(v_id, true, null);
    exception when others then raise notice 'correction: %', sqlerrm; v_fail := v_fail + 1; end;
  end loop;
  for x in
    select ad.employee_id, ad.work_date, ad.first_in from hr.attendance_days ad
    where ad.status = 'MISSING_PUNCH' and ad.work_date >= v_m0 and ad.work_date < v_today - 1 order by md5(ad.employee_id::text || ad.work_date) limit 2
  loop
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      s := hr.shift_for(x.employee_id, x.work_date);
      perform public.hr_request_correction(jsonb_build_object('employee_id', x.employee_id, 'work_date', x.work_date::text,
               'in_time', to_char(x.first_in at time zone 'Asia/Muscat', 'HH24:MI'), 'out_time', to_char(s.end_time, 'HH24:MI'),
               'out_next_day', s.end_time <= s.start_time, 'reason', 'Device was offline at shift end (demo)'));
    exception when others then raise notice 'correction (pending): %', sqlerrm; v_fail := v_fail + 1; end;
  end loop;

  -- 10. overtime matching long days: approved last month, waiting this month
  for x in
    select * from (
      (select ad.employee_id, ad.work_date, ad.sched_end, ad.last_out, false as this_month
       from hr.attendance_days ad join hr.shifts sx on sx.id = ad.shift_id and sx.end_time > sx.start_time
       where ad.status = 'PRESENT' and ad.extra_minutes >= 60 and ad.last_out is not null and ad.work_date >= v_prev and ad.work_date < v_m0
       order by md5(ad.employee_id::text || ad.work_date) limit 9)
      union all
      (select ad.employee_id, ad.work_date, ad.sched_end, ad.last_out, true
       from hr.attendance_days ad join hr.shifts sx on sx.id = ad.shift_id and sx.end_time > sx.start_time
       where ad.status = 'PRESENT' and ad.extra_minutes >= 60 and ad.last_out is not null and ad.work_date >= v_m0 and ad.work_date < v_today
       order by md5(ad.employee_id::text || ad.work_date) limit 3)) q
  loop
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      v_id := (public.hr_request_overtime(jsonb_build_object('employee_id', x.employee_id, 'work_date', x.work_date::text,
               'start_time', to_char(x.sched_end at time zone 'Asia/Muscat', 'HH24:MI'), 'end_time', to_char(x.last_out at time zone 'Asia/Muscat', 'HH24:MI'),
               'end_next_day', false, 'basis', 'CONSENT', 'employee_consent', true, 'comp_choice', 'PAY',
               'reason', 'Order backlog — line kept running (demo)'))->>'id')::uuid;
      if not x.this_month then
        perform set_config('request.jwt.claim.sub', hrm::text, false);
        perform public.hr_decide_overtime(v_id, true, null);
      end if;
    exception when others then raise notice 'overtime: %', sqlerrm; v_fail := v_fail + 1; end;
  end loop;

  -- 11. future and waiting leave
  for e in
    select emp.id, emp.employee_no, row_number() over (order by md5('f' || emp.employee_no)) as rn from hr.employees emp
    where emp.status in ('ACTIVE','NOTICE') and emp.join_date < v_today - 200 and exists (select 1 from hr.shift_assignments sa where sa.employee_id = emp.id)
    order by md5('f' || emp.employee_no) limit 5
  loop
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      d := v_today + 2 + (e.rn * 3)::int;
      v_id := (public.hr_request_leave(jsonb_build_object('employee_id', e.id, 'leave_type', 'ANNUAL', 'start_date', d::text,
               'end_date', (d + 4)::text, 'reason', 'Family travel (demo)', 'ticket_requested', e.rn = 1))->>'id')::uuid;
      if e.rn <= 3 then   -- three approved (they show in "away in the next 14 days"); two wait for HR
        perform set_config('request.jwt.claim.sub', hrm::text, false);
        perform public.hr_decide_leave(v_id, true, null);
      end if;
    exception when others then raise notice 'future leave %: %', e.employee_no, sqlerrm; v_fail := v_fail + 1; end;
  end loop;
  -- sick leave without the medical certificate yet (cannot be approved until it is attached)
  if v_rajesh is not null then
    perform set_config('request.jwt.claim.sub', hro::text, false);
    begin
      d := v_today - 1; while extract(isodow from d)::int in (5, 6) loop d := d - 1; end loop;
      perform public.hr_request_leave(jsonb_build_object('employee_id', v_rajesh, 'leave_type', 'SICK', 'start_date', d::text, 'end_date', d::text,
              'reason', 'Fever (demo)'));
    exception when others then raise notice 'sick: %', sqlerrm; v_fail := v_fail + 1; end;
  end if;
  -- the demo employee (Ravi) asks for leave himself
  if empu is not null and v_ravi is not null then
    perform set_config('request.jwt.claim.sub', empu::text, false);
    begin
      d := (v_m0 + interval '1 month')::date + 6;
      perform public.hr_request_leave(jsonb_build_object('employee_id', v_ravi, 'leave_type', 'ANNUAL', 'start_date', d::text, 'end_date', (d + 2)::text,
              'reason', 'Personal work'));
    exception when others then raise notice 'Ravi leave: %', sqlerrm; v_fail := v_fail + 1; end;
  end if;
  -- a paper request handed to the line manager (Salim) for Hamad: waits at the manager stage
  if v_hamad is not null then
    begin
      d := v_today + 20;
      insert into hr.leave_requests(employee_id, leave_type, start_date, end_date, days, reason, status, requested_by)
      values (v_hamad, 'ANNUAL', d, d + 1, hr.leave_day_count(v_hamad, 'ANNUAL', d, d + 1, false), 'Paper form handed to manager (demo)', 'PENDING_MANAGER', hro);
    exception when others then raise notice 'manager-stage leave: %', sqlerrm; v_fail := v_fail + 1; end;
  end if;

  -- 12. a balance adjustment and a rule change waiting for a second person
  perform set_config('request.jwt.claim.sub', hro::text, false);
  begin
    perform public.hr_propose_leave_adjustments(jsonb_build_object('rows', jsonb_build_array(jsonb_build_object(
      'employee_id', coalesce(v_hamad, (select id from hr.employees where status = 'ACTIVE' limit 1)), 'leave_type', 'ANNUAL', 'kind', 'ADJUSTMENT',
      'days', '2', 'effective_date', v_today::text, 'reason', 'Worked two public holidays in 2025 (demo)'))));
  exception when others then raise notice 'adjustment: %', sqlerrm; v_fail := v_fail + 1; end;
  begin
    perform public.hr_propose_time_rule(jsonb_build_object('code', 'ATTENDANCE', 'effective_from', (v_m0 + interval '1 month')::date::text,
      'rule_basis', 'COMPANY_POLICY', 'legal_basis', 'Proposed policy update (demo)',
      'value', jsonb_build_object('late_grace_minutes', 15, 'window_before_minutes', 180, 'window_after_minutes', 360, 'min_minutes_between_punches', 5)));
  exception when others then raise notice 'rule proposal: %', sqlerrm; v_fail := v_fail + 1; end;

  -- 13. lock last month for payroll
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  for ent in select id, code from hr.legal_entities loop
    begin perform public.hr_lock_period(ent.id, to_char(v_prev, 'YYYY-MM'));
    exception when others then raise notice 'lock % %: %', ent.code, to_char(v_prev, 'YYYY-MM'), sqlerrm; v_fail := v_fail + 1; end;
  end loop;

  perform set_config('request.jwt.claim.sub', '', false);
  raise notice 'Phase 2 dummy data loaded: % shifts, % assignments, % punches, % attendance days, % leave requests, % steps skipped.',
    (select count(*) from hr.shifts), (select count(*) from hr.shift_assignments), (select count(*) from hr.punches),
    (select count(*) from hr.attendance_days), (select count(*) from hr.leave_requests), v_fail;
end
$p2$;
