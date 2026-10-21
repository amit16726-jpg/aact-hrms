-- AACT HRMS — 031 API: self-service portal, change requests, letters, manager team view, e-mail, PDPL data export.
-- Idempotent; no destructive statements.

-- ---------------------------------------------------------------------------
-- Change requests
-- ---------------------------------------------------------------------------
create or replace function public.hr_request_change(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_emp uuid := hr.my_employee_id(); e hr.employees; v_kind text := upper(coalesce(hr.jtext(p,'kind'), '')); v_changes jsonb := '{}'::jsonb;
  f text; v_new text; v_old text; x jsonb; v_list jsonb := '[]'::jsonb; c hr.change_requests; u record;
  v_acc text; v_iban text; v_swift text; v_reason text := hr.jtext(p,'reason');
begin
  perform hr.require_user();
  if v_emp is null then raise exception 'NOT_LINKED: Your login is not linked to an employee record. Ask HR to link it.'; end if;
  select * into e from hr.employees where id = v_emp;
  if v_kind not in ('PROFILE','EMERGENCY','BANK','CORRECTION') then raise exception 'INVALID: Unknown request type.'; end if;
  if v_kind <> 'CORRECTION' and exists (select 1 from hr.change_requests where employee_id = v_emp and kind = v_kind and status = 'PENDING') then
    raise exception 'PENDING_EXISTS: You already have a request of this type waiting. Cancel it first or wait for HR.';
  end if;

  if v_kind = 'PROFILE' then
    for f in select unnest(hr.ss_profile_fields()) loop
      continue when not (coalesce(p->'changes', '{}'::jsonb) ? f);
      v_new := nullif(btrim(p->'changes'->>f), '');
      v_old := to_jsonb(e)->>f;
      continue when v_new is not distinct from v_old;
      if f in ('mobile','alt_phone') then perform hr.check_phone(v_new, case f when 'mobile' then 'Mobile' else 'Alternative phone' end); end if;
      if f = 'personal_email' then perform hr.check_email(v_new, 'Personal e-mail'); end if;
      if f = 'marital_status' and v_new is not null and v_new not in ('SINGLE','MARRIED','DIVORCED','WIDOWED') then
        raise exception 'INVALID: Marital status is not valid.';
      end if;
      if f = 'address_country' and v_new is not null then
        v_new := upper(v_new);
        if not exists (select 1 from hr.countries where code = v_new) then raise exception 'INVALID: Country is not valid.'; end if;
      end if;
      if f = 'mobile' and v_new is null then raise exception 'REQUIRED: Mobile cannot be removed.'; end if;
      v_changes := v_changes || jsonb_build_object(f, jsonb_build_object('old', v_old, 'new', v_new));
    end loop;
    if v_changes = '{}'::jsonb then raise exception 'NO_CHANGE: Nothing was changed.'; end if;
  elsif v_kind = 'EMERGENCY' then
    if jsonb_typeof(p->'contacts') <> 'array' or jsonb_array_length(p->'contacts') = 0 then
      raise exception 'REQUIRED: Give at least one emergency contact.';
    end if;
    if jsonb_array_length(p->'contacts') > 5 then raise exception 'INVALID: Up to 5 emergency contacts.'; end if;
    for x in select * from jsonb_array_elements(p->'contacts') loop
      if hr.jtext(x,'name') is null then raise exception 'REQUIRED: Contact name is required.'; end if;
      if hr.jtext(x,'relationship') is null then raise exception 'REQUIRED: Relationship is required.'; end if;
      if hr.jtext(x,'phone') is null then raise exception 'REQUIRED: Phone is required.'; end if;
      perform hr.check_phone(hr.jtext(x,'phone'), 'Phone');
      perform hr.check_phone(hr.jtext(x,'alt_phone'), 'Alternative phone');
      v_list := v_list || jsonb_build_array(jsonb_build_object('name', hr.jtext(x,'name'), 'relationship', hr.jtext(x,'relationship'),
        'phone', hr.jtext(x,'phone'), 'alt_phone', hr.jtext(x,'alt_phone'), 'address', hr.jtext(x,'address'),
        'is_next_of_kin', hr.jbool(x,'is_next_of_kin')));
    end loop;
    v_changes := jsonb_build_object('contacts', v_list,
      'previous', coalesce((select jsonb_agg(jsonb_build_object('name', ec.name, 'relationship', ec.relationship, 'phone', ec.phone,
                  'alt_phone', ec.alt_phone, 'address', ec.address, 'is_next_of_kin', ec.is_next_of_kin) order by ec.created_at)
                  from hr.emergency_contacts ec where ec.employee_id = v_emp and ec.is_active), '[]'::jsonb));
  elsif v_kind = 'BANK' then
    v_acc := upper(regexp_replace(coalesce(p->>'account_number',''), '\s', '', 'g'));
    v_iban := nullif(upper(regexp_replace(coalesce(p->>'iban',''), '\s', '', 'g')), '');
    v_swift := nullif(upper(btrim(coalesce(p->>'swift_code',''))), '');
    if hr.jtext(p,'bank_name') is null then raise exception 'REQUIRED: Bank name is required.'; end if;
    if hr.jtext(p,'account_name') is null then raise exception 'REQUIRED: Account holder name is required.'; end if;
    if v_acc !~ '^[A-Z0-9-]{5,34}$' then raise exception 'INVALID: Account number must be 5–34 letters or digits.'; end if;
    if v_iban is not null and v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$' then raise exception 'INVALID: IBAN format is not valid.'; end if;
    if v_swift is not null and v_swift !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then raise exception 'INVALID: SWIFT / BIC must be 8 or 11 characters.'; end if;
    v_changes := jsonb_build_object('bank_name', hr.jtext(p,'bank_name'), 'branch', hr.jtext(p,'branch'), 'account_name', hr.jtext(p,'account_name'),
      'account_number', v_acc, 'iban', v_iban, 'swift_code', v_swift);
  else
    if v_reason is null or length(v_reason) < 10 then
      raise exception 'REQUIRED: Describe what is wrong and what the correct information is (at least 10 characters).';
    end if;
    v_changes := jsonb_build_object('field', hr.jtext(p,'field'));
  end if;

  insert into hr.change_requests(employee_id, kind, changes, reason, requested_by, due_date)
  values (v_emp, v_kind, v_changes, v_reason, auth.uid(), hr.today() + 45)
  returning * into c;
  for u in select h.user_id from hr.users_with_perm('SS_APPROVE') h where h.user_id <> auth.uid() loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
      'Change request from ' || e.full_name_en, 'طلب تعديل بيانات من ' || coalesce(e.full_name_ar, e.full_name_en),
      e.employee_no, e.employee_no, '/requests?tab=changes', 'CHG:' || c.id);
  end loop;
  return hr.change_json(c);
end $$;

create or replace function public.hr_cancel_change(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c hr.change_requests;
begin
  perform hr.require_user();
  update hr.change_requests set status = 'CANCELLED' where id = p_id and status = 'PENDING' and requested_by = auth.uid() returning * into c;
  if c.id is null then raise exception 'NOT_FOUND: No waiting request of yours with this reference.'; end if;
  return hr.change_json(c);
end $$;

create or replace function public.hr_list_change_requests(p_status text default null, p_employee uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_all boolean := hr.has_perm('SS_APPROVE') or hr.has_perm('EMP_READ');
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.change_json(c) order by (c.status = 'PENDING') desc, c.due_date, c.requested_at desc)
    from hr.change_requests c
    where (v_all or c.employee_id = hr.my_employee_id())
      and (p_status is null or c.status = p_status)
      and (p_employee is null or c.employee_id = p_employee)), '[]'::jsonb);
end $$;

create or replace function public.hr_decide_change(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c hr.change_requests; e hr.employees; x jsonb; v_bank uuid; ch jsonb; u record;
begin
  perform hr.require_perm('SS_APPROVE');
  select * into c from hr.change_requests where id = p_id for update;
  if c.id is null then raise exception 'NOT_FOUND: Request not found.'; end if;
  if c.status <> 'PENDING' then raise exception 'NOT_PENDING: This request has already been decided.'; end if;
  if c.requested_by = auth.uid() or hr.is_me(c.employee_id) then
    raise exception 'SELF_APPROVAL: You cannot decide a request about yourself.' using errcode = '42501';
  end if;
  if not p_approve and nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  if p_approve and c.kind = 'CORRECTION' and nullif(btrim(coalesce(p_note,'')), '') is null then
    raise exception 'REQUIRED: Say what was corrected.';
  end if;
  select * into e from hr.employees where id = c.employee_id;
  ch := c.changes;
  if p_approve then
    if c.kind = 'PROFILE' then
      update hr.employees set
        preferred_name  = case when ch ? 'preferred_name'  then ch->'preferred_name'->>'new'  else preferred_name end,
        marital_status  = case when ch ? 'marital_status'  then ch->'marital_status'->>'new'  else marital_status end,
        personal_email  = case when ch ? 'personal_email'  then ch->'personal_email'->>'new'  else personal_email end,
        mobile          = case when ch ? 'mobile'          then ch->'mobile'->>'new'          else mobile end,
        alt_phone       = case when ch ? 'alt_phone'       then ch->'alt_phone'->>'new'       else alt_phone end,
        address_line    = case when ch ? 'address_line'    then ch->'address_line'->>'new'    else address_line end,
        city            = case when ch ? 'city'            then ch->'city'->>'new'            else city end,
        wilayat         = case when ch ? 'wilayat'         then ch->'wilayat'->>'new'         else wilayat end,
        governorate     = case when ch ? 'governorate'     then ch->'governorate'->>'new'     else governorate end,
        address_country = case when ch ? 'address_country' then ch->'address_country'->>'new' else address_country end
      where id = c.employee_id;
      perform hr.add_event(c.employee_id, 'PERSONAL_UPDATE', hr.today(),
                           jsonb_build_object('source', 'EMPLOYEE_REQUEST', 'request_id', c.id, 'fields', (select jsonb_agg(k) from jsonb_object_keys(ch) k)));
    elsif c.kind = 'EMERGENCY' then
      update hr.emergency_contacts set is_active = false where employee_id = c.employee_id and is_active;
      for x in select * from jsonb_array_elements(ch->'contacts') loop
        insert into hr.emergency_contacts(employee_id, name, relationship, phone, alt_phone, address, is_next_of_kin)
        values (c.employee_id, x->>'name', x->>'relationship', x->>'phone', nullif(x->>'alt_phone',''), nullif(x->>'address',''),
                coalesce((x->>'is_next_of_kin')::boolean, false));
      end loop;
    elsif c.kind = 'BANK' then
      if exists (select 1 from hr.employee_bank_accounts where employee_id = c.employee_id and status = 'PENDING') then
        raise exception 'PENDING_EXISTS: A bank change for this employee is already waiting for Finance.';
      end if;
      -- the employee is the requester; Finance (BANK_APPROVE) gives the final approval as for any bank change
      insert into hr.employee_bank_accounts(employee_id, bank_name, branch, account_name, account_number, iban, swift_code, effective_from, requested_by)
      values (c.employee_id, ch->>'bank_name', ch->>'branch', ch->>'account_name', ch->>'account_number', ch->>'iban', ch->>'swift_code',
              hr.today(), c.requested_by)
      returning id into v_bank;
      for u in select h.user_id from hr.users_with_perm('BANK_APPROVE') h where h.user_id <> auth.uid() and h.user_id <> c.requested_by loop
        perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
          'Bank account change awaiting approval — ' || e.full_name_en, 'تغيير الحساب البنكي بانتظار الاعتماد — ' || coalesce(e.full_name_ar, e.full_name_en),
          e.employee_no, e.employee_no, '/employees/' || c.employee_id || '?tab=bank', 'BANK:' || v_bank);
      end loop;
    end if;
  end if;
  update hr.change_requests set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(btrim(coalesce(p_note,'')), ''), result_ref = v_bank
   where id = c.id returning * into c;
  perform hr.notify(c.requested_by, 'INFO', 'NORMAL',
    case when p_approve then case when c.kind = 'BANK' then 'Your bank change was checked by HR and sent to Finance' else 'Your change request was approved' end
         else 'Your change request was rejected' end,
    case when p_approve then case when c.kind = 'BANK' then 'تمت مراجعة تغيير الحساب البنكي وأُحيل إلى المالية' else 'تم اعتماد طلب تعديل بياناتك' end
         else 'تم رفض طلب تعديل بياناتك' end,
    c.decision_note, c.decision_note, '/me?tab=requests', 'CHGD:' || c.id);
  return hr.change_json(c);
end $$;

-- ---------------------------------------------------------------------------
-- Letters
-- ---------------------------------------------------------------------------
create or replace function hr.letter_validate(p_type text, p_lang text, p_details jsonb)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if p_type not in ('SALARY_CERT','EXPERIENCE','NOC','EMPLOYMENT') then raise exception 'INVALID: Unknown letter type.'; end if;
  if p_lang not in ('EN','AR','BOTH') then raise exception 'INVALID: Language must be English, Arabic or both.'; end if;
  if p_type = 'NOC' then
    if nullif(btrim(coalesce(p_details->>'destination','')), '') is null and nullif(btrim(coalesce(p_details->>'activity','')), '') is null then
      raise exception 'REQUIRED: Say what the no-objection is for (travel destination or activity).';
    end if;
    if (p_details->>'from_date') is not null and (p_details->>'to_date') is not null
       and (p_details->>'to_date')::date < (p_details->>'from_date')::date then
      raise exception 'INVALID: The end date is before the start date.';
    end if;
  end if;
end $$;

create or replace function public.hr_request_letter(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_emp uuid := coalesce(hr.juuid(p,'employee_id'), hr.my_employee_id()); v_hr boolean := hr.has_perm('LETTER_PREPARE');
  v_type text := upper(coalesce(hr.jtext(p,'letter_type'), '')); v_lang text := upper(coalesce(hr.jtext(p,'language'), 'BOTH'));
  v_details jsonb := coalesce(p->'details', '{}'::jsonb); v_salary boolean; e hr.employees; l hr.letters; u record; v_prepare boolean;
begin
  perform hr.require_user();
  if v_emp is null then raise exception 'NOT_LINKED: Your login is not linked to an employee record. Ask HR to link it.'; end if;
  if not hr.is_me(v_emp) and not v_hr then raise exception 'NOT_ALLOWED: You can only request letters for yourself.' using errcode = '42501'; end if;
  select * into e from hr.employees where id = v_emp;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  perform hr.letter_validate(v_type, v_lang, v_details);
  if v_type = 'EXPERIENCE' and e.status not in ('NOTICE','SEPARATED') and not v_hr then
    raise exception 'NOT_ALLOWED: An experience letter is issued when you leave. Ask for an employment letter instead.';
  end if;
  if exists (select 1 from hr.letters where employee_id = v_emp and letter_type = v_type and status in ('REQUESTED','PREPARED')) then
    raise exception 'PENDING_EXISTS: A letter of this type is already being prepared.';
  end if;
  v_salary := v_type = 'SALARY_CERT' or (v_type = 'EMPLOYMENT' and hr.jbool(p,'include_salary'));
  -- HR starting a letter for someone else may prepare it in the same step; approval is still by another person
  v_prepare := v_hr and not hr.is_me(v_emp) and hr.jbool(p,'prepare');
  insert into hr.letters(employee_id, letter_type, language, addressee, purpose, details, include_salary, requested_by,
                         status, prepared_by, prepared_at)
  values (v_emp, v_type, v_lang, hr.jtext(p,'addressee'), hr.jtext(p,'purpose'), v_details, v_salary, auth.uid(),
          case when v_prepare then 'PREPARED' else 'REQUESTED' end, case when v_prepare then auth.uid() end, case when v_prepare then now() end)
  returning * into l;
  for u in select h.user_id from hr.users_with_perm(case when v_prepare then 'LETTER_APPROVE' else 'LETTER_PREPARE' end) h
           where h.user_id <> auth.uid() and h.user_id is distinct from hr.employee_user(v_emp) loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
      case when v_prepare then 'Letter waiting for approval — ' else 'Letter requested — ' end || e.full_name_en,
      case when v_prepare then 'خطاب بانتظار الاعتماد — ' else 'طلب خطاب — ' end || coalesce(e.full_name_ar, e.full_name_en),
      e.employee_no, e.employee_no, '/requests?tab=letters', 'LTR:' || l.id || ':' || l.status);
  end loop;
  return hr.letter_json(l);
end $$;

create or replace function public.hr_prepare_letter(p_id uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l hr.letters; e hr.employees; v_lang text; v_details jsonb; u record;
begin
  perform hr.require_perm('LETTER_PREPARE');
  select * into l from hr.letters where id = p_id for update;
  if l.id is null then raise exception 'NOT_FOUND: Letter not found.'; end if;
  if l.status <> 'REQUESTED' then raise exception 'NOT_PENDING: This letter is not waiting to be prepared.'; end if;
  if hr.is_me(l.employee_id) then raise exception 'SELF_APPROVAL: You cannot prepare your own letter.' using errcode = '42501'; end if;
  v_lang := upper(coalesce(hr.jtext(p,'language'), l.language));
  v_details := coalesce(p->'details', l.details);
  perform hr.letter_validate(l.letter_type, v_lang, v_details);
  update hr.letters set language = v_lang, addressee = coalesce(hr.jtext(p,'addressee'), addressee), purpose = coalesce(hr.jtext(p,'purpose'), purpose),
         details = v_details,
         include_salary = case when letter_type = 'SALARY_CERT' then true when letter_type = 'EMPLOYMENT' and p ? 'include_salary' then hr.jbool(p,'include_salary') else include_salary end,
         status = 'PREPARED', prepared_by = auth.uid(), prepared_at = now()
   where id = p_id returning * into l;
  select * into e from hr.employees where id = l.employee_id;
  for u in select h.user_id from hr.users_with_perm('LETTER_APPROVE') h where h.user_id <> auth.uid() and h.user_id is distinct from hr.employee_user(l.employee_id) loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL', 'Letter waiting for approval — ' || e.full_name_en,
      'خطاب بانتظار الاعتماد — ' || coalesce(e.full_name_ar, e.full_name_en), e.employee_no, e.employee_no, '/requests?tab=letters', 'LTR:' || l.id || ':PREPARED');
  end loop;
  return hr.letter_json(l);
end $$;

create or replace function public.hr_decide_letter(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l hr.letters; e hr.employees; v_today date := hr.today();
begin
  perform hr.require_user();
  select * into l from hr.letters where id = p_id for update;
  if l.id is null then raise exception 'NOT_FOUND: Letter not found.'; end if;
  if p_approve then
    perform hr.require_perm('LETTER_APPROVE');
    if l.status <> 'PREPARED' then raise exception 'NOT_PENDING: Only a prepared letter can be approved.'; end if;
    if l.prepared_by = auth.uid() then raise exception 'SELF_APPROVAL: The person who prepared a letter cannot approve it.' using errcode = '42501'; end if;
    if hr.is_me(l.employee_id) then raise exception 'SELF_APPROVAL: You cannot approve your own letter.' using errcode = '42501'; end if;
    if l.include_salary and not hr.has_perm('EMP_SALARY_READ') then
      raise exception 'NOT_ALLOWED: Only someone who may see salaries can approve a letter that states the salary.' using errcode = '42501';
    end if;
    select * into e from hr.employees where id = l.employee_id;
    if l.include_salary and hr.comp_on(l.employee_id, v_today) is null then
      raise exception 'NO_SALARY: This employee has no approved salary structure to state.';
    end if;
    update hr.letters set status = 'ISSUED', approved_by = auth.uid(), approved_at = now(), decision_note = nullif(btrim(coalesce(p_note,'')), ''),
           issue_date = v_today, ref_no = hr.next_letter_ref(e.entity_id, v_today), verify_code = hr.new_verify_code(),
           snapshot = hr.letter_snapshot(l.employee_id, l.include_salary, v_today)
     where id = p_id returning * into l;
    perform hr.notify(hr.employee_user(l.employee_id), 'INFO', 'NORMAL', 'Your letter is ready: ' || l.ref_no, 'خطابك جاهز: ' || l.ref_no,
      null, null, '/letters/' || l.id, 'LTRI:' || l.id);
  else
    if not (hr.has_perm('LETTER_PREPARE') or hr.has_perm('LETTER_APPROVE')) then
      raise exception 'NOT_ALLOWED: You cannot reject letters.' using errcode = '42501';
    end if;
    if l.status not in ('REQUESTED','PREPARED') then raise exception 'NOT_PENDING: This letter has already been decided.'; end if;
    if hr.is_me(l.employee_id) then raise exception 'SELF_APPROVAL: You cannot decide your own letter.' using errcode = '42501'; end if;
    if nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
    update hr.letters set status = 'REJECTED', decision_note = btrim(p_note), approved_by = case when prepared_by = auth.uid() then null else auth.uid() end,
           approved_at = now()
     where id = p_id returning * into l;
    perform hr.notify(l.requested_by, 'INFO', 'NORMAL', 'Your letter request was rejected', 'تم رفض طلب الخطاب', l.decision_note, l.decision_note,
      '/me?tab=letters', 'LTRR:' || l.id);
  end if;
  return hr.letter_json(l);
end $$;

create or replace function public.hr_cancel_letter(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l hr.letters;
begin
  perform hr.require_user();
  update hr.letters set status = 'CANCELLED'
   where id = p_id and status in ('REQUESTED','PREPARED') and (requested_by = auth.uid() or hr.has_perm('LETTER_PREPARE'))
  returning * into l;
  if l.id is null then raise exception 'NOT_FOUND: No letter in progress with this reference that you can cancel.'; end if;
  return hr.letter_json(l);
end $$;

create or replace function public.hr_revoke_letter(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l hr.letters;
begin
  perform hr.require_perm('LETTER_APPROVE');
  if nullif(btrim(coalesce(p_reason,'')), '') is null then raise exception 'REQUIRED: Give a reason for withdrawing the letter.'; end if;
  update hr.letters set revoked_at = now(), revoked_by = auth.uid(), revoke_reason = btrim(p_reason)
   where id = p_id and status = 'ISSUED' and revoked_at is null returning * into l;
  if l.id is null then raise exception 'NOT_FOUND: No issued letter with this reference.'; end if;
  return hr.letter_json(l);
end $$;

create or replace function public.hr_list_letters(p_status text default null, p_employee uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_all boolean := hr.has_perm('LETTER_PREPARE') or hr.has_perm('LETTER_APPROVE') or hr.has_perm('EMP_READ');
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(hr.letter_json(l) - 'snapshot' order by (l.status in ('REQUESTED','PREPARED')) desc, l.requested_at desc)
    from hr.letters l
    where (v_all or l.employee_id = hr.my_employee_id())
      and (p_status is null or l.status = p_status)
      and (p_employee is null or l.employee_id = p_employee)), '[]'::jsonb);
end $$;

create or replace function public.hr_get_letter(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare l hr.letters;
begin
  perform hr.require_user();
  select * into l from hr.letters where id = p_id;
  if l.id is null then raise exception 'NOT_FOUND: Letter not found.'; end if;
  if not (hr.is_me(l.employee_id) or hr.has_perm('LETTER_PREPARE') or hr.has_perm('LETTER_APPROVE') or hr.has_perm('EMP_READ')) then
    raise exception 'NOT_ALLOWED: You cannot see this letter.' using errcode = '42501';
  end if;
  return hr.letter_json(l) || jsonb_build_object('settings', (select value from hr.settings where key = 'letters'),
    'preview', case when l.status <> 'ISSUED' then hr.letter_snapshot(l.employee_id, l.include_salary and hr.has_perm('EMP_SALARY_READ'), hr.today()) end);
end $$;

-- Anyone (no login) holding a letter can check it with the reference and the verification code printed on it.
create or replace function public.hr_verify_letter(p_ref text, p_code text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare l hr.letters;
begin
  if p_ref is null or p_code is null or length(p_code) <> 12 then return jsonb_build_object('valid', false); end if;
  select * into l from hr.letters where ref_no = upper(btrim(p_ref)) and verify_code = upper(btrim(p_code)) and status = 'ISSUED';
  if l.id is null then return jsonb_build_object('valid', false); end if;
  return jsonb_build_object('valid', l.revoked_at is null, 'revoked', l.revoked_at is not null, 'ref_no', l.ref_no, 'letter_type', l.letter_type,
    'issue_date', l.issue_date, 'full_name_en', l.snapshot->>'full_name_en', 'full_name_ar', l.snapshot->>'full_name_ar',
    'entity_en', l.snapshot->>'entity_en', 'entity_ar', l.snapshot->>'entity_ar');
end $$;

create or replace function public.hr_letter_settings()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return (select value from hr.settings where key = 'letters');
end $$;

create or replace function public.hr_save_letter_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb := '{}'::jsonb; k text;
begin
  perform hr.require_perm('LETTER_APPROVE');
  foreach k in array array['signatory_en','signatory_ar','signatory_name_en','signatory_name_ar','footer_en','footer_ar','verify_base_url'] loop
    v := v || jsonb_build_object(k, coalesce(left(btrim(coalesce(p->>k, '')), 300), ''));
  end loop;
  if (v->>'verify_base_url') <> '' and (v->>'verify_base_url') !~ '^https?://' then
    raise exception 'INVALID: The verification address must start with https://';
  end if;
  insert into hr.settings(key, value, updated_by) values ('letters', v, auth.uid())
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  return v;
end $$;

-- ---------------------------------------------------------------------------
-- Employee portal ("My HR")
-- ---------------------------------------------------------------------------
create or replace function public.hr_my_portal()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := hr.my_employee_id(); e hr.employees; a hr.employee_assignments; v_today date := hr.today();
begin
  perform hr.require_user();
  if v_me is null then return jsonb_build_object('linked', false); end if;
  select * into e from hr.employees where id = v_me;
  a := hr.current_assignment(v_me);
  return jsonb_build_object('linked', true,
    'employee', hr.emp_brief(v_me) || jsonb_build_object(
      'preferred_name', e.preferred_name, 'marital_status', e.marital_status, 'personal_email', e.personal_email, 'work_email', e.work_email,
      'mobile', e.mobile, 'alt_phone', e.alt_phone, 'address_line', e.address_line, 'city', e.city, 'wilayat', e.wilayat,
      'governorate', e.governorate, 'address_country', e.address_country, 'date_of_birth', e.date_of_birth, 'gender', e.gender,
      'nationality', e.nationality, 'civil_number', e.civil_number, 'join_date', e.join_date, 'status', e.status,
      'probation_end_date', e.probation_end_date, 'last_working_date', e.last_working_date,
      'job_en', (select name_en from hr.job_titles where id = a.job_title_id), 'job_ar', (select name_ar from hr.job_titles where id = a.job_title_id),
      'manager_en', (select full_name_en from hr.employees where id = a.manager_id), 'manager_ar', (select full_name_ar from hr.employees where id = a.manager_id)),
    'emergency_contacts', coalesce((select jsonb_agg(jsonb_build_object('name', x.name, 'relationship', x.relationship, 'phone', x.phone,
                            'alt_phone', x.alt_phone, 'address', x.address, 'is_next_of_kin', x.is_next_of_kin) order by x.created_at)
                          from hr.emergency_contacts x where x.employee_id = v_me and x.is_active), '[]'::jsonb),
    'bank', (select jsonb_build_object('bank_name', b.bank_name, 'account', hr.mask_tail(coalesce(b.iban, b.account_number)))
             from hr.employee_bank_accounts b where b.employee_id = v_me and b.status = 'APPROVED' limit 1),
    'bank_pending', exists (select 1 from hr.employee_bank_accounts b where b.employee_id = v_me and b.status = 'PENDING'),
    'annual', hr.leave_balance(v_me, 'ANNUAL', v_today),
    'sick', hr.leave_balance(v_me, 'SICK', v_today),
    'leave_pending', (select count(*) from hr.leave_requests r where r.employee_id = v_me and r.status like 'PENDING%'),
    'next_leave', (select jsonb_build_object('name_en', t.name_en, 'name_ar', t.name_ar, 'start_date', r.start_date, 'end_date', r.end_date, 'status', r.status)
                   from hr.leave_requests r join hr.leave_types t on t.code = r.leave_type
                   where r.employee_id = v_me and r.status in ('APPROVED','PENDING_MANAGER','PENDING_HR') and r.end_date >= v_today
                   order by r.start_date limit 1),
    'last_payslip', (select jsonb_build_object('id', s.id, 'month', to_char(r.period_start,'YYYY-MM'), 'net', s.net)
                     from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
                     where s.employee_id = v_me and r.status in ('APPROVED','PAID') order by r.period_start desc limit 1),
    'expiring', coalesce((select jsonb_agg(jsonb_build_object('name_en', x.name_en, 'name_ar', x.name_ar, 'expiry_date', x.expiry_date,
                    'days_left', x.days_left, 'bucket', x.bucket) order by x.expiry_date)
                  from hr.expiry_items(v_today) x where x.employee_id = v_me and x.days_left <= 90 and not x.is_sensitive), '[]'::jsonb),
    'changes', coalesce((select jsonb_agg(hr.change_json(c) order by c.requested_at desc) from hr.change_requests c where c.employee_id = v_me), '[]'::jsonb),
    'letters', coalesce((select jsonb_agg(hr.letter_json(l) - 'snapshot' order by l.requested_at desc) from hr.letters l where l.employee_id = v_me), '[]'::jsonb),
    'profile_fields', to_jsonb(hr.ss_profile_fields()));
end $$;

-- PDPL: a copy of everything the system holds about the signed-in employee.
create or replace function public.hr_my_data_export()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_me uuid := hr.my_employee_id();
begin
  perform hr.require_user();
  if v_me is null then raise exception 'NOT_LINKED: Your login is not linked to an employee record.'; end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail)
  values (auth.uid(), v_me, 'DATA_EXPORT', 'Employee downloaded a copy of their personal data');
  return jsonb_build_object(
    'generated_at', now(), 'notice', 'Copy of personal data held by the HR system (Oman Personal Data Protection Law).',
    'employee', (select to_jsonb(e) - 'created_by' from hr.employees e where e.id = v_me),
    'assignments', coalesce((select jsonb_agg(to_jsonb(a) - 'created_by' order by a.effective_from) from hr.employee_assignments a where a.employee_id = v_me), '[]'::jsonb),
    'contracts', coalesce((select jsonb_agg(to_jsonb(c) order by c.start_date) from hr.employee_contracts c where c.employee_id = v_me), '[]'::jsonb),
    'emergency_contacts', coalesce((select jsonb_agg(to_jsonb(x)) from hr.emergency_contacts x where x.employee_id = v_me and x.is_active), '[]'::jsonb),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('type', d.doc_type, 'number', d.doc_number, 'issue_date', d.issue_date,
                    'expiry_date', d.expiry_date, 'status', d.status) order by d.created_at) from hr.employee_documents d where d.employee_id = v_me), '[]'::jsonb),
    'bank_accounts', coalesce((select jsonb_agg(jsonb_build_object('bank_name', b.bank_name, 'account_number', b.account_number, 'iban', b.iban,
                    'effective_from', b.effective_from, 'status', b.status) order by b.requested_at) from hr.employee_bank_accounts b where b.employee_id = v_me), '[]'::jsonb),
    'salary', coalesce((select jsonb_agg(jsonb_build_object('effective_from', r.effective_from, 'status', r.status,
                    'lines', (select jsonb_agg(jsonb_build_object('component', l.component_code, 'amount', l.amount)) from hr.compensation_lines l where l.revision_id = r.id))
                    order by r.effective_from) from hr.compensation_revisions r where r.employee_id = v_me and r.status in ('APPROVED','SUPERSEDED')), '[]'::jsonb),
    'leave_requests', coalesce((select jsonb_agg(jsonb_build_object('type', r.leave_type, 'start_date', r.start_date, 'end_date', r.end_date,
                    'days', r.days, 'status', r.status) order by r.start_date) from hr.leave_requests r where r.employee_id = v_me), '[]'::jsonb),
    'payslips', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(r.period_start,'YYYY-MM'), 'earnings', s.total_earnings,
                    'deductions', s.total_deductions, 'net', s.net) order by r.period_start) from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
                    where s.employee_id = v_me and r.status in ('APPROVED','PAID')), '[]'::jsonb),
    'change_requests', coalesce((select jsonb_agg(jsonb_build_object('kind', c.kind, 'status', c.status, 'requested_at', c.requested_at,
                    'decided_at', c.decided_at)) from hr.change_requests c where c.employee_id = v_me), '[]'::jsonb),
    'letters', coalesce((select jsonb_agg(jsonb_build_object('type', l.letter_type, 'status', l.status, 'ref_no', l.ref_no, 'issue_date', l.issue_date))
                    from hr.letters l where l.employee_id = v_me), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- Line manager: my team today
-- ---------------------------------------------------------------------------
create or replace function public.hr_my_team()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := hr.my_employee_id(); v_today date := hr.today();
begin
  perform hr.require_user();
  if v_me is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(row order by (row->>'direct')::boolean desc, row->>'full_name_en') from (
    select hr.emp_brief(t.employee_id) || jsonb_build_object(
      'direct', a.manager_id = v_me, 'status', e.status, 'mobile', e.mobile, 'work_email', e.work_email,
      'job_en', j.name_en, 'job_ar', j.name_ar, 'probation_end_date', e.probation_end_date,
      'today', (select jsonb_build_object('status', d.status, 'late_minutes', d.late_minutes, 'first_in', d.first_in)
                from hr.attendance_days d where d.employee_id = t.employee_id and d.work_date = v_today),
      'on_leave', (select jsonb_build_object('name_en', lt.name_en, 'name_ar', lt.name_ar, 'end_date', r.end_date)
                   from hr.leave_requests r join hr.leave_types lt on lt.code = r.leave_type
                   where r.employee_id = t.employee_id and r.status = 'APPROVED' and v_today between r.start_date and r.end_date limit 1),
      'pending', (select count(*) from hr.leave_requests r where r.employee_id = t.employee_id and r.status = 'PENDING_MANAGER')
               + (select count(*) from hr.overtime_requests o where o.employee_id = t.employee_id and o.status = 'PENDING_MANAGER')
               + (select count(*) from hr.attendance_corrections c where c.employee_id = t.employee_id and c.status = 'PENDING_MANAGER'),
      'expiring', (select count(*) from hr.expiry_items(v_today) x where x.employee_id = t.employee_id and x.days_left <= 30 and not x.is_sensitive)) as row
    from hr.team_of(v_me) t
    join hr.employees e on e.id = t.employee_id
    left join hr.employee_assignments a on a.id = (hr.current_assignment(t.employee_id)).id
    left join hr.job_titles j on j.id = a.job_title_id
    where e.status <> 'SEPARATED') s), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- E-mail (Microsoft 365)
-- ---------------------------------------------------------------------------
create or replace function public.hr_email_settings()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('EMAIL_ADMIN');
  return jsonb_build_object('settings', (select value from hr.settings where key = 'email'),
    'queue', (select jsonb_build_object('queued', count(*) filter (where status in ('QUEUED','SENDING')), 'sent', count(*) filter (where status = 'SENT'),
                'failed', count(*) filter (where status = 'FAILED')) from hr.email_outbox),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'to_email', o.to_email, 'subject', o.subject, 'status', o.status,
                 'attempts', o.attempts, 'last_error', o.last_error, 'created_at', o.created_at, 'sent_at', o.sent_at) order by o.created_at desc)
                 from (select * from hr.email_outbox order by created_at desc limit 20) o), '[]'::jsonb));
end $$;

create or replace function public.hr_save_email_settings(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb; v_url text := rtrim(coalesce(btrim(p->>'app_url'), ''), '/');
begin
  perform hr.require_perm('EMAIL_ADMIN');
  if v_url <> '' and v_url !~ '^https?://' then raise exception 'INVALID: The application address must start with https://'; end if;
  v := jsonb_build_object('enabled', hr.jbool(p,'enabled'), 'app_url', v_url,
                          'sender_name', coalesce(left(hr.jtext(p,'sender_name'), 80), 'AACT HR'));
  insert into hr.settings(key, value, updated_by) values ('email', v, auth.uid())
  on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  return public.hr_email_settings();
end $$;

-- Queue a test message to the signed-in administrator (even while sending is switched off).
create or replace function public.hr_email_test()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare up hr.user_profiles;
begin
  perform hr.require_perm('EMAIL_ADMIN');
  select * into up from hr.user_profiles where user_id = auth.uid();
  if up.email is null then raise exception 'REQUIRED: Your login has no e-mail address.'; end if;
  insert into hr.email_outbox(user_id, to_email, subject, body_text)
  values (up.user_id, up.email, 'AACT HRMS test e-mail', 'This is a test message from AACT HRMS. If you can read it, Microsoft 365 sending works.');
  return public.hr_email_settings();
end $$;

create or replace function public.hr_my_email_pref()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return (select jsonb_build_object('email_opt_in', up.email_opt_in, 'email', up.email,
                 'sending_enabled', coalesce(((select value from hr.settings where key = 'email')->>'enabled')::boolean, false))
          from hr.user_profiles up where up.user_id = auth.uid());
end $$;

create or replace function public.hr_set_my_email_pref(p_on boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  perform hr.require_user();
  update hr.user_profiles set email_opt_in = coalesce(p_on, true) where user_id = auth.uid();
  return public.hr_my_email_pref();
end $$;

-- Used only by the send-mail edge function with the service-role key (not by signed-in users).
create or replace function public.mail_claim_batch(p_limit int default 20)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  with c as (
    select o.id from hr.email_outbox o
    where o.status = 'QUEUED'
       or (o.status = 'SENDING' and o.claimed_at < now() - interval '15 minutes')
       or (o.status = 'FAILED' and o.attempts < 5 and o.created_at > now() - interval '1 day' and o.claimed_at < now() - interval '10 minutes')
    order by o.created_at limit greatest(1, least(coalesce(p_limit, 20), 100))
    for update skip locked)
  , u as (
    update hr.email_outbox o set status = 'SENDING', claimed_at = now(), attempts = o.attempts + 1
    from c where o.id = c.id
    returning o.id, o.to_email, o.subject, o.body_text)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'to', u.to_email, 'subject', u.subject, 'body', u.body_text)), '[]'::jsonb) into v
  from u;
  return v;
end $$;

create or replace function public.mail_mark(p_id uuid, p_ok boolean, p_error text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update hr.email_outbox set status = case when p_ok then 'SENT' else 'FAILED' end, sent_at = case when p_ok then now() end,
         last_error = case when p_ok then null else left(p_error, 500) end
   where id = p_id and status = 'SENDING';
end $$;

revoke all on function public.mail_claim_batch(int) from public, anon, authenticated;
revoke all on function public.mail_mark(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.mail_claim_batch(int) to service_role;
grant execute on function public.mail_mark(uuid, boolean, text) to service_role;

-- ---------------------------------------------------------------------------
-- Tasks and dashboard: add change requests and letters
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
                       where (j->>'can_prepare')::boolean or (j->>'can_approve')::boolean), '[]'::jsonb) else '[]'::jsonb end)
  into v_res;
  return v_res || jsonb_build_object('count',
    jsonb_array_length(v_res->'leave') + jsonb_array_length(v_res->'corrections') + jsonb_array_length(v_res->'overtime')
    + jsonb_array_length(v_res->'adjustments') + jsonb_array_length(v_res->'rules') + jsonb_array_length(v_res->'pay_rules')
    + jsonb_array_length(v_res->'payroll') + jsonb_array_length(v_res->'loans') + jsonb_array_length(v_res->'pay_adjustments')
    + jsonb_array_length(v_res->'settlements') + jsonb_array_length(v_res->'changes') + jsonb_array_length(v_res->'letters'));
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
  v_tasks := public.hr_list_my_tasks();
  return v_res || jsonb_build_object('tasks', jsonb_build_object(
    'leave', jsonb_array_length(v_tasks->'leave'), 'corrections', jsonb_array_length(v_tasks->'corrections'),
    'overtime', jsonb_array_length(v_tasks->'overtime'), 'adjustments', jsonb_array_length(v_tasks->'adjustments'),
    'rules', jsonb_array_length(v_tasks->'rules') + jsonb_array_length(v_tasks->'pay_rules'),
    'payroll', jsonb_array_length(v_tasks->'payroll'), 'loans', jsonb_array_length(v_tasks->'loans'),
    'pay_adjustments', jsonb_array_length(v_tasks->'pay_adjustments'), 'settlements', jsonb_array_length(v_tasks->'settlements'),
    'changes', jsonb_array_length(v_tasks->'changes'), 'letters', jsonb_array_length(v_tasks->'letters'),
    'count', (v_tasks->>'count')::int));
end $$;

select hr.attach_audit();
select hr.secure_api();
