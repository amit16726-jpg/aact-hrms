-- AACT HRMS — 050 Phase 6: performance, training, discipline, assets & PPE, housing & transport, work injuries, exit.
-- Idempotent; no destructive statements.

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
insert into hr.permissions(code, module, description) values
  ('PERF_MANAGE',  'Performance', 'Run appraisal cycles, finalise reviews, issue and close improvement plans'),
  ('TRAIN_WRITE',  'Training',    'Maintain courses and training records'),
  ('DISC_READ',    'Discipline',  'View disciplinary cases (sensitive)'),
  ('DISC_WRITE',   'Discipline',  'Open and investigate disciplinary cases; propose penalties'),
  ('DISC_APPROVE', 'Discipline',  'Decide penalties proposed by someone else'),
  ('ASSET_WRITE',  'Assets',      'Issue and receive assets and PPE; manage accommodation and transport'),
  ('HSE_WRITE',    'Safety',      'Record and close work injuries'),
  ('EXIT_MANAGE',  'Exit',        'Run the exit workflow (notice, clearance, exit interview, separation)')
on conflict (code) do nothing;

insert into hr.role_permissions(role_code, perm_code)
select 'SUPER_ADMIN', code from hr.permissions
on conflict do nothing;

insert into hr.role_permissions(role_code, perm_code)
select r, p from (values
  ('HR_MANAGER','PERF_MANAGE'),('HR_MANAGER','TRAIN_WRITE'),('HR_MANAGER','DISC_READ'),('HR_MANAGER','DISC_WRITE'),('HR_MANAGER','DISC_APPROVE'),
  ('HR_MANAGER','ASSET_WRITE'),('HR_MANAGER','HSE_WRITE'),('HR_MANAGER','EXIT_MANAGE'),
  ('HR_OFFICER','TRAIN_WRITE'),('HR_OFFICER','DISC_READ'),('HR_OFFICER','DISC_WRITE'),('HR_OFFICER','ASSET_WRITE'),('HR_OFFICER','HSE_WRITE'),
  ('HR_OFFICER','EXIT_MANAGE'),
  ('AUDITOR','DISC_READ')
) v(r, p)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Policy settings (legal values with their source; change only with a dated decision)
-- ---------------------------------------------------------------------------
insert into hr.settings(key, value) values
  ('hr_policies', jsonb_build_object(
     'pip_min_months', 6,
     'pip_legal_basis', 'Labour Law RD 53/2023 — poor performance: written notice and at least 6 months to improve before termination',
     'notice_monthly_days', 30, 'notice_other_days', 15,
     'notice_legal_basis', 'Labour Law RD 53/2023 — notice: 30 days for monthly-paid workers, 15 days for others (unless the contract gives more)',
     'non_compete_max_months', 24, 'non_compete_legal_basis', 'Labour Law RD 53/2023 — non-compete clause: at most 2 years after the contract ends',
     'discipline_max_deduction_days', 5, 'discipline_max_suspension_days', 5,
     'discipline_legal_basis', 'Company disciplinary regulation approved by the Ministry of Labour — confirm the limits',
     'injury_report_days', 7, 'injury_legal_basis', 'Report work injuries to the Social Protection Fund (work-injury branch) — confirm the deadline',
     'exit_tasks', jsonb_build_object(
       'COMMON', jsonb_build_array(
         jsonb_build_object('code','HANDOVER','en','Work handed over to the line manager','ar','تسليم العمل للمدير المباشر'),
         jsonb_build_object('code','IT_ACCESS','en','E-mail and system access removed','ar','إيقاف البريد وصلاحيات الأنظمة'),
         jsonb_build_object('code','SETTLEMENT','en','Final settlement approved and paid','ar','اعتماد التسوية النهائية وصرفها'),
         jsonb_build_object('code','EXPERIENCE_LETTER','en','Experience letter issued','ar','إصدار شهادة الخبرة'),
         jsonb_build_object('code','EXIT_INTERVIEW','en','Exit interview held','ar','إجراء مقابلة الخروج')),
       'EXPAT', jsonb_build_array(
         jsonb_build_object('code','RESIDENCE_CANCEL','en','Resident card / visa cancelled or transferred (Royal Oman Police)','ar','إلغاء أو نقل الإقامة (شرطة عمان السلطانية)'),
         jsonb_build_object('code','WORK_PERMIT_CANCEL','en','Work permit cancelled with the Ministry of Labour','ar','إلغاء ترخيص العمل لدى وزارة العمل'),
         jsonb_build_object('code','AIR_TICKET','en','Return air ticket provided','ar','توفير تذكرة العودة')),
       'OMANI', jsonb_build_array(
         jsonb_build_object('code','SPF_END','en','End of service reported to the Social Protection Fund','ar','إبلاغ صندوق الحماية الاجتماعية بانتهاء الخدمة')))))
on conflict (key) do nothing;

create or replace function hr.policy(p_key text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select (select value from hr.settings where key = 'hr_policies')->p_key
$$;

create or replace function hr.policy_num(p_key text, p_default numeric)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce((hr.policy(p_key) #>> '{}')::numeric, p_default)
$$;

-- ---------------------------------------------------------------------------
-- Performance
-- ---------------------------------------------------------------------------
create table if not exists hr.perf_cycles (
  id           uuid primary key default gen_random_uuid(),
  entity_id    uuid not null references hr.legal_entities(id),
  name         text not null,
  period_start date not null,
  period_end   date not null,
  due_date     date,
  self_review  boolean not null default true,
  status       text not null default 'DRAFT' check (status in ('DRAFT','OPEN','CLOSED')),
  created_by   uuid,
  opened_at    timestamptz,
  closed_at    timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (period_end >= period_start)
);
alter table hr.perf_cycles enable row level security;

create table if not exists hr.perf_reviews (
  id              uuid primary key default gen_random_uuid(),
  cycle_id        uuid not null references hr.perf_cycles(id),
  employee_id     uuid not null references hr.employees(id),
  reviewer_id     uuid references hr.employees(id),     -- line manager when the cycle opened
  status          text not null default 'SELF' check (status in ('SELF','MANAGER','HR','ACK','DONE')),
  goals           jsonb not null default '[]'::jsonb,   -- [{title, weight, self_rating, rating, comment}]
  self_comments   text,
  manager_comments text,
  hr_comments     text,
  overall_rating  numeric(3,2) check (overall_rating is null or overall_rating between 1 and 5),
  employee_comment text,
  submitted_self_at timestamptz,
  submitted_manager_at timestamptz,
  finalised_by    uuid,
  finalised_at    timestamptz,
  acknowledged_at timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (cycle_id, employee_id)
);
create index if not exists perf_reviews_emp on hr.perf_reviews(employee_id);
create index if not exists perf_reviews_reviewer on hr.perf_reviews(reviewer_id, status);
alter table hr.perf_reviews enable row level security;

create table if not exists hr.perf_plans (
  id           uuid primary key default gen_random_uuid(),
  employee_id  uuid not null references hr.employees(id),
  review_id    uuid references hr.perf_reviews(id),
  issued_on    date not null,
  ends_on      date not null,
  areas        text not null,
  support      text,
  status       text not null default 'ACTIVE' check (status in ('ACTIVE','IMPROVED','NOT_IMPROVED','CANCELLED')),
  outcome_note text,
  issued_by    uuid not null,
  closed_by    uuid,
  closed_at    timestamptz,
  acknowledged_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (ends_on > issued_on)
);
create index if not exists perf_plans_emp on hr.perf_plans(employee_id, status);
alter table hr.perf_plans enable row level security;

-- ---------------------------------------------------------------------------
-- Training
-- ---------------------------------------------------------------------------
create table if not exists hr.training_courses (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,
  name_en         text not null,
  name_ar         text,
  provider        text,
  category        text not null default 'GENERAL' check (category in ('SAFETY','TECHNICAL','COMPLIANCE','SOFT_SKILLS','GENERAL')),
  validity_months int check (validity_months is null or validity_months between 1 and 120),
  mandatory       boolean not null default false,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
alter table hr.training_courses enable row level security;

create table if not exists hr.training_records (
  id             uuid primary key default gen_random_uuid(),
  employee_id    uuid not null references hr.employees(id),
  course_id      uuid not null references hr.training_courses(id),
  status         text not null default 'COMPLETED' check (status in ('PLANNED','COMPLETED','CANCELLED')),
  planned_on     date,
  completed_on   date,
  expires_on     date,
  certificate_no text,
  score          text,
  cost           numeric(12,3) check (cost is null or cost >= 0),
  notes          text,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (status <> 'COMPLETED' or completed_on is not null),
  check (expires_on is null or completed_on is null or expires_on > completed_on)
);
create index if not exists training_records_emp on hr.training_records(employee_id, course_id);
create index if not exists training_records_course on hr.training_records(course_id);
create index if not exists training_records_expiry on hr.training_records(expires_on) where status = 'COMPLETED';
alter table hr.training_records enable row level security;

-- ---------------------------------------------------------------------------
-- Discipline (sensitive)
-- ---------------------------------------------------------------------------
create table if not exists hr.disciplinary_cases (
  id             uuid primary key default gen_random_uuid(),
  ref_no         text not null unique,
  employee_id    uuid not null references hr.employees(id),
  incident_date  date not null,
  category       text not null check (category in ('ATTENDANCE','CONDUCT','SAFETY','PERFORMANCE','POLICY','OTHER')),
  description    text not null,
  status         text not null default 'DRAFT' check (status in ('DRAFT','INVESTIGATION','PROPOSED','DECIDED','DISMISSED')),
  investigation_notes text,
  employee_response text,
  response_at    timestamptz,
  proposed_penalty text check (proposed_penalty is null or proposed_penalty in ('VERBAL_WARNING','WRITTEN_WARNING','FINAL_WARNING','DEDUCTION','SUSPENSION','TERMINATION','NONE')),
  proposed_days  numeric(4,1),
  proposed_by    uuid,
  proposed_at    timestamptz,
  penalty        text check (penalty is null or penalty in ('VERBAL_WARNING','WRITTEN_WARNING','FINAL_WARNING','DEDUCTION','SUSPENSION','TERMINATION','NONE')),
  penalty_days   numeric(4,1),
  decided_by     uuid,
  decided_at     timestamptz,
  decision_note  text,
  adjustment_id  uuid references hr.payroll_adjustments(id),
  appeal         text,
  appeal_at      timestamptz,
  opened_by      uuid not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (decided_by is null or (decided_by <> opened_by and decided_by is distinct from proposed_by))
);
create index if not exists disciplinary_emp on hr.disciplinary_cases(employee_id, incident_date desc);
alter table hr.disciplinary_cases enable row level security;

-- ---------------------------------------------------------------------------
-- Assets & PPE
-- ---------------------------------------------------------------------------
create table if not exists hr.asset_items (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  name_en     text not null,
  name_ar     text,
  category    text not null default 'PPE' check (category in ('PPE','UNIFORM','IT','TOOL','VEHICLE','KEY','CARD','OTHER')),
  returnable  boolean not null default true,
  unit_cost   numeric(12,3) check (unit_cost is null or unit_cost >= 0),
  replace_months int check (replace_months is null or replace_months between 1 and 60),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table hr.asset_items enable row level security;

create table if not exists hr.asset_issues (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references hr.employees(id),
  item_id       uuid not null references hr.asset_items(id),
  qty           int not null default 1 check (qty between 1 and 100),
  serial_no     text,
  issued_on     date not null,
  due_return_on date,
  status        text not null default 'ISSUED' check (status in ('ISSUED','RETURNED','LOST','CONSUMED')),
  returned_on   date,
  condition     text check (condition is null or condition in ('GOOD','WORN','DAMAGED','LOST')),
  recovery_adjustment_id uuid references hr.payroll_adjustments(id),
  notes         text,
  issued_by     uuid,
  received_by   uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (returned_on is null or returned_on >= issued_on)
);
create index if not exists asset_issues_emp on hr.asset_issues(employee_id, status);
create index if not exists asset_issues_item on hr.asset_issues(item_id);
alter table hr.asset_issues enable row level security;

-- ---------------------------------------------------------------------------
-- Accommodation & transport
-- ---------------------------------------------------------------------------
create table if not exists hr.facilities (
  id          uuid primary key default gen_random_uuid(),
  entity_id   uuid not null references hr.legal_entities(id),
  kind        text not null check (kind in ('ACCOMMODATION','TRANSPORT')),
  code        text not null,
  name_en     text not null,
  name_ar     text,
  address     text,          -- accommodation address, or the route for transport
  capacity    int not null check (capacity between 1 and 2000),
  vehicle_no  text,
  driver_employee_id uuid references hr.employees(id),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (entity_id, kind, code)
);
alter table hr.facilities enable row level security;

create table if not exists hr.facility_assignments (
  id           uuid primary key default gen_random_uuid(),
  facility_id  uuid not null references hr.facilities(id),
  employee_id  uuid not null references hr.employees(id),
  place        text,          -- room/bed or seat/pick-up point
  from_date    date not null,
  to_date      date,
  created_by   uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (to_date is null or to_date >= from_date)
);
create index if not exists facility_assignments_fac on hr.facility_assignments(facility_id, to_date);
create index if not exists facility_assignments_emp on hr.facility_assignments(employee_id, to_date);
alter table hr.facility_assignments enable row level security;

-- ---------------------------------------------------------------------------
-- Work injuries
-- ---------------------------------------------------------------------------
create table if not exists hr.work_injuries (
  id            uuid primary key default gen_random_uuid(),
  ref_no        text not null unique,
  employee_id   uuid not null references hr.employees(id),
  occurred_at   timestamptz not null,
  location      text not null,
  description   text not null,
  injury_type   text,
  body_part     text,
  severity      text not null check (severity in ('FIRST_AID','MEDICAL','LOST_TIME','PERMANENT','FATAL')),
  lost_days     int not null default 0 check (lost_days between 0 and 3650),
  witnesses     text,
  root_cause    text,
  corrective_action text,
  spf_reported_on date,
  spf_reference text,
  status        text not null default 'OPEN' check (status in ('OPEN','CLOSED')),
  closed_by     uuid,
  closed_at     timestamptz,
  created_by    uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists work_injuries_emp on hr.work_injuries(employee_id);
create index if not exists work_injuries_status on hr.work_injuries(status, occurred_at desc);
alter table hr.work_injuries enable row level security;

-- ---------------------------------------------------------------------------
-- Exit workflow
-- ---------------------------------------------------------------------------
create table if not exists hr.exit_cases (
  id              uuid primary key default gen_random_uuid(),
  employee_id     uuid not null references hr.employees(id),
  exit_type       text not null check (exit_type in ('RESIGNATION','TERMINATION','END_OF_CONTRACT','RETIREMENT','OTHER')),
  notice_given_on date not null,
  last_working_date date not null,
  notice_days     int not null,
  pay_in_lieu     boolean not null default false,
  reason          text,
  non_compete_months int not null default 0 check (non_compete_months between 0 and 24),
  status          text not null default 'OPEN' check (status in ('OPEN','COMPLETED','CANCELLED')),
  interview       jsonb,     -- {reason_code, would_return, rating, comments}
  completed_at    timestamptz,
  completed_by    uuid,
  cancel_reason   text,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (last_working_date >= notice_given_on)
);
create unique index if not exists exit_cases_one_open on hr.exit_cases(employee_id) where status = 'OPEN';
alter table hr.exit_cases enable row level security;

create table if not exists hr.exit_tasks (
  id        uuid primary key default gen_random_uuid(),
  exit_id   uuid not null references hr.exit_cases(id),
  code      text not null,
  title_en  text not null,
  title_ar  text not null,
  ref_id    uuid,            -- asset issue or facility assignment this step clears
  status    text not null default 'PENDING' check (status in ('PENDING','DONE','NOT_NEEDED')),
  note      text,
  done_by   uuid,
  done_at   timestamptz,
  sort      int not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (exit_id, code)
);
alter table hr.exit_tasks enable row level security;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Training certificates expire like documents: add them to the expiry tracker and the daily alerts.
create or replace function hr.expiry_items(p_on date default current_date)
returns table (
  employee_id uuid, source text, ref_id uuid, doc_type text, name_en text, name_ar text,
  doc_number text, expiry_date date, days_left int, bucket text, is_sensitive boolean, alert_days int[])
language sql stable security definer set search_path = '' as $$
  select d.employee_id, 'DOCUMENT', d.id, d.doc_type, t.name_en, t.name_ar, d.doc_number, d.expiry_date,
         (d.expiry_date - p_on)::int, hr.expiry_bucket((d.expiry_date - p_on)::int), t.is_sensitive, t.alert_days
  from hr.employee_documents d
  join hr.document_types t on t.code = d.doc_type
  join hr.employees e on e.id = d.employee_id
  where d.is_current and d.status = 'ACTIVE' and d.expiry_date is not null and e.status <> 'SEPARATED'
  union all
  select c.employee_id, 'CONTRACT', c.id, 'CONTRACT', 'Employment contract', 'عقد العمل', c.contract_no, c.end_date,
         (c.end_date - p_on)::int, hr.expiry_bucket((c.end_date - p_on)::int), false, '{90,60,30}'::int[]
  from hr.employee_contracts c
  join hr.employees e on e.id = c.employee_id
  where c.status = 'ACTIVE' and c.end_date is not null and e.status <> 'SEPARATED'
  union all
  -- only the latest completed record per employee and course
  select r.employee_id, 'TRAINING', r.id, 'TRAINING:' || tc.code, tc.name_en, coalesce(tc.name_ar, tc.name_en), r.certificate_no, r.expires_on,
         (r.expires_on - p_on)::int, hr.expiry_bucket((r.expires_on - p_on)::int), false, '{60,30}'::int[]
  from hr.training_records r
  join hr.training_courses tc on tc.id = r.course_id
  join hr.employees e on e.id = r.employee_id
  where r.status = 'COMPLETED' and r.expires_on is not null and e.status <> 'SEPARATED'
    and not exists (select 1 from hr.training_records r2 where r2.employee_id = r.employee_id and r2.course_id = r.course_id
                    and r2.status = 'COMPLETED' and r2.completed_on > r.completed_on)
$$;

create or replace function hr.next_ref(p_kind text)
returns text language plpgsql security definer set search_path = '' as $$
begin
  return hr.next_rec_ref(p_kind, hr.today());
end $$;

-- Weighted overall rating from goals (weights default to equal).
create or replace function hr.goals_rating(p_goals jsonb)
returns numeric language sql immutable set search_path = '' as $$
  select case when coalesce(sum(coalesce(nullif(g->>'weight','')::numeric, 1)) filter (where nullif(g->>'rating','') is not null), 0) = 0 then null
              else round(sum(coalesce(nullif(g->>'weight','')::numeric, 1) * (g->>'rating')::numeric) filter (where nullif(g->>'rating','') is not null)
                         / sum(coalesce(nullif(g->>'weight','')::numeric, 1)) filter (where nullif(g->>'rating','') is not null), 2) end
  from jsonb_array_elements(coalesce(p_goals, '[]'::jsonb)) g
$$;

create or replace function hr.daily_gross(p_employee uuid, p_on date)
returns numeric language sql stable security definer set search_path = '' as $$
  select round(coalesce((hr.comp_on(p_employee, p_on)->>'gross')::numeric, 0) / 30.0, 3)
$$;

create or replace function hr.notice_min_days(p_employee uuid)
returns int language sql stable security definer set search_path = '' as $$
  select case when coalesce((select c.pay_basis from hr.employee_categories c
                             where c.id = (select a.category_id from hr.employee_assignments a where a.employee_id = p_employee
                                           order by (a.effective_to is null) desc, a.effective_from desc limit 1)), 'MONTHLY') = 'MONTHLY'
              then hr.policy_num('notice_monthly_days', 30)::int else hr.policy_num('notice_other_days', 15)::int end
$$;

select hr.attach_audit();
select hr.secure_api();
