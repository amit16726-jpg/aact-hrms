-- AACT HRMS — 001 core: schema, settings, roles & permissions, users, audit trail
-- All business tables live in schema "hr" (not exposed over the API).
-- The app talks only to public.hr_* RPC functions (SECURITY DEFINER, permission-checked).

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;

create schema if not exists hr;
revoke all on schema hr from public;
revoke all on schema hr from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Settings (key/value)
-- ---------------------------------------------------------------------------
create table if not exists hr.settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into hr.settings(key, value) values
  ('employee_no_prefix', '"AACT-"'),
  ('employee_no_digits', '5'),
  ('default_language',   '"en"'),
  ('currency',           '"OMR"'),
  ('currency_decimals',  '3'),
  ('date_format',        '"dd/MM/yyyy"'),
  ('expiry_horizon_days','90')
on conflict (key) do nothing;

create sequence if not exists hr.employee_no_seq start 1;

-- ---------------------------------------------------------------------------
-- Roles and permissions
-- ---------------------------------------------------------------------------
create table if not exists hr.roles (
  code      text primary key,
  name_en   text not null,
  name_ar   text not null,
  description text,
  sort      int not null default 0
);

create table if not exists hr.permissions (
  code        text primary key,
  module      text not null,
  description text not null
);

create table if not exists hr.role_permissions (
  role_code text not null references hr.roles(code),
  perm_code text not null references hr.permissions(code),
  primary key (role_code, perm_code)
);

insert into hr.roles(code, name_en, name_ar, description, sort) values
  ('SUPER_ADMIN', 'Super administrator', 'مدير النظام',        'Everything, including users and roles', 1),
  ('HR_MANAGER',  'HR manager',          'مدير الموارد البشرية', 'All HR data, approves salary, rules and exceptions', 2),
  ('HR_OFFICER',  'HR officer',          'موظف الموارد البشرية', 'Maintains employees and documents; proposes rules', 3),
  ('FINANCE',     'Finance',             'المالية',             'Reads salary and bank; approves bank changes', 4),
  ('AUDITOR',     'Auditor',             'المدقق',              'Read-only, including the audit trail', 5),
  ('MANAGER',     'Line manager',        'المدير المباشر',       'Own team only, limited fields', 6),
  ('EMPLOYEE',    'Employee',            'موظف',                'Own record only', 7)
on conflict (code) do nothing;

insert into hr.permissions(code, module, description) values
  ('ORG_READ',          'Organisation', 'View organisation masters'),
  ('ORG_WRITE',         'Organisation', 'Maintain organisation masters and document types'),
  ('EMP_READ',          'Employees',    'View all employee records'),
  ('EMP_WRITE',         'Employees',    'Create and change employee records, assignments, contracts'),
  ('EMP_SALARY_READ',   'Compensation', 'View salary and allowances'),
  ('EMP_SALARY_WRITE',  'Compensation', 'Propose salary revisions'),
  ('SALARY_APPROVE',    'Compensation', 'Approve salary revisions proposed by someone else'),
  ('EMP_BANK_READ',     'Bank',         'View full bank account details'),
  ('EMP_BANK_WRITE',    'Bank',         'Request bank account changes'),
  ('BANK_APPROVE',      'Bank',         'Approve bank account changes requested by someone else'),
  ('DOC_READ',          'Documents',    'View employee documents'),
  ('DOC_WRITE',         'Documents',    'Upload, replace, verify and cancel documents'),
  ('DOC_SENSITIVE',     'Documents',    'View medical and disciplinary documents'),
  ('COMPLIANCE_READ',   'Compliance',   'Expiry tracker, missing documents, Omanisation'),
  ('RULES_PROPOSE',     'Compliance',   'Propose Omanisation targets'),
  ('RULES_APPROVE',     'Compliance',   'Approve targets proposed by someone else; set Omani-only jobs'),
  ('EXCEPTION_APPROVE', 'Compliance',   'Record an approved exception for a non-Omani in an Omani-only job'),
  ('USERS_ADMIN',       'Administration','Manage users, roles and employee links'),
  ('AUDIT_READ',        'Administration','View the audit trail and access log')
on conflict (code) do nothing;

insert into hr.role_permissions(role_code, perm_code)
select 'SUPER_ADMIN', code from hr.permissions
on conflict do nothing;

insert into hr.role_permissions(role_code, perm_code)
select r, p from (values
  ('HR_MANAGER','ORG_READ'),('HR_MANAGER','ORG_WRITE'),('HR_MANAGER','EMP_READ'),('HR_MANAGER','EMP_WRITE'),
  ('HR_MANAGER','EMP_SALARY_READ'),('HR_MANAGER','EMP_SALARY_WRITE'),('HR_MANAGER','SALARY_APPROVE'),
  ('HR_MANAGER','EMP_BANK_READ'),('HR_MANAGER','EMP_BANK_WRITE'),
  ('HR_MANAGER','DOC_READ'),('HR_MANAGER','DOC_WRITE'),('HR_MANAGER','DOC_SENSITIVE'),
  ('HR_MANAGER','COMPLIANCE_READ'),('HR_MANAGER','RULES_PROPOSE'),('HR_MANAGER','RULES_APPROVE'),
  ('HR_MANAGER','EXCEPTION_APPROVE'),('HR_MANAGER','AUDIT_READ'),

  ('HR_OFFICER','ORG_READ'),('HR_OFFICER','EMP_READ'),('HR_OFFICER','EMP_WRITE'),
  ('HR_OFFICER','EMP_SALARY_WRITE'),('HR_OFFICER','EMP_BANK_WRITE'),
  ('HR_OFFICER','DOC_READ'),('HR_OFFICER','DOC_WRITE'),('HR_OFFICER','COMPLIANCE_READ'),('HR_OFFICER','RULES_PROPOSE'),

  ('FINANCE','ORG_READ'),('FINANCE','EMP_READ'),('FINANCE','EMP_SALARY_READ'),
  ('FINANCE','EMP_BANK_READ'),('FINANCE','BANK_APPROVE'),('FINANCE','COMPLIANCE_READ'),

  ('AUDITOR','ORG_READ'),('AUDITOR','EMP_READ'),('AUDITOR','EMP_SALARY_READ'),('AUDITOR','DOC_READ'),
  ('AUDITOR','COMPLIANCE_READ'),('AUDITOR','AUDIT_READ'),

  ('MANAGER','ORG_READ'),
  ('EMPLOYEE','ORG_READ')
) v(r, p)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------
create table if not exists hr.user_profiles (
  user_id      uuid primary key,
  email        text,
  display_name text,
  language     text not null default 'en' check (language in ('en','ar')),
  is_active    boolean not null default true,
  employee_id  uuid unique,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists hr.user_roles (
  user_id    uuid not null references hr.user_profiles(user_id),
  role_code  text not null references hr.roles(code),
  granted_by uuid,
  granted_at timestamptz not null default now(),
  revoked_by uuid,
  revoked_at timestamptz,
  primary key (user_id, role_code)
);

create or replace function hr.on_auth_user_created()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into hr.user_profiles(user_id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', split_part(coalesce(new.email,''), '@', 1)))
  on conflict (user_id) do update set email = excluded.email;
  return new;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'hr_on_auth_user_created') then
    create trigger hr_on_auth_user_created after insert on auth.users
      for each row execute function hr.on_auth_user_created();
  end if;
end $$;

-- backfill users that already exist
insert into hr.user_profiles(user_id, email, display_name)
select u.id, u.email, coalesce(u.raw_user_meta_data->>'full_name', split_part(coalesce(u.email,''), '@', 1))
from auth.users u
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------------
-- Permission helpers
-- ---------------------------------------------------------------------------
create or replace function hr.has_perm(p_perm text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from hr.user_roles ur
    join hr.user_profiles up on up.user_id = ur.user_id and up.is_active
    join hr.role_permissions rp on rp.role_code = ur.role_code
    where ur.user_id = auth.uid() and ur.revoked_at is null and rp.perm_code = p_perm)
$$;

create or replace function hr.require_perm(p_perm text)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'NOT_SIGNED_IN: Please sign in again.' using errcode = '42501';
  end if;
  if not hr.has_perm(p_perm) then
    raise exception 'NOT_ALLOWED: You do not have the % permission.', p_perm using errcode = '42501';
  end if;
end $$;

create or replace function hr.require_user()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v uuid := auth.uid();
begin
  if v is null then
    raise exception 'NOT_SIGNED_IN: Please sign in again.' using errcode = '42501';
  end if;
  if not exists (select 1 from hr.user_profiles where user_id = v and is_active) then
    raise exception 'NOT_ALLOWED: Your account is not active.' using errcode = '42501';
  end if;
  return v;
end $$;

create or replace function hr.my_employee_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select employee_id from hr.user_profiles where user_id = auth.uid() and is_active
$$;

-- true only when p_employee is the signed-in user's own employee record (never null)
create or replace function hr.is_me(p_employee uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(p_employee = hr.my_employee_id(), false)
$$;

-- ---------------------------------------------------------------------------
-- Audit trail and sensitive-data access log
-- ---------------------------------------------------------------------------
create table if not exists hr.audit_log (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  user_id     uuid,
  table_name  text not null,
  row_key     text,
  employee_id uuid,
  action      text not null check (action in ('INSERT','UPDATE','DELETE')),
  old_data    jsonb,
  new_data    jsonb
);
create index if not exists audit_log_table_row on hr.audit_log(table_name, row_key);
create index if not exists audit_log_employee on hr.audit_log(employee_id, at desc);
create index if not exists audit_log_at on hr.audit_log(at desc);

create table if not exists hr.access_log (
  id          bigserial primary key,
  at          timestamptz not null default now(),
  user_id     uuid,
  employee_id uuid,
  data_kind   text not null,
  detail      text
);
create index if not exists access_log_employee on hr.access_log(employee_id, at desc);

create or replace function hr.mask_tail(p text)
returns text language sql immutable set search_path = '' as $$
  select case when p is null then null
              when length(p) <= 4 then repeat('•', length(p))
              else repeat('•', length(p) - 4) || right(p, 4) end
$$;

create or replace function hr.audit_mask(p_table text, p jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select case when p is null then null
              when p_table = 'employee_bank_accounts' then
                p || jsonb_build_object('account_number', hr.mask_tail(p->>'account_number'),
                                        'iban',           hr.mask_tail(p->>'iban'))
              else p end
$$;

create or replace function hr.audit_trigger()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_old jsonb; v_new jsonb; v_key text; v_emp text;
begin
  if tg_op in ('UPDATE','DELETE') then v_old := hr.audit_mask(tg_table_name, to_jsonb(old)); end if;
  if tg_op in ('INSERT','UPDATE') then v_new := hr.audit_mask(tg_table_name, to_jsonb(new)); end if;
  if tg_op = 'UPDATE' and (v_old - 'updated_at') = (v_new - 'updated_at') then
    return new;
  end if;
  v_key := coalesce(v_new->>'id', v_old->>'id', v_new->>'code', v_old->>'code', v_new->>'key', v_old->>'key',
                    v_new->>'user_id', v_old->>'user_id');
  if tg_table_name = 'employees' then
    v_emp := coalesce(v_new->>'id', v_old->>'id');
  else
    v_emp := coalesce(v_new->>'employee_id', v_old->>'employee_id');
  end if;
  insert into hr.audit_log(user_id, table_name, row_key, employee_id, action, old_data, new_data)
  values (auth.uid(), tg_table_name, v_key, nullif(v_emp,'')::uuid, tg_op, v_old, v_new);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

create or replace function hr.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Attach audit (and updated_at where the column exists) to every hr table except the logs.
create or replace function hr.attach_audit()
returns void language plpgsql set search_path = '' as $$
declare r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'hr' and c.relkind = 'r'
      and c.relname not in ('audit_log','access_log','notifications')
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
  -- logs: RLS on, no policies (reachable only through RPCs)
  alter table hr.audit_log enable row level security;
  alter table hr.access_log enable row level security;
end $$;

-- Lock down: public.hr_* RPCs callable by signed-in users only; hr.* functions not callable directly.
create or replace function hr.secure_api()
returns void language plpgsql set search_path = '' as $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'hr\_%'
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'hr'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  revoke all on all tables in schema hr from public, anon, authenticated;
  revoke all on all sequences in schema hr from public, anon, authenticated;
end $$;

select hr.attach_audit();
select hr.secure_api();
