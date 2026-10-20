-- AACT HRMS — 008 API: compensation (maker-checker), bank accounts (maker-checker), documents

create or replace function hr.revision_json(r hr.compensation_revisions)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(r) || jsonb_build_object(
    'proposed_by_name', hr.user_label(r.proposed_by),
    'decided_by_name', hr.user_label(r.decided_by),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('component_code', l.component_code, 'amount', l.amount,
                              'name_en', c.name_en, 'name_ar', c.name_ar, 'kind', c.kind) order by c.sort)
                       from hr.compensation_lines l join hr.pay_components c on c.code = l.component_code
                       where l.revision_id = r.id), '[]'::jsonb))
$$;

create or replace function hr.salary_access(p_employee uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  v := hr.require_employee_access(p_employee);
  if hr.is_me(p_employee) and not hr.has_perm('EMP_SALARY_READ') then return 'SELF'; end if;
  if hr.has_perm('EMP_SALARY_READ') or hr.has_perm('EMP_SALARY_WRITE') or hr.has_perm('SALARY_APPROVE') then
    return 'FULL';
  end if;
  raise exception 'NOT_ALLOWED: You cannot see salary details.' using errcode = '42501';
end $$;

create or replace function public.hr_get_compensation(p_employee uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access text; v_cur hr.compensation_revisions; v_a hr.employee_assignments; v_grade hr.grades;
begin
  v_access := hr.salary_access(p_employee);
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), p_employee, 'SALARY', 'view');
  select * into v_cur from hr.compensation_revisions
   where employee_id = p_employee and status = 'APPROVED' and effective_from <= current_date
   order by effective_from desc limit 1;
  v_a := hr.current_assignment(p_employee);
  select * into v_grade from hr.grades where id = v_a.grade_id;
  return jsonb_build_object(
    'current', case when v_cur.id is null then null else hr.revision_json(v_cur) end,
    'scheduled', coalesce((select jsonb_agg(hr.revision_json(r) order by r.effective_from)
                           from hr.compensation_revisions r
                           where r.employee_id = p_employee and r.status = 'APPROVED' and r.effective_from > current_date), '[]'::jsonb),
    'pending', case when v_access = 'FULL' then (select hr.revision_json(r) from hr.compensation_revisions r
                                                 where r.employee_id = p_employee and r.status = 'PENDING') end,
    'history', coalesce((select jsonb_agg(hr.revision_json(r) order by r.effective_from desc, r.created_at desc)
                         from hr.compensation_revisions r
                         where r.employee_id = p_employee
                           and (v_access = 'FULL' or r.status in ('APPROVED','SUPERSEDED'))), '[]'::jsonb),
    'grade', case when v_grade.id is null then null else jsonb_build_object('code', v_grade.code, 'name_en', v_grade.name_en,
                  'name_ar', v_grade.name_ar, 'min_basic', v_grade.min_basic, 'max_basic', v_grade.max_basic) end,
    'access', v_access);
end $$;

create or replace function public.hr_propose_compensation(p_employee uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  e hr.employees; v_from date := hr.jdate(p,'effective_from'); v_reason text := coalesce(hr.jtext(p,'reason'),'INCREMENT');
  v_line jsonb; v_code text; v_amt numeric; v_basic numeric; v_gross numeric := 0; v_rev uuid;
  v_codes text[] := '{}'; v_warn jsonb := '[]'::jsonb; v_grade hr.grades; u record;
begin
  perform hr.require_perm('EMP_SALARY_WRITE');
  select * into e from hr.employees where id = p_employee;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if hr.is_me(p_employee) then
    raise exception 'NOT_ALLOWED: You cannot propose your own salary.' using errcode = '42501';
  end if;
  if e.status = 'SEPARATED' then raise exception 'INVALID: This employee has left.'; end if;
  if v_from is null then raise exception 'REQUIRED: Effective date is required.'; end if;
  if v_from < e.join_date then raise exception 'INVALID: The salary cannot start before the joining date.'; end if;
  if v_reason not in ('JOIN','INCREMENT','PROMOTION','ADJUSTMENT','CORRECTION','REHIRE') then
    raise exception 'INVALID: Unknown reason.';
  end if;
  if jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then
    raise exception 'REQUIRED: Enter at least the basic salary.';
  end if;
  if exists (select 1 from hr.compensation_revisions where employee_id = p_employee and status = 'PENDING') then
    raise exception 'PENDING_EXISTS: A salary revision for this employee is already waiting for approval.';
  end if;

  insert into hr.compensation_revisions(employee_id, effective_from, reason, notes, proposed_by)
  values (p_employee, v_from, v_reason, hr.jtext(p,'notes'), auth.uid())
  returning id into v_rev;

  for v_line in select * from jsonb_array_elements(p->'lines') loop
    v_code := upper(hr.jtext(v_line,'component_code'));
    v_amt := hr.jmoney(v_line,'amount');
    if v_code is null or not exists (select 1 from hr.pay_components where code = v_code and is_active) then
      raise exception 'INVALID: Unknown pay component %.', coalesce(v_code,'(blank)');
    end if;
    if v_code = any(v_codes) then raise exception 'INVALID: % is entered twice.', v_code; end if;
    v_codes := v_codes || v_code;
    continue when v_amt is null or (v_amt = 0 and v_code <> 'BASIC');
    insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (v_rev, p_employee, v_code, v_amt);
    if v_code = 'BASIC' then v_basic := v_amt; end if;
    if (select kind from hr.pay_components where code = v_code) = 'EARNING' then v_gross := v_gross + v_amt; end if;
  end loop;
  if coalesce(v_basic, 0) <= 0 then raise exception 'REQUIRED: The basic salary must be more than zero.'; end if;
  update hr.compensation_revisions set total_monthly = v_gross where id = v_rev;

  select g.* into v_grade from hr.grades g
   join hr.employee_assignments a on a.grade_id = g.id
  where a.employee_id = p_employee and a.effective_from <= v_from and (a.effective_to is null or a.effective_to >= v_from);
  if v_grade.id is not null and ((v_grade.min_basic is not null and v_basic < v_grade.min_basic)
                              or (v_grade.max_basic is not null and v_basic > v_grade.max_basic)) then
    v_warn := v_warn || jsonb_build_object('code', 'OUTSIDE_GRADE_BAND',
                'message', format('Basic %s is outside grade %s band (%s – %s).', v_basic, v_grade.code,
                                  coalesce(v_grade.min_basic::text,'—'), coalesce(v_grade.max_basic::text,'—')));
  end if;

  for u in select h.user_id from hr.users_with_perm('SALARY_APPROVE') h where h.user_id <> auth.uid() loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
      'Salary revision awaiting approval — ' || e.full_name_en, 'مراجعة راتب بانتظار الاعتماد — ' || coalesce(e.full_name_ar, e.full_name_en),
      e.employee_no || ': effective ' || to_char(v_from,'DD/MM/YYYY') || '.', e.employee_no || ': اعتباراً من ' || to_char(v_from,'DD/MM/YYYY') || '.',
      '/employees/' || p_employee || '?tab=pay', 'SAL:' || v_rev);
  end loop;
  return jsonb_build_object('revision_id', v_rev, 'warnings', v_warn, 'compensation', public.hr_get_compensation(p_employee));
end $$;

create or replace function public.hr_decide_compensation(p_revision uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.compensation_revisions; v_emp hr.employees;
begin
  perform hr.require_perm('SALARY_APPROVE');
  select * into r from hr.compensation_revisions where id = p_revision for update;
  if r.id is null then raise exception 'NOT_FOUND: Salary revision not found.'; end if;
  if r.status <> 'PENDING' then raise exception 'INVALID: This revision has already been decided.'; end if;
  if r.proposed_by = auth.uid() then
    raise exception 'SELF_APPROVAL: You proposed this revision; someone else must approve it.' using errcode = '42501';
  end if;
  if hr.is_me(r.employee_id) then
    raise exception 'NOT_ALLOWED: You cannot approve your own salary.' using errcode = '42501';
  end if;
  if not p_approve and nullif(btrim(p_note),'') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  select * into v_emp from hr.employees where id = r.employee_id;

  if p_approve then
    update hr.compensation_revisions set status = 'SUPERSEDED'
     where employee_id = r.employee_id and status = 'APPROVED' and effective_from = r.effective_from;
    update hr.compensation_revisions set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(),
           decision_note = nullif(btrim(p_note),'') where id = r.id;
    perform hr.add_event(r.employee_id, 'SALARY_REVISION', r.effective_from,
                         jsonb_build_object('revision_id', r.id, 'reason', r.reason));
  else
    update hr.compensation_revisions set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(),
           decision_note = btrim(p_note) where id = r.id;
  end if;
  perform hr.notify(r.proposed_by, 'DECISION', 'NORMAL',
    'Salary revision ' || case when p_approve then 'approved' else 'rejected' end || ' — ' || v_emp.full_name_en,
    case when p_approve then 'تم اعتماد مراجعة الراتب' else 'تم رفض مراجعة الراتب' end || ' — ' || coalesce(v_emp.full_name_ar, v_emp.full_name_en),
    nullif(btrim(p_note),''), nullif(btrim(p_note),''), '/employees/' || r.employee_id || '?tab=pay', 'SALDEC:' || r.id);
  return public.hr_get_compensation(r.employee_id);
end $$;

create or replace function public.hr_withdraw_compensation(p_revision uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.compensation_revisions;
begin
  perform hr.require_perm('EMP_SALARY_WRITE');
  select * into r from hr.compensation_revisions where id = p_revision for update;
  if r.id is null or r.status <> 'PENDING' then raise exception 'NOT_FOUND: No pending revision to withdraw.'; end if;
  if r.proposed_by <> auth.uid() then raise exception 'NOT_ALLOWED: Only the person who proposed it can withdraw it.' using errcode = '42501'; end if;
  update hr.compensation_revisions set status = 'REJECTED', decided_at = now(), decision_note = 'Withdrawn by proposer' where id = r.id;
  return public.hr_get_compensation(r.employee_id);
end $$;

create or replace function public.hr_list_pending_approvals()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := hr.require_user(); v_emp uuid := hr.my_employee_id();
begin
  return jsonb_build_object(
    'salary', case when hr.has_perm('SALARY_APPROVE') then coalesce((
       select jsonb_agg(jsonb_build_object('id', r.id, 'employee_id', r.employee_id, 'employee_no', e.employee_no,
              'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar, 'effective_from', r.effective_from,
              'reason', r.reason, 'total_monthly', r.total_monthly, 'proposed_by_name', hr.user_label(r.proposed_by),
              'proposed_at', r.proposed_at, 'can_decide', r.proposed_by <> v_me and r.employee_id is distinct from v_emp)
              order by r.proposed_at)
       from hr.compensation_revisions r join hr.employees e on e.id = r.employee_id where r.status = 'PENDING'), '[]'::jsonb)
       else '[]'::jsonb end,
    'bank', case when hr.has_perm('BANK_APPROVE') then coalesce((
       select jsonb_agg(jsonb_build_object('id', b.id, 'employee_id', b.employee_id, 'employee_no', e.employee_no,
              'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar, 'bank_name', b.bank_name,
              'account_number', hr.mask_tail(b.account_number), 'requested_by_name', hr.user_label(b.requested_by),
              'requested_at', b.requested_at, 'can_decide', b.requested_by <> v_me and b.employee_id is distinct from v_emp)
              order by b.requested_at)
       from hr.employee_bank_accounts b join hr.employees e on e.id = b.employee_id where b.status = 'PENDING'), '[]'::jsonb)
       else '[]'::jsonb end,
    'targets', case when hr.has_perm('RULES_APPROVE') then coalesce((
       select jsonb_agg(jsonb_build_object('id', t.id, 'entity_id', t.entity_id, 'scope_type', t.scope_type,
              'target_pct', t.target_pct, 'effective_from', t.effective_from, 'source_reference', t.source_reference,
              'proposed_by_name', hr.user_label(t.proposed_by), 'proposed_at', t.proposed_at,
              'can_decide', t.proposed_by <> v_me) order by t.proposed_at)
       from hr.omanisation_targets t where t.status = 'PENDING'), '[]'::jsonb)
       else '[]'::jsonb end);
end $$;

-- ---------------------------------------------------------------------------
-- Bank accounts
-- ---------------------------------------------------------------------------
create or replace function hr.bank_json(b hr.employee_bank_accounts, p_full boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(b) || jsonb_build_object(
    'account_number', case when p_full then b.account_number else hr.mask_tail(b.account_number) end,
    'iban', case when p_full then b.iban else hr.mask_tail(b.iban) end,
    'masked', not p_full,
    'requested_by_name', hr.user_label(b.requested_by),
    'decided_by_name', hr.user_label(b.decided_by))
$$;

create or replace function public.hr_get_bank(p_employee uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_access text; v_full boolean;
begin
  v_access := hr.require_employee_access(p_employee);
  if not hr.is_me(p_employee)
     and not (hr.has_perm('EMP_BANK_READ') or hr.has_perm('EMP_BANK_WRITE') or hr.has_perm('BANK_APPROVE')) then
    raise exception 'NOT_ALLOWED: You cannot see bank details.' using errcode = '42501';
  end if;
  v_full := hr.is_me(p_employee) or hr.has_perm('EMP_BANK_READ') or hr.has_perm('BANK_APPROVE');
  if v_full then
    insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), p_employee, 'BANK', 'view');
  end if;
  return jsonb_build_object(
    'current', (select hr.bank_json(b, v_full) from hr.employee_bank_accounts b where b.employee_id = p_employee and b.status = 'APPROVED'),
    'pending', (select hr.bank_json(b, v_full) from hr.employee_bank_accounts b where b.employee_id = p_employee and b.status = 'PENDING'),
    'history', coalesce((select jsonb_agg(hr.bank_json(b, v_full) order by b.requested_at desc)
                         from hr.employee_bank_accounts b where b.employee_id = p_employee
                           and b.status in ('SUPERSEDED','REJECTED')), '[]'::jsonb));
end $$;

create or replace function public.hr_request_bank_change(p_employee uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e hr.employees; v_acc text := upper(regexp_replace(coalesce(p->>'account_number',''), '\s', '', 'g'));
        v_iban text := nullif(upper(regexp_replace(coalesce(p->>'iban',''), '\s', '', 'g')), '');
        v_swift text := nullif(upper(btrim(coalesce(p->>'swift_code',''))), ''); v_id uuid; u record;
begin
  perform hr.require_perm('EMP_BANK_WRITE');
  select * into e from hr.employees where id = p_employee;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if hr.is_me(p_employee) then raise exception 'NOT_ALLOWED: You cannot change your own bank account here.' using errcode = '42501'; end if;
  if hr.jtext(p,'bank_name') is null then raise exception 'REQUIRED: Bank name is required.'; end if;
  if hr.jtext(p,'account_name') is null then raise exception 'REQUIRED: Account holder name is required.'; end if;
  if v_acc !~ '^[A-Z0-9-]{5,34}$' then raise exception 'INVALID: Account number must be 5–34 letters or digits.'; end if;
  if v_iban is not null and v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$' then raise exception 'INVALID: IBAN format is not valid.'; end if;
  if v_swift is not null and v_swift !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then raise exception 'INVALID: SWIFT / BIC must be 8 or 11 characters.'; end if;
  if exists (select 1 from hr.employee_bank_accounts where employee_id = p_employee and status = 'PENDING') then
    raise exception 'PENDING_EXISTS: A bank change for this employee is already waiting for approval.';
  end if;
  insert into hr.employee_bank_accounts(employee_id, bank_name, branch, account_name, account_number, iban, swift_code,
                                        effective_from, requested_by)
  values (p_employee, hr.jtext(p,'bank_name'), hr.jtext(p,'branch'), hr.jtext(p,'account_name'), v_acc, v_iban, v_swift,
          coalesce(hr.jdate(p,'effective_from'), current_date), auth.uid())
  returning id into v_id;
  for u in select h.user_id from hr.users_with_perm('BANK_APPROVE') h where h.user_id <> auth.uid() loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
      'Bank account change awaiting approval — ' || e.full_name_en, 'تغيير الحساب البنكي بانتظار الاعتماد — ' || coalesce(e.full_name_ar, e.full_name_en),
      e.employee_no, e.employee_no, '/employees/' || p_employee || '?tab=bank', 'BANK:' || v_id);
  end loop;
  return public.hr_get_bank(p_employee);
end $$;

create or replace function public.hr_decide_bank(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare b hr.employee_bank_accounts; v_emp hr.employees;
begin
  perform hr.require_perm('BANK_APPROVE');
  select * into b from hr.employee_bank_accounts where id = p_id for update;
  if b.id is null then raise exception 'NOT_FOUND: Bank change not found.'; end if;
  if b.status <> 'PENDING' then raise exception 'INVALID: This change has already been decided.'; end if;
  if b.requested_by = auth.uid() then raise exception 'SELF_APPROVAL: You requested this change; someone else must approve it.' using errcode = '42501'; end if;
  if hr.is_me(b.employee_id) then raise exception 'NOT_ALLOWED: You cannot approve your own bank account.' using errcode = '42501'; end if;
  if not p_approve and nullif(btrim(p_note),'') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  select * into v_emp from hr.employees where id = b.employee_id;
  if p_approve then
    update hr.employee_bank_accounts set status = 'SUPERSEDED' where employee_id = b.employee_id and status = 'APPROVED';
    update hr.employee_bank_accounts set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(),
           decision_note = nullif(btrim(p_note),'') where id = b.id;
    perform hr.add_event(b.employee_id, 'BANK_CHANGE', coalesce(b.effective_from, current_date),
                         jsonb_build_object('bank_name', b.bank_name, 'account_ending', right(b.account_number, 4)));
  else
    update hr.employee_bank_accounts set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(),
           decision_note = btrim(p_note) where id = b.id;
  end if;
  perform hr.notify(b.requested_by, 'DECISION', 'NORMAL',
    'Bank change ' || case when p_approve then 'approved' else 'rejected' end || ' — ' || v_emp.full_name_en,
    case when p_approve then 'تم اعتماد تغيير الحساب البنكي' else 'تم رفض تغيير الحساب البنكي' end || ' — ' || coalesce(v_emp.full_name_ar, v_emp.full_name_en),
    nullif(btrim(p_note),''), nullif(btrim(p_note),''), '/employees/' || b.employee_id || '?tab=bank', 'BANKDEC:' || b.id);
  return public.hr_get_bank(b.employee_id);
end $$;

-- ---------------------------------------------------------------------------
-- Documents
-- ---------------------------------------------------------------------------
create or replace function hr.document_json(d hr.employee_documents)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(d) || jsonb_build_object(
    'name_en', t.name_en, 'name_ar', t.name_ar, 'category', t.category, 'is_sensitive', t.is_sensitive,
    'has_expiry', t.has_expiry,
    'days_left', case when d.expiry_date is null then null else (d.expiry_date - current_date) end,
    'bucket', case when d.expiry_date is null or d.status <> 'ACTIVE' then null
                   else hr.expiry_bucket((d.expiry_date - current_date)::int) end,
    'uploaded_by_name', hr.user_label(d.uploaded_by),
    'verified_by_name', hr.user_label(d.verified_by))
  from hr.document_types t where t.code = d.doc_type
$$;

-- What the caller may see of this employee's documents: 'ALL', 'NON_SENSITIVE' or null.
create or replace function hr.document_scope(p_employee uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v text := hr.require_employee_access(p_employee);
begin
  if hr.is_me(p_employee) or (hr.has_perm('DOC_READ') and hr.has_perm('DOC_SENSITIVE')) then return 'ALL'; end if;
  if hr.has_perm('DOC_READ') then return 'NON_SENSITIVE'; end if;
  return null;
end $$;

create or replace function public.hr_list_employee_documents(p_employee uuid, p_include_history boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_scope text; e hr.employees;
begin
  v_scope := hr.document_scope(p_employee);
  if v_scope is null then raise exception 'NOT_ALLOWED: You cannot see this employee''s documents.' using errcode = '42501'; end if;
  select * into e from hr.employees where id = p_employee;
  return jsonb_build_object(
    'documents', coalesce((
      select jsonb_agg(hr.document_json(d) order by t.sort, d.doc_type, d.is_current desc, d.version desc)
      from hr.employee_documents d join hr.document_types t on t.code = d.doc_type
      where d.employee_id = p_employee
        and (p_include_history or d.is_current)
        and (v_scope = 'ALL' or not t.is_sensitive)), '[]'::jsonb),
    'checklist', coalesce((
      select jsonb_agg(jsonb_build_object('doc_type', t.code, 'name_en', t.name_en, 'name_ar', t.name_ar,
               'status', case when cur.id is null then 'MISSING'
                              when cur.expiry_date is not null and cur.expiry_date < current_date then 'EXPIRED'
                              when cur.expiry_date is not null and cur.expiry_date <= current_date + 30 then 'EXPIRING'
                              else 'OK' end,
               'expiry_date', cur.expiry_date) order by t.sort)
      from hr.document_types t
      left join lateral (select d.id, d.expiry_date from hr.employee_documents d
                         where d.employee_id = p_employee and d.doc_type = t.code and d.is_current
                         order by d.expiry_date desc nulls first limit 1) cur on true
      where t.is_active and t.is_mandatory
        and (t.applies_to = 'ALL' or (t.applies_to = 'OMANI' and e.nationality = 'OM')
             or (t.applies_to = 'EXPAT' and e.nationality <> 'OM'))
        and (v_scope = 'ALL' or not t.is_sensitive)), '[]'::jsonb),
    'scope', v_scope);
end $$;

create or replace function public.hr_save_document(p_employee uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  e hr.employees; t hr.document_types; v_id uuid := hr.juuid(p,'id'); v_replace uuid := hr.juuid(p,'replace_id');
  v_old hr.employee_documents; v_path text := hr.jtext(p,'file_path'); v_new uuid; v_version int := 1;
  v_issue date := hr.jdate(p,'issue_date'); v_expiry date := hr.jdate(p,'expiry_date');
begin
  perform hr.require_perm('DOC_WRITE');
  select * into e from hr.employees where id = p_employee;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;

  if v_id is not null then
    -- correct the details of the current version (file and type stay)
    select * into v_old from hr.employee_documents where id = v_id and employee_id = p_employee for update;
    if v_old.id is null or not v_old.is_current then raise exception 'NOT_FOUND: Only the current version can be corrected.'; end if;
    select * into t from hr.document_types where code = v_old.doc_type;
  else
    select * into t from hr.document_types where code = upper(hr.jtext(p,'doc_type')) and is_active;
    if t.code is null then raise exception 'REQUIRED: Choose a document type.'; end if;
  end if;

  if t.has_number and hr.jtext(p,'doc_number') is null then raise exception 'REQUIRED: Document number is required for %.', t.name_en; end if;
  if t.has_expiry and v_expiry is null then raise exception 'REQUIRED: Expiry date is required for %.', t.name_en; end if;
  if v_issue is not null and v_issue > current_date then raise exception 'INVALID: The issue date is in the future.'; end if;
  if v_issue is not null and v_expiry is not null and v_expiry < v_issue then raise exception 'INVALID: The expiry date is before the issue date.'; end if;

  if v_id is not null then
    update hr.employee_documents set doc_number = hr.jtext(p,'doc_number'), title = hr.jtext(p,'title'),
           issue_date = v_issue, expiry_date = v_expiry, issuing_authority = hr.jtext(p,'issuing_authority'),
           issue_place = hr.jtext(p,'issue_place'), notes = hr.jtext(p,'notes'),
           verified_by = null, verified_at = null
     where id = v_id;
    return (select hr.document_json(d) from hr.employee_documents d where d.id = v_id);
  end if;

  if v_path is not null then
    if v_path not like p_employee::text || '/' || t.code || '/%' then
      raise exception 'INVALID: The file was not uploaded for this employee and document type.';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'hr-documents' and o.name = v_path) then
      raise exception 'INVALID: The uploaded file was not found. Upload it again.';
    end if;
  end if;

  if v_replace is not null then
    select * into v_old from hr.employee_documents where id = v_replace and employee_id = p_employee for update;
    if v_old.id is null or not v_old.is_current then raise exception 'NOT_FOUND: The document to replace is not current.'; end if;
    if v_old.doc_type <> t.code then raise exception 'INVALID: A replacement must be the same document type.'; end if;
    update hr.employee_documents set is_current = false, status = 'SUPERSEDED' where id = v_old.id;
    v_version := v_old.version + 1;
  end if;

  insert into hr.employee_documents(employee_id, doc_type, doc_number, title, issue_date, expiry_date, issuing_authority,
                                    issue_place, version, supersedes_id, file_path, file_name, mime_type, file_size,
                                    notes, uploaded_by)
  values (p_employee, t.code, hr.jtext(p,'doc_number'), hr.jtext(p,'title'), v_issue, v_expiry, hr.jtext(p,'issuing_authority'),
          hr.jtext(p,'issue_place'), v_version, v_old.id, v_path, hr.jtext(p,'file_name'), hr.jtext(p,'mime_type'),
          nullif(p->>'file_size','')::bigint, hr.jtext(p,'notes'), auth.uid())
  returning id into v_new;
  return (select hr.document_json(d) from hr.employee_documents d where d.id = v_new);
exception
  when unique_violation then raise exception 'DUPLICATE: This file is already attached to another document.';
  when check_violation then raise exception 'INVALID: %', sqlerrm;
end $$;

create or replace function public.hr_cancel_document(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d hr.employee_documents;
begin
  perform hr.require_perm('DOC_WRITE');
  if nullif(btrim(p_reason),'') is null then raise exception 'REQUIRED: Give the reason for cancelling.'; end if;
  select * into d from hr.employee_documents where id = p_id for update;
  if d.id is null or not d.is_current then raise exception 'NOT_FOUND: Only a current document can be cancelled.'; end if;
  update hr.employee_documents set status = 'CANCELLED', is_current = false, cancel_reason = btrim(p_reason) where id = p_id;
  return (select hr.document_json(x) from hr.employee_documents x where x.id = p_id);
end $$;

create or replace function public.hr_verify_document(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d hr.employee_documents;
begin
  perform hr.require_perm('DOC_WRITE');
  select * into d from hr.employee_documents where id = p_id for update;
  if d.id is null or not d.is_current then raise exception 'NOT_FOUND: Only a current document can be verified.'; end if;
  if d.uploaded_by = auth.uid() then
    raise exception 'SELF_APPROVAL: You uploaded this document; someone else must verify it against the original.' using errcode = '42501';
  end if;
  if exists (select 1 from hr.document_types t where t.code = d.doc_type and t.is_sensitive) and not hr.has_perm('DOC_SENSITIVE') then
    raise exception 'NOT_ALLOWED: You cannot verify this document.' using errcode = '42501';
  end if;
  update hr.employee_documents set verified_by = auth.uid(), verified_at = now() where id = p_id;
  return (select hr.document_json(x) from hr.employee_documents x where x.id = p_id);
end $$;

-- Permission check + access log before the app asks Storage for a signed URL.
create or replace function public.hr_document_file(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d hr.employee_documents; v_scope text; v_sensitive boolean;
begin
  select * into d from hr.employee_documents where id = p_id;
  if d.id is null then raise exception 'NOT_FOUND: Document not found.'; end if;
  v_scope := hr.document_scope(d.employee_id);
  select is_sensitive into v_sensitive from hr.document_types where code = d.doc_type;
  if v_scope is null or (v_sensitive and v_scope <> 'ALL') then
    raise exception 'NOT_ALLOWED: You cannot open this document.' using errcode = '42501';
  end if;
  if d.file_path is null then raise exception 'NOT_FOUND: No file is attached to this document.'; end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail)
  values (auth.uid(), d.employee_id, case when v_sensitive then 'SENSITIVE_DOCUMENT' else 'DOCUMENT' end, d.doc_type || ' v' || d.version);
  return jsonb_build_object('file_path', d.file_path, 'file_name', d.file_name, 'mime_type', d.mime_type);
end $$;

select hr.secure_api();
