-- AACT HRMS — 004 employee documents, versions, secure file storage

create table if not exists hr.document_types (
  code           text primary key check (code ~ '^[A-Z0-9_]{2,40}$'),
  name_en        text not null,
  name_ar        text not null,
  category       text not null check (category in ('IDENTITY','IMMIGRATION','EMPLOYMENT','QUALIFICATION',
                                                   'MEDICAL','LICENCE','POLICY','DISCIPLINARY','OTHER')),
  has_number     boolean not null default true,
  has_expiry     boolean not null default false,
  alert_days     int[] not null default '{90,60,30}',
  applies_to     text not null default 'ALL' check (applies_to in ('ALL','OMANI','EXPAT')),
  is_mandatory   boolean not null default false,
  allow_multiple boolean not null default false,
  is_sensitive   boolean not null default false,
  rule_basis     text not null default 'COMPANY_POLICY' check (rule_basis in ('LEGAL','COMPANY_POLICY')),
  rule_reference text,
  sort           int not null default 100,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (not is_sensitive or category in ('MEDICAL','DISCIPLINARY','OTHER')),
  check (array_position(alert_days, null) is null)
);

-- Defaults are company-policy suggestions; HR confirms mandatory flags and alert days before go-live.
insert into hr.document_types(code, name_en, name_ar, category, has_number, has_expiry, alert_days, applies_to,
                              is_mandatory, allow_multiple, is_sensitive, sort) values
  ('PASSPORT',        'Passport',                     'جواز السفر',               'IDENTITY',      true,  true,  '{180,90,60,30}', 'ALL',   false, false, false, 10),
  ('CIVIL_ID',        'Omani civil ID card',          'البطاقة الشخصية',           'IDENTITY',      true,  true,  '{90,60,30}',     'OMANI', true,  false, false, 11),
  ('RESIDENT_CARD',   'Resident card',                'بطاقة المقيم',              'IMMIGRATION',   true,  true,  '{90,60,30}',     'EXPAT', true,  false, false, 20),
  ('EMPLOYMENT_VISA', 'Employment visa',              'تأشيرة العمل',              'IMMIGRATION',   true,  true,  '{90,60,30}',     'EXPAT', true,  false, false, 21),
  ('WORK_PERMIT',     'Work permit / labour clearance','تصريح العمل',              'IMMIGRATION',   true,  true,  '{90,60,30}',     'EXPAT', true,  false, false, 22),
  ('CONTRACT_COPY',   'Signed employment contract',   'عقد العمل الموقع',          'EMPLOYMENT',    false, false, '{}',             'ALL',   true,  true,  false, 30),
  ('OFFER_LETTER',    'Offer letter',                 'خطاب العرض',                'EMPLOYMENT',    false, false, '{}',             'ALL',   false, true,  false, 31),
  ('EDU_CERT',        'Educational qualification',    'المؤهل العلمي',             'QUALIFICATION', true,  false, '{}',             'ALL',   false, true,  false, 40),
  ('PROF_CERT',       'Professional certificate',     'شهادة مهنية',               'QUALIFICATION', true,  true,  '{60,30}',        'ALL',   false, true,  false, 41),
  ('DRIVING_LICENCE', 'Driving licence',              'رخصة القيادة',              'LICENCE',       true,  true,  '{60,30}',        'ALL',   false, false, false, 50),
  ('MEDICAL_FITNESS', 'Medical fitness certificate',  'شهادة اللياقة الطبية',      'MEDICAL',       true,  true,  '{60,30}',        'EXPAT', false, false, true,  60),
  ('POLICY_ACK',      'Signed policy acknowledgement','إقرار السياسات',            'POLICY',        false, false, '{}',             'ALL',   false, true,  false, 70),
  ('DISCIPLINARY',    'Disciplinary record',          'سجل تأديبي',                'DISCIPLINARY',  true,  false, '{}',             'ALL',   false, true,  true,  80),
  ('OTHER',           'Other document',               'مستند آخر',                 'OTHER',         true,  false, '{}',             'ALL',   false, true,  false, 99)
on conflict (code) do nothing;

create table if not exists hr.employee_documents (
  id               uuid primary key default gen_random_uuid(),
  employee_id      uuid not null references hr.employees(id),
  doc_type         text not null references hr.document_types(code),
  doc_number       text,
  title            text,
  issue_date       date,
  expiry_date      date,
  issuing_authority text,
  issue_place      text,
  version          int not null default 1,
  supersedes_id    uuid references hr.employee_documents(id),
  is_current       boolean not null default true,
  status           text not null default 'ACTIVE' check (status in ('ACTIVE','SUPERSEDED','CANCELLED')),
  file_path        text,
  file_name        text,
  mime_type        text,
  file_size        bigint,
  verified_by      uuid,
  verified_at      timestamptz,
  cancel_reason    text,
  notes            text,
  uploaded_by      uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (expiry_date is null or issue_date is null or expiry_date >= issue_date),
  check (status <> 'ACTIVE' or is_current),
  check (status = 'ACTIVE' or not is_current),
  check (status <> 'CANCELLED' or coalesce(cancel_reason,'') <> '')
);
create index if not exists employee_documents_emp on hr.employee_documents(employee_id, doc_type, is_current);
create index if not exists employee_documents_expiry on hr.employee_documents(expiry_date) where is_current;
create unique index if not exists employee_documents_file_uq on hr.employee_documents(file_path) where file_path is not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'employee_contracts_document_fk') then
    alter table hr.employee_contracts
      add constraint employee_contracts_document_fk foreign key (document_id) references hr.employee_documents(id);
  end if;
end $$;

-- Single-instance types (passport, resident card …): only one current document per employee.
create or replace function hr.check_single_current_document()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_multi boolean;
begin
  if not new.is_current then return new; end if;
  select allow_multiple into v_multi from hr.document_types where code = new.doc_type;
  if not coalesce(v_multi, false) and exists (
       select 1 from hr.employee_documents d
       where d.employee_id = new.employee_id and d.doc_type = new.doc_type
         and d.is_current and d.id <> new.id) then
    raise exception 'DUPLICATE_DOCUMENT: This employee already has a current % — replace it instead of adding another.', new.doc_type;
  end if;
  return new;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'ab_single_current_document') then
    create trigger ab_single_current_document before insert or update on hr.employee_documents
      for each row execute function hr.check_single_current_document();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- File storage: private bucket, path = <employee_id>/<DOC_TYPE or PHOTO>/<uuid>.<ext>
-- Files are never overwritten or deleted by the app; a new version is a new file.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hr-documents', 'hr-documents', false, 10485760,
        array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create or replace function public.hr_storage_can_read(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_emp uuid; v_type text; v_access text; v_sensitive boolean;
begin
  if auth.uid() is null or array_length(v_parts, 1) <> 3 then return false; end if;
  if v_parts[1] !~ '^[0-9a-fA-F-]{36}$' then return false; end if;
  v_emp := v_parts[1]::uuid; v_type := v_parts[2];
  if not exists (select 1 from hr.user_profiles where user_id = auth.uid() and is_active) then return false; end if;
  v_access := hr.employee_access(v_emp);
  if v_access is null then return false; end if;
  if v_type = 'PHOTO' then return true; end if;
  select is_sensitive into v_sensitive from hr.document_types where code = v_type;
  if v_sensitive is null then return false; end if;
  if hr.is_me(v_emp) then return true; end if;
  if v_sensitive then return hr.has_perm('DOC_SENSITIVE'); end if;
  return hr.has_perm('DOC_READ');
end $$;

create or replace function public.hr_storage_can_write(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_emp uuid; v_type text;
begin
  if auth.uid() is null or array_length(v_parts, 1) <> 3 then return false; end if;
  if v_parts[1] !~ '^[0-9a-fA-F-]{36}$' then return false; end if;
  v_emp := v_parts[1]::uuid; v_type := v_parts[2];
  if not exists (select 1 from hr.user_profiles where user_id = auth.uid() and is_active) then return false; end if;
  if not exists (select 1 from hr.employees where id = v_emp) then return false; end if;
  if v_type = 'PHOTO' then return hr.has_perm('EMP_WRITE'); end if;
  if not exists (select 1 from hr.document_types where code = v_type and is_active) then return false; end if;
  return hr.has_perm('DOC_WRITE');
end $$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                 and policyname = 'hr_documents_read') then
    create policy hr_documents_read on storage.objects for select to authenticated
      using (bucket_id = 'hr-documents' and public.hr_storage_can_read(name));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                 and policyname = 'hr_documents_insert') then
    create policy hr_documents_insert on storage.objects for insert to authenticated
      with check (bucket_id = 'hr-documents' and public.hr_storage_can_write(name));
  end if;
end $$;

select hr.attach_audit();
select hr.secure_api();
