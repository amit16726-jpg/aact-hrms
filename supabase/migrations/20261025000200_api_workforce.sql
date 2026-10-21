-- AACT HRMS — 051 API: performance, training, discipline, assets & PPE, housing & transport, work injuries, exit.
-- Idempotent; no destructive statements.

-- ===========================================================================
-- PERFORMANCE
-- ===========================================================================
create or replace function hr.review_json(r hr.perf_reviews)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(r.employee_id) || jsonb_build_object(
    'id', r.id, 'cycle_id', r.cycle_id, 'cycle_name', c.name, 'period_start', c.period_start, 'period_end', c.period_end, 'due_date', c.due_date,
    'cycle_status', c.status, 'reviewer_id', r.reviewer_id, 'reviewer_en', m.full_name_en, 'reviewer_ar', m.full_name_ar,
    'status', r.status, 'goals', r.goals, 'self_comments', r.self_comments, 'manager_comments', r.manager_comments,
    'hr_comments', case when hr.has_perm('PERF_MANAGE') or r.status in ('ACK','DONE') then r.hr_comments end,
    'overall_rating', r.overall_rating, 'employee_comment', r.employee_comment, 'acknowledged_at', r.acknowledged_at,
    'is_mine', hr.is_me(r.employee_id), 'is_reviewer', coalesce(r.reviewer_id = hr.my_employee_id(), false),
    'can_self', c.status = 'OPEN' and r.status = 'SELF' and hr.is_me(r.employee_id),
    'can_manager', c.status = 'OPEN' and r.status in ('SELF','MANAGER') and (coalesce(r.reviewer_id = hr.my_employee_id(), false) or (hr.has_perm('PERF_MANAGE') and not hr.is_me(r.employee_id))),
    'can_finalise', c.status = 'OPEN' and r.status = 'HR' and hr.has_perm('PERF_MANAGE') and not hr.is_me(r.employee_id)
                    and r.reviewer_id is distinct from hr.my_employee_id(),
    'can_ack', r.status = 'ACK' and hr.is_me(r.employee_id))
  from hr.perf_cycles c left join hr.employees m on m.id = r.reviewer_id
  where c.id = r.cycle_id
$$;

create or replace function hr.can_see_review(r hr.perf_reviews)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(hr.has_perm('PERF_MANAGE') or hr.is_me(r.employee_id) or r.reviewer_id = hr.my_employee_id() or hr.is_my_team(r.employee_id), false)
$$;

create or replace function public.hr_list_perf_cycles()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object(
      'entity_code', (select code from hr.legal_entities where id = c.entity_id),
      'reviews', (select count(*) from hr.perf_reviews r where r.cycle_id = c.id),
      'done', (select count(*) from hr.perf_reviews r where r.cycle_id = c.id and r.status = 'DONE'),
      'by_status', (select coalesce(jsonb_object_agg(s, n), '{}'::jsonb) from (select r.status s, count(*) n from hr.perf_reviews r where r.cycle_id = c.id group by r.status) x),
      'avg_rating', (select round(avg(r.overall_rating), 2) from hr.perf_reviews r where r.cycle_id = c.id and r.overall_rating is not null))
      order by c.period_end desc)
    from hr.perf_cycles c where hr.has_perm('PERF_MANAGE') or c.status <> 'DRAFT'), '[]'::jsonb);
end $$;

create or replace function public.hr_save_perf_cycle(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); c hr.perf_cycles;
begin
  perform hr.require_perm('PERF_MANAGE');
  if hr.jtext(p,'name') is null then raise exception 'REQUIRED: Name the cycle.'; end if;
  if hr.jdate(p,'period_start') is null or hr.jdate(p,'period_end') is null then raise exception 'REQUIRED: Give the review period.'; end if;
  if hr.jdate(p,'period_end') < hr.jdate(p,'period_start') then raise exception 'INVALID: The period ends before it starts.'; end if;
  if v_id is null then
    if not exists (select 1 from hr.legal_entities where id = hr.juuid(p,'entity_id')) then raise exception 'REQUIRED: Choose the company.'; end if;
    insert into hr.perf_cycles(entity_id, name, period_start, period_end, due_date, self_review, created_by)
    values (hr.juuid(p,'entity_id'), hr.jtext(p,'name'), hr.jdate(p,'period_start'), hr.jdate(p,'period_end'), hr.jdate(p,'due_date'),
            hr.jbool(p,'self_review', true), auth.uid()) returning * into c;
  else
    update hr.perf_cycles set name = hr.jtext(p,'name'), period_start = hr.jdate(p,'period_start'), period_end = hr.jdate(p,'period_end'),
           due_date = hr.jdate(p,'due_date'), self_review = hr.jbool(p,'self_review', true)
     where id = v_id and status = 'DRAFT' returning * into c;
    if c.id is null then raise exception 'NOT_PENDING: Only a draft cycle can be changed.'; end if;
  end if;
  return public.hr_list_perf_cycles();
end $$;

-- Open: one review per employee on the books at the period end (category counted), reviewer = line manager then.
create or replace function public.hr_open_perf_cycle(p_id uuid, p_goals jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c hr.perf_cycles; e record; n int := 0; v_goals jsonb := coalesce(p_goals, '[]'::jsonb); u uuid;
begin
  perform hr.require_perm('PERF_MANAGE');
  select * into c from hr.perf_cycles where id = p_id for update;
  if c.id is null then raise exception 'NOT_FOUND: Cycle not found.'; end if;
  if c.status <> 'DRAFT' then raise exception 'INVALID: The cycle is already open or closed.'; end if;
  if jsonb_typeof(v_goals) <> 'array' then raise exception 'INVALID: Goals must be a list.'; end if;
  for e in select emp.id, a.manager_id from hr.employees emp
           join hr.employee_assignments a on a.employee_id = emp.id and a.effective_from <= c.period_end and (a.effective_to is null or a.effective_to >= c.period_end)
           where emp.entity_id = c.entity_id and emp.status in ('ACTIVE','PROBATION','NOTICE','SUSPENDED') and emp.join_date <= c.period_end loop
    insert into hr.perf_reviews(cycle_id, employee_id, reviewer_id, status, goals)
    values (c.id, e.id, e.manager_id, case when c.self_review then 'SELF' else 'MANAGER' end,
            (select coalesce(jsonb_agg(jsonb_build_object('title', g->>'title', 'weight', coalesce(nullif(g->>'weight','')::numeric, 1))), '[]'::jsonb)
             from jsonb_array_elements(v_goals) g where coalesce(btrim(g->>'title'),'') <> ''))
    on conflict (cycle_id, employee_id) do nothing;
    get diagnostics n = row_count;
    u := case when c.self_review then hr.employee_user(e.id) else hr.line_manager_user(e.id) end;
    if u is not null then
      perform hr.notify(u, 'TASK', 'NORMAL', 'Performance review open: ' || c.name, 'التقييم مفتوح: ' || c.name, null, null, '/performance', 'PERF:' || c.id || ':' || e.id);
    end if;
  end loop;
  update hr.perf_cycles set status = 'OPEN', opened_at = now() where id = p_id;
  return public.hr_list_perf_cycles();
end $$;

create or replace function public.hr_close_perf_cycle(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform hr.require_perm('PERF_MANAGE');
  update hr.perf_cycles set status = 'CLOSED', closed_at = now() where id = p_id and status = 'OPEN';
  if not found then raise exception 'INVALID: Only an open cycle can be closed.'; end if;
  return public.hr_list_perf_cycles();
end $$;

create or replace function public.hr_list_perf_reviews(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_scope text := coalesce(hr.jtext(p,'scope'), 'mine'); v_me uuid := hr.my_employee_id();
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.review_json(r) order by c.period_end desc, r.status) from hr.perf_reviews r join hr.perf_cycles c on c.id = r.cycle_id
    where hr.can_see_review(r)
      and (hr.juuid(p,'cycle_id') is null or r.cycle_id = hr.juuid(p,'cycle_id'))
      and case v_scope when 'mine' then r.employee_id = v_me
                       when 'team' then r.reviewer_id = v_me or hr.is_my_team(r.employee_id)
                       else hr.has_perm('PERF_MANAGE') end), '[]'::jsonb);
end $$;

create or replace function public.hr_get_perf_review(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r hr.perf_reviews;
begin
  perform hr.require_user();
  select * into r from hr.perf_reviews where id = p_id;
  if r.id is null then raise exception 'NOT_FOUND: Review not found.'; end if;
  if not hr.can_see_review(r) then raise exception 'NOT_ALLOWED: You cannot see this review.' using errcode = '42501'; end if;
  return hr.review_json(r) || jsonb_build_object('plans', coalesce((select jsonb_agg(to_jsonb(x) order by x.issued_on desc) from hr.perf_plans x where x.review_id = r.id), '[]'::jsonb));
end $$;

-- One entry point for each step: SELF (employee), MANAGER (line manager or HR), FINALISE (HR), ACK (employee).
create or replace function public.hr_save_perf_review(p_id uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.perf_reviews; c hr.perf_cycles; v_step text := upper(coalesce(hr.jtext(p,'step'), '')); v_submit boolean := hr.jbool(p,'submit');
        g jsonb; v_goals jsonb := '[]'::jsonb; v_rating numeric;
begin
  perform hr.require_user();
  select * into r from hr.perf_reviews where id = p_id for update;
  if r.id is null then raise exception 'NOT_FOUND: Review not found.'; end if;
  select * into c from hr.perf_cycles where id = r.cycle_id;
  if v_step <> 'ACK' and c.status <> 'OPEN' then raise exception 'INVALID: The cycle is not open.'; end if;
  if v_step in ('SELF','MANAGER') and p ? 'goals' then
    if jsonb_typeof(p->'goals') <> 'array' or jsonb_array_length(p->'goals') > 15 then raise exception 'INVALID: Up to 15 goals.'; end if;
    for g in select * from jsonb_array_elements(p->'goals') loop
      if coalesce(btrim(g->>'title'), '') = '' then raise exception 'REQUIRED: Each goal needs a title.'; end if;
      if nullif(g->>'rating','') is not null and (g->>'rating') !~ '^[1-5]$' then raise exception 'INVALID: Ratings are 1 to 5.'; end if;
      if nullif(g->>'self_rating','') is not null and (g->>'self_rating') !~ '^[1-5]$' then raise exception 'INVALID: Ratings are 1 to 5.'; end if;
      if nullif(g->>'weight','') is not null and (g->>'weight') !~ '^\d{1,3}(\.\d+)?$' then raise exception 'INVALID: Weight must be a number.'; end if;
      v_goals := v_goals || jsonb_build_array(jsonb_build_object('title', btrim(g->>'title'), 'weight', coalesce(nullif(g->>'weight','')::numeric, 1),
        'self_rating', nullif(g->>'self_rating','')::int, 'rating', nullif(g->>'rating','')::int, 'comment', nullif(btrim(coalesce(g->>'comment','')), '')));
    end loop;
  end if;
  if v_step = 'SELF' then
    if not (r.status = 'SELF' and hr.is_me(r.employee_id)) then raise exception 'NOT_ALLOWED: This is not your self-assessment to edit.' using errcode = '42501'; end if;
    -- the employee may add self-ratings and comments but not the manager's ratings
    if p ? 'goals' then
      select coalesce(jsonb_agg(x - 'rating' || jsonb_build_object('rating', null)), '[]'::jsonb) into v_goals from jsonb_array_elements(v_goals) x;
    end if;
    update hr.perf_reviews set goals = case when p ? 'goals' then v_goals else goals end, self_comments = hr.jtext(p,'self_comments'),
           status = case when v_submit then 'MANAGER' else status end, submitted_self_at = case when v_submit then now() else submitted_self_at end
     where id = p_id returning * into r;
    if v_submit then
      perform hr.notify(hr.line_manager_user(r.employee_id), 'TASK', 'NORMAL', 'Self-assessment ready to review', 'التقييم الذاتي جاهز للمراجعة',
        null, null, '/performance/review/' || r.id, 'PERFS:' || r.id);
    end if;
  elsif v_step = 'MANAGER' then
    if not (r.status in ('SELF','MANAGER') and (coalesce(r.reviewer_id = hr.my_employee_id(), false) or (hr.has_perm('PERF_MANAGE') and not hr.is_me(r.employee_id)))) then
      raise exception 'NOT_ALLOWED: Only the line manager (or HR) reviews this.' using errcode = '42501';
    end if;
    if hr.is_me(r.employee_id) then raise exception 'SELF_APPROVAL: You cannot review yourself.' using errcode = '42501'; end if;
    if p ? 'goals' then
      -- keep the employee's self-ratings
      select coalesce(jsonb_agg(x || jsonb_build_object('self_rating', (select o->'self_rating' from jsonb_array_elements(r.goals) o where o->>'title' = x->>'title' limit 1))), '[]'::jsonb)
        into v_goals from jsonb_array_elements(v_goals) x;
    else v_goals := r.goals; end if;
    v_rating := hr.goals_rating(v_goals);
    if v_submit then
      if jsonb_array_length(v_goals) = 0 then raise exception 'REQUIRED: Add at least one goal.'; end if;
      if exists (select 1 from jsonb_array_elements(v_goals) x where nullif(x->>'rating','') is null) then raise exception 'REQUIRED: Rate every goal before submitting.'; end if;
      if coalesce(length(hr.jtext(p,'manager_comments')), 0) < 10 then raise exception 'REQUIRED: Write the manager''s comments (at least 10 characters).'; end if;
    end if;
    update hr.perf_reviews set goals = v_goals, manager_comments = hr.jtext(p,'manager_comments'), overall_rating = v_rating,
           status = case when v_submit then 'HR' else 'MANAGER' end, submitted_manager_at = case when v_submit then now() else submitted_manager_at end
     where id = p_id returning * into r;
  elsif v_step = 'FINALISE' then
    perform hr.require_perm('PERF_MANAGE');
    if r.status <> 'HR' then raise exception 'NOT_PENDING: The manager has not submitted this review yet.'; end if;
    if hr.is_me(r.employee_id) or coalesce(r.reviewer_id = hr.my_employee_id(), false) then raise exception 'SELF_APPROVAL: Someone else must finalise this review.' using errcode = '42501'; end if;
    update hr.perf_reviews set hr_comments = hr.jtext(p,'hr_comments'), status = 'ACK', finalised_by = auth.uid(), finalised_at = now()
     where id = p_id returning * into r;
    perform hr.notify(hr.employee_user(r.employee_id), 'INFO', 'NORMAL', 'Your performance review is ready', 'تقييم أدائك جاهز',
      null, null, '/performance/review/' || r.id, 'PERFF:' || r.id);
  elsif v_step = 'RETURN' then
    perform hr.require_perm('PERF_MANAGE');
    if r.status <> 'HR' then raise exception 'NOT_PENDING: Only a review waiting for HR can be returned.'; end if;
    update hr.perf_reviews set status = 'MANAGER', hr_comments = hr.jtext(p,'hr_comments') where id = p_id returning * into r;
  elsif v_step = 'ACK' then
    if not (r.status = 'ACK' and hr.is_me(r.employee_id)) then raise exception 'NOT_ALLOWED: Only the employee acknowledges the review.' using errcode = '42501'; end if;
    update hr.perf_reviews set status = 'DONE', employee_comment = hr.jtext(p,'employee_comment'), acknowledged_at = now() where id = p_id returning * into r;
  else
    raise exception 'INVALID: Unknown step.';
  end if;
  return public.hr_get_perf_review(r.id);
end $$;

-- Improvement plan (poor-performance notice): at least 6 months to improve before an outcome can be "not improved".
create or replace function hr.plan_json(x hr.perf_plans)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(x.employee_id) || to_jsonb(x) || jsonb_build_object('issued_by_name', hr.user_label(x.issued_by), 'closed_by_name', hr.user_label(x.closed_by),
    'days_left', x.ends_on - hr.today(), 'can_close', x.status = 'ACTIVE' and hr.has_perm('PERF_MANAGE') and not hr.is_me(x.employee_id),
    'can_ack', x.status = 'ACTIVE' and x.acknowledged_at is null and hr.is_me(x.employee_id))
$$;

create or replace function public.hr_list_perf_plans()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.plan_json(x) order by (x.status = 'ACTIVE') desc, x.ends_on) from hr.perf_plans x
    where hr.has_perm('PERF_MANAGE') or hr.is_me(x.employee_id) or hr.is_my_team(x.employee_id)), '[]'::jsonb);
end $$;

create or replace function public.hr_issue_perf_plan(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_from date := coalesce(hr.jdate(p,'issued_on'), hr.today()); v_to date := hr.jdate(p,'ends_on');
        v_min int := hr.policy_num('pip_min_months', 6)::int; x hr.perf_plans;
begin
  perform hr.require_user();
  if not (hr.has_perm('PERF_MANAGE') or hr.is_my_team(v_emp)) then raise exception 'NOT_ALLOWED: Only HR or the line manager can issue a plan.' using errcode = '42501'; end if;
  if hr.is_me(v_emp) then raise exception 'NOT_ALLOWED: You cannot issue a plan to yourself.' using errcode = '42501'; end if;
  if not exists (select 1 from hr.employees where id = v_emp and status <> 'SEPARATED') then raise exception 'NOT_FOUND: Employee not found.'; end if;
  v_to := coalesce(v_to, (v_from + make_interval(months => v_min))::date);
  if v_to < (v_from + make_interval(months => v_min))::date then
    raise exception 'PIP_TOO_SHORT: The employee must have at least % months to improve (Labour Law).', v_min;
  end if;
  if coalesce(length(hr.jtext(p,'areas')), 0) < 10 then raise exception 'REQUIRED: Describe what must improve (at least 10 characters).'; end if;
  if exists (select 1 from hr.perf_plans where employee_id = v_emp and status = 'ACTIVE') then raise exception 'PENDING_EXISTS: This employee already has an active plan.'; end if;
  insert into hr.perf_plans(employee_id, review_id, issued_on, ends_on, areas, support, issued_by)
  values (v_emp, hr.juuid(p,'review_id'), v_from, v_to, hr.jtext(p,'areas'), hr.jtext(p,'support'), auth.uid()) returning * into x;
  perform hr.notify(hr.employee_user(v_emp), 'INFO', 'HIGH', 'Performance improvement plan until ' || to_char(v_to, 'DD/MM/YYYY'),
    'خطة تحسين الأداء حتى ' || to_char(v_to, 'DD/MM/YYYY'), null, null, '/performance?tab=plans', 'PIP:' || x.id);
  return hr.plan_json(x);
end $$;

create or replace function public.hr_close_perf_plan(p_id uuid, p_outcome text, p_note text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x hr.perf_plans; v_out text := upper(coalesce(p_outcome,''));
begin
  perform hr.require_perm('PERF_MANAGE');
  select * into x from hr.perf_plans where id = p_id for update;
  if x.id is null then raise exception 'NOT_FOUND: Plan not found.'; end if;
  if x.status <> 'ACTIVE' then raise exception 'NOT_PENDING: This plan is already closed.'; end if;
  if hr.is_me(x.employee_id) then raise exception 'SELF_APPROVAL: You cannot close your own plan.' using errcode = '42501'; end if;
  if v_out not in ('IMPROVED','NOT_IMPROVED','CANCELLED') then raise exception 'INVALID: Unknown outcome.'; end if;
  if v_out = 'NOT_IMPROVED' and hr.today() < x.ends_on then
    raise exception 'PIP_TOO_SHORT: "Not improved" can be recorded only after the improvement period ends (%).', to_char(x.ends_on, 'DD/MM/YYYY');
  end if;
  if coalesce(length(btrim(coalesce(p_note,''))), 0) < 10 then raise exception 'REQUIRED: Record the outcome (at least 10 characters).'; end if;
  update hr.perf_plans set status = v_out, outcome_note = btrim(p_note), closed_by = auth.uid(), closed_at = now() where id = p_id returning * into x;
  return hr.plan_json(x);
end $$;

create or replace function public.hr_ack_perf_plan(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x hr.perf_plans;
begin
  perform hr.require_user();
  update hr.perf_plans set acknowledged_at = now() where id = p_id and hr.is_me(employee_id) and acknowledged_at is null returning * into x;
  if x.id is null then raise exception 'NOT_FOUND: No plan of yours to acknowledge.'; end if;
  return hr.plan_json(x);
end $$;

-- ===========================================================================
-- TRAINING
-- ===========================================================================
create or replace function public.hr_list_courses()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(to_jsonb(c) || jsonb_build_object(
      'completed', (select count(distinct r.employee_id) from hr.training_records r where r.course_id = c.id and r.status = 'COMPLETED'),
      'expiring_60', (select count(*) from hr.expiry_items(hr.today()) x where x.source = 'TRAINING' and x.doc_type = 'TRAINING:' || c.code and x.days_left <= 60))
      order by c.mandatory desc, c.code) from hr.training_courses c), '[]'::jsonb);
end $$;

create or replace function public.hr_save_course(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); v_code text := upper(hr.jtext(p,'code'));
begin
  perform hr.require_perm('TRAIN_WRITE');
  if v_code is null or v_code !~ '^[A-Z0-9_-]{2,20}$' then raise exception 'INVALID: Code: 2–20 capital letters, digits, - or _.'; end if;
  if hr.jtext(p,'name_en') is null then raise exception 'REQUIRED: Course name is required.'; end if;
  if coalesce(upper(hr.jtext(p,'category')), 'GENERAL') not in ('SAFETY','TECHNICAL','COMPLIANCE','SOFT_SKILLS','GENERAL') then raise exception 'INVALID: Unknown category.'; end if;
  if hr.jint(p,'validity_months') is not null and hr.jint(p,'validity_months') not between 1 and 120 then raise exception 'INVALID: Validity 1–120 months.'; end if;
  if exists (select 1 from hr.training_courses where code = v_code and id is distinct from v_id) then raise exception 'DUPLICATE: This code is already used.'; end if;
  if v_id is null then
    insert into hr.training_courses(code, name_en, name_ar, provider, category, validity_months, mandatory, is_active)
    values (v_code, hr.jtext(p,'name_en'), hr.jtext(p,'name_ar'), hr.jtext(p,'provider'), coalesce(upper(hr.jtext(p,'category')), 'GENERAL'),
            hr.jint(p,'validity_months'), hr.jbool(p,'mandatory'), hr.jbool(p,'is_active', true));
  else
    update hr.training_courses set code = v_code, name_en = hr.jtext(p,'name_en'), name_ar = hr.jtext(p,'name_ar'), provider = hr.jtext(p,'provider'),
      category = coalesce(upper(hr.jtext(p,'category')), 'GENERAL'), validity_months = hr.jint(p,'validity_months'), mandatory = hr.jbool(p,'mandatory'),
      is_active = hr.jbool(p,'is_active', true) where id = v_id;
    if not found then raise exception 'NOT_FOUND: Course not found.'; end if;
  end if;
  return public.hr_list_courses();
end $$;

create or replace function public.hr_list_training(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id');
begin
  perform hr.require_user();
  if v_emp is not null then perform hr.require_employee_access(v_emp);
  elsif not (hr.has_perm('TRAIN_WRITE') or hr.has_perm('EMP_READ')) then v_emp := coalesce(hr.my_employee_id(), '00000000-0000-0000-0000-000000000000'::uuid); end if;
  return coalesce((select jsonb_agg(hr.emp_brief(r.employee_id) || jsonb_build_object('id', r.id, 'course_id', r.course_id, 'course_code', c.code,
      'course_en', c.name_en, 'course_ar', c.name_ar, 'category', c.category, 'mandatory', c.mandatory, 'status', r.status, 'planned_on', r.planned_on,
      'completed_on', r.completed_on, 'expires_on', r.expires_on, 'days_left', r.expires_on - hr.today(), 'certificate_no', r.certificate_no,
      'score', r.score, 'cost', case when hr.has_perm('TRAIN_WRITE') then r.cost end, 'notes', r.notes,
      'superseded', exists (select 1 from hr.training_records r2 where r2.employee_id = r.employee_id and r2.course_id = r.course_id and r2.status = 'COMPLETED' and r2.completed_on > r.completed_on))
      order by coalesce(r.completed_on, r.planned_on) desc nulls last)
    from hr.training_records r join hr.training_courses c on c.id = r.course_id
    where (v_emp is null or r.employee_id = v_emp) and (hr.juuid(p,'course_id') is null or r.course_id = hr.juuid(p,'course_id'))
      and (hr.jint(p,'expiring_days') is null or (r.status = 'COMPLETED' and r.expires_on <= hr.today() + hr.jint(p,'expiring_days')))
      and r.status <> 'CANCELLED'
    limit 1000), '[]'::jsonb);
end $$;

-- Record a course for one or many employees at once (expiry from the course validity).
create or replace function public.hr_save_training(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c hr.training_courses; v_emp uuid; v_st text := upper(coalesce(hr.jtext(p,'status'), 'COMPLETED')); v_done date := hr.jdate(p,'completed_on'); n int := 0;
begin
  perform hr.require_perm('TRAIN_WRITE');
  if hr.juuid(p,'id') is not null then
    update hr.training_records set status = v_st, planned_on = hr.jdate(p,'planned_on'), completed_on = v_done,
      expires_on = coalesce(hr.jdate(p,'expires_on'), case when v_done is not null then (v_done + make_interval(months => (select validity_months from hr.training_courses where id = course_id)))::date end),
      certificate_no = hr.jtext(p,'certificate_no'), score = hr.jtext(p,'score'), cost = hr.jmoney(p,'cost'), notes = hr.jtext(p,'notes')
     where id = hr.juuid(p,'id');
    if not found then raise exception 'NOT_FOUND: Record not found.'; end if;
    return jsonb_build_object('saved', 1);
  end if;
  select * into c from hr.training_courses where id = hr.juuid(p,'course_id') and is_active;
  if c.id is null then raise exception 'REQUIRED: Choose an active course.'; end if;
  if v_st not in ('PLANNED','COMPLETED') then raise exception 'INVALID: Status must be planned or completed.'; end if;
  if v_st = 'COMPLETED' and v_done is null then raise exception 'REQUIRED: Completion date is required.'; end if;
  if v_done > hr.today() then raise exception 'INVALID: Completion date is in the future.'; end if;
  if jsonb_typeof(p->'employee_ids') <> 'array' or jsonb_array_length(p->'employee_ids') = 0 then raise exception 'REQUIRED: Choose at least one employee.'; end if;
  for v_emp in select (x #>> '{}')::uuid from jsonb_array_elements(p->'employee_ids') x loop
    if not exists (select 1 from hr.employees where id = v_emp) then raise exception 'NOT_FOUND: Employee not found.'; end if;
    insert into hr.training_records(employee_id, course_id, status, planned_on, completed_on, expires_on, certificate_no, score, cost, notes, created_by)
    values (v_emp, c.id, v_st, hr.jdate(p,'planned_on'), v_done,
            coalesce(hr.jdate(p,'expires_on'), case when v_done is not null and c.validity_months is not null then (v_done + make_interval(months => c.validity_months))::date end),
            hr.jtext(p,'certificate_no'), hr.jtext(p,'score'), hr.jmoney(p,'cost'), hr.jtext(p,'notes'), auth.uid());
    n := n + 1;
  end loop;
  return jsonb_build_object('saved', n);
end $$;

create or replace function public.hr_cancel_training(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform hr.require_perm('TRAIN_WRITE');
  update hr.training_records set status = 'CANCELLED' where id = p_id and status <> 'CANCELLED';
  if not found then raise exception 'NOT_FOUND: Record not found.'; end if;
  return jsonb_build_object('cancelled', 1);
end $$;

-- Mandatory courses missing or expired, per employee.
create or replace function public.hr_training_gaps()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('TRAIN_WRITE');
  return coalesce((select jsonb_agg(hr.emp_brief(e.id) || jsonb_build_object('course_code', c.code, 'course_en', c.name_en, 'course_ar', c.name_ar,
      'last_expired', (select max(r.expires_on) from hr.training_records r where r.employee_id = e.id and r.course_id = c.id and r.status = 'COMPLETED'))
      order by c.code, e.employee_no)
    from hr.employees e cross join hr.training_courses c
    where c.mandatory and c.is_active and e.status <> 'SEPARATED' and e.join_date <= hr.today()
      and not exists (select 1 from hr.training_records r where r.employee_id = e.id and r.course_id = c.id and r.status = 'COMPLETED'
                      and (r.expires_on is null or r.expires_on >= hr.today()))), '[]'::jsonb);
end $$;

-- ===========================================================================
-- DISCIPLINE
-- ===========================================================================
create or replace function hr.case_json(d hr.disciplinary_cases, p_full boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(d.employee_id) || jsonb_build_object('id', d.id, 'ref_no', d.ref_no, 'incident_date', d.incident_date, 'category', d.category,
    'description', d.description, 'status', d.status, 'investigation_notes', case when p_full then d.investigation_notes end,
    'employee_response', d.employee_response, 'response_at', d.response_at,
    'proposed_penalty', case when p_full then d.proposed_penalty end, 'proposed_days', case when p_full then d.proposed_days end,
    'proposed_by_name', case when p_full then hr.user_label(d.proposed_by) end,
    'penalty', d.penalty, 'penalty_days', d.penalty_days, 'decided_by_name', hr.user_label(d.decided_by), 'decided_at', d.decided_at,
    'decision_note', d.decision_note, 'adjustment_id', d.adjustment_id, 'appeal', d.appeal, 'appeal_at', d.appeal_at,
    'opened_by_name', case when p_full then hr.user_label(d.opened_by) end, 'created_at', d.created_at,
    'can_edit', p_full and d.status in ('DRAFT','INVESTIGATION') and hr.has_perm('DISC_WRITE') and not hr.is_me(d.employee_id),
    'can_propose', p_full and d.status = 'INVESTIGATION' and hr.has_perm('DISC_WRITE') and not hr.is_me(d.employee_id),
    'can_decide', p_full and d.status = 'PROPOSED' and hr.has_perm('DISC_APPROVE') and auth.uid() <> d.opened_by
                  and auth.uid() is distinct from d.proposed_by and not hr.is_me(d.employee_id),
    'can_respond', hr.is_me(d.employee_id) and ((d.status = 'INVESTIGATION' and d.employee_response is null) or (d.status = 'DECIDED' and d.appeal is null)))
$$;

create or replace function public.hr_list_cases(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_full boolean := hr.has_perm('DISC_READ');
begin
  perform hr.require_user();
  if v_full and hr.juuid(p,'employee_id') is not null then
    insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), hr.juuid(p,'employee_id'), 'DISCIPLINE', 'Viewed disciplinary cases');
  end if;
  return coalesce((select jsonb_agg(hr.case_json(d, v_full) order by (d.status in ('DRAFT','INVESTIGATION','PROPOSED')) desc, d.incident_date desc)
    from hr.disciplinary_cases d
    where (v_full or (hr.is_me(d.employee_id) and d.status <> 'DRAFT'))
      and (hr.juuid(p,'employee_id') is null or d.employee_id = hr.juuid(p,'employee_id'))
      and (hr.jtext(p,'status') is null or (hr.jtext(p,'status') = 'OPEN' and d.status in ('DRAFT','INVESTIGATION','PROPOSED')) or d.status = hr.jtext(p,'status'))), '[]'::jsonb);
end $$;

create or replace function public.hr_save_case(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); d hr.disciplinary_cases; v_cat text := upper(hr.jtext(p,'category'));
begin
  perform hr.require_perm('DISC_WRITE');
  if v_cat is null or v_cat not in ('ATTENDANCE','CONDUCT','SAFETY','PERFORMANCE','POLICY','OTHER') then raise exception 'REQUIRED: Choose the category.'; end if;
  if hr.jdate(p,'incident_date') is null or hr.jdate(p,'incident_date') > hr.today() then raise exception 'REQUIRED: Give the incident date (not in the future).'; end if;
  if coalesce(length(hr.jtext(p,'description')), 0) < 15 then raise exception 'REQUIRED: Describe what happened (at least 15 characters).'; end if;
  if v_id is null then
    if hr.is_me(hr.juuid(p,'employee_id')) then raise exception 'NOT_ALLOWED: You cannot open a case about yourself.' using errcode = '42501'; end if;
    if not exists (select 1 from hr.employees where id = hr.juuid(p,'employee_id')) then raise exception 'NOT_FOUND: Employee not found.'; end if;
    insert into hr.disciplinary_cases(ref_no, employee_id, incident_date, category, description, investigation_notes, opened_by)
    values (hr.next_ref('DC'), hr.juuid(p,'employee_id'), hr.jdate(p,'incident_date'), v_cat, hr.jtext(p,'description'), hr.jtext(p,'investigation_notes'), auth.uid())
    returning * into d;
  else
    update hr.disciplinary_cases set incident_date = hr.jdate(p,'incident_date'), category = v_cat, description = hr.jtext(p,'description'),
           investigation_notes = hr.jtext(p,'investigation_notes')
     where id = v_id and status in ('DRAFT','INVESTIGATION') returning * into d;
    if d.id is null then raise exception 'NOT_PENDING: Only an open case can be changed.'; end if;
  end if;
  return hr.case_json(d, true);
end $$;

-- Actions: INVESTIGATE (asks the employee for a written response), PROPOSE (penalty), DECIDE (by someone else), RETURN, DISMISS.
create or replace function public.hr_case_action(p_id uuid, p_action text, p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d hr.disciplinary_cases; v_act text := upper(coalesce(p_action,'')); v_pen text := upper(hr.jtext(p,'penalty')); v_days numeric := nullif(p->>'days','')::numeric;
        v_adj uuid; v_amt numeric; v_max_d numeric := hr.policy_num('discipline_max_deduction_days', 5); v_max_s numeric := hr.policy_num('discipline_max_suspension_days', 5);
begin
  perform hr.require_perm('DISC_WRITE');
  select * into d from hr.disciplinary_cases where id = p_id for update;
  if d.id is null then raise exception 'NOT_FOUND: Case not found.'; end if;
  if hr.is_me(d.employee_id) then raise exception 'NOT_ALLOWED: You cannot act on a case about yourself.' using errcode = '42501'; end if;
  if v_act = 'INVESTIGATE' then
    if d.status <> 'DRAFT' then raise exception 'INVALID: The investigation has already started.'; end if;
    update hr.disciplinary_cases set status = 'INVESTIGATION' where id = p_id returning * into d;
    perform hr.notify(hr.employee_user(d.employee_id), 'TASK', 'HIGH', 'Disciplinary case ' || d.ref_no || ': please give your written response',
      'قضية تأديبية ' || d.ref_no || ': يرجى تقديم ردك كتابياً', null, null, '/discipline/' || d.id, 'DCI:' || d.id);
  elsif v_act = 'PROPOSE' then
    if d.status <> 'INVESTIGATION' then raise exception 'INVALID: A penalty is proposed after the investigation.'; end if;
    if v_pen is null or v_pen not in ('VERBAL_WARNING','WRITTEN_WARNING','FINAL_WARNING','DEDUCTION','SUSPENSION','TERMINATION','NONE') then raise exception 'REQUIRED: Choose the penalty.'; end if;
    if v_pen = 'DEDUCTION' and (v_days is null or v_days <= 0 or v_days > v_max_d) then raise exception 'PENALTY_LIMIT: A deduction can be 0.5 to % days'' wage.', v_max_d; end if;
    if v_pen = 'SUSPENSION' and (v_days is null or v_days <= 0 or v_days > v_max_s) then raise exception 'PENALTY_LIMIT: A suspension can be 1 to % days.', v_max_s; end if;
    if d.employee_response is null and not hr.jbool(p,'no_response_confirmed') then
      raise exception 'RESPONSE_MISSING: The employee has not responded. Confirm that they were asked and did not respond.';
    end if;
    update hr.disciplinary_cases set status = 'PROPOSED', proposed_penalty = v_pen, proposed_days = case when v_pen in ('DEDUCTION','SUSPENSION') then v_days end,
           proposed_by = auth.uid(), proposed_at = now(), investigation_notes = coalesce(hr.jtext(p,'investigation_notes'), investigation_notes)
     where id = p_id returning * into d;
  elsif v_act = 'DECIDE' then
    perform hr.require_perm('DISC_APPROVE');
    if d.status <> 'PROPOSED' then raise exception 'NOT_PENDING: No proposed penalty to decide.'; end if;
    if auth.uid() = d.opened_by or auth.uid() = d.proposed_by then raise exception 'SELF_APPROVAL: Someone who did not open or propose must decide.' using errcode = '42501'; end if;
    v_pen := coalesce(v_pen, d.proposed_penalty); v_days := coalesce(v_days, d.proposed_days);
    if v_pen = 'DEDUCTION' and (v_days is null or v_days <= 0 or v_days > v_max_d) then raise exception 'PENALTY_LIMIT: A deduction can be 0.5 to % days'' wage.', v_max_d; end if;
    if v_pen = 'SUSPENSION' and (v_days is null or v_days <= 0 or v_days > v_max_s) then raise exception 'PENALTY_LIMIT: A suspension can be 1 to % days.', v_max_s; end if;
    if v_pen = 'DEDUCTION' then
      v_amt := round(v_days * hr.daily_gross(d.employee_id, hr.today()), 3);
      if v_amt <= 0 then raise exception 'NO_SALARY: No approved salary to calculate the deduction.'; end if;
      -- goes to payroll as a one-off deduction waiting for Finance approval (the 25 % limit applies there)
      insert into hr.payroll_adjustments(employee_id, period_start, kind, code, amount, reason, proposed_by)
      values (d.employee_id, (date_trunc('month', hr.today()) + interval '1 month')::date, 'DEDUCTION', 'PENALTY', v_amt,
              'Disciplinary case ' || d.ref_no || ': ' || v_days || ' day(s) wage', auth.uid())
      returning id into v_adj;
    end if;
    update hr.disciplinary_cases set status = 'DECIDED', penalty = v_pen, penalty_days = case when v_pen in ('DEDUCTION','SUSPENSION') then v_days end,
           decided_by = auth.uid(), decided_at = now(), decision_note = hr.jtext(p,'note'), adjustment_id = v_adj
     where id = p_id returning * into d;
    perform hr.notify(hr.employee_user(d.employee_id), 'INFO', 'HIGH', 'Decision on disciplinary case ' || d.ref_no, 'قرار في القضية التأديبية ' || d.ref_no,
      null, null, '/discipline/' || d.id, 'DCD:' || d.id);
  elsif v_act = 'RETURN' then
    perform hr.require_perm('DISC_APPROVE');
    if d.status <> 'PROPOSED' then raise exception 'NOT_PENDING: Only a proposed penalty can be returned.'; end if;
    update hr.disciplinary_cases set status = 'INVESTIGATION', decision_note = hr.jtext(p,'note') where id = p_id returning * into d;
  elsif v_act = 'DISMISS' then
    if d.status not in ('DRAFT','INVESTIGATION','PROPOSED') then raise exception 'INVALID: The case is already decided.'; end if;
    if coalesce(length(hr.jtext(p,'note')), 0) < 5 then raise exception 'REQUIRED: Give the reason for dismissing the case.'; end if;
    update hr.disciplinary_cases set status = 'DISMISSED', decision_note = hr.jtext(p,'note') where id = p_id returning * into d;
  else
    raise exception 'INVALID: Unknown action.';
  end if;
  return hr.case_json(d, true);
end $$;

-- The employee's right to be heard: written response during the investigation; appeal after the decision.
create or replace function public.hr_respond_case(p_id uuid, p_text text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d hr.disciplinary_cases; u record;
begin
  perform hr.require_user();
  if coalesce(length(btrim(coalesce(p_text,''))), 0) < 10 then raise exception 'REQUIRED: Write your response (at least 10 characters).'; end if;
  select * into d from hr.disciplinary_cases where id = p_id and hr.is_me(employee_id) for update;
  if d.id is null then raise exception 'NOT_FOUND: Case not found.'; end if;
  if d.status = 'INVESTIGATION' and d.employee_response is null then
    update hr.disciplinary_cases set employee_response = btrim(p_text), response_at = now() where id = p_id returning * into d;
  elsif d.status = 'DECIDED' and d.appeal is null then
    update hr.disciplinary_cases set appeal = btrim(p_text), appeal_at = now() where id = p_id returning * into d;
  else
    raise exception 'INVALID: This case is not waiting for your response.';
  end if;
  for u in select h.user_id from hr.users_with_perm('DISC_APPROVE') h loop
    perform hr.notify(u.user_id, 'TASK', 'NORMAL', 'Employee response on case ' || d.ref_no, 'رد الموظف على القضية ' || d.ref_no, null, null,
      '/discipline/' || d.id, 'DCR:' || d.id || ':' || coalesce(d.appeal_at, d.response_at));
  end loop;
  return hr.case_json(d, false);
end $$;

create or replace function public.hr_get_case(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare d hr.disciplinary_cases; v_full boolean := hr.has_perm('DISC_READ');
begin
  perform hr.require_user();
  select * into d from hr.disciplinary_cases where id = p_id;
  if d.id is null or not (v_full or (hr.is_me(d.employee_id) and d.status <> 'DRAFT')) then raise exception 'NOT_FOUND: Case not found.'; end if;
  return hr.case_json(d, v_full) || jsonb_build_object('history', case when v_full then coalesce((select jsonb_agg(jsonb_build_object('ref_no', x.ref_no,
      'incident_date', x.incident_date, 'category', x.category, 'penalty', x.penalty, 'status', x.status) order by x.incident_date desc)
      from hr.disciplinary_cases x where x.employee_id = d.employee_id and x.id <> d.id), '[]'::jsonb) else '[]'::jsonb end);
end $$;

-- ===========================================================================
-- ASSETS & PPE
-- ===========================================================================
create or replace function public.hr_list_asset_items()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(to_jsonb(i) || jsonb_build_object('issued', (select coalesce(sum(x.qty), 0) from hr.asset_issues x where x.item_id = i.id and x.status = 'ISSUED')) order by i.category, i.code)
    from hr.asset_items i), '[]'::jsonb);
end $$;

create or replace function public.hr_save_asset_item(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); v_code text := upper(hr.jtext(p,'code')); v_cat text := coalesce(upper(hr.jtext(p,'category')), 'PPE');
begin
  perform hr.require_perm('ASSET_WRITE');
  if v_code is null or v_code !~ '^[A-Z0-9_-]{2,20}$' then raise exception 'INVALID: Code: 2–20 capital letters, digits, - or _.'; end if;
  if hr.jtext(p,'name_en') is null then raise exception 'REQUIRED: Name is required.'; end if;
  if v_cat not in ('PPE','UNIFORM','IT','TOOL','VEHICLE','KEY','CARD','OTHER') then raise exception 'INVALID: Unknown category.'; end if;
  if exists (select 1 from hr.asset_items where code = v_code and id is distinct from v_id) then raise exception 'DUPLICATE: This code is already used.'; end if;
  if v_id is null then
    insert into hr.asset_items(code, name_en, name_ar, category, returnable, unit_cost, replace_months, is_active)
    values (v_code, hr.jtext(p,'name_en'), hr.jtext(p,'name_ar'), v_cat, hr.jbool(p,'returnable', true), hr.jmoney(p,'unit_cost'), hr.jint(p,'replace_months'), hr.jbool(p,'is_active', true));
  else
    update hr.asset_items set code = v_code, name_en = hr.jtext(p,'name_en'), name_ar = hr.jtext(p,'name_ar'), category = v_cat, returnable = hr.jbool(p,'returnable', true),
      unit_cost = hr.jmoney(p,'unit_cost'), replace_months = hr.jint(p,'replace_months'), is_active = hr.jbool(p,'is_active', true) where id = v_id;
    if not found then raise exception 'NOT_FOUND: Item not found.'; end if;
  end if;
  return public.hr_list_asset_items();
end $$;

create or replace function hr.issue_json(x hr.asset_issues)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(x.employee_id) || to_jsonb(x) || jsonb_build_object('item_code', i.code, 'item_en', i.name_en, 'item_ar', i.name_ar, 'category', i.category,
    'returnable', i.returnable, 'unit_cost', i.unit_cost, 'overdue', x.status = 'ISSUED' and x.due_return_on < hr.today(),
    'replace_due', case when i.replace_months is not null and x.status in ('ISSUED','CONSUMED') then (x.issued_on + make_interval(months => i.replace_months))::date end,
    'issued_by_name', hr.user_label(x.issued_by))
  from hr.asset_items i where i.id = x.item_id
$$;

create or replace function public.hr_list_asset_issues(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id');
begin
  perform hr.require_user();
  if v_emp is not null then perform hr.require_employee_access(v_emp);
  elsif not (hr.has_perm('ASSET_WRITE') or hr.has_perm('EMP_READ')) then v_emp := coalesce(hr.my_employee_id(), '00000000-0000-0000-0000-000000000000'::uuid); end if;
  return coalesce((select jsonb_agg(hr.issue_json(x) order by x.issued_on desc) from hr.asset_issues x
    where (v_emp is null or x.employee_id = v_emp) and (not hr.jbool(p,'open_only') or x.status = 'ISSUED')
    limit 1000), '[]'::jsonb);
end $$;

create or replace function public.hr_issue_asset(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare i hr.asset_items; v_emp uuid; x hr.asset_issues; n int := 0;
begin
  perform hr.require_perm('ASSET_WRITE');
  select * into i from hr.asset_items where id = hr.juuid(p,'item_id') and is_active;
  if i.id is null then raise exception 'REQUIRED: Choose an active item.'; end if;
  if jsonb_typeof(p->'employee_ids') <> 'array' or jsonb_array_length(p->'employee_ids') = 0 then raise exception 'REQUIRED: Choose at least one employee.'; end if;
  if coalesce(hr.jint(p,'qty'), 1) not between 1 and 100 then raise exception 'INVALID: Quantity 1–100.'; end if;
  for v_emp in select (y #>> '{}')::uuid from jsonb_array_elements(p->'employee_ids') y loop
    if not exists (select 1 from hr.employees where id = v_emp and status <> 'SEPARATED') then raise exception 'NOT_FOUND: Employee not found or has left.'; end if;
    insert into hr.asset_issues(employee_id, item_id, qty, serial_no, issued_on, due_return_on, status, notes, issued_by)
    values (v_emp, i.id, coalesce(hr.jint(p,'qty'), 1), hr.jtext(p,'serial_no'), coalesce(hr.jdate(p,'issued_on'), hr.today()), hr.jdate(p,'due_return_on'),
            case when i.returnable then 'ISSUED' else 'CONSUMED' end, hr.jtext(p,'notes'), auth.uid());
    n := n + 1;
  end loop;
  return jsonb_build_object('issued', n);
end $$;

-- Receive back (or record loss/damage). A recovery amount becomes a one-off deduction waiting for Finance.
create or replace function public.hr_return_asset(p_id uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x hr.asset_issues; v_cond text := coalesce(upper(hr.jtext(p,'condition')), 'GOOD'); v_rec numeric := hr.jmoney(p,'recover_amount'); v_adj uuid; i hr.asset_items;
begin
  perform hr.require_perm('ASSET_WRITE');
  select * into x from hr.asset_issues where id = p_id for update;
  if x.id is null then raise exception 'NOT_FOUND: Record not found.'; end if;
  if x.status <> 'ISSUED' then raise exception 'INVALID: This item is not out.'; end if;
  if v_cond not in ('GOOD','WORN','DAMAGED','LOST') then raise exception 'INVALID: Unknown condition.'; end if;
  if coalesce(hr.jdate(p,'returned_on'), hr.today()) < x.issued_on then raise exception 'INVALID: Returned before it was issued.'; end if;
  select * into i from hr.asset_items where id = x.item_id;
  if v_rec is not null and v_rec > 0 then
    if v_cond not in ('DAMAGED','LOST') then raise exception 'INVALID: Recovery applies only to damaged or lost items.'; end if;
    if coalesce(length(hr.jtext(p,'notes')), 0) < 10 then raise exception 'REQUIRED: Explain the damage or loss (at least 10 characters).'; end if;
    insert into hr.payroll_adjustments(employee_id, period_start, kind, code, amount, reason, proposed_by)
    values (x.employee_id, (date_trunc('month', hr.today()) + interval '1 month')::date, 'DEDUCTION', 'DAMAGE', v_rec,
            i.name_en || ' ' || lower(v_cond) || ': ' || hr.jtext(p,'notes'), auth.uid()) returning id into v_adj;
  end if;
  update hr.asset_issues set status = case when v_cond = 'LOST' then 'LOST' else 'RETURNED' end, returned_on = coalesce(hr.jdate(p,'returned_on'), hr.today()),
         condition = v_cond, notes = coalesce(hr.jtext(p,'notes'), notes), received_by = auth.uid(), recovery_adjustment_id = v_adj
   where id = p_id returning * into x;
  update hr.exit_tasks set status = 'DONE', done_by = auth.uid(), done_at = now(), note = 'Returned: ' || lower(v_cond) where ref_id = p_id and status = 'PENDING';
  return hr.issue_json(x);
end $$;

-- ===========================================================================
-- ACCOMMODATION & TRANSPORT
-- ===========================================================================
create or replace function public.hr_list_facilities(p_kind text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  if not (hr.has_perm('ASSET_WRITE') or hr.has_perm('EMP_READ')) then raise exception 'NOT_ALLOWED: You cannot see this.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(f) || jsonb_build_object('entity_code', (select code from hr.legal_entities where id = f.entity_id),
      'driver_en', (select full_name_en from hr.employees where id = f.driver_employee_id),
      'occupants', coalesce((select jsonb_agg(hr.emp_brief(a.employee_id) || jsonb_build_object('assignment_id', a.id, 'place', a.place, 'from_date', a.from_date) order by a.place nulls last, a.from_date)
                             from hr.facility_assignments a where a.facility_id = f.id and (a.to_date is null or a.to_date >= hr.today())), '[]'::jsonb),
      'occupied', (select count(*) from hr.facility_assignments a where a.facility_id = f.id and (a.to_date is null or a.to_date >= hr.today())))
      order by f.code) from hr.facilities f where f.kind = upper(p_kind)), '[]'::jsonb);
end $$;

create or replace function public.hr_save_facility(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); v_kind text := upper(hr.jtext(p,'kind')); v_code text := upper(hr.jtext(p,'code'));
begin
  perform hr.require_perm('ASSET_WRITE');
  if v_kind not in ('ACCOMMODATION','TRANSPORT') then raise exception 'INVALID: Unknown kind.'; end if;
  if v_code is null or v_code !~ '^[A-Z0-9_-]{1,20}$' then raise exception 'INVALID: Code: capital letters, digits, - or _.'; end if;
  if hr.jtext(p,'name_en') is null then raise exception 'REQUIRED: Name is required.'; end if;
  if coalesce(hr.jint(p,'capacity'), 0) not between 1 and 2000 then raise exception 'REQUIRED: Capacity 1–2000.'; end if;
  if v_id is null then
    if not exists (select 1 from hr.legal_entities where id = hr.juuid(p,'entity_id')) then raise exception 'REQUIRED: Choose the company.'; end if;
    insert into hr.facilities(entity_id, kind, code, name_en, name_ar, address, capacity, vehicle_no, driver_employee_id, is_active)
    values (hr.juuid(p,'entity_id'), v_kind, v_code, hr.jtext(p,'name_en'), hr.jtext(p,'name_ar'), hr.jtext(p,'address'), hr.jint(p,'capacity'),
            hr.jtext(p,'vehicle_no'), hr.juuid(p,'driver_employee_id'), hr.jbool(p,'is_active', true));
  else
    if hr.jint(p,'capacity') < (select count(*) from hr.facility_assignments a where a.facility_id = v_id and (a.to_date is null or a.to_date >= hr.today())) then
      raise exception 'INVALID: More people are assigned than the new capacity.';
    end if;
    update hr.facilities set code = v_code, name_en = hr.jtext(p,'name_en'), name_ar = hr.jtext(p,'name_ar'), address = hr.jtext(p,'address'),
      capacity = hr.jint(p,'capacity'), vehicle_no = hr.jtext(p,'vehicle_no'), driver_employee_id = hr.juuid(p,'driver_employee_id'), is_active = hr.jbool(p,'is_active', true)
     where id = v_id;
    if not found then raise exception 'NOT_FOUND: Not found.'; end if;
  end if;
  return public.hr_list_facilities(v_kind);
end $$;

-- Assign someone (ends any current assignment of the same kind the day before).
create or replace function public.hr_assign_facility(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare f hr.facilities; v_emp uuid := hr.juuid(p,'employee_id'); v_from date := coalesce(hr.jdate(p,'from_date'), hr.today());
begin
  perform hr.require_perm('ASSET_WRITE');
  select * into f from hr.facilities where id = hr.juuid(p,'facility_id') and is_active;
  if f.id is null then raise exception 'REQUIRED: Choose an active place or route.'; end if;
  if not exists (select 1 from hr.employees where id = v_emp and status <> 'SEPARATED') then raise exception 'NOT_FOUND: Employee not found or has left.'; end if;
  if (select count(*) from hr.facility_assignments a where a.facility_id = f.id and (a.to_date is null or a.to_date >= v_from)) >= f.capacity then
    raise exception 'FULL: % is full (% places).', f.name_en, f.capacity;
  end if;
  update hr.facility_assignments a set to_date = greatest(a.from_date, v_from - 1)
   where a.employee_id = v_emp and (a.to_date is null or a.to_date >= v_from)
     and a.facility_id in (select id from hr.facilities where kind = f.kind);
  insert into hr.facility_assignments(facility_id, employee_id, place, from_date, created_by) values (f.id, v_emp, hr.jtext(p,'place'), v_from, auth.uid());
  return public.hr_list_facilities(f.kind);
end $$;

create or replace function public.hr_end_facility(p_assignment uuid, p_to date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.facility_assignments; v_kind text;
begin
  perform hr.require_perm('ASSET_WRITE');
  update hr.facility_assignments set to_date = greatest(from_date, coalesce(p_to, hr.today()))
   where id = p_assignment and (to_date is null or to_date >= hr.today()) returning * into a;
  if a.id is null then raise exception 'NOT_FOUND: No current assignment.'; end if;
  update hr.exit_tasks set status = 'DONE', done_by = auth.uid(), done_at = now() where ref_id = p_assignment and status = 'PENDING';
  select kind into v_kind from hr.facilities where id = a.facility_id;
  return public.hr_list_facilities(v_kind);
end $$;

-- ===========================================================================
-- WORK INJURIES
-- ===========================================================================
create or replace function hr.injury_json(w hr.work_injuries)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(w.employee_id) || to_jsonb(w) || jsonb_build_object(
    'report_due', ((w.occurred_at at time zone 'Asia/Muscat')::date + hr.policy_num('injury_report_days', 7)::int),
    'report_overdue', w.spf_reported_on is null and w.severity <> 'FIRST_AID'
                      and hr.today() > ((w.occurred_at at time zone 'Asia/Muscat')::date + hr.policy_num('injury_report_days', 7)::int),
    'created_by_name', hr.user_label(w.created_by), 'closed_by_name', hr.user_label(w.closed_by),
    'can_edit', w.status = 'OPEN' and hr.has_perm('HSE_WRITE'))
$$;

create or replace function public.hr_list_injuries(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  if not (hr.has_perm('HSE_WRITE') or hr.has_perm('EMP_READ')) then raise exception 'NOT_ALLOWED: You cannot see injury records.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(hr.injury_json(w) order by w.occurred_at desc) from hr.work_injuries w
    where (hr.jtext(p,'status') is null or w.status = hr.jtext(p,'status')) and (hr.juuid(p,'employee_id') is null or w.employee_id = hr.juuid(p,'employee_id'))), '[]'::jsonb);
end $$;

create or replace function public.hr_save_injury(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); w hr.work_injuries; v_sev text := upper(hr.jtext(p,'severity')); v_at timestamptz := nullif(p->>'occurred_at','')::timestamptz; u record;
begin
  perform hr.require_perm('HSE_WRITE');
  if v_sev is null or v_sev not in ('FIRST_AID','MEDICAL','LOST_TIME','PERMANENT','FATAL') then raise exception 'REQUIRED: Choose the severity.'; end if;
  if v_at is null or v_at > now() then raise exception 'REQUIRED: Give when it happened (not in the future).'; end if;
  if hr.jtext(p,'location') is null then raise exception 'REQUIRED: Give the location.'; end if;
  if coalesce(length(hr.jtext(p,'description')), 0) < 15 then raise exception 'REQUIRED: Describe what happened (at least 15 characters).'; end if;
  if hr.jdate(p,'spf_reported_on') is not null and hr.jdate(p,'spf_reported_on') < (v_at at time zone 'Asia/Muscat')::date then raise exception 'INVALID: Reported before it happened.'; end if;
  if v_id is null then
    if not exists (select 1 from hr.employees where id = hr.juuid(p,'employee_id')) then raise exception 'NOT_FOUND: Employee not found.'; end if;
    insert into hr.work_injuries(ref_no, employee_id, occurred_at, location, description, injury_type, body_part, severity, lost_days, witnesses,
      root_cause, corrective_action, spf_reported_on, spf_reference, created_by)
    values (hr.next_ref('INJ'), hr.juuid(p,'employee_id'), v_at, hr.jtext(p,'location'), hr.jtext(p,'description'), hr.jtext(p,'injury_type'), hr.jtext(p,'body_part'),
      v_sev, coalesce(hr.jint(p,'lost_days'), 0), hr.jtext(p,'witnesses'), hr.jtext(p,'root_cause'), hr.jtext(p,'corrective_action'),
      hr.jdate(p,'spf_reported_on'), hr.jtext(p,'spf_reference'), auth.uid()) returning * into w;
    if v_sev in ('LOST_TIME','PERMANENT','FATAL') then
      for u in select h.user_id from hr.users_with_perm('HSE_WRITE') h where h.user_id <> auth.uid() loop
        perform hr.notify(u.user_id, 'ALERT', 'HIGH', 'Serious work injury ' || w.ref_no || ' — report to the Social Protection Fund',
          'إصابة عمل جسيمة ' || w.ref_no || ' — يجب الإبلاغ لصندوق الحماية الاجتماعية', null, null, '/injuries', 'INJ:' || w.id);
      end loop;
    end if;
  else
    update hr.work_injuries set occurred_at = v_at, location = hr.jtext(p,'location'), description = hr.jtext(p,'description'), injury_type = hr.jtext(p,'injury_type'),
      body_part = hr.jtext(p,'body_part'), severity = v_sev, lost_days = coalesce(hr.jint(p,'lost_days'), 0), witnesses = hr.jtext(p,'witnesses'),
      root_cause = hr.jtext(p,'root_cause'), corrective_action = hr.jtext(p,'corrective_action'), spf_reported_on = hr.jdate(p,'spf_reported_on'),
      spf_reference = hr.jtext(p,'spf_reference')
     where id = v_id and status = 'OPEN' returning * into w;
    if w.id is null then raise exception 'NOT_PENDING: Only an open record can be changed.'; end if;
  end if;
  return hr.injury_json(w);
end $$;

create or replace function public.hr_close_injury(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare w hr.work_injuries;
begin
  perform hr.require_perm('HSE_WRITE');
  select * into w from hr.work_injuries where id = p_id for update;
  if w.id is null or w.status <> 'OPEN' then raise exception 'NOT_FOUND: No open record.'; end if;
  if coalesce(length(w.corrective_action), 0) < 10 then raise exception 'REQUIRED: Record the corrective action before closing.'; end if;
  if w.severity <> 'FIRST_AID' and w.spf_reported_on is null then raise exception 'REQUIRED: Record when it was reported to the Social Protection Fund.'; end if;
  update hr.work_injuries set status = 'CLOSED', closed_by = auth.uid(), closed_at = now() where id = p_id returning * into w;
  return hr.injury_json(w);
end $$;

-- ===========================================================================
-- EXIT
-- ===========================================================================
create or replace function hr.exit_json(x hr.exit_cases)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(x.employee_id) || to_jsonb(x) || jsonb_build_object(
    'min_notice_days', hr.notice_min_days(x.employee_id), 'is_omani', (select nationality = 'OM' from hr.employees where id = x.employee_id),
    'employee_status', (select status from hr.employees where id = x.employee_id),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'title_en', t.title_en, 'title_ar', t.title_ar, 'ref_id', t.ref_id,
               'status', t.status, 'note', t.note, 'done_by_name', hr.user_label(t.done_by), 'done_at', t.done_at) order by t.sort) from hr.exit_tasks t where t.exit_id = x.id), '[]'::jsonb),
    'settlement', (select jsonb_build_object('id', s.id, 'status', s.status, 'net', s.net) from hr.final_settlements s where s.employee_id = x.employee_id
                   and s.status not in ('CANCELLED') order by s.prepared_at desc limit 1),
    'open_assets', (select count(*) from hr.asset_issues a where a.employee_id = x.employee_id and a.status = 'ISSUED'),
    'created_by_name', hr.user_label(x.created_by), 'completed_by_name', hr.user_label(x.completed_by),
    'can_manage', x.status = 'OPEN' and hr.has_perm('EXIT_MANAGE') and not hr.is_me(x.employee_id))
$$;

create or replace function public.hr_list_exits(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('EXIT_MANAGE');
  return coalesce((select jsonb_agg(hr.exit_json(x) - 'tasks' || jsonb_build_object(
      'done', (select count(*) from hr.exit_tasks t where t.exit_id = x.id and t.status <> 'PENDING'),
      'total', (select count(*) from hr.exit_tasks t where t.exit_id = x.id)) order by (x.status = 'OPEN') desc, x.last_working_date)
    from hr.exit_cases x where hr.jtext(p,'status') is null or x.status = hr.jtext(p,'status')), '[]'::jsonb);
end $$;

create or replace function public.hr_get_exit(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare x hr.exit_cases;
begin
  perform hr.require_perm('EXIT_MANAGE');
  select * into x from hr.exit_cases where id = p_id;
  if x.id is null then raise exception 'NOT_FOUND: Exit not found.'; end if;
  return hr.exit_json(x);
end $$;

-- What the start-exit form needs before saving: status, minimum notice, items and places to clear.
create or replace function public.hr_exit_preview(p_employee uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare e hr.employees;
begin
  perform hr.require_perm('EXIT_MANAGE');
  select * into e from hr.employees where id = p_employee;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  return jsonb_build_object('employee_id', e.id, 'status', e.status, 'is_omani', e.nationality = 'OM', 'min_notice_days', hr.notice_min_days(e.id),
    'open_exit', (select id from hr.exit_cases where employee_id = e.id and status = 'OPEN'),
    'open_assets', (select count(*) from hr.asset_issues where employee_id = e.id and status = 'ISSUED'),
    'facilities', (select count(*) from hr.facility_assignments where employee_id = e.id and (to_date is null or to_date >= hr.today())),
    'contract_end', (select max(end_date) from hr.employee_contracts where employee_id = e.id and status = 'ACTIVE'));
end $$;

-- Start: records the notice on the employee, builds the clearance list (assets out, housing/transport, standard steps).
create or replace function public.hr_start_exit(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e hr.employees; v_type text := upper(hr.jtext(p,'exit_type')); v_given date := coalesce(hr.jdate(p,'notice_given_on'), hr.today());
        v_last date := hr.jdate(p,'last_working_date'); v_min int; v_days int; v_nc int := coalesce(hr.jint(p,'non_compete_months'), 0); x hr.exit_cases;
        t jsonb; k int := 0; a record;
begin
  perform hr.require_perm('EXIT_MANAGE');
  select * into e from hr.employees where id = hr.juuid(p,'employee_id') for update;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if hr.is_me(e.id) then raise exception 'NOT_ALLOWED: You cannot run your own exit.' using errcode = '42501'; end if;
  if e.status = 'SEPARATED' then raise exception 'INVALID: The employee has already left.'; end if;
  if exists (select 1 from hr.exit_cases where employee_id = e.id and status = 'OPEN') then raise exception 'PENDING_EXISTS: An exit is already open for this employee.'; end if;
  if v_type is null or v_type not in ('RESIGNATION','TERMINATION','END_OF_CONTRACT','RETIREMENT','OTHER') then raise exception 'REQUIRED: Choose the type of exit.'; end if;
  if v_last is null then raise exception 'REQUIRED: Last working day is required.'; end if;
  if v_last < v_given then raise exception 'INVALID: The last working day is before the notice date.'; end if;
  v_days := v_last - v_given;
  v_min := hr.notice_min_days(e.id);
  if v_type in ('RESIGNATION','TERMINATION') and v_days < v_min and not hr.jbool(p,'pay_in_lieu') and e.status <> 'PROBATION' then
    raise exception 'NOTICE_SHORT: The notice is % days; at least % days are required (or tick "pay in lieu of notice").', v_days, v_min;
  end if;
  if v_nc > hr.policy_num('non_compete_max_months', 24) then raise exception 'INVALID: A non-compete clause can last at most % months.', hr.policy_num('non_compete_max_months', 24); end if;
  if v_type = 'TERMINATION' and coalesce(length(hr.jtext(p,'reason')), 0) < 15 then raise exception 'REQUIRED: Give the reason for termination (at least 15 characters).'; end if;
  insert into hr.exit_cases(employee_id, exit_type, notice_given_on, last_working_date, notice_days, pay_in_lieu, reason, non_compete_months, created_by)
  values (e.id, v_type, v_given, v_last, v_days, hr.jbool(p,'pay_in_lieu'), hr.jtext(p,'reason'), v_nc, auth.uid()) returning * into x;
  if e.status in ('ACTIVE','PROBATION') then
    perform public.hr_change_status(e.id, jsonb_build_object('action', 'NOTICE', 'date', v_given, 'last_working_date', v_last,
                                    'separation_type', v_type, 'notes', hr.jtext(p,'reason')));
  end if;
  for a in select ai.id, i.name_en, i.name_ar, ai.qty from hr.asset_issues ai join hr.asset_items i on i.id = ai.item_id where ai.employee_id = e.id and ai.status = 'ISSUED' loop
    k := k + 1;
    insert into hr.exit_tasks(exit_id, code, title_en, title_ar, ref_id, sort)
    values (x.id, 'ASSET_' || k, 'Return: ' || a.name_en || case when a.qty > 1 then ' × ' || a.qty else '' end, 'إرجاع: ' || coalesce(a.name_ar, a.name_en), a.id, k);
  end loop;
  for a in select fa.id, f.kind, f.name_en, f.name_ar from hr.facility_assignments fa join hr.facilities f on f.id = fa.facility_id
           where fa.employee_id = e.id and (fa.to_date is null or fa.to_date >= hr.today()) loop
    k := k + 1;
    insert into hr.exit_tasks(exit_id, code, title_en, title_ar, ref_id, sort)
    values (x.id, a.kind || '_' || k, case when a.kind = 'ACCOMMODATION' then 'Vacate ' else 'End transport: ' end || a.name_en,
            case when a.kind = 'ACCOMMODATION' then 'إخلاء ' else 'إنهاء النقل: ' end || coalesce(a.name_ar, a.name_en), a.id, 20 + k);
  end loop;
  for t in select * from jsonb_array_elements(coalesce(hr.policy('exit_tasks')->'COMMON', '[]'::jsonb) || coalesce(hr.policy('exit_tasks')->case when e.nationality = 'OM' then 'OMANI' else 'EXPAT' end, '[]'::jsonb)) loop
    k := k + 1;
    insert into hr.exit_tasks(exit_id, code, title_en, title_ar, sort) values (x.id, t->>'code', t->>'en', coalesce(t->>'ar', t->>'en'), 100 + k)
    on conflict (exit_id, code) do nothing;
  end loop;
  return hr.exit_json(x);
end $$;

create or replace function public.hr_exit_task(p_id uuid, p_status text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t hr.exit_tasks; v_st text := upper(coalesce(p_status,'')); x hr.exit_cases;
begin
  perform hr.require_perm('EXIT_MANAGE');
  select * into t from hr.exit_tasks where id = p_id for update;
  if t.id is null then raise exception 'NOT_FOUND: Step not found.'; end if;
  select * into x from hr.exit_cases where id = t.exit_id;
  if x.status <> 'OPEN' then raise exception 'INVALID: The exit is closed.'; end if;
  if v_st not in ('PENDING','DONE','NOT_NEEDED') then raise exception 'INVALID: Unknown status.'; end if;
  if v_st = 'NOT_NEEDED' and coalesce(length(btrim(coalesce(p_note,''))), 0) < 3 then raise exception 'REQUIRED: Say why this step is not needed.'; end if;
  if t.ref_id is not null and v_st = 'DONE' and exists (select 1 from hr.asset_issues where id = t.ref_id and status = 'ISSUED') then
    raise exception 'INVALID: Receive the item in Assets & PPE (that ticks this step).';
  end if;
  update hr.exit_tasks set status = v_st, note = coalesce(nullif(btrim(coalesce(p_note,'')), ''), note),
         done_by = case when v_st = 'PENDING' then null else auth.uid() end, done_at = case when v_st = 'PENDING' then null else now() end where id = p_id;
  return hr.exit_json(x);
end $$;

create or replace function public.hr_save_exit_interview(p_id uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x hr.exit_cases;
begin
  perform hr.require_perm('EXIT_MANAGE');
  if hr.jint(p,'rating') is not null and hr.jint(p,'rating') not between 1 and 5 then raise exception 'INVALID: Rating 1–5.'; end if;
  update hr.exit_cases set interview = jsonb_build_object('reason_code', hr.jtext(p,'reason_code'), 'would_return', hr.jbool(p,'would_return'),
      'rating', hr.jint(p,'rating'), 'comments', hr.jtext(p,'comments'), 'recorded_by', hr.user_label(auth.uid()), 'recorded_at', now())
   where id = p_id and status = 'OPEN' returning * into x;
  if x.id is null then raise exception 'NOT_FOUND: No open exit.'; end if;
  update hr.exit_tasks set status = 'DONE', done_by = auth.uid(), done_at = now() where exit_id = p_id and code = 'EXIT_INTERVIEW' and status = 'PENDING';
  return hr.exit_json(x);
end $$;

-- Complete: every step closed, then the employee is separated on the last working day.
create or replace function public.hr_complete_exit(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x hr.exit_cases; v_open int;
begin
  perform hr.require_perm('EXIT_MANAGE');
  select * into x from hr.exit_cases where id = p_id for update;
  if x.id is null or x.status <> 'OPEN' then raise exception 'NOT_FOUND: No open exit.'; end if;
  if hr.is_me(x.employee_id) then raise exception 'NOT_ALLOWED: You cannot complete your own exit.' using errcode = '42501'; end if;
  select count(*) into v_open from hr.exit_tasks where exit_id = p_id and status = 'PENDING';
  if v_open > 0 then raise exception 'STEPS_OPEN: % clearance step(s) are still open.', v_open; end if;
  if x.last_working_date > hr.today() then raise exception 'INVALID: The last working day (%) has not passed yet.', to_char(x.last_working_date, 'DD/MM/YYYY'); end if;
  perform public.hr_change_status(x.employee_id, jsonb_build_object('action', 'SEPARATE', 'date', x.last_working_date, 'separation_type', x.exit_type, 'notes', x.reason));
  update hr.facility_assignments set to_date = x.last_working_date where employee_id = x.employee_id and (to_date is null or to_date > x.last_working_date);
  update hr.exit_cases set status = 'COMPLETED', completed_at = now(), completed_by = auth.uid() where id = p_id returning * into x;
  return hr.exit_json(x);
end $$;

create or replace function public.hr_cancel_exit(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x hr.exit_cases;
begin
  perform hr.require_perm('EXIT_MANAGE');
  if coalesce(length(btrim(coalesce(p_reason,''))), 0) < 5 then raise exception 'REQUIRED: Give the reason.'; end if;
  select * into x from hr.exit_cases where id = p_id for update;
  if x.id is null or x.status <> 'OPEN' then raise exception 'NOT_FOUND: No open exit.'; end if;
  if (select status from hr.employees where id = x.employee_id) = 'NOTICE' then
    perform public.hr_change_status(x.employee_id, jsonb_build_object('action', 'WITHDRAW_NOTICE', 'notes', btrim(p_reason)));
  end if;
  update hr.exit_cases set status = 'CANCELLED', cancel_reason = btrim(p_reason) where id = p_id returning * into x;
  return hr.exit_json(x);
end $$;

-- ===========================================================================
-- Policies (HR manager)
-- ===========================================================================
create or replace function public.hr_hr_policies()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return (select value from hr.settings where key = 'hr_policies');
end $$;

create or replace function public.hr_save_hr_policies(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select value from hr.settings where key = 'hr_policies');
begin
  perform hr.require_perm('PERF_MANAGE');
  perform hr.require_perm('DISC_APPROVE');
  if p ? 'discipline_max_deduction_days' then
    if (p->>'discipline_max_deduction_days')::numeric not between 0 and 30 then raise exception 'INVALID: 0–30 days.'; end if;
    v := v || jsonb_build_object('discipline_max_deduction_days', (p->>'discipline_max_deduction_days')::numeric);
  end if;
  if p ? 'discipline_max_suspension_days' then
    if (p->>'discipline_max_suspension_days')::numeric not between 0 and 30 then raise exception 'INVALID: 0–30 days.'; end if;
    v := v || jsonb_build_object('discipline_max_suspension_days', (p->>'discipline_max_suspension_days')::numeric);
  end if;
  if p ? 'injury_report_days' then
    if (p->>'injury_report_days')::int not between 1 and 30 then raise exception 'INVALID: 1–30 days.'; end if;
    v := v || jsonb_build_object('injury_report_days', (p->>'injury_report_days')::int);
  end if;
  update hr.settings set value = v, updated_by = auth.uid(), updated_at = now() where key = 'hr_policies';
  return v;
end $$;

-- ===========================================================================
-- Tasks and dashboard: add reviews, improvement plans, disciplinary decisions, case responses
-- ===========================================================================
create or replace function public.hr_list_my_tasks()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_res jsonb; v_me uuid := hr.my_employee_id();
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
                       where i.interviewer_id = auth.uid() and i.status = 'SCHEDULED' and i.scheduled_at < now()), '[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(hr.review_json(r) order by c.due_date nulls last) from hr.perf_reviews r join hr.perf_cycles c on c.id = r.cycle_id
                       where c.status = 'OPEN' and ((r.status = 'SELF' and r.employee_id = v_me)
                         or (r.status = 'MANAGER' and r.reviewer_id = v_me)
                         or (r.status = 'HR' and hr.has_perm('PERF_MANAGE') and not hr.is_me(r.employee_id) and r.reviewer_id is distinct from v_me)
                         or (r.status = 'ACK' and r.employee_id = v_me))), '[]'::jsonb),
    'cases', case when hr.has_perm('DISC_APPROVE') then coalesce((select jsonb_agg(hr.case_json(d, true) order by d.proposed_at) from hr.disciplinary_cases d
                       where d.status = 'PROPOSED' and d.opened_by <> auth.uid() and d.proposed_by is distinct from auth.uid() and not hr.is_me(d.employee_id)), '[]'::jsonb)
                       else '[]'::jsonb end,
    'my_cases', coalesce((select jsonb_agg(hr.case_json(d, false)) from hr.disciplinary_cases d
                       where d.employee_id = v_me and d.status = 'INVESTIGATION' and d.employee_response is null), '[]'::jsonb))
  into v_res;
  return v_res || jsonb_build_object('count',
    jsonb_array_length(v_res->'leave') + jsonb_array_length(v_res->'corrections') + jsonb_array_length(v_res->'overtime')
    + jsonb_array_length(v_res->'adjustments') + jsonb_array_length(v_res->'rules') + jsonb_array_length(v_res->'pay_rules')
    + jsonb_array_length(v_res->'payroll') + jsonb_array_length(v_res->'loans') + jsonb_array_length(v_res->'pay_adjustments')
    + jsonb_array_length(v_res->'settlements') + jsonb_array_length(v_res->'changes') + jsonb_array_length(v_res->'letters')
    + jsonb_array_length(v_res->'requisitions') + jsonb_array_length(v_res->'offers') + jsonb_array_length(v_res->'interviews')
    + jsonb_array_length(v_res->'reviews') + jsonb_array_length(v_res->'cases') + jsonb_array_length(v_res->'my_cases'));
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
  if hr.has_perm('TRAIN_WRITE') or hr.has_perm('ASSET_WRITE') or hr.has_perm('HSE_WRITE') or hr.has_perm('EXIT_MANAGE') then
    v_res := v_res || jsonb_build_object('workforce', jsonb_build_object(
      'training_expiring_30', (select count(*) from hr.expiry_items(v_today) x where x.source = 'TRAINING' and x.days_left <= 30),
      'assets_overdue', (select count(*) from hr.asset_issues where status = 'ISSUED' and due_return_on < v_today),
      'injuries_open', (select count(*) from hr.work_injuries where status = 'OPEN'),
      'injuries_unreported', (select count(*) from hr.work_injuries w where w.spf_reported_on is null and w.severity <> 'FIRST_AID'
                              and v_today > ((w.occurred_at at time zone 'Asia/Muscat')::date + hr.policy_num('injury_report_days', 7)::int)),
      'exits_open', (select count(*) from hr.exit_cases where status = 'OPEN'),
      'plans_active', (select count(*) from hr.perf_plans where status = 'ACTIVE')));
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
    'interviews', jsonb_array_length(v_tasks->'interviews'), 'reviews', jsonb_array_length(v_tasks->'reviews'),
    'cases', jsonb_array_length(v_tasks->'cases'), 'my_cases', jsonb_array_length(v_tasks->'my_cases'),
    'count', (v_tasks->>'count')::int));
end $$;

select hr.attach_audit();
select hr.secure_api();
