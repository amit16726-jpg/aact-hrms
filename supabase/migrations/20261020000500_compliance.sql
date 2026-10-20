-- AACT HRMS — 005 compliance: expiry tracking, missing documents, Omanisation, notifications

-- ---------------------------------------------------------------------------
-- Omanisation targets: no figures are seeded. Each target carries its source and is
-- proposed by one user and approved by another (maker-checker).
-- ---------------------------------------------------------------------------
create table if not exists hr.omanisation_targets (
  id               uuid primary key default gen_random_uuid(),
  entity_id        uuid not null references hr.legal_entities(id),
  scope_type       text not null check (scope_type in ('ENTITY','DEPARTMENT','JOB_TITLE','PROFESSION_CODE')),
  scope_id         uuid,
  profession_code  text,
  target_pct       numeric(5,2) not null check (target_pct between 0 and 100),
  effective_from   date not null,
  effective_to     date,
  rule_basis       text not null check (rule_basis in ('LEGAL','COMPANY_POLICY')),
  source_reference text not null check (length(trim(source_reference)) >= 3),
  notes            text,
  status           text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','RETIRED')),
  proposed_by      uuid not null,
  proposed_at      timestamptz not null default now(),
  decided_by       uuid,
  decided_at       timestamptz,
  decision_note    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (decided_by is null or decided_by <> proposed_by),
  check ((scope_type = 'ENTITY' and scope_id is null and profession_code is null)
      or (scope_type in ('DEPARTMENT','JOB_TITLE') and scope_id is not null and profession_code is null)
      or (scope_type = 'PROFESSION_CODE' and scope_id is null and coalesce(profession_code,'') <> ''))
);
create index if not exists omanisation_targets_entity on hr.omanisation_targets(entity_id, status);

create table if not exists hr.omanisation_exceptions (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references hr.employees(id),
  job_title_id uuid not null references hr.job_titles(id),
  reason       text not null check (length(trim(reason)) >= 10),
  reference    text,
  valid_to     date,
  status       text not null default 'ACTIVE' check (status in ('ACTIVE','REVOKED')),
  approved_by  uuid not null,
  approved_at  timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'employee_assignments_exception_fk') then
    alter table hr.employee_assignments
      add constraint employee_assignments_exception_fk
      foreign key (omanisation_exception_id) references hr.omanisation_exceptions(id);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Expiry items: current documents with an expiry date + active fixed-term contracts
-- ---------------------------------------------------------------------------
create or replace function hr.expiry_bucket(p_days int)
returns text language sql immutable set search_path = '' as $$
  select case when p_days is null then null
              when p_days < 0 then 'EXPIRED'
              when p_days <= 30 then 'D30'
              when p_days <= 60 then 'D60'
              when p_days <= 90 then 'D90'
              else 'LATER' end
$$;

create or replace function hr.expiry_items(p_on date default current_date)
returns table (
  employee_id uuid, source text, ref_id uuid, doc_type text, name_en text, name_ar text,
  doc_number text, expiry_date date, days_left int, bucket text, is_sensitive boolean, alert_days int[])
language sql stable security definer set search_path = '' as $$
  select d.employee_id, 'DOCUMENT', d.id, d.doc_type, t.name_en, t.name_ar, d.doc_number, d.expiry_date,
         (d.expiry_date - p_on)::int, hr.expiry_bucket((d.expiry_date - p_on)::int), t.is_sensitive, t.alert_days
  from hr.employee_documents d
  join hr.document_types t on t.code = d.doc_type
  join hr.employees e on e.id = d.employee_id
  where d.is_current and d.status = 'ACTIVE' and d.expiry_date is not null and e.status <> 'SEPARATED'
  union all
  select c.employee_id, 'CONTRACT', c.id, 'CONTRACT', 'Employment contract', 'عقد العمل', c.contract_no, c.end_date,
         (c.end_date - p_on)::int, hr.expiry_bucket((c.end_date - p_on)::int), false, '{90,60,30}'::int[]
  from hr.employee_contracts c
  join hr.employees e on e.id = c.employee_id
  where c.status = 'ACTIVE' and c.end_date is not null and e.status <> 'SEPARATED'
$$;

create or replace function hr.missing_documents(p_on date default current_date)
returns table (employee_id uuid, doc_type text, name_en text, name_ar text)
language sql stable security definer set search_path = '' as $$
  select e.id, t.code, t.name_en, t.name_ar
  from hr.employees e
  join hr.document_types t on t.is_active and t.is_mandatory
   and (t.applies_to = 'ALL'
        or (t.applies_to = 'OMANI' and e.nationality = 'OM')
        or (t.applies_to = 'EXPAT' and e.nationality <> 'OM'))
  where e.status <> 'SEPARATED' and e.join_date <= p_on
    and not exists (select 1 from hr.employee_documents d
                    where d.employee_id = e.id and d.doc_type = t.code and d.is_current and d.status = 'ACTIVE')
$$;

-- Headcount counted for Omanisation on a date, with the assignment then in force.
create or replace function hr.omanisation_population(p_entity uuid, p_on date default current_date)
returns table (employee_id uuid, is_omani boolean, department_id uuid, job_title_id uuid, profession_code text)
language sql stable security definer set search_path = '' as $$
  select e.id, e.nationality = 'OM', a.department_id, a.job_title_id, j.profession_code
  from hr.employees e
  join hr.employee_assignments a on a.employee_id = e.id
       and a.effective_from <= p_on and (a.effective_to is null or a.effective_to >= p_on)
  join hr.employee_categories c on c.id = a.category_id and c.counts_for_omanisation
  join hr.job_titles j on j.id = a.job_title_id
  where e.entity_id = p_entity
    and e.join_date <= p_on
    and (e.separation_date is null or e.separation_date > p_on)
$$;

-- ---------------------------------------------------------------------------
-- In-app notifications
-- ---------------------------------------------------------------------------
create table if not exists hr.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references hr.user_profiles(user_id),
  kind        text not null,
  priority    text not null default 'NORMAL' check (priority in ('NORMAL','HIGH')),
  title_en    text not null,
  title_ar    text not null,
  body_en     text,
  body_ar     text,
  link        text,
  ref_key     text not null,
  created_at  timestamptz not null default now(),
  read_at     timestamptz,
  unique (user_id, ref_key)
);
create index if not exists notifications_user on hr.notifications(user_id, read_at, created_at desc);
alter table hr.notifications enable row level security;

create or replace function hr.users_with_perm(p_perm text)
returns table (user_id uuid) language sql stable security definer set search_path = '' as $$
  select distinct ur.user_id
  from hr.user_roles ur
  join hr.user_profiles up on up.user_id = ur.user_id and up.is_active
  join hr.role_permissions rp on rp.role_code = ur.role_code and rp.perm_code = p_perm
  where ur.revoked_at is null
$$;

create or replace function hr.notify(p_user uuid, p_kind text, p_priority text, p_title_en text, p_title_ar text,
                                     p_body_en text, p_body_ar text, p_link text, p_ref text)
returns int language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if p_user is null then return 0; end if;
  insert into hr.notifications(user_id, kind, priority, title_en, title_ar, body_en, body_ar, link, ref_key)
  values (p_user, p_kind, p_priority, p_title_en, p_title_ar, p_body_en, p_body_ar, p_link, p_ref)
  on conflict (user_id, ref_key) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- One notification per item per alert threshold crossed; expired items escalate as HIGH.
create or replace function hr.generate_expiry_notifications(p_on date default current_date)
returns int language plpgsql security definer set search_path = '' as $$
declare
  r record; v_threshold int; v_ref text; v_priority text; v_total int := 0;
  v_emp record; v_mgr_user uuid; v_self_user uuid; u record;
  v_title_en text; v_title_ar text; v_body_en text; v_body_ar text;
begin
  for r in select * from hr.expiry_items(p_on) loop
    if r.days_left < 0 then
      v_threshold := -1;
    else
      select min(t) into v_threshold from unnest(r.alert_days) t where r.days_left <= t;
    end if;
    continue when v_threshold is null;

    select e.id, e.employee_no, e.full_name_en, coalesce(e.full_name_ar, e.full_name_en) as full_name_ar
      into v_emp from hr.employees e where e.id = r.employee_id;
    select up.user_id into v_self_user from hr.user_profiles up where up.employee_id = r.employee_id and up.is_active;
    select up.user_id into v_mgr_user
      from hr.employee_assignments a join hr.user_profiles up on up.employee_id = a.manager_id and up.is_active
     where a.employee_id = r.employee_id and a.effective_from <= p_on
       and (a.effective_to is null or a.effective_to >= p_on)
     limit 1;

    if v_threshold = -1 then
      v_ref := 'EXPIRED:' || r.ref_id; v_priority := 'HIGH';
      v_title_en := r.name_en || ' expired — ' || v_emp.full_name_en;
      v_title_ar := 'انتهت صلاحية ' || r.name_ar || ' — ' || v_emp.full_name_ar;
      v_body_en := v_emp.employee_no || ': expired on ' || to_char(r.expiry_date, 'DD/MM/YYYY') || ' (' || abs(r.days_left) || ' days ago).';
      v_body_ar := v_emp.employee_no || ': انتهت في ' || to_char(r.expiry_date, 'DD/MM/YYYY') || ' (قبل ' || abs(r.days_left) || ' يوم).';
    else
      v_ref := 'EXP:' || r.ref_id || ':' || v_threshold; v_priority := 'NORMAL';
      v_title_en := r.name_en || ' expires in ' || r.days_left || ' days — ' || v_emp.full_name_en;
      v_title_ar := r.name_ar || ' تنتهي خلال ' || r.days_left || ' يوم — ' || v_emp.full_name_ar;
      v_body_en := v_emp.employee_no || ': expiry date ' || to_char(r.expiry_date, 'DD/MM/YYYY') || '.';
      v_body_ar := v_emp.employee_no || ': تاريخ الانتهاء ' || to_char(r.expiry_date, 'DD/MM/YYYY') || '.';
    end if;

    for u in
      select h.user_id from hr.users_with_perm('COMPLIANCE_READ') h
      where not r.is_sensitive or h.user_id in (select s.user_id from hr.users_with_perm('DOC_SENSITIVE') s)
    loop
      v_total := v_total + hr.notify(u.user_id, 'EXPIRY', v_priority, v_title_en, v_title_ar, v_body_en, v_body_ar,
                                     '/employees/' || r.employee_id || '?tab=documents', v_ref);
    end loop;
    if not r.is_sensitive then
      v_total := v_total + hr.notify(v_mgr_user, 'EXPIRY', v_priority, v_title_en, v_title_ar, v_body_en, v_body_ar,
                                     '/employees/' || r.employee_id || '?tab=documents', v_ref);
    end if;
    v_total := v_total + hr.notify(v_self_user, 'EXPIRY', v_priority, v_title_en, v_title_ar, v_body_en, v_body_ar,
                                   '/my', v_ref);
  end loop;
  return v_total;
end $$;

-- Daily scan at 03:00 UTC (07:00 Muscat) where pg_cron is available.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('hr-expiry-scan', '0 3 * * *', 'select hr.generate_expiry_notifications()');
  end if;
end $$;

select hr.attach_audit();
select hr.secure_api();
