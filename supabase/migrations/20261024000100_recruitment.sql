-- AACT HRMS — 040 Phase 5: recruitment & onboarding — tables, permissions, rules, helpers.
-- Idempotent; no destructive statements.

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
insert into hr.permissions(code, module, description) values
  ('REC_READ',    'Recruitment', 'View requisitions, candidates, interviews, offers, onboarding and probation'),
  ('REC_WRITE',   'Recruitment', 'Raise requisitions; add candidates; schedule interviews; prepare offers; run onboarding and hire'),
  ('REC_APPROVE', 'Recruitment', 'Approve requisitions and offers prepared by someone else; recruitment settings')
on conflict (code) do nothing;

insert into hr.role_permissions(role_code, perm_code)
select 'SUPER_ADMIN', code from hr.permissions
on conflict do nothing;

insert into hr.role_permissions(role_code, perm_code)
select r, p from (values
  ('HR_MANAGER','REC_READ'),('HR_MANAGER','REC_WRITE'),('HR_MANAGER','REC_APPROVE'),
  ('HR_OFFICER','REC_READ'),('HR_OFFICER','REC_WRITE'),
  ('AUDITOR','REC_READ')
) v(r, p)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Settings: probation limits (Labour Law) and onboarding checklists
-- ---------------------------------------------------------------------------
insert into hr.settings(key, value) values
  ('recruitment', jsonb_build_object(
     'probation_monthly_max_months', 3,
     'probation_other_max_months', 2,
     'probation_legal_basis', 'Labour Law RD 53/2023 — probation: up to 3 months for monthly-paid workers, 2 months for others; once with the same employer',
     'probation_reminder_days', 14,
     'onboarding', jsonb_build_object(
       'EXPAT_ABROAD', jsonb_build_array(
         jsonb_build_object('code','LABOUR_CLEARANCE','en','Work permit (labour clearance) from the Ministry of Labour','ar','ترخيص العمل من وزارة العمل','days',-45),
         jsonb_build_object('code','VISA','en','Employment visa from Royal Oman Police','ar','تأشيرة العمل من شرطة عمان السلطانية','days',-30),
         jsonb_build_object('code','FLIGHT','en','Air ticket and arrival pick-up','ar','تذكرة السفر والاستقبال عند الوصول','days',-7),
         jsonb_build_object('code','ACCOMMODATION','en','Accommodation and transport arranged','ar','ترتيب السكن والمواصلات','days',-3),
         jsonb_build_object('code','INDUCTION','en','Safety induction and PPE issued','ar','التعريف بالسلامة وصرف معدات الوقاية','days',0),
         jsonb_build_object('code','MEDICAL','en','Medical fitness examination','ar','الفحص الطبي','days',7),
         jsonb_build_object('code','CONTRACT_MOL','en','Contract signed and registered with the Ministry of Labour','ar','توقيع العقد وتسجيله في وزارة العمل','days',7),
         jsonb_build_object('code','RESIDENT_CARD','en','Fingerprints and resident card (Royal Oman Police)','ar','البصمة وبطاقة الإقامة (شرطة عمان السلطانية)','days',21),
         jsonb_build_object('code','BANK_ACCOUNT','en','Salary bank account opened and recorded','ar','فتح حساب بنكي للراتب وتسجيله','days',30)),
       'EXPAT_IN_OMAN', jsonb_build_array(
         jsonb_build_object('code','LABOUR_CLEARANCE','en','Transfer / new work permit from the Ministry of Labour','ar','نقل الكفالة / ترخيص عمل جديد من وزارة العمل','days',-21),
         jsonb_build_object('code','INDUCTION','en','Safety induction and PPE issued','ar','التعريف بالسلامة وصرف معدات الوقاية','days',0),
         jsonb_build_object('code','MEDICAL','en','Medical fitness examination','ar','الفحص الطبي','days',7),
         jsonb_build_object('code','CONTRACT_MOL','en','Contract signed and registered with the Ministry of Labour','ar','توقيع العقد وتسجيله في وزارة العمل','days',7),
         jsonb_build_object('code','RESIDENT_CARD','en','Resident card updated (Royal Oman Police)','ar','تحديث بطاقة الإقامة (شرطة عمان السلطانية)','days',21),
         jsonb_build_object('code','BANK_ACCOUNT','en','Salary bank account recorded','ar','تسجيل حساب الراتب البنكي','days',30)),
       'OMANI', jsonb_build_array(
         jsonb_build_object('code','INDUCTION','en','Safety induction and PPE issued','ar','التعريف بالسلامة وصرف معدات الوقاية','days',0),
         jsonb_build_object('code','CONTRACT_MOL','en','Contract signed and registered with the Ministry of Labour','ar','توقيع العقد وتسجيله في وزارة العمل','days',7),
         jsonb_build_object('code','SPF_REGISTRATION','en','Registered with the Social Protection Fund','ar','التسجيل في صندوق الحماية الاجتماعية','days',7),
         jsonb_build_object('code','BANK_ACCOUNT','en','Salary bank account recorded','ar','تسجيل حساب الراتب البنكي','days',30)))))
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists hr.rec_counters (
  kind  text not null,
  year  int not null,
  last_no int not null default 0,
  primary key (kind, year)
);
alter table hr.rec_counters enable row level security;

create table if not exists hr.job_requisitions (
  id              uuid primary key default gen_random_uuid(),
  ref_no          text not null unique,
  entity_id       uuid not null references hr.legal_entities(id),
  department_id   uuid not null references hr.departments(id),
  job_title_id    uuid not null references hr.job_titles(id),
  grade_id        uuid references hr.grades(id),
  category_id     uuid references hr.employee_categories(id),
  location_id     uuid references hr.locations(id),
  positions       int not null default 1 check (positions between 1 and 200),
  reason          text not null default 'NEW' check (reason in ('NEW','REPLACEMENT','TEMPORARY')),
  replaces_employee_id uuid references hr.employees(id),
  employment_type text not null default 'FULL_TIME' check (employment_type in ('FULL_TIME','PART_TIME','TEMPORARY','TRAINEE')),
  nationality_rule text not null default 'ANY' check (nationality_rule in ('ANY','OMANI_ONLY','OMANI_PREFERRED')),
  salary_min      numeric(12,3) check (salary_min is null or salary_min >= 0),
  salary_max      numeric(12,3) check (salary_max is null or salary_max >= 0),
  target_date     date,
  justification   text not null,
  status          text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','ON_HOLD','FILLED','CANCELLED')),
  requested_by    uuid not null,
  requested_at    timestamptz not null default now(),
  decided_by      uuid,
  decided_at      timestamptz,
  decision_note   text,
  closed_reason   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (salary_min is null or salary_max is null or salary_min <= salary_max),
  check (decided_by is null or decided_by <> requested_by),
  check (reason <> 'REPLACEMENT' or replaces_employee_id is not null)
);
create index if not exists job_requisitions_status on hr.job_requisitions(status, entity_id);
create index if not exists job_requisitions_dept on hr.job_requisitions(department_id);
create index if not exists job_requisitions_job on hr.job_requisitions(job_title_id);
alter table hr.job_requisitions enable row level security;

create table if not exists hr.candidates (
  id            uuid primary key default gen_random_uuid(),
  full_name_en  text not null check (length(btrim(full_name_en)) > 1),
  full_name_ar  text,
  nationality   char(2) not null references hr.countries(code),
  gender        char(1) check (gender in ('M','F')),
  date_of_birth date,
  email         text,
  phone         text,
  civil_number  text,
  passport_no   text,
  in_oman       boolean not null default false,
  current_employer text,
  experience_years numeric(4,1) check (experience_years is null or experience_years between 0 and 60),
  qualification text,
  source        text not null default 'OTHER' check (source in ('REFERRAL','AGENCY','WEBSITE','WALK_IN','INTERNAL','MOL_PORTAL','OTHER')),
  notes         text,
  employee_id   uuid references hr.employees(id),   -- set when hired
  created_by    uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists candidates_civil_uq on hr.candidates(upper(civil_number)) where civil_number is not null;
create unique index if not exists candidates_email_uq on hr.candidates(lower(email)) where email is not null;
create index if not exists candidates_name on hr.candidates(lower(full_name_en));
create index if not exists candidates_employee on hr.candidates(employee_id);
alter table hr.candidates enable row level security;

create table if not exists hr.applications (
  id             uuid primary key default gen_random_uuid(),
  requisition_id uuid not null references hr.job_requisitions(id),
  candidate_id   uuid not null references hr.candidates(id),
  stage          text not null default 'APPLIED' check (stage in ('APPLIED','SHORTLISTED','INTERVIEW','OFFER','HIRED','REJECTED','WITHDRAWN')),
  stage_at       timestamptz not null default now(),
  rejection_reason text,
  employee_id    uuid references hr.employees(id),
  created_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (requisition_id, candidate_id)
);
create index if not exists applications_candidate on hr.applications(candidate_id);
create index if not exists applications_employee on hr.applications(employee_id);
alter table hr.applications enable row level security;

create table if not exists hr.interviews (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references hr.applications(id),
  scheduled_at   timestamptz not null,
  mode           text not null default 'IN_PERSON' check (mode in ('IN_PERSON','PHONE','VIDEO')),
  location       text,
  interviewer_id uuid not null references hr.user_profiles(user_id),
  status         text not null default 'SCHEDULED' check (status in ('SCHEDULED','DONE','CANCELLED','NO_SHOW')),
  rating         int check (rating is null or rating between 1 and 5),
  recommendation text check (recommendation is null or recommendation in ('HIRE','MAYBE','NO')),
  feedback       text,
  recorded_at    timestamptz,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (status <> 'DONE' or (rating is not null and recommendation is not null))
);
create index if not exists interviews_app on hr.interviews(application_id);
create index if not exists interviews_interviewer on hr.interviews(interviewer_id, status, scheduled_at);
alter table hr.interviews enable row level security;

create table if not exists hr.job_offers (
  id             uuid primary key default gen_random_uuid(),
  ref_no         text not null unique,
  application_id uuid not null references hr.applications(id),
  job_title_id   uuid not null references hr.job_titles(id),
  department_id  uuid not null references hr.departments(id),
  grade_id       uuid references hr.grades(id),
  category_id    uuid not null references hr.employee_categories(id),
  location_id    uuid references hr.locations(id),
  start_date     date not null,
  contract_type  text not null default 'FIXED_TERM' check (contract_type in ('FIXED_TERM','INDEFINITE')),
  contract_months int check (contract_months is null or contract_months between 1 and 60),
  probation_months int not null default 0 check (probation_months between 0 and 6),
  notice_days    int not null default 30 check (notice_days between 0 and 180),
  lines          jsonb not null,           -- [{code, amount}] monthly earnings
  benefits       text,                     -- tickets, accommodation, transport, medical … (free text)
  valid_until    date,
  status         text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','ACCEPTED','DECLINED','WITHDRAWN')),
  prepared_by    uuid not null,
  prepared_at    timestamptz not null default now(),
  approved_by    uuid,
  approved_at    timestamptz,
  decision_note  text,
  response_at    timestamptz,
  response_note  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (approved_by is null or approved_by <> prepared_by),
  check (contract_type <> 'FIXED_TERM' or contract_months is not null)
);
create index if not exists job_offers_app on hr.job_offers(application_id);
create unique index if not exists job_offers_one_open on hr.job_offers(application_id) where status in ('PENDING','APPROVED','ACCEPTED');
alter table hr.job_offers enable row level security;

create table if not exists hr.onboarding_tasks (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references hr.applications(id),
  employee_id    uuid references hr.employees(id),
  code           text not null,
  title_en       text not null,
  title_ar       text not null,
  due_date       date,
  status         text not null default 'PENDING' check (status in ('PENDING','DONE','NOT_NEEDED')),
  note           text,
  done_by        uuid,
  done_at        timestamptz,
  sort           int not null default 100,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (application_id, code)
);
create index if not exists onboarding_open on hr.onboarding_tasks(status, due_date);
create index if not exists onboarding_employee on hr.onboarding_tasks(employee_id);
alter table hr.onboarding_tasks enable row level security;

-- Phase 4 follow-up (advisor): index the e-mail queue's user link
create index if not exists email_outbox_user on hr.email_outbox(user_id);

-- Audit everything except logs, recomputed tables, queues and counters.
create or replace function hr.attach_audit()
returns void language plpgsql set search_path = '' as $$
declare r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'hr' and c.relkind = 'r'
      and c.relname not in ('audit_log','access_log','notifications','attendance_days','email_outbox','letter_counters','rec_counters')
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

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function hr.next_rec_ref(p_kind text, p_on date)
returns text language plpgsql security definer set search_path = '' as $$
declare v_no int; v_year int := extract(year from p_on)::int;
begin
  insert into hr.rec_counters(kind, year, last_no) values (p_kind, v_year, 1)
  on conflict (kind, year) do update set last_no = hr.rec_counters.last_no + 1
  returning last_no into v_no;
  return p_kind || '-' || v_year || '-' || lpad(v_no::text, 4, '0');
end $$;

create or replace function hr.rec_setting(p_key text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select (select value from hr.settings where key = 'recruitment')->p_key
$$;

-- Maximum probation (months) for a category: monthly-paid vs others.
create or replace function hr.probation_max_months(p_category uuid)
returns int language sql stable security definer set search_path = '' as $$
  select case when coalesce((select pay_basis from hr.employee_categories where id = p_category), 'MONTHLY') = 'MONTHLY'
              then coalesce((hr.rec_setting('probation_monthly_max_months') #>> '{}')::int, 3)
              else coalesce((hr.rec_setting('probation_other_max_months') #>> '{}')::int, 2) end
$$;

-- Has this candidate already worked for the company (probation is allowed only once with the same employer)?
create or replace function hr.candidate_prior_employee(p_candidate uuid, p_entity uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select e.id from hr.candidates c join hr.employees e on e.entity_id = p_entity
    and ((c.civil_number is not null and upper(e.civil_number) = upper(c.civil_number))
      or (c.employee_id is not null and e.id = c.employee_id))
  where c.id = p_candidate
  order by e.join_date desc limit 1
$$;

-- Omanisation position for a hire: current ratio, target, and the ratio after the requested hires.
create or replace function hr.hire_omanisation(p_entity uuid, p_department uuid, p_job uuid, p_positions int)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_on date := hr.today(); j hr.job_titles; v_tot int; v_om int; v_dtot int; v_dom int; t hr.omanisation_targets; td hr.omanisation_targets; v_n int := greatest(coalesce(p_positions, 1), 1);
begin
  select * into j from hr.job_titles where id = p_job;
  select count(*), count(*) filter (where is_omani) into v_tot, v_om from hr.omanisation_population(p_entity, v_on);
  select count(*), count(*) filter (where is_omani) into v_dtot, v_dom from hr.omanisation_population(p_entity, v_on) where department_id = p_department;
  t := hr.target_for(p_entity, 'ENTITY', null, null, v_on);
  td := hr.target_for(p_entity, 'DEPARTMENT', p_department, null, v_on);
  return jsonb_build_object(
    'job_omani_only', coalesce(j.omani_only, false), 'job_omani_only_source', j.omani_only_source,
    'entity', hr.omanisation_row(v_tot, v_om, t),
    'department', hr.omanisation_row(v_dtot, v_dom, td),
    'pct_if_omani', case when v_tot + v_n = 0 then null else round(100.0 * (v_om + v_n) / (v_tot + v_n), 2) end,
    'pct_if_expat', case when v_tot + v_n = 0 then null else round(100.0 * v_om / (v_tot + v_n), 2) end,
    'expat_breaks_target', t.id is not null and v_tot + v_n > 0 and (100.0 * v_om / (v_tot + v_n)) < t.target_pct,
    'target_pct', t.target_pct);
end $$;

-- Who may see a requisition / application: recruitment staff, the requester, interviewers on it.
create or replace function hr.can_see_requisition(r hr.job_requisitions)
returns boolean language sql stable security definer set search_path = '' as $$
  select hr.has_perm('REC_READ') or r.requested_by = auth.uid()
      or exists (select 1 from hr.applications a join hr.interviews i on i.application_id = a.id
                 where a.requisition_id = r.id and i.interviewer_id = auth.uid())
$$;

create or replace function hr.can_see_application(p_app uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select hr.has_perm('REC_READ')
      or exists (select 1 from hr.applications a join hr.job_requisitions r on r.id = a.requisition_id where a.id = p_app and r.requested_by = auth.uid())
      or exists (select 1 from hr.interviews i where i.application_id = p_app and i.interviewer_id = auth.uid())
$$;

create or replace function hr.offer_gross(p_lines jsonb)
returns numeric language sql immutable set search_path = '' as $$
  select coalesce(sum((l->>'amount')::numeric), 0) from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l
$$;

create or replace function hr.offer_lines_named(p_lines jsonb)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'name_en', c.name_en, 'name_ar', coalesce(c.name_ar, c.name_en),
           'amount', (l->>'amount')::numeric, 'is_basic', c.is_basic) order by c.sort), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l join hr.pay_components c on c.code = l->>'code'
$$;

create or replace function hr.requisition_json(r hr.job_requisitions)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', r.id, 'ref_no', r.ref_no, 'entity_id', r.entity_id, 'entity_code', le.code,
    'department_id', r.department_id, 'department_en', d.name_en, 'department_ar', d.name_ar,
    'job_title_id', r.job_title_id, 'job_en', j.name_en, 'job_ar', j.name_ar, 'job_omani_only', j.omani_only,
    'grade_id', r.grade_id, 'grade_en', g.name_en, 'grade_ar', g.name_ar,
    'category_id', r.category_id, 'category_en', c.name_en, 'category_ar', c.name_ar, 'location_id', r.location_id,
    'positions', r.positions, 'reason', r.reason, 'replaces_employee_id', r.replaces_employee_id,
    'replaces_name', (select full_name_en from hr.employees where id = r.replaces_employee_id),
    'employment_type', r.employment_type, 'nationality_rule', r.nationality_rule,
    'salary_min', case when hr.has_perm('REC_READ') or r.requested_by = auth.uid() then r.salary_min end,
    'salary_max', case when hr.has_perm('REC_READ') or r.requested_by = auth.uid() then r.salary_max end,
    'target_date', r.target_date, 'justification', r.justification, 'status', r.status,
    'requested_by_name', hr.user_label(r.requested_by), 'requested_at', r.requested_at,
    'decided_by_name', hr.user_label(r.decided_by), 'decided_at', r.decided_at, 'decision_note', r.decision_note, 'closed_reason', r.closed_reason,
    'hired', (select count(*) from hr.applications a where a.requisition_id = r.id and a.stage = 'HIRED'),
    'in_pipeline', (select count(*) from hr.applications a where a.requisition_id = r.id and a.stage not in ('HIRED','REJECTED','WITHDRAWN')),
    'can_decide', r.status = 'PENDING' and hr.has_perm('REC_APPROVE') and auth.uid() <> r.requested_by,
    'can_edit', r.status = 'PENDING' and (auth.uid() = r.requested_by or hr.has_perm('REC_WRITE')),
    'can_manage', r.status in ('APPROVED','ON_HOLD') and hr.has_perm('REC_WRITE'))
  from hr.legal_entities le, hr.departments d, hr.job_titles j
  left join hr.grades g on g.id = r.grade_id
  left join hr.employee_categories c on c.id = r.category_id
  where le.id = r.entity_id and d.id = r.department_id and j.id = r.job_title_id
$$;

create or replace function hr.candidate_json(c hr.candidates)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'full_name_en', c.full_name_en, 'full_name_ar', c.full_name_ar, 'nationality', c.nationality,
    'nationality_en', (select nationality_en from hr.countries where code = c.nationality),
    'nationality_ar', (select nationality_ar from hr.countries where code = c.nationality),
    'is_omani', c.nationality = 'OM', 'gender', c.gender, 'date_of_birth', c.date_of_birth, 'email', c.email, 'phone', c.phone,
    'civil_number', c.civil_number, 'passport_no', c.passport_no, 'in_oman', c.in_oman, 'current_employer', c.current_employer,
    'experience_years', c.experience_years, 'qualification', c.qualification, 'source', c.source, 'notes', c.notes,
    'employee_id', c.employee_id, 'created_at', c.created_at)
$$;

create or replace function hr.offer_json(o hr.job_offers)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_sal boolean := hr.has_perm('REC_WRITE') or hr.has_perm('REC_APPROVE') or hr.has_perm('EMP_SALARY_READ');
begin
  return jsonb_build_object(
    'id', o.id, 'ref_no', o.ref_no, 'application_id', o.application_id,
    'job_title_id', o.job_title_id, 'job_en', (select name_en from hr.job_titles where id = o.job_title_id), 'job_ar', (select name_ar from hr.job_titles where id = o.job_title_id),
    'department_id', o.department_id, 'department_en', (select name_en from hr.departments where id = o.department_id),
    'department_ar', (select name_ar from hr.departments where id = o.department_id),
    'grade_id', o.grade_id, 'category_id', o.category_id, 'category_en', (select name_en from hr.employee_categories where id = o.category_id),
    'category_ar', (select name_ar from hr.employee_categories where id = o.category_id),
    'location_id', o.location_id, 'location_en', (select name_en from hr.locations where id = o.location_id),
    'location_ar', (select name_ar from hr.locations where id = o.location_id),
    'start_date', o.start_date, 'contract_type', o.contract_type, 'contract_months', o.contract_months, 'probation_months', o.probation_months,
    'notice_days', o.notice_days, 'benefits', o.benefits, 'valid_until', o.valid_until,
    'lines', case when v_sal then hr.offer_lines_named(o.lines) else '[]'::jsonb end,
    'gross', case when v_sal then hr.offer_gross(o.lines) end,
    'status', o.status, 'prepared_by_name', hr.user_label(o.prepared_by), 'prepared_at', o.prepared_at,
    'approved_by_name', hr.user_label(o.approved_by), 'approved_at', o.approved_at, 'decision_note', o.decision_note,
    'response_at', o.response_at, 'response_note', o.response_note,
    'can_decide', o.status = 'PENDING' and hr.has_perm('REC_APPROVE') and auth.uid() <> o.prepared_by,
    'can_edit', o.status = 'PENDING' and hr.has_perm('REC_WRITE'),
    'can_respond', o.status = 'APPROVED' and hr.has_perm('REC_WRITE'),
    'can_withdraw', o.status in ('PENDING','APPROVED','ACCEPTED') and hr.has_perm('REC_WRITE')
                    and not exists (select 1 from hr.applications a where a.id = o.application_id and a.stage = 'HIRED'),
    'can_hire', o.status = 'ACCEPTED' and hr.has_perm('REC_WRITE') and hr.has_perm('EMP_WRITE') and hr.has_perm('EMP_SALARY_WRITE')
                and not exists (select 1 from hr.applications a where a.id = o.application_id and a.stage = 'HIRED'));
end $$;

create or replace function hr.interview_json(i hr.interviews)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', i.id, 'application_id', i.application_id, 'scheduled_at', i.scheduled_at, 'mode', i.mode, 'location', i.location,
    'interviewer_id', i.interviewer_id, 'interviewer_name', hr.user_label(i.interviewer_id), 'status', i.status, 'rating', i.rating,
    'recommendation', i.recommendation, 'feedback', i.feedback, 'recorded_at', i.recorded_at,
    'can_record', i.status = 'SCHEDULED' and (auth.uid() = i.interviewer_id or hr.has_perm('REC_WRITE')),
    'can_cancel', i.status = 'SCHEDULED' and hr.has_perm('REC_WRITE'))
$$;

create or replace function hr.application_brief(a hr.applications)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', a.id, 'requisition_id', a.requisition_id, 'candidate_id', a.candidate_id, 'stage', a.stage, 'stage_at', a.stage_at,
    'rejection_reason', a.rejection_reason, 'employee_id', a.employee_id,
    'full_name_en', c.full_name_en, 'full_name_ar', c.full_name_ar, 'nationality', c.nationality, 'is_omani', c.nationality = 'OM',
    'in_oman', c.in_oman, 'source', c.source, 'experience_years', c.experience_years,
    'interviews', (select count(*) from hr.interviews i where i.application_id = a.id and i.status <> 'CANCELLED'),
    'avg_rating', (select round(avg(i.rating), 1) from hr.interviews i where i.application_id = a.id and i.status = 'DONE'),
    'offer_status', (select o.status from hr.job_offers o where o.application_id = a.id order by o.prepared_at desc limit 1))
  from hr.candidates c where c.id = a.candidate_id
$$;

-- Create the onboarding checklist for an accepted offer (once).
create or replace function hr.create_onboarding(p_app uuid, p_start date)
returns int language plpgsql security definer set search_path = '' as $$
declare c hr.candidates; v_kind text; t jsonb; n int := 0; k int := 0;
begin
  select cd.* into c from hr.applications a join hr.candidates cd on cd.id = a.candidate_id where a.id = p_app;
  v_kind := case when c.nationality = 'OM' then 'OMANI' when c.in_oman then 'EXPAT_IN_OMAN' else 'EXPAT_ABROAD' end;
  for t in select * from jsonb_array_elements(coalesce(hr.rec_setting('onboarding')->v_kind, '[]'::jsonb)) loop
    k := k + 1;
    insert into hr.onboarding_tasks(application_id, code, title_en, title_ar, due_date, sort)
    values (p_app, t->>'code', t->>'en', coalesce(t->>'ar', t->>'en'), p_start + coalesce((t->>'days')::int, 0), k * 10)
    on conflict (application_id, code) do nothing;
    get diagnostics n = row_count;
  end loop;
  return k;
end $$;

-- Line manager's login from the assignment in force, or the first one for someone who has not joined yet.
create or replace function hr.line_manager_user(p_employee uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select up.user_id from hr.user_profiles up
  where up.is_active and up.employee_id = (select a.manager_id from hr.employee_assignments a where a.employee_id = p_employee
                                           and (a.effective_to is null or a.effective_to >= hr.today()) order by a.effective_from limit 1)
  limit 1
$$;

-- Daily: remind HR and the line manager before probation ends (and when it has passed without a decision).
create or replace function hr.probation_reminders()
returns int language plpgsql security definer set search_path = '' as $$
declare e record; u record; v_days int := coalesce((hr.rec_setting('probation_reminder_days') #>> '{}')::int, 14); n int := 0;
begin
  for e in select emp.id, emp.employee_no, emp.full_name_en, emp.full_name_ar, emp.probation_end_date
           from hr.employees emp where emp.status = 'PROBATION' and emp.probation_end_date is not null
             and emp.probation_end_date <= hr.today() + v_days loop
    for u in select h.user_id from hr.users_with_perm('REC_APPROVE') h
             union select hr.line_manager_user(e.id) where hr.line_manager_user(e.id) is not null loop
      n := n + hr.notify(u.user_id, 'REMINDER', case when e.probation_end_date < hr.today() then 'HIGH' else 'NORMAL' end,
        'Probation ends ' || to_char(e.probation_end_date, 'DD/MM/YYYY') || ' — ' || e.full_name_en,
        'تنتهي فترة التجربة ' || to_char(e.probation_end_date, 'DD/MM/YYYY') || ' — ' || coalesce(e.full_name_ar, e.full_name_en),
        'Confirm the employee or end the employment before the date.', 'يرجى تثبيت الموظف أو إنهاء الخدمة قبل التاريخ.',
        '/probation', 'PROB:' || e.id || ':' || e.probation_end_date);
    end loop;
  end loop;
  return n;
end $$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('hr-probation-reminders', '30 3 * * *', 'select hr.probation_reminders()');
  end if;
end $$;

select hr.attach_audit();
select hr.secure_api();
