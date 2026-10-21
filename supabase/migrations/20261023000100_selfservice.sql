-- AACT HRMS — 030 Phase 4: self-service & letters — tables, permissions, helpers, e-mail outbox.
-- Idempotent; no destructive statements.

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
insert into hr.permissions(code, module, description) values
  ('SS_APPROVE',     'Self-service', 'Approve or reject changes employees request to their own details'),
  ('LETTER_PREPARE', 'Letters',      'Prepare salary certificates, experience letters, NOCs and employment letters'),
  ('LETTER_APPROVE', 'Letters',      'Approve and issue letters prepared by someone else'),
  ('EMAIL_ADMIN',    'Administration','Configure e-mail notifications (Microsoft 365)')
on conflict (code) do nothing;

insert into hr.role_permissions(role_code, perm_code)
select 'SUPER_ADMIN', code from hr.permissions
on conflict do nothing;

insert into hr.role_permissions(role_code, perm_code)
select r, p from (values
  ('HR_MANAGER','SS_APPROVE'),('HR_MANAGER','LETTER_PREPARE'),('HR_MANAGER','LETTER_APPROVE'),
  ('HR_OFFICER','SS_APPROVE'),('HR_OFFICER','LETTER_PREPARE')
) v(r, p)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Settings: letters and e-mail
-- ---------------------------------------------------------------------------
insert into hr.settings(key, value) values
  ('letters', '{"signatory_en":"HR Manager","signatory_ar":"مدير الموارد البشرية","signatory_name_en":"","signatory_name_ar":"","footer_en":"","footer_ar":"","verify_base_url":""}'::jsonb),
  ('email', '{"enabled":false,"app_url":"","sender_name":"AACT HR"}'::jsonb)
on conflict (key) do nothing;

alter table hr.user_profiles add column if not exists email_opt_in boolean not null default true;

-- ---------------------------------------------------------------------------
-- Change requests: employees ask HR to change their own details (PDPL right to correction)
-- ---------------------------------------------------------------------------
create table if not exists hr.change_requests (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references hr.employees(id),
  kind          text not null check (kind in ('PROFILE','EMERGENCY','BANK','CORRECTION')),
  changes       jsonb not null default '{}'::jsonb,   -- PROFILE: {field:{old,new}}; EMERGENCY: {contacts:[…]}; BANK: {bank fields}; CORRECTION: {}
  reason        text,
  status        text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','CANCELLED')),
  requested_by  uuid not null,
  requested_at  timestamptz not null default now(),
  due_date      date not null,                       -- PDPL: answer within 45 days
  decided_by    uuid,
  decided_at    timestamptz,
  decision_note text,
  result_ref    uuid,                                -- e.g. the bank account row created on approval
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (decided_by is null or decided_by <> requested_by)
);
create index if not exists change_requests_emp on hr.change_requests(employee_id, requested_at desc);
create index if not exists change_requests_status on hr.change_requests(status, due_date);
create unique index if not exists change_requests_one_pending on hr.change_requests(employee_id, kind) where status = 'PENDING' and kind <> 'CORRECTION';
alter table hr.change_requests enable row level security;

-- ---------------------------------------------------------------------------
-- Letters: requested by the employee (or started by HR) → prepared → approved & issued
-- ---------------------------------------------------------------------------
create table if not exists hr.letter_counters (
  entity_id uuid not null references hr.legal_entities(id),
  year      int not null,
  last_no   int not null default 0,
  primary key (entity_id, year)
);
alter table hr.letter_counters enable row level security;

create table if not exists hr.letters (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references hr.employees(id),
  letter_type    text not null check (letter_type in ('SALARY_CERT','EXPERIENCE','NOC','EMPLOYMENT')),
  language       text not null default 'BOTH' check (language in ('EN','AR','BOTH')),
  addressee      text,
  purpose        text,
  details        jsonb not null default '{}'::jsonb,  -- NOC: {destination, from_date, to_date}; free extras
  include_salary boolean not null default false,
  status         text not null default 'REQUESTED' check (status in ('REQUESTED','PREPARED','ISSUED','REJECTED','CANCELLED')),
  requested_by   uuid not null,
  requested_at   timestamptz not null default now(),
  prepared_by    uuid,
  prepared_at    timestamptz,
  approved_by    uuid,
  approved_at    timestamptz,
  decision_note  text,
  ref_no         text unique,
  verify_code    text,
  issue_date     date,
  snapshot       jsonb,                               -- employee, job and (if included) salary as at issue
  revoked_at     timestamptz,
  revoked_by     uuid,
  revoke_reason  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (approved_by is null or approved_by <> prepared_by),
  check (status <> 'ISSUED' or (ref_no is not null and verify_code is not null and snapshot is not null))
);
create index if not exists letters_emp on hr.letters(employee_id, requested_at desc);
create index if not exists letters_status on hr.letters(status);
alter table hr.letters enable row level security;

-- ---------------------------------------------------------------------------
-- E-mail outbox (Microsoft 365 via Graph, sent by the send-mail edge function)
-- ---------------------------------------------------------------------------
create table if not exists hr.email_outbox (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references hr.user_profiles(user_id),
  to_email        text not null,
  subject         text not null,
  body_text       text not null,
  notification_id uuid,
  status          text not null default 'QUEUED' check (status in ('QUEUED','SENDING','SENT','FAILED')),
  attempts        int not null default 0,
  last_error      text,
  claimed_at      timestamptz,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz
);
create index if not exists email_outbox_queue on hr.email_outbox(status, created_at);
alter table hr.email_outbox enable row level security;

-- Audit everything except logs, attendance days (recomputed) and the e-mail queue.
create or replace function hr.attach_audit()
returns void language plpgsql set search_path = '' as $$
declare r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'hr' and c.relkind = 'r'
      and c.relname not in ('audit_log','access_log','notifications','attendance_days','email_outbox','letter_counters')
  loop
    if not exists (select 1 from pg_trigger t join pg_class c2 on c2.oid = t.tgrelid
                   join pg_namespace n2 on n2.oid = c2.relnamespace
                   where n2.nspname = 'hr' and c2.relname = r.relname and t.tgname = 'zz_audit') then
      execute format('create trigger zz_audit after insert or update or delete on hr.%I
                      for each row execute function hr.audit_trigger()', r.relname);
    end if;
    if exists (select 1 from information_schema.columns
               where table_schema = 'hr' and table_name = r.relname and column_name = 'updated_at')
       and not exists (select 1 from pg_trigger t join pg_class c2 on c2.oid = t.tgrelid
                       join pg_namespace n2 on n2.oid = c2.relnamespace
                       where n2.nspname = 'hr' and c2.relname = r.relname and t.tgname = 'aa_touch') then
      execute format('create trigger aa_touch before update on hr.%I
                      for each row execute function hr.touch_updated_at()', r.relname);
    end if;
  end loop;
end $$;

-- Queue an e-mail for each new notification when e-mail is switched on and the user has not opted out.
create or replace function hr.queue_notification_email()
returns trigger language plpgsql security definer set search_path = '' as $$
declare s jsonb; up hr.user_profiles; v_url text; v_subject text; v_body text;
begin
  select value into s from hr.settings where key = 'email';
  if s is null or coalesce((s->>'enabled')::boolean, false) is false then return new; end if;
  select * into up from hr.user_profiles where user_id = new.user_id;
  if up.user_id is null or not up.is_active or not up.email_opt_in or up.email is null then return new; end if;
  v_url := nullif(rtrim(coalesce(s->>'app_url', ''), '/'), '');
  if up.language = 'ar' then
    v_subject := new.title_ar;
    v_body := new.title_ar || coalesce(E'\n\n' || new.body_ar, '');
  else
    v_subject := new.title_en;
    v_body := new.title_en || coalesce(E'\n\n' || new.body_en, '');
  end if;
  if v_url is not null and new.link is not null then v_body := v_body || E'\n\n' || v_url || new.link; end if;
  v_body := v_body || E'\n\n— ' || coalesce(nullif(s->>'sender_name', ''), 'AACT HR')
            || case when up.language = 'ar' then E'\nيمكنك إيقاف هذه الرسائل من الإعدادات.' else E'\nYou can turn these e-mails off in Settings.' end;
  insert into hr.email_outbox(user_id, to_email, subject, body_text, notification_id)
  values (up.user_id, up.email, left(v_subject, 250), v_body, new.id);
  return new;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'hr' and c.relname = 'notifications' and t.tgname = 'zz_email') then
    create trigger zz_email after insert on hr.notifications for each row execute function hr.queue_notification_email();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Fields an employee may ask to change about themselves (anything else goes through a CORRECTION request).
create or replace function hr.ss_profile_fields()
returns text[] language sql immutable set search_path = '' as $$
  select array['preferred_name','marital_status','personal_email','mobile','alt_phone','address_line','city','wilayat','governorate','address_country']
$$;

create or replace function hr.change_json(c hr.change_requests)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(c.employee_id) || jsonb_build_object(
    'id', c.id, 'kind', c.kind,
    -- bank details are only shown to people who may see bank data, or the employee
    'changes', case when c.kind = 'BANK' and not (hr.has_perm('EMP_BANK_READ') or hr.is_me(c.employee_id))
                    then jsonb_build_object('bank_name', c.changes->>'bank_name', 'account_number', hr.mask_tail(c.changes->>'account_number'))
                    else c.changes end,
    'reason', c.reason, 'status', c.status, 'requested_by', c.requested_by, 'requested_by_name', hr.user_label(c.requested_by),
    'requested_at', c.requested_at, 'due_date', c.due_date,
    'overdue', c.status = 'PENDING' and c.due_date < hr.today(),
    'decided_by_name', hr.user_label(c.decided_by), 'decided_at', c.decided_at, 'decision_note', c.decision_note,
    'can_decide', c.status = 'PENDING' and hr.has_perm('SS_APPROVE') and auth.uid() <> c.requested_by and not hr.is_me(c.employee_id),
    'can_cancel', c.status = 'PENDING' and auth.uid() = c.requested_by)
$$;

-- Snapshot of what a letter states, taken at issue so the letter never changes afterwards.
create or replace function hr.letter_snapshot(p_employee uuid, p_salary boolean, p_on date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare e hr.employees; a hr.employee_assignments; d hr.departments; j hr.job_titles; le hr.legal_entities; c hr.countries; comp jsonb;
begin
  select * into e from hr.employees where id = p_employee;
  a := hr.current_assignment(p_employee, least(p_on, coalesce(e.separation_date, p_on)));
  if a.id is null then
    select * into a from hr.employee_assignments where employee_id = p_employee order by effective_from desc limit 1;
  end if;
  select * into d from hr.departments where id = a.department_id;
  select * into j from hr.job_titles where id = a.job_title_id;
  select * into le from hr.legal_entities where id = e.entity_id;
  select * into c from hr.countries where code = e.nationality;
  if p_salary then comp := hr.comp_on(p_employee, p_on); end if;
  return jsonb_build_object(
    'employee_no', e.employee_no, 'full_name_en', e.full_name_en, 'full_name_ar', coalesce(e.full_name_ar, e.full_name_en),
    'gender', e.gender, 'nationality_en', c.nationality_en, 'nationality_ar', c.nationality_ar, 'is_omani', e.nationality = 'OM',
    'civil_number', e.civil_number, 'join_date', e.original_join_date, 'status', e.status,
    'last_working_date', coalesce(e.separation_date, e.last_working_date),
    'separated', e.status = 'SEPARATED',
    'job_en', j.name_en, 'job_ar', coalesce(j.name_ar, j.name_en), 'department_en', d.name_en, 'department_ar', coalesce(d.name_ar, d.name_en),
    'entity_en', le.name_en, 'entity_ar', coalesce(le.name_ar, le.name_en), 'entity_cr', le.cr_number, 'entity_code', le.code,
    'salary', case when comp is null then null else jsonb_build_object('basic', comp->'basic', 'gross', comp->'gross',
                'lines', (select coalesce(jsonb_agg(jsonb_build_object('code', l->>'code', 'name_en', l->>'name_en', 'name_ar', l->>'name_ar',
                            'amount', (l->>'amount')::numeric) order by (l->>'sort')::int), '[]'::jsonb)
                          from jsonb_array_elements(comp->'lines') l where l->>'kind' = 'EARNING')) end);
end $$;

create or replace function hr.letter_json(l hr.letters)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_snap jsonb := l.snapshot; v_salary_ok boolean := hr.has_perm('EMP_SALARY_READ') or hr.is_me(l.employee_id);
begin
  if v_snap is not null and not v_salary_ok then v_snap := v_snap - 'salary'; end if;
  return hr.emp_brief(l.employee_id) || jsonb_build_object(
    'id', l.id, 'letter_type', l.letter_type, 'language', l.language, 'addressee', l.addressee, 'purpose', l.purpose,
    'details', l.details, 'include_salary', l.include_salary, 'status', l.status,
    'requested_by_name', hr.user_label(l.requested_by), 'requested_at', l.requested_at, 'self_requested', hr.employee_user(l.employee_id) = l.requested_by,
    'prepared_by_name', hr.user_label(l.prepared_by), 'prepared_at', l.prepared_at,
    'approved_by_name', hr.user_label(l.approved_by), 'approved_at', l.approved_at, 'decision_note', l.decision_note,
    'ref_no', l.ref_no, 'verify_code', case when l.status = 'ISSUED' and (hr.is_me(l.employee_id) or hr.has_perm('LETTER_PREPARE')) then l.verify_code end,
    'issue_date', l.issue_date, 'snapshot', v_snap, 'salary_hidden', l.include_salary and not v_salary_ok,
    'revoked', l.revoked_at is not null, 'revoked_at', l.revoked_at, 'revoke_reason', l.revoke_reason,
    'can_prepare', l.status = 'REQUESTED' and hr.has_perm('LETTER_PREPARE') and not hr.is_me(l.employee_id),
    'can_approve', l.status = 'PREPARED' and hr.has_perm('LETTER_APPROVE') and not hr.is_me(l.employee_id)
                   and auth.uid() is distinct from l.prepared_by
                   and (not l.include_salary or hr.has_perm('EMP_SALARY_READ')),
    'can_cancel', l.status in ('REQUESTED','PREPARED') and (auth.uid() = l.requested_by or hr.has_perm('LETTER_PREPARE')) ,
    'can_revoke', l.status = 'ISSUED' and l.revoked_at is null and hr.has_perm('LETTER_APPROVE'));
end $$;

create or replace function hr.next_letter_ref(p_entity uuid, p_on date)
returns text language plpgsql security definer set search_path = '' as $$
declare v_no int; v_year int := extract(year from p_on)::int; v_code text;
begin
  insert into hr.letter_counters(entity_id, year, last_no) values (p_entity, v_year, 1)
  on conflict (entity_id, year) do update set last_no = hr.letter_counters.last_no + 1
  returning last_no into v_no;
  select code into v_code from hr.legal_entities where id = p_entity;
  return coalesce(v_code, 'HR') || '/HR/' || v_year || '/' || lpad(v_no::text, 4, '0');
end $$;

-- 12 random characters from a version-4 UUID (122 random bits), easy to type: no 0/O/1/I confusion.
create or replace function hr.new_verify_code()
returns text language sql volatile set search_path = '' as $$
  select translate(upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)), '01', 'XY')
$$;

-- Grant anonymous execute only to the public letter check; everything else stays signed-in only.
create or replace function hr.secure_api()
returns void language plpgsql set search_path = '' as $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'hr\_%'
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
    if r.proname = 'hr_verify_letter' then
      execute format('grant execute on function %s to anon', r.sig);
    end if;
  end loop;
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'hr'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  revoke all on all tables in schema hr from public, anon, authenticated;
  revoke all on all sequences in schema hr from public, anon, authenticated;
end $$;

select hr.attach_audit();
select hr.secure_api();
