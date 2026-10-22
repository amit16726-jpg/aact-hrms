-- =============================================================================
-- 1.13.0 — security hardening from the audit
--  * two-step sign-in (TOTP authenticator app): once a person has set it up, every API call needs a session that passed
--    the second step (aal2); optionally required for chosen roles (Settings → Security)
--  * automatic sign-out after a period without activity (Settings → Security, default 30 minutes)
-- =============================================================================

insert into hr.settings(key, value) values
  ('session_idle_minutes', '30'),
  ('mfa', '{"required": false, "roles": ["SUPER_ADMIN", "HR_MANAGER", "FINANCE", "MG_PAYROLL"]}')
on conflict (key) do nothing;

-- OK = may use the system; CHALLENGE = has two-step sign-in but this session did not pass it; SETUP = must set it up first.
create or replace function hr.mfa_state()
returns text language plpgsql stable security definer set search_path = '' as $$
declare v uuid := auth.uid(); v_has boolean; m jsonb;
begin
  if v is null then return 'OK'; end if;
  select exists (select 1 from auth.mfa_factors f where f.user_id = v and f.status::text = 'verified') into v_has;
  if v_has then
    return case when coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then 'OK' else 'CHALLENGE' end;
  end if;
  select value into m from hr.settings where key = 'mfa';
  if coalesce((m ->> 'required')::boolean, false) and exists (
       select 1 from hr.user_roles ur where ur.user_id = v and ur.revoked_at is null
          and ur.role_code in (select jsonb_array_elements_text(coalesce(m -> 'roles', '[]'::jsonb)))) then
    return 'SETUP';
  end if;
  return 'OK';
end $$;

create or replace function hr.require_mfa()
returns void language plpgsql stable security definer set search_path = '' as $$
declare s text := hr.mfa_state();
begin
  if s = 'CHALLENGE' then raise exception 'MFA_REQUIRED: Enter the code from your authenticator app to continue.' using errcode = '42501'; end if;
  if s = 'SETUP' then raise exception 'MFA_SETUP_REQUIRED: Set up two-step sign-in to continue.' using errcode = '42501'; end if;
end $$;

create or replace function hr.has_perm(p_perm text)
returns boolean language sql stable security definer set search_path = '' as $$
  select hr.mfa_state() = 'OK' and exists (
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
  perform hr.require_mfa();
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
  perform hr.require_mfa();
  return v;
end $$;

create or replace function public.hr_me()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v uuid := auth.uid(); v_res jsonb;
begin
  if v is null then
    raise exception 'NOT_SIGNED_IN: Please sign in again.' using errcode = '42501';
  end if;
  -- a sign-in left in the browser after its account was removed (e.g. the test database was reset)
  if not exists (select 1 from auth.users where id = v) then
    raise exception 'NOT_SIGNED_IN: This sign-in has ended. Please sign in again.' using errcode = '42501';
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
    'unread_notifications', (select count(*) from hr.notifications n where n.user_id = v and n.read_at is null),
    'mfa_state', hr.mfa_state(),
    'mfa_enrolled', exists (select 1 from auth.mfa_factors f where f.user_id = v and f.status::text = 'verified')
  ) into v_res
  from hr.user_profiles up
  left join hr.employees e on e.id = up.employee_id
  where up.user_id = v;
  return v_res;
end $function$;

create or replace function public.hr_save_setting(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_role text;
begin
  perform hr.require_perm('USERS_ADMIN');
  if p_key not in ('employee_no_prefix','employee_no_digits','default_language','date_format','expiry_horizon_days','leave_opening_date',
                   'session_idle_minutes','mfa') then
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
  if p_key = 'leave_opening_date' and not (jsonb_typeof(p_value) = 'null'
       or (jsonb_typeof(p_value) = 'string' and (p_value #>> '{}') ~ '^\d{4}-\d{2}-01$')) then
    raise exception 'INVALID: The leave opening date must be the first day of a month (YYYY-MM-01).';
  end if;
  if p_key = 'leave_opening_date' and exists (select 1 from hr.leave_ledger where kind = 'ACCRUAL') then
    raise exception 'INVALID: Accruals already exist; the opening date can no longer be changed.';
  end if;
  if p_key = 'session_idle_minutes' and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::int not between 5 and 480) then
    raise exception 'INVALID: Automatic sign-out must be between 5 and 480 minutes.';
  end if;
  if p_key = 'mfa' then
    if jsonb_typeof(p_value) <> 'object' or jsonb_typeof(p_value -> 'required') <> 'boolean' or jsonb_typeof(coalesce(p_value -> 'roles', '[]'::jsonb)) <> 'array' then
      raise exception 'INVALID: Two-step sign-in settings are not valid.';
    end if;
    for v_role in select jsonb_array_elements_text(coalesce(p_value -> 'roles', '[]'::jsonb)) loop
      if not exists (select 1 from hr.roles where code = v_role) then raise exception 'INVALID: Unknown role %.', v_role; end if;
    end loop;
    if (p_value ->> 'required')::boolean
       and not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status::text = 'verified')
       and exists (select 1 from hr.user_roles ur where ur.user_id = auth.uid() and ur.revoked_at is null
                    and ur.role_code in (select jsonb_array_elements_text(coalesce(p_value -> 'roles', '[]'::jsonb)))) then
      raise exception 'INVALID: Set up two-step sign-in for yourself first (Settings → Security), so you are not locked out.';
    end if;
  end if;
  insert into hr.settings(key, value, updated_by) values (p_key, p_value, auth.uid())
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  return (select jsonb_object_agg(key, value) from hr.settings);
end $$;

select hr.attach_audit();
select hr.secure_api();
