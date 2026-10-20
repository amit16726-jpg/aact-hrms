-- AACT HRMS — 009 API: expiry tracker, missing documents, Omanisation, targets, dashboard, notifications, audit

-- Rows of hr.expiry_items the caller may see, with employee details.
create or replace function hr.visible_expiries(p_on date default current_date)
returns table (employee_id uuid, employee_no text, full_name_en text, full_name_ar text, nationality char(2),
               entity_id uuid, department_id uuid, department_en text, department_ar text,
               source text, ref_id uuid, doc_type text, name_en text, name_ar text, doc_number text,
               expiry_date date, days_left int, bucket text, is_sensitive boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_all boolean := hr.has_perm('COMPLIANCE_READ'); v_sens boolean := hr.has_perm('DOC_SENSITIVE');
        v_me uuid := hr.my_employee_id();
begin
  return query
  select x.employee_id, e.employee_no, e.full_name_en, e.full_name_ar, e.nationality, e.entity_id,
         a.department_id, d.name_en, d.name_ar, x.source, x.ref_id, x.doc_type, x.name_en, x.name_ar,
         case when v_all or x.employee_id = v_me then x.doc_number else null end,
         x.expiry_date, x.days_left, x.bucket, x.is_sensitive
  from hr.expiry_items(p_on) x
  join hr.employees e on e.id = x.employee_id
  left join hr.employee_assignments a on a.employee_id = e.id and a.effective_from <= p_on
       and (a.effective_to is null or a.effective_to >= p_on)
  left join hr.departments d on d.id = a.department_id
  where (v_all and (v_sens or not x.is_sensitive))
     or x.employee_id = v_me
     or (not x.is_sensitive and v_me is not null and x.employee_id in (select t.employee_id from hr.team_of(v_me) t));
end $$;

create or replace function public.hr_list_expiries(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_days int := hr.jint(p,'within_days'); v_expired boolean := hr.jbool(p,'include_expired', true);
  v_type text := hr.jtext(p,'doc_type'); v_dept uuid := hr.juuid(p,'department_id'); v_entity uuid := hr.juuid(p,'entity_id');
  v_bucket text := hr.jtext(p,'bucket');
begin
  perform hr.require_user();
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.days_left, x.employee_no)
    from hr.visible_expiries() x
    where (v_days is null or x.days_left <= v_days)
      and (v_expired or x.days_left >= 0)
      and (v_type is null or x.doc_type = v_type)
      and (v_dept is null or x.department_id = v_dept)
      and (v_entity is null or x.entity_id = v_entity)
      and (v_bucket is null or x.bucket = v_bucket)), '[]'::jsonb);
end $$;

create or replace function public.hr_list_missing_documents(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_dept uuid := hr.juuid(p,'department_id'); v_entity uuid := hr.juuid(p,'entity_id'); v_type text := hr.jtext(p,'doc_type');
begin
  perform hr.require_perm('COMPLIANCE_READ');
  return coalesce((
    select jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en,
             'full_name_ar', e.full_name_ar, 'nationality', e.nationality, 'status', e.status, 'join_date', e.join_date,
             'department_en', d.name_en, 'department_ar', d.name_ar, 'doc_type', m.doc_type,
             'name_en', m.name_en, 'name_ar', m.name_ar) order by e.employee_no, m.doc_type)
    from hr.missing_documents() m
    join hr.employees e on e.id = m.employee_id
    left join hr.employee_assignments a on a.employee_id = e.id and a.effective_from <= current_date
         and (a.effective_to is null or a.effective_to >= current_date)
    left join hr.departments d on d.id = a.department_id
    left join hr.document_types t on t.code = m.doc_type
    where (v_dept is null or a.department_id = v_dept)
      and (v_entity is null or e.entity_id = v_entity)
      and (v_type is null or m.doc_type = v_type)
      and (not coalesce(t.is_sensitive, false) or hr.has_perm('DOC_SENSITIVE'))), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Omanisation
-- ---------------------------------------------------------------------------
create or replace function hr.target_for(p_entity uuid, p_scope text, p_scope_id uuid, p_prof text, p_on date)
returns hr.omanisation_targets language sql stable security definer set search_path = '' as $$
  select t.* from hr.omanisation_targets t
  where t.entity_id = p_entity and t.status = 'APPROVED' and t.scope_type = p_scope
    and t.effective_from <= p_on and (t.effective_to is null or t.effective_to >= p_on)
    and (p_scope_id is null or t.scope_id = p_scope_id)
    and (p_prof is null or t.profession_code = p_prof)
  order by t.effective_from desc limit 1
$$;

create or replace function hr.omanisation_row(p_total int, p_omani int, t hr.omanisation_targets)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'total', p_total, 'omani', p_omani, 'expat', p_total - p_omani,
    'pct', case when p_total = 0 then null else round(100.0 * p_omani / p_total, 2) end,
    'target_pct', t.target_pct, 'target_id', t.id, 'target_source', t.source_reference, 'rule_basis', t.rule_basis,
    'omanis_needed', case when t.id is null or p_total = 0 then null
                          else greatest(0, ceil(t.target_pct * p_total / 100.0)::int - p_omani) end,
    'meets_target', case when t.id is null or p_total = 0 then null
                         else (100.0 * p_omani / p_total) >= t.target_pct end)
$$;

create or replace function public.hr_get_omanisation(p_entity uuid, p_as_of date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_on date := coalesce(p_as_of, current_date); v_tot int; v_om int;
begin
  perform hr.require_perm('COMPLIANCE_READ');
  if not exists (select 1 from hr.legal_entities where id = p_entity) then raise exception 'NOT_FOUND: Company not found.'; end if;
  select count(*), count(*) filter (where is_omani) into v_tot, v_om from hr.omanisation_population(p_entity, v_on);
  return jsonb_build_object(
    'entity_id', p_entity, 'as_of', v_on,
    'overall', hr.omanisation_row(v_tot, v_om, hr.target_for(p_entity, 'ENTITY', null, null, v_on)),
    'by_department', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'code', d.code, 'name_en', d.name_en, 'name_ar', d.name_ar)
                       || hr.omanisation_row(x.total, x.omani, hr.target_for(p_entity, 'DEPARTMENT', d.id, null, v_on))
                       order by d.code)
      from (select department_id, count(*)::int total, count(*) filter (where is_omani)::int omani
            from hr.omanisation_population(p_entity, v_on) group by department_id) x
      join hr.departments d on d.id = x.department_id), '[]'::jsonb),
    'by_job_title', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'code', j.code, 'name_en', j.name_en, 'name_ar', j.name_ar,
                         'profession_code', j.profession_code, 'omani_only', j.omani_only)
                       || hr.omanisation_row(x.total, x.omani, hr.target_for(p_entity, 'JOB_TITLE', j.id, null, v_on))
                       order by j.code)
      from (select job_title_id, count(*)::int total, count(*) filter (where is_omani)::int omani
            from hr.omanisation_population(p_entity, v_on) group by job_title_id) x
      join hr.job_titles j on j.id = x.job_title_id), '[]'::jsonb),
    'by_profession', coalesce((
      select jsonb_agg(jsonb_build_object('profession_code', x.profession_code)
                       || hr.omanisation_row(x.total, x.omani, hr.target_for(p_entity, 'PROFESSION_CODE', null, x.profession_code, v_on))
                       order by x.profession_code)
      from (select profession_code, count(*)::int total, count(*) filter (where is_omani)::int omani
            from hr.omanisation_population(p_entity, v_on) where profession_code is not null group by profession_code) x), '[]'::jsonb),
    'omani_only_placements', coalesce((
      select jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en,
               'full_name_ar', e.full_name_ar, 'nationality', e.nationality, 'job_title_en', j.name_en, 'job_title_ar', j.name_ar,
               'exception_id', x.id, 'exception_reason', x.reason, 'exception_valid_to', x.valid_to,
               'exception_status', x.status) order by e.employee_no)
      from hr.omanisation_population(p_entity, v_on) pop
      join hr.employees e on e.id = pop.employee_id
      join hr.job_titles j on j.id = pop.job_title_id and j.omani_only
      join hr.employee_assignments a on a.employee_id = e.id and a.effective_from <= v_on
           and (a.effective_to is null or a.effective_to >= v_on)
      left join hr.omanisation_exceptions x on x.id = a.omanisation_exception_id
      where not pop.is_omani), '[]'::jsonb),
    'counting_basis', 'Employees on the books on the date, in categories marked "counts for Omanisation"; ratio = Omani ÷ total.');
end $$;

create or replace function public.hr_list_omanisation_targets(p_entity uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('COMPLIANCE_READ');
  return coalesce((
    select jsonb_agg(to_jsonb(t) || jsonb_build_object(
             'scope_name_en', coalesce(d.name_en, j.name_en, t.profession_code, le.name_en),
             'scope_name_ar', coalesce(d.name_ar, j.name_ar, t.profession_code, le.name_ar),
             'proposed_by_name', hr.user_label(t.proposed_by), 'decided_by_name', hr.user_label(t.decided_by),
             'can_decide', t.status = 'PENDING' and t.proposed_by <> auth.uid() and hr.has_perm('RULES_APPROVE'))
           order by t.status = 'PENDING' desc, t.scope_type, t.effective_from desc)
    from hr.omanisation_targets t
    join hr.legal_entities le on le.id = t.entity_id
    left join hr.departments d on t.scope_type = 'DEPARTMENT' and d.id = t.scope_id
    left join hr.job_titles j on t.scope_type = 'JOB_TITLE' and j.id = t.scope_id
    where p_entity is null or t.entity_id = p_entity), '[]'::jsonb);
end $$;

create or replace function public.hr_propose_omanisation_target(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_entity uuid := hr.juuid(p,'entity_id'); v_scope text := upper(coalesce(hr.jtext(p,'scope_type'),'ENTITY'));
  v_scope_id uuid := hr.juuid(p,'scope_id'); v_prof text := hr.jtext(p,'profession_code');
  v_pct numeric := nullif(p->>'target_pct','')::numeric; v_from date := hr.jdate(p,'effective_from');
  v_to date := hr.jdate(p,'effective_to'); v_id uuid; u record;
begin
  perform hr.require_perm('RULES_PROPOSE');
  if v_entity is null or not exists (select 1 from hr.legal_entities where id = v_entity) then raise exception 'REQUIRED: Choose the company.'; end if;
  if v_scope not in ('ENTITY','DEPARTMENT','JOB_TITLE','PROFESSION_CODE') then raise exception 'INVALID: Unknown scope.'; end if;
  if v_scope = 'ENTITY' then v_scope_id := null; v_prof := null; end if;
  if v_scope = 'DEPARTMENT' and not exists (select 1 from hr.departments where id = v_scope_id and entity_id = v_entity) then
    raise exception 'REQUIRED: Choose a department of this company.';
  end if;
  if v_scope = 'JOB_TITLE' and not exists (select 1 from hr.job_titles where id = v_scope_id and entity_id = v_entity) then
    raise exception 'REQUIRED: Choose a job title of this company.';
  end if;
  if v_scope = 'PROFESSION_CODE' then
    v_scope_id := null;
    if v_prof is null then raise exception 'REQUIRED: Enter the profession code.'; end if;
  elsif v_scope <> 'ENTITY' then v_prof := null;
  end if;
  if v_pct is null or v_pct < 0 or v_pct > 100 then raise exception 'INVALID: The target must be between 0 and 100 %%.'; end if;
  if v_from is null then raise exception 'REQUIRED: Effective-from date is required.'; end if;
  if v_to is not null and v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  if coalesce(hr.jtext(p,'rule_basis'),'') not in ('LEGAL','COMPANY_POLICY') then
    raise exception 'REQUIRED: Say whether this is a legal requirement or company policy.';
  end if;
  if coalesce(length(hr.jtext(p,'source_reference')),0) < 3 then
    raise exception 'REQUIRED: Give the source (Ministry decision / circular number and date, or the internal policy reference).';
  end if;

  insert into hr.omanisation_targets(entity_id, scope_type, scope_id, profession_code, target_pct, effective_from, effective_to,
                                     rule_basis, source_reference, notes, proposed_by)
  values (v_entity, v_scope, v_scope_id, v_prof, round(v_pct, 2), v_from, v_to, hr.jtext(p,'rule_basis'),
          hr.jtext(p,'source_reference'), hr.jtext(p,'notes'), auth.uid())
  returning id into v_id;
  for u in select h.user_id from hr.users_with_perm('RULES_APPROVE') h where h.user_id <> auth.uid() loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL', 'Omanisation target awaiting approval', 'هدف تعمين بانتظار الاعتماد',
                      round(v_pct,2) || '% from ' || to_char(v_from,'DD/MM/YYYY'), round(v_pct,2) || '% اعتباراً من ' || to_char(v_from,'DD/MM/YYYY'),
                      '/compliance/targets', 'TGT:' || v_id);
  end loop;
  return public.hr_list_omanisation_targets(v_entity);
end $$;

create or replace function public.hr_decide_omanisation_target(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t hr.omanisation_targets; v_clash hr.omanisation_targets;
begin
  perform hr.require_perm('RULES_APPROVE');
  select * into t from hr.omanisation_targets where id = p_id for update;
  if t.id is null then raise exception 'NOT_FOUND: Target not found.'; end if;
  if t.status <> 'PENDING' then raise exception 'INVALID: This target has already been decided.'; end if;
  if t.proposed_by = auth.uid() then
    raise exception 'SELF_APPROVAL: You proposed this target; someone else must approve it.' using errcode = '42501';
  end if;
  if not p_approve then
    if nullif(btrim(p_note),'') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
    update hr.omanisation_targets set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(), decision_note = btrim(p_note)
     where id = p_id;
  else
    -- an approved target for the same scope that starts on/after this one cannot be silently replaced
    select * into v_clash from hr.omanisation_targets x
     where x.id <> t.id and x.entity_id = t.entity_id and x.status = 'APPROVED' and x.scope_type = t.scope_type
       and x.scope_id is not distinct from t.scope_id and x.profession_code is not distinct from t.profession_code
       and x.effective_from >= t.effective_from
       and (t.effective_to is null or x.effective_from <= t.effective_to)
     limit 1;
    if v_clash.id is not null then
      raise exception 'OVERLAP: An approved target for this scope already starts on %. Retire it first.', to_char(v_clash.effective_from,'DD/MM/YYYY');
    end if;
    -- close the earlier open-ended target the day before this one starts
    update hr.omanisation_targets x set effective_to = t.effective_from - 1
     where x.id <> t.id and x.entity_id = t.entity_id and x.status = 'APPROVED' and x.scope_type = t.scope_type
       and x.scope_id is not distinct from t.scope_id and x.profession_code is not distinct from t.profession_code
       and x.effective_from < t.effective_from and (x.effective_to is null or x.effective_to >= t.effective_from);
    update hr.omanisation_targets set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(),
           decision_note = nullif(btrim(p_note),'') where id = p_id;
  end if;
  perform hr.notify(t.proposed_by, 'DECISION', 'NORMAL',
    'Omanisation target ' || case when p_approve then 'approved' else 'rejected' end,
    case when p_approve then 'تم اعتماد هدف التعمين' else 'تم رفض هدف التعمين' end,
    nullif(btrim(p_note),''), nullif(btrim(p_note),''), '/compliance/targets', 'TGTDEC:' || p_id);
  return public.hr_list_omanisation_targets(t.entity_id);
end $$;

create or replace function public.hr_retire_omanisation_target(p_id uuid, p_to date default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t hr.omanisation_targets; v_to date := coalesce(p_to, current_date);
begin
  perform hr.require_perm('RULES_APPROVE');
  select * into t from hr.omanisation_targets where id = p_id for update;
  if t.id is null or t.status <> 'APPROVED' then raise exception 'NOT_FOUND: Only an approved target can be retired.'; end if;
  if v_to < t.effective_from then raise exception 'INVALID: The end date is before the target starts.'; end if;
  if nullif(btrim(p_note),'') is null then raise exception 'REQUIRED: Give the reason (e.g. the new decision number).'; end if;
  update hr.omanisation_targets set status = 'RETIRED', effective_to = v_to,
         decision_note = coalesce(decision_note || ' | ', '') || 'Retired: ' || btrim(p_note)
   where id = p_id;
  return public.hr_list_omanisation_targets(t.entity_id);
end $$;

create or replace function public.hr_revoke_omanisation_exception(p_id uuid, p_note text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_emp uuid;
begin
  perform hr.require_perm('EXCEPTION_APPROVE');
  if nullif(btrim(p_note),'') is null then raise exception 'REQUIRED: Give the reason.'; end if;
  update hr.omanisation_exceptions set status = 'REVOKED', reason = reason || ' | Revoked: ' || btrim(p_note)
   where id = p_id and status = 'ACTIVE' returning employee_id into v_emp;
  if v_emp is null then raise exception 'NOT_FOUND: No active exception.'; end if;
  return public.hr_get_employee(v_emp);
end $$;

-- ---------------------------------------------------------------------------
-- Dashboard (each section only when the caller may see it)
-- ---------------------------------------------------------------------------
create or replace function public.hr_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_res jsonb := '{}'::jsonb; v_me uuid := hr.my_employee_id(); v_uid uuid := hr.require_user();
begin
  if hr.has_perm('EMP_READ') then
    v_res := v_res || jsonb_build_object('workforce', (
      select jsonb_build_object(
        'headcount', count(*) filter (where e.status <> 'SEPARATED'),
        'omani', count(*) filter (where e.status <> 'SEPARATED' and e.nationality = 'OM'),
        'expat', count(*) filter (where e.status <> 'SEPARATED' and e.nationality <> 'OM'),
        'probation', count(*) filter (where e.status = 'PROBATION'),
        'notice', count(*) filter (where e.status = 'NOTICE'),
        'suspended', count(*) filter (where e.status = 'SUSPENDED'),
        'joiners_30', count(*) filter (where e.join_date between current_date - 30 and current_date),
        'leavers_30', count(*) filter (where e.separation_date between current_date - 30 and current_date),
        'probation_due_30', count(*) filter (where e.status = 'PROBATION' and e.probation_end_date <= current_date + 30))
      from hr.employees e),
      'by_department', coalesce((
        select jsonb_agg(jsonb_build_object('department_id', x.department_id, 'name_en', d.name_en, 'name_ar', d.name_ar,
                 'total', x.total, 'omani', x.omani) order by x.total desc, d.name_en)
        from (select a.department_id, count(*)::int total, count(*) filter (where e.nationality = 'OM')::int omani
              from hr.employees e join hr.employee_assignments a on a.employee_id = e.id
                   and a.effective_from <= current_date and (a.effective_to is null or a.effective_to >= current_date)
              where e.status <> 'SEPARATED' group by a.department_id) x
        join hr.departments d on d.id = x.department_id), '[]'::jsonb),
      'by_nationality', coalesce((
        select jsonb_agg(jsonb_build_object('code', x.nationality, 'name_en', c.nationality_en, 'name_ar', c.nationality_ar,
                 'total', x.total) order by x.total desc)
        from (select nationality, count(*)::int total from hr.employees where status <> 'SEPARATED' group by nationality) x
        join hr.countries c on c.code = x.nationality), '[]'::jsonb),
      'probation_due', coalesce((
        select jsonb_agg(jsonb_build_object('id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en,
                 'full_name_ar', e.full_name_ar, 'probation_end_date', e.probation_end_date) order by e.probation_end_date)
        from hr.employees e where e.status = 'PROBATION' and e.probation_end_date <= current_date + 30), '[]'::jsonb));
  end if;

  if hr.has_perm('COMPLIANCE_READ') then
    v_res := v_res || jsonb_build_object('compliance', (
      select jsonb_build_object(
        'expired', count(*) filter (where x.bucket = 'EXPIRED'),
        'd30', count(*) filter (where x.bucket = 'D30'),
        'd60', count(*) filter (where x.bucket = 'D60'),
        'd90', count(*) filter (where x.bucket = 'D90'),
        'missing', (select count(*) from hr.missing_documents() m join hr.document_types t on t.code = m.doc_type
                    where not t.is_sensitive or hr.has_perm('DOC_SENSITIVE')),
        'employees_missing', (select count(distinct m.employee_id) from hr.missing_documents() m))
      from hr.visible_expiries() x),
      'expiring_soon', coalesce((select jsonb_agg(to_jsonb(x) order by x.days_left) from (
          select * from hr.visible_expiries() v where v.days_left <= 30 order by v.days_left limit 10) x), '[]'::jsonb),
      'omanisation', coalesce((
        select jsonb_agg(jsonb_build_object('entity_id', le.id, 'code', le.code, 'name_en', le.name_en, 'name_ar', le.name_ar)
                 || hr.omanisation_row(
                      (select count(*)::int from hr.omanisation_population(le.id)),
                      (select count(*)::int from hr.omanisation_population(le.id) p where p.is_omani),
                      hr.target_for(le.id, 'ENTITY', null, null, current_date)) order by le.code)
        from hr.legal_entities le where le.is_active), '[]'::jsonb));
  end if;

  v_res := v_res || jsonb_build_object('approvals', (
    select jsonb_build_object(
      'salary', case when hr.has_perm('SALARY_APPROVE') then (select count(*) from hr.compensation_revisions r
                     where r.status = 'PENDING' and r.proposed_by <> v_uid and r.employee_id is distinct from v_me) else 0 end,
      'bank', case when hr.has_perm('BANK_APPROVE') then (select count(*) from hr.employee_bank_accounts b
                   where b.status = 'PENDING' and b.requested_by <> v_uid and b.employee_id is distinct from v_me) else 0 end,
      'targets', case when hr.has_perm('RULES_APPROVE') then (select count(*) from hr.omanisation_targets t
                      where t.status = 'PENDING' and t.proposed_by <> v_uid) else 0 end)));

  if v_me is not null then
    v_res := v_res || jsonb_build_object('me', (
      select jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en,
               'full_name_ar', e.full_name_ar, 'status', e.status, 'join_date', e.join_date,
               'assignment', hr.assignment_json(hr.current_assignment(e.id)),
               'my_expiries', coalesce((select jsonb_agg(to_jsonb(x) order by x.days_left)
                                        from hr.visible_expiries() x where x.employee_id = e.id and x.days_left <= 90), '[]'::jsonb),
               'team_size', (select count(*) from hr.team_of(e.id)),
               'team_expiries', coalesce((select jsonb_agg(to_jsonb(x) order by x.days_left) from (
                    select * from hr.visible_expiries() v
                    where v.employee_id in (select t.employee_id from hr.team_of(e.id) t) and v.days_left <= 60
                    order by v.days_left limit 20) x), '[]'::jsonb))
      from hr.employees e where e.id = v_me));
  end if;
  return v_res;
end $$;

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_notifications(p_unread_only boolean default false, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v uuid := hr.require_user();
begin
  return jsonb_build_object(
    'unread', (select count(*) from hr.notifications where user_id = v and read_at is null),
    'rows', coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from (
               select * from hr.notifications where user_id = v and (not p_unread_only or read_at is null)
               order by created_at desc limit least(greatest(coalesce(p_limit,50),1),200)) n), '[]'::jsonb));
end $$;

create or replace function public.hr_mark_notifications_read(p_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v uuid := hr.require_user();
begin
  update hr.notifications set read_at = now()
   where user_id = v and read_at is null and (p_ids is null or id = any(p_ids));
  return public.hr_list_notifications(false, 50);
end $$;

create or replace function public.hr_run_expiry_scan()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  perform hr.require_perm('COMPLIANCE_READ');
  n := hr.generate_expiry_notifications(current_date);
  return jsonb_build_object('created', n);
end $$;

-- ---------------------------------------------------------------------------
-- Audit trail
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_audit(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_limit int := least(greatest(coalesce(hr.jint(p,'limit'), 100), 1), 500);
  v_offset int := greatest(coalesce(hr.jint(p,'offset'), 0), 0);
  v_table text := hr.jtext(p,'table_name'); v_emp uuid := hr.juuid(p,'employee_id');
  v_from date := hr.jdate(p,'from'); v_to date := hr.jdate(p,'to'); v_user uuid := hr.juuid(p,'user_id');
  v_salary boolean := hr.has_perm('EMP_SALARY_READ'); v_bank boolean := hr.has_perm('EMP_BANK_READ');
begin
  perform hr.require_perm('AUDIT_READ');
  return jsonb_build_object(
    'total', (select count(*) from hr.audit_log a
              where (v_table is null or a.table_name = v_table) and (v_emp is null or a.employee_id = v_emp)
                and (v_user is null or a.user_id = v_user)
                and (v_from is null or a.at >= v_from) and (v_to is null or a.at < v_to + 1)
                and (v_salary or a.table_name not in ('compensation_revisions','compensation_lines'))
                and (v_bank or a.table_name <> 'employee_bank_accounts')),
    'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.id desc) from (
              select a.*, hr.user_label(a.user_id) as user_name, e.employee_no, e.full_name_en
              from hr.audit_log a left join hr.employees e on e.id = a.employee_id
              where (v_table is null or a.table_name = v_table) and (v_emp is null or a.employee_id = v_emp)
                and (v_user is null or a.user_id = v_user)
                and (v_from is null or a.at >= v_from) and (v_to is null or a.at < v_to + 1)
                and (v_salary or a.table_name not in ('compensation_revisions','compensation_lines'))
                and (v_bank or a.table_name <> 'employee_bank_accounts')
              order by a.id desc limit v_limit offset v_offset) x), '[]'::jsonb));
end $$;

create or replace function public.hr_list_access_log(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_limit int := least(greatest(coalesce(hr.jint(p,'limit'), 100), 1), 500);
begin
  perform hr.require_perm('AUDIT_READ');
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.id desc) from (
      select l.*, hr.user_label(l.user_id) as user_name, e.employee_no, e.full_name_en
      from hr.access_log l left join hr.employees e on e.id = l.employee_id
      where v_emp is null or l.employee_id = v_emp
      order by l.id desc limit v_limit) x), '[]'::jsonb);
end $$;

select hr.secure_api();
