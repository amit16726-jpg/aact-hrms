-- AACT HRMS — 003 employees, effective-dated assignments, events, contracts, compensation, bank

create table if not exists hr.employees (
  id                 uuid primary key default gen_random_uuid(),
  entity_id          uuid not null references hr.legal_entities(id),
  employee_no        text not null unique,
  full_name_en       text not null check (length(trim(full_name_en)) > 1),
  full_name_ar       text,
  preferred_name     text,
  date_of_birth      date,
  gender             char(1) check (gender in ('M','F')),
  nationality        char(2) not null references hr.countries(code),
  marital_status     text check (marital_status in ('SINGLE','MARRIED','DIVORCED','WIDOWED')),
  civil_number       text,           -- Omani civil number or expatriate resident card number
  personal_email     text,
  work_email         text,
  mobile             text,
  alt_phone          text,
  address_line       text,
  city               text,
  wilayat            text,
  governorate        text,
  address_country    char(2) references hr.countries(code),
  photo_path         text,
  original_join_date date not null,
  join_date          date not null,
  probation_end_date date,
  confirmation_date  date,
  status             text not null default 'PROBATION'
                     check (status in ('PROBATION','ACTIVE','NOTICE','SUSPENDED','SEPARATED')),
  notice_given_date  date,
  last_working_date  date,
  separation_date    date,
  separation_type    text check (separation_type in ('RESIGNATION','TERMINATION','END_OF_CONTRACT','RETIREMENT','DEATH','OTHER')),
  separation_reason  text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid,
  check (date_of_birth is null or date_of_birth < join_date),
  check (probation_end_date is null or probation_end_date >= join_date),
  check (confirmation_date is null or confirmation_date >= join_date),
  check (separation_date is null or separation_date >= join_date),
  check (status <> 'SEPARATED' or separation_date is not null)
);
create unique index if not exists employees_civil_number_uq on hr.employees(upper(civil_number)) where civil_number is not null;
create index if not exists employees_entity_status on hr.employees(entity_id, status);
create index if not exists employees_name_lower on hr.employees(lower(full_name_en));

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'user_profiles_employee_fk') then
    alter table hr.user_profiles
      add constraint user_profiles_employee_fk foreign key (employee_id) references hr.employees(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'departments_head_fk') then
    alter table hr.departments
      add constraint departments_head_fk foreign key (head_employee_id) references hr.employees(id);
  end if;
end $$;

create table if not exists hr.emergency_contacts (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references hr.employees(id),
  name          text not null,
  relationship  text not null,
  phone         text not null,
  alt_phone     text,
  address       text,
  is_next_of_kin boolean not null default false,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists emergency_contacts_emp on hr.emergency_contacts(employee_id);

-- Effective-dated assignment: one row per period, periods never overlap.
create table if not exists hr.employee_assignments (
  id              uuid primary key default gen_random_uuid(),
  employee_id     uuid not null references hr.employees(id),
  effective_from  date not null,
  effective_to    date,
  department_id   uuid not null references hr.departments(id),
  job_title_id    uuid not null references hr.job_titles(id),
  grade_id        uuid references hr.grades(id),
  category_id     uuid not null references hr.employee_categories(id),
  location_id     uuid references hr.locations(id),
  cost_centre_id  uuid references hr.cost_centres(id),
  manager_id      uuid references hr.employees(id),
  employment_type text not null default 'FULL_TIME'
                  check (employment_type in ('FULL_TIME','PART_TIME','TEMPORARY','TRAINEE')),
  shift_code      text,
  reason          text not null default 'JOIN'
                  check (reason in ('JOIN','TRANSFER','PROMOTION','DEMOTION','REORGANISATION','REHIRE','CORRECTION','OTHER')),
  omanisation_exception_id uuid,
  notes           text,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (manager_id is null or manager_id <> employee_id),
  constraint employee_assignments_no_overlap exclude using gist (
    employee_id with =,
    daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') with &&)
);
create index if not exists employee_assignments_emp on hr.employee_assignments(employee_id, effective_from desc);
create index if not exists employee_assignments_mgr on hr.employee_assignments(manager_id) where effective_to is null;

create table if not exists hr.employee_events (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references hr.employees(id),
  event_type  text not null check (event_type in (
                'JOIN','CONFIRM','TRANSFER','PROMOTION','DEMOTION','REORGANISATION','ASSIGNMENT_CORRECTION',
                'SALARY_REVISION','BANK_CHANGE','CONTRACT','NOTICE','NOTICE_WITHDRAWN','SUSPEND','REINSTATE',
                'SEPARATION','REHIRE','PERSONAL_UPDATE','OMANISATION_EXCEPTION')),
  event_date  date not null,
  details     jsonb not null default '{}'::jsonb,
  created_by  uuid,
  created_at  timestamptz not null default now()
);
create index if not exists employee_events_emp on hr.employee_events(employee_id, event_date desc, created_at desc);

create table if not exists hr.employee_contracts (
  id              uuid primary key default gen_random_uuid(),
  employee_id     uuid not null references hr.employees(id),
  contract_no     text,
  contract_type   text not null check (contract_type in ('FIXED_TERM','INDEFINITE')),
  start_date      date not null,
  end_date        date,
  probation_days  int check (probation_days is null or probation_days between 0 and 365),
  notice_days     int check (notice_days is null or notice_days between 0 and 365),
  working_hours_per_week numeric(5,2),
  mol_registration_no text,
  version         int not null default 1,
  supersedes_id   uuid references hr.employee_contracts(id),
  status          text not null default 'ACTIVE' check (status in ('ACTIVE','SUPERSEDED','ENDED','CANCELLED')),
  document_id     uuid,
  notes           text,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (contract_type <> 'FIXED_TERM' or end_date is not null),
  check (end_date is null or end_date >= start_date)
);
create unique index if not exists employee_contracts_one_active on hr.employee_contracts(employee_id) where status = 'ACTIVE';

-- ---------------------------------------------------------------------------
-- Compensation (restricted) — revisions are proposed then approved by someone else
-- ---------------------------------------------------------------------------
create table if not exists hr.pay_components (
  code       text primary key,
  name_en    text not null,
  name_ar    text not null,
  kind       text not null check (kind in ('EARNING','DEDUCTION')),
  is_basic   boolean not null default false,
  sort       int not null default 100,
  is_active  boolean not null default true
);

insert into hr.pay_components(code, name_en, name_ar, kind, is_basic, sort) values
  ('BASIC',      'Basic salary',          'الراتب الأساسي',   'EARNING', true, 1),
  ('HOUSING',    'Housing allowance',     'بدل السكن',        'EARNING', false, 2),
  ('TRANSPORT',  'Transport allowance',   'بدل النقل',        'EARNING', false, 3),
  ('FOOD',       'Food allowance',        'بدل الطعام',       'EARNING', false, 4),
  ('TELEPHONE',  'Telephone allowance',   'بدل الهاتف',       'EARNING', false, 5),
  ('UTILITY',    'Utility allowance',     'بدل المرافق',      'EARNING', false, 6),
  ('SPECIAL',    'Special allowance',     'بدل خاص',          'EARNING', false, 7),
  ('OTHER_ALLOW','Other allowance',       'بدلات أخرى',       'EARNING', false, 8),
  ('FIXED_DED',  'Fixed deduction',       'استقطاع ثابت',     'DEDUCTION', false, 50)
on conflict (code) do nothing;

create table if not exists hr.compensation_revisions (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references hr.employees(id),
  effective_from date not null,
  reason         text not null check (reason in ('JOIN','INCREMENT','PROMOTION','ADJUSTMENT','CORRECTION','REHIRE')),
  status         text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','SUPERSEDED')),
  total_monthly  numeric(12,3) not null default 0,
  notes          text,
  proposed_by    uuid not null,
  proposed_at    timestamptz not null default now(),
  decided_by     uuid,
  decided_at     timestamptz,
  decision_note  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (decided_by is null or decided_by <> proposed_by)
);
create index if not exists compensation_revisions_emp on hr.compensation_revisions(employee_id, effective_from desc);
create unique index if not exists compensation_one_pending on hr.compensation_revisions(employee_id) where status = 'PENDING';
create unique index if not exists compensation_one_approved_per_date
  on hr.compensation_revisions(employee_id, effective_from) where status = 'APPROVED';

create table if not exists hr.compensation_lines (
  id             uuid primary key default gen_random_uuid(),
  revision_id    uuid not null references hr.compensation_revisions(id),
  employee_id    uuid not null references hr.employees(id),
  component_code text not null references hr.pay_components(code),
  amount         numeric(12,3) not null check (amount >= 0),
  unique (revision_id, component_code)
);

-- ---------------------------------------------------------------------------
-- Bank accounts (restricted) — change requested, then approved by someone else
-- ---------------------------------------------------------------------------
create table if not exists hr.employee_bank_accounts (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references hr.employees(id),
  bank_name      text not null,
  branch         text,
  account_name   text not null,
  account_number text not null,
  iban           text,
  swift_code     text,
  effective_from date not null default current_date,
  status         text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','SUPERSEDED')),
  requested_by   uuid not null,
  requested_at   timestamptz not null default now(),
  decided_by     uuid,
  decided_at     timestamptz,
  decision_note  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (decided_by is null or decided_by <> requested_by)
);
create unique index if not exists bank_one_approved on hr.employee_bank_accounts(employee_id) where status = 'APPROVED';
create unique index if not exists bank_one_pending on hr.employee_bank_accounts(employee_id) where status = 'PENDING';

-- ---------------------------------------------------------------------------
-- Visibility helpers
-- ---------------------------------------------------------------------------
create or replace function hr.current_assignment(p_employee uuid, p_on date default current_date)
returns hr.employee_assignments language sql stable security definer set search_path = '' as $$
  select a.* from hr.employee_assignments a
  where a.employee_id = p_employee
    and a.effective_from <= p_on
    and (a.effective_to is null or a.effective_to >= p_on)
  order by a.effective_from desc
  limit 1
$$;

-- Everyone who reports to p_manager, directly or indirectly, on today's assignments.
create or replace function hr.team_of(p_manager uuid)
returns table(employee_id uuid) language sql stable security definer set search_path = '' as $$
  with recursive t(employee_id, depth) as (
    select a.employee_id, 1
    from hr.employee_assignments a
    where a.manager_id = p_manager
      and a.effective_from <= current_date and (a.effective_to is null or a.effective_to >= current_date)
    union
    select a.employee_id, t.depth + 1
    from hr.employee_assignments a
    join t on a.manager_id = t.employee_id
    where a.effective_from <= current_date and (a.effective_to is null or a.effective_to >= current_date)
      and t.depth < 12
  )
  select distinct employee_id from t where employee_id <> p_manager
$$;

create or replace function hr.is_my_team(p_employee uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select hr.my_employee_id() is not null
     and exists (select 1 from hr.team_of(hr.my_employee_id()) t where t.employee_id = p_employee)
$$;

-- 'FULL' (HR-level), 'SELF', 'TEAM' (limited fields) or null (no access)
create or replace function hr.employee_access(p_employee uuid)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when hr.has_perm('EMP_READ') then 'FULL'
    when hr.is_me(p_employee) then 'SELF'
    when hr.is_my_team(p_employee) then 'TEAM'
    else null end
$$;

create or replace function hr.require_employee_access(p_employee uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  perform hr.require_user();
  if not exists (select 1 from hr.employees where id = p_employee) then
    raise exception 'NOT_FOUND: Employee not found.';
  end if;
  v := hr.employee_access(p_employee);
  if v is null then
    raise exception 'NOT_ALLOWED: You cannot see this employee.' using errcode = '42501';
  end if;
  return v;
end $$;

create or replace function hr.next_employee_no()
returns text language plpgsql security definer set search_path = '' as $$
declare v_prefix text; v_digits int; v_no text;
begin
  select value #>> '{}' into v_prefix from hr.settings where key = 'employee_no_prefix';
  select (value #>> '{}')::int into v_digits from hr.settings where key = 'employee_no_digits';
  loop
    v_no := coalesce(v_prefix,'') || lpad(nextval('hr.employee_no_seq')::text, coalesce(v_digits,5), '0');
    exit when not exists (select 1 from hr.employees where employee_no = v_no);
  end loop;
  return v_no;
end $$;

select hr.attach_audit();
select hr.secure_api();
