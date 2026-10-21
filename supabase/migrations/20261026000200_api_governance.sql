-- AACT HRMS — 061 API: privacy (PDPL), statutory reports (MoL, SPF), executive dashboard, data import.
-- Idempotent; no destructive statements.

-- ===========================================================================
-- PRIVACY NOTICE AND CONSENTS
-- ===========================================================================
create or replace function hr.notice_json(n hr.privacy_notices)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(n) || jsonb_build_object('prepared_by_name', hr.user_label(n.prepared_by), 'published_by_name', hr.user_label(n.published_by),
    'acknowledged', (select count(distinct c.user_id) from hr.consents c where c.purpose = 'NOTICE' and c.notice_version = n.version and c.withdrawn_at is null))
$$;

create or replace function hr.current_notice()
returns hr.privacy_notices language sql stable security definer set search_path = '' as $$
  select * from hr.privacy_notices where status = 'PUBLISHED' limit 1
$$;

create or replace function public.hr_list_notices()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('PDPL_READ');
  return coalesce((select jsonb_agg(hr.notice_json(n) order by n.version desc) from hr.privacy_notices n), '[]'::jsonb);
end $$;

create or replace function public.hr_save_notice(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); n hr.privacy_notices;
begin
  perform hr.require_perm('PDPL_MANAGE');
  if hr.jtext(p,'title_en') is null or hr.jtext(p,'title_ar') is null then raise exception 'REQUIRED: Give the title in English and Arabic.'; end if;
  if coalesce(length(hr.jtext(p,'body_en')), 0) < 100 or coalesce(length(hr.jtext(p,'body_ar')), 0) < 100 then
    raise exception 'REQUIRED: Write the notice in English and Arabic (at least 100 characters each).';
  end if;
  if v_id is null then
    insert into hr.privacy_notices(version, title_en, title_ar, body_en, body_ar, prepared_by)
    values (coalesce((select max(version) from hr.privacy_notices), 0) + 1, hr.jtext(p,'title_en'), hr.jtext(p,'title_ar'), hr.jtext(p,'body_en'), hr.jtext(p,'body_ar'), auth.uid())
    returning * into n;
  else
    update hr.privacy_notices set title_en = hr.jtext(p,'title_en'), title_ar = hr.jtext(p,'title_ar'), body_en = hr.jtext(p,'body_en'),
           body_ar = hr.jtext(p,'body_ar'), prepared_by = auth.uid()
     where id = v_id and status = 'DRAFT' returning * into n;
    if n.id is null then raise exception 'NOT_PENDING: Only a draft can be changed. Start a new version instead.'; end if;
  end if;
  return hr.notice_json(n);
end $$;

-- Publishing needs a second person; everyone with a login is asked to read and acknowledge it.
create or replace function public.hr_publish_notice(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n hr.privacy_notices; u record;
begin
  perform hr.require_perm('PDPL_MANAGE');
  select * into n from hr.privacy_notices where id = p_id for update;
  if n.id is null or n.status <> 'DRAFT' then raise exception 'NOT_PENDING: Only a draft can be published.'; end if;
  if n.prepared_by = auth.uid() then raise exception 'SELF_APPROVAL: You prepared this text; someone else must publish it.' using errcode = '42501'; end if;
  update hr.privacy_notices set status = 'RETIRED' where status = 'PUBLISHED';
  update hr.privacy_notices set status = 'PUBLISHED', published_by = auth.uid(), published_at = now() where id = p_id returning * into n;
  for u in select up.user_id from hr.user_profiles up where up.is_active loop
    perform hr.notify(u.user_id, 'TASK', 'NORMAL', 'Please read the privacy notice (version ' || n.version || ')',
      'يرجى قراءة إشعار الخصوصية (الإصدار ' || n.version || ')', null, null, '/me?tab=privacy', 'NOTICE:' || n.version);
  end loop;
  return hr.notice_json(n);
end $$;

create or replace function public.hr_my_privacy()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare n hr.privacy_notices := hr.current_notice();
begin
  perform hr.require_user();
  return jsonb_build_object(
    'notice', case when n.id is not null then jsonb_build_object('version', n.version, 'title_en', n.title_en, 'title_ar', n.title_ar,
                'body_en', n.body_en, 'body_ar', n.body_ar, 'published_at', n.published_at) end,
    'acknowledged_at', (select c.given_at from hr.consents c where c.user_id = auth.uid() and c.purpose = 'NOTICE' and c.withdrawn_at is null
                        and c.notice_version = n.version),
    'consents', coalesce((select jsonb_agg(jsonb_build_object('purpose', c.purpose, 'given', c.given, 'given_at', c.given_at) order by c.purpose)
                          from hr.consents c where c.user_id = auth.uid() and c.withdrawn_at is null and c.purpose <> 'NOTICE'), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'ref_no', d.ref_no, 'kind', d.kind, 'received_on', d.received_on, 'due_on', d.due_on,
                          'status', d.status, 'outcome', d.outcome) order by d.received_on desc)
                          from hr.dsr_requests d where d.employee_id = hr.my_employee_id() and d.employee_id is not null), '[]'::jsonb),
    'dsr_days', coalesce((hr.pdpl('dsr_days') #>> '{}')::int, 45));
end $$;

create or replace function public.hr_ack_notice()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n hr.privacy_notices := hr.current_notice();
begin
  perform hr.require_user();
  if n.id is null then raise exception 'NOT_FOUND: No privacy notice has been published yet.'; end if;
  if not exists (select 1 from hr.consents where user_id = auth.uid() and purpose = 'NOTICE' and withdrawn_at is null and notice_version = n.version) then
    update hr.consents set withdrawn_at = now() where user_id = auth.uid() and purpose = 'NOTICE' and withdrawn_at is null;
    insert into hr.consents(user_id, employee_id, purpose, notice_version, given) values (auth.uid(), hr.my_employee_id(), 'NOTICE', n.version, true);
  end if;
  return public.hr_my_privacy();
end $$;

-- Optional consents (each can be withdrawn at any time; withdrawing does not affect earlier processing).
create or replace function public.hr_set_consent(p_purpose text, p_given boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_p text := upper(coalesce(p_purpose,''));
begin
  perform hr.require_user();
  if v_p not in ('PHOTO_DIRECTORY','MARKETING_MEDIA','BIOMETRIC','HEALTH_DATA','TRANSFER_ABROAD') then raise exception 'INVALID: Unknown purpose.'; end if;
  update hr.consents set withdrawn_at = now() where user_id = auth.uid() and purpose = v_p and withdrawn_at is null;
  insert into hr.consents(user_id, employee_id, purpose, notice_version, given)
  values (auth.uid(), hr.my_employee_id(), v_p, (hr.current_notice()).version, coalesce(p_given, false));
  return public.hr_my_privacy();
end $$;

create or replace function public.hr_list_consents()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_ver int := (hr.current_notice()).version;
begin
  perform hr.require_perm('PDPL_READ');
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', up.user_id, 'name', coalesce(e.full_name_en, up.display_name, hr.user_label(up.user_id)),
      'name_ar', e.full_name_ar, 'employee_no', e.employee_no, 'employee_id', e.id,
      'notice_version', (select max(c.notice_version) from hr.consents c where c.user_id = up.user_id and c.purpose = 'NOTICE' and c.withdrawn_at is null),
      'acknowledged_at', (select max(c.given_at) from hr.consents c where c.user_id = up.user_id and c.purpose = 'NOTICE' and c.withdrawn_at is null and c.notice_version = v_ver),
      'consents', coalesce((select jsonb_object_agg(c.purpose, c.given) from hr.consents c where c.user_id = up.user_id and c.withdrawn_at is null and c.purpose <> 'NOTICE'), '{}'::jsonb))
      order by e.employee_no nulls last, up.display_name)
    from hr.user_profiles up left join hr.employees e on e.id = up.employee_id where up.is_active), '[]'::jsonb);
end $$;

-- ===========================================================================
-- DATA-SUBJECT REQUESTS
-- ===========================================================================
create or replace function hr.dsr_json(d hr.dsr_requests)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(d) || jsonb_build_object('employee_no', (select employee_no from hr.employees where id = d.employee_id),
    'days_left', d.due_on - hr.today(), 'overdue', d.status in ('OPEN','IN_PROGRESS') and d.due_on < hr.today(),
    'created_by_name', hr.user_label(d.created_by), 'closed_by_name', hr.user_label(d.closed_by))
$$;

create or replace function public.hr_list_dsr(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('PDPL_READ');
  return coalesce((select jsonb_agg(hr.dsr_json(d) order by (d.status in ('OPEN','IN_PROGRESS')) desc, d.due_on) from hr.dsr_requests d
    where hr.jtext(p,'status') is null or (hr.jtext(p,'status') = 'OPEN' and d.status in ('OPEN','IN_PROGRESS')) or d.status = hr.jtext(p,'status')), '[]'::jsonb);
end $$;

create or replace function hr.notify_pdpl(p_title_en text, p_title_ar text, p_link text, p_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare u record;
begin
  for u in select h.user_id from hr.users_with_perm('PDPL_MANAGE') h loop
    perform hr.notify(u.user_id, 'TASK', 'HIGH', p_title_en, p_title_ar, null, null, p_link, p_ref);
  end loop;
end $$;

-- From the employee (My HR → Privacy)
create or replace function public.hr_submit_dsr(p_kind text, p_details text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_emp uuid := hr.my_employee_id(); d hr.dsr_requests; v_k text := upper(coalesce(p_kind,''));
begin
  perform hr.require_user();
  if v_emp is null then raise exception 'NOT_LINKED: Your login is not linked to an employee record.'; end if;
  if v_k not in ('ACCESS','CORRECTION','ERASURE','RESTRICTION','OBJECTION','PORTABILITY','WITHDRAW_CONSENT','COMPLAINT') then raise exception 'INVALID: Unknown request type.'; end if;
  if coalesce(length(btrim(coalesce(p_details,''))), 0) < 10 then raise exception 'REQUIRED: Describe your request (at least 10 characters).'; end if;
  insert into hr.dsr_requests(ref_no, employee_id, requester_name, kind, details, received_on, due_on, identity_checked, created_by)
  values (hr.next_ref('DSR'), v_emp, (select full_name_en from hr.employees where id = v_emp), v_k, btrim(p_details), hr.today(), hr.dsr_due(hr.today()), true, auth.uid())
  returning * into d;
  perform hr.notify_pdpl('Data-subject request ' || d.ref_no || ' — reply by ' || to_char(d.due_on, 'DD/MM/YYYY'),
    'طلب صاحب بيانات ' || d.ref_no || ' — الرد قبل ' || to_char(d.due_on, 'DD/MM/YYYY'), '/privacy?tab=requests', 'DSR:' || d.id);
  return public.hr_my_privacy();
end $$;

-- Recorded by HR (letters, e-mails, former employees, candidates)
create or replace function public.hr_save_dsr(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); d hr.dsr_requests; v_k text := upper(hr.jtext(p,'kind')); v_rec date := coalesce(hr.jdate(p,'received_on'), hr.today());
begin
  perform hr.require_perm('PDPL_MANAGE');
  if v_k is null or v_k not in ('ACCESS','CORRECTION','ERASURE','RESTRICTION','OBJECTION','PORTABILITY','WITHDRAW_CONSENT','COMPLAINT') then raise exception 'REQUIRED: Choose the request type.'; end if;
  if hr.jtext(p,'requester_name') is null and hr.juuid(p,'employee_id') is null then raise exception 'REQUIRED: Who made the request?'; end if;
  if coalesce(length(hr.jtext(p,'details')), 0) < 10 then raise exception 'REQUIRED: Describe the request (at least 10 characters).'; end if;
  if v_rec > hr.today() then raise exception 'INVALID: The date received is in the future.'; end if;
  if v_id is null then
    insert into hr.dsr_requests(ref_no, employee_id, candidate_id, requester_name, contact, kind, details, received_on, due_on, identity_checked, created_by)
    values (hr.next_ref('DSR'), hr.juuid(p,'employee_id'), hr.juuid(p,'candidate_id'),
            coalesce(hr.jtext(p,'requester_name'), (select full_name_en from hr.employees where id = hr.juuid(p,'employee_id'))),
            hr.jtext(p,'contact'), v_k, hr.jtext(p,'details'), v_rec, hr.dsr_due(v_rec), hr.jbool(p,'identity_checked'), auth.uid())
    returning * into d;
  else
    update hr.dsr_requests set kind = v_k, details = hr.jtext(p,'details'), contact = hr.jtext(p,'contact'), identity_checked = hr.jbool(p,'identity_checked'),
           status = case when status = 'OPEN' and hr.jbool(p,'identity_checked') then 'IN_PROGRESS' else status end
     where id = v_id and status in ('OPEN','IN_PROGRESS') returning * into d;
    if d.id is null then raise exception 'NOT_PENDING: Only an open request can be changed.'; end if;
  end if;
  return hr.dsr_json(d);
end $$;

create or replace function public.hr_close_dsr(p_id uuid, p_status text, p_outcome text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d hr.dsr_requests; v_st text := upper(coalesce(p_status,''));
begin
  perform hr.require_perm('PDPL_MANAGE');
  select * into d from hr.dsr_requests where id = p_id for update;
  if d.id is null or d.status not in ('OPEN','IN_PROGRESS') then raise exception 'NOT_FOUND: No open request.'; end if;
  if v_st not in ('COMPLETED','REJECTED') then raise exception 'INVALID: Unknown outcome.'; end if;
  if v_st = 'COMPLETED' and not d.identity_checked then raise exception 'REQUIRED: Confirm the requester''s identity first.'; end if;
  if coalesce(length(btrim(coalesce(p_outcome,''))), 0) < 15 then raise exception 'REQUIRED: Record what was done or why it was refused (at least 15 characters).'; end if;
  update hr.dsr_requests set status = v_st, outcome = btrim(p_outcome), closed_by = auth.uid(), closed_at = now() where id = p_id returning * into d;
  if d.employee_id is not null then
    perform hr.notify(hr.employee_user(d.employee_id), 'INFO', 'NORMAL', 'Your data request ' || d.ref_no || ' has been answered',
      'تم الرد على طلبك بشأن البيانات ' || d.ref_no, null, null, '/me?tab=privacy', 'DSRC:' || d.id);
  end if;
  return hr.dsr_json(d);
end $$;

-- ===========================================================================
-- BREACH LOG
-- ===========================================================================
create or replace function hr.breach_json(b hr.data_breaches)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(b) || jsonb_build_object('deadline', hr.breach_deadline(b.discovered_at),
    'hours_left', round(extract(epoch from (hr.breach_deadline(b.discovered_at) - now())) / 3600.0, 1),
    'overdue', b.authority_notified_at is null and b.not_notified_reason is null and now() > hr.breach_deadline(b.discovered_at),
    'notified_late', b.authority_notified_at is not null and b.authority_notified_at > hr.breach_deadline(b.discovered_at),
    'created_by_name', hr.user_label(b.created_by), 'closed_by_name', hr.user_label(b.closed_by))
$$;

create or replace function public.hr_list_breaches()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('PDPL_READ');
  return coalesce((select jsonb_agg(hr.breach_json(b) order by (b.status = 'OPEN') desc, b.discovered_at desc) from hr.data_breaches b), '[]'::jsonb);
end $$;

create or replace function public.hr_save_breach(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); b hr.data_breaches; v_disc timestamptz := nullif(p->>'discovered_at','')::timestamptz; v_risk text := upper(hr.jtext(p,'risk'));
        v_notified timestamptz := nullif(p->>'authority_notified_at','')::timestamptz;
begin
  perform hr.require_perm('PDPL_MANAGE');
  if v_disc is null or v_disc > now() then raise exception 'REQUIRED: When was the breach discovered (not in the future)?'; end if;
  if v_risk is null or v_risk not in ('LOW','MEDIUM','HIGH') then raise exception 'REQUIRED: Assess the risk.'; end if;
  if coalesce(length(hr.jtext(p,'description')), 0) < 20 then raise exception 'REQUIRED: Describe what happened (at least 20 characters).'; end if;
  if nullif(p->>'occurred_at','')::timestamptz > v_disc then raise exception 'INVALID: It cannot have happened after it was discovered.'; end if;
  if v_notified is not null and v_notified < v_disc then raise exception 'INVALID: The Ministry was notified before the breach was discovered.'; end if;
  if v_id is null then
    insert into hr.data_breaches(ref_no, discovered_at, occurred_at, description, data_kinds, people_affected, risk, containment, contained_at,
      authority_notified_at, authority_reference, not_notified_reason, subjects_notified_at, created_by)
    values (hr.next_ref('BR'), v_disc, nullif(p->>'occurred_at','')::timestamptz, hr.jtext(p,'description'), hr.jtext(p,'data_kinds'), hr.jint(p,'people_affected'),
      v_risk, hr.jtext(p,'containment'), nullif(p->>'contained_at','')::timestamptz, v_notified, hr.jtext(p,'authority_reference'),
      hr.jtext(p,'not_notified_reason'), nullif(p->>'subjects_notified_at','')::timestamptz, auth.uid())
    returning * into b;
    perform hr.notify_pdpl('Personal data breach ' || b.ref_no || ' — notify the Ministry by ' || to_char(hr.breach_deadline(b.discovered_at) at time zone 'Asia/Muscat', 'DD/MM/YYYY HH24:MI'),
      'خرق بيانات شخصية ' || b.ref_no || ' — الإبلاغ للوزارة قبل ' || to_char(hr.breach_deadline(b.discovered_at) at time zone 'Asia/Muscat', 'DD/MM/YYYY HH24:MI'),
      '/privacy?tab=breaches', 'BR:' || b.id);
  else
    update hr.data_breaches set discovered_at = v_disc, occurred_at = nullif(p->>'occurred_at','')::timestamptz, description = hr.jtext(p,'description'),
      data_kinds = hr.jtext(p,'data_kinds'), people_affected = hr.jint(p,'people_affected'), risk = v_risk, containment = hr.jtext(p,'containment'),
      contained_at = nullif(p->>'contained_at','')::timestamptz, authority_notified_at = v_notified, authority_reference = hr.jtext(p,'authority_reference'),
      not_notified_reason = hr.jtext(p,'not_notified_reason'), subjects_notified_at = nullif(p->>'subjects_notified_at','')::timestamptz
     where id = v_id and status = 'OPEN' returning * into b;
    if b.id is null then raise exception 'NOT_PENDING: Only an open record can be changed.'; end if;
  end if;
  return hr.breach_json(b);
end $$;

create or replace function public.hr_close_breach(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare b hr.data_breaches;
begin
  perform hr.require_perm('PDPL_MANAGE');
  select * into b from hr.data_breaches where id = p_id for update;
  if b.id is null or b.status <> 'OPEN' then raise exception 'NOT_FOUND: No open record.'; end if;
  if b.contained_at is null or coalesce(length(b.containment), 0) < 10 then raise exception 'REQUIRED: Record how and when the breach was contained.'; end if;
  if b.authority_notified_at is null and coalesce(length(b.not_notified_reason), 0) < 15 then
    raise exception 'REQUIRED: Record when the Ministry was notified, or why notification was not required.';
  end if;
  if b.risk = 'HIGH' and b.subjects_notified_at is null then raise exception 'REQUIRED: For a high-risk breach, record when the affected people were told.'; end if;
  update hr.data_breaches set status = 'CLOSED', closed_by = auth.uid(), closed_at = now() where id = p_id returning * into b;
  return hr.breach_json(b);
end $$;

-- ===========================================================================
-- PROCESSING REGISTER, RETENTION, SETTINGS
-- ===========================================================================
create or replace function public.hr_list_activities()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('PDPL_READ');
  return coalesce((select jsonb_agg(to_jsonb(a) order by a.is_active desc, a.code) from hr.processing_activities a), '[]'::jsonb);
end $$;

create or replace function public.hr_save_activity(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := hr.juuid(p,'id'); v_code text := upper(hr.jtext(p,'code')); v_basis text := upper(hr.jtext(p,'legal_basis'));
begin
  perform hr.require_perm('PDPL_MANAGE');
  if v_code is null or v_code !~ '^[A-Z0-9_-]{2,30}$' then raise exception 'INVALID: Code: capital letters, digits, - or _.'; end if;
  if hr.jtext(p,'name_en') is null or hr.jtext(p,'purpose') is null or hr.jtext(p,'data_subjects') is null or hr.jtext(p,'data_categories') is null then
    raise exception 'REQUIRED: Name, purpose, whose data and which data are required.';
  end if;
  if v_basis is null or v_basis not in ('CONTRACT','LEGAL_OBLIGATION','CONSENT','VITAL_INTEREST','PUBLIC_INTEREST','LEGITIMATE_INTEREST') then raise exception 'REQUIRED: Choose the legal basis.'; end if;
  if exists (select 1 from hr.processing_activities where code = v_code and id is distinct from v_id) then raise exception 'DUPLICATE: This code is already used.'; end if;
  if v_id is null then
    insert into hr.processing_activities(code, name_en, name_ar, purpose, legal_basis, data_subjects, data_categories, sensitive, recipients,
      transfer_outside_oman, retention, security, system_owner, is_active, reviewed_at)
    values (v_code, hr.jtext(p,'name_en'), hr.jtext(p,'name_ar'), hr.jtext(p,'purpose'), v_basis, hr.jtext(p,'data_subjects'), hr.jtext(p,'data_categories'),
      hr.jbool(p,'sensitive'), hr.jtext(p,'recipients'), hr.jtext(p,'transfer_outside_oman'), hr.jtext(p,'retention'), hr.jtext(p,'security'),
      hr.jtext(p,'system_owner'), hr.jbool(p,'is_active', true), hr.today());
  else
    update hr.processing_activities set code = v_code, name_en = hr.jtext(p,'name_en'), name_ar = hr.jtext(p,'name_ar'), purpose = hr.jtext(p,'purpose'),
      legal_basis = v_basis, data_subjects = hr.jtext(p,'data_subjects'), data_categories = hr.jtext(p,'data_categories'), sensitive = hr.jbool(p,'sensitive'),
      recipients = hr.jtext(p,'recipients'), transfer_outside_oman = hr.jtext(p,'transfer_outside_oman'), retention = hr.jtext(p,'retention'),
      security = hr.jtext(p,'security'), system_owner = hr.jtext(p,'system_owner'), is_active = hr.jbool(p,'is_active', true), reviewed_at = hr.today()
     where id = v_id;
    if not found then raise exception 'NOT_FOUND: Not found.'; end if;
  end if;
  return public.hr_list_activities();
end $$;

create or replace function hr.retention_months(p_code text)
returns int language sql stable security definer set search_path = '' as $$
  select (r->>'months')::int from jsonb_array_elements(coalesce(hr.pdpl('retention'), '[]'::jsonb)) r where r->>'code' = p_code limit 1
$$;

-- Candidates who were not hired, have nothing open and were last touched before the retention period.
create or replace function hr.candidates_past_retention()
returns setof hr.candidates language sql stable security definer set search_path = '' as $$
  select c.* from hr.candidates c
  where c.employee_id is null and c.full_name_en <> 'Anonymised candidate'
    and not exists (select 1 from hr.applications a where a.candidate_id = c.id and a.stage not in ('REJECTED','WITHDRAWN','HIRED'))
    and greatest(c.updated_at, coalesce((select max(a.stage_at) from hr.applications a where a.candidate_id = c.id), c.updated_at))
        < now() - make_interval(months => coalesce(hr.retention_months('CANDIDATE'), 12))
$$;

create or replace function public.hr_retention_report()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r jsonb; v_out jsonb := '[]'::jsonb; v_m int; v_n bigint;
begin
  perform hr.require_perm('PDPL_READ');
  for r in select * from jsonb_array_elements(coalesce(hr.pdpl('retention'), '[]'::jsonb)) loop
    v_m := (r->>'months')::int;
    v_n := case r->>'code'
      when 'EX_EMPLOYEE' then (select count(*) from hr.employees where status = 'SEPARATED' and separation_date < hr.today() - make_interval(months => v_m))
      when 'CANDIDATE' then (select count(*) from hr.candidates_past_retention())
      when 'ATTENDANCE' then (select count(*) from hr.punches where punch_at < now() - make_interval(months => v_m))
      when 'ACCESS_LOG' then (select count(*) from hr.access_log where at < now() - make_interval(months => v_m))
      else null end;
    v_out := v_out || jsonb_build_array(r || jsonb_build_object('due', v_n, 'action', case when r->>'code' = 'CANDIDATE' then 'ANONYMISE' else 'REVIEW' end));
  end loop;
  return jsonb_build_object('rules', v_out,
    'candidates', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'full_name_en', c.full_name_en, 'nationality', c.nationality, 'updated_at', c.updated_at) order by c.updated_at)
                            from hr.candidates_past_retention() c), '[]'::jsonb));
end $$;

-- Erasure for candidates past retention: identifying fields are blanked, the pipeline history stays without a name.
create or replace function public.hr_anonymise_candidates(p_ids jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid; n int := 0;
begin
  perform hr.require_perm('PDPL_MANAGE');
  if jsonb_typeof(p_ids) <> 'array' or jsonb_array_length(p_ids) = 0 then raise exception 'REQUIRED: Choose the candidates.'; end if;
  for v_id in select (x #>> '{}')::uuid from jsonb_array_elements(p_ids) x loop
    if not exists (select 1 from hr.candidates_past_retention() c where c.id = v_id) then
      raise exception 'INVALID: A chosen candidate is not past the retention period (or has an open application).';
    end if;
    update hr.candidates set full_name_en = 'Anonymised candidate', full_name_ar = null, date_of_birth = null, email = null, phone = null,
           civil_number = null, passport_no = null, current_employer = null, notes = null, qualification = null
     where id = v_id;
    update hr.applications set rejection_reason = null where candidate_id = v_id;
    n := n + 1;
  end loop;
  return jsonb_build_object('anonymised', n);
end $$;

create or replace function public.hr_pdpl_settings()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('PDPL_READ');
  return (select value from hr.settings where key = 'pdpl');
end $$;

create or replace function public.hr_save_pdpl_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb := (select value from hr.settings where key = 'pdpl'); r jsonb; v_ret jsonb := '[]'::jsonb;
begin
  perform hr.require_perm('PDPL_MANAGE');
  if hr.jtext(p,'dpo_email') is not null then perform hr.check_email(hr.jtext(p,'dpo_email'), 'Data protection contact e-mail'); end if;
  v := v || jsonb_build_object('dpo_name', hr.jtext(p,'dpo_name'), 'dpo_email', hr.jtext(p,'dpo_email'));
  if p ? 'retention' then
    for r in select * from jsonb_array_elements(p->'retention') loop
      if (r->>'months') !~ '^\d{1,3}$' or (r->>'months')::int not between 1 and 600 then raise exception 'INVALID: Retention months 1–600.'; end if;
      v_ret := v_ret || jsonb_build_array(jsonb_build_object('code', r->>'code', 'en', r->>'en', 'ar', r->>'ar', 'months', (r->>'months')::int, 'basis', r->>'basis'));
    end loop;
    v := v || jsonb_build_object('retention', v_ret);
  end if;
  update hr.settings set value = v, updated_by = auth.uid(), updated_at = now() where key = 'pdpl';
  return v;
end $$;

create or replace function public.hr_pdpl_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare n hr.privacy_notices := hr.current_notice(); v_users int;
begin
  perform hr.require_perm('PDPL_READ');
  select count(*) into v_users from hr.user_profiles where is_active;
  return jsonb_build_object(
    'notice_version', n.version, 'notice_published_at', n.published_at, 'users', v_users,
    'acknowledged', (select count(distinct c.user_id) from hr.consents c join hr.user_profiles up on up.user_id = c.user_id and up.is_active
                     where c.purpose = 'NOTICE' and c.withdrawn_at is null and c.notice_version = n.version),
    'dsr_open', (select count(*) from hr.dsr_requests where status in ('OPEN','IN_PROGRESS')),
    'dsr_overdue', (select count(*) from hr.dsr_requests where status in ('OPEN','IN_PROGRESS') and due_on < hr.today()),
    'breaches_open', (select count(*) from hr.data_breaches where status = 'OPEN'),
    'breaches_overdue', (select count(*) from hr.data_breaches b where b.authority_notified_at is null and b.not_notified_reason is null and now() > hr.breach_deadline(b.discovered_at)),
    'activities', (select count(*) from hr.processing_activities where is_active),
    'activities_unreviewed', (select count(*) from hr.processing_activities where is_active and (reviewed_at is null or reviewed_at < hr.today() - 365)),
    'candidates_due', (select count(*) from hr.candidates_past_retention()),
    'settings', (select value - 'retention' from hr.settings where key = 'pdpl'));
end $$;

-- ===========================================================================
-- STATUTORY REPORTS
-- ===========================================================================
-- Ministry of Labour localisation (Omanisation) report: workforce by profession with nationality, plus the employee list.
create or replace function public.hr_mol_report(p_entity uuid, p_as_of date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_on date := coalesce(p_as_of, hr.today()); en hr.legal_entities; v_sal boolean := hr.has_perm('EMP_SALARY_READ');
begin
  perform hr.require_perm('COMPLIANCE_READ');
  select * into en from hr.legal_entities where id = p_entity;
  if en.id is null then raise exception 'NOT_FOUND: Company not found.'; end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'MOL_REPORT', 'Localisation report ' || en.code || ' as of ' || v_on);
  return jsonb_build_object(
    'entity', jsonb_build_object('id', en.id, 'code', en.code, 'name_en', en.name_en, 'name_ar', en.name_ar, 'cr_number', en.cr_number, 'mol_establishment_no', en.mol_establishment_no),
    'as_of', v_on,
    'overall', public.hr_get_omanisation(p_entity, v_on)->'overall',
    'by_profession', coalesce((select jsonb_agg(jsonb_build_object('profession_code', x.profession_code, 'job_en', x.job_en, 'job_ar', x.job_ar,
          'omani_only', x.omani_only, 'total', x.total, 'omani', x.omani, 'expat', x.total - x.omani,
          'pct', case when x.total > 0 then round(100.0 * x.omani / x.total, 1) end,
          'expat_in_omani_only', case when x.omani_only then x.total - x.omani else 0 end) order by x.profession_code nulls last, x.job_en)
        from (select j.profession_code, j.name_en job_en, j.name_ar job_ar, j.omani_only, count(*)::int total, count(*) filter (where p.is_omani)::int omani
              from hr.omanisation_population(p_entity, v_on) p join hr.job_titles j on j.id = p.job_title_id
              group by j.profession_code, j.name_en, j.name_ar, j.omani_only) x), '[]'::jsonb),
    'employees', coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar,
          'nationality', e.nationality, 'gender', e.gender, 'date_of_birth', e.date_of_birth, 'civil_number', e.civil_number,
          'passport_no', (select d.doc_number from hr.employee_documents d where d.employee_id = e.id and d.doc_type = 'PASSPORT' and d.is_current and d.status = 'ACTIVE' limit 1),
          'resident_card_no', (select d.doc_number from hr.employee_documents d where d.employee_id = e.id and d.doc_type = 'RESIDENT_CARD' and d.is_current and d.status = 'ACTIVE' limit 1),
          'job_en', j.name_en, 'job_ar', j.name_ar, 'profession_code', j.profession_code, 'omani_only', j.omani_only,
          'department_en', dp.name_en, 'department_ar', dp.name_ar, 'join_date', e.join_date, 'status', e.status,
          'contract_type', ct.contract_type, 'contract_end', ct.end_date, 'mol_registration_no', ct.mol_registration_no,
          'basic', case when v_sal then (hr.comp_on(e.id, v_on)->>'basic')::numeric end) order by e.employee_no)
        from hr.omanisation_population(p_entity, v_on) p join hr.employees e on e.id = p.employee_id
        join hr.job_titles j on j.id = p.job_title_id left join hr.departments dp on dp.id = p.department_id
        left join lateral (select c.contract_type, c.end_date, c.mol_registration_no from hr.employee_contracts c
                           where c.employee_id = e.id and c.status = 'ACTIVE' order by c.start_date desc limit 1) ct on true), '[]'::jsonb),
    'show_salary', v_sal);
end $$;

-- Social Protection Fund monthly contribution schedule from an approved payroll run.
create or replace function public.hr_spf_report(p_run uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare r hr.payroll_runs; en hr.legal_entities;
begin
  perform hr.require_perm('PAY_READ');
  select * into r from hr.payroll_runs where id = p_run;
  if r.id is null then raise exception 'NOT_FOUND: Payroll run not found.'; end if;
  select * into en from hr.legal_entities where id = r.entity_id;
  return jsonb_build_object(
    'run', jsonb_build_object('id', r.id, 'month', to_char(r.period_start, 'YYYY-MM'), 'status', r.status, 'final', r.status in ('APPROVED','PAID')),
    'entity', jsonb_build_object('code', en.code, 'name_en', en.name_en, 'name_ar', en.name_ar, 'cr_number', en.cr_number, 'spf_employer_no', en.spf_employer_no),
    'rows', coalesce((select jsonb_agg(x order by x->>'is_omani' desc, x->>'employee_no') from (
        select jsonb_build_object('employee_id', s.employee_id, 'employee_no', s.employee_no, 'full_name_en', s.full_name_en, 'full_name_ar', s.full_name_ar,
          'nationality', s.nationality, 'is_omani', s.is_omani, 'civil_number', s.civil_number, 'paid_days', s.paid_days,
          'wage', (select max(l.qty) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_%' and l.rate is not null),
          'lines', coalesce((select jsonb_object_agg(l.code, l.amount) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_%'), '{}'::jsonb),
          'employee_total', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_EE\_%'),
          'employer_total', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_ER\_%')) x
        from hr.payslips s where s.run_id = r.id
          and exists (select 1 from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_%')) q), '[]'::jsonb),
    'totals', (select coalesce(jsonb_object_agg(code, amt), '{}'::jsonb) from (select l.code, sum(l.amount) amt from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id
               where s.run_id = r.id and l.code like 'SPF\_%' group by l.code) t),
    'codes', coalesce((select jsonb_agg(distinct jsonb_build_object('code', l.code, 'name_en', l.name_en, 'name_ar', l.name_ar, 'kind', l.kind))
               from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id where s.run_id = r.id and l.code like 'SPF\_%'), '[]'::jsonb));
end $$;

-- ===========================================================================
-- EXECUTIVE DASHBOARD
-- ===========================================================================
create or replace function public.hr_exec_dashboard(p_entity uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_today date := hr.today(); v_pay boolean := hr.has_perm('PAY_READ'); v_start date;
begin
  perform hr.require_perm('EXEC_VIEW');
  if not exists (select 1 from hr.legal_entities where id = p_entity) then raise exception 'NOT_FOUND: Company not found.'; end if;
  v_start := (date_trunc('month', v_today) - interval '11 months')::date;
  return jsonb_build_object(
    'as_of', v_today,
    'months', (select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'),
        'headcount', (select count(*) from hr.employees e where e.entity_id = p_entity and e.join_date <= me and (e.separation_date is null or e.separation_date > me)),
        'joiners', (select count(*) from hr.employees e where e.entity_id = p_entity and e.join_date between m and me),
        'leavers', (select count(*) from hr.employees e where e.entity_id = p_entity and e.separation_date between m and me),
        'omani_pct', (select case when count(*) > 0 then round(100.0 * count(*) filter (where p.is_omani) / count(*), 1) end from hr.omanisation_population(p_entity, me) p),
        'overtime_hours', (select round(coalesce(sum(o.minutes), 0) / 60.0, 1) from hr.overtime_requests o join hr.employees e on e.id = o.employee_id
                           where e.entity_id = p_entity and o.status = 'APPROVED' and o.work_date between m and me),
        'absent_days', (select count(*) from hr.attendance_days a join hr.employees e on e.id = a.employee_id
                        where e.entity_id = p_entity and a.status = 'ABSENT' and a.work_date between m and least(me, v_today)),
        'worked_days', (select count(*) from hr.attendance_days a join hr.employees e on e.id = a.employee_id
                        where e.entity_id = p_entity and a.status in ('PRESENT','ABSENT','MISSING_PUNCH') and a.work_date between m and least(me, v_today)),
        'payroll_cost', case when v_pay then (select sum(s.total_earnings + s.employer_cost) from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
                        where r.entity_id = p_entity and r.period_start = m and r.status in ('APPROVED','PAID')) end) order by m)
      from (select m::date m, (m + interval '1 month' - interval '1 day')::date me from generate_series(v_start, date_trunc('month', v_today)::date, interval '1 month') m) mm),
    'snapshot', (select jsonb_build_object(
        'headcount', count(*), 'omani', count(*) filter (where e.nationality = 'OM'), 'female', count(*) filter (where e.gender = 'F'),
        'probation', count(*) filter (where e.status = 'PROBATION'), 'notice', count(*) filter (where e.status = 'NOTICE'),
        'avg_tenure_years', round(avg((v_today - e.join_date) / 365.25)::numeric, 1),
        'avg_age', round(avg(extract(year from age(v_today, e.date_of_birth)))::numeric, 1))
      from hr.employees e where e.entity_id = p_entity and e.status <> 'SEPARATED' and e.join_date <= v_today),
    'by_department', coalesce((select jsonb_agg(jsonb_build_object('name_en', d.name_en, 'name_ar', d.name_ar, 'total', x.total, 'omani', x.omani) order by x.total desc)
        from (select department_id, count(*)::int total, count(*) filter (where is_omani)::int omani from hr.omanisation_population(p_entity, v_today) group by department_id) x
        join hr.departments d on d.id = x.department_id), '[]'::jsonb),
    'by_nationality', coalesce((select jsonb_agg(jsonb_build_object('code', x.nationality, 'name_en', c.name_en, 'name_ar', c.name_ar, 'total', x.n) order by x.n desc)
        from (select nationality, count(*)::int n from hr.employees where entity_id = p_entity and status <> 'SEPARATED' and join_date <= v_today group by nationality) x
        left join hr.countries c on c.code = x.nationality), '[]'::jsonb),
    'risks', jsonb_build_object(
        'documents_expired', (select count(*) from hr.expiry_items(v_today) x join hr.employees e on e.id = x.employee_id where e.entity_id = p_entity and x.days_left < 0),
        'documents_30', (select count(*) from hr.expiry_items(v_today) x join hr.employees e on e.id = x.employee_id where e.entity_id = p_entity and x.days_left between 0 and 30),
        'open_positions', (select coalesce(sum(r.positions - (select count(*) from hr.applications a where a.requisition_id = r.id and a.stage = 'HIRED')), 0)
                           from hr.job_requisitions r where r.entity_id = p_entity and r.status in ('APPROVED','ON_HOLD')),
        'injuries_ytd', (select count(*) from hr.work_injuries w join hr.employees e on e.id = w.employee_id
                         where e.entity_id = p_entity and w.occurred_at >= date_trunc('year', now())),
        'lost_days_ytd', (select coalesce(sum(w.lost_days), 0) from hr.work_injuries w join hr.employees e on e.id = w.employee_id
                          where e.entity_id = p_entity and w.occurred_at >= date_trunc('year', now())),
        'open_cases', (select count(*) from hr.disciplinary_cases d join hr.employees e on e.id = d.employee_id
                       where e.entity_id = p_entity and d.status in ('DRAFT','INVESTIGATION','PROPOSED')),
        'exits_open', (select count(*) from hr.exit_cases x join hr.employees e on e.id = x.employee_id where e.entity_id = p_entity and x.status = 'OPEN'),
        'gratuity_liability', case when v_pay then (select round(coalesce(sum((hr.gratuity_calc(e.id, v_today, coalesce((hr.comp_on(e.id, v_today)->>'basic')::numeric, 0))->>'total')::numeric), 0), 3)
                              from hr.employees e where e.entity_id = p_entity and e.nationality <> 'OM' and e.status <> 'SEPARATED' and e.join_date <= v_today) end),
    'show_pay', v_pay);
end $$;

-- ===========================================================================
-- DATA IMPORT (from the old system's spreadsheets)
-- ===========================================================================
create or replace function hr.master_id(p_table text, p_entity uuid, p_code text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v uuid;
begin
  if p_code is null or btrim(p_code) = '' then return null; end if;
  execute format('select id from hr.%I where entity_id = $1 and upper(code) = upper($2) limit 1', p_table) into v using p_entity, btrim(p_code);
  if v is null then raise exception 'Unknown % code "%".', replace(p_table, '_', ' '), p_code; end if;
  return v;
end $$;

create or replace function hr.employee_by_no(p_no text, p_label text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v uuid;
begin
  if p_no is null or btrim(p_no) = '' then return null; end if;
  select id into v from hr.employees where upper(employee_no) = upper(btrim(p_no));
  if v is null then raise exception 'Unknown %employee number "%".', p_label, p_no; end if;
  return v;
end $$;

-- Rows are objects keyed by column heading. A dry run checks every row and undoes everything.
create or replace function public.hr_import(p_kind text, p_rows jsonb, p_dry_run boolean default true, p_file_name text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_kind text := upper(coalesce(p_kind,'')); r jsonb; i int := 0; v_ok int := 0; v_res jsonb := '[]'::jsonb; v_out jsonb; v_emp uuid; v_ent uuid;
        v_p jsonb; k text; v_lines jsonb; v_batch uuid; v_skip text[] := array['employee_no','effective_from','notes','reason'];
begin
  perform hr.require_perm('DATA_IMPORT');
  if v_kind not in ('EMPLOYEES','DOCUMENTS','SALARIES') then raise exception 'INVALID: Unknown import type.'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'REQUIRED: The file has no rows.'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'INVALID: At most 2000 rows at a time.'; end if;
  begin
    for r in select * from jsonb_array_elements(p_rows) loop
      i := i + 1;
      begin
        if v_kind = 'EMPLOYEES' then
          v_ent := coalesce((select id from hr.legal_entities where upper(code) = upper(hr.jtext(r,'company_code'))),
                            (select id from hr.legal_entities where is_active order by created_at limit 1));
          if hr.jtext(r,'company_code') is not null and not exists (select 1 from hr.legal_entities where upper(code) = upper(hr.jtext(r,'company_code'))) then
            raise exception 'Unknown company code "%".', hr.jtext(r,'company_code');
          end if;
          v_p := jsonb_strip_nulls(jsonb_build_object('entity_id', v_ent, 'employee_no', hr.jtext(r,'employee_no'), 'full_name_en', hr.jtext(r,'full_name_en'),
            'full_name_ar', hr.jtext(r,'full_name_ar'), 'nationality', upper(hr.jtext(r,'nationality')), 'gender', upper(hr.jtext(r,'gender')),
            'date_of_birth', hr.jtext(r,'date_of_birth'), 'marital_status', upper(hr.jtext(r,'marital_status')), 'civil_number', hr.jtext(r,'civil_number'),
            'mobile', hr.jtext(r,'mobile'), 'personal_email', hr.jtext(r,'personal_email'), 'work_email', hr.jtext(r,'work_email'),
            'join_date', hr.jtext(r,'join_date'), 'probation_end_date', hr.jtext(r,'probation_end_date'), 'exception_reason', hr.jtext(r,'exception_reason'),
            'confirm_duplicate', hr.jbool(r,'confirm_duplicate'),
            'assignment', jsonb_strip_nulls(jsonb_build_object(
              'department_id', hr.master_id('departments', v_ent, hr.jtext(r,'department_code')),
              'job_title_id', hr.master_id('job_titles', v_ent, hr.jtext(r,'job_code')),
              'grade_id', hr.master_id('grades', v_ent, hr.jtext(r,'grade_code')),
              'category_id', hr.master_id('employee_categories', v_ent, hr.jtext(r,'category_code')),
              'location_id', hr.master_id('locations', v_ent, hr.jtext(r,'location_code')),
              'manager_id', hr.employee_by_no(hr.jtext(r,'manager_employee_no'), 'manager '),
              'employment_type', upper(hr.jtext(r,'employment_type')), 'shift_code', hr.jtext(r,'shift_code')))));
          v_out := public.hr_save_employee(v_p);
          v_res := v_res || jsonb_build_array(jsonb_build_object('row', i, 'ok', true, 'key', v_out->'employee'->>'employee_no', 'id', v_out->'employee'->>'id'));
        else
          if hr.jtext(r,'employee_no') is null then raise exception 'The employee number is blank.'; end if;
          v_emp := hr.employee_by_no(hr.jtext(r,'employee_no'), '');
          if v_kind = 'DOCUMENTS' then
            v_out := public.hr_save_document(v_emp, jsonb_strip_nulls(jsonb_build_object('doc_type', upper(hr.jtext(r,'doc_type')), 'doc_number', hr.jtext(r,'doc_number'),
              'issue_date', hr.jtext(r,'issue_date'), 'expiry_date', hr.jtext(r,'expiry_date'), 'issuing_authority', hr.jtext(r,'issuing_authority'),
              'issue_place', hr.jtext(r,'issue_place'), 'notes', coalesce(hr.jtext(r,'notes'), 'Imported'))));
          else
            v_lines := '[]'::jsonb;
            for k in select key from jsonb_each(r) loop
              continue when lower(k) = any(v_skip) or nullif(btrim(r->>k), '') is null;
              v_lines := v_lines || jsonb_build_array(jsonb_build_object('component_code', upper(k), 'amount', r->>k));
            end loop;
            v_out := public.hr_propose_compensation(v_emp, jsonb_build_object('effective_from', coalesce(hr.jtext(r,'effective_from'),
                       (select join_date::text from hr.employees where id = v_emp)), 'reason', coalesce(upper(hr.jtext(r,'reason')), 'JOIN'),
                       'notes', coalesce(hr.jtext(r,'notes'), 'Imported opening salary'), 'lines', v_lines));
          end if;
          v_res := v_res || jsonb_build_array(jsonb_build_object('row', i, 'ok', true, 'key', hr.jtext(r,'employee_no')));
        end if;
        v_ok := v_ok + 1;
      exception when others then
        v_res := v_res || jsonb_build_array(jsonb_build_object('row', i, 'ok', false, 'key', coalesce(hr.jtext(r,'employee_no'), hr.jtext(r,'full_name_en')),
                   'message', regexp_replace(sqlerrm, '^[A-Z_]+:\s*', '')));
      end;
    end loop;
    if coalesce(p_dry_run, true) then raise exception 'HR_IMPORT_DRY_RUN'; end if;
  exception when others then
    if sqlerrm <> 'HR_IMPORT_DRY_RUN' then raise; end if;
  end;
  insert into hr.import_batches(kind, file_name, dry_run, rows_total, rows_ok, rows_failed, results, created_by)
  values (v_kind, p_file_name, coalesce(p_dry_run, true), i, v_ok, i - v_ok, v_res, auth.uid()) returning id into v_batch;
  return jsonb_build_object('batch_id', v_batch, 'dry_run', coalesce(p_dry_run, true), 'total', i, 'ok', v_ok, 'failed', i - v_ok, 'results', v_res);
end $$;

create or replace function public.hr_list_imports()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('DATA_IMPORT');
  return coalesce((select jsonb_agg(to_jsonb(b) - 'results' || jsonb_build_object('created_by_name', hr.user_label(b.created_by)) order by b.created_at desc)
    from (select * from hr.import_batches order by created_at desc limit 50) b), '[]'::jsonb);
end $$;

select hr.attach_audit();
select hr.secure_api();
