-- AACT HRMS — 060 Phase 7: personal data protection (PDPL), statutory reports, executive view, data import.
-- Idempotent; no destructive statements.

insert into hr.permissions(code, module, description) values
  ('PDPL_READ',   'Privacy', 'View the privacy register, consents, data-subject requests and breach log'),
  ('PDPL_MANAGE', 'Privacy', 'Publish the privacy notice, handle data-subject requests and breaches, maintain the processing register'),
  ('EXEC_VIEW',   'Reports', 'Executive dashboard (headcount, turnover, Omanisation, cost)'),
  ('DATA_IMPORT', 'Admin',   'Import employees, documents and opening data from spreadsheets')
on conflict (code) do nothing;

insert into hr.role_permissions(role_code, perm_code)
select 'SUPER_ADMIN', code from hr.permissions
on conflict do nothing;

insert into hr.role_permissions(role_code, perm_code)
select r, p from (values
  ('HR_MANAGER','PDPL_READ'),('HR_MANAGER','PDPL_MANAGE'),('HR_MANAGER','EXEC_VIEW'),('HR_MANAGER','DATA_IMPORT'),
  ('AUDITOR','PDPL_READ'),('AUDITOR','EXEC_VIEW'),
  ('FINANCE','EXEC_VIEW')
) v(r, p)
on conflict do nothing;

-- Values from the Personal Data Protection Law (RD 6/2022) and its Executive Regulation (MTCIT decision 34/2024), kept with their source.
insert into hr.settings(key, value) values
  ('pdpl', jsonb_build_object(
     'dsr_days', 45, 'dsr_legal_basis', 'PDPL Executive Regulation — reply to a data subject''s request within 45 days',
     'breach_hours', 72, 'breach_legal_basis', 'PDPL Executive Regulation — notify the Ministry (MTCIT) of a personal data breach within 72 hours of becoming aware of it',
     'controller', 'AACT', 'dpo_name', null, 'dpo_email', null,
     'retention', jsonb_build_array(
       jsonb_build_object('code','EX_EMPLOYEE','en','Records of employees who have left','ar','سجلات الموظفين الذين تركوا العمل','months',120,'basis','Labour Law limitation and tax/SPF audits — confirm'),
       jsonb_build_object('code','CANDIDATE','en','Candidates not hired','ar','المرشحون الذين لم يُعيَّنوا','months',12,'basis','Consent / legitimate interest — confirm'),
       jsonb_build_object('code','ATTENDANCE','en','Raw attendance punches','ar','بصمات الحضور الأصلية','months',36,'basis','Payroll evidence — confirm'),
       jsonb_build_object('code','ACCESS_LOG','en','Access log of sensitive data','ar','سجل الاطلاع على البيانات الحساسة','months',60,'basis','Accountability — confirm'))))
on conflict (key) do nothing;

create or replace function hr.pdpl(p_key text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select (select value from hr.settings where key = 'pdpl')->p_key
$$;

-- ---------------------------------------------------------------------------
-- Privacy notice (versioned) and acknowledgements / consents
-- ---------------------------------------------------------------------------
create table if not exists hr.privacy_notices (
  id            uuid primary key default gen_random_uuid(),
  version       int not null unique,
  title_en      text not null,
  title_ar      text not null,
  body_en       text not null,
  body_ar       text not null,
  status        text not null default 'DRAFT' check (status in ('DRAFT','PUBLISHED','RETIRED')),
  prepared_by   uuid,
  published_by  uuid,
  published_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (published_by is null or published_by is distinct from prepared_by)
);
create unique index if not exists privacy_notices_one_published on hr.privacy_notices((true)) where status = 'PUBLISHED';
alter table hr.privacy_notices enable row level security;

-- Template text (draft version 1) — HR must review it with legal advice, then publish (published by someone other than the preparer).
insert into hr.privacy_notices(version, title_en, title_ar, body_en, body_ar)
select 1, 'Employee privacy notice', 'إشعار الخصوصية للموظفين',
'1. Who we are. The company named in your employment contract ("the company") is the controller of your personal data under the Personal Data Protection Law (Royal Decree 6/2022).
2. What we collect. Identity and contact details, family and emergency contacts, nationality and residence documents, job, contract, salary and bank details, attendance and leave, training, performance, disciplinary and safety records. Health information is kept only where the law requires it (for example sick leave and work injuries).
3. Why. To run your employment contract, pay salaries and Social Protection Fund contributions, meet the Labour Law, residence and Omanisation rules, keep the workplace safe and defend legal claims.
4. Who receives it. Government bodies (Ministry of Labour, Social Protection Fund, Royal Oman Police), banks for salary payment, auditors and service providers bound by confidentiality. Data is kept on the company''s server in Oman and is not transferred abroad without the safeguards the law requires.
5. How long. Only as long as needed for the purpose and legal limitation periods, as set out in the company''s retention rules.
6. Your rights. You may ask to see, correct, restrict or object to the processing of your data, ask for erasure where the law allows, withdraw a consent you gave, and complain to the Ministry of Transport, Communications and Information Technology. Use "My HR → Privacy" or write to HR. We reply within 45 days.
7. Security. Access is limited by role, every change is recorded, and sensitive records (salary, discipline, health) are restricted further.',
'1. من نحن: الشركة المذكورة في عقد عملك ("الشركة") هي المتحكم في بياناتك الشخصية وفق قانون حماية البيانات الشخصية الصادر بالمرسوم السلطاني رقم 6/2022.
2. ما نجمعه: بيانات الهوية والاتصال، وجهات الاتصال العائلية والطارئة، والجنسية ووثائق الإقامة، والوظيفة والعقد والراتب والبيانات المصرفية، والحضور والإجازات، والتدريب والأداء والسجلات التأديبية والسلامة. ولا نحتفظ بالمعلومات الصحية إلا حيث يتطلب القانون ذلك (مثل الإجازات المرضية وإصابات العمل).
3. لماذا: لتنفيذ عقد عملك، وصرف الرواتب واشتراكات صندوق الحماية الاجتماعية، والالتزام بقانون العمل وأنظمة الإقامة والتعمين، والحفاظ على سلامة بيئة العمل، والدفاع في المطالبات القانونية.
4. من يتلقاها: الجهات الحكومية (وزارة العمل، صندوق الحماية الاجتماعية، شرطة عمان السلطانية)، والبنوك لصرف الرواتب، والمدققون ومقدمو الخدمات الملتزمون بالسرية. تُحفظ البيانات على خادم الشركة في سلطنة عمان ولا تُنقل إلى الخارج دون الضمانات التي يتطلبها القانون.
5. مدة الاحتفاظ: فقط للمدة اللازمة للغرض ولمدد التقادم القانونية، وفق قواعد الاحتفاظ المعتمدة في الشركة.
6. حقوقك: يحق لك الاطلاع على بياناتك وتصحيحها وتقييد معالجتها أو الاعتراض عليها، وطلب محوها حيث يسمح القانون، وسحب موافقة سبق أن منحتها، وتقديم شكوى إلى وزارة النقل والاتصالات وتقنية المعلومات. استخدم "شؤوني الوظيفية ← الخصوصية" أو راسل الموارد البشرية، وسنرد خلال 45 يوماً.
7. الأمان: الوصول محدود حسب الدور، وكل تعديل مسجَّل، والسجلات الحساسة (الراتب، التأديب، الصحة) مقيدة بشكل إضافي.'
where not exists (select 1 from hr.privacy_notices);

-- One row per person and purpose; acknowledgement of the notice is purpose NOTICE.
create table if not exists hr.consents (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references hr.user_profiles(user_id),
  employee_id    uuid references hr.employees(id),
  purpose        text not null check (purpose in ('NOTICE','PHOTO_DIRECTORY','MARKETING_MEDIA','BIOMETRIC','HEALTH_DATA','TRANSFER_ABROAD')),
  notice_version int,
  given          boolean not null,
  given_at       timestamptz not null default now(),
  withdrawn_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists consents_current on hr.consents(user_id, purpose) where withdrawn_at is null;
alter table hr.consents enable row level security;

-- ---------------------------------------------------------------------------
-- Data-subject requests (45 days)
-- ---------------------------------------------------------------------------
create table if not exists hr.dsr_requests (
  id            uuid primary key default gen_random_uuid(),
  ref_no        text not null unique,
  employee_id   uuid references hr.employees(id),
  candidate_id  uuid references hr.candidates(id),
  requester_name text not null,
  contact       text,
  kind          text not null check (kind in ('ACCESS','CORRECTION','ERASURE','RESTRICTION','OBJECTION','PORTABILITY','WITHDRAW_CONSENT','COMPLAINT')),
  details       text not null,
  received_on   date not null,
  due_on        date not null,
  identity_checked boolean not null default false,
  status        text not null default 'OPEN' check (status in ('OPEN','IN_PROGRESS','COMPLETED','REJECTED')),
  outcome       text,
  created_by    uuid,
  closed_by     uuid,
  closed_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (due_on >= received_on)
);
alter table hr.dsr_requests enable row level security;

-- ---------------------------------------------------------------------------
-- Breach log (72 hours)
-- ---------------------------------------------------------------------------
create table if not exists hr.data_breaches (
  id              uuid primary key default gen_random_uuid(),
  ref_no          text not null unique,
  discovered_at   timestamptz not null,
  occurred_at     timestamptz,
  description     text not null,
  data_kinds      text,
  people_affected int check (people_affected is null or people_affected >= 0),
  risk            text not null check (risk in ('LOW','MEDIUM','HIGH')),
  containment     text,
  contained_at    timestamptz,
  authority_notified_at timestamptz,
  authority_reference text,
  not_notified_reason text,
  subjects_notified_at timestamptz,
  status          text not null default 'OPEN' check (status in ('OPEN','CLOSED')),
  created_by      uuid,
  closed_by       uuid,
  closed_at       timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
alter table hr.data_breaches enable row level security;

-- ---------------------------------------------------------------------------
-- Register of processing activities
-- ---------------------------------------------------------------------------
create table if not exists hr.processing_activities (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  name_en       text not null,
  name_ar       text,
  purpose       text not null,
  legal_basis   text not null check (legal_basis in ('CONTRACT','LEGAL_OBLIGATION','CONSENT','VITAL_INTEREST','PUBLIC_INTEREST','LEGITIMATE_INTEREST')),
  data_subjects text not null,
  data_categories text not null,
  sensitive     boolean not null default false,
  recipients    text,
  transfer_outside_oman text,
  retention     text,
  security      text,
  system_owner  text,
  is_active     boolean not null default true,
  reviewed_at   date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table hr.processing_activities enable row level security;

insert into hr.processing_activities(code, name_en, name_ar, purpose, legal_basis, data_subjects, data_categories, sensitive, recipients, transfer_outside_oman, retention, security, system_owner) values
  ('EMP_RECORDS', 'Employee records', 'سجلات الموظفين', 'Managing the employment relationship', 'CONTRACT', 'Employees', 'Identity, contact, job, contract, family contacts', false,
   'Ministry of Labour, Royal Oman Police (residence), banks (WPS)', 'None (company server in Oman)', 'See retention rules: employees who left', 'Role-based access, audit trail, encrypted backups', 'HR manager'),
  ('PAYROLL', 'Payroll and benefits', 'الرواتب والمزايا', 'Paying salaries, SPF contributions, end-of-service benefits', 'LEGAL_OBLIGATION', 'Employees', 'Salary, bank account, attendance, deductions', false,
   'Banks (WPS), Social Protection Fund, auditors', 'None', '10 years after leaving — confirm', 'Maker-checker, Finance-only access, audit trail', 'Finance manager'),
  ('ATTENDANCE', 'Attendance and leave', 'الحضور والإجازات', 'Working time, overtime and leave under the Labour Law', 'LEGAL_OBLIGATION', 'Employees', 'Punch times, leave, sick notes', true,
   'Line managers', 'None', 'Raw punches 3 years — confirm', 'Sick-note details restricted to HR', 'HR manager'),
  ('RECRUITMENT', 'Recruitment', 'التوظيف', 'Selecting candidates', 'CONSENT', 'Candidates', 'CV, contact, interview feedback', false,
   'Interviewers (without contact details)', 'None', '12 months if not hired — confirm', 'Need-to-know access', 'HR manager'),
  ('HSE', 'Work injuries and safety', 'إصابات العمل والسلامة', 'Recording work injuries and reporting to the Social Protection Fund', 'LEGAL_OBLIGATION', 'Employees', 'Injury details', true,
   'Social Protection Fund', 'None', '10 years — confirm', 'HSE and HR only', 'HSE officer'),
  ('DISCIPLINE', 'Disciplinary cases', 'القضايا التأديبية', 'Applying the disciplinary regulation', 'LEGAL_OBLIGATION', 'Employees', 'Allegations, responses, decisions', true,
   'None', 'None', 'Duration of employment plus limitation period — confirm', 'Every view logged', 'HR manager')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Import batches (spreadsheet migration from the old system)
-- ---------------------------------------------------------------------------
create table if not exists hr.import_batches (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('EMPLOYEES','DOCUMENTS','SALARIES')),
  file_name   text,
  dry_run     boolean not null,
  rows_total  int not null,
  rows_ok     int not null,
  rows_failed int not null,
  results     jsonb not null default '[]'::jsonb,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table hr.import_batches enable row level security;

-- Reference number helper for the new registers (DSR-YYYY-NNNN, BR-YYYY-NNNN)
create or replace function hr.dsr_due(p_from date)
returns date language sql stable security definer set search_path = '' as $$
  select p_from + coalesce((hr.pdpl('dsr_days') #>> '{}')::int, 45)
$$;

create or replace function hr.breach_deadline(p_discovered timestamptz)
returns timestamptz language sql stable security definer set search_path = '' as $$
  select p_discovered + make_interval(hours => coalesce((hr.pdpl('breach_hours') #>> '{}')::int, 72))
$$;

select hr.attach_audit();
select hr.secure_api();
