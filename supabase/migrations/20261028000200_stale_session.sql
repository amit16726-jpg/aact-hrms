-- =============================================================================
-- 1.10.1 — a browser still signed in to an account that no longer exists (after the test reset)
-- is signed out automatically instead of showing an empty page.
-- =============================================================================

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
    'unread_notifications', (select count(*) from hr.notifications n where n.user_id = v and n.read_at is null)
  ) into v_res
  from hr.user_profiles up
  left join hr.employees e on e.id = up.employee_id
  where up.user_id = v;
  return v_res;
end $function$;

select hr.attach_audit();
select hr.secure_api();
