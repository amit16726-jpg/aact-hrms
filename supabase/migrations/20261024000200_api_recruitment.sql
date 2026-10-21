-- AACT HRMS — 041 API: requisitions, candidates, applications, interviews, offers, onboarding, hiring, probation.
-- Idempotent; no destructive statements.

-- ---------------------------------------------------------------------------
-- Requisitions
-- ---------------------------------------------------------------------------
create or replace function public.hr_save_requisition(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := hr.juuid(p,'id'); r hr.job_requisitions; v_dept hr.departments; v_job hr.job_titles; v_entity uuid;
  v_rule text := upper(coalesce(hr.jtext(p,'nationality_rule'), 'ANY')); v_reason text := upper(coalesce(hr.jtext(p,'reason'), 'NEW'));
  v_pos int := coalesce(hr.jint(p,'positions'), 1); v_me uuid := hr.my_employee_id(); u record;
begin
  perform hr.require_user();
  if not (hr.has_perm('REC_WRITE') or (v_me is not null and exists (select 1 from hr.team_of(v_me)))) then
    raise exception 'NOT_ALLOWED: Only HR or a line manager can raise a requisition.' using errcode = '42501';
  end if;
  select * into v_dept from hr.departments where id = hr.juuid(p,'department_id') and is_active;
  if v_dept.id is null then raise exception 'REQUIRED: Choose an active department.'; end if;
  v_entity := v_dept.entity_id;
  select * into v_job from hr.job_titles where id = hr.juuid(p,'job_title_id') and entity_id = v_entity and is_active;
  if v_job.id is null then raise exception 'REQUIRED: Choose an active job title of the same company.'; end if;
  if hr.juuid(p,'grade_id') is not null and not exists (select 1 from hr.grades where id = hr.juuid(p,'grade_id') and entity_id = v_entity) then
    raise exception 'INVALID: Grade is not a grade of this company.';
  end if;
  if hr.juuid(p,'category_id') is not null and not exists (select 1 from hr.employee_categories where id = hr.juuid(p,'category_id') and entity_id = v_entity) then
    raise exception 'INVALID: Category is not a category of this company.';
  end if;
  if v_rule not in ('ANY','OMANI_ONLY','OMANI_PREFERRED') then raise exception 'INVALID: Unknown nationality rule.'; end if;
  if v_job.omani_only then v_rule := 'OMANI_ONLY'; end if;
  if v_reason not in ('NEW','REPLACEMENT','TEMPORARY') then raise exception 'INVALID: Unknown reason.'; end if;
  if v_reason = 'REPLACEMENT' and hr.juuid(p,'replaces_employee_id') is null then raise exception 'REQUIRED: Choose the employee being replaced.'; end if;
  if v_pos < 1 or v_pos > 200 then raise exception 'INVALID: Positions must be between 1 and 200.'; end if;
  if coalesce(length(hr.jtext(p,'justification')), 0) < 10 then raise exception 'REQUIRED: Explain why the position is needed (at least 10 characters).'; end if;
  if hr.jmoney(p,'salary_min') is not null and hr.jmoney(p,'salary_max') is not null and hr.jmoney(p,'salary_min') > hr.jmoney(p,'salary_max') then
    raise exception 'INVALID: The minimum salary is above the maximum.';
  end if;
  if v_id is null then
    insert into hr.job_requisitions(ref_no, entity_id, department_id, job_title_id, grade_id, category_id, location_id, positions, reason,
      replaces_employee_id, employment_type, nationality_rule, salary_min, salary_max, target_date, justification, requested_by)
    values (hr.next_rec_ref('REQ', hr.today()), v_entity, v_dept.id, v_job.id, hr.juuid(p,'grade_id'), hr.juuid(p,'category_id'), hr.juuid(p,'location_id'),
      v_pos, v_reason, case when v_reason = 'REPLACEMENT' then hr.juuid(p,'replaces_employee_id') end,
      coalesce(upper(hr.jtext(p,'employment_type')), 'FULL_TIME'), v_rule, hr.jmoney(p,'salary_min'), hr.jmoney(p,'salary_max'),
      hr.jdate(p,'target_date'), hr.jtext(p,'justification'), auth.uid())
    returning * into r;
    for u in select h.user_id from hr.users_with_perm('REC_APPROVE') h where h.user_id <> auth.uid() loop
      perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL', 'Requisition ' || r.ref_no || ' — ' || v_job.name_en || ' × ' || v_pos,
        'طلب توظيف ' || r.ref_no || ' — ' || coalesce(v_job.name_ar, v_job.name_en) || ' × ' || v_pos, null, null,
        '/recruitment/req/' || r.id, 'REQ:' || r.id);
    end loop;
  else
    select * into r from hr.job_requisitions where id = v_id for update;
    if r.id is null then raise exception 'NOT_FOUND: Requisition not found.'; end if;
    if r.status <> 'PENDING' then raise exception 'NOT_PENDING: Only a requisition waiting for approval can be changed.'; end if;
    if not (auth.uid() = r.requested_by or hr.has_perm('REC_WRITE')) then raise exception 'NOT_ALLOWED: You cannot change this requisition.' using errcode = '42501'; end if;
    update hr.job_requisitions set entity_id = v_entity, department_id = v_dept.id, job_title_id = v_job.id, grade_id = hr.juuid(p,'grade_id'),
      category_id = hr.juuid(p,'category_id'), location_id = hr.juuid(p,'location_id'), positions = v_pos, reason = v_reason,
      replaces_employee_id = case when v_reason = 'REPLACEMENT' then hr.juuid(p,'replaces_employee_id') end,
      employment_type = coalesce(upper(hr.jtext(p,'employment_type')), 'FULL_TIME'), nationality_rule = v_rule,
      salary_min = hr.jmoney(p,'salary_min'), salary_max = hr.jmoney(p,'salary_max'), target_date = hr.jdate(p,'target_date'),
      justification = hr.jtext(p,'justification')
    where id = v_id returning * into r;
  end if;
  return public.hr_get_requisition(r.id);
end $$;

create or replace function public.hr_decide_requisition(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.job_requisitions;
begin
  perform hr.require_perm('REC_APPROVE');
  select * into r from hr.job_requisitions where id = p_id for update;
  if r.id is null then raise exception 'NOT_FOUND: Requisition not found.'; end if;
  if r.status <> 'PENDING' then raise exception 'NOT_PENDING: This requisition has already been decided.'; end if;
  if r.requested_by = auth.uid() then raise exception 'SELF_APPROVAL: You cannot approve your own requisition.' using errcode = '42501'; end if;
  if not p_approve and nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  update hr.job_requisitions set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(btrim(coalesce(p_note,'')), '') where id = p_id returning * into r;
  perform hr.notify(r.requested_by, 'INFO', 'NORMAL',
    'Requisition ' || r.ref_no || case when p_approve then ' approved' else ' rejected' end,
    'طلب التوظيف ' || r.ref_no || case when p_approve then ' معتمد' else ' مرفوض' end, r.decision_note, r.decision_note,
    '/recruitment/req/' || r.id, 'REQD:' || r.id);
  return public.hr_get_requisition(r.id);
end $$;

create or replace function public.hr_set_requisition_status(p_id uuid, p_status text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.job_requisitions; v_st text := upper(coalesce(p_status,''));
begin
  perform hr.require_user();
  select * into r from hr.job_requisitions where id = p_id for update;
  if r.id is null then raise exception 'NOT_FOUND: Requisition not found.'; end if;
  if v_st not in ('APPROVED','ON_HOLD','FILLED','CANCELLED') then raise exception 'INVALID: Unknown status.'; end if;
  if v_st = 'CANCELLED' and r.status = 'PENDING' and auth.uid() = r.requested_by then
    null; -- the requester may withdraw a requisition that is still waiting
  else
    perform hr.require_perm('REC_WRITE');
    if r.status not in ('APPROVED','ON_HOLD') then raise exception 'INVALID: Only an approved or on-hold requisition can be changed.'; end if;
    if v_st = 'APPROVED' and r.status <> 'ON_HOLD' then raise exception 'INVALID: Only a requisition on hold can be reopened.'; end if;
  end if;
  if v_st in ('ON_HOLD','CANCELLED') and nullif(btrim(coalesce(p_reason,'')), '') is null then raise exception 'REQUIRED: Give a reason.'; end if;
  update hr.job_requisitions set status = v_st, closed_reason = nullif(btrim(coalesce(p_reason,'')), '') where id = p_id;
  return public.hr_get_requisition(p_id);
end $$;

create or replace function public.hr_list_requisitions(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_st text := hr.jtext(p,'status');
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.requisition_json(r) order by (r.status = 'PENDING') desc, r.requested_at desc)
    from hr.job_requisitions r
    where hr.can_see_requisition(r)
      and (v_st is null or (v_st = 'OPEN' and r.status in ('PENDING','APPROVED','ON_HOLD')) or r.status = v_st)
      and (hr.juuid(p,'entity_id') is null or r.entity_id = hr.juuid(p,'entity_id'))), '[]'::jsonb);
end $$;

create or replace function public.hr_get_requisition(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r hr.job_requisitions; v_full boolean := hr.has_perm('REC_READ');
begin
  perform hr.require_user();
  select * into r from hr.job_requisitions where id = p_id;
  if r.id is null then raise exception 'NOT_FOUND: Requisition not found.'; end if;
  if not hr.can_see_requisition(r) then raise exception 'NOT_ALLOWED: You cannot see this requisition.' using errcode = '42501'; end if;
  return hr.requisition_json(r) || jsonb_build_object(
    'omanisation', hr.hire_omanisation(r.entity_id, r.department_id, r.job_title_id, r.positions),
    'applications', coalesce((select jsonb_agg(hr.application_brief(a) order by a.stage_at desc) from hr.applications a
                              where a.requisition_id = r.id and (v_full or r.requested_by = auth.uid() or hr.can_see_application(a.id))), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- Candidates and applications
-- ---------------------------------------------------------------------------
create or replace function hr.save_candidate(p jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); v_nat text := upper(hr.jtext(p,'nationality')); v_dup uuid; v_civil text := upper(hr.jtext(p,'civil_number'));
        v_email text := lower(hr.jtext(p,'email'));
begin
  if hr.jtext(p,'full_name_en') is null then raise exception 'REQUIRED: Candidate name (English) is required.'; end if;
  if v_nat is null or not exists (select 1 from hr.countries where code = v_nat) then raise exception 'REQUIRED: Choose the nationality.'; end if;
  perform hr.check_email(v_email, 'E-mail');
  perform hr.check_phone(hr.jtext(p,'phone'), 'Phone');
  if hr.jtext(p,'gender') is not null and hr.jtext(p,'gender') not in ('M','F') then raise exception 'INVALID: Gender must be M or F.'; end if;
  if hr.jdate(p,'date_of_birth') > hr.today() - 365 * 15 then raise exception 'INVALID: The candidate must be at least 15 years old.'; end if;
  if hr.jtext(p,'source') is not null and upper(hr.jtext(p,'source')) not in ('REFERRAL','AGENCY','WEBSITE','WALK_IN','INTERNAL','MOL_PORTAL','OTHER') then
    raise exception 'INVALID: Unknown source.';
  end if;
  select id into v_dup from hr.candidates
   where id is distinct from v_id and ((v_civil is not null and upper(civil_number) = v_civil) or (v_email is not null and lower(email) = v_email)) limit 1;
  if v_dup is not null then raise exception 'DUPLICATE: This candidate is already registered (same ID number or e-mail).'; end if;
  if v_id is null then
    insert into hr.candidates(full_name_en, full_name_ar, nationality, gender, date_of_birth, email, phone, civil_number, passport_no, in_oman,
      current_employer, experience_years, qualification, source, notes, created_by)
    values (hr.jtext(p,'full_name_en'), hr.jtext(p,'full_name_ar'), v_nat, hr.jtext(p,'gender'), hr.jdate(p,'date_of_birth'), v_email,
      hr.jtext(p,'phone'), v_civil, upper(hr.jtext(p,'passport_no')), hr.jbool(p,'in_oman', v_nat = 'OM'), hr.jtext(p,'current_employer'),
      nullif(p->>'experience_years','')::numeric, hr.jtext(p,'qualification'), coalesce(upper(hr.jtext(p,'source')), 'OTHER'), hr.jtext(p,'notes'), auth.uid())
    returning id into v_id;
  else
    update hr.candidates set full_name_en = hr.jtext(p,'full_name_en'), full_name_ar = hr.jtext(p,'full_name_ar'), nationality = v_nat,
      gender = hr.jtext(p,'gender'), date_of_birth = hr.jdate(p,'date_of_birth'), email = v_email, phone = hr.jtext(p,'phone'),
      civil_number = v_civil, passport_no = upper(hr.jtext(p,'passport_no')), in_oman = hr.jbool(p,'in_oman', v_nat = 'OM'),
      current_employer = hr.jtext(p,'current_employer'), experience_years = nullif(p->>'experience_years','')::numeric,
      qualification = hr.jtext(p,'qualification'), source = coalesce(upper(hr.jtext(p,'source')), source), notes = hr.jtext(p,'notes')
    where id = v_id and employee_id is null;
    if not found then raise exception 'NOT_FOUND: Candidate not found, or already hired (change the employee record instead).'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.hr_save_candidate(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  perform hr.require_perm('REC_WRITE');
  v_id := hr.save_candidate(p);   -- separate statement: the stable read below must see the new row
  return public.hr_get_candidate(v_id);
end $$;

create or replace function public.hr_list_candidates(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_q text := lower(hr.jtext(p,'q'));
begin
  perform hr.require_perm('REC_READ');
  return coalesce((select jsonb_agg(hr.candidate_json(c) || jsonb_build_object(
      'applications', (select count(*) from hr.applications a where a.candidate_id = c.id),
      'active', (select count(*) from hr.applications a where a.candidate_id = c.id and a.stage not in ('HIRED','REJECTED','WITHDRAWN')))
      order by c.created_at desc)
    from (select * from hr.candidates c
          where v_q is null or lower(c.full_name_en) like '%' || v_q || '%' or coalesce(c.full_name_ar,'') like '%' || hr.jtext(p,'q') || '%'
             or lower(coalesce(c.email,'')) like '%' || v_q || '%' or lower(coalesce(c.civil_number,'')) like '%' || v_q || '%'
             or coalesce(c.phone,'') like '%' || v_q || '%'
          order by c.created_at desc limit 200) c), '[]'::jsonb);
end $$;

create or replace function public.hr_get_candidate(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare c hr.candidates;
begin
  perform hr.require_perm('REC_READ');
  select * into c from hr.candidates where id = p_id;
  if c.id is null then raise exception 'NOT_FOUND: Candidate not found.'; end if;
  return hr.candidate_json(c) || jsonb_build_object('applications', coalesce((
    select jsonb_agg(hr.application_brief(a) || jsonb_build_object('requisition_ref', r.ref_no, 'job_en', j.name_en, 'job_ar', j.name_ar) order by a.created_at desc)
    from hr.applications a join hr.job_requisitions r on r.id = a.requisition_id join hr.job_titles j on j.id = r.job_title_id
    where a.candidate_id = c.id), '[]'::jsonb));
end $$;

create or replace function public.hr_add_application(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.job_requisitions; v_cand uuid := hr.juuid(p,'candidate_id'); c hr.candidates; v_app uuid;
begin
  perform hr.require_perm('REC_WRITE');
  select * into r from hr.job_requisitions where id = hr.juuid(p,'requisition_id');
  if r.id is null then raise exception 'NOT_FOUND: Requisition not found.'; end if;
  if r.status <> 'APPROVED' then raise exception 'INVALID: Candidates can be added only to an approved, open requisition.'; end if;
  if v_cand is null then
    if p->'candidate' is null then raise exception 'REQUIRED: Choose or enter a candidate.'; end if;
    v_cand := hr.save_candidate(p->'candidate');
  end if;
  select * into c from hr.candidates where id = v_cand;
  if c.id is null then raise exception 'NOT_FOUND: Candidate not found.'; end if;
  if r.nationality_rule = 'OMANI_ONLY' and c.nationality <> 'OM' then
    raise exception 'OMANI_ONLY: This position is reserved for Omani nationals.';
  end if;
  if exists (select 1 from hr.applications where requisition_id = r.id and candidate_id = v_cand) then
    raise exception 'DUPLICATE: This candidate is already on this requisition.';
  end if;
  insert into hr.applications(requisition_id, candidate_id, created_by) values (r.id, v_cand, auth.uid()) returning id into v_app;
  return public.hr_get_application(v_app);
end $$;

create or replace function public.hr_move_application(p_id uuid, p_stage text, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.applications; v_st text := upper(coalesce(p_stage,''));
begin
  perform hr.require_perm('REC_WRITE');
  select * into a from hr.applications where id = p_id for update;
  if a.id is null then raise exception 'NOT_FOUND: Application not found.'; end if;
  if a.stage in ('HIRED') then raise exception 'INVALID: The candidate has been hired.'; end if;
  if v_st not in ('APPLIED','SHORTLISTED','INTERVIEW','REJECTED','WITHDRAWN') then
    raise exception 'INVALID: Offers and hiring move the candidate automatically.';
  end if;
  if a.stage = 'OFFER' and exists (select 1 from hr.job_offers o where o.application_id = a.id and o.status in ('PENDING','APPROVED','ACCEPTED')) then
    raise exception 'INVALID: Withdraw the open offer first.';
  end if;
  if v_st in ('REJECTED','WITHDRAWN') and nullif(btrim(coalesce(p_reason,'')), '') is null then raise exception 'REQUIRED: Give a reason.'; end if;
  update hr.applications set stage = v_st, stage_at = now(),
         rejection_reason = case when v_st in ('REJECTED','WITHDRAWN') then btrim(p_reason) else null end where id = p_id;
  return public.hr_get_application(p_id);
end $$;

create or replace function public.hr_get_application(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare a hr.applications; r hr.job_requisitions; c hr.candidates; v_full boolean := hr.has_perm('REC_READ');
begin
  perform hr.require_user();
  select * into a from hr.applications where id = p_id;
  if a.id is null then raise exception 'NOT_FOUND: Application not found.'; end if;
  if not hr.can_see_application(p_id) then raise exception 'NOT_ALLOWED: You cannot see this candidate.' using errcode = '42501'; end if;
  select * into r from hr.job_requisitions where id = a.requisition_id;
  select * into c from hr.candidates where id = a.candidate_id;
  return hr.application_brief(a) || jsonb_build_object(
    'candidate', case when v_full then hr.candidate_json(c)
                      else jsonb_build_object('id', c.id, 'full_name_en', c.full_name_en, 'full_name_ar', c.full_name_ar, 'nationality', c.nationality,
                             'experience_years', c.experience_years, 'qualification', c.qualification, 'current_employer', c.current_employer) end,
    'requisition', hr.requisition_json(r),
    'prior_employee_id', case when v_full then hr.candidate_prior_employee(c.id, r.entity_id) end,
    'probation_max_months', hr.probation_max_months(r.category_id),
    'interviews', coalesce((select jsonb_agg(hr.interview_json(i) order by i.scheduled_at) from hr.interviews i
                            where i.application_id = a.id and (v_full or i.interviewer_id = auth.uid() or r.requested_by = auth.uid())), '[]'::jsonb),
    'offers', case when v_full then coalesce((select jsonb_agg(hr.offer_json(o) order by o.prepared_at desc) from hr.job_offers o where o.application_id = a.id), '[]'::jsonb)
                   else '[]'::jsonb end,
    'onboarding', case when v_full then coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'title_en', t.title_en, 'title_ar', t.title_ar,
                     'due_date', t.due_date, 'status', t.status, 'note', t.note, 'done_by_name', hr.user_label(t.done_by), 'done_at', t.done_at,
                     'overdue', t.status = 'PENDING' and t.due_date < hr.today()) order by t.sort) from hr.onboarding_tasks t where t.application_id = a.id), '[]'::jsonb)
                   else '[]'::jsonb end,
    'can_manage', hr.has_perm('REC_WRITE'));
end $$;

-- ---------------------------------------------------------------------------
-- Interviews
-- ---------------------------------------------------------------------------
create or replace function public.hr_schedule_interview(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.applications; v_at timestamptz := nullif(p->>'scheduled_at','')::timestamptz; v_who uuid := hr.juuid(p,'interviewer_id'); v_id uuid;
        c hr.candidates;
begin
  perform hr.require_perm('REC_WRITE');
  select * into a from hr.applications where id = hr.juuid(p,'application_id');
  if a.id is null then raise exception 'NOT_FOUND: Application not found.'; end if;
  if a.stage in ('HIRED','REJECTED','WITHDRAWN') then raise exception 'INVALID: This candidate is no longer in the process.'; end if;
  if v_at is null then raise exception 'REQUIRED: Date and time are required.'; end if;
  if v_who is null or not exists (select 1 from hr.user_profiles where user_id = v_who and is_active) then raise exception 'REQUIRED: Choose an interviewer with a login.'; end if;
  if coalesce(upper(hr.jtext(p,'mode')), 'IN_PERSON') not in ('IN_PERSON','PHONE','VIDEO') then raise exception 'INVALID: Unknown interview type.'; end if;
  insert into hr.interviews(application_id, scheduled_at, mode, location, interviewer_id, created_by)
  values (a.id, v_at, coalesce(upper(hr.jtext(p,'mode')), 'IN_PERSON'), hr.jtext(p,'location'), v_who, auth.uid()) returning id into v_id;
  if a.stage in ('APPLIED','SHORTLISTED') then update hr.applications set stage = 'INTERVIEW', stage_at = now() where id = a.id; end if;
  select * into c from hr.candidates where id = a.candidate_id;
  perform hr.notify(v_who, 'TASK', 'NORMAL', 'Interview: ' || c.full_name_en || ' — ' || to_char(v_at at time zone 'Asia/Muscat', 'DD/MM/YYYY HH24:MI'),
    'مقابلة: ' || coalesce(c.full_name_ar, c.full_name_en) || ' — ' || to_char(v_at at time zone 'Asia/Muscat', 'DD/MM/YYYY HH24:MI'), null, null,
    '/recruitment/app/' || a.id, 'INT:' || v_id);
  return public.hr_get_application(a.id);
end $$;

-- Active logins that can be chosen as interviewers.
create or replace function public.hr_rec_interviewers()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('REC_WRITE');
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', up.user_id, 'name', coalesce(nullif(up.display_name,''), up.email), 'email', up.email,
             'job_en', j.name_en, 'job_ar', j.name_ar) order by coalesce(nullif(up.display_name,''), up.email))
    from hr.user_profiles up
    left join hr.employee_assignments a on a.id = (hr.current_assignment(up.employee_id)).id
    left join hr.job_titles j on j.id = a.job_title_id
    where up.is_active and exists (select 1 from hr.user_roles ur where ur.user_id = up.user_id and ur.revoked_at is null)), '[]'::jsonb);
end $$;

create or replace function public.hr_record_interview(p_id uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare i hr.interviews; v_st text := upper(coalesce(hr.jtext(p,'status'), 'DONE')); v_rec text := upper(hr.jtext(p,'recommendation'));
begin
  perform hr.require_user();
  select * into i from hr.interviews where id = p_id for update;
  if i.id is null then raise exception 'NOT_FOUND: Interview not found.'; end if;
  if i.status <> 'SCHEDULED' then raise exception 'NOT_PENDING: This interview has already been recorded.'; end if;
  if v_st = 'CANCELLED' then
    perform hr.require_perm('REC_WRITE');
  elsif not (auth.uid() = i.interviewer_id or hr.has_perm('REC_WRITE')) then
    raise exception 'NOT_ALLOWED: Only the interviewer or HR can record this interview.' using errcode = '42501';
  end if;
  if v_st not in ('DONE','CANCELLED','NO_SHOW') then raise exception 'INVALID: Unknown result.'; end if;
  if v_st = 'DONE' then
    if hr.jint(p,'rating') is null or hr.jint(p,'rating') not between 1 and 5 then raise exception 'REQUIRED: Give a rating from 1 to 5.'; end if;
    if v_rec is null or v_rec not in ('HIRE','MAYBE','NO') then raise exception 'REQUIRED: Give a recommendation.'; end if;
    if coalesce(length(hr.jtext(p,'feedback')), 0) < 10 then raise exception 'REQUIRED: Write short feedback (at least 10 characters).'; end if;
  end if;
  update hr.interviews set status = v_st, rating = case when v_st = 'DONE' then hr.jint(p,'rating') end,
         recommendation = case when v_st = 'DONE' then v_rec end, feedback = hr.jtext(p,'feedback'), recorded_at = now()
   where id = p_id;
  return public.hr_get_application(i.application_id);
end $$;

create or replace function public.hr_my_interviews()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.interview_json(i) || jsonb_build_object('full_name_en', c.full_name_en, 'full_name_ar', c.full_name_ar,
             'job_en', j.name_en, 'job_ar', j.name_ar, 'requisition_ref', r.ref_no) order by i.scheduled_at)
    from hr.interviews i join hr.applications a on a.id = i.application_id join hr.candidates c on c.id = a.candidate_id
    join hr.job_requisitions r on r.id = a.requisition_id join hr.job_titles j on j.id = r.job_title_id
    where (i.interviewer_id = auth.uid() or hr.has_perm('REC_READ'))
      and (i.status = 'SCHEDULED' or i.scheduled_at > now() - interval '30 days')), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Offers
-- ---------------------------------------------------------------------------
create or replace function public.hr_save_offer(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := hr.juuid(p,'id'); o hr.job_offers; a hr.applications; r hr.job_requisitions; c hr.candidates; v_job hr.job_titles;
  v_cat uuid; v_prob int := coalesce(hr.jint(p,'probation_months'), 0); v_max int; v_lines jsonb := '[]'::jsonb; x jsonb; v_amt numeric;
  v_type text := upper(coalesce(hr.jtext(p,'contract_type'), 'FIXED_TERM')); v_start date := hr.jdate(p,'start_date'); u record; v_basic boolean := false;
begin
  perform hr.require_perm('REC_WRITE');
  if v_id is not null then
    select * into o from hr.job_offers where id = v_id for update;
    if o.id is null then raise exception 'NOT_FOUND: Offer not found.'; end if;
    if o.status <> 'PENDING' then raise exception 'NOT_PENDING: Only an offer waiting for approval can be changed.'; end if;
    select * into a from hr.applications where id = o.application_id;
  else
    select * into a from hr.applications where id = hr.juuid(p,'application_id') for update;
    if a.id is null then raise exception 'NOT_FOUND: Application not found.'; end if;
    if a.stage in ('HIRED','REJECTED','WITHDRAWN') then raise exception 'INVALID: This candidate is no longer in the process.'; end if;
    if exists (select 1 from hr.job_offers where application_id = a.id and status in ('PENDING','APPROVED','ACCEPTED')) then
      raise exception 'PENDING_EXISTS: This candidate already has an open offer.';
    end if;
  end if;
  select * into r from hr.job_requisitions where id = a.requisition_id;
  select * into c from hr.candidates where id = a.candidate_id;
  if r.status not in ('APPROVED','ON_HOLD') then raise exception 'INVALID: The requisition is not open.'; end if;
  select * into v_job from hr.job_titles where id = coalesce(hr.juuid(p,'job_title_id'), r.job_title_id) and entity_id = r.entity_id;
  if v_job.id is null then raise exception 'INVALID: Job title is not a job title of this company.'; end if;
  if v_job.omani_only and c.nationality <> 'OM' then
    raise exception 'OMANI_ONLY: % is an Omani-only job (%). An offer cannot be made to a non-Omani.', v_job.name_en, v_job.omani_only_source;
  end if;
  v_cat := coalesce(hr.juuid(p,'category_id'), r.category_id);
  if v_cat is null or not exists (select 1 from hr.employee_categories where id = v_cat and entity_id = r.entity_id) then
    raise exception 'REQUIRED: Choose the employee category.';
  end if;
  if v_start is null then raise exception 'REQUIRED: Start date is required.'; end if;
  if v_start < hr.today() then raise exception 'INVALID: The start date is in the past.'; end if;
  if v_type not in ('FIXED_TERM','INDEFINITE') then raise exception 'INVALID: Unknown contract type.'; end if;
  if v_type = 'FIXED_TERM' and coalesce(hr.jint(p,'contract_months'), 0) not between 1 and 60 then
    raise exception 'REQUIRED: Give the contract length in months (1–60).';
  end if;
  v_max := hr.probation_max_months(v_cat);
  if v_prob < 0 or v_prob > v_max then
    raise exception 'PROBATION_LIMIT: Probation can be at most % month(s) for this category (Labour Law).', v_max;
  end if;
  if v_prob > 0 and hr.candidate_prior_employee(c.id, r.entity_id) is not null then
    raise exception 'PROBATION_LIMIT: This person has worked for the company before; probation is allowed only once with the same employer.';
  end if;
  if jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then raise exception 'REQUIRED: Enter at least the basic salary.'; end if;
  for x in select * from jsonb_array_elements(p->'lines') loop
    v_amt := hr.jmoney(x, 'amount');
    continue when v_amt is null or v_amt = 0;
    if not exists (select 1 from hr.pay_components where code = x->>'code' and kind = 'EARNING' and is_active) then
      raise exception 'INVALID: % is not an active earning component.', x->>'code';
    end if;
    if exists (select 1 from jsonb_array_elements(v_lines) y where y->>'code' = x->>'code') then raise exception 'INVALID: % appears twice.', x->>'code'; end if;
    if exists (select 1 from hr.pay_components where code = x->>'code' and is_basic) then v_basic := true; end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', x->>'code', 'amount', v_amt));
  end loop;
  if not v_basic then raise exception 'REQUIRED: The basic salary is required.'; end if;
  if v_id is null then
    insert into hr.job_offers(ref_no, application_id, job_title_id, department_id, grade_id, category_id, location_id, start_date, contract_type,
      contract_months, probation_months, notice_days, lines, benefits, valid_until, prepared_by)
    values (hr.next_rec_ref('OFR', hr.today()), a.id, v_job.id, coalesce(hr.juuid(p,'department_id'), r.department_id), coalesce(hr.juuid(p,'grade_id'), r.grade_id),
      v_cat, coalesce(hr.juuid(p,'location_id'), r.location_id), v_start, v_type, case when v_type = 'FIXED_TERM' then hr.jint(p,'contract_months') end,
      v_prob, coalesce(hr.jint(p,'notice_days'), 30), v_lines, hr.jtext(p,'benefits'), hr.jdate(p,'valid_until'), auth.uid())
    returning * into o;
    update hr.applications set stage = 'OFFER', stage_at = now() where id = a.id;
    for u in select h.user_id from hr.users_with_perm('REC_APPROVE') h where h.user_id <> auth.uid() loop
      perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL', 'Offer ' || o.ref_no || ' — ' || c.full_name_en || ' — ' || v_job.name_en,
        'عرض عمل ' || o.ref_no || ' — ' || coalesce(c.full_name_ar, c.full_name_en), null, null, '/recruitment/app/' || a.id, 'OFR:' || o.id);
    end loop;
  else
    update hr.job_offers set job_title_id = v_job.id, department_id = coalesce(hr.juuid(p,'department_id'), department_id),
      grade_id = hr.juuid(p,'grade_id'), category_id = v_cat, location_id = hr.juuid(p,'location_id'), start_date = v_start, contract_type = v_type,
      contract_months = case when v_type = 'FIXED_TERM' then hr.jint(p,'contract_months') end, probation_months = v_prob,
      notice_days = coalesce(hr.jint(p,'notice_days'), notice_days), lines = v_lines, benefits = hr.jtext(p,'benefits'), valid_until = hr.jdate(p,'valid_until')
    where id = v_id returning * into o;
  end if;
  return public.hr_get_application(a.id);
end $$;

create or replace function public.hr_decide_offer(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o hr.job_offers;
begin
  perform hr.require_perm('REC_APPROVE');
  select * into o from hr.job_offers where id = p_id for update;
  if o.id is null then raise exception 'NOT_FOUND: Offer not found.'; end if;
  if o.status <> 'PENDING' then raise exception 'NOT_PENDING: This offer has already been decided.'; end if;
  if o.prepared_by = auth.uid() then raise exception 'SELF_APPROVAL: The person who prepared an offer cannot approve it.' using errcode = '42501'; end if;
  if not p_approve and nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  update hr.job_offers set status = case when p_approve then 'APPROVED' else 'REJECTED' end, approved_by = auth.uid(), approved_at = now(),
         decision_note = nullif(btrim(coalesce(p_note,'')), '') where id = p_id returning * into o;
  if not p_approve then update hr.applications set stage = 'INTERVIEW', stage_at = now() where id = o.application_id and stage = 'OFFER'; end if;
  perform hr.notify(o.prepared_by, 'INFO', 'NORMAL', 'Offer ' || o.ref_no || case when p_approve then ' approved — send it to the candidate' else ' rejected' end,
    'عرض العمل ' || o.ref_no || case when p_approve then ' معتمد — أرسله للمرشح' else ' مرفوض' end, o.decision_note, o.decision_note,
    '/recruitment/app/' || o.application_id, 'OFRD:' || o.id);
  return public.hr_get_application(o.application_id);
end $$;

create or replace function public.hr_offer_response(p_id uuid, p_accepted boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o hr.job_offers;
begin
  perform hr.require_perm('REC_WRITE');
  select * into o from hr.job_offers where id = p_id for update;
  if o.id is null then raise exception 'NOT_FOUND: Offer not found.'; end if;
  if o.status <> 'APPROVED' then raise exception 'INVALID: Only an approved offer can be accepted or declined.'; end if;
  if not p_accepted and nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'REQUIRED: Record the reason the candidate gave.'; end if;
  update hr.job_offers set status = case when p_accepted then 'ACCEPTED' else 'DECLINED' end, response_at = now(),
         response_note = nullif(btrim(coalesce(p_note,'')), '') where id = p_id returning * into o;
  if p_accepted then
    perform hr.create_onboarding(o.application_id, o.start_date);
  else
    update hr.applications set stage = 'WITHDRAWN', stage_at = now(), rejection_reason = 'Offer declined: ' || o.response_note where id = o.application_id;
  end if;
  return public.hr_get_application(o.application_id);
end $$;

create or replace function public.hr_withdraw_offer(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare o hr.job_offers;
begin
  perform hr.require_perm('REC_WRITE');
  if nullif(btrim(coalesce(p_reason,'')), '') is null then raise exception 'REQUIRED: Give a reason.'; end if;
  select * into o from hr.job_offers where id = p_id for update;
  if o.id is null then raise exception 'NOT_FOUND: Offer not found.'; end if;
  if o.status not in ('PENDING','APPROVED','ACCEPTED') then raise exception 'INVALID: This offer is already closed.'; end if;
  if exists (select 1 from hr.applications where id = o.application_id and stage = 'HIRED') then raise exception 'INVALID: The candidate has been hired.'; end if;
  update hr.job_offers set status = 'WITHDRAWN', response_note = btrim(p_reason), response_at = now() where id = p_id;
  update hr.applications set stage = 'INTERVIEW', stage_at = now() where id = o.application_id and stage = 'OFFER';
  update hr.onboarding_tasks set status = 'NOT_NEEDED', note = 'Offer withdrawn' where application_id = o.application_id and status = 'PENDING';
  return public.hr_get_application(o.application_id);
end $$;

-- Printable offer (approved or later), with the letter settings for the signatory.
create or replace function public.hr_get_offer(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare o hr.job_offers; a hr.applications; r hr.job_requisitions; c hr.candidates;
begin
  perform hr.require_perm('REC_READ');
  select * into o from hr.job_offers where id = p_id;
  if o.id is null then raise exception 'NOT_FOUND: Offer not found.'; end if;
  select * into a from hr.applications where id = o.application_id;
  select * into r from hr.job_requisitions where id = a.requisition_id;
  select * into c from hr.candidates where id = a.candidate_id;
  return hr.offer_json(o) || jsonb_build_object('candidate', hr.candidate_json(c),
    'entity_en', (select name_en from hr.legal_entities where id = r.entity_id), 'entity_ar', (select name_ar from hr.legal_entities where id = r.entity_id),
    'entity_cr', (select cr_number from hr.legal_entities where id = r.entity_id),
    'settings', (select value from hr.settings where key = 'letters'), 'today', hr.today());
end $$;

-- ---------------------------------------------------------------------------
-- Onboarding and hiring
-- ---------------------------------------------------------------------------
create or replace function public.hr_set_onboarding_task(p_id uuid, p_status text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t hr.onboarding_tasks; v_st text := upper(coalesce(p_status,''));
begin
  perform hr.require_perm('REC_WRITE');
  if v_st not in ('PENDING','DONE','NOT_NEEDED') then raise exception 'INVALID: Unknown status.'; end if;
  if v_st = 'NOT_NEEDED' and nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'REQUIRED: Say why this step is not needed.'; end if;
  update hr.onboarding_tasks set status = v_st, note = coalesce(nullif(btrim(coalesce(p_note,'')), ''), note),
         done_by = case when v_st = 'PENDING' then null else auth.uid() end, done_at = case when v_st = 'PENDING' then null else now() end
   where id = p_id returning * into t;
  if t.id is null then raise exception 'NOT_FOUND: Step not found.'; end if;
  return public.hr_get_application(t.application_id);
end $$;

create or replace function public.hr_list_onboarding(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('REC_READ');
  return coalesce((select jsonb_agg(x order by x->>'start_date', x->>'full_name_en') from (
    select jsonb_build_object('application_id', a.id, 'full_name_en', c.full_name_en, 'full_name_ar', c.full_name_ar, 'nationality', c.nationality,
      'employee_id', a.employee_id, 'stage', a.stage, 'job_en', j.name_en, 'job_ar', j.name_ar, 'start_date', o.start_date, 'offer_ref', o.ref_no,
      'total', count(t.*), 'done', count(t.*) filter (where t.status <> 'PENDING'),
      'overdue', count(t.*) filter (where t.status = 'PENDING' and t.due_date < hr.today()),
      'next', (select jsonb_build_object('title_en', t2.title_en, 'title_ar', t2.title_ar, 'due_date', t2.due_date) from hr.onboarding_tasks t2
               where t2.application_id = a.id and t2.status = 'PENDING' order by t2.due_date nulls last, t2.sort limit 1)) x
    from hr.applications a join hr.candidates c on c.id = a.candidate_id
    join hr.job_offers o on o.application_id = a.id and o.status = 'ACCEPTED'
    join hr.job_titles j on j.id = o.job_title_id
    join hr.onboarding_tasks t on t.application_id = a.id
    group by a.id, c.id, j.id, o.id
    having not hr.jbool(p, 'open_only', true) or count(t.*) filter (where t.status = 'PENDING') > 0) s), '[]'::jsonb);
end $$;

-- Hire: create the employee from the accepted offer (Omani-only rule, duplicate check and numbering as for any new employee),
-- propose the salary for approval, record the contract, and move the onboarding checklist to the employee.
create or replace function public.hr_hire(p_offer uuid, p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  o hr.job_offers; a hr.applications; r hr.job_requisitions; c hr.candidates; v_emp uuid; v_res jsonb; v_prob_end date; v_hired int;
begin
  perform hr.require_perm('REC_WRITE');
  perform hr.require_perm('EMP_WRITE');
  perform hr.require_perm('EMP_SALARY_WRITE');
  select * into o from hr.job_offers where id = p_offer for update;
  if o.id is null then raise exception 'NOT_FOUND: Offer not found.'; end if;
  if o.status <> 'ACCEPTED' then raise exception 'INVALID: Only an accepted offer can be turned into an employee.'; end if;
  select * into a from hr.applications where id = o.application_id for update;
  if a.stage = 'HIRED' then raise exception 'INVALID: Already hired.'; end if;
  select * into r from hr.job_requisitions where id = a.requisition_id for update;
  select * into c from hr.candidates where id = a.candidate_id;
  v_prob_end := case when o.probation_months > 0 then (o.start_date + make_interval(months => o.probation_months) - interval '1 day')::date end;
  v_res := public.hr_save_employee(jsonb_build_object(
    'entity_id', r.entity_id, 'full_name_en', c.full_name_en, 'full_name_ar', c.full_name_ar, 'nationality', c.nationality,
    'gender', c.gender, 'date_of_birth', c.date_of_birth, 'civil_number', c.civil_number, 'personal_email', c.email, 'mobile', c.phone,
    'join_date', o.start_date, 'probation_end_date', v_prob_end, 'employee_no', hr.jtext(p,'employee_no'),
    'work_email', hr.jtext(p,'work_email'), 'confirm_duplicate', hr.jbool(p,'confirm_duplicate'),
    'exception_reason', hr.jtext(p,'exception_reason'),
    'assignment', jsonb_build_object('department_id', o.department_id, 'job_title_id', o.job_title_id, 'grade_id', o.grade_id,
      'category_id', o.category_id, 'location_id', coalesce(hr.juuid(p,'location_id'), o.location_id), 'manager_id', hr.juuid(p,'manager_id'),
      'employment_type', r.employment_type, 'shift_code', hr.jtext(p,'shift_code'))));
  v_emp := (v_res->'employee'->>'id')::uuid;
  perform public.hr_propose_compensation(v_emp, jsonb_build_object('effective_from', o.start_date, 'reason', 'JOIN',
    'notes', 'From offer ' || o.ref_no,
    'lines', (select jsonb_agg(jsonb_build_object('component_code', l->>'code', 'amount', l->>'amount')) from jsonb_array_elements(o.lines) l)));
  perform public.hr_save_contract(v_emp, jsonb_build_object('contract_type', o.contract_type, 'start_date', o.start_date,
    'end_date', case when o.contract_type = 'FIXED_TERM' then (o.start_date + make_interval(months => o.contract_months) - interval '1 day')::date end,
    'probation_days', case when v_prob_end is null then 0 else v_prob_end - o.start_date + 1 end, 'notice_days', o.notice_days,
    'notes', 'From offer ' || o.ref_no));
  update hr.applications set stage = 'HIRED', stage_at = now(), employee_id = v_emp where id = a.id;
  update hr.candidates set employee_id = v_emp where id = c.id;
  update hr.onboarding_tasks set employee_id = v_emp where application_id = a.id;
  select count(*) into v_hired from hr.applications where requisition_id = r.id and stage = 'HIRED';
  if v_hired >= r.positions then
    update hr.job_requisitions set status = 'FILLED', closed_reason = 'All positions filled' where id = r.id;
  end if;
  return public.hr_get_application(a.id) || jsonb_build_object('new_employee_id', v_emp, 'employee_no', v_res->'employee'->>'employee_no');
end $$;

-- ---------------------------------------------------------------------------
-- Probation tracker
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_probation()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  if not (hr.has_perm('REC_READ') or hr.has_perm('EMP_READ') or exists (select 1 from hr.team_of(hr.my_employee_id()))) then
    raise exception 'NOT_ALLOWED: You cannot see probation dates.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(hr.emp_brief(e.id) || jsonb_build_object(
      'join_date', e.join_date, 'probation_end_date', e.probation_end_date, 'days_left', e.probation_end_date - hr.today(),
      'overdue', e.probation_end_date < hr.today(),
      'job_en', j.name_en, 'job_ar', j.name_ar, 'manager_en', m.full_name_en, 'manager_ar', m.full_name_ar,
      'max_end', (e.join_date + make_interval(months => hr.probation_max_months(a.category_id)) - interval '1 day')::date,
      'can_decide', hr.has_perm('EMP_WRITE') and not hr.is_me(e.id)) order by e.probation_end_date nulls last)
    from hr.employees e
    -- the assignment in force, or the first one for someone who has not joined yet
    left join hr.employee_assignments a on a.id = (select a2.id from hr.employee_assignments a2 where a2.employee_id = e.id
                                                   and (a2.effective_to is null or a2.effective_to >= hr.today()) order by a2.effective_from limit 1)
    left join hr.job_titles j on j.id = a.job_title_id
    left join hr.employees m on m.id = a.manager_id
    where e.status = 'PROBATION'
      and (hr.has_perm('REC_READ') or hr.has_perm('EMP_READ') or e.id in (select employee_id from hr.team_of(hr.my_employee_id()))
           or (a.manager_id is not null and a.manager_id = hr.my_employee_id()))), '[]'::jsonb);
end $$;

-- Extend probation within the legal maximum (counted from the joining date).
create or replace function public.hr_extend_probation(p_employee uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e hr.employees; a hr.employee_assignments; v_new date := hr.jdate(p,'probation_end_date'); v_max date;
begin
  perform hr.require_perm('EMP_WRITE');
  select * into e from hr.employees where id = p_employee for update;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if hr.is_me(p_employee) then raise exception 'NOT_ALLOWED: You cannot change your own probation.' using errcode = '42501'; end if;
  if e.status <> 'PROBATION' then raise exception 'INVALID: The employee is not on probation.'; end if;
  if v_new is null then raise exception 'REQUIRED: New end date is required.'; end if;
  if coalesce(length(hr.jtext(p,'reason')), 0) < 10 then raise exception 'REQUIRED: Give the reason (at least 10 characters).'; end if;
  select * into a from hr.employee_assignments a2 where a2.employee_id = p_employee and (a2.effective_to is null or a2.effective_to >= hr.today())
   order by a2.effective_from limit 1;
  v_max := (e.join_date + make_interval(months => hr.probation_max_months(a.category_id)) - interval '1 day')::date;
  if v_new > v_max then
    raise exception 'PROBATION_LIMIT: Probation cannot go beyond % (the legal maximum from the joining date).', to_char(v_max, 'DD/MM/YYYY');
  end if;
  if v_new <= coalesce(e.probation_end_date, e.join_date) then raise exception 'INVALID: The new date must be after the current end date.'; end if;
  update hr.employees set probation_end_date = v_new where id = p_employee;
  perform hr.add_event(p_employee, 'PERSONAL_UPDATE', hr.today(), jsonb_build_object('probation_extended_to', v_new, 'reason', hr.jtext(p,'reason')));
  return public.hr_list_probation();
end $$;

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
create or replace function public.hr_recruitment_settings()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('REC_READ');
  return (select value from hr.settings where key = 'recruitment');
end $$;

create or replace function public.hr_save_recruitment_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select value from hr.settings where key = 'recruitment'); k text; t jsonb; x jsonb;
begin
  perform hr.require_perm('REC_APPROVE');
  if p ? 'probation_reminder_days' then
    if hr.jint(p,'probation_reminder_days') not between 1 and 60 then raise exception 'INVALID: Reminder days must be 1–60.'; end if;
    v := v || jsonb_build_object('probation_reminder_days', hr.jint(p,'probation_reminder_days'));
  end if;
  -- probation maxima are legal limits: they can be lowered (company policy) but never raised above the law
  if p ? 'probation_monthly_max_months' then
    if hr.jint(p,'probation_monthly_max_months') not between 0 and 3 then raise exception 'INVALID: Monthly-paid probation may be 0–3 months.'; end if;
    v := v || jsonb_build_object('probation_monthly_max_months', hr.jint(p,'probation_monthly_max_months'));
  end if;
  if p ? 'probation_other_max_months' then
    if hr.jint(p,'probation_other_max_months') not between 0 and 2 then raise exception 'INVALID: Probation for others may be 0–2 months.'; end if;
    v := v || jsonb_build_object('probation_other_max_months', hr.jint(p,'probation_other_max_months'));
  end if;
  if p ? 'onboarding' then
    foreach k in array array['EXPAT_ABROAD','EXPAT_IN_OMAN','OMANI'] loop
      t := p->'onboarding'->k;
      continue when t is null;
      if jsonb_typeof(t) <> 'array' then raise exception 'INVALID: Checklist % must be a list.', k; end if;
      for x in select * from jsonb_array_elements(t) loop
        if coalesce(x->>'code','') !~ '^[A-Z0-9_]{2,30}$' or coalesce(btrim(x->>'en'),'') = '' then
          raise exception 'INVALID: Each step needs a code (capital letters) and an English title.';
        end if;
        if (x->>'days') is not null and (x->>'days') !~ '^-?\d{1,3}$' then raise exception 'INVALID: Days must be a whole number.'; end if;
      end loop;
      v := jsonb_set(v, array['onboarding', k], t, true);
    end loop;
  end if;
  update hr.settings set value = v, updated_by = auth.uid(), updated_at = now() where key = 'recruitment';
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Tasks and dashboard: add requisitions, offers and interviews
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_my_tasks()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_res jsonb;
begin
  perform hr.require_user();
  select jsonb_build_object(
    'leave', coalesce((select jsonb_agg(hr.leave_json(r) order by r.start_date) from hr.leave_requests r
                       where r.status like 'PENDING%' and hr.can_decide(r.status, r.employee_id, r.requested_by, 'LEAVE_APPROVE')), '[]'::jsonb),
    'corrections', coalesce((select jsonb_agg(hr.correction_json(c) order by c.work_date) from hr.attendance_corrections c
                       where c.status like 'PENDING%' and hr.can_decide(c.status, c.employee_id, c.requested_by, 'ATT_APPROVE')), '[]'::jsonb),
    'overtime', coalesce((select jsonb_agg(hr.overtime_json(o) order by o.work_date) from hr.overtime_requests o
                       where o.status like 'PENDING%' and hr.can_decide(o.status, o.employee_id, o.requested_by, 'ATT_APPROVE')), '[]'::jsonb),
    'adjustments', case when hr.has_perm('LEAVE_APPROVE') then coalesce((select jsonb_agg(hr.adjustment_json(a) order by a.proposed_at)
                       from hr.leave_adjustments a where a.status = 'PENDING' and a.proposed_by <> auth.uid() and not hr.is_me(a.employee_id)), '[]'::jsonb)
                       else '[]'::jsonb end,
    'rules', case when hr.has_perm('RULES_APPROVE') then coalesce((select jsonb_agg(hr.time_rule_json(t)) from hr.time_rules t
                       where t.status = 'PENDING' and t.proposed_by is distinct from auth.uid()), '[]'::jsonb) else '[]'::jsonb end,
    'pay_rules', case when hr.has_perm('RULES_APPROVE') then coalesce((select jsonb_agg(hr.pay_rule_json(t)) from hr.pay_rules t
                       where t.status = 'PENDING' and t.proposed_by is distinct from auth.uid()), '[]'::jsonb) else '[]'::jsonb end,
    'payroll', coalesce((select jsonb_agg(j order by j->>'period_start') from (select hr.run_json(r) j from hr.payroll_runs r
                       where r.status in ('CALCULATED','VERIFIED')) t
                       where (j->>'can_verify')::boolean or (j->>'can_approve')::boolean), '[]'::jsonb),
    'loans', case when hr.has_perm('PAY_APPROVE') then coalesce((select jsonb_agg(hr.loan_json(l) order by l.proposed_at) from hr.employee_loans l
                       where l.status = 'PENDING' and l.proposed_by <> auth.uid() and not hr.is_me(l.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'pay_adjustments', case when hr.has_perm('PAY_APPROVE') then coalesce((select jsonb_agg(hr.pay_adj_json(a) order by a.proposed_at) from hr.payroll_adjustments a
                       where a.status = 'PENDING' and a.proposed_by <> auth.uid() and not hr.is_me(a.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'settlements', case when hr.has_perm('PAY_APPROVE') then coalesce((select jsonb_agg(hr.settlement_json(s) order by s.prepared_at) from hr.final_settlements s
                       where s.status = 'PREPARED' and s.prepared_by <> auth.uid() and not hr.is_me(s.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'changes', case when hr.has_perm('SS_APPROVE') then coalesce((select jsonb_agg(hr.change_json(c) order by c.due_date, c.requested_at) from hr.change_requests c
                       where c.status = 'PENDING' and c.requested_by <> auth.uid() and not hr.is_me(c.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'letters', case when hr.has_perm('LETTER_PREPARE') or hr.has_perm('LETTER_APPROVE') then coalesce((select jsonb_agg(j - 'snapshot' order by j->>'requested_at')
                       from (select hr.letter_json(l) j from hr.letters l where l.status in ('REQUESTED','PREPARED')) t
                       where (j->>'can_prepare')::boolean or (j->>'can_approve')::boolean), '[]'::jsonb) else '[]'::jsonb end,
    'requisitions', case when hr.has_perm('REC_APPROVE') then coalesce((select jsonb_agg(hr.requisition_json(r) order by r.requested_at)
                       from hr.job_requisitions r where r.status = 'PENDING' and r.requested_by <> auth.uid()), '[]'::jsonb) else '[]'::jsonb end,
    'offers', case when hr.has_perm('REC_APPROVE') then coalesce((select jsonb_agg(hr.offer_json(o) || jsonb_build_object('full_name_en', c.full_name_en,
                         'full_name_ar', c.full_name_ar) order by o.prepared_at)
                       from hr.job_offers o join hr.applications a on a.id = o.application_id join hr.candidates c on c.id = a.candidate_id
                       where o.status = 'PENDING' and o.prepared_by <> auth.uid()), '[]'::jsonb) else '[]'::jsonb end,
    'interviews', coalesce((select jsonb_agg(hr.interview_json(i) || jsonb_build_object('full_name_en', c.full_name_en, 'full_name_ar', c.full_name_ar)
                         order by i.scheduled_at)
                       from hr.interviews i join hr.applications a on a.id = i.application_id join hr.candidates c on c.id = a.candidate_id
                       where i.interviewer_id = auth.uid() and i.status = 'SCHEDULED' and i.scheduled_at < now()), '[]'::jsonb))
  into v_res;
  return v_res || jsonb_build_object('count',
    jsonb_array_length(v_res->'leave') + jsonb_array_length(v_res->'corrections') + jsonb_array_length(v_res->'overtime')
    + jsonb_array_length(v_res->'adjustments') + jsonb_array_length(v_res->'rules') + jsonb_array_length(v_res->'pay_rules')
    + jsonb_array_length(v_res->'payroll') + jsonb_array_length(v_res->'loans') + jsonb_array_length(v_res->'pay_adjustments')
    + jsonb_array_length(v_res->'settlements') + jsonb_array_length(v_res->'changes') + jsonb_array_length(v_res->'letters')
    + jsonb_array_length(v_res->'requisitions') + jsonb_array_length(v_res->'offers') + jsonb_array_length(v_res->'interviews'));
end $$;

create or replace function public.hr_time_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := hr.my_employee_id(); v_today date := hr.today(); v_res jsonb := '{}'::jsonb; v_tasks jsonb;
begin
  perform hr.require_user();
  if hr.has_perm('ATT_READ') or exists (select 1 from hr.team_of(v_me)) then
    v_res := v_res || jsonb_build_object('today', (
      select jsonb_build_object(
        'date', v_today,
        'present', count(*) filter (where a.status = 'PRESENT'),
        'absent', count(*) filter (where a.status = 'ABSENT'),
        'missing', count(*) filter (where a.status = 'MISSING_PUNCH'),
        'late', count(*) filter (where a.late_minutes > 0),
        'leave', count(*) filter (where a.status = 'LEAVE'),
        'off', count(*) filter (where a.status in ('REST','HOLIDAY')),
        'scope', case when hr.has_perm('ATT_READ') then 'ALL' else 'TEAM' end)
      from hr.attendance_days a
      where a.work_date = v_today
        and a.employee_id in (select employee_id from hr.visible_employees('ATT_READ', null) where employee_id is distinct from
                              case when hr.has_perm('ATT_READ') then null else v_me end)));
    v_res := v_res || jsonb_build_object('away_next_14', coalesce((
      select jsonb_agg(hr.emp_brief(r.employee_id) || jsonb_build_object('leave_type', r.leave_type, 'name_en', t.name_en, 'name_ar', t.name_ar,
               'start_date', r.start_date, 'end_date', r.end_date, 'status', r.status) order by r.start_date)
      from hr.leave_requests r join hr.leave_types t on t.code = r.leave_type
      where r.status in ('APPROVED','PENDING_MANAGER','PENDING_HR') and r.start_date <= v_today + 14 and r.end_date >= v_today
        and r.employee_id in (select employee_id from hr.visible_employees('LEAVE_READ', null))
        and r.employee_id is distinct from v_me), '[]'::jsonb));
  end if;
  if v_me is not null then
    v_res := v_res || jsonb_build_object('mine', jsonb_build_object(
      'today', (select hr.attendance_json(a) from hr.attendance_days a where a.employee_id = v_me and a.work_date = v_today),
      'annual', hr.leave_balance(v_me, 'ANNUAL', v_today),
      'sick', hr.leave_balance(v_me, 'SICK', v_today),
      'pending', (select count(*) from hr.leave_requests r where r.employee_id = v_me and r.status like 'PENDING%'),
      'next_leave', (select jsonb_build_object('leave_type', r.leave_type, 'name_en', t.name_en, 'name_ar', t.name_ar,
                       'start_date', r.start_date, 'end_date', r.end_date, 'status', r.status)
                     from hr.leave_requests r join hr.leave_types t on t.code = r.leave_type
                     where r.employee_id = v_me and r.status in ('APPROVED','PENDING_MANAGER','PENDING_HR') and r.end_date >= v_today
                     order by r.start_date limit 1),
      'last_payslip', (select jsonb_build_object('id', s.id, 'month', to_char(r.period_start,'YYYY-MM'), 'net', s.net)
                       from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
                       where s.employee_id = v_me and r.status in ('APPROVED','PAID') order by r.period_start desc limit 1),
      'requests_open', (select count(*) from hr.change_requests c where c.employee_id = v_me and c.status = 'PENDING')
                     + (select count(*) from hr.letters l where l.employee_id = v_me and l.status in ('REQUESTED','PREPARED')),
      'letters_ready', (select count(*) from hr.letters l where l.employee_id = v_me and l.status = 'ISSUED' and l.revoked_at is null
                          and l.approved_at > now() - interval '14 days')));
  end if;
  if hr.has_perm('PAY_READ') then
    v_res := v_res || jsonb_build_object('payroll', (select hr.run_json(r) from hr.payroll_runs r order by r.period_start desc, r.created_at desc limit 1));
  end if;
  if hr.has_perm('REC_READ') then
    v_res := v_res || jsonb_build_object('recruitment', jsonb_build_object(
      'open_requisitions', (select count(*) from hr.job_requisitions where status in ('APPROVED','ON_HOLD')),
      'open_positions', (select coalesce(sum(r.positions - (select count(*) from hr.applications a where a.requisition_id = r.id and a.stage = 'HIRED')), 0)
                         from hr.job_requisitions r where r.status in ('APPROVED','ON_HOLD')),
      'in_pipeline', (select count(*) from hr.applications a join hr.job_requisitions r on r.id = a.requisition_id
                      where a.stage not in ('HIRED','REJECTED','WITHDRAWN') and r.status in ('APPROVED','ON_HOLD')),
      'joining_30', (select count(*) from hr.job_offers o join hr.applications a on a.id = o.application_id
                     where o.status = 'ACCEPTED' and a.stage <> 'HIRED' and o.start_date <= v_today + 30),
      'onboarding_overdue', (select count(*) from hr.onboarding_tasks where status = 'PENDING' and due_date < v_today),
      'probation_due_30', (select count(*) from hr.employees where status = 'PROBATION' and probation_end_date <= v_today + 30)));
  end if;
  v_tasks := public.hr_list_my_tasks();
  return v_res || jsonb_build_object('tasks', jsonb_build_object(
    'leave', jsonb_array_length(v_tasks->'leave'), 'corrections', jsonb_array_length(v_tasks->'corrections'),
    'overtime', jsonb_array_length(v_tasks->'overtime'), 'adjustments', jsonb_array_length(v_tasks->'adjustments'),
    'rules', jsonb_array_length(v_tasks->'rules') + jsonb_array_length(v_tasks->'pay_rules'),
    'payroll', jsonb_array_length(v_tasks->'payroll'), 'loans', jsonb_array_length(v_tasks->'loans'),
    'pay_adjustments', jsonb_array_length(v_tasks->'pay_adjustments'), 'settlements', jsonb_array_length(v_tasks->'settlements'),
    'changes', jsonb_array_length(v_tasks->'changes'), 'letters', jsonb_array_length(v_tasks->'letters'),
    'requisitions', jsonb_array_length(v_tasks->'requisitions'), 'offers', jsonb_array_length(v_tasks->'offers'),
    'interviews', jsonb_array_length(v_tasks->'interviews'),
    'count', (v_tasks->>'count')::int));
end $$;

select hr.attach_audit();
select hr.secure_api();
