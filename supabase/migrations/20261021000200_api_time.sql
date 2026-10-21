-- AACT HRMS — 011 API: time rules, shifts & rosters, calendar, punches, attendance, corrections, overtime, periods.

create or replace function hr.emp_brief(p_employee uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en,
                            'full_name_ar', e.full_name_ar, 'entity_id', e.entity_id,
                            'department_en', d.name_en, 'department_ar', d.name_ar)
  from hr.employees e
  left join hr.employee_assignments a on a.id = (hr.current_assignment(e.id)).id
  left join hr.departments d on d.id = a.department_id
  where e.id = p_employee
$$;

-- Employees whose time data the caller may see: everyone (with the permission), else self + team.
create or replace function hr.visible_employees(p_perm text, p_entity uuid default null)
returns table(employee_id uuid) language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  if hr.has_perm(p_perm) then
    return query select e.id from hr.employees e where p_entity is null or e.entity_id = p_entity;
  else
    return query
      select e.id from hr.employees e
      where (e.id = hr.my_employee_id() or e.id in (select t.employee_id from hr.team_of(hr.my_employee_id()) t))
        and (p_entity is null or e.entity_id = p_entity);
  end if;
end $$;

create or replace function hr.hhmm(p timestamptz)
returns text language sql stable set search_path = '' as $$
  select to_char(p at time zone 'Asia/Muscat', 'HH24:MI')
$$;

create or replace function hr.month_start(p text)
returns date language plpgsql immutable set search_path = '' as $$
begin
  if p is null or p !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'INVALID_DATE: Month must be YYYY-MM.'; end if;
  return (p || '-01')::date;
end $$;

-- ---------------------------------------------------------------------------
-- Time rules
-- ---------------------------------------------------------------------------
create or replace function hr.time_rule_json(r hr.time_rules)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(r) - 'proposed_by' - 'decided_by'
         || jsonb_build_object('proposed_by_name', hr.user_label(r.proposed_by), 'decided_by_name', hr.user_label(r.decided_by),
                               'can_decide', r.status = 'PENDING' and hr.has_perm('RULES_APPROVE')
                                             and auth.uid() is distinct from r.proposed_by)
$$;

create or replace function public.hr_list_time_rules()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.time_rule_json(r) order by r.code, r.effective_from desc, r.proposed_at desc)
                   from hr.time_rules r where r.status <> 'REJECTED' or r.proposed_at > now() - interval '90 days'), '[]'::jsonb);
end $$;

create or replace function public.hr_propose_time_rule(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_code text := hr.jtext(p,'code'); v_val jsonb := p->'value'; v_from date := hr.jdate(p,'effective_from');
  v_keys text[]; k text; v_id uuid;
begin
  perform hr.require_perm('RULES_PROPOSE');
  if v_code is null or v_val is null or jsonb_typeof(v_val) <> 'object' or v_from is null then
    raise exception 'REQUIRED: Rule, values and effective date are required.';
  end if;
  if coalesce(hr.jtext(p,'legal_basis'), '') = '' then raise exception 'REQUIRED: Give the legal basis or policy reference.'; end if;
  v_keys := case v_code
    when 'WORK_HOURS' then array['daily_max_hours','weekly_max_hours','break_minutes','max_continuous_hours']
    when 'RAMADAN_HOURS' then array['daily_max_hours','weekly_max_hours']
    when 'WEEKLY_REST' then array['min_consecutive_days']
    when 'OVERTIME' then array['day_premium','night_premium','rest_day_premium','max_total_daily_hours']
    when 'OVERTIME_NO_CONSENT' then array['day_premium','night_premium','rest_day_premium','max_inventory_days_per_year']
    when 'ATTENDANCE' then array['late_grace_minutes','window_before_minutes','window_after_minutes','min_minutes_between_punches']
    else null end;
  if v_keys is null then raise exception 'INVALID: Unknown rule %.', v_code; end if;
  foreach k in array v_keys loop
    if jsonb_typeof(v_val->k) <> 'number' or (v_val->>k)::numeric < 0 then
      raise exception 'INVALID: % must be a number of zero or more.', k;
    end if;
  end loop;
  if v_code = 'OVERTIME' then
    if coalesce(v_val->>'night_start','') !~ '^\d{2}:\d{2}$' or coalesce(v_val->>'night_end','') !~ '^\d{2}:\d{2}$' then
      raise exception 'INVALID: Night start and end must be HH:MM.';
    end if;
  end if;
  if exists (select 1 from hr.time_rules where code = v_code and status = 'PENDING') then
    raise exception 'PENDING_EXISTS: A change to this rule is already waiting for approval.';
  end if;
  insert into hr.time_rules(code, value, effective_from, rule_basis, legal_basis, status, proposed_by)
  values (v_code, v_val, v_from, coalesce(hr.jtext(p,'rule_basis'), 'LEGAL'), hr.jtext(p,'legal_basis'), 'PENDING', auth.uid())
  returning id into v_id;
  perform hr.notify_approvers(null, 'PENDING_HR', 'RULES_APPROVE', 'RULE', 'Time rule change waiting: ' || v_code,
                              'تغيير قاعدة وقت بانتظار الاعتماد: ' || v_code, '/approvals', 'rule:' || v_id);
  return public.hr_list_time_rules();
end $$;

create or replace function public.hr_decide_time_rule(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.time_rules;
begin
  perform hr.require_perm('RULES_APPROVE');
  select * into r from hr.time_rules where id = p_id for update;
  if r.id is null or r.status <> 'PENDING' then raise exception 'NOT_FOUND: This rule change is no longer waiting.'; end if;
  if r.proposed_by = auth.uid() then raise exception 'SELF_APPROVAL: Someone other than the proposer must approve this rule.'; end if;
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  if p_approve then
    if exists (select 1 from hr.time_rules where code = r.code and status = 'APPROVED' and effective_from >= r.effective_from) then
      raise exception 'OVERLAP: An approved value already starts on or after %.', to_char(r.effective_from, 'DD/MM/YYYY');
    end if;
    update hr.time_rules set effective_to = r.effective_from - 1
     where code = r.code and status = 'APPROVED' and (effective_to is null or effective_to >= r.effective_from);
  end if;
  update hr.time_rules set status = case when p_approve then 'APPROVED' else 'REJECTED' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note),'')
   where id = p_id;
  return public.hr_list_time_rules();
end $$;

-- ---------------------------------------------------------------------------
-- Shifts and rosters
-- ---------------------------------------------------------------------------
create or replace function hr.shift_json(s hr.shifts)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(s) || jsonb_build_object(
    'start_time', to_char(s.start_time, 'HH24:MI'), 'end_time', to_char(s.end_time, 'HH24:MI'),
    'net_minutes', hr.shift_net_minutes(s),
    'weekly_minutes', hr.shift_net_minutes(s) * (7 - coalesce(array_length(s.rest_days, 1), 0)),
    'crosses_midnight', s.end_time <= s.start_time,
    'assigned', (select count(*) from hr.shift_assignments a where a.shift_id = s.id
                 and a.effective_from <= hr.today() and (a.effective_to is null or a.effective_to >= hr.today())))
$$;

create or replace function public.hr_list_shifts(p_entity uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.shift_json(s) order by s.is_active desc, s.code)
                   from hr.shifts s where p_entity is null or s.entity_id = p_entity), '[]'::jsonb);
end $$;

create or replace function public.hr_save_shift(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); s hr.shifts; v_rest int[];
begin
  perform hr.require_perm('ATT_WRITE');
  if p ? 'rest_days' then
    select array_agg(x::int order by x::int) into v_rest from jsonb_array_elements_text(p->'rest_days') x;
  end if;
  if v_id is null then
    if hr.juuid(p,'entity_id') is null or hr.jtext(p,'code') is null or hr.jtext(p,'name_en') is null
       or hr.jtime(p,'start_time') is null or hr.jtime(p,'end_time') is null then
      raise exception 'REQUIRED: Company, code, name, start and end time are required.';
    end if;
    if exists (select 1 from hr.shifts where entity_id = hr.juuid(p,'entity_id') and code = upper(hr.jtext(p,'code'))) then
      raise exception 'DUPLICATE: A shift with this code already exists.';
    end if;
    s.id := gen_random_uuid(); s.entity_id := hr.juuid(p,'entity_id'); s.code := upper(hr.jtext(p,'code'));
    s.is_active := true;
  else
    select * into s from hr.shifts where id = v_id for update;
    if s.id is null then raise exception 'NOT_FOUND: Shift not found.'; end if;
  end if;
  if p ? 'name_en' then s.name_en := hr.jtext(p,'name_en'); end if;
  if p ? 'name_ar' then s.name_ar := hr.jtext(p,'name_ar'); end if;
  if p ? 'start_time' then s.start_time := hr.jtime(p,'start_time'); end if;
  if p ? 'end_time' then s.end_time := hr.jtime(p,'end_time'); end if;
  if p ? 'break_minutes' then s.break_minutes := coalesce(hr.jint(p,'break_minutes'), 0); end if;
  if p ? 'grace_minutes' then s.grace_minutes := hr.jint(p,'grace_minutes'); end if;
  if p ? 'rest_days' then s.rest_days := coalesce(v_rest, '{}'); end if;
  if p ? 'is_ramadan' then s.is_ramadan := hr.jbool(p,'is_ramadan'); end if;
  if p ? 'notes' then s.notes := hr.jtext(p,'notes'); end if;
  if p ? 'is_active' then s.is_active := hr.jbool(p,'is_active', true); end if;
  s.break_minutes := coalesce(s.break_minutes, 60); s.rest_days := coalesce(s.rest_days, '{5,6}');
  s.is_ramadan := coalesce(s.is_ramadan, false);
  if s.name_en is null or s.start_time is null or s.end_time is null then raise exception 'REQUIRED: Name, start and end time are required.'; end if;
  if s.start_time = s.end_time then raise exception 'INVALID: Start and end time cannot be the same.'; end if;
  perform hr.validate_shift(s);
  if v_id is null then
    insert into hr.shifts(id, entity_id, code, name_en, name_ar, start_time, end_time, break_minutes, grace_minutes, rest_days, is_ramadan, notes, is_active)
    values (s.id, s.entity_id, s.code, s.name_en, s.name_ar, s.start_time, s.end_time, s.break_minutes, s.grace_minutes, s.rest_days, s.is_ramadan, s.notes, s.is_active);
  else
    update hr.shifts set name_en = s.name_en, name_ar = s.name_ar, start_time = s.start_time, end_time = s.end_time,
           break_minutes = s.break_minutes, grace_minutes = s.grace_minutes, rest_days = s.rest_days, is_ramadan = s.is_ramadan,
           notes = s.notes, is_active = s.is_active
     where id = s.id;
  end if;
  select * into s from hr.shifts where id = s.id;
  return hr.shift_json(s);
end $$;

create or replace function public.hr_list_shift_assignments(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_shift uuid := hr.juuid(p,'shift_id'); v_on date := coalesce(hr.jdate(p,'on'), hr.today());
begin
  perform hr.require_user();
  if v_emp is not null then
    if not hr.can_see_time(v_emp, 'ATT_READ') then raise exception 'NOT_ALLOWED: You cannot see this employee.' using errcode = '42501'; end if;
  elsif not hr.has_perm('ATT_READ') then
    raise exception 'NOT_ALLOWED: You do not have the ATT_READ permission.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'employee_id', a.employee_id, 'shift_id', a.shift_id,
             'shift_code', s.code, 'shift_name_en', s.name_en, 'shift_name_ar', s.name_ar,
             'effective_from', a.effective_from, 'effective_to', a.effective_to, 'notes', a.notes,
             'created_by_name', hr.user_label(a.created_by), 'created_at', a.created_at) || hr.emp_brief(a.employee_id)
           order by a.effective_from desc)
    from hr.shift_assignments a join hr.shifts s on s.id = a.shift_id
    where (v_emp is null or a.employee_id = v_emp)
      and (v_shift is null or a.shift_id = v_shift)
      and (v_emp is not null or (a.effective_from <= v_on and (a.effective_to is null or a.effective_to >= v_on)))), '[]'::jsonb);
end $$;

-- Give a shift to employees for a period. Earlier open assignments are closed; a temporary period
-- (e.g. Ramadan) inside an open assignment splits it, so the old shift resumes afterwards.
create or replace function public.hr_assign_shift(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_shift uuid := hr.juuid(p,'shift_id'); v_from date := hr.jdate(p,'effective_from'); v_to date := hr.jdate(p,'effective_to');
  v_emp uuid; x record; s hr.shifts; v_n int := 0; v_ids uuid[];
begin
  perform hr.require_perm('ATT_WRITE');
  if v_shift is null or v_from is null then raise exception 'REQUIRED: Shift and start date are required.'; end if;
  if v_to is not null and v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  select * into s from hr.shifts where id = v_shift and is_active;
  if s.id is null then raise exception 'NOT_FOUND: Shift not found or inactive.'; end if;
  select array_agg(distinct (v #>> '{}')::uuid) into v_ids from jsonb_array_elements(coalesce(p->'employee_ids','[]'::jsonb)) v;
  if v_ids is null or array_length(v_ids,1) = 0 then raise exception 'REQUIRED: Choose at least one employee.'; end if;
  foreach v_emp in array v_ids loop
    if not exists (select 1 from hr.employees where id = v_emp and entity_id = s.entity_id) then
      raise exception 'INVALID: An employee is not in the shift''s company.';
    end if;
    if v_from < hr.today() then perform hr.assert_open(v_emp, v_from, least(coalesce(v_to, hr.today()), hr.today())); end if;
    if exists (select 1 from hr.shift_assignments a where a.employee_id = v_emp and a.effective_from >= v_from
               and (v_to is null or a.effective_from <= v_to)) then
      raise exception 'OVERLAP: % already has a shift starting on or after %. Change that one instead.',
        (select employee_no from hr.employees where id = v_emp), to_char(v_from, 'DD/MM/YYYY');
    end if;
    for x in select * from hr.shift_assignments a where a.employee_id = v_emp and a.effective_from < v_from
             and (a.effective_to is null or a.effective_to >= v_from) loop
      update hr.shift_assignments set effective_to = v_from - 1 where id = x.id;
      if v_to is not null and (x.effective_to is null or x.effective_to > v_to) then
        insert into hr.shift_assignments(employee_id, shift_id, effective_from, effective_to, notes, created_by)
        values (v_emp, x.shift_id, v_to + 1, x.effective_to, coalesce(x.notes, 'Resumes after a temporary shift'), auth.uid());
      end if;
    end loop;
    insert into hr.shift_assignments(employee_id, shift_id, effective_from, effective_to, notes, created_by)
    values (v_emp, v_shift, v_from, v_to, hr.jtext(p,'notes'), auth.uid());
    if v_from <= hr.today() then
      perform hr.compute_attendance(v_emp, greatest(v_from, hr.today() - 92), least(coalesce(v_to, hr.today()), hr.today()));
    end if;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('assigned', v_n);
end $$;

-- ---------------------------------------------------------------------------
-- Calendar
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_holidays(p_year int default null, p_entity uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_year int := coalesce(p_year, extract(year from hr.today())::int);
begin
  perform hr.require_user();
  return jsonb_build_object(
    'holidays', coalesce((select jsonb_agg(to_jsonb(h) - 'created_by' || jsonb_build_object('created_by_name', hr.user_label(h.created_by))
                                  order by h.holiday_date)
                          from hr.holidays h where h.is_active and extract(year from h.holiday_date) = v_year
                            and (h.entity_id is null or p_entity is null or h.entity_id = p_entity)), '[]'::jsonb),
    'ramadan', coalesce((select jsonb_agg(to_jsonb(sp) - 'created_by' order by sp.start_date)
                         from hr.special_periods sp where extract(year from sp.start_date) = v_year
                            or extract(year from sp.end_date) = v_year), '[]'::jsonb));
end $$;

create or replace function public.hr_save_holiday(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); h hr.holidays; v_date date; v_entity uuid; r record;
begin
  perform hr.require_perm('ATT_WRITE');
  if v_id is not null then
    select * into h from hr.holidays where id = v_id;
    if h.id is null then raise exception 'NOT_FOUND: Holiday not found.'; end if;
  end if;
  v_date := coalesce(hr.jdate(p,'holiday_date'), h.holiday_date);
  v_entity := case when p ? 'entity_id' then hr.juuid(p,'entity_id') else h.entity_id end;
  if v_date is null or coalesce(hr.jtext(p,'name_en'), h.name_en) is null then raise exception 'REQUIRED: Date and name are required.'; end if;
  if exists (select 1 from hr.attendance_periods ap where ap.status = 'LOCKED' and ap.period_start = date_trunc('month', v_date)::date
             and (v_entity is null or ap.entity_id = v_entity))
     or (h.id is not null and exists (select 1 from hr.attendance_periods ap where ap.status = 'LOCKED'
             and ap.period_start = date_trunc('month', h.holiday_date)::date)) then
    raise exception 'PERIOD_LOCKED: Attendance for that month is locked.';
  end if;
  if v_id is null then
    if exists (select 1 from hr.holidays x where x.is_active and x.holiday_date = v_date
               and coalesce(x.entity_id,'00000000-0000-0000-0000-000000000000') = coalesce(v_entity,'00000000-0000-0000-0000-000000000000')) then
      raise exception 'DUPLICATE: A holiday already exists on this date.';
    end if;
    insert into hr.holidays(entity_id, holiday_date, name_en, name_ar, kind, source_reference, created_by)
    values (v_entity, v_date, hr.jtext(p,'name_en'), hr.jtext(p,'name_ar'), coalesce(hr.jtext(p,'kind'),'PUBLIC'),
            hr.jtext(p,'source_reference'), auth.uid())
    returning * into h;
  else
    update hr.holidays set holiday_date = v_date, entity_id = v_entity,
           name_en = coalesce(hr.jtext(p,'name_en'), name_en), name_ar = case when p ? 'name_ar' then hr.jtext(p,'name_ar') else name_ar end,
           kind = coalesce(hr.jtext(p,'kind'), kind),
           source_reference = case when p ? 'source_reference' then hr.jtext(p,'source_reference') else source_reference end,
           is_active = case when p ? 'is_active' then hr.jbool(p,'is_active', true) else is_active end
     where id = v_id;
  end if;
  for r in select distinct x.d from (select v_date as d union select h.holiday_date) x where x.d is not null and x.d <= hr.today() loop
    perform hr.compute_attendance(e.id, r.d, r.d) from hr.employees e
     where e.status <> 'SEPARATED' and (v_entity is null or e.entity_id = v_entity);
  end loop;
  return public.hr_list_holidays(extract(year from v_date)::int, null);
end $$;

create or replace function public.hr_save_special_period(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); v_from date := hr.jdate(p,'start_date'); v_to date := hr.jdate(p,'end_date');
begin
  perform hr.require_perm('ATT_WRITE');
  if v_from is null or v_to is null or v_to < v_from then raise exception 'INVALID: Give a valid start and end date.'; end if;
  if v_to - v_from > 31 then raise exception 'INVALID: Ramadan cannot be longer than 31 days.'; end if;
  if exists (select 1 from hr.special_periods x where x.id is distinct from v_id
             and daterange(x.start_date, x.end_date, '[]') && daterange(v_from, v_to, '[]')) then
    raise exception 'OVERLAP: This overlaps another Ramadan period.';
  end if;
  if v_id is null then
    insert into hr.special_periods(code, start_date, end_date, name_en, name_ar, notes, created_by)
    values ('RAMADAN', v_from, v_to, coalesce(hr.jtext(p,'name_en'), 'Ramadan ' || extract(year from v_from)),
            coalesce(hr.jtext(p,'name_ar'), 'رمضان ' || extract(year from v_from)), hr.jtext(p,'notes'), auth.uid());
  else
    update hr.special_periods set start_date = v_from, end_date = v_to, name_en = coalesce(hr.jtext(p,'name_en'), name_en),
           name_ar = coalesce(hr.jtext(p,'name_ar'), name_ar), notes = hr.jtext(p,'notes')
     where id = v_id;
    if not found then raise exception 'NOT_FOUND: Period not found.'; end if;
  end if;
  return public.hr_list_holidays(extract(year from v_from)::int, null);
end $$;

-- ---------------------------------------------------------------------------
-- Device ids and punch import
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_device_users(p_entity uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('ATT_READ');
  return coalesce((select jsonb_agg(jsonb_build_object('device_code', d.device_code, 'device_user_id', d.device_user_id)
                                    || hr.emp_brief(d.employee_id) order by d.device_code, d.device_user_id)
                   from hr.device_users d join hr.employees e on e.id = d.employee_id
                   where p_entity is null or e.entity_id = p_entity), '[]'::jsonb);
end $$;

create or replace function public.hr_set_device_user(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_dev text := coalesce(upper(hr.jtext(p,'device_code')), 'DEFAULT');
        v_uid text := hr.jtext(p,'device_user_id');
begin
  perform hr.require_perm('ATT_WRITE');
  if v_emp is null or not exists (select 1 from hr.employees where id = v_emp) then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if v_uid is null then
    delete from hr.device_users where employee_id = v_emp and device_code = v_dev;
  else
    if exists (select 1 from hr.device_users where device_code = v_dev and device_user_id = v_uid and employee_id <> v_emp) then
      raise exception 'DUPLICATE: Device id % is already used by another employee.', v_uid;
    end if;
    insert into hr.device_users(device_code, device_user_id, employee_id) values (v_dev, v_uid, v_emp)
    on conflict (employee_id, device_code) do update set device_user_id = excluded.device_user_id;
  end if;
  return public.hr_list_device_users(null);
end $$;

-- rows: [{ref, at: 'YYYY-MM-DD HH:MM[:SS]' (Muscat time), dir: 'IN'|'OUT'|null}], at most 5000 per call
create or replace function public.hr_import_punches(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_kind text := coalesce(upper(hr.jtext(p,'ref_kind')), 'EMPLOYEE_NO'); v_dev text := coalesce(upper(hr.jtext(p,'device_code')), 'DEFAULT');
  v_entity uuid := hr.juuid(p,'entity_id'); v_batch uuid; r jsonb; i int := 0; v_emp uuid; v_at timestamptz; v_ref text; v_dir text;
  v_ok int := 0; v_dup int := 0; v_err int := 0; v_errors jsonb := '[]'::jsonb; v_rows int; v_min date; v_max date; x record;
  v_touched uuid[] := '{}';
begin
  perform hr.require_perm('ATT_WRITE');
  if v_kind not in ('EMPLOYEE_NO','DEVICE_ID','CIVIL') then raise exception 'INVALID: Unknown employee reference type.'; end if;
  if jsonb_typeof(p->'rows') <> 'array' then raise exception 'REQUIRED: No rows to import.'; end if;
  if jsonb_array_length(p->'rows') > 5000 then raise exception 'INVALID: Import at most 5000 rows at a time.'; end if;
  insert into hr.punch_batches(entity_id, file_name, ref_kind, rows_total, created_by)
  values (v_entity, hr.jtext(p,'file_name'), v_kind, jsonb_array_length(p->'rows'), auth.uid()) returning id into v_batch;
  for r in select * from jsonb_array_elements(p->'rows') loop
    i := i + 1;
    begin
      v_ref := nullif(btrim(r->>'ref'), '');
      if v_ref is null then raise exception 'Employee reference is empty.'; end if;
      v_emp := case v_kind
        when 'EMPLOYEE_NO' then (select id from hr.employees where upper(employee_no) = upper(v_ref))
        when 'CIVIL' then (select id from hr.employees where upper(civil_number) = upper(v_ref))
        else (select employee_id from hr.device_users where device_code = v_dev and device_user_id = v_ref) end;
      if v_emp is null then raise exception 'No employee for %.', v_ref; end if;
      if v_entity is not null and not exists (select 1 from hr.employees where id = v_emp and entity_id = v_entity) then
        raise exception 'Employee % is in another company.', v_ref;
      end if;
      if coalesce(r->>'at','') !~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$' then raise exception 'Date/time must be YYYY-MM-DD HH:MM.'; end if;
      v_at := (replace(r->>'at', 'T', ' '))::timestamp at time zone 'Asia/Muscat';
      if v_at > now() + interval '10 minutes' then raise exception 'Punch is in the future.'; end if;
      if hr.is_locked(v_emp, (v_at at time zone 'Asia/Muscat')::date) then raise exception 'Month is locked.'; end if;
      v_dir := upper(nullif(btrim(coalesce(r->>'dir','')), ''));
      if v_dir is not null and v_dir not in ('IN','OUT') then v_dir := null; end if;
      insert into hr.punches(employee_id, punch_at, direction, source, batch_id, created_by)
      values (v_emp, v_at, v_dir, 'IMPORT', v_batch, auth.uid())
      on conflict (employee_id, punch_at) do nothing;
      get diagnostics v_rows = row_count;
      if v_rows = 0 then v_dup := v_dup + 1; else
        v_ok := v_ok + 1;
        v_min := least(coalesce(v_min, (v_at at time zone 'Asia/Muscat')::date), (v_at at time zone 'Asia/Muscat')::date);
        v_max := greatest(coalesce(v_max, (v_at at time zone 'Asia/Muscat')::date), (v_at at time zone 'Asia/Muscat')::date);
        if not v_emp = any(v_touched) then v_touched := v_touched || v_emp; end if;
      end if;
    exception when others then
      v_err := v_err + 1;
      if jsonb_array_length(v_errors) < 200 then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', i, 'ref', r->>'ref', 'message', sqlerrm));
      end if;
    end;
  end loop;
  update hr.punch_batches set rows_imported = v_ok, rows_duplicate = v_dup, rows_error = v_err, errors = v_errors,
         date_from = v_min, date_to = v_max where id = v_batch;
  if v_min is not null then
    for x in select unnest(v_touched) as id loop
      perform hr.compute_attendance(x.id, v_min - 1, v_max);
    end loop;
  end if;
  return (select to_jsonb(b) - 'created_by' || jsonb_build_object('created_by_name', hr.user_label(b.created_by))
          from hr.punch_batches b where b.id = v_batch);
end $$;

create or replace function public.hr_list_punch_batches(p_entity uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('ATT_READ');
  return coalesce((select jsonb_agg(to_jsonb(b) - 'created_by' - 'errors' || jsonb_build_object('created_by_name', hr.user_label(b.created_by),
                                    'error_count', jsonb_array_length(b.errors)) order by b.created_at desc)
                   from (select * from hr.punch_batches where p_entity is null or entity_id = p_entity or entity_id is null
                         order by created_at desc limit 50) b), '[]'::jsonb);
end $$;

create or replace function public.hr_list_punches(p_employee uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  if not hr.can_see_time(p_employee, 'ATT_READ') then raise exception 'NOT_ALLOWED: You cannot see this employee.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'time', hr.hhmm(x.punch_at), 'date', (x.punch_at at time zone 'Asia/Muscat')::date,
                                     'direction', x.direction, 'source', x.source) order by x.punch_at)
                   from hr.punches x where x.employee_id = p_employee
                     and x.punch_at >= hr.local_ts(p_date, time '00:00') - interval '4 hours'
                     and x.punch_at < hr.local_ts(p_date + 1, time '00:00') + interval '8 hours'), '[]'::jsonb);
end $$;

create or replace function public.hr_recompute_attendance(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_from date := hr.jdate(p,'from'); v_to date := coalesce(hr.jdate(p,'to'), hr.today()); v_n int := 0; x record;
begin
  perform hr.require_perm('ATT_WRITE');
  if v_from is null or v_to < v_from then raise exception 'INVALID: Give a valid date range.'; end if;
  if v_to - v_from > 92 then raise exception 'INVALID: Recalculate at most 93 days at a time.'; end if;
  for x in select e.id from hr.employees e
           where (hr.juuid(p,'employee_id') is null or e.id = hr.juuid(p,'employee_id'))
             and (hr.juuid(p,'entity_id') is null or e.entity_id = hr.juuid(p,'entity_id')) loop
    v_n := v_n + hr.compute_attendance(x.id, v_from, v_to);
  end loop;
  return jsonb_build_object('days', v_n);
end $$;

-- ---------------------------------------------------------------------------
-- Attendance views
-- ---------------------------------------------------------------------------
create or replace function hr.attendance_json(a hr.attendance_days)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'employee_id', a.employee_id, 'work_date', a.work_date, 'status', a.status,
    'shift_id', a.shift_id, 'shift_code', s.code, 'shift_name_en', s.name_en, 'shift_name_ar', s.name_ar,
    'sched_start', hr.hhmm(a.sched_start), 'sched_end', hr.hhmm(a.sched_end), 'sched_minutes', a.sched_minutes,
    'first_in', hr.hhmm(a.first_in), 'last_out', hr.hhmm(a.last_out), 'punch_count', a.punch_count,
    'worked_minutes', a.worked_minutes, 'late_minutes', a.late_minutes, 'early_minutes', a.early_minutes,
    'extra_minutes', a.extra_minutes, 'leave_type', a.leave_type, 'leave_name_en', lt.name_en, 'leave_name_ar', lt.name_ar,
    'leave_fraction', a.leave_fraction, 'worked_off_day', a.worked_off_day, 'is_ramadan', a.is_ramadan,
    'holiday_en', (hr.holiday_on(e.entity_id, a.work_date)).name_en, 'holiday_ar', (hr.holiday_on(e.entity_id, a.work_date)).name_ar,
    'pending_correction', exists (select 1 from hr.attendance_corrections c where c.employee_id = a.employee_id
                                   and c.work_date = a.work_date and c.status like 'PENDING%'),
    'overtime_minutes', coalesce((select sum(o.minutes) from hr.overtime_requests o where o.employee_id = a.employee_id
                                   and o.work_date = a.work_date and o.status = 'APPROVED'), 0),
    'locked', hr.is_locked(a.employee_id, a.work_date))
  from hr.employees e
  left join hr.shifts s on s.id = a.shift_id
  left join hr.leave_types lt on lt.code = a.leave_type
  where e.id = a.employee_id
$$;

create or replace function public.hr_attendance_day(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_date date := coalesce(hr.jdate(p,'date'), hr.today()); v_dep uuid := hr.juuid(p,'department_id'); v_status text := hr.jtext(p,'status');
begin
  return jsonb_build_object('date', v_date, 'rows', coalesce((
    select jsonb_agg(hr.attendance_json(a) || hr.emp_brief(a.employee_id) order by e.employee_no)
    from hr.attendance_days a join hr.employees e on e.id = a.employee_id
    where a.work_date = v_date
      and a.employee_id in (select employee_id from hr.visible_employees('ATT_READ', hr.juuid(p,'entity_id')))
      and (v_dep is null or (hr.current_assignment(a.employee_id, v_date)).department_id = v_dep)
      and (v_status is null or a.status = v_status
           or (v_status = 'LATE' and a.late_minutes > 0)
           or (v_status = 'EXCEPTION' and (a.status in ('ABSENT','MISSING_PUNCH') or a.late_minutes > 0)))), '[]'::jsonb),
    'counts', (select jsonb_build_object(
        'present', count(*) filter (where a.status = 'PRESENT'),
        'absent', count(*) filter (where a.status = 'ABSENT'),
        'missing', count(*) filter (where a.status = 'MISSING_PUNCH'),
        'late', count(*) filter (where a.late_minutes > 0),
        'leave', count(*) filter (where a.status = 'LEAVE'),
        'off', count(*) filter (where a.status in ('REST','HOLIDAY')),
        'no_shift', count(*) filter (where a.status = 'NO_SHIFT'))
      from hr.attendance_days a
      where a.work_date = v_date and a.employee_id in (select employee_id from hr.visible_employees('ATT_READ', hr.juuid(p,'entity_id')))
        and (v_dep is null or (hr.current_assignment(a.employee_id, v_date)).department_id = v_dep)));
end $$;

create or replace function public.hr_attendance_month(p_employee uuid, p_month text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_m0 date := hr.month_start(p_month); v_m1 date := (hr.month_start(p_month) + interval '1 month - 1 day')::date;
begin
  perform hr.require_user();
  if not hr.can_see_time(p_employee, 'ATT_READ') then raise exception 'NOT_ALLOWED: You cannot see this employee.' using errcode = '42501'; end if;
  return hr.emp_brief(p_employee) || jsonb_build_object(
    'month', p_month, 'locked', hr.is_locked(p_employee, v_m0),
    'days', coalesce((select jsonb_agg(hr.attendance_json(a) order by a.work_date)
                      from hr.attendance_days a where a.employee_id = p_employee and a.work_date between v_m0 and v_m1), '[]'::jsonb),
    'totals', (select jsonb_build_object(
        'scheduled_days', count(*) filter (where a.sched_minutes > 0 or a.status in ('ABSENT','LEAVE')),
        'present', count(*) filter (where a.status = 'PRESENT'),
        'absent', count(*) filter (where a.status = 'ABSENT'),
        'missing', count(*) filter (where a.status = 'MISSING_PUNCH'),
        'leave_days', coalesce(sum(a.leave_fraction), 0),
        'late_count', count(*) filter (where a.late_minutes > 0),
        'late_minutes', coalesce(sum(a.late_minutes), 0),
        'worked_minutes', coalesce(sum(a.worked_minutes), 0),
        'worked_off_days', count(*) filter (where a.worked_off_day))
      from hr.attendance_days a where a.employee_id = p_employee and a.work_date between v_m0 and v_m1),
    'shift', (select hr.shift_json(s) from hr.shifts s where s.id = (hr.shift_for(p_employee, least(v_m1, hr.today()))).id));
end $$;

-- Month grid: one row per employee, one code per day
create or replace function public.hr_attendance_grid(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_m0 date := hr.month_start(hr.jtext(p,'month')); v_m1 date; v_dep uuid := hr.juuid(p,'department_id');
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  return jsonb_build_object('month', to_char(v_m0, 'YYYY-MM'), 'days_in_month', extract(day from v_m1)::int,
    'locked', exists (select 1 from hr.attendance_periods ap where ap.period_start = v_m0 and ap.status = 'LOCKED'
                      and (hr.juuid(p,'entity_id') is null or ap.entity_id = hr.juuid(p,'entity_id'))),
    'rows', coalesce((
      select jsonb_agg(x.j order by x.no) from (
        select e.employee_no as no, hr.emp_brief(e.id) || jsonb_build_object(
          'days', (select jsonb_object_agg(extract(day from a.work_date)::int,
                     case a.status when 'PRESENT' then case when a.late_minutes > 0 then 'L' else 'P' end
                       when 'ABSENT' then 'A' when 'LEAVE' then 'V' when 'HOLIDAY' then 'H' when 'REST' then 'R'
                       when 'MISSING_PUNCH' then 'M' else 'N' end)
                   from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1),
          'present', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.status = 'PRESENT'),
          'absent', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.status = 'ABSENT'),
          'missing', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.status = 'MISSING_PUNCH'),
          'late', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.late_minutes > 0),
          'leave', (select coalesce(sum(a.leave_fraction), 0) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1)) as j
        from hr.employees e
        where e.id in (select employee_id from hr.visible_employees('ATT_READ', hr.juuid(p,'entity_id')))
          and e.join_date <= v_m1 and (e.separation_date is null or e.separation_date >= v_m0)
          and (v_dep is null or (hr.current_assignment(e.id, least(v_m1, hr.today()))).department_id = v_dep)
      ) x), '[]'::jsonb));
end $$;

-- Payroll inputs for one month (used by Phase 3)
create or replace function public.hr_attendance_summary(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_m0 date := hr.month_start(hr.jtext(p,'month')); v_m1 date; v_entity uuid := hr.juuid(p,'entity_id');
begin
  perform hr.require_perm('ATT_READ');
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  return jsonb_build_object('month', to_char(v_m0,'YYYY-MM'),
    'locked', v_entity is not null and exists (select 1 from hr.attendance_periods ap where ap.entity_id = v_entity and ap.period_start = v_m0 and ap.status = 'LOCKED'),
    'rows', coalesce((select jsonb_agg(hr.emp_brief(e.id) || jsonb_build_object(
      'scheduled_days', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1
                         and a.status in ('PRESENT','ABSENT','MISSING_PUNCH','LEAVE')),
      'present_days', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.status = 'PRESENT'),
      'absent_days', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.status = 'ABSENT'),
      'missing_punch_days', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.status = 'MISSING_PUNCH'),
      'late_minutes', (select coalesce(sum(a.late_minutes),0) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1),
      'holidays', (select count(*) from hr.attendance_days a where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.status = 'HOLIDAY'),
      'leave', coalesce((select jsonb_object_agg(x.leave_type, x.days) from (
                 select a.leave_type, sum(a.leave_fraction) days from hr.attendance_days a
                 where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and a.leave_type is not null group by a.leave_type) x), '{}'::jsonb),
      'unpaid_leave_days', (select coalesce(sum(a.leave_fraction),0) from hr.attendance_days a join hr.leave_types lt on lt.code = a.leave_type
                            where a.employee_id = e.id and a.work_date between v_m0 and v_m1 and lt.pay_mode = 'UNPAID'),
      'ot_pay_hours', (select coalesce(sum(o.pay_hours),0) from hr.overtime_requests o where o.employee_id = e.id
                       and o.work_date between v_m0 and v_m1 and o.status = 'APPROVED' and o.day_kind = 'WORKDAY' and o.comp_choice = 'PAY'),
      'ot_pay_days', (select coalesce(sum(o.pay_days),0) from hr.overtime_requests o where o.employee_id = e.id
                      and o.work_date between v_m0 and v_m1 and o.status = 'APPROVED' and o.day_kind <> 'WORKDAY' and o.comp_choice = 'PAY'),
      'ot_time_off_requests', (select count(*) from hr.overtime_requests o where o.employee_id = e.id
                      and o.work_date between v_m0 and v_m1 and o.status = 'APPROVED' and o.comp_choice = 'TIME_OFF'))
      order by e.employee_no)
      from hr.employees e
      where (v_entity is null or e.entity_id = v_entity) and e.join_date <= v_m1
        and (e.separation_date is null or e.separation_date >= v_m0)), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- Attendance corrections
-- ---------------------------------------------------------------------------
create or replace function hr.correction_json(c hr.attendance_corrections)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(c.employee_id) || jsonb_build_object(
    'id', c.id, 'work_date', c.work_date, 'punch_in', hr.hhmm(c.punch_in), 'punch_out', hr.hhmm(c.punch_out),
    'out_next_day', c.punch_out is not null and (c.punch_out at time zone 'Asia/Muscat')::date > c.work_date,
    'reason', c.reason, 'status', c.status, 'requested_by_name', hr.user_label(c.requested_by), 'requested_at', c.requested_at,
    'manager_decided_by_name', hr.user_label(c.manager_decided_by), 'decided_by_name', hr.user_label(c.decided_by),
    'decided_at', c.decided_at, 'decision_note', c.decision_note,
    'can_decide', hr.can_decide(c.status, c.employee_id, c.requested_by, 'ATT_APPROVE'),
    'can_cancel', c.status like 'PENDING%' and (auth.uid() = c.requested_by or hr.is_me(c.employee_id)))
$$;

create or replace function public.hr_request_correction(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_emp uuid := hr.juuid(p,'employee_id'); v_date date := hr.jdate(p,'work_date'); v_in time := hr.jtime(p,'in_time');
  v_out time := hr.jtime(p,'out_time'); v_in_at timestamptz; v_out_at timestamptz; v_status text; c hr.attendance_corrections; e hr.employees;
begin
  perform hr.require_user();
  if v_emp is null or v_date is null then raise exception 'REQUIRED: Employee and date are required.'; end if;
  if not (hr.is_me(v_emp) or hr.is_my_team(v_emp) or hr.has_perm('ATT_WRITE')) then
    raise exception 'NOT_ALLOWED: You cannot request corrections for this employee.' using errcode = '42501';
  end if;
  select * into e from hr.employees where id = v_emp;
  if v_in is null and v_out is null then raise exception 'REQUIRED: Give the missing in or out time.'; end if;
  if coalesce(length(btrim(hr.jtext(p,'reason'))), 0) < 3 then raise exception 'REQUIRED: Explain the correction.'; end if;
  if v_date > hr.today() then raise exception 'INVALID: You cannot correct a future day.'; end if;
  if v_date < e.join_date or (e.separation_date is not null and v_date > e.separation_date) then
    raise exception 'INVALID: The employee was not employed on that day.';
  end if;
  perform hr.assert_open(v_emp, v_date);
  if v_in is not null then v_in_at := hr.local_ts(v_date, v_in); end if;
  if v_out is not null then v_out_at := hr.local_ts(v_date + case when hr.jbool(p,'out_next_day') then 1 else 0 end, v_out); end if;
  if v_in_at is not null and v_out_at is not null and v_out_at <= v_in_at then raise exception 'INVALID: The out time must be after the in time.'; end if;
  if coalesce(v_out_at, v_in_at) > now() then raise exception 'INVALID: A correction cannot be in the future.'; end if;
  if exists (select 1 from hr.attendance_corrections where employee_id = v_emp and work_date = v_date and status like 'PENDING%') then
    raise exception 'PENDING_EXISTS: A correction for this day is already waiting for approval.';
  end if;
  v_status := hr.first_status(v_emp);
  insert into hr.attendance_corrections(employee_id, work_date, punch_in, punch_out, reason, status, requested_by)
  values (v_emp, v_date, v_in_at, v_out_at, btrim(hr.jtext(p,'reason')), v_status, auth.uid()) returning * into c;
  perform hr.notify_approvers(v_emp, v_status, 'ATT_APPROVE', 'CORRECTION',
    'Attendance correction waiting: ' || e.full_name_en || ', ' || to_char(v_date,'DD/MM/YYYY'),
    'تصحيح حضور بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en) || '، ' || to_char(v_date,'DD/MM/YYYY'),
    '/approvals', 'corr:' || c.id || ':' || v_status);
  return hr.correction_json(c);
end $$;

create or replace function public.hr_decide_correction(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c hr.attendance_corrections; v_next text; e hr.employees;
begin
  perform hr.require_user();
  select * into c from hr.attendance_corrections where id = p_id for update;
  if c.id is null or c.status not like 'PENDING%' then raise exception 'NOT_FOUND: This correction is no longer waiting.'; end if;
  if auth.uid() = c.requested_by or hr.is_me(c.employee_id) then raise exception 'SELF_APPROVAL: Someone other than you must approve this.'; end if;
  if not hr.can_decide(c.status, c.employee_id, c.requested_by, 'ATT_APPROVE') then
    raise exception 'NOT_ALLOWED: You cannot decide this correction.' using errcode = '42501';
  end if;
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  perform hr.assert_open(c.employee_id, c.work_date);
  select * into e from hr.employees where id = c.employee_id;
  if not p_approve then
    update hr.attendance_corrections set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(), decision_note = btrim(p_note) where id = p_id;
  elsif c.status = 'PENDING_MANAGER' and not hr.has_perm('ATT_APPROVE') then
    update hr.attendance_corrections set status = 'PENDING_HR', manager_decided_by = auth.uid(), manager_decided_at = now(),
           decision_note = nullif(btrim(p_note),'') where id = p_id;
    perform hr.notify_approvers(c.employee_id, 'PENDING_HR', 'ATT_APPROVE', 'CORRECTION',
      'Attendance correction waiting: ' || e.full_name_en || ', ' || to_char(c.work_date,'DD/MM/YYYY'),
      'تصحيح حضور بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en), '/approvals', 'corr:' || c.id || ':PENDING_HR');
  else
    update hr.attendance_corrections set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(),
           decision_note = nullif(btrim(p_note),'') where id = p_id;
    if c.punch_in is not null then
      insert into hr.punches(employee_id, punch_at, direction, source, correction_id, created_by)
      values (c.employee_id, c.punch_in, 'IN', 'MANUAL', c.id, auth.uid()) on conflict (employee_id, punch_at) do nothing;
    end if;
    if c.punch_out is not null then
      insert into hr.punches(employee_id, punch_at, direction, source, correction_id, created_by)
      values (c.employee_id, c.punch_out, 'OUT', 'MANUAL', c.id, auth.uid()) on conflict (employee_id, punch_at) do nothing;
    end if;
    perform hr.compute_attendance(c.employee_id, c.work_date - 1, c.work_date + 1);
  end if;
  select * into c from hr.attendance_corrections where id = p_id;
  if c.status in ('APPROVED','REJECTED') then
    perform hr.notify(hr.employee_user(c.employee_id), 'CORRECTION', 'NORMAL',
      'Attendance correction ' || lower(c.status) || ': ' || to_char(c.work_date,'DD/MM/YYYY'),
      case when c.status = 'APPROVED' then 'تم اعتماد تصحيح الحضور: ' else 'تم رفض تصحيح الحضور: ' end || to_char(c.work_date,'DD/MM/YYYY'),
      c.decision_note, c.decision_note, '/attendance', 'corr-done:' || c.id);
  end if;
  return hr.correction_json(c);
end $$;

create or replace function public.hr_cancel_correction(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c hr.attendance_corrections;
begin
  perform hr.require_user();
  select * into c from hr.attendance_corrections where id = p_id for update;
  if c.id is null or c.status not like 'PENDING%' then raise exception 'NOT_FOUND: This correction is no longer waiting.'; end if;
  if not (auth.uid() = c.requested_by or hr.is_me(c.employee_id)) then raise exception 'NOT_ALLOWED: Only the requester can withdraw it.' using errcode = '42501'; end if;
  update hr.attendance_corrections set status = 'CANCELLED' where id = p_id returning * into c;
  return hr.correction_json(c);
end $$;

create or replace function public.hr_list_corrections(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_status text := hr.jtext(p,'status'); v_emp uuid := hr.juuid(p,'employee_id');
        v_from date := hr.jdate(p,'from'); v_to date := hr.jdate(p,'to');
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.correction_json(c) order by c.requested_at desc)
    from (select * from hr.attendance_corrections c
          where c.employee_id in (select employee_id from hr.visible_employees('ATT_READ', null))
            and (v_emp is null or c.employee_id = v_emp)
            and (v_status is null or c.status = v_status or (v_status = 'PENDING' and c.status like 'PENDING%'))
            and (v_from is null or c.work_date >= v_from) and (v_to is null or c.work_date <= v_to)
          order by c.requested_at desc limit 300) c), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Overtime
-- ---------------------------------------------------------------------------
create or replace function hr.overtime_json(o hr.overtime_requests)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(o.employee_id) || jsonb_build_object(
    'id', o.id, 'work_date', o.work_date, 'start_time', hr.hhmm(o.start_at), 'end_time', hr.hhmm(o.end_at),
    'end_next_day', (o.end_at at time zone 'Asia/Muscat')::date > o.work_date,
    'minutes', o.minutes, 'day_minutes', o.day_minutes, 'night_minutes', o.night_minutes, 'day_kind', o.day_kind,
    'basis', o.basis, 'employee_consent', o.employee_consent, 'comp_choice', o.comp_choice, 'rates', o.rates,
    'pay_hours', o.pay_hours, 'pay_days', o.pay_days, 'reason', o.reason, 'authority_notified', o.authority_notified,
    'status', o.status, 'requested_by_name', hr.user_label(o.requested_by), 'requested_at', o.requested_at,
    'decided_by_name', hr.user_label(o.decided_by), 'decided_at', o.decided_at, 'decision_note', o.decision_note,
    'can_decide', hr.can_decide(o.status, o.employee_id, o.requested_by, 'ATT_APPROVE'),
    'can_cancel', o.status like 'PENDING%' and (auth.uid() = o.requested_by or hr.is_me(o.employee_id)))
$$;

create or replace function public.hr_request_overtime(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_emp uuid := hr.juuid(p,'employee_id'); v_date date := hr.jdate(p,'work_date');
  v_st time := hr.jtime(p,'start_time'); v_et time := hr.jtime(p,'end_time');
  v_basis text := coalesce(upper(hr.jtext(p,'basis')), 'CONSENT'); v_comp text := coalesce(upper(hr.jtext(p,'comp_choice')), 'PAY');
  v_start timestamptz; v_end timestamptz; v_min int; v_night int; v_kind text; s hr.shifts; e hr.employees;
  v_rules jsonb; v_ot jsonb := hr.rule('OVERTIME', v_date); v_cap int; v_other int; v_sched int := 0; v_consent boolean;
  v_status text; o hr.overtime_requests; v_ss timestamptz; v_se timestamptz; v_inv int;
begin
  perform hr.require_user();
  if v_emp is null or v_date is null or v_st is null or v_et is null then raise exception 'REQUIRED: Employee, date, start and end time are required.'; end if;
  if not (hr.is_me(v_emp) or hr.is_my_team(v_emp) or hr.has_perm('ATT_WRITE')) then
    raise exception 'NOT_ALLOWED: You cannot request overtime for this employee.' using errcode = '42501';
  end if;
  if v_basis not in ('CONSENT','INVENTORY','EMERGENCY') then raise exception 'INVALID: Unknown overtime basis.'; end if;
  if v_comp not in ('PAY','TIME_OFF') then raise exception 'INVALID: Choose pay or time off.'; end if;
  if coalesce(length(btrim(hr.jtext(p,'reason'))), 0) < 3 then raise exception 'REQUIRED: Explain the overtime.'; end if;
  select * into e from hr.employees where id = v_emp;
  if v_date < e.join_date or e.status = 'SEPARATED' then raise exception 'INVALID: The employee is not employed on that day.'; end if;
  if v_date > hr.today() + 31 then raise exception 'INVALID: Overtime can be planned at most 31 days ahead.'; end if;
  perform hr.assert_open(v_emp, v_date);
  v_start := hr.local_ts(v_date, v_st);
  v_end := hr.local_ts(v_date + case when hr.jbool(p,'end_next_day') or v_et <= v_st then 1 else 0 end, v_et);
  v_min := (extract(epoch from (v_end - v_start)) / 60)::int;
  if v_min <= 0 then raise exception 'INVALID: The end time must be after the start time.'; end if;
  s := hr.shift_for(v_emp, v_date);
  if (hr.holiday_on(e.entity_id, v_date)).id is not null then v_kind := 'HOLIDAY';
  elsif (s.id is not null and extract(isodow from v_date)::int = any(s.rest_days))
     or (s.id is null and extract(isodow from v_date)::int in (5,6)) then v_kind := 'REST_DAY';
  else v_kind := 'WORKDAY';
  end if;
  if v_kind = 'WORKDAY' and s.id is not null then
    v_ss := hr.local_ts(v_date, s.start_time);
    v_se := hr.local_ts(v_date + case when s.end_time > s.start_time then 0 else 1 end, s.end_time);
    if v_start < v_se and v_end > v_ss then raise exception 'INVALID: Overtime must be outside the scheduled shift (% – %).', to_char(s.start_time,'HH24:MI'), to_char(s.end_time,'HH24:MI'); end if;
    v_sched := hr.shift_net_minutes(s);
  end if;
  if exists (select 1 from hr.overtime_requests x where x.employee_id = v_emp and x.status in ('PENDING_MANAGER','PENDING_HR','APPROVED')
             and x.start_at < v_end and x.end_at > v_start) then
    raise exception 'OVERLAP: This overlaps another overtime request.';
  end if;
  select coalesce(sum(x.minutes), 0) into v_other from hr.overtime_requests x
   where x.employee_id = v_emp and x.work_date = v_date and x.status in ('PENDING_MANAGER','PENDING_HR','APPROVED');
  v_cap := (coalesce((v_ot->>'max_total_daily_hours')::numeric, 12) * 60)::int;
  if v_sched + v_other + v_min > v_cap then
    raise exception 'HOURS_LIMIT: Working hours including overtime would be % on this day; the limit is % (Labour Law Art. 71).',
      round((v_sched + v_other + v_min) / 60.0, 2), round(v_cap / 60.0, 2);
  end if;
  if v_basis = 'CONSENT' then
    v_rules := v_ot;
    v_consent := hr.is_me(v_emp) or hr.jbool(p,'employee_consent');
    if not v_consent then raise exception 'CONSENT_REQUIRED: Overtime needs the employee''s consent (Labour Law Art. 71).'; end if;
  else
    v_rules := hr.rule('OVERTIME_NO_CONSENT', v_date);
    v_consent := hr.is_me(v_emp) or hr.jbool(p,'employee_consent');
    if v_basis = 'INVENTORY' then
      select count(distinct x.work_date) into v_inv from hr.overtime_requests x
       where x.employee_id = v_emp and x.basis = 'INVENTORY' and x.status in ('PENDING_MANAGER','PENDING_HR','APPROVED')
         and extract(year from x.work_date) = extract(year from v_date) and x.work_date <> v_date;
      if v_inv >= coalesce((v_rules->>'max_inventory_days_per_year')::int, 15) then
        raise exception 'HOURS_LIMIT: Overtime without consent for inventory work is limited to % days a year (Labour Law Art. 72).',
          coalesce((v_rules->>'max_inventory_days_per_year')::int, 15);
      end if;
    end if;
  end if;
  v_night := hr.night_minutes(v_start, v_end, coalesce((v_ot->>'night_start')::time, time '21:00'), coalesce((v_ot->>'night_end')::time, time '05:00'));
  v_status := hr.first_status(v_emp);
  insert into hr.overtime_requests(employee_id, work_date, start_at, end_at, minutes, day_minutes, night_minutes, day_kind, basis,
                                   employee_consent, comp_choice, rates, pay_hours, pay_days, reason, status, requested_by)
  values (v_emp, v_date, v_start, v_end, v_min, v_min - v_night, v_night, v_kind, v_basis, v_consent, v_comp,
          v_rules || jsonb_build_object('rule', case when v_basis = 'CONSENT' then 'OVERTIME' else 'OVERTIME_NO_CONSENT' end),
          case when v_kind = 'WORKDAY' and v_comp = 'PAY' then
            round((v_min - v_night) / 60.0 * (1 + coalesce((v_rules->>'day_premium')::numeric, 0.25))
                  + v_night / 60.0 * (1 + coalesce((v_rules->>'night_premium')::numeric, 0.5)), 2) else 0 end,
          case when v_kind <> 'WORKDAY' and v_comp = 'PAY' then 1 + coalesce((v_rules->>'rest_day_premium')::numeric, 1) else 0 end,
          btrim(hr.jtext(p,'reason')), v_status, auth.uid())
  returning * into o;
  perform hr.notify_approvers(v_emp, v_status, 'ATT_APPROVE', 'OVERTIME',
    'Overtime waiting: ' || e.full_name_en || ', ' || to_char(v_date,'DD/MM/YYYY'),
    'عمل إضافي بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en) || '، ' || to_char(v_date,'DD/MM/YYYY'),
    '/approvals', 'ot:' || o.id || ':' || v_status);
  return hr.overtime_json(o);
end $$;

create or replace function public.hr_decide_overtime(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o hr.overtime_requests; e hr.employees;
begin
  perform hr.require_user();
  select * into o from hr.overtime_requests where id = p_id for update;
  if o.id is null or o.status not like 'PENDING%' then raise exception 'NOT_FOUND: This overtime request is no longer waiting.'; end if;
  if auth.uid() = o.requested_by or hr.is_me(o.employee_id) then raise exception 'SELF_APPROVAL: Someone other than you must approve this.'; end if;
  if not hr.can_decide(o.status, o.employee_id, o.requested_by, 'ATT_APPROVE') then
    raise exception 'NOT_ALLOWED: You cannot decide this overtime.' using errcode = '42501';
  end if;
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  perform hr.assert_open(o.employee_id, o.work_date);
  select * into e from hr.employees where id = o.employee_id;
  if not p_approve then
    update hr.overtime_requests set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(), decision_note = btrim(p_note) where id = p_id;
  elsif o.status = 'PENDING_MANAGER' and not hr.has_perm('ATT_APPROVE') then
    update hr.overtime_requests set status = 'PENDING_HR', manager_decided_by = auth.uid(), manager_decided_at = now() where id = p_id;
    perform hr.notify_approvers(o.employee_id, 'PENDING_HR', 'ATT_APPROVE', 'OVERTIME',
      'Overtime waiting: ' || e.full_name_en || ', ' || to_char(o.work_date,'DD/MM/YYYY'),
      'عمل إضافي بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en), '/approvals', 'ot:' || o.id || ':PENDING_HR');
  else
    update hr.overtime_requests set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note),'') where id = p_id;
  end if;
  select * into o from hr.overtime_requests where id = p_id;
  if o.status in ('APPROVED','REJECTED') then
    perform hr.notify(hr.employee_user(o.employee_id), 'OVERTIME', 'NORMAL',
      'Overtime ' || lower(o.status) || ': ' || to_char(o.work_date,'DD/MM/YYYY'),
      case when o.status = 'APPROVED' then 'تم اعتماد العمل الإضافي: ' else 'تم رفض العمل الإضافي: ' end || to_char(o.work_date,'DD/MM/YYYY'),
      o.decision_note, o.decision_note, '/overtime', 'ot-done:' || o.id);
  end if;
  return hr.overtime_json(o);
end $$;

create or replace function public.hr_cancel_overtime(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o hr.overtime_requests;
begin
  perform hr.require_user();
  select * into o from hr.overtime_requests where id = p_id for update;
  if o.id is null or o.status not like 'PENDING%' then raise exception 'NOT_FOUND: This overtime request is no longer waiting.'; end if;
  if not (auth.uid() = o.requested_by or hr.is_me(o.employee_id)) then raise exception 'NOT_ALLOWED: Only the requester can withdraw it.' using errcode = '42501'; end if;
  update hr.overtime_requests set status = 'CANCELLED' where id = p_id returning * into o;
  return hr.overtime_json(o);
end $$;

create or replace function public.hr_set_overtime_notified(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o hr.overtime_requests;
begin
  perform hr.require_perm('ATT_WRITE');
  update hr.overtime_requests set authority_notified = true where id = p_id and basis <> 'CONSENT' returning * into o;
  if o.id is null then raise exception 'NOT_FOUND: Overtime without consent not found.'; end if;
  return hr.overtime_json(o);
end $$;

create or replace function public.hr_list_overtime(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_status text := hr.jtext(p,'status'); v_emp uuid := hr.juuid(p,'employee_id');
        v_from date := hr.jdate(p,'from'); v_to date := hr.jdate(p,'to');
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.overtime_json(o) order by o.work_date desc, o.start_at desc)
    from (select * from hr.overtime_requests o
          where o.employee_id in (select employee_id from hr.visible_employees('ATT_READ', null))
            and (v_emp is null or o.employee_id = v_emp)
            and (v_status is null or o.status = v_status or (v_status = 'PENDING' and o.status like 'PENDING%'))
            and (v_from is null or o.work_date >= v_from) and (v_to is null or o.work_date <= v_to)
          order by o.work_date desc limit 300) o), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Attendance months: lock / unlock
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_periods(p_entity uuid, p_year int default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_year int := coalesce(p_year, extract(year from hr.today())::int);
begin
  perform hr.require_perm('ATT_READ');
  return coalesce((select jsonb_agg(jsonb_build_object(
      'month', to_char(m, 'YYYY-MM'), 'period_start', m,
      'status', coalesce(ap.status, 'OPEN'), 'locked_by_name', hr.user_label(ap.locked_by), 'locked_at', ap.locked_at,
      'unlocked_by_name', hr.user_label(ap.unlocked_by), 'unlocked_at', ap.unlocked_at, 'unlock_reason', ap.unlock_reason,
      'can_lock', (m + interval '1 month - 1 day')::date < hr.today(),
      'pending', (select count(*) from hr.attendance_corrections c join hr.employees e on e.id = c.employee_id
                  where e.entity_id = p_entity and c.status like 'PENDING%' and date_trunc('month', c.work_date) = m)
               + (select count(*) from hr.overtime_requests o join hr.employees e on e.id = o.employee_id
                  where e.entity_id = p_entity and o.status like 'PENDING%' and date_trunc('month', o.work_date) = m)
               + (select count(*) from hr.leave_requests r join hr.employees e on e.id = r.employee_id
                  where e.entity_id = p_entity and r.status like 'PENDING%'
                    and daterange(r.start_date, r.end_date, '[]') && daterange(m::date, (m + interval '1 month - 1 day')::date, '[]')))
      order by m)
    from generate_series(make_date(v_year, 1, 1), make_date(v_year, 12, 1), interval '1 month') m
    left join hr.attendance_periods ap on ap.entity_id = p_entity and ap.period_start = m::date), '[]'::jsonb);
end $$;

create or replace function public.hr_lock_period(p_entity uuid, p_month text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_m0 date := hr.month_start(p_month); v_m1 date; v_pending int; x record;
begin
  perform hr.require_perm('ATT_LOCK');
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_m1 >= hr.today() then raise exception 'INVALID: Only a completed month can be locked.'; end if;
  if exists (select 1 from hr.attendance_periods where entity_id = p_entity and period_start = v_m0 and status = 'LOCKED') then
    raise exception 'INVALID: This month is already locked.';
  end if;
  select (select count(*) from hr.attendance_corrections c join hr.employees e on e.id = c.employee_id
          where e.entity_id = p_entity and c.status like 'PENDING%' and c.work_date between v_m0 and v_m1)
       + (select count(*) from hr.overtime_requests o join hr.employees e on e.id = o.employee_id
          where e.entity_id = p_entity and o.status like 'PENDING%' and o.work_date between v_m0 and v_m1)
       + (select count(*) from hr.leave_requests r join hr.employees e on e.id = r.employee_id
          where e.entity_id = p_entity and r.status like 'PENDING%' and daterange(r.start_date, r.end_date, '[]') && daterange(v_m0, v_m1, '[]'))
    into v_pending;
  if v_pending > 0 then
    raise exception 'PENDING_EXISTS: % requests for this month are still waiting for approval. Decide them first.', v_pending;
  end if;
  for x in select id from hr.employees where entity_id = p_entity loop
    perform hr.compute_attendance(x.id, v_m0, v_m1);
  end loop;
  insert into hr.attendance_periods(entity_id, period_start, status, locked_by, locked_at)
  values (p_entity, v_m0, 'LOCKED', auth.uid(), now())
  on conflict (entity_id, period_start) do update set status = 'LOCKED', locked_by = auth.uid(), locked_at = now();
  return public.hr_list_periods(p_entity, extract(year from v_m0)::int);
end $$;

create or replace function public.hr_unlock_period(p_entity uuid, p_month text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_m0 date := hr.month_start(p_month);
begin
  perform hr.require_perm('ATT_LOCK');
  if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'REQUIRED: Give a reason for unlocking.'; end if;
  update hr.attendance_periods set status = 'OPEN', unlocked_by = auth.uid(), unlocked_at = now(), unlock_reason = btrim(p_reason)
   where entity_id = p_entity and period_start = v_m0 and status = 'LOCKED';
  if not found then raise exception 'NOT_FOUND: This month is not locked.'; end if;
  return public.hr_list_periods(p_entity, extract(year from v_m0)::int);
end $$;

select hr.attach_audit();
select hr.secure_api();
