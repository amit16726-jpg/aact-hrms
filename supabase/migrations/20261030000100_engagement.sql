-- =============================================================================
-- 1.14.0 — Employee engagement: company announcements, simple surveys and recognition.
--  * Announcements and surveys are prepared by HR and published only after a second person approves (maker-checker).
--  * Peer recognition is posted at once (moderated by HR); formal awards need a second person's approval.
--  * Anonymous surveys: who took part is recorded (one answer each), but answers carry no person, no time and are
--    kept out of the audit trail; results show only once enough people have answered.
-- Idempotent; no destructive statements.
-- =============================================================================

insert into hr.permissions(code, module, description) values
  ('ENGAGE_MANAGE',  'Engagement', 'Prepare announcements, surveys and awards; see survey results; moderate recognition'),
  ('ENGAGE_APPROVE', 'Engagement', 'Approve announcements, surveys and awards prepared by someone else')
on conflict (code) do nothing;

insert into hr.role_permissions(role_code, perm_code)
select 'SUPER_ADMIN', code from hr.permissions
on conflict do nothing;

insert into hr.role_permissions(role_code, perm_code)
select r, p from (values
  ('HR_MANAGER','ENGAGE_MANAGE'),('HR_MANAGER','ENGAGE_APPROVE'),
  ('HR_OFFICER','ENGAGE_MANAGE')
) v(r, p)
on conflict do nothing;

insert into hr.settings(key, value) values
  ('engagement', '{"survey_min_responses": 5, "peer_daily_limit": 5}')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table if not exists hr.announcements (
  id             uuid primary key default gen_random_uuid(),
  entity_id      uuid references hr.legal_entities(id),
  department_id  uuid references hr.departments(id),
  category       text not null default 'GENERAL' check (category in ('GENERAL','HR_POLICY','EVENT','SAFETY','HOLIDAY','CELEBRATION','IT')),
  title_en       text not null check (length(btrim(title_en)) between 3 and 150),
  title_ar       text,
  body_en        text not null check (length(btrim(body_en)) between 3 and 5000),
  body_ar        text,
  pinned         boolean not null default false,
  require_ack    boolean not null default false,
  publish_on     date not null,
  expires_on     date,
  status         text not null default 'DRAFT' check (status in ('DRAFT','PENDING','PUBLISHED','REJECTED','ARCHIVED')),
  created_by     uuid references hr.user_profiles(user_id),
  created_at     timestamptz not null default now(),
  submitted_at   timestamptz,
  decided_by     uuid references hr.user_profiles(user_id),
  decided_at     timestamptz,
  decision_note  text,
  notified_on    date,
  archived_by    uuid references hr.user_profiles(user_id),
  archived_at    timestamptz,
  updated_at     timestamptz not null default now(),
  check (expires_on is null or expires_on >= publish_on)
);
create index if not exists announcements_status_idx on hr.announcements(status, publish_on desc);
create index if not exists announcements_entity_idx on hr.announcements(entity_id);
create index if not exists announcements_department_idx on hr.announcements(department_id);
create index if not exists announcements_created_by_idx on hr.announcements(created_by);
create index if not exists announcements_decided_by_idx on hr.announcements(decided_by);
create index if not exists announcements_archived_by_idx on hr.announcements(archived_by);

create table if not exists hr.announcement_reads (
  announcement_id  uuid not null references hr.announcements(id),
  user_id          uuid not null references hr.user_profiles(user_id),
  read_at          timestamptz not null default now(),
  acknowledged_at  timestamptz,
  primary key (announcement_id, user_id)
);
create index if not exists announcement_reads_user_idx on hr.announcement_reads(user_id);

create table if not exists hr.surveys (
  id             uuid primary key default gen_random_uuid(),
  entity_id      uuid references hr.legal_entities(id),
  department_id  uuid references hr.departments(id),
  title_en       text not null check (length(btrim(title_en)) between 3 and 150),
  title_ar       text,
  intro_en       text,
  intro_ar       text,
  anonymous      boolean not null default true,
  questions      jsonb not null default '[]'::jsonb check (jsonb_typeof(questions) = 'array'),
  opens_on       date not null,
  closes_on      date not null,
  status         text not null default 'DRAFT' check (status in ('DRAFT','PENDING','OPEN','REJECTED','CLOSED')),
  created_by     uuid references hr.user_profiles(user_id),
  created_at     timestamptz not null default now(),
  submitted_at   timestamptz,
  decided_by     uuid references hr.user_profiles(user_id),
  decided_at     timestamptz,
  decision_note  text,
  notified_on    date,
  closed_by      uuid references hr.user_profiles(user_id),
  closed_at      timestamptz,
  updated_at     timestamptz not null default now(),
  check (closes_on >= opens_on)
);
create index if not exists surveys_status_idx on hr.surveys(status, closes_on);
create index if not exists surveys_entity_idx on hr.surveys(entity_id);
create index if not exists surveys_department_idx on hr.surveys(department_id);
create index if not exists surveys_created_by_idx on hr.surveys(created_by);
create index if not exists surveys_decided_by_idx on hr.surveys(decided_by);
create index if not exists surveys_closed_by_idx on hr.surveys(closed_by);

-- who took part (one answer per person) — date only, no time
create table if not exists hr.survey_participants (
  survey_id     uuid not null references hr.surveys(id),
  user_id       uuid not null references hr.user_profiles(user_id),
  responded_on  date not null,
  primary key (survey_id, user_id)
);
create index if not exists survey_participants_user_idx on hr.survey_participants(user_id);

-- the answers — no user and no time; employee only for surveys that are not anonymous
create table if not exists hr.survey_answers (
  id            uuid primary key default gen_random_uuid(),
  survey_id     uuid not null references hr.surveys(id),
  response_id   uuid not null,
  question_key  text not null,
  rating        int check (rating between 1 and 5),
  choice        int check (choice >= 0),
  text_value    text check (length(text_value) <= 1000),
  employee_id   uuid references hr.employees(id)
);
create index if not exists survey_answers_survey_idx on hr.survey_answers(survey_id, question_key);
create index if not exists survey_answers_employee_idx on hr.survey_answers(employee_id);

-- Survey answers are kept out of the audit trail (it would show who gave which answer). hr.attach_audit() adds its
-- audit trigger only to tables that have no trigger called zz_audit, so this table gets a placeholder that records nothing.
create or replace function hr.no_audit()
returns trigger language plpgsql set search_path = '' as $$
begin
  return null;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'hr' and c.relname = 'survey_answers' and t.tgname = 'zz_audit') then
    create trigger zz_audit after insert on hr.survey_answers for each row execute function hr.no_audit();
  end if;
end $$;

create table if not exists hr.recognitions (
  id                 uuid primary key default gen_random_uuid(),
  kind               text not null check (kind in ('PEER','AWARD')),
  entity_id          uuid not null references hr.legal_entities(id),
  employee_id        uuid not null references hr.employees(id),
  giver_employee_id  uuid references hr.employees(id),
  category           text not null default 'TEAMWORK'
                     check (category in ('TEAMWORK','SAFETY','QUALITY','CUSTOMER','INNOVATION','EXTRA_MILE','LEADERSHIP')),
  award_title        text check (award_title is null or length(btrim(award_title)) between 3 and 100),
  message            text not null check (length(btrim(message)) between 3 and 500),
  status             text not null check (status in ('PENDING','APPROVED','REJECTED','HIDDEN')),
  created_by         uuid references hr.user_profiles(user_id),
  created_at         timestamptz not null default now(),
  decided_by         uuid references hr.user_profiles(user_id),
  decided_at         timestamptz,
  decision_note      text,
  hidden_by          uuid references hr.user_profiles(user_id),
  hidden_at          timestamptz,
  hidden_reason      text,
  updated_at         timestamptz not null default now(),
  check (kind = 'PEER' or award_title is not null)
);
create index if not exists recognitions_wall_idx on hr.recognitions(entity_id, status, created_at desc);
create index if not exists recognitions_employee_idx on hr.recognitions(employee_id);
create index if not exists recognitions_giver_idx on hr.recognitions(giver_employee_id);
create index if not exists recognitions_created_by_idx on hr.recognitions(created_by);
create index if not exists recognitions_decided_by_idx on hr.recognitions(decided_by);
create index if not exists recognitions_hidden_by_idx on hr.recognitions(hidden_by);

create table if not exists hr.recognition_applause (
  recognition_id  uuid not null references hr.recognitions(id),
  user_id         uuid not null references hr.user_profiles(user_id),
  created_at      timestamptz not null default now(),
  primary key (recognition_id, user_id)
);
create index if not exists recognition_applause_user_idx on hr.recognition_applause(user_id);

alter table hr.announcements enable row level security;
alter table hr.announcement_reads enable row level security;
alter table hr.surveys enable row level security;
alter table hr.survey_participants enable row level security;
alter table hr.survey_answers enable row level security;
alter table hr.recognitions enable row level security;
alter table hr.recognition_applause enable row level security;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function hr.engage_setting(p_key text, p_default numeric)
returns numeric language sql stable security definer set search_path = '' as $$
  select coalesce(((select value from hr.settings where key = 'engagement') ->> p_key)::numeric, p_default)
$$;

-- true when p_dept is p_root or sits below it in the department tree
create or replace function hr.dept_within(p_dept uuid, p_root uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  with recursive up as (
    select d.id, d.parent_id, 1 as depth from hr.departments d where d.id = p_dept
    union all
    select d.id, d.parent_id, up.depth + 1 from hr.departments d join up on d.id = up.parent_id where up.depth < 20
  )
  select p_root is null or exists (select 1 from up where up.id = p_root)
$$;

-- the caller's employee, company and department today
create or replace function hr.engage_me()
returns table(employee_id uuid, entity_id uuid, department_id uuid)
language sql stable security definer set search_path = '' as $$
  select e.id, e.entity_id, (hr.current_assignment(e.id, hr.today())).department_id
  from hr.user_profiles up join hr.employees e on e.id = up.employee_id
  where up.user_id = auth.uid() and up.is_active and e.status <> 'SEPARATED'
$$;

create or replace function hr.engage_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select hr.has_perm('ENGAGE_MANAGE') or hr.has_perm('ENGAGE_APPROVE')
$$;

-- is the caller (as an employee) in the audience of a company / department?
create or replace function hr.engage_in_audience(p_entity uuid, p_dept uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from hr.engage_me() m
                 where (p_entity is null or m.entity_id = p_entity) and hr.dept_within(m.department_id, p_dept))
$$;

-- active users (linked to a current employee) in an audience
create or replace function hr.engage_audience(p_entity uuid, p_dept uuid)
returns table(user_id uuid, employee_id uuid)
language sql stable security definer set search_path = '' as $$
  select up.user_id, e.id
  from hr.user_profiles up join hr.employees e on e.id = up.employee_id
  where up.is_active and e.status <> 'SEPARATED'
    and (p_entity is null or e.entity_id = p_entity)
    and (p_dept is null or hr.dept_within((hr.current_assignment(e.id, hr.today())).department_id, p_dept))
$$;

create or replace function hr.engage_notify_approvers(p_except uuid, p_title_en text, p_title_ar text, p_link text, p_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare u record;
begin
  for u in select up.user_id from hr.user_profiles up where up.is_active and up.user_id is distinct from p_except loop
    if hr.user_has_perm(u.user_id, 'ENGAGE_APPROVE') then
      perform hr.notify(u.user_id, 'ENGAGEMENT', 'NORMAL', p_title_en, p_title_ar, null, null, p_link, p_ref);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Announcements
-- ---------------------------------------------------------------------------
create or replace function hr.ann_live(a hr.announcements)
returns boolean language sql stable security definer set search_path = '' as $$
  select a.status = 'PUBLISHED' and a.publish_on <= hr.today() and (a.expires_on is null or a.expires_on >= hr.today())
$$;

create or replace function hr.ann_json(a hr.announcements)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(a) || jsonb_build_object(
    'live', hr.ann_live(a),
    'entity_code', (select le.code from hr.legal_entities le where le.id = a.entity_id),
    'department_en', (select d.name_en from hr.departments d where d.id = a.department_id),
    'department_ar', (select d.name_ar from hr.departments d where d.id = a.department_id),
    'created_by_name', hr.user_label(a.created_by), 'decided_by_name', hr.user_label(a.decided_by),
    'read_at', r.read_at, 'acknowledged_at', r.acknowledged_at,
    'can_edit', a.status in ('DRAFT','REJECTED') and hr.has_perm('ENGAGE_MANAGE'),
    'can_decide', a.status = 'PENDING' and hr.has_perm('ENGAGE_APPROVE') and a.created_by is distinct from auth.uid(),
    'can_archive', a.status = 'PUBLISHED' and hr.has_perm('ENGAGE_MANAGE'),
    'stats', case when hr.engage_staff() and a.status in ('PUBLISHED','ARCHIVED') then (
      select jsonb_build_object('audience', count(*),
               'read', count(*) filter (where x.read_at is not null),
               'acknowledged', count(*) filter (where x.acknowledged_at is not null))
      from (select au.user_id, ar.read_at, ar.acknowledged_at from hr.engage_audience(a.entity_id, a.department_id) au
            left join hr.announcement_reads ar on ar.announcement_id = a.id and ar.user_id = au.user_id) x) end)
  from (select 1) one
  left join hr.announcement_reads r on r.announcement_id = a.id and r.user_id = auth.uid()
$$;

create or replace function hr.engage_notify_announcement(p_id uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare a hr.announcements; u record; n int := 0;
begin
  select * into a from hr.announcements where id = p_id;
  if a.id is null or not hr.ann_live(a) or a.notified_on is not null then return 0; end if;
  for u in select au.user_id from hr.engage_audience(a.entity_id, a.department_id) au loop
    n := n + hr.notify(u.user_id, 'ANNOUNCEMENT', case when a.require_ack or a.category = 'SAFETY' then 'HIGH' else 'NORMAL' end,
      a.title_en, coalesce(a.title_ar, a.title_en),
      case when a.require_ack then 'Please read and confirm.' end, case when a.require_ack then 'يرجى القراءة والتأكيد.' end,
      '/engage/news/' || a.id::text, 'ann:' || a.id::text);
  end loop;
  update hr.announcements set notified_on = hr.today() where id = a.id;
  return n;
end $$;

create or replace function public.hr_list_announcements()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  if not hr.engage_staff() then raise exception 'NOT_ALLOWED: You do not have the ENGAGE_MANAGE permission.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(hr.ann_json(a) order by
      case a.status when 'PENDING' then 0 when 'DRAFT' then 1 when 'REJECTED' then 2 when 'PUBLISHED' then 3 else 4 end, a.publish_on desc, a.created_at desc)
    from hr.announcements a), '[]'::jsonb);
end $$;

-- Opening an announcement marks it read for the caller.
create or replace function public.hr_get_announcement(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.announcements; v_aud boolean;
begin
  perform hr.require_user();
  select * into a from hr.announcements where id = p_id;
  if a.id is null then raise exception 'NOT_FOUND: Announcement not found.'; end if;
  v_aud := hr.ann_live(a) and hr.engage_in_audience(a.entity_id, a.department_id);
  if not (v_aud or hr.engage_staff()) then raise exception 'NOT_FOUND: Announcement not found.'; end if;
  if v_aud then
    insert into hr.announcement_reads(announcement_id, user_id) values (a.id, auth.uid()) on conflict do nothing;
  end if;
  return hr.ann_json(a) || jsonb_build_object('in_audience', v_aud);
end $$;

create or replace function public.hr_save_announcement(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.announcements; v_id uuid := hr.juuid(p, 'id'); v_ent uuid := hr.juuid(p, 'entity_id'); v_dep uuid := hr.juuid(p, 'department_id');
        v_cat text := upper(coalesce(hr.jtext(p, 'category'), 'GENERAL')); v_from date := coalesce(hr.jdate(p, 'publish_on'), hr.today());
        v_to date := hr.jdate(p, 'expires_on');
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  if coalesce(length(btrim(hr.jtext(p, 'title_en'))), 0) < 3 then raise exception 'REQUIRED: Enter a title (at least 3 characters).'; end if;
  if coalesce(length(btrim(hr.jtext(p, 'body_en'))), 0) < 3 then raise exception 'REQUIRED: Enter the message.'; end if;
  if length(hr.jtext(p, 'title_en')) > 150 or length(coalesce(hr.jtext(p, 'title_ar'), '')) > 150 then raise exception 'INVALID: The title is too long (150 characters at most).'; end if;
  if length(hr.jtext(p, 'body_en')) > 5000 or length(coalesce(hr.jtext(p, 'body_ar'), '')) > 5000 then raise exception 'INVALID: The message is too long (5,000 characters at most).'; end if;
  if v_cat not in ('GENERAL','HR_POLICY','EVENT','SAFETY','HOLIDAY','CELEBRATION','IT') then raise exception 'INVALID: Unknown category.'; end if;
  if v_to is not null and v_to < v_from then raise exception 'INVALID: The end date is before the publish date.'; end if;
  if v_ent is not null and not exists (select 1 from hr.legal_entities where id = v_ent) then raise exception 'NOT_FOUND: Company not found.'; end if;
  if v_dep is not null and not exists (select 1 from hr.departments where id = v_dep and (v_ent is null or entity_id = v_ent)) then
    raise exception 'INVALID: The department does not belong to the chosen company.';
  end if;
  if v_id is null then
    if v_from < hr.today() then raise exception 'INVALID: The publish date cannot be in the past.'; end if;
    insert into hr.announcements(entity_id, department_id, category, title_en, title_ar, body_en, body_ar, pinned, require_ack, publish_on, expires_on, created_by)
    values (v_ent, v_dep, v_cat, btrim(hr.jtext(p, 'title_en')), nullif(btrim(coalesce(hr.jtext(p, 'title_ar'), '')), ''),
            btrim(hr.jtext(p, 'body_en')), nullif(btrim(coalesce(hr.jtext(p, 'body_ar'), '')), ''),
            hr.jbool(p, 'pinned'), hr.jbool(p, 'require_ack'), v_from, v_to, auth.uid())
    returning * into a;
  else
    select * into a from hr.announcements where id = v_id for update;
    if a.id is null then raise exception 'NOT_FOUND: Announcement not found.'; end if;
    if a.status not in ('DRAFT','REJECTED') then raise exception 'INVALID: Only a draft or a rejected announcement can be changed.'; end if;
    if v_from < hr.today() then raise exception 'INVALID: The publish date cannot be in the past.'; end if;
    update hr.announcements set entity_id = v_ent, department_id = v_dep, category = v_cat,
           title_en = btrim(hr.jtext(p, 'title_en')), title_ar = nullif(btrim(coalesce(hr.jtext(p, 'title_ar'), '')), ''),
           body_en = btrim(hr.jtext(p, 'body_en')), body_ar = nullif(btrim(coalesce(hr.jtext(p, 'body_ar'), '')), ''),
           pinned = hr.jbool(p, 'pinned'), require_ack = hr.jbool(p, 'require_ack'), publish_on = v_from, expires_on = v_to,
           status = 'DRAFT', decided_by = null, decided_at = null, decision_note = null
     where id = v_id returning * into a;
  end if;
  return hr.ann_json(a);
end $$;

create or replace function public.hr_submit_announcement(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.announcements;
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  select * into a from hr.announcements where id = p_id for update;
  if a.id is null then raise exception 'NOT_FOUND: Announcement not found.'; end if;
  if a.status not in ('DRAFT','REJECTED') then raise exception 'INVALID: Only a draft can be sent for approval.'; end if;
  if a.publish_on < hr.today() then raise exception 'INVALID: The publish date is in the past; change it first.'; end if;
  update hr.announcements set status = 'PENDING', submitted_at = now() where id = p_id returning * into a;
  perform hr.engage_notify_approvers(auth.uid(), 'Announcement to approve: ' || a.title_en, 'إعلان بانتظار الاعتماد: ' || coalesce(a.title_ar, a.title_en),
    '/engage/admin?tab=news', 'ann-approve:' || a.id::text || ':' || extract(epoch from a.submitted_at)::bigint::text);
  return hr.ann_json(a);
end $$;

create or replace function public.hr_decide_announcement(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.announcements;
begin
  perform hr.require_perm('ENGAGE_APPROVE');
  select * into a from hr.announcements where id = p_id for update;
  if a.id is null then raise exception 'NOT_FOUND: Announcement not found.'; end if;
  if a.status <> 'PENDING' then raise exception 'NOT_PENDING: This announcement is not waiting for approval.'; end if;
  if a.created_by = auth.uid() then raise exception 'SELF_APPROVAL: You cannot approve your own announcement.' using errcode = '42501'; end if;
  if not coalesce(p_approve, false) and coalesce(length(btrim(p_note)), 0) < 3 then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  update hr.announcements set status = case when p_approve then 'PUBLISHED' else 'REJECTED' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id returning * into a;
  perform hr.notify(a.created_by, 'ENGAGEMENT', 'NORMAL',
    case when p_approve then 'Announcement approved: ' else 'Announcement rejected: ' end || a.title_en,
    case when p_approve then 'تم اعتماد الإعلان: ' else 'تم رفض الإعلان: ' end || coalesce(a.title_ar, a.title_en),
    a.decision_note, a.decision_note, '/engage/admin?tab=news', 'ann-decided:' || a.id::text || ':' || extract(epoch from a.decided_at)::bigint::text);
  if p_approve then perform hr.engage_notify_announcement(a.id); end if;
  select * into a from hr.announcements where id = p_id;
  return hr.ann_json(a);
end $$;

create or replace function public.hr_archive_announcement(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.announcements;
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  update hr.announcements set status = 'ARCHIVED', archived_by = auth.uid(), archived_at = now(), pinned = false
   where id = p_id and status = 'PUBLISHED' returning * into a;
  if a.id is null then raise exception 'INVALID: Only a published announcement can be archived.'; end if;
  return hr.ann_json(a);
end $$;

create or replace function public.hr_ack_announcement(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.announcements;
begin
  perform hr.require_user();
  select * into a from hr.announcements where id = p_id;
  if a.id is null or not hr.ann_live(a) or not hr.engage_in_audience(a.entity_id, a.department_id) then
    raise exception 'NOT_FOUND: Announcement not found.';
  end if;
  if not a.require_ack then raise exception 'INVALID: This announcement does not need confirmation.'; end if;
  insert into hr.announcement_reads(announcement_id, user_id, acknowledged_at) values (a.id, auth.uid(), now())
  on conflict (announcement_id, user_id) do update set acknowledged_at = coalesce(hr.announcement_reads.acknowledged_at, now());
  return hr.ann_json(a) || jsonb_build_object('in_audience', true);
end $$;

-- Who in the audience has read / confirmed (for HR).
create or replace function public.hr_announcement_readers(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare a hr.announcements;
begin
  perform hr.require_user();
  if not hr.engage_staff() then raise exception 'NOT_ALLOWED: You do not have the ENGAGE_MANAGE permission.' using errcode = '42501'; end if;
  select * into a from hr.announcements where id = p_id;
  if a.id is null then raise exception 'NOT_FOUND: Announcement not found.'; end if;
  return coalesce((select jsonb_agg(hr.emp_brief(au.employee_id) || jsonb_build_object('read_at', r.read_at, 'acknowledged_at', r.acknowledged_at)
                     order by (r.acknowledged_at is not null), (r.read_at is not null), e.employee_no)
    from hr.engage_audience(a.entity_id, a.department_id) au join hr.employees e on e.id = au.employee_id
    left join hr.announcement_reads r on r.announcement_id = a.id and r.user_id = au.user_id), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Surveys
-- ---------------------------------------------------------------------------
create or replace function hr.survey_live(s hr.surveys)
returns boolean language sql stable security definer set search_path = '' as $$
  select s.status = 'OPEN' and s.opens_on <= hr.today() and s.closes_on >= hr.today()
$$;

create or replace function hr.survey_json(s hr.surveys)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(s) || jsonb_build_object(
    'live', hr.survey_live(s),
    'entity_code', (select le.code from hr.legal_entities le where le.id = s.entity_id),
    'department_en', (select d.name_en from hr.departments d where d.id = s.department_id),
    'department_ar', (select d.name_ar from hr.departments d where d.id = s.department_id),
    'created_by_name', hr.user_label(s.created_by), 'decided_by_name', hr.user_label(s.decided_by),
    'answered', exists (select 1 from hr.survey_participants sp where sp.survey_id = s.id and sp.user_id = auth.uid()),
    'responses', case when hr.engage_staff() then (select count(*) from hr.survey_participants sp where sp.survey_id = s.id) end,
    'audience', case when hr.engage_staff() then (select count(*) from hr.engage_audience(s.entity_id, s.department_id)) end,
    'can_edit', s.status in ('DRAFT','REJECTED') and hr.has_perm('ENGAGE_MANAGE'),
    'can_decide', s.status = 'PENDING' and hr.has_perm('ENGAGE_APPROVE') and s.created_by is distinct from auth.uid(),
    'can_close', s.status = 'OPEN' and hr.has_perm('ENGAGE_MANAGE'))
$$;

create or replace function hr.engage_notify_survey(p_id uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare s hr.surveys; u record; n int := 0;
begin
  select * into s from hr.surveys where id = p_id;
  if s.id is null or not hr.survey_live(s) or s.notified_on is not null then return 0; end if;
  for u in select au.user_id from hr.engage_audience(s.entity_id, s.department_id) au loop
    n := n + hr.notify(u.user_id, 'SURVEY', 'NORMAL', 'Survey: ' || s.title_en, 'استبيان: ' || coalesce(s.title_ar, s.title_en),
      'Please answer by ' || to_char(s.closes_on, 'DD/MM/YYYY') || case when s.anonymous then ' — your answers are anonymous.' else '.' end,
      'يرجى الإجابة قبل ' || to_char(s.closes_on, 'DD/MM/YYYY') || case when s.anonymous then ' — إجاباتك سرية.' else '.' end,
      '/engage/survey/' || s.id::text, 'survey:' || s.id::text);
  end loop;
  update hr.surveys set notified_on = hr.today() where id = s.id;
  return n;
end $$;

-- Checks the question list and gives each question a key (q1, q2 …).
create or replace function hr.survey_clean_questions(p jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare q jsonb; i int := 0; v_out jsonb := '[]'::jsonb; v_kind text; v_opts jsonb; o jsonb; v_clean jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) = 0 then raise exception 'REQUIRED: Add at least one question.'; end if;
  if jsonb_array_length(p) > 30 then raise exception 'INVALID: A survey can have at most 30 questions.'; end if;
  for q in select x from jsonb_array_elements(p) x loop
    i := i + 1;
    v_kind := upper(coalesce(q->>'kind', ''));
    if v_kind not in ('RATING','CHOICE','TEXT') then raise exception 'INVALID: Question %: choose a question type.', i; end if;
    if coalesce(length(btrim(q->>'text_en')), 0) < 3 then raise exception 'REQUIRED: Question %: enter the question.', i; end if;
    if length(q->>'text_en') > 300 or length(coalesce(q->>'text_ar', '')) > 300 then raise exception 'INVALID: Question %: too long (300 characters at most).', i; end if;
    v_opts := '[]'::jsonb;
    if v_kind = 'CHOICE' then
      if jsonb_typeof(q->'options') <> 'array' or jsonb_array_length(q->'options') not between 2 and 10 then
        raise exception 'INVALID: Question %: give between 2 and 10 choices.', i;
      end if;
      for o in select x from jsonb_array_elements(q->'options') x loop
        if coalesce(length(btrim(o->>'en')), 0) < 1 then raise exception 'REQUIRED: Question %: every choice needs text.', i; end if;
        v_opts := v_opts || jsonb_build_array(jsonb_build_object('en', left(btrim(o->>'en'), 120), 'ar', nullif(left(btrim(coalesce(o->>'ar', '')), 120), '')));
      end loop;
    end if;
    v_clean := jsonb_build_object('key', 'q' || i, 'kind', v_kind, 'text_en', btrim(q->>'text_en'),
      'text_ar', nullif(btrim(coalesce(q->>'text_ar', '')), ''), 'required', coalesce((q->>'required')::boolean, v_kind <> 'TEXT'), 'options', v_opts);
    v_out := v_out || jsonb_build_array(v_clean);
  end loop;
  return v_out;
end $$;

create or replace function public.hr_list_surveys()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  if not hr.engage_staff() then raise exception 'NOT_ALLOWED: You do not have the ENGAGE_MANAGE permission.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(hr.survey_json(s) order by
      case s.status when 'PENDING' then 0 when 'OPEN' then 1 when 'DRAFT' then 2 when 'REJECTED' then 3 else 4 end, s.closes_on desc, s.created_at desc)
    from hr.surveys s), '[]'::jsonb);
end $$;

create or replace function public.hr_get_survey(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s hr.surveys; v_aud boolean;
begin
  perform hr.require_user();
  select * into s from hr.surveys where id = p_id;
  if s.id is null then raise exception 'NOT_FOUND: Survey not found.'; end if;
  v_aud := s.status in ('OPEN','CLOSED') and s.opens_on <= hr.today() and hr.engage_in_audience(s.entity_id, s.department_id);
  if not (v_aud or hr.engage_staff()) then raise exception 'NOT_FOUND: Survey not found.'; end if;
  return hr.survey_json(s) || jsonb_build_object('in_audience', v_aud,
    'can_answer', v_aud and hr.survey_live(s) and not exists (select 1 from hr.survey_participants sp where sp.survey_id = s.id and sp.user_id = auth.uid()));
end $$;

create or replace function public.hr_save_survey(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.surveys; v_id uuid := hr.juuid(p, 'id'); v_ent uuid := hr.juuid(p, 'entity_id'); v_dep uuid := hr.juuid(p, 'department_id');
        v_from date := coalesce(hr.jdate(p, 'opens_on'), hr.today()); v_to date := hr.jdate(p, 'closes_on'); v_q jsonb;
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  if coalesce(length(btrim(hr.jtext(p, 'title_en'))), 0) < 3 then raise exception 'REQUIRED: Enter a title (at least 3 characters).'; end if;
  if length(hr.jtext(p, 'title_en')) > 150 or length(coalesce(hr.jtext(p, 'title_ar'), '')) > 150 then raise exception 'INVALID: The title is too long (150 characters at most).'; end if;
  if length(coalesce(hr.jtext(p, 'intro_en'), '')) > 2000 or length(coalesce(hr.jtext(p, 'intro_ar'), '')) > 2000 then raise exception 'INVALID: The introduction is too long.'; end if;
  if v_to is null then raise exception 'REQUIRED: Choose the closing date.'; end if;
  if v_from < hr.today() then raise exception 'INVALID: The opening date cannot be in the past.'; end if;
  if v_to < v_from then raise exception 'INVALID: The closing date is before the opening date.'; end if;
  if v_to > v_from + 180 then raise exception 'INVALID: A survey can stay open for at most 180 days.'; end if;
  if v_ent is not null and not exists (select 1 from hr.legal_entities where id = v_ent) then raise exception 'NOT_FOUND: Company not found.'; end if;
  if v_dep is not null and not exists (select 1 from hr.departments where id = v_dep and (v_ent is null or entity_id = v_ent)) then
    raise exception 'INVALID: The department does not belong to the chosen company.';
  end if;
  v_q := hr.survey_clean_questions(p->'questions');
  if v_id is null then
    insert into hr.surveys(entity_id, department_id, title_en, title_ar, intro_en, intro_ar, anonymous, questions, opens_on, closes_on, created_by)
    values (v_ent, v_dep, btrim(hr.jtext(p, 'title_en')), nullif(btrim(coalesce(hr.jtext(p, 'title_ar'), '')), ''),
            nullif(btrim(coalesce(hr.jtext(p, 'intro_en'), '')), ''), nullif(btrim(coalesce(hr.jtext(p, 'intro_ar'), '')), ''),
            hr.jbool(p, 'anonymous', true), v_q, v_from, v_to, auth.uid())
    returning * into s;
  else
    select * into s from hr.surveys where id = v_id for update;
    if s.id is null then raise exception 'NOT_FOUND: Survey not found.'; end if;
    if s.status not in ('DRAFT','REJECTED') then raise exception 'INVALID: Only a draft or a rejected survey can be changed.'; end if;
    update hr.surveys set entity_id = v_ent, department_id = v_dep, title_en = btrim(hr.jtext(p, 'title_en')),
           title_ar = nullif(btrim(coalesce(hr.jtext(p, 'title_ar'), '')), ''),
           intro_en = nullif(btrim(coalesce(hr.jtext(p, 'intro_en'), '')), ''), intro_ar = nullif(btrim(coalesce(hr.jtext(p, 'intro_ar'), '')), ''),
           anonymous = hr.jbool(p, 'anonymous', true), questions = v_q, opens_on = v_from, closes_on = v_to,
           status = 'DRAFT', decided_by = null, decided_at = null, decision_note = null
     where id = v_id returning * into s;
  end if;
  return hr.survey_json(s);
end $$;

create or replace function public.hr_submit_survey(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.surveys;
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  select * into s from hr.surveys where id = p_id for update;
  if s.id is null then raise exception 'NOT_FOUND: Survey not found.'; end if;
  if s.status not in ('DRAFT','REJECTED') then raise exception 'INVALID: Only a draft can be sent for approval.'; end if;
  if s.opens_on < hr.today() then raise exception 'INVALID: The opening date is in the past; change it first.'; end if;
  update hr.surveys set status = 'PENDING', submitted_at = now() where id = p_id returning * into s;
  perform hr.engage_notify_approvers(auth.uid(), 'Survey to approve: ' || s.title_en, 'استبيان بانتظار الاعتماد: ' || coalesce(s.title_ar, s.title_en),
    '/engage/admin?tab=surveys', 'survey-approve:' || s.id::text || ':' || extract(epoch from s.submitted_at)::bigint::text);
  return hr.survey_json(s);
end $$;

create or replace function public.hr_decide_survey(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.surveys;
begin
  perform hr.require_perm('ENGAGE_APPROVE');
  select * into s from hr.surveys where id = p_id for update;
  if s.id is null then raise exception 'NOT_FOUND: Survey not found.'; end if;
  if s.status <> 'PENDING' then raise exception 'NOT_PENDING: This survey is not waiting for approval.'; end if;
  if s.created_by = auth.uid() then raise exception 'SELF_APPROVAL: You cannot approve your own survey.' using errcode = '42501'; end if;
  if not coalesce(p_approve, false) and coalesce(length(btrim(p_note)), 0) < 3 then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  update hr.surveys set status = case when p_approve then 'OPEN' else 'REJECTED' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id returning * into s;
  perform hr.notify(s.created_by, 'ENGAGEMENT', 'NORMAL',
    case when p_approve then 'Survey approved: ' else 'Survey rejected: ' end || s.title_en,
    case when p_approve then 'تم اعتماد الاستبيان: ' else 'تم رفض الاستبيان: ' end || coalesce(s.title_ar, s.title_en),
    s.decision_note, s.decision_note, '/engage/admin?tab=surveys', 'survey-decided:' || s.id::text || ':' || extract(epoch from s.decided_at)::bigint::text);
  if p_approve then perform hr.engage_notify_survey(s.id); end if;
  select * into s from hr.surveys where id = p_id;
  return hr.survey_json(s);
end $$;

create or replace function public.hr_close_survey(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.surveys;
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  update hr.surveys set status = 'CLOSED', closed_by = auth.uid(), closed_at = now() where id = p_id and status = 'OPEN' returning * into s;
  if s.id is null then raise exception 'INVALID: Only an open survey can be closed.'; end if;
  return hr.survey_json(s);
end $$;

-- p_answers: {"q1": 4, "q2": 1, "q3": "text"} — rating 1–5, choice = option number from 0, text up to 1,000 characters.
create or replace function public.hr_answer_survey(p_id uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.surveys; q jsonb; v jsonb; v_resp uuid := gen_random_uuid(); v_emp uuid; v_n int := 0; v_int int; v_txt text;
begin
  perform hr.require_user();
  select * into s from hr.surveys where id = p_id for share;
  if s.id is null or not hr.engage_in_audience(s.entity_id, s.department_id) or s.status not in ('OPEN','CLOSED') then
    raise exception 'NOT_FOUND: Survey not found.';
  end if;
  if not hr.survey_live(s) then raise exception 'INVALID: This survey is not open.'; end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'INVALID: Answers are not valid.'; end if;
  begin
    insert into hr.survey_participants(survey_id, user_id, responded_on) values (s.id, auth.uid(), hr.today());
  exception when unique_violation then
    raise exception 'DUPLICATE: You have already answered this survey.';
  end;
  select m.employee_id into v_emp from hr.engage_me() m;
  for q in select x from jsonb_array_elements(s.questions) x loop
    v := p_answers -> (q->>'key');
    if v is null or v = 'null'::jsonb or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then
      if coalesce((q->>'required')::boolean, true) then raise exception 'REQUIRED: Please answer: %', q->>'text_en'; end if;
      continue;
    end if;
    v_int := null; v_txt := null;
    if q->>'kind' = 'TEXT' then
      v_txt := btrim(v #>> '{}');
      if length(v_txt) > 1000 then raise exception 'INVALID: An answer is too long (1,000 characters at most).'; end if;
    else
      if jsonb_typeof(v) <> 'number' or (v #>> '{}') !~ '^\d+$' then raise exception 'INVALID: Answer for "%" is not valid.', q->>'text_en'; end if;
      v_int := (v #>> '{}')::int;
      if q->>'kind' = 'RATING' and v_int not between 1 and 5 then raise exception 'INVALID: Ratings go from 1 to 5.'; end if;
      if q->>'kind' = 'CHOICE' and v_int >= jsonb_array_length(q->'options') then raise exception 'INVALID: Answer for "%" is not valid.', q->>'text_en'; end if;
    end if;
    insert into hr.survey_answers(survey_id, response_id, question_key, rating, choice, text_value, employee_id)
    values (s.id, v_resp, q->>'key', case when q->>'kind' = 'RATING' then v_int end, case when q->>'kind' = 'CHOICE' then v_int end,
            v_txt, case when s.anonymous then null else v_emp end);
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'REQUIRED: Answer at least one question.'; end if;
  return jsonb_build_object('ok', true, 'answered', v_n);
end $$;

create or replace function public.hr_survey_results(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.surveys; v_n int; v_min int := hr.engage_setting('survey_min_responses', 5)::int; v_hidden boolean; v_q jsonb := '[]'::jsonb; q jsonb;
begin
  perform hr.require_user();
  if not hr.engage_staff() then raise exception 'NOT_ALLOWED: You do not have the ENGAGE_MANAGE permission.' using errcode = '42501'; end if;
  select * into s from hr.surveys where id = p_id;
  if s.id is null then raise exception 'NOT_FOUND: Survey not found.'; end if;
  select count(*) into v_n from hr.survey_participants where survey_id = s.id;
  v_hidden := s.anonymous and v_n < v_min;
  if not v_hidden then
    for q in select x from jsonb_array_elements(s.questions) x loop
      v_q := v_q || jsonb_build_array(q || (
        select jsonb_build_object(
          'answered', count(*),
          'average', case when q->>'kind' = 'RATING' then round(avg(a.rating), 2) end,
          'ratings', case when q->>'kind' = 'RATING' then
             (select jsonb_agg((select count(*) from hr.survey_answers b where b.survey_id = s.id and b.question_key = q->>'key' and b.rating = g) order by g)
                from generate_series(1, 5) g) end,
          'choices', case when q->>'kind' = 'CHOICE' then
             (select jsonb_agg((select count(*) from hr.survey_answers b where b.survey_id = s.id and b.question_key = q->>'key' and b.choice = g - 1) order by g)
                from generate_series(1, jsonb_array_length(q->'options')) g) end,
          'texts', case when q->>'kind' = 'TEXT' then
             (select coalesce(jsonb_agg(case when s.anonymous then to_jsonb(b.text_value)
                                             else jsonb_build_object('text', b.text_value, 'employee', (select e.full_name_en from hr.employees e where e.id = b.employee_id)) end
                                        order by b.text_value), '[]'::jsonb)
                from hr.survey_answers b where b.survey_id = s.id and b.question_key = q->>'key' and b.text_value is not null) end)
        from hr.survey_answers a where a.survey_id = s.id and a.question_key = q->>'key'));
    end loop;
  end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'REPORT', 'SURVEY_RESULTS ' || s.id::text);
  return jsonb_build_object('survey', hr.survey_json(s), 'responses', v_n,
    'audience', (select count(*) from hr.engage_audience(s.entity_id, s.department_id)),
    'min_responses', v_min, 'hidden', v_hidden, 'questions', v_q);
end $$;

-- ---------------------------------------------------------------------------
-- Recognition
-- ---------------------------------------------------------------------------
create or replace function hr.recog_json(r hr.recognitions)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', r.id, 'kind', r.kind, 'category', r.category, 'award_title', r.award_title, 'message', r.message,
    'status', r.status, 'created_at', r.created_at, 'posted_at', coalesce(r.decided_at, r.created_at), 'entity_id', r.entity_id,
    'employee', hr.emp_brief(r.employee_id),
    'giver', case when r.giver_employee_id is not null then hr.emp_brief(r.giver_employee_id) end,
    'giver_name', coalesce((select e.full_name_en from hr.employees e where e.id = r.giver_employee_id), hr.user_label(r.created_by)),
    'giver_name_ar', (select e.full_name_ar from hr.employees e where e.id = r.giver_employee_id),
    'decided_by_name', hr.user_label(r.decided_by), 'decision_note', r.decision_note,
    'hidden_reason', case when hr.engage_staff() then r.hidden_reason end,
    'applause', (select count(*) from hr.recognition_applause x where x.recognition_id = r.id),
    'applauded', exists (select 1 from hr.recognition_applause x where x.recognition_id = r.id and x.user_id = auth.uid()),
    'is_mine', r.employee_id = (select m.employee_id from hr.engage_me() m),
    'can_decide', r.status = 'PENDING' and hr.has_perm('ENGAGE_APPROVE') and r.created_by is distinct from auth.uid(),
    'can_hide', r.status = 'APPROVED' and hr.has_perm('ENGAGE_MANAGE'))
$$;

-- recognition the caller may see on the wall: own company (staff: every company)
create or replace function hr.recog_visible(r hr.recognitions)
returns boolean language sql stable security definer set search_path = '' as $$
  select r.status = 'APPROVED' and (hr.engage_staff() or exists (select 1 from hr.engage_me() m where m.entity_id = r.entity_id))
$$;

create or replace function hr.recog_notify(r hr.recognitions)
returns void language plpgsql security definer set search_path = '' as $$
declare v_t_en text; v_t_ar text; v_mgr uuid;
begin
  if r.kind = 'AWARD' then
    v_t_en := 'You received an award: ' || r.award_title; v_t_ar := 'حصلت على تكريم: ' || r.award_title;
  else
    v_t_en := 'You were recognised by ' || coalesce((select e.full_name_en from hr.employees e where e.id = r.giver_employee_id), 'a colleague');
    v_t_ar := 'حصلت على تقدير من ' || coalesce((select coalesce(e.full_name_ar, e.full_name_en) from hr.employees e where e.id = r.giver_employee_id), 'زميل');
  end if;
  perform hr.notify(hr.employee_user(r.employee_id), 'RECOGNITION', 'NORMAL', v_t_en, v_t_ar, left(r.message, 200), left(r.message, 200),
    '/engage?tab=recognition', 'recog:' || r.id::text);
  v_mgr := hr.manager_user_of(r.employee_id);
  if v_mgr is not null and v_mgr is distinct from r.created_by then
    perform hr.notify(v_mgr, 'RECOGNITION', 'NORMAL',
      'Your team member ' || (select e.full_name_en from hr.employees e where e.id = r.employee_id) || ' was recognised',
      'تم تقدير أحد أعضاء فريقك: ' || (select coalesce(e.full_name_ar, e.full_name_en) from hr.employees e where e.id = r.employee_id),
      left(r.message, 200), left(r.message, 200), '/engage?tab=recognition', 'recog-mgr:' || r.id::text);
  end if;
end $$;

-- Colleagues the caller may recognise: active employees of the caller's company (staff: any company).
create or replace function public.hr_engage_colleagues(p_q text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me record; v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  perform hr.require_user();
  select * into v_me from hr.engage_me();
  if v_me.employee_id is null and not hr.engage_staff() then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(hr.emp_brief(x.id) order by x.full_name_en) from (
      select e.id, e.full_name_en from hr.employees e
      where e.status <> 'SEPARATED' and e.id is distinct from v_me.employee_id
        and (hr.engage_staff() or e.entity_id = v_me.entity_id)
        and (v_q is null or e.full_name_en ilike '%' || v_q || '%' or coalesce(e.full_name_ar, '') ilike '%' || v_q || '%' or e.employee_no ilike '%' || v_q || '%')
      order by e.full_name_en limit 20) x), '[]'::jsonb);
end $$;

create or replace function public.hr_give_recognition(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_me record; v_emp hr.employees; r hr.recognitions; v_cat text := upper(coalesce(hr.jtext(p, 'category'), 'TEAMWORK'));
        v_msg text := btrim(coalesce(hr.jtext(p, 'message'), '')); v_limit int := hr.engage_setting('peer_daily_limit', 5)::int;
begin
  perform hr.require_user();
  select * into v_me from hr.engage_me();
  if v_me.employee_id is null then raise exception 'NOT_LINKED: Only employees can recognise colleagues.'; end if;
  select * into v_emp from hr.employees where id = hr.juuid(p, 'employee_id');
  if v_emp.id is null or v_emp.status = 'SEPARATED' then raise exception 'NOT_FOUND: Colleague not found.'; end if;
  if v_emp.id = v_me.employee_id then raise exception 'INVALID: You cannot recognise yourself.'; end if;
  if v_emp.entity_id <> v_me.entity_id then raise exception 'INVALID: You can recognise colleagues in your own company.'; end if;
  if v_cat not in ('TEAMWORK','SAFETY','QUALITY','CUSTOMER','INNOVATION','EXTRA_MILE','LEADERSHIP') then raise exception 'INVALID: Unknown category.'; end if;
  if length(v_msg) < 3 then raise exception 'REQUIRED: Write a short message (at least 3 characters).'; end if;
  if length(v_msg) > 500 then raise exception 'INVALID: The message is too long (500 characters at most).'; end if;
  if (select count(*) from hr.recognitions x where x.created_by = auth.uid() and x.kind = 'PEER' and x.created_at >= now() - interval '1 day') >= v_limit then
    raise exception 'INVALID: You can recognise up to % colleagues a day.', v_limit;
  end if;
  insert into hr.recognitions(kind, entity_id, employee_id, giver_employee_id, category, message, status, created_by)
  values ('PEER', v_emp.entity_id, v_emp.id, v_me.employee_id, v_cat, v_msg, 'APPROVED', auth.uid())
  returning * into r;
  perform hr.recog_notify(r);
  return hr.recog_json(r);
end $$;

create or replace function public.hr_propose_award(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_emp hr.employees; r hr.recognitions; v_cat text := upper(coalesce(hr.jtext(p, 'category'), 'EXTRA_MILE'));
        v_title text := btrim(coalesce(hr.jtext(p, 'award_title'), '')); v_msg text := btrim(coalesce(hr.jtext(p, 'message'), ''));
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  select * into v_emp from hr.employees where id = hr.juuid(p, 'employee_id');
  if v_emp.id is null or v_emp.status = 'SEPARATED' then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if hr.is_me(v_emp.id) then raise exception 'NOT_ALLOWED: You cannot propose an award for yourself.' using errcode = '42501'; end if;
  if v_cat not in ('TEAMWORK','SAFETY','QUALITY','CUSTOMER','INNOVATION','EXTRA_MILE','LEADERSHIP') then raise exception 'INVALID: Unknown category.'; end if;
  if length(v_title) < 3 then raise exception 'REQUIRED: Enter the award name (e.g. Employee of the month).'; end if;
  if length(v_title) > 100 then raise exception 'INVALID: The award name is too long (100 characters at most).'; end if;
  if length(v_msg) < 3 then raise exception 'REQUIRED: Write the citation.'; end if;
  if length(v_msg) > 500 then raise exception 'INVALID: The citation is too long (500 characters at most).'; end if;
  insert into hr.recognitions(kind, entity_id, employee_id, category, award_title, message, status, created_by)
  values ('AWARD', v_emp.entity_id, v_emp.id, v_cat, v_title, v_msg, 'PENDING', auth.uid())
  returning * into r;
  perform hr.engage_notify_approvers(auth.uid(), 'Award to approve: ' || v_title || ' — ' || v_emp.full_name_en,
    'تكريم بانتظار الاعتماد: ' || v_title || ' — ' || coalesce(v_emp.full_name_ar, v_emp.full_name_en), '/engage/admin?tab=awards', 'award-approve:' || r.id::text);
  return hr.recog_json(r);
end $$;

create or replace function public.hr_decide_award(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.recognitions;
begin
  perform hr.require_perm('ENGAGE_APPROVE');
  select * into r from hr.recognitions where id = p_id and kind = 'AWARD' for update;
  if r.id is null then raise exception 'NOT_FOUND: Award not found.'; end if;
  if r.status <> 'PENDING' then raise exception 'NOT_PENDING: This award is not waiting for approval.'; end if;
  if r.created_by = auth.uid() then raise exception 'SELF_APPROVAL: You cannot approve an award you proposed.' using errcode = '42501'; end if;
  if hr.is_me(r.employee_id) then raise exception 'SELF_APPROVAL: You cannot approve your own award.' using errcode = '42501'; end if;
  if not coalesce(p_approve, false) and coalesce(length(btrim(p_note)), 0) < 3 then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  update hr.recognitions set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id returning * into r;
  if p_approve then perform hr.recog_notify(r); end if;
  perform hr.notify(r.created_by, 'ENGAGEMENT', 'NORMAL', case when p_approve then 'Award approved: ' else 'Award rejected: ' end || r.award_title,
    case when p_approve then 'تم اعتماد التكريم: ' else 'تم رفض التكريم: ' end || r.award_title, r.decision_note, r.decision_note,
    '/engage/admin?tab=awards', 'award-decided:' || r.id::text);
  return hr.recog_json(r);
end $$;

create or replace function public.hr_hide_recognition(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.recognitions;
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'REQUIRED: Give a reason for hiding it.'; end if;
  update hr.recognitions set status = 'HIDDEN', hidden_by = auth.uid(), hidden_at = now(), hidden_reason = btrim(p_reason)
   where id = p_id and status = 'APPROVED' returning * into r;
  if r.id is null then raise exception 'NOT_FOUND: Recognition not found.'; end if;
  return hr.recog_json(r);
end $$;

create or replace function public.hr_applaud_recognition(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.recognitions;
begin
  perform hr.require_user();
  select * into r from hr.recognitions where id = p_id;
  if r.id is null or not hr.recog_visible(r) then raise exception 'NOT_FOUND: Recognition not found.'; end if;
  insert into hr.recognition_applause(recognition_id, user_id) values (r.id, auth.uid()) on conflict do nothing;
  return hr.recog_json(r);
end $$;

-- p: {"scope": "wall" | "mine" | "pending" | "all", "limit": 50}
create or replace function public.hr_list_recognitions(p jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_scope text := lower(coalesce(hr.jtext(p, 'scope'), 'wall')); v_lim int := least(greatest(coalesce(hr.jint(p, 'limit'), 50), 1), 200);
        v_me record;
begin
  perform hr.require_user();
  select * into v_me from hr.engage_me();
  if v_scope in ('pending','all') and not hr.engage_staff() then
    raise exception 'NOT_ALLOWED: You do not have the ENGAGE_MANAGE permission.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(hr.recog_json(x) order by coalesce(x.decided_at, x.created_at) desc) from (
      select r.* from hr.recognitions r
      where case v_scope
              when 'mine' then r.status = 'APPROVED' and r.employee_id = v_me.employee_id
              when 'pending' then r.status = 'PENDING'
              when 'all' then r.kind = 'AWARD' or r.status = 'HIDDEN'
              else hr.recog_visible(r) end
      order by coalesce(r.decided_at, r.created_at) desc limit v_lim) x), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- Home: everything the caller sees on the engagement page in one call
-- ---------------------------------------------------------------------------
create or replace function public.hr_engage_home()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me record; v_from timestamptz := date_trunc('month', now() at time zone 'Asia/Muscat') at time zone 'Asia/Muscat';
begin
  perform hr.require_user();
  select * into v_me from hr.engage_me();
  return jsonb_build_object(
    'caps', jsonb_build_object('manage', hr.has_perm('ENGAGE_MANAGE'), 'approve', hr.has_perm('ENGAGE_APPROVE'),
                               'recognise', v_me.employee_id is not null, 'employee_id', v_me.employee_id),
    'announcements', coalesce((select jsonb_agg(hr.ann_json(a) order by a.pinned desc, a.publish_on desc, a.created_at desc) from (
        select a.* from hr.announcements a where hr.ann_live(a) and hr.engage_in_audience(a.entity_id, a.department_id)
        order by a.pinned desc, a.publish_on desc limit 50) a), '[]'::jsonb),
    'unread', (select count(*) from hr.announcements a where hr.ann_live(a) and hr.engage_in_audience(a.entity_id, a.department_id)
               and not exists (select 1 from hr.announcement_reads r where r.announcement_id = a.id and r.user_id = auth.uid())),
    'to_confirm', (select count(*) from hr.announcements a where hr.ann_live(a) and a.require_ack and hr.engage_in_audience(a.entity_id, a.department_id)
               and not exists (select 1 from hr.announcement_reads r where r.announcement_id = a.id and r.user_id = auth.uid() and r.acknowledged_at is not null)),
    'surveys', coalesce((select jsonb_agg(hr.survey_json(s) order by s.closes_on) from hr.surveys s
        where hr.survey_live(s) and hr.engage_in_audience(s.entity_id, s.department_id)), '[]'::jsonb),
    'recognitions', coalesce((select jsonb_agg(hr.recog_json(x) order by coalesce(x.decided_at, x.created_at) desc) from (
        select r.* from hr.recognitions r where hr.recog_visible(r) order by coalesce(r.decided_at, r.created_at) desc limit 30) x), '[]'::jsonb),
    'top_month', coalesce((select jsonb_agg(hr.emp_brief(t.employee_id) || jsonb_build_object('count', t.n) order by t.n desc, t.employee_id) from (
        select r.employee_id, count(*)::int n from hr.recognitions r where hr.recog_visible(r) and coalesce(r.decided_at, r.created_at) >= v_from
        group by r.employee_id order by count(*) desc, r.employee_id limit 5) t), '[]'::jsonb),
    'my_count', (select count(*) from hr.recognitions r where r.status = 'APPROVED' and r.employee_id = v_me.employee_id));
end $$;

-- Small counts for the menu badge.
create or replace function public.hr_engage_counts()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return jsonb_build_object(
    'unread', (select count(*) from hr.announcements a where hr.ann_live(a) and hr.engage_in_audience(a.entity_id, a.department_id)
               and not exists (select 1 from hr.announcement_reads r where r.announcement_id = a.id and r.user_id = auth.uid())),
    'surveys', (select count(*) from hr.surveys s where hr.survey_live(s) and hr.engage_in_audience(s.entity_id, s.department_id)
               and not exists (select 1 from hr.survey_participants sp where sp.survey_id = s.id and sp.user_id = auth.uid())),
    'to_approve', case when hr.has_perm('ENGAGE_APPROVE') then
        (select count(*) from hr.announcements a where a.status = 'PENDING' and a.created_by is distinct from auth.uid())
      + (select count(*) from hr.surveys s where s.status = 'PENDING' and s.created_by is distinct from auth.uid())
      + (select count(*) from hr.recognitions r where r.status = 'PENDING' and r.created_by is distinct from auth.uid()) else 0 end);
end $$;

-- ---------------------------------------------------------------------------
-- Daily job: tell people about announcements and surveys that start today; close surveys past their date.
-- ---------------------------------------------------------------------------
create or replace function hr.engage_daily(p_on date default null)
returns int language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in select a.id from hr.announcements a where a.status = 'PUBLISHED' and a.notified_on is null loop
    n := n + hr.engage_notify_announcement(r.id);
  end loop;
  for r in select s.id from hr.surveys s where s.status = 'OPEN' and s.notified_on is null loop
    n := n + hr.engage_notify_survey(r.id);
  end loop;
  update hr.surveys set status = 'CLOSED', closed_at = now() where status = 'OPEN' and closes_on < coalesce(p_on, hr.today());
  return n;
end $$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('hr-engagement-daily', '5 2 * * *', 'select hr.engage_daily()');
  end if;
end $$;

select hr.attach_audit();
select hr.secure_api();
