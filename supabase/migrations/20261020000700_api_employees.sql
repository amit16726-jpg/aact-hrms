-- AACT HRMS — 007 API: employees, assignments, status changes, contracts, emergency contacts

create or replace function hr.assignment_json(a hr.employee_assignments)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when a.id is null then null else
    to_jsonb(a) || jsonb_build_object(
      'department_en', d.name_en, 'department_ar', d.name_ar, 'department_code', d.code,
      'job_title_en', j.name_en, 'job_title_ar', j.name_ar, 'job_title_code', j.code,
      'profession_code', j.profession_code, 'omani_only', j.omani_only,
      'grade_en', g.name_en, 'grade_ar', g.name_ar, 'grade_code', g.code,
      'category_en', c.name_en, 'category_ar', c.name_ar, 'pay_basis', c.pay_basis,
      'location_en', l.name_en, 'location_ar', l.name_ar,
      'cost_centre_en', cc.name_en, 'cost_centre_ar', cc.name_ar, 'cost_centre_code', cc.code,
      'manager_name_en', m.full_name_en, 'manager_name_ar', m.full_name_ar, 'manager_no', m.employee_no,
      'created_by_name', hr.user_label(a.created_by)) end
  from (select 1) x
  left join hr.departments d on d.id = a.department_id
  left join hr.job_titles j on j.id = a.job_title_id
  left join hr.grades g on g.id = a.grade_id
  left join hr.employee_categories c on c.id = a.category_id
  left join hr.locations l on l.id = a.location_id
  left join hr.cost_centres cc on cc.id = a.cost_centre_id
  left join hr.employees m on m.id = a.manager_id
$$;

create or replace function hr.add_event(p_employee uuid, p_type text, p_date date, p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into hr.employee_events(employee_id, event_type, event_date, details, created_by)
  values (p_employee, p_type, p_date, coalesce(p_details, '{}'::jsonb), auth.uid())
$$;

-- Validate an assignment payload for an employee; returns the omanisation exception id when one was recorded.
create or replace function hr.validate_assignment(p_employee uuid, p_entity uuid, p_nationality text, a jsonb,
                                                  p_exception_reason text, p_effective date)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_job hr.job_titles; v_exc uuid; v_mgr uuid := hr.juuid(a, 'manager_id');
begin
  if hr.juuid(a,'department_id') is null then raise exception 'REQUIRED: Department is required.'; end if;
  if hr.juuid(a,'job_title_id') is null then raise exception 'REQUIRED: Job title is required.'; end if;
  if hr.juuid(a,'category_id') is null then raise exception 'REQUIRED: Employee category is required.'; end if;

  if not exists (select 1 from hr.departments where id = hr.juuid(a,'department_id') and entity_id = p_entity and is_active) then
    raise exception 'INVALID: Department is not an active department of this company.';
  end if;
  select * into v_job from hr.job_titles where id = hr.juuid(a,'job_title_id') and entity_id = p_entity and is_active;
  if v_job.id is null then raise exception 'INVALID: Job title is not an active job title of this company.'; end if;
  if not exists (select 1 from hr.employee_categories where id = hr.juuid(a,'category_id') and entity_id = p_entity and is_active) then
    raise exception 'INVALID: Category is not an active category of this company.';
  end if;
  if hr.juuid(a,'grade_id') is not null and not exists (
       select 1 from hr.grades where id = hr.juuid(a,'grade_id') and entity_id = p_entity and is_active) then
    raise exception 'INVALID: Grade is not an active grade of this company.';
  end if;
  if hr.juuid(a,'location_id') is not null and not exists (
       select 1 from hr.locations where id = hr.juuid(a,'location_id') and entity_id = p_entity and is_active) then
    raise exception 'INVALID: Location is not an active location of this company.';
  end if;
  if hr.juuid(a,'cost_centre_id') is not null and not exists (
       select 1 from hr.cost_centres where id = hr.juuid(a,'cost_centre_id') and entity_id = p_entity and is_active) then
    raise exception 'INVALID: Cost centre is not an active cost centre of this company.';
  end if;
  if v_mgr is not null then
    if v_mgr = p_employee then raise exception 'INVALID: An employee cannot report to himself.'; end if;
    if not exists (select 1 from hr.employees where id = v_mgr and status <> 'SEPARATED') then
      raise exception 'INVALID: The manager must be a current employee.';
    end if;
    if p_employee is not null and exists (select 1 from hr.team_of(p_employee) t where t.employee_id = v_mgr) then
      raise exception 'INVALID: The chosen manager already reports to this employee.';
    end if;
  end if;
  if coalesce(a->>'employment_type','FULL_TIME') not in ('FULL_TIME','PART_TIME','TEMPORARY','TRAINEE') then
    raise exception 'INVALID: Unknown employment type.';
  end if;

  if v_job.omani_only and p_nationality <> 'OM' then
    if p_exception_reason is null or length(btrim(p_exception_reason)) < 10 then
      raise exception 'OMANI_ONLY: % is an Omani-only job (%). A non-Omani can be placed only with an approved exception and a reason of at least 10 characters.',
        v_job.name_en, v_job.omani_only_source;
    end if;
    perform hr.require_perm('EXCEPTION_APPROVE');
    if p_employee is not null then
      insert into hr.omanisation_exceptions(employee_id, job_title_id, reason, approved_by)
      values (p_employee, v_job.id, btrim(p_exception_reason), auth.uid())
      returning id into v_exc;
      perform hr.add_event(p_employee, 'OMANISATION_EXCEPTION', p_effective,
                           jsonb_build_object('job_title', v_job.name_en, 'reason', btrim(p_exception_reason)));
    end if;
  end if;
  return v_exc;
end $$;

-- ---------------------------------------------------------------------------
-- List and read
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_employees(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_all boolean; v_me uuid; v_sort text; v_dir text; v_res jsonb;
  v_limit int := least(greatest(coalesce(hr.jint(p,'limit'), 50), 1), 500);
  v_offset int := greatest(coalesce(hr.jint(p,'offset'), 0), 0);
  v_search text := lower(hr.jtext(p,'search'));
  v_status text := coalesce(hr.jtext(p,'status'), 'CURRENT');
  v_nat text := hr.jtext(p,'nationality');
begin
  perform hr.require_user();
  v_all := hr.has_perm('EMP_READ');
  v_me := hr.my_employee_id();
  if not v_all and v_me is null then
    return jsonb_build_object('total', 0, 'rows', '[]'::jsonb);
  end if;
  v_sort := case hr.jtext(p,'sort')
              when 'name' then 'lower(b.full_name_en)'
              when 'join_date' then 'b.join_date'
              when 'department' then 'lower(b.department_en)'
              when 'status' then 'b.status'
              else 'b.employee_no' end;
  v_dir := case when lower(coalesce(hr.jtext(p,'dir'),'asc')) = 'desc' then 'desc' else 'asc' end;

  execute format($q$
    with base as (
      select e.id, e.employee_no, e.full_name_en, e.full_name_ar, e.nationality, e.status, e.join_date,
             e.mobile, e.work_email, e.photo_path, e.entity_id, e.gender, e.probation_end_date,
             a.department_id, a.job_title_id, a.location_id, a.manager_id,
             d.name_en as department_en, d.name_ar as department_ar,
             j.name_en as job_title_en, j.name_ar as job_title_ar,
             l.name_en as location_en, l.name_ar as location_ar,
             m.full_name_en as manager_en, m.full_name_ar as manager_ar,
             c.nationality_en, c.nationality_ar
      from hr.employees e
      left join lateral (
        select * from hr.employee_assignments x
        where x.employee_id = e.id and x.effective_from <= current_date
        order by x.effective_from desc limit 1) a on true
      left join hr.departments d on d.id = a.department_id
      left join hr.job_titles j on j.id = a.job_title_id
      left join hr.locations l on l.id = a.location_id
      left join hr.employees m on m.id = a.manager_id
      left join hr.countries c on c.code = e.nationality
      where ($1 or e.id = $2 or e.id in (select t.employee_id from hr.team_of($2) t))
        and ($3 is null or lower(e.employee_no) like '%%' || $3 || '%%'
                        or lower(e.full_name_en) like '%%' || $3 || '%%'
                        or coalesce(e.full_name_ar,'') like '%%' || $3 || '%%'
                        or ($1 and lower(coalesce(e.civil_number,'')) like '%%' || $3 || '%%')
                        or coalesce(e.mobile,'') like '%%' || $3 || '%%')
        and ($4 = 'ALL' or ($4 = 'CURRENT' and e.status <> 'SEPARATED') or e.status = $4)
        and ($5::uuid is null or a.department_id = $5::uuid)
        and ($6::uuid is null or e.entity_id = $6::uuid)
        and ($7 is null or ($7 = 'OMANI' and e.nationality = 'OM') or ($7 = 'EXPAT' and e.nationality <> 'OM')
                        or e.nationality = $7)
        and ($8::uuid is null or a.job_title_id = $8::uuid)
        and ($9::uuid is null or a.location_id = $9::uuid)
    )
    select jsonb_build_object(
      'total', (select count(*) from base),
      'rows', coalesce((select jsonb_agg(to_jsonb(r)) from (
                select b.*, (b.nationality = 'OM') as is_omani,
                       case when $1 then 'FULL' when b.id = $2 then 'SELF' else 'TEAM' end as access
                from base b order by %s %s nulls last, b.employee_no limit $10 offset $11) r), '[]'::jsonb))
  $q$, v_sort, v_dir)
  into v_res
  using v_all, v_me, v_search, v_status, hr.juuid(p,'department_id'), hr.juuid(p,'entity_id'), v_nat,
        hr.juuid(p,'job_title_id'), hr.juuid(p,'location_id'), v_limit, v_offset;
  return v_res;
end $$;

create or replace function public.hr_employee_lookup(p_search text default null, p_limit int default 20)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_s text := lower(nullif(btrim(p_search),''));
begin
  perform hr.require_user();
  if not (hr.has_perm('EMP_READ') or hr.has_perm('EMP_WRITE') or hr.has_perm('USERS_ADMIN') or hr.has_perm('ORG_WRITE')) then
    raise exception 'NOT_ALLOWED: You cannot search employees.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'employee_no', e.employee_no,
                       'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar, 'status', e.status,
                       'entity_id', e.entity_id))
    from (select * from hr.employees e
          where e.status <> 'SEPARATED'
            and (v_s is null or lower(e.employee_no) like '%' || v_s || '%' or lower(e.full_name_en) like '%' || v_s || '%'
                 or coalesce(e.full_name_ar,'') like '%' || v_s || '%')
          order by e.employee_no limit least(greatest(coalesce(p_limit,20),1),100)) e), '[]'::jsonb);
end $$;

create or replace function public.hr_get_employee(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_access text; e hr.employees; v_emp jsonb; v_cur hr.employee_assignments; v_self boolean;
begin
  v_access := hr.require_employee_access(p_id);
  v_self := hr.is_me(p_id);
  select * into e from hr.employees where id = p_id;
  v_cur := hr.current_assignment(p_id);
  if v_cur.id is null then
    select * into v_cur from hr.employee_assignments
     where employee_id = p_id and effective_from <= current_date order by effective_from desc limit 1;
  end if;

  if v_access = 'TEAM' then
    v_emp := jsonb_build_object('id', e.id, 'entity_id', e.entity_id, 'employee_no', e.employee_no,
               'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar, 'preferred_name', e.preferred_name,
               'nationality', e.nationality, 'gender', e.gender, 'work_email', e.work_email, 'mobile', e.mobile,
               'photo_path', e.photo_path, 'join_date', e.join_date, 'status', e.status,
               'probation_end_date', e.probation_end_date, 'confirmation_date', e.confirmation_date,
               'last_working_date', e.last_working_date);
  else
    v_emp := to_jsonb(e);
  end if;
  v_emp := v_emp || jsonb_build_object(
    'nationality_en', (select nationality_en from hr.countries where code = e.nationality),
    'nationality_ar', (select nationality_ar from hr.countries where code = e.nationality),
    'entity_en', (select name_en from hr.legal_entities where id = e.entity_id),
    'entity_ar', (select name_ar from hr.legal_entities where id = e.entity_id),
    'is_omani', e.nationality = 'OM');

  return jsonb_build_object(
    'employee', v_emp,
    'access', v_access,
    'current_assignment', hr.assignment_json(v_cur),
    'assignments', case when v_access = 'TEAM' then '[]'::jsonb else coalesce((
        select jsonb_agg(hr.assignment_json(a) order by a.effective_from desc)
        from hr.employee_assignments a where a.employee_id = p_id), '[]'::jsonb) end,
    'contracts', case when v_access = 'TEAM' then '[]'::jsonb else coalesce((
        select jsonb_agg(to_jsonb(c) || jsonb_build_object('created_by_name', hr.user_label(c.created_by))
                         order by c.version desc)
        from hr.employee_contracts c where c.employee_id = p_id), '[]'::jsonb) end,
    'emergency_contacts', case when v_access = 'TEAM' then '[]'::jsonb else coalesce((
        select jsonb_agg(to_jsonb(x) order by x.is_next_of_kin desc, x.created_at)
        from hr.emergency_contacts x where x.employee_id = p_id and x.is_active), '[]'::jsonb) end,
    'events', case when v_access = 'TEAM' then '[]'::jsonb else coalesce((
        select jsonb_agg(to_jsonb(v) || jsonb_build_object('created_by_name', hr.user_label(v.created_by))
                         order by v.event_date desc, v.created_at desc)
        from hr.employee_events v where v.employee_id = p_id), '[]'::jsonb) end,
    'omanisation_exceptions', case when v_access = 'FULL' then coalesce((
        select jsonb_agg(to_jsonb(x) || jsonb_build_object('job_title_en', j.name_en, 'job_title_ar', j.name_ar,
                         'approved_by_name', hr.user_label(x.approved_by)) order by x.approved_at desc)
        from hr.omanisation_exceptions x join hr.job_titles j on j.id = x.job_title_id
        where x.employee_id = p_id), '[]'::jsonb) else '[]'::jsonb end,
    'linked_user', case when v_access = 'FULL' then (
        select jsonb_build_object('user_id', up.user_id, 'email', up.email, 'is_active', up.is_active)
        from hr.user_profiles up where up.employee_id = p_id) end,
    'caps', jsonb_build_object(
      'edit',            hr.has_perm('EMP_WRITE'),
      'salary_read',     v_self or hr.has_perm('EMP_SALARY_READ') or hr.has_perm('EMP_SALARY_WRITE') or hr.has_perm('SALARY_APPROVE'),
      'salary_write',    hr.has_perm('EMP_SALARY_WRITE') and not v_self,
      'salary_approve',  hr.has_perm('SALARY_APPROVE') and not v_self,
      'bank_read',       v_self or hr.has_perm('EMP_BANK_READ') or hr.has_perm('EMP_BANK_WRITE') or hr.has_perm('BANK_APPROVE'),
      'bank_write',      hr.has_perm('EMP_BANK_WRITE') and not v_self,
      'bank_approve',    hr.has_perm('BANK_APPROVE') and not v_self,
      'docs_read',       v_self or hr.has_perm('DOC_READ'),
      'docs_write',      hr.has_perm('DOC_WRITE'),
      'docs_sensitive',  v_self or hr.has_perm('DOC_SENSITIVE'),
      'history',         hr.has_perm('EMP_READ'),
      'exception_approve', hr.has_perm('EXCEPTION_APPROVE')));
end $$;

-- ---------------------------------------------------------------------------
-- Create / update an employee
-- ---------------------------------------------------------------------------
create or replace function public.hr_save_employee(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := hr.juuid(p, 'id');
  v_old hr.employees; v_entity uuid; v_nat text; v_join date; v_no text; v_dup text;
  v_exc uuid; v_a jsonb := coalesce(p->'assignment', '{}'::jsonb); v_status text; v_changed text[];
  v_personal text[] := array['full_name_en','full_name_ar','preferred_name','date_of_birth','gender','nationality',
                             'marital_status','civil_number','personal_email','work_email','mobile','alt_phone',
                             'address_line','city','wilayat','governorate','address_country','probation_end_date'];
begin
  perform hr.require_perm('EMP_WRITE');

  if hr.jtext(p,'full_name_en') is null and v_id is null then raise exception 'REQUIRED: Full name (English) is required.'; end if;
  if v_id is null and hr.jtext(p,'nationality') is null then raise exception 'REQUIRED: Nationality is required.'; end if;
  perform hr.check_email(hr.jtext(p,'personal_email'), 'Personal e-mail');
  perform hr.check_email(hr.jtext(p,'work_email'), 'Work e-mail');
  perform hr.check_phone(hr.jtext(p,'mobile'), 'Mobile');
  perform hr.check_phone(hr.jtext(p,'alt_phone'), 'Alternative phone');
  if hr.jtext(p,'gender') is not null and hr.jtext(p,'gender') not in ('M','F') then raise exception 'INVALID: Gender must be M or F.'; end if;
  if hr.jdate(p,'date_of_birth') > current_date then raise exception 'INVALID: Date of birth cannot be in the future.'; end if;
  if hr.jtext(p,'nationality') is not null and not exists (select 1 from hr.countries where code = upper(hr.jtext(p,'nationality'))) then
    raise exception 'INVALID: Unknown nationality.';
  end if;

  if v_id is null then
    -- ---------------- create ----------------
    v_entity := hr.juuid(p, 'entity_id');
    if v_entity is null or not exists (select 1 from hr.legal_entities where id = v_entity and is_active) then
      raise exception 'REQUIRED: Choose an active company.';
    end if;
    v_join := hr.jdate(p, 'join_date');
    if v_join is null then raise exception 'REQUIRED: Joining date is required.'; end if;
    if v_join > current_date + 180 then raise exception 'INVALID: Joining date is more than 180 days ahead.'; end if;
    v_nat := upper(hr.jtext(p,'nationality'));

    if not hr.jbool(p, 'confirm_duplicate') then
      select employee_no into v_dup from hr.employees
       where lower(full_name_en) = lower(hr.jtext(p,'full_name_en'))
         and date_of_birth is not distinct from hr.jdate(p,'date_of_birth')
         and nationality = v_nat
       limit 1;
      if v_dup is not null then
        raise exception 'POSSIBLE_DUPLICATE: % already has the same name, date of birth and nationality. Save again with "this is a different person" ticked if that is correct.', v_dup;
      end if;
    end if;

    v_no := coalesce(upper(hr.jtext(p,'employee_no')), hr.next_employee_no());
    if v_no !~ '^[A-Z0-9/-]{2,30}$' then raise exception 'INVALID: Employee number may contain capital letters, digits, / and -.'; end if;
    v_status := case when hr.jdate(p,'probation_end_date') is not null and hr.jdate(p,'probation_end_date') > v_join
                     then 'PROBATION' else 'ACTIVE' end;

    -- validate the assignment before inserting (no employee id yet: the exception is recorded after the insert)
    perform hr.validate_assignment(null, v_entity, v_nat, v_a, hr.jtext(p,'exception_reason'), v_join);

    insert into hr.employees(entity_id, employee_no, full_name_en, full_name_ar, preferred_name, date_of_birth, gender,
                             nationality, marital_status, civil_number, personal_email, work_email, mobile, alt_phone,
                             address_line, city, wilayat, governorate, address_country, original_join_date, join_date,
                             probation_end_date, status, created_by)
    values (v_entity, v_no, hr.jtext(p,'full_name_en'), hr.jtext(p,'full_name_ar'), hr.jtext(p,'preferred_name'),
            hr.jdate(p,'date_of_birth'), hr.jtext(p,'gender'), v_nat, hr.jtext(p,'marital_status'),
            upper(hr.jtext(p,'civil_number')), lower(hr.jtext(p,'personal_email')), lower(hr.jtext(p,'work_email')),
            hr.jtext(p,'mobile'), hr.jtext(p,'alt_phone'), hr.jtext(p,'address_line'), hr.jtext(p,'city'),
            hr.jtext(p,'wilayat'), hr.jtext(p,'governorate'), upper(hr.jtext(p,'address_country')), v_join, v_join,
            hr.jdate(p,'probation_end_date'), v_status, auth.uid())
    returning id into v_id;

    v_exc := hr.validate_assignment(v_id, v_entity, v_nat, v_a, hr.jtext(p,'exception_reason'), v_join);

    insert into hr.employee_assignments(employee_id, effective_from, department_id, job_title_id, grade_id, category_id,
                                        location_id, cost_centre_id, manager_id, employment_type, shift_code, reason,
                                        omanisation_exception_id, notes, created_by)
    values (v_id, v_join, hr.juuid(v_a,'department_id'), hr.juuid(v_a,'job_title_id'), hr.juuid(v_a,'grade_id'),
            hr.juuid(v_a,'category_id'), hr.juuid(v_a,'location_id'),
            coalesce(hr.juuid(v_a,'cost_centre_id'), (select cost_centre_id from hr.departments where id = hr.juuid(v_a,'department_id'))),
            hr.juuid(v_a,'manager_id'), coalesce(hr.jtext(v_a,'employment_type'),'FULL_TIME'), hr.jtext(v_a,'shift_code'),
            'JOIN', v_exc, hr.jtext(v_a,'notes'), auth.uid());

    perform hr.add_event(v_id, 'JOIN', v_join, jsonb_build_object('employee_no', v_no));
  else
    -- ---------------- update personal details ----------------
    select * into v_old from hr.employees where id = v_id for update;
    if v_old.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;

    select array_agg(k) into v_changed from jsonb_object_keys(p) k where k = any(v_personal);
    if v_changed is null then return public.hr_get_employee(v_id); end if;

    if p ? 'full_name_en' and hr.jtext(p,'full_name_en') is null then raise exception 'REQUIRED: Full name (English) is required.'; end if;
    if p ? 'nationality' and hr.jtext(p,'nationality') is null then raise exception 'REQUIRED: Nationality is required.'; end if;
    if p ? 'probation_end_date' and hr.jdate(p,'probation_end_date') < v_old.join_date then
      raise exception 'INVALID: Probation cannot end before the joining date.';
    end if;
    if p ? 'nationality' and upper(hr.jtext(p,'nationality')) <> 'OM' and v_old.nationality = 'OM'
       and exists (select 1 from hr.employee_assignments a join hr.job_titles j on j.id = a.job_title_id
                   where a.employee_id = v_id and a.effective_to is null and j.omani_only) then
      raise exception 'OMANI_ONLY: This employee holds an Omani-only job. Move him to another job before changing the nationality.';
    end if;

    update hr.employees set
      full_name_en     = case when p ? 'full_name_en' then hr.jtext(p,'full_name_en') else full_name_en end,
      full_name_ar     = case when p ? 'full_name_ar' then hr.jtext(p,'full_name_ar') else full_name_ar end,
      preferred_name   = case when p ? 'preferred_name' then hr.jtext(p,'preferred_name') else preferred_name end,
      date_of_birth    = case when p ? 'date_of_birth' then hr.jdate(p,'date_of_birth') else date_of_birth end,
      gender           = case when p ? 'gender' then hr.jtext(p,'gender') else gender end,
      nationality      = case when p ? 'nationality' then upper(hr.jtext(p,'nationality')) else nationality end,
      marital_status   = case when p ? 'marital_status' then hr.jtext(p,'marital_status') else marital_status end,
      civil_number     = case when p ? 'civil_number' then upper(hr.jtext(p,'civil_number')) else civil_number end,
      personal_email   = case when p ? 'personal_email' then lower(hr.jtext(p,'personal_email')) else personal_email end,
      work_email       = case when p ? 'work_email' then lower(hr.jtext(p,'work_email')) else work_email end,
      mobile           = case when p ? 'mobile' then hr.jtext(p,'mobile') else mobile end,
      alt_phone        = case when p ? 'alt_phone' then hr.jtext(p,'alt_phone') else alt_phone end,
      address_line     = case when p ? 'address_line' then hr.jtext(p,'address_line') else address_line end,
      city             = case when p ? 'city' then hr.jtext(p,'city') else city end,
      wilayat          = case when p ? 'wilayat' then hr.jtext(p,'wilayat') else wilayat end,
      governorate      = case when p ? 'governorate' then hr.jtext(p,'governorate') else governorate end,
      address_country  = case when p ? 'address_country' then upper(hr.jtext(p,'address_country')) else address_country end,
      probation_end_date = case when p ? 'probation_end_date' then hr.jdate(p,'probation_end_date') else probation_end_date end
    where id = v_id;
    perform hr.add_event(v_id, 'PERSONAL_UPDATE', current_date, jsonb_build_object('fields', to_jsonb(v_changed)));
  end if;
  return public.hr_get_employee(v_id);
exception
  when unique_violation then
    if sqlerrm like '%civil_number%' then
      raise exception 'DUPLICATE: Another employee already has this civil / resident card number.';
    elsif sqlerrm like '%employee_no%' then
      raise exception 'DUPLICATE: This employee number is already used.';
    end if;
    raise exception 'DUPLICATE: %', sqlerrm;
  when check_violation then
    raise exception 'INVALID: %', sqlerrm;
end $$;

create or replace function public.hr_set_employee_photo(p_employee uuid, p_path text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform hr.require_perm('EMP_WRITE');
  if p_path is not null and p_path not like p_employee::text || '/PHOTO/%' then
    raise exception 'INVALID: The photo was not uploaded for this employee.';
  end if;
  update hr.employees set photo_path = p_path where id = p_employee;
  if not found then raise exception 'NOT_FOUND: Employee not found.'; end if;
  return public.hr_get_employee(p_employee);
end $$;

-- ---------------------------------------------------------------------------
-- Effective-dated assignment change (transfer, promotion …) or correction of the open record
-- ---------------------------------------------------------------------------
create or replace function public.hr_add_assignment(p_employee uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  e hr.employees; v_open hr.employee_assignments; v_from date := hr.jdate(p,'effective_from');
  v_reason text := coalesce(hr.jtext(p,'reason'), 'TRANSFER'); v_a jsonb; v_exc uuid; v_new uuid;
  v_event text;
begin
  perform hr.require_perm('EMP_WRITE');
  select * into e from hr.employees where id = p_employee for update;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if e.status = 'SEPARATED' then raise exception 'INVALID: This employee has left. Use Rehire.'; end if;
  if v_reason not in ('TRANSFER','PROMOTION','DEMOTION','REORGANISATION','CORRECTION','OTHER') then
    raise exception 'INVALID: Unknown reason %.', v_reason;
  end if;
  select * into v_open from hr.employee_assignments where employee_id = p_employee and effective_to is null;
  if v_open.id is null then raise exception 'INVALID: The employee has no open assignment.'; end if;

  -- fields not sent keep their current values
  v_a := jsonb_build_object(
    'department_id', coalesce(p->>'department_id', v_open.department_id::text),
    'job_title_id',  coalesce(p->>'job_title_id', v_open.job_title_id::text),
    'grade_id',      case when p ? 'grade_id' then p->>'grade_id' else v_open.grade_id::text end,
    'category_id',   coalesce(p->>'category_id', v_open.category_id::text),
    'location_id',   case when p ? 'location_id' then p->>'location_id' else v_open.location_id::text end,
    'cost_centre_id',case when p ? 'cost_centre_id' then p->>'cost_centre_id' else v_open.cost_centre_id::text end,
    'manager_id',    case when p ? 'manager_id' then p->>'manager_id' else v_open.manager_id::text end,
    'employment_type', coalesce(p->>'employment_type', v_open.employment_type),
    'shift_code',    case when p ? 'shift_code' then p->>'shift_code' else v_open.shift_code end);

  if v_reason = 'CORRECTION' then
    if hr.jtext(p,'notes') is null then
      raise exception 'REQUIRED: Explain the correction in the notes.';
    end if;
    v_exc := hr.validate_assignment(p_employee, e.entity_id, e.nationality, v_a, hr.jtext(p,'exception_reason'), v_open.effective_from);
    update hr.employee_assignments set
      department_id = hr.juuid(v_a,'department_id'), job_title_id = hr.juuid(v_a,'job_title_id'),
      grade_id = hr.juuid(v_a,'grade_id'), category_id = hr.juuid(v_a,'category_id'),
      location_id = hr.juuid(v_a,'location_id'), cost_centre_id = hr.juuid(v_a,'cost_centre_id'),
      manager_id = hr.juuid(v_a,'manager_id'), employment_type = hr.jtext(v_a,'employment_type'),
      shift_code = hr.jtext(v_a,'shift_code'),
      omanisation_exception_id = coalesce(v_exc, omanisation_exception_id),
      notes = coalesce(hr.jtext(p,'notes'), notes)
    where id = v_open.id;
    perform hr.add_event(p_employee, 'ASSIGNMENT_CORRECTION', current_date,
                         jsonb_build_object('assignment_id', v_open.id, 'notes', hr.jtext(p,'notes')));
    return public.hr_get_employee(p_employee);
  end if;

  if v_from is null then raise exception 'REQUIRED: Effective date is required.'; end if;
  if v_from <= v_open.effective_from then
    raise exception 'INVALID: The new assignment must start after % (the start of the current one). Use Correction to fix the current record.',
      to_char(v_open.effective_from, 'DD/MM/YYYY');
  end if;
  if v_from > current_date + 365 then raise exception 'INVALID: The effective date is more than a year ahead.'; end if;

  v_exc := hr.validate_assignment(p_employee, e.entity_id, e.nationality, v_a, hr.jtext(p,'exception_reason'), v_from);

  update hr.employee_assignments set effective_to = v_from - 1 where id = v_open.id;
  insert into hr.employee_assignments(employee_id, effective_from, department_id, job_title_id, grade_id, category_id,
                                      location_id, cost_centre_id, manager_id, employment_type, shift_code, reason,
                                      omanisation_exception_id, notes, created_by)
  values (p_employee, v_from, hr.juuid(v_a,'department_id'), hr.juuid(v_a,'job_title_id'), hr.juuid(v_a,'grade_id'),
          hr.juuid(v_a,'category_id'), hr.juuid(v_a,'location_id'), hr.juuid(v_a,'cost_centre_id'),
          hr.juuid(v_a,'manager_id'), hr.jtext(v_a,'employment_type'), hr.jtext(v_a,'shift_code'), v_reason,
          v_exc, hr.jtext(p,'notes'), auth.uid())
  returning id into v_new;

  v_event := case v_reason when 'PROMOTION' then 'PROMOTION' when 'DEMOTION' then 'DEMOTION'
                           when 'REORGANISATION' then 'REORGANISATION' else 'TRANSFER' end;
  perform hr.add_event(p_employee, v_event, v_from, jsonb_build_object('assignment_id', v_new, 'reason', v_reason,
                       'notes', hr.jtext(p,'notes')));
  return public.hr_get_employee(p_employee);
end $$;

-- ---------------------------------------------------------------------------
-- Status changes: CONFIRM, NOTICE, WITHDRAW_NOTICE, SUSPEND, REINSTATE, SEPARATE, REHIRE
-- ---------------------------------------------------------------------------
create or replace function public.hr_change_status(p_employee uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  e hr.employees; v_action text := upper(coalesce(hr.jtext(p,'action'),''));
  v_date date := coalesce(hr.jdate(p,'date'), current_date); v_open hr.employee_assignments;
  v_a jsonb; v_exc uuid; v_type text;
begin
  perform hr.require_perm('EMP_WRITE');
  select * into e from hr.employees where id = p_employee for update;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  select * into v_open from hr.employee_assignments where employee_id = p_employee and effective_to is null;

  if v_action = 'CONFIRM' then
    if e.status <> 'PROBATION' then raise exception 'INVALID: Only an employee on probation can be confirmed.'; end if;
    if v_date < e.join_date then raise exception 'INVALID: Confirmation cannot be before the joining date.'; end if;
    update hr.employees set status = 'ACTIVE', confirmation_date = v_date where id = p_employee;
    perform hr.add_event(p_employee, 'CONFIRM', v_date, jsonb_build_object('notes', hr.jtext(p,'notes')));

  elsif v_action = 'NOTICE' then
    if e.status not in ('ACTIVE','PROBATION') then raise exception 'INVALID: Notice can be recorded only for an active employee.'; end if;
    if hr.jdate(p,'last_working_date') is null then raise exception 'REQUIRED: Last working day is required.'; end if;
    if hr.jdate(p,'last_working_date') < v_date then raise exception 'INVALID: The last working day is before the notice date.'; end if;
    if hr.jtext(p,'separation_type') is null or hr.jtext(p,'separation_type') not in ('RESIGNATION','TERMINATION','END_OF_CONTRACT','RETIREMENT','OTHER') then
      raise exception 'REQUIRED: Choose the reason for leaving.';
    end if;
    update hr.employees set status = 'NOTICE', notice_given_date = v_date,
           last_working_date = hr.jdate(p,'last_working_date'), separation_type = hr.jtext(p,'separation_type'),
           separation_reason = hr.jtext(p,'notes')
     where id = p_employee;
    perform hr.add_event(p_employee, 'NOTICE', v_date, jsonb_build_object('last_working_date', hr.jdate(p,'last_working_date'),
                         'separation_type', hr.jtext(p,'separation_type'), 'notes', hr.jtext(p,'notes')));

  elsif v_action = 'WITHDRAW_NOTICE' then
    if e.status <> 'NOTICE' then raise exception 'INVALID: The employee is not serving notice.'; end if;
    update hr.employees set status = case when confirmation_date is null and probation_end_date >= current_date then 'PROBATION' else 'ACTIVE' end,
           notice_given_date = null, last_working_date = null, separation_type = null, separation_reason = null
     where id = p_employee;
    perform hr.add_event(p_employee, 'NOTICE_WITHDRAWN', v_date, jsonb_build_object('notes', hr.jtext(p,'notes')));

  elsif v_action = 'SUSPEND' then
    if e.status not in ('ACTIVE','PROBATION','NOTICE') then raise exception 'INVALID: Only a working employee can be suspended.'; end if;
    if hr.jtext(p,'notes') is null then raise exception 'REQUIRED: Give the reason for the suspension.'; end if;
    update hr.employees set status = 'SUSPENDED' where id = p_employee;
    perform hr.add_event(p_employee, 'SUSPEND', v_date, jsonb_build_object('previous_status', e.status, 'notes', hr.jtext(p,'notes')));

  elsif v_action = 'REINSTATE' then
    if e.status <> 'SUSPENDED' then raise exception 'INVALID: The employee is not suspended.'; end if;
    update hr.employees set status = case when notice_given_date is not null then 'NOTICE'
                                          when confirmation_date is null and probation_end_date >= current_date then 'PROBATION'
                                          else 'ACTIVE' end
     where id = p_employee;
    perform hr.add_event(p_employee, 'REINSTATE', v_date, jsonb_build_object('notes', hr.jtext(p,'notes')));

  elsif v_action = 'SEPARATE' then
    if e.status = 'SEPARATED' then raise exception 'INVALID: The employee has already left.'; end if;
    v_type := coalesce(hr.jtext(p,'separation_type'), e.separation_type);
    if v_type is null or v_type not in ('RESIGNATION','TERMINATION','END_OF_CONTRACT','RETIREMENT','DEATH','OTHER') then
      raise exception 'REQUIRED: Choose the reason for leaving.';
    end if;
    if v_date < e.join_date then raise exception 'INVALID: The leaving date is before the joining date.'; end if;
    if v_open.id is not null and v_open.effective_from > v_date then
      raise exception 'INVALID: An assignment starts on % — after the leaving date.', to_char(v_open.effective_from,'DD/MM/YYYY');
    end if;
    update hr.employee_assignments set effective_to = v_date where id = v_open.id;
    update hr.employee_contracts set status = 'ENDED' where employee_id = p_employee and status = 'ACTIVE';
    update hr.omanisation_exceptions set status = 'REVOKED' where employee_id = p_employee and status = 'ACTIVE';
    update hr.employees set status = 'SEPARATED', separation_date = v_date, separation_type = v_type,
           last_working_date = coalesce(last_working_date, v_date),
           separation_reason = coalesce(hr.jtext(p,'notes'), separation_reason)
     where id = p_employee;
    perform hr.add_event(p_employee, 'SEPARATION', v_date, jsonb_build_object('separation_type', v_type,
                         'notes', hr.jtext(p,'notes')));

  elsif v_action = 'REHIRE' then
    if e.status <> 'SEPARATED' then raise exception 'INVALID: Only an employee who has left can be rehired.'; end if;
    if v_date <= e.separation_date then raise exception 'INVALID: The rehire date must be after the leaving date.'; end if;
    v_a := coalesce(p->'assignment', '{}'::jsonb);
    v_exc := hr.validate_assignment(p_employee, e.entity_id, e.nationality, v_a, hr.jtext(p,'exception_reason'), v_date);
    insert into hr.employee_assignments(employee_id, effective_from, department_id, job_title_id, grade_id, category_id,
                                        location_id, cost_centre_id, manager_id, employment_type, shift_code, reason,
                                        omanisation_exception_id, notes, created_by)
    values (p_employee, v_date, hr.juuid(v_a,'department_id'), hr.juuid(v_a,'job_title_id'), hr.juuid(v_a,'grade_id'),
            hr.juuid(v_a,'category_id'), hr.juuid(v_a,'location_id'),
            coalesce(hr.juuid(v_a,'cost_centre_id'), (select cost_centre_id from hr.departments where id = hr.juuid(v_a,'department_id'))),
            hr.juuid(v_a,'manager_id'), coalesce(hr.jtext(v_a,'employment_type'),'FULL_TIME'), hr.jtext(v_a,'shift_code'),
            'REHIRE', v_exc, hr.jtext(p,'notes'), auth.uid());
    perform hr.add_event(p_employee, 'REHIRE', v_date, jsonb_build_object('previous_join_date', e.join_date,
                         'previous_separation_date', e.separation_date, 'previous_separation_type', e.separation_type));
    update hr.employees set status = case when hr.jdate(p,'probation_end_date') > v_date then 'PROBATION' else 'ACTIVE' end,
           join_date = v_date, probation_end_date = hr.jdate(p,'probation_end_date'), confirmation_date = null,
           notice_given_date = null, last_working_date = null, separation_date = null, separation_type = null,
           separation_reason = null
     where id = p_employee;
  else
    raise exception 'INVALID: Unknown action %.', v_action;
  end if;
  return public.hr_get_employee(p_employee);
end $$;

-- ---------------------------------------------------------------------------
-- Contracts (a new version supersedes the active one)
-- ---------------------------------------------------------------------------
create or replace function public.hr_save_contract(p_employee uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  e hr.employees; v_active hr.employee_contracts; v_id uuid := hr.juuid(p,'id');
  v_type text := hr.jtext(p,'contract_type'); v_start date := hr.jdate(p,'start_date'); v_end date := hr.jdate(p,'end_date');
  v_doc uuid := hr.juuid(p,'document_id'); v_new uuid; v_version int;
begin
  perform hr.require_perm('EMP_WRITE');
  select * into e from hr.employees where id = p_employee;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if v_type is null or v_type not in ('FIXED_TERM','INDEFINITE') then raise exception 'REQUIRED: Choose the contract type.'; end if;
  if v_start is null then raise exception 'REQUIRED: Contract start date is required.'; end if;
  if v_type = 'FIXED_TERM' and v_end is null then raise exception 'REQUIRED: A fixed-term contract needs an end date.'; end if;
  if v_type = 'INDEFINITE' then v_end := null; end if;
  if v_end is not null and v_end < v_start then raise exception 'INVALID: The end date is before the start date.'; end if;
  if v_start < e.original_join_date then raise exception 'INVALID: The contract starts before the employee first joined.'; end if;
  if v_doc is not null and not exists (select 1 from hr.employee_documents where id = v_doc and employee_id = p_employee) then
    raise exception 'INVALID: The linked document belongs to another employee.';
  end if;

  select * into v_active from hr.employee_contracts where employee_id = p_employee and status = 'ACTIVE' for update;

  if v_id is not null then
    if v_active.id is distinct from v_id then raise exception 'INVALID: Only the active contract can be corrected.'; end if;
    update hr.employee_contracts set contract_no = hr.jtext(p,'contract_no'), contract_type = v_type, start_date = v_start,
           end_date = v_end, probation_days = hr.jint(p,'probation_days'), notice_days = hr.jint(p,'notice_days'),
           working_hours_per_week = nullif(p->>'working_hours_per_week','')::numeric,
           mol_registration_no = hr.jtext(p,'mol_registration_no'), document_id = v_doc, notes = hr.jtext(p,'notes')
     where id = v_id;
    perform hr.add_event(p_employee, 'CONTRACT', current_date, jsonb_build_object('contract_id', v_id, 'action', 'CORRECTED'));
    return public.hr_get_employee(p_employee);
  end if;

  if e.status = 'SEPARATED' then raise exception 'INVALID: This employee has left.'; end if;
  if v_active.id is not null and v_start < v_active.start_date then
    raise exception 'INVALID: A new contract cannot start before the current one (%).', to_char(v_active.start_date,'DD/MM/YYYY');
  end if;
  select coalesce(max(version), 0) + 1 into v_version from hr.employee_contracts where employee_id = p_employee;
  if v_active.id is not null then
    update hr.employee_contracts set status = 'SUPERSEDED' where id = v_active.id;
  end if;
  insert into hr.employee_contracts(employee_id, contract_no, contract_type, start_date, end_date, probation_days,
                                    notice_days, working_hours_per_week, mol_registration_no, version, supersedes_id,
                                    status, document_id, notes, created_by)
  values (p_employee, hr.jtext(p,'contract_no'), v_type, v_start, v_end, hr.jint(p,'probation_days'),
          hr.jint(p,'notice_days'), nullif(p->>'working_hours_per_week','')::numeric, hr.jtext(p,'mol_registration_no'),
          v_version, v_active.id, 'ACTIVE', v_doc, hr.jtext(p,'notes'), auth.uid())
  returning id into v_new;
  perform hr.add_event(p_employee, 'CONTRACT', v_start, jsonb_build_object('contract_id', v_new, 'version', v_version,
                       'contract_type', v_type, 'end_date', v_end));
  return public.hr_get_employee(p_employee);
exception
  when check_violation then raise exception 'INVALID: %', sqlerrm;
  when invalid_text_representation then raise exception 'INVALID: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- Emergency contacts
-- ---------------------------------------------------------------------------
create or replace function public.hr_save_emergency_contact(p_employee uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id');
begin
  perform hr.require_perm('EMP_WRITE');
  if not exists (select 1 from hr.employees where id = p_employee) then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if hr.jtext(p,'name') is null then raise exception 'REQUIRED: Contact name is required.'; end if;
  if hr.jtext(p,'relationship') is null then raise exception 'REQUIRED: Relationship is required.'; end if;
  if hr.jtext(p,'phone') is null then raise exception 'REQUIRED: Phone is required.'; end if;
  perform hr.check_phone(hr.jtext(p,'phone'), 'Phone');
  perform hr.check_phone(hr.jtext(p,'alt_phone'), 'Alternative phone');
  if v_id is null then
    insert into hr.emergency_contacts(employee_id, name, relationship, phone, alt_phone, address, is_next_of_kin)
    values (p_employee, hr.jtext(p,'name'), hr.jtext(p,'relationship'), hr.jtext(p,'phone'), hr.jtext(p,'alt_phone'),
            hr.jtext(p,'address'), hr.jbool(p,'is_next_of_kin'));
  else
    update hr.emergency_contacts set name = hr.jtext(p,'name'), relationship = hr.jtext(p,'relationship'),
           phone = hr.jtext(p,'phone'), alt_phone = hr.jtext(p,'alt_phone'), address = hr.jtext(p,'address'),
           is_next_of_kin = hr.jbool(p,'is_next_of_kin')
     where id = v_id and employee_id = p_employee and is_active;
    if not found then raise exception 'NOT_FOUND: Contact not found.'; end if;
  end if;
  return public.hr_get_employee(p_employee);
end $$;

create or replace function public.hr_remove_emergency_contact(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_emp uuid;
begin
  perform hr.require_perm('EMP_WRITE');
  update hr.emergency_contacts set is_active = false where id = p_id and is_active returning employee_id into v_emp;
  if v_emp is null then raise exception 'NOT_FOUND: Contact not found.'; end if;
  return public.hr_get_employee(v_emp);
end $$;

select hr.secure_api();
