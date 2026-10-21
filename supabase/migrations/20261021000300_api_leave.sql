-- AACT HRMS — 012 API: leave types, balances, requests, approvals, adjustments, accrual; my tasks; time dashboard.

-- ---------------------------------------------------------------------------
-- Leave types
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_leave_types()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(to_jsonb(t) order by t.sort, t.code) from hr.leave_types t), '[]'::jsonb);
end $$;

create or replace function public.hr_save_leave_type(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_code text := upper(hr.jtext(p,'code')); t hr.leave_types; v_new boolean := false;
begin
  perform hr.require_perm('RULES_APPROVE');
  if v_code is null then raise exception 'REQUIRED: Code is required.'; end if;
  select * into t from hr.leave_types where code = v_code for update;
  if t.code is null then
    if hr.jtext(p,'name_en') is null or hr.jtext(p,'name_ar') is null then raise exception 'REQUIRED: Names in English and Arabic are required.'; end if;
    if v_code !~ '^[A-Z0-9_]{2,30}$' then raise exception 'INVALID: Code may use A–Z, 0–9 and _ only.'; end if;
    insert into hr.leave_types(code, name_en, name_ar, category, rule_basis, quota_period)
    values (v_code, hr.jtext(p,'name_en'), hr.jtext(p,'name_ar'), 'COMPANY', 'COMPANY_POLICY', 'YEAR')
    returning * into t;
    v_new := true;
  end if;
  if p ? 'quota_days' and t.legal_min_days is not null and coalesce(hr.jnum(p,'quota_days'), 0) < t.legal_min_days then
    raise exception 'LEGAL_MINIMUM: % cannot be less than the legal minimum of % days.', t.name_en, t.legal_min_days;
  end if;
  update hr.leave_types set
    name_en = coalesce(hr.jtext(p,'name_en'), name_en), name_ar = coalesce(hr.jtext(p,'name_ar'), name_ar),
    pay_mode = coalesce(hr.jtext(p,'pay_mode'), pay_mode),
    pay_tiers = case when p ? 'pay_tiers' then coalesce(p->'pay_tiers','[]'::jsonb) else pay_tiers end,
    paid_by = coalesce(hr.jtext(p,'paid_by'), paid_by),
    quota_days = case when p ? 'quota_days' then hr.jnum(p,'quota_days') else quota_days end,
    quota_period = coalesce(hr.jtext(p,'quota_period'), quota_period),
    accrual = coalesce(hr.jtext(p,'accrual'), accrual),
    count_mode = coalesce(hr.jtext(p,'count_mode'), count_mode),
    min_service_months = coalesce(hr.jint(p,'min_service_months'), min_service_months),
    carry_forward_max = case when p ? 'carry_forward_max' then hr.jnum(p,'carry_forward_max') else carry_forward_max end,
    gender = coalesce(hr.jtext(p,'gender'), gender), nationality = coalesce(hr.jtext(p,'nationality'), nationality),
    requires_document = case when p ? 'requires_document' then hr.jbool(p,'requires_document') else requires_document end,
    needs_event_date = case when p ? 'needs_event_date' then hr.jbool(p,'needs_event_date') else needs_event_date end,
    event_window_days = case when p ? 'event_window_days' then hr.jint(p,'event_window_days') else event_window_days end,
    max_before_event_days = case when p ? 'max_before_event_days' then hr.jint(p,'max_before_event_days') else max_before_event_days end,
    allow_half_day = case when p ? 'allow_half_day' then hr.jbool(p,'allow_half_day') else allow_half_day end,
    allow_negative = case when p ? 'allow_negative' then hr.jbool(p,'allow_negative') else allow_negative end,
    ticket_eligible = case when p ? 'ticket_eligible' then hr.jbool(p,'ticket_eligible') else ticket_eligible end,
    legal_basis = case when p ? 'legal_basis' then hr.jtext(p,'legal_basis') else legal_basis end,
    notes = case when p ? 'notes' then hr.jtext(p,'notes') else notes end,
    sort = coalesce(hr.jint(p,'sort'), sort),
    is_active = case when p ? 'is_active' then hr.jbool(p,'is_active', true) else is_active end
  where code = v_code
  returning * into t;
  if t.quota_days is not null and t.legal_min_days is not null and t.quota_days < t.legal_min_days then
    raise exception 'LEGAL_MINIMUM: % cannot be less than the legal minimum of % days.', t.name_en, t.legal_min_days;
  end if;
  if t.quota_period = 'NONE' and t.quota_days is not null then raise exception 'INVALID: Unlimited leave cannot have a quota.'; end if;
  if t.quota_period <> 'NONE' and t.quota_days is null then raise exception 'INVALID: Give the number of days.'; end if;
  if t.pay_mode = 'TIERED' and jsonb_array_length(t.pay_tiers) = 0 then raise exception 'INVALID: Tiered pay needs tiers.'; end if;
  return to_jsonb(t);
exception when check_violation then
  raise exception 'INVALID: These settings are not consistent (%).', sqlerrm;
end $$;

-- ---------------------------------------------------------------------------
-- Balances
-- ---------------------------------------------------------------------------
create or replace function hr.type_applies(t hr.leave_types, e hr.employees)
returns boolean language sql stable set search_path = '' as $$
  select (t.gender = 'ALL' or t.gender = e.gender)
     and (t.nationality = 'ALL' or (t.nationality = 'OMANI' and e.nationality = 'OM') or (t.nationality = 'EXPAT' and e.nationality <> 'OM'))
$$;

create or replace function public.hr_leave_balances(p_employee uuid, p_on date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare e hr.employees; v_on date := coalesce(p_on, hr.today());
begin
  perform hr.require_user();
  if not hr.can_see_time(p_employee, 'LEAVE_READ') then raise exception 'NOT_ALLOWED: You cannot see this employee''s leave.' using errcode = '42501'; end if;
  select * into e from hr.employees where id = p_employee;
  return hr.emp_brief(p_employee) || jsonb_build_object(
    'as_of', v_on, 'gender', e.gender, 'is_omani', e.nationality = 'OM', 'join_date', e.join_date,
    'balances', coalesce((select jsonb_agg(hr.leave_balance(p_employee, t.code, v_on) || jsonb_build_object(
                    'pay_mode', t.pay_mode, 'requires_document', t.requires_document, 'needs_event_date', t.needs_event_date,
                    'allow_half_day', t.allow_half_day, 'ticket_eligible', t.ticket_eligible and e.nationality <> 'OM',
                    'min_service_months', t.min_service_months, 'max_before_event_days', t.max_before_event_days,
                    'event_window_days', t.event_window_days,
                    'eligible_from', (e.join_date + make_interval(months => t.min_service_months))::date) order by t.sort)
                  from hr.leave_types t where t.is_active and hr.type_applies(t, e)), '[]'::jsonb),
    'annual_taken_24m', (select coalesce(sum(r.days), 0) from hr.leave_requests r
                         where r.employee_id = p_employee and r.leave_type = 'ANNUAL' and r.status = 'APPROVED'
                           and r.end_date > v_on - interval '24 months' and r.start_date <= v_on),
    'ledger', coalesce((select jsonb_agg(jsonb_build_object('entry_date', l.entry_date, 'leave_type', l.leave_type, 'days', l.days,
                          'kind', l.kind, 'note', l.note) order by l.entry_date desc, l.created_at desc)
                        from (select * from hr.leave_ledger where employee_id = p_employee order by entry_date desc, created_at desc limit 60) l), '[]'::jsonb));
end $$;

create or replace function public.hr_list_leave_balances(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_type text := coalesce(hr.jtext(p,'leave_type'), 'ANNUAL'); v_entity uuid := hr.juuid(p,'entity_id');
        v_dep uuid := hr.juuid(p,'department_id'); v_on date := coalesce(hr.jdate(p,'on'), hr.today());
begin
  perform hr.require_perm('LEAVE_READ');
  return coalesce((select jsonb_agg(hr.emp_brief(e.id) || hr.leave_balance(e.id, v_type, v_on) || jsonb_build_object(
             'join_date', e.join_date, 'status', e.status,
             'taken_24m', (select coalesce(sum(r.days), 0) from hr.leave_requests r where r.employee_id = e.id and r.leave_type = 'ANNUAL'
                           and r.status = 'APPROVED' and r.end_date > v_on - interval '24 months' and r.start_date <= v_on),
             'two_year_rule_due', v_type = 'ANNUAL' and e.join_date <= v_on - interval '24 months'
                           and (select coalesce(sum(r.days), 0) from hr.leave_requests r where r.employee_id = e.id and r.leave_type = 'ANNUAL'
                                and r.status = 'APPROVED' and r.end_date > v_on - interval '24 months' and r.start_date <= v_on) < 30)
           order by e.employee_no)
    from hr.employees e join hr.leave_types t on t.code = v_type
    where e.status <> 'SEPARATED' and hr.type_applies(t, e)
      and (v_entity is null or e.entity_id = v_entity)
      and (v_dep is null or (hr.current_assignment(e.id)).department_id = v_dep)), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Leave requests
-- ---------------------------------------------------------------------------
create or replace function hr.leave_json(r hr.leave_requests)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(r.employee_id) || jsonb_build_object(
    'id', r.id, 'leave_type', r.leave_type, 'name_en', t.name_en, 'name_ar', t.name_ar, 'pay_mode', t.pay_mode,
    'start_date', r.start_date, 'end_date', r.end_date, 'half_day', r.half_day, 'days', r.days, 'event_date', r.event_date,
    'reason', r.reason, 'document_id', r.document_id, 'requires_document', t.requires_document,
    'document_name', (select coalesce(d.file_name, d.doc_type) from hr.employee_documents d where d.id = r.document_id),
    'status', r.status, 'pay_breakdown', r.pay_breakdown, 'ticket_requested', r.ticket_requested, 'ticket_status', r.ticket_status,
    'requested_by_name', hr.user_label(r.requested_by), 'requested_at', r.requested_at,
    'manager_decided_by_name', hr.user_label(r.manager_decided_by), 'manager_decided_at', r.manager_decided_at, 'manager_note', r.manager_note,
    'decided_by_name', hr.user_label(r.decided_by), 'decided_at', r.decided_at, 'decision_note', r.decision_note,
    'cancelled_by_name', hr.user_label(r.cancelled_by), 'cancelled_at', r.cancelled_at, 'cancel_reason', r.cancel_reason,
    'can_decide', hr.can_decide(r.status, r.employee_id, r.requested_by, 'LEAVE_APPROVE'),
    'can_cancel', (r.status like 'PENDING%' and (auth.uid() = r.requested_by or hr.is_me(r.employee_id) or hr.has_perm('LEAVE_APPROVE')))
                  or (r.status = 'APPROVED' and hr.has_perm('LEAVE_APPROVE')),
    'can_attach', r.status in ('PENDING_MANAGER','PENDING_HR','APPROVED') and (hr.is_me(r.employee_id) or auth.uid() = r.requested_by or hr.has_perm('DOC_WRITE')),
    'balance', case when hr.can_see_time(r.employee_id, 'LEAVE_READ') then hr.leave_balance(r.employee_id, r.leave_type, r.start_date) end)
  from hr.leave_types t where t.code = r.leave_type
$$;

create or replace function public.hr_request_leave(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_emp uuid := hr.juuid(p,'employee_id'); v_type text := upper(hr.jtext(p,'leave_type'));
  v_from date := hr.jdate(p,'start_date'); v_to date := coalesce(hr.jdate(p,'end_date'), hr.jdate(p,'start_date'));
  v_half boolean := hr.jbool(p,'half_day'); v_event date := hr.jdate(p,'event_date');
  t hr.leave_types; e hr.employees; v_days numeric; b jsonb; v_status text; r hr.leave_requests;
begin
  perform hr.require_user();
  if v_emp is null or v_type is null or v_from is null then raise exception 'REQUIRED: Employee, leave type and dates are required.'; end if;
  if not (hr.is_me(v_emp) or hr.is_my_team(v_emp) or hr.has_perm('LEAVE_WRITE')) then
    raise exception 'NOT_ALLOWED: You cannot request leave for this employee.' using errcode = '42501';
  end if;
  select * into t from hr.leave_types where code = v_type and is_active;
  if t.code is null then raise exception 'NOT_FOUND: Leave type not found.'; end if;
  select * into e from hr.employees where id = v_emp;
  if e.status = 'SEPARATED' then raise exception 'INVALID: The employee has left.'; end if;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  if v_to - v_from > 400 then raise exception 'INVALID: A single request cannot be longer than 400 days.'; end if;
  if not hr.type_applies(t, e) then raise exception 'NOT_ELIGIBLE: % does not apply to this employee.', t.name_en; end if;
  if v_from < e.join_date then raise exception 'INVALID: Leave cannot start before the joining date.'; end if;
  if v_from < (e.join_date + make_interval(months => t.min_service_months))::date then
    raise exception 'NOT_ELIGIBLE: % can be taken after % months of service (from %).', t.name_en, t.min_service_months,
      to_char((e.join_date + make_interval(months => t.min_service_months))::date, 'DD/MM/YYYY');
  end if;
  if v_half and not t.allow_half_day then raise exception 'INVALID: % cannot be taken as a half day.', t.name_en; end if;
  if v_half and v_to <> v_from then raise exception 'INVALID: A half day must start and end on the same date.'; end if;
  if t.needs_event_date and v_event is null then raise exception 'REQUIRED: Give the date of the event (birth, marriage or death).'; end if;
  if t.max_before_event_days is not null and v_from < v_event - t.max_before_event_days then
    raise exception 'INVALID: % can start at most % days before the event date.', t.name_en, t.max_before_event_days;
  end if;
  if t.event_window_days is not null and (v_from < v_event or v_to > v_event + t.event_window_days - 1) then
    raise exception 'INVALID: % must be taken within % days from the event date.', t.name_en, t.event_window_days;
  end if;
  v_days := hr.leave_day_count(v_emp, v_type, v_from, v_to, v_half);
  if v_days <= 0 then raise exception 'INVALID: There are no leave days in this period.'; end if;
  if t.quota_period = 'EVENT' and v_days > t.quota_days then
    raise exception 'BALANCE: % is at most % days per event.', t.name_en, t.quota_days;
  end if;
  if t.quota_period in ('YEAR','ONCE') or t.accrual = 'MONTHLY' then
    b := hr.leave_balance(v_emp, v_type, v_from);
    if not t.allow_negative and (b->>'available')::numeric - (b->>'pending')::numeric < v_days then
      raise exception 'BALANCE: Only % days are available (% waiting for approval); this request needs %.',
        (b->>'available')::numeric, (b->>'pending')::numeric, v_days;
    end if;
  end if;
  if exists (select 1 from hr.leave_requests x where x.employee_id = v_emp and x.status in ('PENDING_MANAGER','PENDING_HR','APPROVED')
             and daterange(x.start_date, x.end_date, '[]') && daterange(v_from, v_to, '[]')
             and (v_half or x.half_day)) then
    raise exception 'OVERLAP: This overlaps another leave request.';
  end if;
  perform hr.assert_open(v_emp, v_from, v_to);
  v_status := hr.first_status(v_emp);
  begin
    insert into hr.leave_requests(employee_id, leave_type, start_date, end_date, half_day, days, event_date, reason, status,
                                  ticket_requested, requested_by)
    values (v_emp, v_type, v_from, v_to, v_half, v_days, v_event, hr.jtext(p,'reason'), v_status,
            hr.jbool(p,'ticket_requested') and t.ticket_eligible and e.nationality <> 'OM', auth.uid())
    returning * into r;
  exception when exclusion_violation then
    raise exception 'OVERLAP: This overlaps another leave request.';
  end;
  perform hr.notify_approvers(v_emp, v_status, 'LEAVE_APPROVE', 'LEAVE',
    'Leave waiting: ' || e.full_name_en || ', ' || t.name_en || ' ' || to_char(v_from,'DD/MM') || '–' || to_char(v_to,'DD/MM/YYYY'),
    'إجازة بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en) || '، ' || t.name_ar,
    '/approvals', 'leave:' || r.id || ':' || v_status);
  return hr.leave_json(r);
end $$;

create or replace function public.hr_attach_leave_document(p_request uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.leave_requests; v_type text := coalesce(upper(hr.jtext(p,'doc_type')), 'LEAVE_SUPPORT'); v_path text := hr.jtext(p,'file_path');
        v_doc uuid; t hr.leave_types;
begin
  perform hr.require_user();
  select * into r from hr.leave_requests where id = p_request for update;
  if r.id is null then raise exception 'NOT_FOUND: Leave request not found.'; end if;
  if not (hr.is_me(r.employee_id) or auth.uid() = r.requested_by or hr.has_perm('DOC_WRITE')) then
    raise exception 'NOT_ALLOWED: You cannot attach documents to this request.' using errcode = '42501';
  end if;
  if r.status not in ('PENDING_MANAGER','PENDING_HR','APPROVED') then raise exception 'INVALID: This request is closed.'; end if;
  if v_type not in ('MEDICAL_CERT','LEAVE_SUPPORT') then raise exception 'INVALID: Use a medical certificate or supporting document.'; end if;
  if v_path is null or v_path not like r.employee_id::text || '/' || v_type || '/%' then
    raise exception 'INVALID: The file was not uploaded for this employee and document type.';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'hr-documents' and o.name = v_path) then
    raise exception 'NOT_FOUND: The uploaded file was not found. Upload it again.';
  end if;
  select * into t from hr.leave_types where code = r.leave_type;
  insert into hr.employee_documents(employee_id, doc_type, title, issue_date, file_path, file_name, mime_type, file_size, uploaded_by, notes)
  values (r.employee_id, v_type, t.name_en || ' ' || to_char(r.start_date,'DD/MM/YYYY') || '–' || to_char(r.end_date,'DD/MM/YYYY'),
          hr.today(), v_path, hr.jtext(p,'file_name'), hr.jtext(p,'mime_type'), hr.jint(p,'file_size'), auth.uid(),
          'Attached to leave request')
  returning id into v_doc;
  update hr.leave_requests set document_id = v_doc where id = p_request returning * into r;
  return hr.leave_json(r);
end $$;

create or replace function public.hr_decide_leave(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.leave_requests; t hr.leave_types; e hr.employees; b jsonb; v_prior numeric; v_breakdown jsonb;
begin
  perform hr.require_user();
  select * into r from hr.leave_requests where id = p_id for update;
  if r.id is null or r.status not like 'PENDING%' then raise exception 'NOT_FOUND: This leave request is no longer waiting.'; end if;
  if auth.uid() = r.requested_by or hr.is_me(r.employee_id) then raise exception 'SELF_APPROVAL: Someone other than you must approve this.'; end if;
  if not hr.can_decide(r.status, r.employee_id, r.requested_by, 'LEAVE_APPROVE') then
    raise exception 'NOT_ALLOWED: You cannot decide this leave request.' using errcode = '42501';
  end if;
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  select * into t from hr.leave_types where code = r.leave_type;
  select * into e from hr.employees where id = r.employee_id;
  if not p_approve then
    update hr.leave_requests set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(), decision_note = btrim(p_note)
     where id = p_id returning * into r;
  elsif r.status = 'PENDING_MANAGER' and not hr.has_perm('LEAVE_APPROVE') then
    update hr.leave_requests set status = 'PENDING_HR', manager_decided_by = auth.uid(), manager_decided_at = now(),
           manager_note = nullif(btrim(p_note),'') where id = p_id returning * into r;
    perform hr.notify_approvers(r.employee_id, 'PENDING_HR', 'LEAVE_APPROVE', 'LEAVE',
      'Leave waiting: ' || e.full_name_en || ', ' || t.name_en, 'إجازة بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en),
      '/approvals', 'leave:' || r.id || ':PENDING_HR');
  else
    perform hr.assert_open(r.employee_id, r.start_date, r.end_date);
    if t.requires_document and r.document_id is null then
      raise exception 'REQUIRED: Attach the supporting document before final approval.';
    end if;
    if (t.quota_period in ('YEAR','ONCE') or t.accrual = 'MONTHLY') and not t.allow_negative then
      b := hr.leave_balance(r.employee_id, r.leave_type, r.start_date);
      if (b->>'available')::numeric < r.days then
        raise exception 'BALANCE: Only % days are available; this request needs %.', (b->>'available')::numeric, r.days;
      end if;
    end if;
    if t.pay_mode = 'TIERED' then
      select coalesce(sum(x.days), 0) into v_prior from hr.leave_requests x
       where x.employee_id = r.employee_id and x.leave_type = r.leave_type and x.status = 'APPROVED'
         and extract(year from x.start_date) = extract(year from r.start_date) and x.start_date < r.start_date;
      v_breakdown := hr.tier_breakdown(t.pay_tiers, v_prior, r.days);
    elsif t.pay_mode = 'UNPAID' then
      v_breakdown := jsonb_build_array(jsonb_build_object('pct', 0, 'days', r.days));
    else
      v_breakdown := jsonb_build_array(jsonb_build_object('pct', 100, 'days', r.days));
    end if;
    update hr.leave_requests set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note),''),
           pay_breakdown = v_breakdown, ticket_status = case when ticket_requested then 'REQUESTED' else ticket_status end
     where id = p_id returning * into r;
    insert into hr.leave_ledger(employee_id, leave_type, entry_date, days, kind, request_id, note, created_by)
    values (r.employee_id, r.leave_type, r.start_date, -r.days, 'TAKEN', r.id, 'Approved leave', auth.uid());
    perform hr.compute_attendance(r.employee_id, r.start_date, r.end_date);
  end if;
  if r.status in ('APPROVED','REJECTED') then
    perform hr.notify(hr.employee_user(r.employee_id), 'LEAVE', 'NORMAL',
      t.name_en || ' ' || lower(r.status) || ': ' || to_char(r.start_date,'DD/MM') || '–' || to_char(r.end_date,'DD/MM/YYYY'),
      t.name_ar || ': ' || case when r.status = 'APPROVED' then 'تم الاعتماد' else 'تم الرفض' end,
      r.decision_note, r.decision_note, '/leave', 'leave-done:' || r.id);
  end if;
  return hr.leave_json(r);
end $$;

create or replace function public.hr_cancel_leave(p_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.leave_requests; v_was text;
begin
  perform hr.require_user();
  select * into r from hr.leave_requests where id = p_id for update;
  if r.id is null or r.status not in ('PENDING_MANAGER','PENDING_HR','APPROVED') then raise exception 'NOT_FOUND: This leave request cannot be cancelled.'; end if;
  if r.status = 'APPROVED' then
    if not hr.has_perm('LEAVE_APPROVE') then raise exception 'NOT_ALLOWED: Ask HR to cancel approved leave.' using errcode = '42501'; end if;
    if coalesce(length(btrim(p_reason)),0) < 3 then raise exception 'REQUIRED: Give a reason for cancelling approved leave.'; end if;
    perform hr.assert_open(r.employee_id, r.start_date, r.end_date);
  elsif not (auth.uid() = r.requested_by or hr.is_me(r.employee_id) or hr.has_perm('LEAVE_APPROVE')) then
    raise exception 'NOT_ALLOWED: Only the requester or HR can withdraw it.' using errcode = '42501';
  end if;
  v_was := r.status;
  update hr.leave_requests set status = 'CANCELLED', cancelled_by = auth.uid(), cancelled_at = now(), cancel_reason = nullif(btrim(p_reason),'')
   where id = p_id returning * into r;
  if v_was = 'APPROVED' then
    insert into hr.leave_ledger(employee_id, leave_type, entry_date, days, kind, request_id, note, created_by)
    values (r.employee_id, r.leave_type, r.start_date, r.days, 'REVERSAL', r.id, 'Cancelled: ' || coalesce(r.cancel_reason,''), auth.uid());
    perform hr.compute_attendance(r.employee_id, r.start_date, r.end_date);
    perform hr.notify(hr.employee_user(r.employee_id), 'LEAVE', 'NORMAL',
      'Approved leave cancelled: ' || to_char(r.start_date,'DD/MM/YYYY'), 'تم إلغاء إجازة معتمدة: ' || to_char(r.start_date,'DD/MM/YYYY'),
      r.cancel_reason, r.cancel_reason, '/leave', 'leave-cancel:' || r.id);
  end if;
  return hr.leave_json(r);
end $$;

create or replace function public.hr_set_ticket_status(p_id uuid, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.leave_requests;
begin
  perform hr.require_perm('LEAVE_WRITE');
  if p_status not in ('REQUESTED','ISSUED','CASH','DECLINED') then raise exception 'INVALID: Unknown ticket status.'; end if;
  update hr.leave_requests set ticket_status = p_status where id = p_id and ticket_requested and status = 'APPROVED' returning * into r;
  if r.id is null then raise exception 'NOT_FOUND: No approved leave with a ticket request.'; end if;
  return hr.leave_json(r);
end $$;

create or replace function public.hr_list_leave_requests(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_status text := hr.jtext(p,'status'); v_emp uuid := hr.juuid(p,'employee_id'); v_type text := hr.jtext(p,'leave_type');
        v_from date := hr.jdate(p,'from'); v_to date := hr.jdate(p,'to'); v_scope text := coalesce(hr.jtext(p,'scope'), 'all');
        v_limit int := least(coalesce(hr.jint(p,'limit'), 100), 500); v_offset int := greatest(coalesce(hr.jint(p,'offset'), 0), 0);
        v_total int; v_rows jsonb;
begin
  perform hr.require_user();
  with base as (
    select r.* from hr.leave_requests r
    where r.employee_id in (select employee_id from hr.visible_employees('LEAVE_READ', hr.juuid(p,'entity_id')))
      and (v_scope <> 'mine' or hr.is_me(r.employee_id))
      and (v_scope <> 'team' or hr.is_my_team(r.employee_id))
      and (v_emp is null or r.employee_id = v_emp)
      and (v_type is null or r.leave_type = v_type)
      and (v_status is null or r.status = v_status or (v_status = 'PENDING' and r.status like 'PENDING%'))
      and (v_from is null or r.end_date >= v_from) and (v_to is null or r.start_date <= v_to))
  select (select count(*) from base),
         coalesce((select jsonb_agg(hr.leave_json(b) order by b.start_date desc, b.requested_at desc)
                   from (select * from base order by start_date desc, requested_at desc limit v_limit offset v_offset) b), '[]'::jsonb)
    into v_total, v_rows;
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $$;

-- Who is away: approved and pending leave per employee per day of a month
create or replace function public.hr_leave_calendar(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_m0 date := hr.month_start(hr.jtext(p,'month')); v_m1 date; v_dep uuid := hr.juuid(p,'department_id'); v_entity uuid := hr.juuid(p,'entity_id');
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  return jsonb_build_object('month', to_char(v_m0,'YYYY-MM'), 'days_in_month', extract(day from v_m1)::int,
    'holidays', coalesce((select jsonb_agg(jsonb_build_object('day', extract(day from h.holiday_date)::int, 'name_en', h.name_en, 'name_ar', h.name_ar))
                          from hr.holidays h where h.is_active and h.holiday_date between v_m0 and v_m1
                            and (h.entity_id is null or v_entity is null or h.entity_id = v_entity)), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(x.j order by x.no) from (
      select e.employee_no no, hr.emp_brief(e.id) || jsonb_build_object('leave', (
        select jsonb_agg(jsonb_build_object('id', r.id, 'leave_type', r.leave_type, 'name_en', t.name_en, 'name_ar', t.name_ar,
                 'status', r.status, 'half_day', r.half_day,
                 'from_day', extract(day from greatest(r.start_date, v_m0))::int, 'to_day', extract(day from least(r.end_date, v_m1))::int)
               order by r.start_date)
        from hr.leave_requests r join hr.leave_types t on t.code = r.leave_type
        where r.employee_id = e.id and r.status in ('PENDING_MANAGER','PENDING_HR','APPROVED')
          and daterange(r.start_date, r.end_date, '[]') && daterange(v_m0, v_m1, '[]'))) j
      from hr.employees e
      where e.id in (select employee_id from hr.visible_employees('LEAVE_READ', v_entity))
        and e.status <> 'SEPARATED'
        and (v_dep is null or (hr.current_assignment(e.id)).department_id = v_dep)
        and (hr.jbool(p,'all_employees') or exists (select 1 from hr.leave_requests r where r.employee_id = e.id
             and r.status in ('PENDING_MANAGER','PENDING_HR','APPROVED') and daterange(r.start_date, r.end_date, '[]') && daterange(v_m0, v_m1, '[]')))
    ) x), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- Balance adjustments (opening balances and corrections) — maker-checker
-- ---------------------------------------------------------------------------
create or replace function hr.adjustment_json(a hr.leave_adjustments)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(a.employee_id) || jsonb_build_object(
    'id', a.id, 'leave_type', a.leave_type, 'name_en', t.name_en, 'name_ar', t.name_ar, 'kind', a.kind, 'days', a.days,
    'effective_date', a.effective_date, 'reason', a.reason, 'status', a.status,
    'proposed_by_name', hr.user_label(a.proposed_by), 'proposed_at', a.proposed_at,
    'decided_by_name', hr.user_label(a.decided_by), 'decided_at', a.decided_at, 'decision_note', a.decision_note,
    'can_decide', a.status = 'PENDING' and hr.has_perm('LEAVE_APPROVE') and auth.uid() <> a.proposed_by and not hr.is_me(a.employee_id))
  from hr.leave_types t where t.code = a.leave_type
$$;

-- rows: [{employee_id | employee_no, leave_type, kind, days, effective_date, reason}]
create or replace function public.hr_propose_leave_adjustments(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r jsonb; i int := 0; v_emp uuid; v_ok int := 0; v_errors jsonb := '[]'::jsonb; v_type text; v_kind text; v_days numeric; v_date date;
begin
  perform hr.require_perm('LEAVE_WRITE');
  if jsonb_typeof(p->'rows') <> 'array' or jsonb_array_length(p->'rows') = 0 then raise exception 'REQUIRED: No rows.'; end if;
  if jsonb_array_length(p->'rows') > 2000 then raise exception 'INVALID: At most 2000 rows at a time.'; end if;
  for r in select * from jsonb_array_elements(p->'rows') loop
    i := i + 1;
    begin
      v_emp := coalesce(hr.juuid(r,'employee_id'), (select id from hr.employees where upper(employee_no) = upper(hr.jtext(r,'employee_no'))));
      if v_emp is null then raise exception 'Employee not found.'; end if;
      if hr.is_me(v_emp) then raise exception 'You cannot adjust your own balance.'; end if;
      v_type := upper(coalesce(hr.jtext(r,'leave_type'), 'ANNUAL'));
      if not exists (select 1 from hr.leave_types where code = v_type) then raise exception 'Unknown leave type %.', v_type; end if;
      v_kind := upper(coalesce(hr.jtext(r,'kind'), 'ADJUSTMENT'));
      if v_kind not in ('OPENING','ADJUSTMENT') then raise exception 'Kind must be OPENING or ADJUSTMENT.'; end if;
      v_days := hr.jnum(r,'days');
      if v_days is null or v_days = 0 then raise exception 'Days must be a non-zero number.'; end if;
      v_date := coalesce(hr.jdate(r,'effective_date'), hr.today());
      if coalesce(length(btrim(hr.jtext(r,'reason'))), 0) < 3 then raise exception 'Give a reason.'; end if;
      if v_kind = 'OPENING' and exists (select 1 from hr.leave_adjustments x where x.employee_id = v_emp and x.leave_type = v_type
                                        and x.kind = 'OPENING' and x.status in ('PENDING','APPROVED')) then
        raise exception 'An opening balance already exists for this leave type.';
      end if;
      insert into hr.leave_adjustments(employee_id, leave_type, kind, days, effective_date, reason, proposed_by)
      values (v_emp, v_type, v_kind, v_days, v_date, btrim(hr.jtext(r,'reason')), auth.uid());
      v_ok := v_ok + 1;
    exception when others then
      if jsonb_array_length(v_errors) < 200 then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', i, 'message', regexp_replace(sqlerrm, '^[A-Z_]+: ', '')));
      end if;
    end;
  end loop;
  if v_ok > 0 then
    perform hr.notify_approvers(null, 'PENDING_HR', 'LEAVE_APPROVE', 'LEAVE_ADJ', v_ok || ' leave balance adjustments waiting',
      v_ok || ' تعديل رصيد إجازات بانتظار الاعتماد', '/approvals', 'leave-adj:' || now()::text);
  end if;
  return jsonb_build_object('proposed', v_ok, 'errors', v_errors);
end $$;

create or replace function public.hr_decide_leave_adjustments(p_ids uuid[], p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.leave_adjustments; v_n int := 0;
begin
  perform hr.require_perm('LEAVE_APPROVE');
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  for a in select * from hr.leave_adjustments where id = any(p_ids) and status = 'PENDING' for update loop
    if a.proposed_by = auth.uid() then raise exception 'SELF_APPROVAL: Someone other than the proposer must approve this.'; end if;
    if hr.is_me(a.employee_id) then raise exception 'SELF_APPROVAL: You cannot approve your own balance.'; end if;
    update hr.leave_adjustments set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(),
           decided_at = now(), decision_note = nullif(btrim(p_note),'') where id = a.id;
    if p_approve then
      insert into hr.leave_ledger(employee_id, leave_type, entry_date, days, kind, adjustment_id, note, created_by)
      values (a.employee_id, a.leave_type, a.effective_date, a.days, a.kind, a.id, a.reason, auth.uid());
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'NOT_FOUND: Nothing is waiting.'; end if;
  return jsonb_build_object('decided', v_n);
end $$;

create or replace function public.hr_list_leave_adjustments(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_status text := hr.jtext(p,'status'); v_emp uuid := hr.juuid(p,'employee_id');
begin
  perform hr.require_perm('LEAVE_READ');
  return coalesce((select jsonb_agg(hr.adjustment_json(a) order by a.proposed_at desc)
    from (select * from hr.leave_adjustments a where (v_status is null or a.status = v_status) and (v_emp is null or a.employee_id = v_emp)
          order by a.proposed_at desc limit 500) a), '[]'::jsonb);
end $$;

create or replace function public.hr_run_leave_accrual(p_through date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_through date := coalesce(p_through, (date_trunc('month', hr.today()) - interval '1 day')::date);
begin
  perform hr.require_perm('LEAVE_WRITE');
  if v_through > hr.today() then raise exception 'INVALID: Accrual cannot run for future dates.'; end if;
  return jsonb_build_object('created', hr.accrue_leave(v_through), 'through', v_through);
end $$;

create or replace function public.hr_close_leave_year(p_year int)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform hr.require_perm('LEAVE_APPROVE');
  if make_date(p_year, 12, 31) >= hr.today() then raise exception 'INVALID: Only a finished year can be closed.'; end if;
  return jsonb_build_object('lapsed', hr.close_leave_year(p_year), 'year', p_year);
end $$;

-- ---------------------------------------------------------------------------
-- My tasks (everything the caller can decide) and the time dashboard
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
                       where t.status = 'PENDING' and t.proposed_by is distinct from auth.uid()), '[]'::jsonb) else '[]'::jsonb end)
  into v_res;
  return v_res || jsonb_build_object('count',
    jsonb_array_length(v_res->'leave') + jsonb_array_length(v_res->'corrections') + jsonb_array_length(v_res->'overtime')
    + jsonb_array_length(v_res->'adjustments') + jsonb_array_length(v_res->'rules'));
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
                     order by r.start_date limit 1)));
  end if;
  v_tasks := public.hr_list_my_tasks();
  return v_res || jsonb_build_object('tasks', jsonb_build_object(
    'leave', jsonb_array_length(v_tasks->'leave'), 'corrections', jsonb_array_length(v_tasks->'corrections'),
    'overtime', jsonb_array_length(v_tasks->'overtime'), 'adjustments', jsonb_array_length(v_tasks->'adjustments'),
    'rules', jsonb_array_length(v_tasks->'rules'), 'count', (v_tasks->>'count')::int));
end $$;


-- Settings: add the leave opening date (accrual starts from it; opening balances are entered as at that date).
create or replace function public.hr_save_setting(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform hr.require_perm('USERS_ADMIN');
  if p_key not in ('employee_no_prefix','employee_no_digits','default_language','date_format','expiry_horizon_days','leave_opening_date') then
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
  insert into hr.settings(key, value, updated_by) values (p_key, p_value, auth.uid())
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  return (select jsonb_object_agg(key, value) from hr.settings);
end $$;

select hr.attach_audit();
select hr.secure_api();
