-- AACT HRMS — 006 API: helpers, session, users & roles, settings, organisation masters

-- ---------------------------------------------------------------------------
-- JSON helpers
-- ---------------------------------------------------------------------------
create or replace function hr.jtext(p jsonb, k text)
returns text language sql immutable set search_path = '' as $$
  select nullif(btrim(p->>k), '')
$$;

create or replace function hr.jdate(p jsonb, k text)
returns date language plpgsql immutable set search_path = '' as $$
declare v text := nullif(btrim(p->>k), '');
begin
  if v is null then return null; end if;
  if v !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'INVALID_DATE: % must be a date (YYYY-MM-DD).', k;
  end if;
  return v::date;
exception when datetime_field_overflow or invalid_datetime_format then
  raise exception 'INVALID_DATE: % is not a valid date.', k;
end $$;

create or replace function hr.juuid(p jsonb, k text)
returns uuid language plpgsql immutable set search_path = '' as $$
declare v text := nullif(btrim(p->>k), '');
begin
  if v is null then return null; end if;
  if v !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'INVALID_ID: % is not a valid id.', k;
  end if;
  return v::uuid;
end $$;

create or replace function hr.jbool(p jsonb, k text, p_default boolean default false)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce((p->>k)::boolean, p_default)
$$;

create or replace function hr.jint(p jsonb, k text)
returns int language plpgsql immutable set search_path = '' as $$
declare v text := nullif(btrim(p->>k), '');
begin
  if v is null then return null; end if;
  if v !~ '^-?\d{1,9}$' then raise exception 'INVALID_NUMBER: % must be a whole number.', k; end if;
  return v::int;
end $$;

create or replace function hr.jmoney(p jsonb, k text)
returns numeric language plpgsql immutable set search_path = '' as $$
declare v text := nullif(btrim(p->>k), '');
begin
  if v is null then return null; end if;
  if v !~ '^\d{1,9}(\.\d{1,3})?$' then
    raise exception 'INVALID_AMOUNT: % must be a positive amount with at most 3 decimals.', k;
  end if;
  return v::numeric(12,3);
end $$;

create or replace function hr.user_label(p_user uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(display_name,''), email) from hr.user_profiles where user_id = p_user
$$;

create or replace function hr.check_email(p text, k text)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if p is not null and p !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'INVALID_EMAIL: % is not a valid e-mail address.', k;
  end if;
end $$;

create or replace function hr.check_phone(p text, k text)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if p is not null and p !~ '^\+?[0-9 ()-]{6,20}$' then
    raise exception 'INVALID_PHONE: % is not a valid phone number.', k;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Session
-- ---------------------------------------------------------------------------
create or replace function public.hr_me()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v uuid := auth.uid(); v_res jsonb;
begin
  if v is null then
    raise exception 'NOT_SIGNED_IN: Please sign in again.' using errcode = '42501';
  end if;
  insert into hr.user_profiles(user_id, email, display_name)
  select u.id, u.email, split_part(coalesce(u.email,''),'@',1) from auth.users u where u.id = v
  on conflict (user_id) do nothing;

  select jsonb_build_object(
    'user_id', up.user_id,
    'email', up.email,
    'display_name', up.display_name,
    'language', up.language,
    'is_active', up.is_active,
    'employee_id', up.employee_id,
    'employee_no', e.employee_no,
    'employee_name', e.full_name_en,
    'employee_name_ar', e.full_name_ar,
    'roles', coalesce((select jsonb_agg(ur.role_code order by r.sort)
                       from hr.user_roles ur join hr.roles r on r.code = ur.role_code
                       where ur.user_id = v and ur.revoked_at is null), '[]'::jsonb),
    'permissions', case when up.is_active then coalesce((
                       select jsonb_agg(distinct rp.perm_code)
                       from hr.user_roles ur join hr.role_permissions rp on rp.role_code = ur.role_code
                       where ur.user_id = v and ur.revoked_at is null), '[]'::jsonb) else '[]'::jsonb end,
    'is_manager', up.is_active and up.employee_id is not null
                  and exists (select 1 from hr.team_of(up.employee_id)),
    'admin_exists', exists (select 1 from hr.user_roles where role_code = 'SUPER_ADMIN' and revoked_at is null),
    'settings', (select jsonb_object_agg(key, value) from hr.settings),
    'entities', coalesce((select jsonb_agg(jsonb_build_object('id', le.id, 'code', le.code, 'name_en', le.name_en,
                                   'name_ar', le.name_ar) order by le.code)
                          from hr.legal_entities le where le.is_active), '[]'::jsonb),
    'unread_notifications', (select count(*) from hr.notifications n where n.user_id = v and n.read_at is null)
  ) into v_res
  from hr.user_profiles up
  left join hr.employees e on e.id = up.employee_id
  where up.user_id = v;
  return v_res;
end $$;

-- The very first signed-in user can make themselves super administrator, once.
create or replace function public.hr_claim_first_admin()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v uuid := auth.uid();
begin
  if v is null then raise exception 'NOT_SIGNED_IN: Please sign in again.' using errcode = '42501'; end if;
  lock table hr.user_roles in share row exclusive mode;
  if exists (select 1 from hr.user_roles where role_code = 'SUPER_ADMIN' and revoked_at is null) then
    raise exception 'ADMIN_EXISTS: An administrator already exists. Ask them to give you access.';
  end if;
  insert into hr.user_profiles(user_id, email)
  select u.id, u.email from auth.users u where u.id = v
  on conflict (user_id) do update set is_active = true;
  insert into hr.user_roles(user_id, role_code, granted_by) values (v, 'SUPER_ADMIN', v)
  on conflict (user_id, role_code) do update set revoked_at = null, revoked_by = null, granted_by = v, granted_at = now();
  return public.hr_me();
end $$;

create or replace function public.hr_set_my_profile(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v uuid := hr.require_user(); v_lang text := hr.jtext(p, 'language');
begin
  if v_lang is not null and v_lang not in ('en','ar') then
    raise exception 'INVALID: Language must be en or ar.';
  end if;
  update hr.user_profiles
     set language = coalesce(v_lang, language),
         display_name = coalesce(hr.jtext(p, 'display_name'), display_name)
   where user_id = v;
  return public.hr_me();
end $$;

-- ---------------------------------------------------------------------------
-- Users and roles
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_roles()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return jsonb_build_object(
    'roles', coalesce((select jsonb_agg(jsonb_build_object(
                'code', r.code, 'name_en', r.name_en, 'name_ar', r.name_ar, 'description', r.description,
                'permissions', coalesce((select jsonb_agg(rp.perm_code order by rp.perm_code)
                                         from hr.role_permissions rp where rp.role_code = r.code), '[]'::jsonb))
              order by r.sort) from hr.roles r), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(to_jsonb(p) order by p.module, p.code) from hr.permissions p), '[]'::jsonb));
end $$;

create or replace function public.hr_list_users()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('USERS_ADMIN');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'user_id', up.user_id, 'email', up.email, 'display_name', up.display_name,
      'is_active', up.is_active, 'language', up.language, 'created_at', up.created_at,
      'employee_id', up.employee_id, 'employee_no', e.employee_no, 'employee_name', e.full_name_en,
      'roles', coalesce((select jsonb_agg(ur.role_code order by ur.role_code) from hr.user_roles ur
                         where ur.user_id = up.user_id and ur.revoked_at is null), '[]'::jsonb))
      order by up.created_at)
    from hr.user_profiles up left join hr.employees e on e.id = up.employee_id), '[]'::jsonb);
end $$;

create or replace function public.hr_set_user_roles(p_user uuid, p_roles text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_me uuid; v_bad text; v_roles text[] := coalesce(p_roles, '{}');
begin
  perform hr.require_perm('USERS_ADMIN');
  v_me := auth.uid();
  if not exists (select 1 from hr.user_profiles where user_id = p_user) then
    raise exception 'NOT_FOUND: User not found.';
  end if;
  select r into v_bad from unnest(v_roles) r where not exists (select 1 from hr.roles where code = r) limit 1;
  if v_bad is not null then raise exception 'INVALID: Unknown role %.', v_bad; end if;
  if p_user = v_me and not ('SUPER_ADMIN' = any(v_roles))
     and exists (select 1 from hr.user_roles where user_id = v_me and role_code = 'SUPER_ADMIN' and revoked_at is null) then
    raise exception 'NOT_ALLOWED: You cannot remove your own administrator role.';
  end if;
  if not ('SUPER_ADMIN' = any(v_roles))
     and exists (select 1 from hr.user_roles where user_id = p_user and role_code = 'SUPER_ADMIN' and revoked_at is null)
     and not exists (select 1 from hr.user_roles where role_code = 'SUPER_ADMIN' and revoked_at is null and user_id <> p_user) then
    raise exception 'NOT_ALLOWED: At least one super administrator must remain.';
  end if;
  if 'SUPER_ADMIN' = any(v_roles) and not hr.has_perm('USERS_ADMIN') then
    raise exception 'NOT_ALLOWED';
  end if;

  update hr.user_roles set revoked_at = now(), revoked_by = v_me
   where user_id = p_user and revoked_at is null and not (role_code = any(v_roles));
  insert into hr.user_roles(user_id, role_code, granted_by)
  select p_user, r, v_me from unnest(v_roles) r
  on conflict (user_id, role_code) do update
    set revoked_at = null, revoked_by = null, granted_by = excluded.granted_by, granted_at = now()
    where hr.user_roles.revoked_at is not null;
  return public.hr_list_users();
end $$;

create or replace function public.hr_set_user_active(p_user uuid, p_active boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform hr.require_perm('USERS_ADMIN');
  if p_user = auth.uid() and not p_active then
    raise exception 'NOT_ALLOWED: You cannot deactivate your own account.';
  end if;
  if not p_active
     and exists (select 1 from hr.user_roles where user_id = p_user and role_code = 'SUPER_ADMIN' and revoked_at is null)
     and not exists (select 1 from hr.user_roles ur join hr.user_profiles up on up.user_id = ur.user_id and up.is_active
                     where ur.role_code = 'SUPER_ADMIN' and ur.revoked_at is null and ur.user_id <> p_user) then
    raise exception 'NOT_ALLOWED: At least one active super administrator must remain.';
  end if;
  update hr.user_profiles set is_active = p_active where user_id = p_user;
  if not found then raise exception 'NOT_FOUND: User not found.'; end if;
  return public.hr_list_users();
end $$;

create or replace function public.hr_link_user_employee(p_user uuid, p_employee uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_other text;
begin
  perform hr.require_perm('USERS_ADMIN');
  if p_employee is not null then
    if not exists (select 1 from hr.employees where id = p_employee) then
      raise exception 'NOT_FOUND: Employee not found.';
    end if;
    select coalesce(email, user_id::text) into v_other from hr.user_profiles
     where employee_id = p_employee and user_id <> p_user;
    if v_other is not null then
      raise exception 'DUPLICATE: This employee is already linked to %.', v_other;
    end if;
  end if;
  update hr.user_profiles set employee_id = p_employee where user_id = p_user;
  if not found then raise exception 'NOT_FOUND: User not found.'; end if;
  return public.hr_list_users();
end $$;

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
create or replace function public.hr_save_setting(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform hr.require_perm('USERS_ADMIN');
  if p_key not in ('employee_no_prefix','employee_no_digits','default_language','date_format','expiry_horizon_days') then
    raise exception 'INVALID: % cannot be changed here.', p_key;
  end if;
  if p_key = 'employee_no_digits' and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::int not between 3 and 8) then
    raise exception 'INVALID: Employee number digits must be between 3 and 8.';
  end if;
  if p_key = 'employee_no_prefix' and (jsonb_typeof(p_value) <> 'string' or (p_value #>> '{}') !~ '^[A-Z0-9-]{0,10}$') then
    raise exception 'INVALID: Prefix may contain capital letters, digits and hyphens (up to 10).';
  end if;
  if p_key = 'default_language' and (p_value #>> '{}') not in ('en','ar') then
    raise exception 'INVALID: Language must be en or ar.';
  end if;
  if p_key = 'expiry_horizon_days' and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::int not between 30 and 365) then
    raise exception 'INVALID: Horizon must be between 30 and 365 days.';
  end if;
  insert into hr.settings(key, value, updated_by) values (p_key, p_value, auth.uid())
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  return (select jsonb_object_agg(key, value) from hr.settings);
end $$;

-- ---------------------------------------------------------------------------
-- Organisation masters (generic, column-whitelisted)
-- ---------------------------------------------------------------------------
create or replace function hr.master_def(p_kind text, out tbl text, out cols text[], out keycol text, out has_entity boolean)
language plpgsql immutable set search_path = '' as $$
begin
  keycol := 'id'; has_entity := true;
  case p_kind
    when 'entity' then tbl := 'legal_entities'; has_entity := false;
      cols := array['code','name_en','name_ar','cr_number','mol_establishment_no','sector','country','currency','address','is_active'];
    when 'location' then tbl := 'locations';
      cols := array['entity_id','code','name_en','name_ar','location_type','address','city','governorate','is_active'];
    when 'cost_centre' then tbl := 'cost_centres';
      cols := array['entity_id','code','name_en','name_ar','gl_code','is_active'];
    when 'department' then tbl := 'departments';
      cols := array['entity_id','code','name_en','name_ar','parent_id','cost_centre_id','head_employee_id','is_active'];
    when 'grade' then tbl := 'grades';
      cols := array['entity_id','code','name_en','name_ar','level','min_basic','max_basic','is_active'];
    when 'job_title' then tbl := 'job_titles';
      cols := array['entity_id','code','name_en','name_ar','profession_code','omani_only','omani_only_source',
                    'omani_only_verified','description','required_qualifications','is_active'];
    when 'category' then tbl := 'employee_categories';
      cols := array['entity_id','code','name_en','name_ar','pay_basis','counts_for_omanisation','is_active'];
    when 'document_type' then tbl := 'document_types'; keycol := 'code'; has_entity := false;
      cols := array['code','name_en','name_ar','category','has_number','has_expiry','alert_days','applies_to',
                    'is_mandatory','allow_multiple','is_sensitive','rule_basis','rule_reference','sort','is_active'];
    else raise exception 'INVALID: Unknown master %.', p_kind;
  end case;
end $$;

create or replace function public.hr_list_master(p_kind text, p_entity uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare d record; v jsonb; v_order text;
begin
  perform hr.require_user();
  perform hr.require_perm('ORG_READ');
  select * into d from hr.master_def(p_kind);
  v_order := case when p_kind = 'document_type' then 't.sort, t.code' when p_kind = 'grade' then 't.level, t.code' else 't.code' end;
  if d.has_entity and p_entity is not null then
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by %s), ''[]''::jsonb) from hr.%I t where t.entity_id = $1',
                   v_order, d.tbl) into v using p_entity;
  else
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by %s), ''[]''::jsonb) from hr.%I t', v_order, d.tbl) into v;
  end if;
  return v;
end $$;

create or replace function public.hr_save_master(p_kind text, p_row jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  d record; v_keys text[]; v_key text; v_exists boolean; v_res jsonb; v_old jsonb;
  v_collist text; v_cycle boolean; v_entity uuid;
begin
  perform hr.require_perm('ORG_WRITE');
  select * into d from hr.master_def(p_kind);
  v_key := p_row->>d.keycol;
  if d.keycol = 'id' and v_key is not null then perform hr.juuid(p_row, 'id'); end if;

  if v_key is not null then
    execute format('select to_jsonb(t) from hr.%I t where t.%I::text = $1', d.tbl, d.keycol) into v_old using v_key;
  end if;
  v_exists := v_old is not null;
  if d.keycol = 'id' and v_key is not null and not v_exists then
    raise exception 'NOT_FOUND: Record not found.';
  end if;

  -- Omani-only flags are legal rules: they need the approval permission and a source.
  if p_kind = 'job_title' and (p_row ? 'omani_only' or p_row ? 'omani_only_source' or p_row ? 'omani_only_verified') then
    if coalesce((p_row->>'omani_only')::boolean, false) is distinct from coalesce((v_old->>'omani_only')::boolean, false)
       or hr.jtext(p_row,'omani_only_source') is distinct from hr.jtext(v_old,'omani_only_source')
       or coalesce((p_row->>'omani_only_verified')::boolean, false) is distinct from coalesce((v_old->>'omani_only_verified')::boolean, false) then
      perform hr.require_perm('RULES_APPROVE');
    end if;
  end if;
  if p_kind = 'document_type' and v_key is null then
    raise exception 'INVALID: A document type needs a code.';
  end if;

  if v_exists then
    select array_agg(k) into v_keys from jsonb_object_keys(p_row) k
     where k = any(d.cols) and k not in ('entity_id', 'code') ;
    -- codes of organisation masters may be corrected; document type codes are keys and may not
    if p_kind <> 'document_type' and p_row ? 'code' then v_keys := array_append(v_keys, 'code'); end if;
    if v_keys is null then return v_old; end if;
    select string_agg(format('%I', k), ',') into v_collist from unnest(v_keys) k;
    execute format('update hr.%I t set (%s) = (select %s from jsonb_populate_record(null::hr.%I, $1)) where t.%I::text = $2 returning to_jsonb(t)',
                   d.tbl, v_collist, v_collist, d.tbl, d.keycol)
      into v_res using p_row, v_key;
  else
    if d.has_entity and hr.jtext(p_row, 'entity_id') is null then
      raise exception 'INVALID: Choose the company first.';
    end if;
    select array_agg(k) into v_keys from jsonb_object_keys(p_row) k where k = any(d.cols);
    select string_agg(format('%I', k), ',') into v_collist from unnest(v_keys) k;
    execute format('insert into hr.%I as t (%s) select %s from jsonb_populate_record(null::hr.%I, $1) returning to_jsonb(t)',
                   d.tbl, v_collist, v_collist, d.tbl)
      into v_res using p_row;
  end if;

  -- cross-checks
  if d.has_entity then
    v_entity := (v_res->>'entity_id')::uuid;
    if p_kind = 'department' then
      if (v_res->>'parent_id') is not null and not exists (
           select 1 from hr.departments where id = (v_res->>'parent_id')::uuid and entity_id = v_entity) then
        raise exception 'INVALID: The parent department belongs to another company.';
      end if;
      if (v_res->>'cost_centre_id') is not null and not exists (
           select 1 from hr.cost_centres where id = (v_res->>'cost_centre_id')::uuid and entity_id = v_entity) then
        raise exception 'INVALID: The cost centre belongs to another company.';
      end if;
      with recursive up(id, depth) as (
        select parent_id, 1 from hr.departments where id = (v_res->>'id')::uuid
        union all
        select dd.parent_id, up.depth + 1 from hr.departments dd join up on dd.id = up.id
        where up.id is not null and up.depth < 50)
      select exists (select 1 from up where id = (v_res->>'id')::uuid) into v_cycle;
      if v_cycle then raise exception 'INVALID: A department cannot sit under itself.'; end if;
    end if;
  end if;
  return v_res;
exception
  when unique_violation then
    raise exception 'DUPLICATE: A record with this code already exists.';
  when check_violation then
    raise exception 'INVALID: %', sqlerrm;
  when foreign_key_violation then
    raise exception 'INVALID: A linked record does not exist (%).', sqlerrm;
  when not_null_violation then
    raise exception 'REQUIRED: % is required.', (regexp_match(sqlerrm, 'column "([^"]+)"'))[1];
  when invalid_text_representation then
    raise exception 'INVALID: %', sqlerrm;
end $$;

create or replace function public.hr_list_countries()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(c) order by c.sort, c.name_en), '[]'::jsonb) from hr.countries c
$$;

create or replace function public.hr_list_pay_components()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(to_jsonb(c) order by c.sort) from hr.pay_components c where c.is_active), '[]'::jsonb);
end $$;

select hr.secure_api();
