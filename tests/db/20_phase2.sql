-- AACT HRMS — Phase 2 (attendance & leave) database tests.
-- Runs after 10_priority1.sql on the same database (uses its users, company and employees).
-- Every call goes through the public API as the real "authenticated" role.

set client_min_messages = warning;
reset role;

create or replace function tst.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Muscat')::date $$;
-- n-th most recent past working day (not Friday/Saturday)
create or replace function tst.workday(p_n int) returns date language sql stable as $$
  select d::date from generate_series(tst.today() - 1, tst.today() - 40, interval '-1 day') d
  where extract(isodow from d) not in (5, 6) offset p_n - 1 limit 1 $$;
-- n-th next working day after today
create or replace function tst.next_workday(p_n int) returns date language sql stable as $$
  select d::date from generate_series(tst.today() + 1, tst.today() + 40, interval '1 day') d
  where extract(isodow from d) not in (5, 6) offset p_n - 1 limit 1 $$;
create or replace function tst.next_friday() returns date language sql stable as $$
  select d::date from generate_series(tst.today() + 1, tst.today() + 8, interval '1 day') d where extract(isodow from d) = 5 limit 1 $$;
create or replace function tst.day(p_emp uuid, p_d date) returns jsonb language sql as $$
  select d from jsonb_array_elements(public.hr_attendance_month(p_emp, to_char(p_d, 'YYYY-MM'))->'days') d
  where (d->>'work_date')::date = p_d $$;
create or replace function tst.bal(p_emp uuid, p_type text) returns jsonb language sql as $$
  select b from jsonb_array_elements(public.hr_leave_balances(p_emp)->'balances') b where b->>'leave_type' = p_type $$;
grant execute on all functions in schema tst to authenticated;

set role authenticated;

-- ===========================================================================
-- 1. Shifts: Oman hours, rest and break rules
-- ===========================================================================
do $$
declare v jsonb; e uuid := tst.id('ent');
begin
  perform tst.as_user('hro');
  v := public.hr_save_shift(jsonb_build_object('entity_id', e, 'code','DAY', 'name_en','Day shift', 'start_time','07:00',
         'end_time','16:00', 'break_minutes', 60, 'rest_days', jsonb_build_array(5,6)));
  perform tst.put('shift_day', (v->>'id')::uuid);
  perform tst.check((v->>'net_minutes')::int = 480 and (v->>'weekly_minutes')::int = 2400, '8 h/day, 40 h/week');
  perform tst.expect_error(format('select public.hr_save_shift(%L)', jsonb_build_object('entity_id', e, 'code','LONG', 'name_en','Long',
            'start_time','07:00', 'end_time','17:00', 'break_minutes', 60)), 'HOURS_LIMIT');
  perform tst.expect_error(format('select public.hr_save_shift(%L)', jsonb_build_object('entity_id', e, 'code','R1', 'name_en','One rest day',
            'start_time','08:00', 'end_time','15:00', 'break_minutes', 60, 'rest_days', jsonb_build_array(5))), 'REST_RULE');
  perform tst.expect_error(format('select public.hr_save_shift(%L)', jsonb_build_object('entity_id', e, 'code','R2', 'name_en','Split rest',
            'start_time','08:00', 'end_time','15:00', 'break_minutes', 60, 'rest_days', jsonb_build_array(5,7))), 'REST_RULE');
  v := public.hr_save_shift(jsonb_build_object('entity_id', e, 'code','WRAP', 'name_en','Sunday-Monday rest', 'start_time','08:00',
         'end_time','16:00', 'break_minutes', 60, 'rest_days', jsonb_build_array(7,1)));
  perform tst.check((v->>'net_minutes')::int = 420, 'rest Sunday+Monday accepted (wraps the week)');
  perform tst.expect_error(format('select public.hr_save_shift(%L)', jsonb_build_object('entity_id', e, 'code','NOBRK', 'name_en','No break',
            'start_time','07:00', 'end_time','14:30', 'break_minutes', 0)), 'BREAK_RULE');
  v := public.hr_save_shift(jsonb_build_object('entity_id', e, 'code','RAM', 'name_en','Ramadan', 'start_time','08:00',
         'end_time','14:00', 'break_minutes', 0, 'is_ramadan', true));
  perform tst.put('shift_ram', (v->>'id')::uuid);
  perform tst.expect_error(format('select public.hr_save_shift(%L)', jsonb_build_object('entity_id', e, 'code','RAM2', 'name_en','Ramadan long',
            'start_time','08:00', 'end_time','15:00', 'break_minutes', 0, 'is_ramadan', true)), 'HOURS_LIMIT');
  v := public.hr_save_shift(jsonb_build_object('entity_id', e, 'code','EVE', 'name_en','Evening', 'start_time','14:00',
         'end_time','23:00', 'break_minutes', 60));
  perform tst.check(not (v->>'crosses_midnight')::boolean, 'evening shift');
  perform tst.expect_error(format('select public.hr_save_shift(%L)', jsonb_build_object('entity_id', e, 'code','DAY', 'name_en','Dup',
            'start_time','07:00', 'end_time','15:00')), 'DUPLICATE');
  perform tst.as_user('aud');
  perform tst.expect_error(format('select public.hr_save_shift(%L)', jsonb_build_object('entity_id', e, 'code','X', 'name_en','X',
            'start_time','07:00', 'end_time','15:00')), 'NOT_ALLOWED');
end $$;

-- ===========================================================================
-- 2. Rosters: a temporary (Ramadan) shift splits the open assignment
-- ===========================================================================
do $$
declare v jsonb; t date := tst.today();
begin
  perform tst.as_user('hro');
  v := public.hr_assign_shift(jsonb_build_object('employee_ids', jsonb_build_array(tst.id('emp_w'), tst.id('emp_mgr'), tst.id('emp_om')),
         'shift_id', tst.id('shift_day'), 'effective_from', (t - 45)::text));
  perform tst.check((v->>'assigned')::int = 3, 'three employees assigned');
  perform public.hr_assign_shift(jsonb_build_object('employee_ids', jsonb_build_array(tst.id('emp_w')), 'shift_id', tst.id('shift_ram'),
         'effective_from', (t - 10)::text, 'effective_to', (t - 5)::text));
  v := public.hr_list_shift_assignments(jsonb_build_object('employee_id', tst.id('emp_w')));
  perform tst.check(jsonb_array_length(v) = 3, 'split into three periods');
  perform tst.check(v->0->>'shift_code' = 'DAY' and (v->0->>'effective_from')::date = t - 4 and v->0->>'effective_to' is null, 'day shift resumes after Ramadan');
  perform tst.check(v->1->>'shift_code' = 'RAM', 'Ramadan period in the middle');
  perform tst.check((v->2->>'effective_to')::date = t - 11, 'first period closed the day before');
  perform tst.expect_error(format('select public.hr_assign_shift(%L)', jsonb_build_object('employee_ids', jsonb_build_array(tst.id('emp_w')),
            'shift_id', tst.id('shift_day'), 'effective_from', (t - 20)::text)), 'OVERLAP');
end $$;

-- ===========================================================================
-- 3. Holiday, punch import and computed attendance
-- ===========================================================================
do $$
declare v jsonb; rows jsonb := '[]'::jsonb; d date; v_no text; n int := 0; t date := tst.today();
begin
  perform tst.as_user('hro');
  v := public.hr_save_holiday(jsonb_build_object('holiday_date', tst.workday(3)::text, 'name_en', 'Test holiday', 'name_ar', 'عطلة اختبار'));
  perform tst.expect_error(format('select public.hr_save_holiday(%L)', jsonb_build_object('holiday_date', tst.workday(3)::text, 'name_en', 'Again')), 'DUPLICATE');
  v_no := public.hr_get_employee(tst.id('emp_w'))->'employee'->>'employee_no';
  for d in select x::date from generate_series(t - 20, t - 1, interval '1 day') x where extract(isodow from x) not in (5,6) loop
    continue when d = tst.workday(7) or d = tst.workday(3);
    if d = tst.workday(5) then
      rows := rows || jsonb_build_array(jsonb_build_object('ref', v_no, 'at', d || ' 06:55')); n := n + 1;
    elsif d = tst.workday(2) then
      rows := rows || jsonb_build_array(jsonb_build_object('ref', v_no, 'at', d || ' 07:35', 'dir','IN'), jsonb_build_object('ref', v_no, 'at', d || ' 16:10', 'dir','OUT')); n := n + 2;
    else
      rows := rows || jsonb_build_array(jsonb_build_object('ref', v_no, 'at', d || ' 06:55'), jsonb_build_object('ref', v_no, 'at', d || ' 16:05')); n := n + 2;
    end if;
  end loop;
  rows := rows || jsonb_build_array(jsonb_build_object('ref', 'NOPE-1', 'at', (t - 1) || ' 07:00'),
                                    jsonb_build_object('ref', v_no, 'at', tst.workday(1) || ' 06:55'));
  v := public.hr_import_punches(jsonb_build_object('entity_id', tst.id('ent'), 'file_name', 'test.csv', 'ref_kind', 'EMPLOYEE_NO', 'rows', rows));
  perform tst.check((v->>'rows_imported')::int = n, 'all good rows imported');
  perform tst.check((v->>'rows_duplicate')::int = 1 and (v->>'rows_error')::int = 1, 'duplicate skipped, unknown employee reported');
  perform tst.check(tst.day(tst.id('emp_w'), tst.workday(1))->>'status' = 'PRESENT', 'present day');
  perform tst.check((tst.day(tst.id('emp_w'), tst.workday(2))->>'late_minutes')::int >= 35, 'late arrival counted');
  perform tst.check(tst.day(tst.id('emp_w'), tst.workday(3))->>'status' = 'HOLIDAY', 'public holiday');
  perform tst.check(tst.day(tst.id('emp_w'), tst.workday(5))->>'status' = 'MISSING_PUNCH', 'single punch = missing punch');
  perform tst.check(tst.day(tst.id('emp_w'), tst.workday(7))->>'status' = 'ABSENT', 'no punches = absent');
  perform tst.check((select count(*) from jsonb_array_elements(public.hr_attendance_month(tst.id('emp_w'), to_char(tst.workday(1), 'YYYY-MM'))->'days') x
                     where x->>'status' = 'REST') > 0, 'weekly rest days marked');
  -- device ids
  perform public.hr_set_device_user(jsonb_build_object('employee_id', tst.id('emp_mgr'), 'device_code', 'ZK', 'device_user_id', '1001'));
  v := public.hr_import_punches(jsonb_build_object('ref_kind', 'DEVICE_ID', 'device_code', 'ZK', 'rows', jsonb_build_array(
         jsonb_build_object('ref','1001','at', tst.workday(1) || ' 06:50'), jsonb_build_object('ref','1001','at', tst.workday(1) || ' 16:02'))));
  perform tst.check((v->>'rows_imported')::int = 2, 'imported by device id');
  perform tst.check(tst.day(tst.id('emp_mgr'), tst.workday(1))->>'status' = 'PRESENT', 'manager present');
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_import_punches(%L)', jsonb_build_object('rows', '[]'::jsonb)), 'NOT_ALLOWED');
end $$;

-- ===========================================================================
-- 4. Who sees whose attendance
-- ===========================================================================
do $$
declare v jsonb;
begin
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_attendance_month(%L, %L)', tst.id('emp_mgr'), to_char(tst.today(), 'YYYY-MM')), 'NOT_ALLOWED');
  v := public.hr_attendance_day(jsonb_build_object('date', tst.workday(1)::text));
  perform tst.check(jsonb_array_length(v->'rows') = 1 and v->'rows'->0->>'employee_id' = tst.id('emp_w')::text, 'employee sees only own day');
  perform tst.as_user('mgr');
  v := public.hr_attendance_day(jsonb_build_object('date', tst.workday(1)::text));
  perform tst.check(jsonb_array_length(v->'rows') = 3, 'manager sees self and team');
  perform tst.expect_error(format('select public.hr_attendance_summary(%L)', jsonb_build_object('month', to_char(tst.today(),'YYYY-MM'))), 'NOT_ALLOWED');
  perform tst.as_user('fin');
  v := public.hr_attendance_summary(jsonb_build_object('entity_id', tst.id('ent'), 'month', to_char(tst.workday(1),'YYYY-MM')));
  perform tst.check(jsonb_array_length(v->'rows') >= 3, 'finance reads the payroll summary');
  v := public.hr_attendance_grid(jsonb_build_object('entity_id', tst.id('ent'), 'month', to_char(tst.workday(1),'YYYY-MM')));
  perform tst.check(exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'employee_id' = tst.id('emp_w')::text
                    and (r->>'absent')::int >= 1), 'month grid counts absences');
end $$;

-- ===========================================================================
-- 5. Attendance corrections: employee → manager → HR
-- ===========================================================================
do $$
declare v jsonb; d date := tst.workday(5);
begin
  perform tst.as_user('emp');
  v := public.hr_request_correction(jsonb_build_object('employee_id', tst.id('emp_w'), 'work_date', d::text, 'out_time', '16:00',
         'reason', 'Forgot to punch out'));
  perform tst.put('corr1', (v->>'id')::uuid);
  perform tst.check(v->>'status' = 'PENDING_MANAGER', 'goes to the line manager first');
  perform tst.expect_error(format('select public.hr_request_correction(%L)', jsonb_build_object('employee_id', tst.id('emp_w'),
            'work_date', d::text, 'out_time', '16:00', 'reason', 'again')), 'PENDING_EXISTS');
  perform tst.expect_error(format('select public.hr_request_correction(%L)', jsonb_build_object('employee_id', tst.id('emp_w'),
            'work_date', (tst.today() + 1)::text, 'in_time', '07:00', 'reason', 'future')), 'INVALID');
  perform tst.expect_error(format('select public.hr_decide_correction(%L, true)', tst.id('corr1')), 'SELF_APPROVAL');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_decide_correction(%L, true)', tst.id('corr1')), 'NOT_ALLOWED');
  perform tst.as_user('mgr');
  perform tst.check(jsonb_array_length(public.hr_list_my_tasks()->'corrections') = 1, 'manager sees it in tasks');
  v := public.hr_decide_correction(tst.id('corr1'), true, null);
  perform tst.check(v->>'status' = 'PENDING_HR', 'manager approval passes to HR');
  perform tst.as_user('hrm');
  v := public.hr_decide_correction(tst.id('corr1'), true, null);
  perform tst.check(v->>'status' = 'APPROVED', 'HR approves');
  perform tst.check(tst.day(tst.id('emp_w'), d)->>'status' = 'PRESENT' and (tst.day(tst.id('emp_w'), d)->>'worked_minutes')::int > 300,
                    'day recomputed with the corrected punch');
end $$;

-- ===========================================================================
-- 6. Overtime: consent, outside the shift, 12-hour cap, night premium, rest day
-- ===========================================================================
do $$
declare v jsonb; f date := tst.next_workday(2);
begin
  perform tst.as_user('emp');
  v := public.hr_request_overtime(jsonb_build_object('employee_id', tst.id('emp_w'), 'work_date', tst.workday(1)::text,
         'start_time','16:30', 'end_time','19:00', 'reason','Machine breakdown'));
  perform tst.put('ot1', (v->>'id')::uuid);
  perform tst.check(v->>'day_kind' = 'WORKDAY' and (v->>'minutes')::int = 150 and (v->>'pay_hours')::numeric = 3.13, '2.5 h × 1.25 = 3.13 pay hours');
  perform tst.check((v->>'employee_consent')::boolean, 'own request = consent');
  perform tst.expect_error(format('select public.hr_request_overtime(%L)', jsonb_build_object('employee_id', tst.id('emp_w'),
            'work_date', f::text, 'start_time','15:00', 'end_time','17:00', 'reason','overlap')), 'outside the scheduled shift');
  perform tst.expect_error(format('select public.hr_request_overtime(%L)', jsonb_build_object('employee_id', tst.id('emp_w'),
            'work_date', f::text, 'start_time','16:30', 'end_time','21:31', 'reason','too long')), 'HOURS_LIMIT');
  v := public.hr_request_overtime(jsonb_build_object('employee_id', tst.id('emp_w'), 'work_date', f::text,
         'start_time','20:00', 'end_time','23:00', 'reason','Night loading'));
  perform tst.check((v->>'night_minutes')::int = 120 and (v->>'day_minutes')::int = 60 and (v->>'pay_hours')::numeric = 4.25,
                    '1 h × 1.25 + 2 night h × 1.50 = 4.25');
  v := public.hr_request_overtime(jsonb_build_object('employee_id', tst.id('emp_w'), 'work_date', tst.next_friday()::text,
         'start_time','08:00', 'end_time','12:00', 'reason','Rest-day delivery'));
  perform tst.check(v->>'day_kind' = 'REST_DAY' and (v->>'pay_days')::numeric = 2.00, 'rest day: day''s wage plus 100 %');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_request_overtime(%L)', jsonb_build_object('employee_id', tst.id('emp_w'),
            'work_date', tst.next_workday(3)::text, 'start_time','17:00', 'end_time','18:00', 'reason','no consent')), 'CONSENT_REQUIRED');
  v := public.hr_request_overtime(jsonb_build_object('employee_id', tst.id('emp_w'), 'work_date', tst.next_workday(3)::text,
         'start_time','17:00', 'end_time','18:00', 'reason','Agreed with worker', 'employee_consent', true));
  perform tst.check(v->>'status' = 'PENDING_HR', 'raised by HR goes straight to the HR approver');
  perform tst.as_user('mgr');
  perform public.hr_decide_overtime(tst.id('ot1'), true, null);
  perform tst.as_user('hrm');
  v := public.hr_decide_overtime(tst.id('ot1'), true, null);
  perform tst.check(v->>'status' = 'APPROVED', 'overtime approved');
  v := public.hr_attendance_summary(jsonb_build_object('entity_id', tst.id('ent'), 'month', to_char(tst.workday(1),'YYYY-MM')));
  perform tst.check((select (r->>'ot_pay_hours')::numeric from jsonb_array_elements(v->'rows') r
                     where r->>'employee_id' = tst.id('emp_w')::text) = 3.13, 'approved overtime reaches the payroll summary');
end $$;

-- ===========================================================================
-- 7. Leave types and opening balances
-- ===========================================================================
do $$
declare v jsonb; v_open date := (date_trunc('month', tst.today()) - interval '2 months')::date;
begin
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_save_leave_type(%L)', '{"code":"ANNUAL","quota_days":"35"}'), 'NOT_ALLOWED');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_save_leave_type(%L)', '{"code":"ANNUAL","quota_days":"25"}'), 'LEGAL_MINIMUM');
  v := public.hr_save_leave_type('{"code":"ANNUAL","quota_days":"32"}');
  perform tst.check((v->>'quota_days')::numeric = 32, 'company may give more than the law');
  perform public.hr_save_leave_type('{"code":"ANNUAL","quota_days":"30"}');
  perform tst.check(jsonb_array_length(public.hr_list_leave_types()) = 15, '15 leave types seeded');
  perform tst.as_user('admin');
  perform public.hr_save_setting('leave_opening_date', to_jsonb(v_open::text));
  perform tst.as_user('hro');
  v := public.hr_propose_leave_adjustments(jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('employee_id', tst.id('emp_mgr'), 'leave_type','ANNUAL', 'kind','OPENING', 'days', '12',
                            'effective_date', v_open::text, 'reason', 'Opening balance'))));
  perform tst.check((v->>'proposed')::int = 1, 'opening balance proposed');
  v := public.hr_propose_leave_adjustments(jsonb_build_object('rows', jsonb_build_array(
         jsonb_build_object('employee_id', tst.id('emp_mgr'), 'leave_type','ANNUAL', 'kind','OPENING', 'days', '3', 'reason', 'Twice'))));
  perform tst.check((v->>'proposed')::int = 0 and jsonb_array_length(v->'errors') = 1, 'only one opening balance per type');
  perform tst.expect_error(format('select public.hr_decide_leave_adjustments(array[%L]::uuid[], true)',
            (public.hr_list_leave_adjustments('{"status":"PENDING"}')->0->>'id')), 'NOT_ALLOWED');
  perform tst.as_user('hrm');
  perform public.hr_decide_leave_adjustments(array[(public.hr_list_leave_adjustments('{"status":"PENDING"}')->0->>'id')::uuid], true, null);
  perform tst.as_user('hro');
  v := public.hr_run_leave_accrual(null);
  perform tst.check((v->>'created')::int > 0, 'monthly accrual created');
  perform tst.check((public.hr_run_leave_accrual(null)->>'created')::int = 0, 'accrual is idempotent');
  perform tst.as_user('admin');
  perform tst.expect_error(format('select public.hr_save_setting(%L, %L)', 'leave_opening_date', '"2026-01-01"'), 'can no longer be changed');
  perform tst.as_user('mgr');
  perform tst.check((tst.bal(tst.id('emp_mgr'), 'ANNUAL')->>'available')::numeric = 17, '12 opening + 2 × 2.5 accrued = 17');
end $$;

-- ===========================================================================
-- 8. Leave requests: balance, eligibility, documents, sick-pay tiers, cancellation
-- ===========================================================================
do $$
declare v jsonb; t date := tst.today(); v_path text; v_path2 text;
begin
  perform tst.as_user('mgr');
  v := public.hr_request_leave(jsonb_build_object('employee_id', tst.id('emp_mgr'), 'leave_type', 'ANNUAL',
         'start_date', (t + 14)::text, 'end_date', (t + 18)::text, 'reason', 'Family trip'));
  perform tst.put('lv1', (v->>'id')::uuid);
  perform tst.check(v->>'status' = 'PENDING_HR' and (v->>'days')::numeric = 5, 'no line manager → HR');
  perform tst.expect_error(format('select public.hr_decide_leave(%L, true)', tst.id('lv1')), 'SELF_APPROVAL');
  perform tst.expect_error(format('select public.hr_request_leave(%L)', jsonb_build_object('employee_id', tst.id('emp_mgr'), 'leave_type','ANNUAL',
            'start_date', (t + 30)::text, 'end_date', (t + 59)::text)), 'BALANCE');
  perform tst.expect_error(format('select public.hr_request_leave(%L)', jsonb_build_object('employee_id', tst.id('emp_mgr'), 'leave_type','ANNUAL',
            'start_date', (t + 16)::text, 'end_date', (t + 17)::text)), 'OVERLAP');
  perform tst.as_user('hrm');
  v := public.hr_decide_leave(tst.id('lv1'), true, null);
  perform tst.check(v->>'status' = 'APPROVED' and v->'pay_breakdown'->0->>'pct' = '100', 'annual leave approved at full pay');
  perform tst.as_user('mgr');
  perform tst.check((tst.bal(tst.id('emp_mgr'), 'ANNUAL')->>'available')::numeric = 12, 'balance reduced by 5');
  v := public.hr_request_leave(jsonb_build_object('employee_id', tst.id('emp_mgr'), 'leave_type','ANNUAL', 'start_date', (t + 20)::text, 'half_day', true));
  perform tst.check((v->>'days')::numeric = 0.5, 'half day');
  perform tst.put('lv_half', (v->>'id')::uuid);

  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_request_leave(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'leave_type','ANNUAL',
            'start_date', (t + 5)::text, 'end_date', (t + 6)::text)), 'NOT_ELIGIBLE');
  perform tst.expect_error(format('select public.hr_request_leave(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'leave_type','MATERNITY',
            'start_date', (t + 5)::text, 'end_date', (t + 6)::text, 'event_date', (t + 5)::text)), 'NOT_ELIGIBLE');
  perform tst.expect_error(format('select public.hr_request_leave(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'leave_type','EXAM',
            'start_date', (t + 5)::text, 'end_date', (t + 6)::text)), 'NOT_ELIGIBLE');
  perform tst.expect_error(format('select public.hr_request_leave(%L)', jsonb_build_object('employee_id', tst.id('emp_w'), 'leave_type','PATERNITY',
            'start_date', (t - 7)::text, 'end_date', (t - 4)::text, 'event_date', (t - 5)::text)), 'within 98 days');
  v := public.hr_request_leave(jsonb_build_object('employee_id', tst.id('emp_w'), 'leave_type','SICK',
         'start_date', tst.workday(6)::text, 'end_date', tst.workday(6)::text, 'reason', 'Fever'));
  perform tst.put('sick1', (v->>'id')::uuid);
  perform tst.check(v->>'status' = 'PENDING_MANAGER', 'sick leave to manager');
  perform tst.as_user('mgr');
  perform tst.check(exists (select 1 from jsonb_array_elements(public.hr_list_leave_requests('{"scope":"team"}')->'rows') r
                    where r->>'id' = tst.id('sick1')::text), 'manager sees team requests');
  perform public.hr_decide_leave(tst.id('sick1'), true, 'Get well');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_decide_leave(%L, true)', tst.id('sick1')), 'supporting document');
  perform tst.as_user('emp');
  v_path := tst.id('emp_w') || '/MEDICAL_CERT/med1.pdf';
  insert into storage.objects(bucket_id, name) values ('hr-documents', v_path);
  perform tst.expect_error(format('insert into storage.objects(bucket_id, name) values (''hr-documents'', %L)',
            tst.id('emp_w') || '/PASSPORT/self.pdf'), 'row-level security');
  v := public.hr_attach_leave_document(tst.id('sick1'), jsonb_build_object('doc_type','MEDICAL_CERT', 'file_path', v_path, 'file_name','med1.pdf'));
  perform tst.check(v->>'document_id' is not null, 'employee attached own medical certificate');
  perform tst.as_user('hrm');
  v := public.hr_decide_leave(tst.id('sick1'), true, null);
  perform tst.check(v->>'status' = 'APPROVED', 'sick leave approved');
  perform tst.check(tst.day(tst.id('emp_w'), tst.workday(6))->>'status' = 'LEAVE', 'attendance shows leave');

  -- sick-pay tiers: 25 days = 21 at 100 % + 4 at 75 %
  perform tst.as_user('hro');
  v := public.hr_request_leave(jsonb_build_object('employee_id', tst.id('emp_om'), 'leave_type','SICK',
         'start_date', (t + 1)::text, 'end_date', (t + 25)::text));
  perform tst.put('sick2', (v->>'id')::uuid);
  perform tst.check(v->>'status' = 'PENDING_HR', 'raised by HR');
  v_path2 := tst.id('emp_om') || '/MEDICAL_CERT/med2.pdf';
  insert into storage.objects(bucket_id, name) values ('hr-documents', v_path2);
  perform public.hr_attach_leave_document(tst.id('sick2'), jsonb_build_object('doc_type','MEDICAL_CERT', 'file_path', v_path2));
  perform tst.as_user('hrm');
  v := public.hr_decide_leave(tst.id('sick2'), true, null);
  perform tst.check(v->'pay_breakdown' = '[{"pct":100,"days":21},{"pct":75,"days":4}]'::jsonb, 'Art. 82 tiers applied');

  -- HR manager cannot approve leave they raised
  v := public.hr_request_leave(jsonb_build_object('employee_id', tst.id('emp_om'), 'leave_type','ANNUAL',
         'start_date', (t + 40)::text, 'end_date', (t + 41)::text));
  perform tst.expect_error(format('select public.hr_decide_leave(%L, true)', v->>'id'), 'SELF_APPROVAL');
  perform tst.as_user('admin');
  perform tst.check(public.hr_decide_leave((v->>'id')::uuid, true, null)->>'status' = 'APPROVED', 'another approver decides');

  -- cancellation of approved leave
  perform tst.as_user('mgr');
  perform tst.expect_error(format('select public.hr_cancel_leave(%L, %L)', tst.id('lv1'), 'Changed plans'), 'NOT_ALLOWED');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_cancel_leave(%L)', tst.id('lv1')), 'REQUIRED');
  v := public.hr_cancel_leave(tst.id('lv1'), 'Trip postponed');
  perform tst.check(v->>'status' = 'CANCELLED', 'cancelled');
  perform tst.as_user('mgr');
  perform tst.check((tst.bal(tst.id('emp_mgr'), 'ANNUAL')->>'available')::numeric = 17, 'days returned to the balance');
  perform tst.as_user('hro');
  v := public.hr_leave_calendar(jsonb_build_object('month', to_char(t + 1, 'YYYY-MM'), 'entity_id', tst.id('ent')));
  perform tst.check(exists (select 1 from jsonb_array_elements(v->'rows') r where r->>'employee_id' = tst.id('emp_om')::text), 'leave calendar');
  v := public.hr_list_leave_balances(jsonb_build_object('entity_id', tst.id('ent'), 'leave_type', 'ANNUAL'));
  perform tst.check(jsonb_array_length(v) >= 3, 'balances report');
end $$;

-- ===========================================================================
-- 9. Tasks and dashboard
-- ===========================================================================
do $$
declare v jsonb;
begin
  perform tst.as_user('mgr');
  v := public.hr_time_dashboard();
  perform tst.check(v ? 'today' and v ? 'mine' and v->'mine'->'annual' is not null, 'manager dashboard: team today and own balance');
  perform tst.as_user('hrm');
  v := public.hr_list_my_tasks();
  perform tst.check((v->>'count')::int >= 2, 'HR manager has items to decide (overtime and half day)');
  perform tst.check(exists (select 1 from jsonb_array_elements(v->'leave') x where x->>'id' = tst.id('lv_half')::text), 'half day waiting');
  perform tst.as_user('emp');
  perform tst.check((public.hr_list_my_tasks()->>'count')::int = 0, 'employee decides nothing');
end $$;

-- ===========================================================================
-- 10. Time rules: dated changes with maker-checker
-- ===========================================================================
do $$
declare v jsonb; t date := tst.today(); v_id text;
begin
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_propose_time_rule(%L)', jsonb_build_object('code','OVERTIME', 'effective_from', (t + 60)::text,
            'legal_basis', 'x', 'value', jsonb_build_object('day_premium', 'a'))), 'INVALID');
  v := public.hr_propose_time_rule(jsonb_build_object('code','OVERTIME', 'effective_from', (t + 60)::text, 'legal_basis', 'Test amendment',
         'value', jsonb_build_object('day_premium', 0.30, 'night_premium', 0.5, 'rest_day_premium', 1, 'max_total_daily_hours', 12,
                                     'night_start', '21:00', 'night_end', '05:00')));
  v_id := (select x->>'id' from jsonb_array_elements(v) x where x->>'status' = 'PENDING' and x->>'code' = 'OVERTIME');
  perform tst.as_user('hrm');
  v := public.hr_decide_time_rule(v_id::uuid, true, null);
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where x->>'code' = 'OVERTIME' and x->>'status' = 'APPROVED'
                    and (x->>'effective_to')::date = t + 59), 'current value closes the day before the new one');
  v := public.hr_propose_time_rule(jsonb_build_object('code','WEEKLY_REST', 'effective_from', (t + 90)::text, 'legal_basis', 'Test',
         'value', jsonb_build_object('min_consecutive_days', 2)));
  v_id := (select x->>'id' from jsonb_array_elements(v) x where x->>'status' = 'PENDING' and x->>'code' = 'WEEKLY_REST');
  perform tst.expect_error(format('select public.hr_decide_time_rule(%L, true)', v_id), 'SELF_APPROVAL');
  perform tst.as_user('admin');
  perform public.hr_decide_time_rule(v_id::uuid, true, null);
end $$;

-- ===========================================================================
-- 11. Locking a month
-- ===========================================================================
do $$
declare v jsonb; v_prev date := (date_trunc('month', tst.today()) - interval '1 month')::date; v_no text;
begin
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_lock_period(%L, %L)', tst.id('ent'), to_char(v_prev, 'YYYY-MM')), 'NOT_ALLOWED');
  v_no := public.hr_get_employee(tst.id('emp_w'))->'employee'->>'employee_no';
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_lock_period(%L, %L)', tst.id('ent'), to_char(tst.today(), 'YYYY-MM')), 'completed month');
  v := public.hr_lock_period(tst.id('ent'), to_char(v_prev, 'YYYY-MM'));
  perform tst.check(exists (select 1 from jsonb_array_elements(v) m where m->>'month' = to_char(v_prev,'YYYY-MM') and m->>'status' = 'LOCKED'), 'month locked');
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_request_correction(%L)', jsonb_build_object('employee_id', tst.id('emp_w'),
            'work_date', (v_prev + 14)::text, 'in_time', '07:00', 'reason', 'Locked month')), 'PERIOD_LOCKED');
  perform tst.as_user('hro');
  v := public.hr_import_punches(jsonb_build_object('ref_kind','EMPLOYEE_NO', 'rows', jsonb_build_array(jsonb_build_object('ref', v_no, 'at', (v_prev + 14) || ' 07:00'))));
  perform tst.check((v->>'rows_error')::int = 1 and v->'errors'->0->>'message' like '%locked%', 'no punches into a locked month');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_unlock_period(%L, %L, %L)', tst.id('ent'), to_char(v_prev, 'YYYY-MM'), ''), 'REQUIRED');
  v := public.hr_unlock_period(tst.id('ent'), to_char(v_prev, 'YYYY-MM'), 'Late medical certificate');
  perform tst.check(exists (select 1 from jsonb_array_elements(v) m where m->>'month' = to_char(v_prev,'YYYY-MM') and m->>'status' = 'OPEN'), 'unlocked with a reason');
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_recompute_attendance(%L)', '{"from":"2026-01-01"}'), 'NOT_ALLOWED');
  perform tst.as_user('hro');
  perform tst.expect_error(format('select public.hr_recompute_attendance(%L)', '{"from":"2025-01-01","to":"2025-12-31"}'), 'at most 93');
end $$;

-- ===========================================================================
-- 12. Every remaining list/maintenance call works for the right role
-- ===========================================================================
do $$
declare v jsonb; t date := tst.today(); v_ot text;
begin
  perform tst.as_user('hro');
  v := public.hr_save_special_period(jsonb_build_object('start_date', (t + 100)::text, 'end_date', (t + 128)::text));
  perform tst.check(jsonb_array_length(v->'ramadan') >= 0, 'Ramadan period saved');
  perform tst.expect_error(format('select public.hr_save_special_period(%L)', jsonb_build_object('start_date', (t + 110)::text, 'end_date', (t + 120)::text)), 'OVERLAP');
  perform tst.check(jsonb_array_length(public.hr_list_holidays(extract(year from tst.workday(3))::int, null)->'holidays') >= 1, 'holidays listed');
  perform tst.check(jsonb_array_length(public.hr_list_device_users(null)) = 1, 'device ids listed');
  perform tst.check(jsonb_array_length(public.hr_list_punch_batches(null)) >= 2, 'import batches listed');
  perform tst.check(jsonb_array_length(public.hr_list_punches(tst.id('emp_w'), tst.workday(1))) >= 2, 'punches of a day');
  perform tst.check(jsonb_array_length(public.hr_list_corrections('{}')) >= 1, 'corrections listed');
  perform tst.check(jsonb_array_length(public.hr_list_overtime('{"status":"PENDING"}')) >= 1, 'pending overtime listed');
  perform tst.check(jsonb_array_length(public.hr_list_shifts(tst.id('ent'))) >= 4, 'shifts listed');
  perform tst.check(jsonb_array_length(public.hr_list_shift_assignments(jsonb_build_object('shift_id', tst.id('shift_day')))) >= 2, 'who is on a shift');
  perform tst.check(jsonb_array_length(public.hr_list_periods(tst.id('ent'), null)) = 12, 'twelve months');
  perform tst.check(jsonb_array_length(public.hr_leave_balances(tst.id('emp_w'))->'ledger') >= 1, 'ledger shown');
  perform tst.check((public.hr_recompute_attendance(jsonb_build_object('from', (t - 7)::text, 'employee_id', tst.id('emp_w')))->>'days')::int >= 7, 'recompute');
  -- emergency overtime without consent: HR records that the authority was notified
  v := public.hr_request_overtime(jsonb_build_object('employee_id', tst.id('emp_om'), 'work_date', tst.next_workday(4)::text,
         'start_time','17:00', 'end_time','19:00', 'basis','EMERGENCY', 'reason','Pipe burst'));
  perform tst.check((v->>'pay_hours')::numeric = 3.00 and v->'rates'->>'rule' = 'OVERTIME_NO_CONSENT', 'no-consent rates: 2 h × 1.50');
  v := public.hr_set_overtime_notified((v->>'id')::uuid);
  perform tst.check((v->>'authority_notified')::boolean, 'authority notification recorded');
  v_ot := v->>'id';
  perform tst.as_user('emp');
  v := public.hr_request_correction(jsonb_build_object('employee_id', tst.id('emp_w'), 'work_date', tst.workday(7)::text,
         'in_time','07:00', 'out_time','16:00', 'reason','Device was down'));
  perform tst.check(public.hr_cancel_correction((v->>'id')::uuid)->>'status' = 'CANCELLED', 'requester withdraws a correction');
  perform tst.expect_error(format('select public.hr_cancel_overtime(%L)', v_ot), 'NOT_ALLOWED');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_close_leave_year(%s)', extract(year from t)::int), 'finished year');
  v := public.hr_close_leave_year(extract(year from t)::int - 1);
  perform tst.check(v ? 'lapsed', 'previous year closed');
  perform tst.expect_error(format('select public.hr_set_ticket_status(%L, %L)', tst.id('sick1'), 'ISSUED'), 'NOT_FOUND');
end $$;

reset role;
select 'ALL PHASE 2 TESTS PASSED' as result;
