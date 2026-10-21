-- AACT HRMS — 010 Phase 2: attendance & leave — tables, Oman rules (dated, with legal source), helpers.
-- Idempotent; no destructive statements.

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
insert into hr.permissions(code, module, description) values
  ('ATT_READ',      'Time',  'View attendance, overtime and corrections of all employees'),
  ('ATT_WRITE',     'Time',  'Maintain shifts, rosters and the holiday calendar; import punches; raise requests for others'),
  ('ATT_APPROVE',   'Time',  'Final approval of attendance corrections and overtime'),
  ('ATT_LOCK',      'Time',  'Lock and unlock attendance months'),
  ('LEAVE_READ',    'Leave', 'View leave requests and balances of all employees'),
  ('LEAVE_WRITE',   'Leave', 'Request leave for others; propose balance adjustments; run accruals'),
  ('LEAVE_APPROVE', 'Leave', 'Final approval of leave requests and balance adjustments')
on conflict (code) do nothing;

insert into hr.role_permissions(role_code, perm_code)
select 'SUPER_ADMIN', code from hr.permissions
on conflict do nothing;

insert into hr.role_permissions(role_code, perm_code)
select r, p from (values
  ('HR_MANAGER','ATT_READ'),('HR_MANAGER','ATT_WRITE'),('HR_MANAGER','ATT_APPROVE'),('HR_MANAGER','ATT_LOCK'),
  ('HR_MANAGER','LEAVE_READ'),('HR_MANAGER','LEAVE_WRITE'),('HR_MANAGER','LEAVE_APPROVE'),
  ('HR_OFFICER','ATT_READ'),('HR_OFFICER','ATT_WRITE'),('HR_OFFICER','LEAVE_READ'),('HR_OFFICER','LEAVE_WRITE'),
  ('FINANCE','ATT_READ'),('FINANCE','LEAVE_READ'),
  ('AUDITOR','ATT_READ'),('AUDITOR','LEAVE_READ')
) v(r, p)
on conflict do nothing;

insert into hr.settings(key, value) values
  ('time_zone', '"Asia/Muscat"'),
  ('leave_opening_date', 'null')
on conflict (key) do nothing;

create or replace function hr.today()
returns date language sql stable set search_path = '' as $$
  select (now() at time zone 'Asia/Muscat')::date
$$;

create or replace function hr.local_ts(p_date date, p_time time)
returns timestamptz language sql stable set search_path = '' as $$
  select (p_date + p_time) at time zone 'Asia/Muscat'
$$;

create or replace function hr.jtime(p jsonb, k text)
returns time language plpgsql immutable set search_path = '' as $$
declare v text := nullif(btrim(p->>k), '');
begin
  if v is null then return null; end if;
  if v !~ '^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$' then
    raise exception 'INVALID_TIME: % must be a time (HH:MM).', k;
  end if;
  return v::time;
end $$;

create or replace function hr.jnum(p jsonb, k text)
returns numeric language plpgsql immutable set search_path = '' as $$
declare v text := nullif(btrim(p->>k), '');
begin
  if v is null then return null; end if;
  if v !~ '^-?\d{1,6}(\.\d{1,2})?$' then raise exception 'INVALID_NUMBER: % must be a number with at most 2 decimals.', k; end if;
  return v::numeric;
end $$;

-- ---------------------------------------------------------------------------
-- Oman time rules — dated values with legal basis; maker-checker for changes.
-- ---------------------------------------------------------------------------
create table if not exists hr.time_rules (
  id               uuid primary key default gen_random_uuid(),
  code             text not null check (code in ('WORK_HOURS','RAMADAN_HOURS','WEEKLY_REST','OVERTIME','OVERTIME_NO_CONSENT','ATTENDANCE')),
  value            jsonb not null,
  effective_from   date not null,
  effective_to     date,
  rule_basis       text not null default 'LEGAL' check (rule_basis in ('LEGAL','COMPANY_POLICY')),
  legal_basis      text not null,
  status           text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED')),
  proposed_by      uuid,
  proposed_at      timestamptz not null default now(),
  decided_by       uuid,
  decided_at       timestamptz,
  decision_note    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (decided_by is null or proposed_by is null or decided_by <> proposed_by)
);
create index if not exists time_rules_code on hr.time_rules(code, effective_from desc) where status = 'APPROVED';

insert into hr.time_rules(code, value, effective_from, rule_basis, legal_basis, status)
select v.code, v.value::jsonb, date '2023-07-26', v.basis, v.src, 'APPROVED'
from (values
  ('WORK_HOURS', '{"daily_max_hours":8,"weekly_max_hours":40,"break_minutes":60,"max_continuous_hours":6}', 'LEGAL', 'Labour Law RD 53/2023, Art. 70'),
  ('RAMADAN_HOURS', '{"daily_max_hours":6,"weekly_max_hours":30}', 'LEGAL', 'Labour Law RD 53/2023, Art. 70 (Muslim workers)'),
  ('WEEKLY_REST', '{"min_consecutive_days":2}', 'LEGAL', 'Labour Law RD 53/2023, Art. 77'),
  ('OVERTIME', '{"day_premium":0.25,"night_premium":0.50,"rest_day_premium":1.00,"max_total_daily_hours":12,"night_start":"21:00","night_end":"05:00"}', 'LEGAL', 'Labour Law RD 53/2023, Art. 71 and Art. 1 (night hours)'),
  ('OVERTIME_NO_CONSENT', '{"day_premium":0.50,"night_premium":0.75,"rest_day_premium":2.00,"max_inventory_days_per_year":15}', 'LEGAL', 'Labour Law RD 53/2023, Art. 72'),
  ('ATTENDANCE', '{"late_grace_minutes":10,"window_before_minutes":180,"window_after_minutes":360,"min_minutes_between_punches":5}', 'COMPANY_POLICY', 'AACT attendance policy (default)')
) v(code, value, basis, src)
where not exists (select 1 from hr.time_rules t where t.code = v.code);

create or replace function hr.rule(p_code text, p_on date default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select t.value from hr.time_rules t
  where t.code = p_code and t.status = 'APPROVED'
    and t.effective_from <= coalesce(p_on, hr.today())
    and (t.effective_to is null or t.effective_to >= coalesce(p_on, hr.today()))
  order by t.effective_from desc limit 1
$$;

create or replace function hr.rule_num(p_code text, p_key text, p_on date default null)
returns numeric language sql stable security definer set search_path = '' as $$
  select (hr.rule(p_code, p_on)->>p_key)::numeric
$$;

-- ---------------------------------------------------------------------------
-- Shifts and rosters
-- ---------------------------------------------------------------------------
create table if not exists hr.shifts (
  id            uuid primary key default gen_random_uuid(),
  entity_id     uuid not null references hr.legal_entities(id),
  code          text not null,
  name_en       text not null,
  name_ar       text,
  start_time    time not null,
  end_time      time not null,
  break_minutes int not null default 60 check (break_minutes between 0 and 240),
  grace_minutes int check (grace_minutes is null or grace_minutes between 0 and 120),
  rest_days     int[] not null default '{5,6}',
  is_ramadan    boolean not null default false,
  notes         text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (entity_id, code),
  check (start_time <> end_time),
  check (array_position(rest_days, null) is null)
);

create table if not exists hr.shift_assignments (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references hr.employees(id),
  shift_id       uuid not null references hr.shifts(id),
  effective_from date not null,
  effective_to   date,
  notes          text,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  constraint shift_assignments_no_overlap exclude using gist (
    employee_id with =,
    daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') with &&)
);
create index if not exists shift_assignments_shift on hr.shift_assignments(shift_id);

create or replace function hr.shift_net_minutes(s hr.shifts)
returns int language sql immutable set search_path = '' as $$
  select (extract(epoch from (case when s.end_time > s.start_time then s.end_time - s.start_time
                                   else (s.end_time - s.start_time) + interval '24 hours' end)) / 60)::int
         - case when (extract(epoch from (case when s.end_time > s.start_time then s.end_time - s.start_time
                                              else (s.end_time - s.start_time) + interval '24 hours' end)) / 60) > 360
                then s.break_minutes else 0 end
$$;

create or replace function hr.shift_span_minutes(s hr.shifts)
returns int language sql immutable set search_path = '' as $$
  select (extract(epoch from (case when s.end_time > s.start_time then s.end_time - s.start_time
                                   else (s.end_time - s.start_time) + interval '24 hours' end)) / 60)::int
$$;

-- Raises when a shift breaks the hours, rest or break rules in force today.
create or replace function hr.validate_shift(s hr.shifts)
returns void language plpgsql stable security definer set search_path = '' as $$
declare
  w jsonb := hr.rule('WORK_HOURS'); r jsonb := hr.rule('RAMADAN_HOURS'); rest jsonb := hr.rule('WEEKLY_REST');
  v_net int := hr.shift_net_minutes(s); v_span int := hr.shift_span_minutes(s);
  v_daily numeric; v_weekly numeric; v_days int; v_min int; v_run int := 0; v_best int := 0; d int; v_set int[];
begin
  if s.rest_days is null or exists (select 1 from unnest(s.rest_days) x where x not between 1 and 7) then
    raise exception 'INVALID: Rest days must be weekdays 1 (Monday) to 7 (Sunday).';
  end if;
  select array_agg(distinct x order by x) into v_set from unnest(s.rest_days) x;
  v_min := coalesce((rest->>'min_consecutive_days')::int, 2);
  -- longest run of consecutive rest days, wrapping Sunday→Monday
  for d in 1..14 loop
    if ((d - 1) % 7) + 1 = any(v_set) then v_run := v_run + 1; v_best := greatest(v_best, v_run); else v_run := 0; end if;
  end loop;
  v_best := least(v_best, 7);
  if v_best < v_min then
    raise exception 'REST_RULE: The weekly rest must include at least % consecutive days (Labour Law Art. 77).', v_min;
  end if;
  v_days := 7 - coalesce(array_length(v_set, 1), 0);
  if s.is_ramadan then
    v_daily := coalesce((r->>'daily_max_hours')::numeric, 6); v_weekly := coalesce((r->>'weekly_max_hours')::numeric, 30);
  else
    v_daily := coalesce((w->>'daily_max_hours')::numeric, 8); v_weekly := coalesce((w->>'weekly_max_hours')::numeric, 40);
  end if;
  if v_net > v_daily * 60 then
    raise exception 'HOURS_LIMIT: This shift has % working hours a day; the limit is % (Labour Law Art. 70).',
      round(v_net / 60.0, 2), v_daily;
  end if;
  if v_net * v_days > v_weekly * 60 then
    raise exception 'HOURS_LIMIT: This shift gives % working hours a week; the limit is % (Labour Law Art. 70).',
      round(v_net * v_days / 60.0, 2), v_weekly;
  end if;
  if v_span > coalesce((w->>'max_continuous_hours')::numeric, 6) * 60
     and s.break_minutes < coalesce((w->>'break_minutes')::int, 60) then
    raise exception 'BREAK_RULE: Shifts longer than % hours need a break of at least % minutes (Labour Law Art. 70).',
      coalesce((w->>'max_continuous_hours')::numeric, 6), coalesce((w->>'break_minutes')::int, 60);
  end if;
end $$;

create or replace function hr.shift_for(p_employee uuid, p_on date)
returns hr.shifts language sql stable security definer set search_path = '' as $$
  select s.* from hr.shift_assignments a join hr.shifts s on s.id = a.shift_id
  where a.employee_id = p_employee and a.effective_from <= p_on and (a.effective_to is null or a.effective_to >= p_on)
  limit 1
$$;

-- ---------------------------------------------------------------------------
-- Calendar: public holidays (entered yearly as announced) and Ramadan periods
-- ---------------------------------------------------------------------------
create table if not exists hr.holidays (
  id               uuid primary key default gen_random_uuid(),
  entity_id        uuid references hr.legal_entities(id),
  holiday_date     date not null,
  name_en          text not null,
  name_ar          text,
  kind             text not null default 'PUBLIC' check (kind in ('PUBLIC','COMPANY')),
  source_reference text,
  is_active        boolean not null default true,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists holidays_uq on hr.holidays(coalesce(entity_id, '00000000-0000-0000-0000-000000000000'::uuid), holiday_date) where is_active;

insert into hr.holidays(holiday_date, name_en, name_ar, kind, source_reference)
select v.d::date, v.en, v.ar, 'PUBLIC', 'Ministry of Labour announcement of 2026 holidays (Eid holidays are added after moon sighting)'
from (values
  ('2026-01-15', 'Sultan''s Accession Day', 'ذكرى تولي جلالة السلطان مقاليد الحكم'),
  ('2026-01-18', 'Al Isra'' wal Mi''raj', 'الإسراء والمعراج'),
  ('2026-06-18', 'Islamic New Year', 'رأس السنة الهجرية'),
  ('2026-08-27', 'Prophet Muhammad''s Birthday', 'المولد النبوي الشريف'),
  ('2026-11-25', 'National Day', 'العيد الوطني'),
  ('2026-11-26', 'National Day', 'العيد الوطني')
) v(d, en, ar)
where not exists (select 1 from hr.holidays h where h.holiday_date = v.d::date and h.entity_id is null);

create table if not exists hr.special_periods (
  id         uuid primary key default gen_random_uuid(),
  code       text not null default 'RAMADAN' check (code in ('RAMADAN')),
  start_date date not null,
  end_date   date not null,
  name_en    text not null,
  name_ar    text,
  notes      text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create or replace function hr.holiday_on(p_entity uuid, p_on date)
returns hr.holidays language sql stable security definer set search_path = '' as $$
  select h.* from hr.holidays h
  where h.is_active and h.holiday_date = p_on and (h.entity_id is null or h.entity_id = p_entity)
  order by h.entity_id nulls last limit 1
$$;

-- ---------------------------------------------------------------------------
-- Attendance months (lock)
-- ---------------------------------------------------------------------------
create table if not exists hr.attendance_periods (
  entity_id     uuid not null references hr.legal_entities(id),
  period_start  date not null check (extract(day from period_start) = 1),
  status        text not null default 'OPEN' check (status in ('OPEN','LOCKED')),
  locked_by     uuid,
  locked_at     timestamptz,
  unlocked_by   uuid,
  unlocked_at   timestamptz,
  unlock_reason text,
  updated_at    timestamptz not null default now(),
  primary key (entity_id, period_start)
);

create or replace function hr.is_locked(p_employee uuid, p_on date)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from hr.attendance_periods ap join hr.employees e on e.entity_id = ap.entity_id
                 where e.id = p_employee and ap.period_start = date_trunc('month', p_on)::date and ap.status = 'LOCKED')
$$;

create or replace function hr.assert_open(p_employee uuid, p_from date, p_to date default null)
returns void language plpgsql stable security definer set search_path = '' as $$
declare m date;
begin
  for m in select generate_series(date_trunc('month', p_from), date_trunc('month', coalesce(p_to, p_from)), interval '1 month')::date loop
    if hr.is_locked(p_employee, m) then
      raise exception 'PERIOD_LOCKED: Attendance for % is locked. Ask HR to unlock it first.', to_char(m, 'MM/YYYY');
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Punches (device import, approved corrections)
-- ---------------------------------------------------------------------------
create table if not exists hr.device_users (
  device_code    text not null default 'DEFAULT',
  device_user_id text not null,
  employee_id    uuid not null references hr.employees(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  primary key (device_code, device_user_id),
  unique (employee_id, device_code)
);

create table if not exists hr.punch_batches (
  id             uuid primary key default gen_random_uuid(),
  entity_id      uuid references hr.legal_entities(id),
  file_name      text,
  ref_kind       text not null,
  rows_total     int not null default 0,
  rows_imported  int not null default 0,
  rows_duplicate int not null default 0,
  rows_error     int not null default 0,
  errors         jsonb not null default '[]'::jsonb,
  date_from      date,
  date_to        date,
  created_by     uuid,
  created_at     timestamptz not null default now()
);

create table if not exists hr.punches (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references hr.employees(id),
  punch_at      timestamptz not null,
  direction     text check (direction in ('IN','OUT')),
  source        text not null check (source in ('DEVICE','IMPORT','MANUAL')),
  batch_id      uuid references hr.punch_batches(id),
  correction_id uuid,
  created_by    uuid,
  created_at    timestamptz not null default now(),
  unique (employee_id, punch_at)
);
create index if not exists punches_batch on hr.punches(batch_id);

-- ---------------------------------------------------------------------------
-- Leave types (statutory minimums from the Labour Law; company may be more generous)
-- ---------------------------------------------------------------------------
create table if not exists hr.leave_types (
  code               text primary key check (code ~ '^[A-Z0-9_]{2,30}$'),
  name_en            text not null,
  name_ar            text not null,
  category           text not null default 'STATUTORY' check (category in ('STATUTORY','COMPANY')),
  pay_mode           text not null default 'FULL' check (pay_mode in ('FULL','TIERED','UNPAID')),
  pay_tiers          jsonb not null default '[]'::jsonb,
  paid_by            text not null default 'EMPLOYER' check (paid_by in ('EMPLOYER','FUND','NONE')),
  quota_days         numeric(6,2),
  legal_min_days     numeric(6,2),
  quota_period       text not null default 'YEAR' check (quota_period in ('YEAR','EVENT','ONCE','NONE')),
  accrual            text not null default 'NONE' check (accrual in ('MONTHLY','NONE')),
  count_mode         text not null default 'CALENDAR' check (count_mode in ('CALENDAR','CALENDAR_EXCL_HOLIDAYS','WORKING')),
  min_service_months int not null default 0,
  carry_forward_max  numeric(6,2),
  gender             text not null default 'ALL' check (gender in ('ALL','M','F')),
  nationality        text not null default 'ALL' check (nationality in ('ALL','OMANI','EXPAT')),
  requires_document  boolean not null default false,
  needs_event_date   boolean not null default false,
  event_window_days  int,
  max_before_event_days int,
  allow_half_day     boolean not null default false,
  allow_negative     boolean not null default false,
  ticket_eligible    boolean not null default false,
  rule_basis         text not null default 'LEGAL' check (rule_basis in ('LEGAL','COMPANY_POLICY')),
  legal_basis        text,
  notes              text,
  sort               int not null default 100,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (quota_days is null or quota_days > 0),
  check (legal_min_days is null or quota_days is null or quota_days >= legal_min_days),
  check (quota_period <> 'NONE' or quota_days is null)
);

insert into hr.leave_types(code, name_en, name_ar, pay_mode, pay_tiers, paid_by, quota_days, legal_min_days, quota_period, accrual,
                           count_mode, min_service_months, carry_forward_max, gender, nationality, requires_document,
                           needs_event_date, event_window_days, max_before_event_days, allow_half_day, ticket_eligible,
                           legal_basis, notes, sort)
select * from (values
  ('ANNUAL', 'Annual leave', 'إجازة سنوية', 'FULL', '[]'::jsonb, 'EMPLOYER', 30::numeric, 30::numeric, 'YEAR', 'MONTHLY',
   'CALENDAR', 6, 30::numeric, 'ALL', 'ALL', false, false, null::int, null::int, true, true,
   'Labour Law RD 53/2023, Art. 78 and 81', 'Gross wage; usable after 6 months; carry forward up to 30 days; at least 30 days every 2 years; return ticket for expatriates.', 10),
  ('SICK', 'Sick leave', 'إجازة مرضية', 'TIERED',
   '[{"from":1,"to":21,"pct":100},{"from":22,"to":35,"pct":75},{"from":36,"to":70,"pct":50},{"from":71,"to":182,"pct":35}]'::jsonb,
   'EMPLOYER', 182, 182, 'YEAR', 'NONE', 'CALENDAR', 0, null, 'ALL', 'ALL', true, false, null, null, false, false,
   'Labour Law RD 53/2023, Art. 82', 'Confirm with the Social Protection Fund which part the sick-leave branch (from 19 Jul 2026) pays.', 20),
  ('MATERNITY', 'Maternity leave', 'إجازة الأمومة', 'FULL', '[]'::jsonb, 'FUND', 98, 98, 'EVENT', 'NONE', 'CALENDAR', 0, null,
   'F', 'ALL', true, true, null, 14, false, false, 'Labour Law RD 53/2023, Art. 84(10)', 'At most 14 days before the expected birth date.', 30),
  ('PATERNITY', 'Paternity leave', 'إجازة الأبوة', 'FULL', '[]'::jsonb, 'FUND', 7, 7, 'EVENT', 'NONE', 'CALENDAR', 0, null,
   'M', 'ALL', true, true, 98, null, false, false, 'Labour Law RD 53/2023, Art. 84(1)', 'Taken within 98 days of the birth.', 31),
  ('MARRIAGE', 'Marriage leave', 'إجازة الزواج', 'FULL', '[]'::jsonb, 'EMPLOYER', 3, 3, 'EVENT', 'NONE', 'CALENDAR', 0, null,
   'ALL', 'ALL', true, true, null, null, false, false, 'Labour Law RD 53/2023, Art. 84(2)', null, 40),
  ('BEREAVE_FAMILY', 'Bereavement – parent, grandparent, brother or sister', 'إجازة وفاة – الوالدين أو الأجداد أو الإخوة',
   'FULL', '[]'::jsonb, 'EMPLOYER', 3, 3, 'EVENT', 'NONE', 'CALENDAR', 0, null, 'ALL', 'ALL', false, true, null, null, false, false,
   'Labour Law RD 53/2023, Art. 84(3)', null, 50),
  ('BEREAVE_RELATIVE', 'Bereavement – uncle or aunt', 'إجازة وفاة – العم أو الخال أو العمة أو الخالة',
   'FULL', '[]'::jsonb, 'EMPLOYER', 2, 2, 'EVENT', 'NONE', 'CALENDAR', 0, null, 'ALL', 'ALL', false, true, null, null, false, false,
   'Labour Law RD 53/2023, Art. 84(4)', null, 51),
  ('BEREAVE_SPOUSE_CHILD', 'Bereavement – wife or child', 'إجازة وفاة – الزوجة أو الأبناء',
   'FULL', '[]'::jsonb, 'EMPLOYER', 10, 10, 'EVENT', 'NONE', 'CALENDAR', 0, null, 'ALL', 'ALL', false, true, null, null, false, false,
   'Labour Law RD 53/2023, Art. 84(5)', null, 52),
  ('WIDOW_MUSLIM', 'Widow''s leave (Muslim)', 'إجازة عدة الوفاة (مسلمة)', 'FULL', '[]'::jsonb, 'EMPLOYER', 130, 130, 'EVENT', 'NONE',
   'CALENDAR', 0, null, 'F', 'ALL', true, true, null, null, false, false, 'Labour Law RD 53/2023, Art. 84(8)', null, 53),
  ('WIDOW_OTHER', 'Widow''s leave (non-Muslim)', 'إجازة وفاة الزوج (غير مسلمة)', 'FULL', '[]'::jsonb, 'EMPLOYER', 14, 14, 'EVENT', 'NONE',
   'CALENDAR', 0, null, 'F', 'ALL', true, true, null, null, false, false, 'Labour Law RD 53/2023, Art. 84(8)', null, 54),
  ('HAJJ', 'Hajj leave', 'إجازة الحج', 'FULL', '[]'::jsonb, 'EMPLOYER', 15, 15, 'ONCE', 'NONE', 'CALENDAR', 12, null,
   'ALL', 'ALL', false, false, null, null, false, false, 'Labour Law RD 53/2023, Art. 84(6)', 'Once during service, after one year with the employer.', 60),
  ('EXAM', 'Exam leave', 'إجازة الامتحانات', 'FULL', '[]'::jsonb, 'EMPLOYER', 15, 15, 'YEAR', 'NONE', 'CALENDAR', 0, null,
   'ALL', 'OMANI', true, false, null, null, false, false, 'Labour Law RD 53/2023, Art. 84(7)', 'Omani workers studying at a recognised institution.', 70),
  ('ACCOMPANY', 'Leave to accompany a patient', 'إجازة مرافقة مريض', 'FULL', '[]'::jsonb, 'EMPLOYER', 15, 15, 'YEAR', 'NONE',
   'CALENDAR', 0, null, 'ALL', 'OMANI', true, false, null, null, false, false, 'Labour Law RD 53/2023, Art. 84(9)',
   'Omani workers accompanying a spouse or a relative up to the second degree.', 71),
  ('CHILDCARE', 'Unpaid childcare leave', 'إجازة رعاية طفل بدون أجر', 'UNPAID', '[]'::jsonb, 'NONE', 365, 365, 'EVENT', 'NONE',
   'CALENDAR', 0, null, 'F', 'ALL', false, true, null, null, false, false, 'Labour Law RD 53/2023, Art. 83', null, 80),
  ('UNPAID', 'Unpaid leave', 'إجازة بدون أجر', 'UNPAID', '[]'::jsonb, 'NONE', null, null, 'NONE', 'NONE', 'CALENDAR', 0, null,
   'ALL', 'ALL', false, false, null, null, false, false, 'Labour Law RD 53/2023 (special unpaid leave)',
   'The employee pays the social protection contributions for this period.', 90)
) v
where not exists (select 1 from hr.leave_types t where t.code = v.column1);

-- Leave attachments may be uploaded by the employee (self_upload)
alter table hr.document_types add column if not exists self_upload boolean not null default false;
insert into hr.document_types(code, name_en, name_ar, category, has_number, has_expiry, alert_days, applies_to,
                              is_mandatory, allow_multiple, is_sensitive, sort, self_upload) values
  ('MEDICAL_CERT',  'Medical certificate (leave)', 'شهادة طبية (إجازة)',   'MEDICAL', false, false, '{}', 'ALL', false, true, true,  61, true),
  ('LEAVE_SUPPORT', 'Leave supporting document',   'مستند داعم للإجازة', 'OTHER',   false, false, '{}', 'ALL', false, true, false, 98, true)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Leave requests, ledger and adjustments
-- ---------------------------------------------------------------------------
create table if not exists hr.leave_requests (
  id                 uuid primary key default gen_random_uuid(),
  employee_id        uuid not null references hr.employees(id),
  leave_type         text not null references hr.leave_types(code),
  start_date         date not null,
  end_date           date not null,
  half_day           boolean not null default false,
  days               numeric(6,2) not null check (days > 0),
  event_date         date,
  reason             text,
  document_id        uuid references hr.employee_documents(id),
  status             text not null check (status in ('PENDING_MANAGER','PENDING_HR','APPROVED','REJECTED','CANCELLED')),
  pay_breakdown      jsonb,
  ticket_requested   boolean not null default false,
  ticket_status      text not null default 'NONE' check (ticket_status in ('NONE','REQUESTED','ISSUED','CASH','DECLINED')),
  requested_by       uuid not null,
  requested_at       timestamptz not null default now(),
  manager_decided_by uuid,
  manager_decided_at timestamptz,
  manager_note       text,
  decided_by         uuid,
  decided_at         timestamptz,
  decision_note      text,
  cancelled_by       uuid,
  cancelled_at       timestamptz,
  cancel_reason      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (end_date >= start_date),
  check (not half_day or start_date = end_date),
  check (decided_by is null or decided_by <> requested_by),
  constraint leave_requests_no_overlap exclude using gist (
    employee_id with =, daterange(start_date, end_date, '[]') with &&)
    where (status in ('PENDING_MANAGER','PENDING_HR','APPROVED') and not half_day)
);
create index if not exists leave_requests_emp on hr.leave_requests(employee_id, start_date);
create index if not exists leave_requests_status on hr.leave_requests(status) where status like 'PENDING%';
create index if not exists leave_requests_type on hr.leave_requests(leave_type);
create index if not exists leave_requests_doc on hr.leave_requests(document_id);

create table if not exists hr.leave_adjustments (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references hr.employees(id),
  leave_type     text not null references hr.leave_types(code),
  kind           text not null check (kind in ('OPENING','ADJUSTMENT')),
  days           numeric(7,2) not null check (days <> 0),
  effective_date date not null,
  reason         text not null,
  status         text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED')),
  proposed_by    uuid not null,
  proposed_at    timestamptz not null default now(),
  decided_by     uuid,
  decided_at     timestamptz,
  decision_note  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (decided_by is null or decided_by <> proposed_by)
);
create index if not exists leave_adjustments_emp on hr.leave_adjustments(employee_id);
create index if not exists leave_adjustments_type on hr.leave_adjustments(leave_type);

create table if not exists hr.leave_ledger (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references hr.employees(id),
  leave_type    text not null references hr.leave_types(code),
  entry_date    date not null,
  days          numeric(7,2) not null,
  kind          text not null check (kind in ('OPENING','ACCRUAL','TAKEN','REVERSAL','ADJUSTMENT','CARRY_EXPIRY')),
  period_key    text,
  request_id    uuid references hr.leave_requests(id),
  adjustment_id uuid references hr.leave_adjustments(id),
  note          text,
  created_by    uuid,
  created_at    timestamptz not null default now()
);
create index if not exists leave_ledger_emp on hr.leave_ledger(employee_id, leave_type, entry_date);
create index if not exists leave_ledger_request on hr.leave_ledger(request_id);
create index if not exists leave_ledger_adjustment on hr.leave_ledger(adjustment_id);
create index if not exists leave_ledger_type on hr.leave_ledger(leave_type);
create unique index if not exists leave_ledger_periodic on hr.leave_ledger(employee_id, leave_type, kind, period_key)
  where kind in ('ACCRUAL','CARRY_EXPIRY');

-- ---------------------------------------------------------------------------
-- Attendance corrections and overtime
-- ---------------------------------------------------------------------------
create table if not exists hr.attendance_corrections (
  id                 uuid primary key default gen_random_uuid(),
  employee_id        uuid not null references hr.employees(id),
  work_date          date not null,
  punch_in           timestamptz,
  punch_out          timestamptz,
  reason             text not null check (length(btrim(reason)) >= 3),
  status             text not null check (status in ('PENDING_MANAGER','PENDING_HR','APPROVED','REJECTED','CANCELLED')),
  requested_by       uuid not null,
  requested_at       timestamptz not null default now(),
  manager_decided_by uuid,
  manager_decided_at timestamptz,
  decided_by         uuid,
  decided_at         timestamptz,
  decision_note      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (punch_in is not null or punch_out is not null),
  check (punch_in is null or punch_out is null or punch_out > punch_in),
  check (decided_by is null or decided_by <> requested_by)
);
create index if not exists corrections_emp on hr.attendance_corrections(employee_id, work_date);

create table if not exists hr.overtime_requests (
  id                 uuid primary key default gen_random_uuid(),
  employee_id        uuid not null references hr.employees(id),
  work_date          date not null,
  start_at           timestamptz not null,
  end_at             timestamptz not null,
  minutes            int not null check (minutes > 0),
  day_minutes        int not null default 0,
  night_minutes      int not null default 0,
  day_kind           text not null check (day_kind in ('WORKDAY','REST_DAY','HOLIDAY')),
  basis              text not null default 'CONSENT' check (basis in ('CONSENT','INVENTORY','EMERGENCY')),
  employee_consent   boolean not null default false,
  comp_choice        text not null default 'PAY' check (comp_choice in ('PAY','TIME_OFF')),
  rates              jsonb not null default '{}'::jsonb,
  pay_hours          numeric(8,2) not null default 0,
  pay_days           numeric(6,2) not null default 0,
  reason             text not null check (length(btrim(reason)) >= 3),
  authority_notified boolean not null default false,
  status             text not null check (status in ('PENDING_MANAGER','PENDING_HR','APPROVED','REJECTED','CANCELLED')),
  requested_by       uuid not null,
  requested_at       timestamptz not null default now(),
  manager_decided_by uuid,
  manager_decided_at timestamptz,
  decided_by         uuid,
  decided_at         timestamptz,
  decision_note      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (end_at > start_at),
  check (decided_by is null or decided_by <> requested_by),
  check (basis <> 'CONSENT' or employee_consent)
);
create index if not exists overtime_emp on hr.overtime_requests(employee_id, work_date);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'punches_correction_fk') then
    alter table hr.punches add constraint punches_correction_fk foreign key (correction_id) references hr.attendance_corrections(id);
  end if;
end $$;
create index if not exists punches_correction on hr.punches(correction_id);

-- ---------------------------------------------------------------------------
-- Computed attendance (derived, rebuilt from punches; not audited row by row)
-- ---------------------------------------------------------------------------
create table if not exists hr.attendance_days (
  employee_id       uuid not null references hr.employees(id),
  work_date         date not null,
  shift_id          uuid references hr.shifts(id),
  sched_start       timestamptz,
  sched_end         timestamptz,
  sched_minutes     int not null default 0,
  first_in          timestamptz,
  last_out          timestamptz,
  punch_count       int not null default 0,
  worked_minutes    int not null default 0,
  late_minutes      int not null default 0,
  early_minutes     int not null default 0,
  extra_minutes     int not null default 0,
  status            text not null check (status in ('PRESENT','ABSENT','LEAVE','HOLIDAY','REST','MISSING_PUNCH','NO_SHIFT')),
  leave_request_id  uuid references hr.leave_requests(id),
  leave_type        text,
  leave_fraction    numeric(3,2) not null default 0,
  worked_off_day    boolean not null default false,
  is_ramadan        boolean not null default false,
  computed_at       timestamptz not null default now(),
  primary key (employee_id, work_date)
);
create index if not exists attendance_days_date on hr.attendance_days(work_date, status);
create index if not exists attendance_days_shift on hr.attendance_days(shift_id);
create index if not exists attendance_days_leave on hr.attendance_days(leave_request_id);

-- Re-define attach_audit to skip derived tables.
create or replace function hr.attach_audit()
returns void language plpgsql set search_path = '' as $$
declare r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'hr' and c.relkind = 'r'
      and c.relname not in ('audit_log','access_log','notifications','attendance_days')
  loop
    if not exists (select 1 from pg_trigger t join pg_class c2 on c2.oid = t.tgrelid
                   join pg_namespace n2 on n2.oid = c2.relnamespace
                   where n2.nspname = 'hr' and c2.relname = r.relname and t.tgname = 'zz_audit') then
      execute format('create trigger zz_audit after insert or update or delete on hr.%I
                      for each row execute function hr.audit_trigger()', r.relname);
    end if;
    if exists (select 1 from information_schema.columns
               where table_schema = 'hr' and table_name = r.relname and column_name = 'updated_at')
       and not exists (select 1 from pg_trigger t join pg_class c2 on c2.oid = t.tgrelid
                       join pg_namespace n2 on n2.oid = c2.relnamespace
                       where n2.nspname = 'hr' and c2.relname = r.relname and t.tgname = 'aa_touch') then
      execute format('create trigger aa_touch before update on hr.%I
                      for each row execute function hr.touch_updated_at()', r.relname);
    end if;
    execute format('alter table hr.%I enable row level security', r.relname);
  end loop;
  alter table hr.audit_log enable row level security;
  alter table hr.access_log enable row level security;
  alter table hr.attendance_days enable row level security;
end $$;

-- Approved leave covering a day (full day first)
create or replace function hr.leave_on(p_employee uuid, p_on date)
returns hr.leave_requests language sql stable security definer set search_path = '' as $$
  select r.* from hr.leave_requests r
  where r.employee_id = p_employee and r.status = 'APPROVED' and p_on between r.start_date and r.end_date
  order by r.half_day, r.start_date limit 1
$$;

create or replace function hr.in_ramadan(p_on date)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from hr.special_periods sp where sp.code = 'RAMADAN' and p_on between sp.start_date and sp.end_date)
$$;

-- Rebuild attendance for one employee and date range (never future days, never locked months).
create or replace function hr.compute_attendance(p_employee uuid, p_from date, p_to date)
returns int language plpgsql security definer set search_path = '' as $$
declare
  e hr.employees; d date; s hr.shifts; s_next hr.shifts; lv hr.leave_requests; h hr.holidays;
  att jsonb; v_grace int; v_before int; v_after int; v_gap int;
  v_ss timestamptz; v_se timestamptz; v_ws timestamptz; v_we timestamptz; v_next_ss timestamptz;
  v_first timestamptz; v_last timestamptz; v_count int; v_worked int; v_status text; v_sched int;
  v_rest boolean; v_late int; v_early int; v_frac numeric; v_to date; v_n int := 0; v_span int;
begin
  select * into e from hr.employees where id = p_employee;
  if e.id is null then return 0; end if;
  v_to := least(p_to, hr.today());
  for d in select generate_series(p_from, v_to, interval '1 day')::date loop
    continue when hr.is_locked(p_employee, d);
    if d < e.join_date or (e.separation_date is not null and d > e.separation_date) then
      delete from hr.attendance_days where employee_id = p_employee and work_date = d;
      continue;
    end if;
    att := coalesce(hr.rule('ATTENDANCE', d), '{}'::jsonb);
    v_before := coalesce((att->>'window_before_minutes')::int, 180);
    v_after := coalesce((att->>'window_after_minutes')::int, 360);
    v_gap := coalesce((att->>'min_minutes_between_punches')::int, 5);
    s := hr.shift_for(p_employee, d);
    lv := hr.leave_on(p_employee, d);
    h := hr.holiday_on(e.entity_id, d);
    v_rest := s.id is not null and extract(isodow from d)::int = any(s.rest_days);
    if s.id is not null then
      v_ss := hr.local_ts(d, s.start_time);
      v_se := hr.local_ts(d + case when s.end_time > s.start_time then 0 else 1 end, s.end_time);
      v_sched := hr.shift_net_minutes(s);
      v_grace := coalesce(s.grace_minutes, (att->>'late_grace_minutes')::int, 10);
      v_ws := v_ss - make_interval(mins => v_before);
      v_we := v_se + make_interval(mins => v_after);
      s_next := hr.shift_for(p_employee, d + 1);
      if s_next.id is not null then
        v_next_ss := hr.local_ts(d + 1, s_next.start_time) - make_interval(mins => v_before);
        if v_next_ss < v_we and v_next_ss > v_se then v_we := v_next_ss; end if;
      end if;
    else
      v_ss := null; v_se := null; v_sched := 0; v_grace := 0;
      v_ws := hr.local_ts(d, time '00:00'); v_we := hr.local_ts(d + 1, time '00:00');
    end if;
    select min(punch_at), max(punch_at), count(*) into v_first, v_last, v_count
      from hr.punches where employee_id = p_employee and punch_at >= v_ws and punch_at < v_we;
    if v_count >= 2 and extract(epoch from (v_last - v_first)) / 60 >= v_gap then
      v_span := (extract(epoch from (v_last - v_first)) / 60)::int;
      v_worked := greatest(0, v_span - case when v_span > 360 and s.id is not null then s.break_minutes else 0 end);
    else
      v_worked := 0;
      if v_count >= 2 then v_count := 1; v_last := null; end if;
      if v_count = 1 then v_last := null; end if;
    end if;
    v_frac := case when lv.id is null then 0 when lv.half_day then 0.5 else 1 end;
    -- a working day that has not started yet (start + grace still ahead, nothing punched) gets no row yet
    if s.id is not null and v_count = 0 and v_frac < 1 and h.id is null and not v_rest and now() < v_ss + make_interval(mins => v_grace) then
      delete from hr.attendance_days where employee_id = p_employee and work_date = d;
      continue;
    end if;
    if v_frac = 1 then v_status := 'LEAVE';
    elsif h.id is not null then v_status := 'HOLIDAY';
    elsif v_rest then v_status := 'REST';
    elsif s.id is null then v_status := 'NO_SHIFT';
    elsif v_count = 0 then v_status := case when v_frac = 0.5 then 'LEAVE' else 'ABSENT' end;
    elsif v_count = 1 and s.id is not null and now() < v_we then v_status := 'PRESENT';   -- shift still running: in, not yet out
    elsif v_count = 1 then v_status := 'MISSING_PUNCH';
    else v_status := 'PRESENT';
    end if;
    v_late := 0; v_early := 0;
    if v_status = 'PRESENT' and v_ss is not null then
      if extract(epoch from (v_first - v_ss)) / 60 > v_grace then v_late := (extract(epoch from (v_first - v_ss)) / 60)::int; end if;
      if v_last is not null and v_last < v_se then v_early := (extract(epoch from (v_se - v_last)) / 60)::int; end if;
      if v_frac = 0.5 then v_late := 0; v_early := 0; end if;
    end if;
    insert into hr.attendance_days(employee_id, work_date, shift_id, sched_start, sched_end, sched_minutes, first_in, last_out,
                                   punch_count, worked_minutes, late_minutes, early_minutes, extra_minutes, status,
                                   leave_request_id, leave_type, leave_fraction, worked_off_day, is_ramadan, computed_at)
    values (p_employee, d, s.id,
            case when v_status in ('REST','HOLIDAY') then null else v_ss end,
            case when v_status in ('REST','HOLIDAY') then null else v_se end,
            case when v_status in ('REST','HOLIDAY','NO_SHIFT') or v_frac = 1 then 0
                 when v_frac = 0.5 then (v_sched / 2) else v_sched end,
            v_first, v_last, v_count, v_worked, v_late, v_early,
            case when v_status = 'PRESENT' then greatest(0, v_worked - case when v_frac = 0.5 then v_sched / 2 else v_sched end) else 0 end,
            v_status, lv.id, lv.leave_type, v_frac,
            v_count > 0 and (v_status in ('REST','HOLIDAY')), hr.in_ramadan(d), now())
    on conflict (employee_id, work_date) do update set
      shift_id = excluded.shift_id, sched_start = excluded.sched_start, sched_end = excluded.sched_end,
      sched_minutes = excluded.sched_minutes, first_in = excluded.first_in, last_out = excluded.last_out,
      punch_count = excluded.punch_count, worked_minutes = excluded.worked_minutes, late_minutes = excluded.late_minutes,
      early_minutes = excluded.early_minutes, extra_minutes = excluded.extra_minutes, status = excluded.status,
      leave_request_id = excluded.leave_request_id, leave_type = excluded.leave_type, leave_fraction = excluded.leave_fraction,
      worked_off_day = excluded.worked_off_day, is_ramadan = excluded.is_ramadan, computed_at = excluded.computed_at;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- Minutes of [p_start, p_end) that fall in the nightly window (e.g. 21:00–05:00 Muscat time)
create or replace function hr.night_minutes(p_start timestamptz, p_end timestamptz, p_night_start time, p_night_end time)
returns int language plpgsql stable set search_path = '' as $$
declare d date; v_total numeric := 0; ns timestamptz; ne timestamptz;
begin
  for d in select generate_series(((p_start at time zone 'Asia/Muscat')::date - 1), ((p_end at time zone 'Asia/Muscat')::date), interval '1 day')::date loop
    ns := (d + p_night_start) at time zone 'Asia/Muscat';
    ne := ((d + case when p_night_end <= p_night_start then 1 else 0 end) + p_night_end) at time zone 'Asia/Muscat';
    v_total := v_total + greatest(0, extract(epoch from (least(p_end, ne) - greatest(p_start, ns))) / 60);
  end loop;
  return round(v_total)::int;
end $$;

-- ---------------------------------------------------------------------------
-- Leave helpers
-- ---------------------------------------------------------------------------
create or replace function hr.leave_day_count(p_employee uuid, p_type text, p_from date, p_to date, p_half boolean)
returns numeric language plpgsql stable security definer set search_path = '' as $$
declare t hr.leave_types; e hr.employees; d date; n numeric := 0; s hr.shifts;
begin
  select * into t from hr.leave_types where code = p_type;
  select * into e from hr.employees where id = p_employee;
  if p_half then return 0.5; end if;
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    if t.count_mode = 'CALENDAR' then n := n + 1;
    elsif t.count_mode = 'CALENDAR_EXCL_HOLIDAYS' then
      if (hr.holiday_on(e.entity_id, d)).id is null then n := n + 1; end if;
    else
      s := hr.shift_for(p_employee, d);
      if (hr.holiday_on(e.entity_id, d)).id is null
         and not (s.id is not null and extract(isodow from d)::int = any(s.rest_days))
         and not (s.id is null and extract(isodow from d)::int in (5, 6)) then n := n + 1; end if;
    end if;
  end loop;
  return n;
end $$;

-- Balance of one leave type for one employee as at a date.
create or replace function hr.leave_balance(p_employee uuid, p_type text, p_on date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  t hr.leave_types; v_on date := coalesce(p_on, hr.today()); v_y0 date; v_y1 date;
  v_entitled numeric; v_used numeric; v_pending numeric; v_adj numeric;
begin
  select * into t from hr.leave_types where code = p_type;
  if t.code is null then return null; end if;
  v_y0 := date_trunc('year', v_on)::date; v_y1 := (date_trunc('year', v_on) + interval '1 year - 1 day')::date;
  select coalesce(sum(r.days), 0) into v_pending from hr.leave_requests r
   where r.employee_id = p_employee and r.leave_type = p_type and r.status in ('PENDING_MANAGER','PENDING_HR')
     and (t.quota_period <> 'YEAR' or t.accrual = 'MONTHLY' or r.start_date between v_y0 and v_y1);
  if t.accrual = 'MONTHLY' then
    select coalesce(sum(days) filter (where kind in ('OPENING','ACCRUAL','ADJUSTMENT','CARRY_EXPIRY') and entry_date <= v_on), 0),
           coalesce(-sum(days) filter (where kind in ('TAKEN','REVERSAL')), 0)
      into v_entitled, v_used
      from hr.leave_ledger where employee_id = p_employee and leave_type = p_type;
  elsif t.quota_period = 'YEAR' then
    select coalesce(sum(days) filter (where kind in ('OPENING','ADJUSTMENT') and entry_date between v_y0 and v_y1), 0),
           coalesce(-sum(days) filter (where kind in ('TAKEN','REVERSAL') and entry_date between v_y0 and v_y1), 0)
      into v_adj, v_used
      from hr.leave_ledger where employee_id = p_employee and leave_type = p_type;
    v_entitled := t.quota_days + v_adj;
  elsif t.quota_period = 'ONCE' then
    select coalesce(sum(days) filter (where kind in ('OPENING','ADJUSTMENT')), 0),
           coalesce(-sum(days) filter (where kind in ('TAKEN','REVERSAL')), 0)
      into v_adj, v_used
      from hr.leave_ledger where employee_id = p_employee and leave_type = p_type;
    v_entitled := t.quota_days + v_adj;
  else
    select coalesce(-sum(days) filter (where kind in ('TAKEN','REVERSAL') and entry_date between v_y0 and v_y1), 0)
      into v_used from hr.leave_ledger where employee_id = p_employee and leave_type = p_type;
    v_entitled := t.quota_days;
  end if;
  return jsonb_build_object(
    'leave_type', t.code, 'name_en', t.name_en, 'name_ar', t.name_ar, 'quota_period', t.quota_period, 'accrual', t.accrual,
    'quota_days', t.quota_days, 'entitled', v_entitled, 'used', v_used, 'pending', v_pending,
    'available', case when t.quota_period in ('EVENT','NONE') then null else v_entitled - v_used end,
    'as_of', v_on);
end $$;

-- Pay split of sick-leave days by tier, given the sick days already taken earlier in the same year.
create or replace function hr.tier_breakdown(p_tiers jsonb, p_prior numeric, p_days numeric)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare t jsonb; v_res jsonb := '[]'::jsonb; v_start numeric := p_prior + 1; v_end numeric := p_prior + p_days;
        v_from numeric; v_to numeric; v_n numeric; v_covered numeric := 0;
begin
  for t in select * from jsonb_array_elements(p_tiers) loop
    v_from := (t->>'from')::numeric; v_to := (t->>'to')::numeric;
    v_n := greatest(0, least(v_end, v_to) - greatest(v_start, v_from) + 1);
    if v_n > 0 then
      v_res := v_res || jsonb_build_array(jsonb_build_object('pct', (t->>'pct')::numeric, 'days', v_n));
      v_covered := v_covered + v_n;
    end if;
  end loop;
  if v_covered < p_days then
    v_res := v_res || jsonb_build_array(jsonb_build_object('pct', 0, 'days', p_days - v_covered));
  end if;
  return v_res;
end $$;

-- Monthly accrual of annual leave (2.5 days per full month for a 30-day entitlement), idempotent per month.
create or replace function hr.accrue_leave(p_through date)
returns int language plpgsql security definer set search_path = '' as $$
declare
  t record; e record; m date; v_start date; v_open date; v_days numeric; v_in numeric; v_month_days int; v_n int := 0; v_rows int;
begin
  select (value #>> '{}')::date into v_open from hr.settings where key = 'leave_opening_date' and jsonb_typeof(value) = 'string';
  for t in select * from hr.leave_types where accrual = 'MONTHLY' and is_active and quota_days is not null loop
    for e in select id, join_date, separation_date from hr.employees loop
      v_start := greatest(e.join_date, coalesce(v_open, e.join_date));
      for m in select generate_series(date_trunc('month', v_start), date_trunc('month', p_through), interval '1 month')::date loop
        exit when (m + interval '1 month - 1 day')::date > p_through;
        v_month_days := extract(day from (m + interval '1 month - 1 day'))::int;
        v_in := greatest(0, (least((m + interval '1 month - 1 day')::date, coalesce(e.separation_date, '9999-12-31'::date))
                            - greatest(m, v_start)) + 1);
        continue when v_in <= 0;
        v_days := round(t.quota_days / 12.0 * least(v_in, v_month_days) / v_month_days, 2);
        continue when v_days <= 0;
        insert into hr.leave_ledger(employee_id, leave_type, entry_date, days, kind, period_key, note)
        values (e.id, t.code, (m + interval '1 month - 1 day')::date, v_days, 'ACCRUAL', to_char(m, 'YYYY-MM'),
                'Monthly accrual')
        on conflict do nothing;
        get diagnostics v_rows = row_count;
        v_n := v_n + v_rows;
      end loop;
    end loop;
  end loop;
  return v_n;
end $$;

-- Year end: balance above the carry-forward limit lapses (entry dated 31 Dec).
create or replace function hr.close_leave_year(p_year int)
returns int language plpgsql security definer set search_path = '' as $$
declare t record; e record; v_bal numeric; v_end date := make_date(p_year, 12, 31); v_n int := 0; v_rows int;
begin
  perform hr.accrue_leave(v_end);
  for t in select * from hr.leave_types where accrual = 'MONTHLY' and carry_forward_max is not null loop
    for e in select id from hr.employees where join_date <= v_end loop
      select coalesce(sum(days), 0) into v_bal from hr.leave_ledger
       where employee_id = e.id and leave_type = t.code and entry_date <= v_end;
      if v_bal > t.carry_forward_max then
        insert into hr.leave_ledger(employee_id, leave_type, entry_date, days, kind, period_key, note)
        values (e.id, t.code, v_end, -(v_bal - t.carry_forward_max), 'CARRY_EXPIRY', 'CF-' || p_year,
                'Above the carry-forward limit of ' || t.carry_forward_max || ' days')
        on conflict do nothing;
        get diagnostics v_rows = row_count;
        v_n := v_n + v_rows;
      end if;
    end loop;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------
-- Approval routing (employee → line manager → HR); nobody approves their own request.
-- ---------------------------------------------------------------------------
create or replace function hr.manager_user_of(p_employee uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select up.user_id from hr.user_profiles up
  where up.is_active and up.employee_id = (hr.current_assignment(p_employee)).manager_id
  limit 1
$$;

create or replace function hr.first_status(p_employee uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_mgr uuid := hr.manager_user_of(p_employee);
begin
  if hr.is_me(p_employee) and v_mgr is not null and v_mgr <> auth.uid() then return 'PENDING_MANAGER'; end if;
  return 'PENDING_HR';
end $$;

create or replace function hr.can_decide(p_status text, p_employee uuid, p_requested_by uuid, p_hr_perm text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or auth.uid() = p_requested_by or hr.is_me(p_employee) then return false; end if;
  if p_status = 'PENDING_MANAGER' then return auth.uid() = hr.manager_user_of(p_employee) or hr.has_perm(p_hr_perm); end if;
  if p_status = 'PENDING_HR' then return hr.has_perm(p_hr_perm); end if;
  return false;
end $$;

-- Who may see time and leave data of an employee
create or replace function hr.can_see_time(p_employee uuid, p_perm text)
returns boolean language sql stable security definer set search_path = '' as $$
  select hr.has_perm(p_perm) or hr.is_me(p_employee) or hr.is_my_team(p_employee)
$$;

create or replace function hr.notify_approvers(p_employee uuid, p_status text, p_perm text, p_kind text,
                                               p_title_en text, p_title_ar text, p_link text, p_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare u record;
begin
  if p_status = 'PENDING_MANAGER' then
    perform hr.notify(hr.manager_user_of(p_employee), p_kind, 'NORMAL', p_title_en, p_title_ar, null, null, p_link, p_ref);
  else
    for u in select user_id from hr.users_with_perm(p_perm) loop
      continue when u.user_id = auth.uid();
      perform hr.notify(u.user_id, p_kind, 'NORMAL', p_title_en, p_title_ar, null, null, p_link, p_ref);
    end loop;
  end if;
end $$;

create or replace function hr.employee_user(p_employee uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select user_id from hr.user_profiles where employee_id = p_employee and is_active limit 1
$$;

-- Storage: employees may upload their own leave attachments (document types marked self_upload).
create or replace function public.hr_storage_can_write(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_emp uuid; v_type text;
begin
  if auth.uid() is null or array_length(v_parts, 1) <> 3 then return false; end if;
  if v_parts[1] !~ '^[0-9a-fA-F-]{36}$' then return false; end if;
  v_emp := v_parts[1]::uuid; v_type := v_parts[2];
  if not exists (select 1 from hr.user_profiles where user_id = auth.uid() and is_active) then return false; end if;
  if not exists (select 1 from hr.employees where id = v_emp) then return false; end if;
  if v_type = 'PHOTO' then return hr.has_perm('EMP_WRITE'); end if;
  if not exists (select 1 from hr.document_types where code = v_type and is_active) then return false; end if;
  if hr.has_perm('DOC_WRITE') then return true; end if;
  return hr.is_me(v_emp) and exists (select 1 from hr.document_types where code = v_type and is_active and self_upload);
end $$;

-- Re-evaluate yesterday and today for everyone on a shift, so a day "in progress" becomes MISSING_PUNCH
-- once its punch window has closed even when no further punches are imported.
create or replace function hr.recompute_recent()
returns int language plpgsql security definer set search_path = '' as $$
declare x record; n int := 0;
begin
  for x in select distinct a.employee_id from hr.shift_assignments a join hr.employees e on e.id = a.employee_id
           where e.status <> 'SEPARATED' and a.effective_from <= hr.today() and (a.effective_to is null or a.effective_to >= hr.today() - 1) loop
    n := n + hr.compute_attendance(x.employee_id, hr.today() - 1, hr.today());
  end loop;
  return n;
end $$;
revoke all on function hr.recompute_recent() from public;

do $cron2$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    if not exists (select 1 from cron.job where jobname = 'hr-attendance-hourly') then
      perform cron.schedule('hr-attendance-hourly', '7 * * * *', 'select hr.recompute_recent()');
    end if;
  end if;
end $cron2$;

-- Monthly accrual on the 1st at 03:15 UTC (07:15 Muscat) where pg_cron is available.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    if not exists (select 1 from cron.job where jobname = 'hr-leave-accrual') then
      perform cron.schedule('hr-leave-accrual', '15 3 1 * *', 'select hr.accrue_leave((now() at time zone ''Asia/Muscat'')::date - 1)');
    end if;
  end if;
end $$;

select hr.attach_audit();
select hr.secure_api();
