-- =============================================================================
-- 1.15.0 — Announcements: signed PDF attachment and English <-> Arabic translation.
--  * A signed PDF (e.g. the circular signed by management) can be attached to an announcement. Files live in the private
--    bucket hr-engage (path ann/<uuid>.pdf); HR may upload, readers may open it only while the announcement is live for them.
--    Files are never overwritten or removed by the app; replacing the PDF stores a new file.
--  * Translation runs in the `translate` edge function. Before calling the translation service it records the request
--    here (who, when, direction, length — not the text) and gets the company glossary. A daily limit per person applies.
-- Idempotent; no destructive statements.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Attachment columns
-- ---------------------------------------------------------------------------
alter table hr.announcements add column if not exists attachment_path text;
alter table hr.announcements add column if not exists attachment_name text;
alter table hr.announcements add column if not exists attachment_bytes integer;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'announcements_attachment_path_chk') then
    alter table hr.announcements add constraint announcements_attachment_path_chk
      check (attachment_path is null or attachment_path ~ '^ann/[0-9a-f-]{36}\.pdf$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'announcements_attachment_bytes_chk') then
    alter table hr.announcements add constraint announcements_attachment_bytes_chk
      check (attachment_bytes is null or attachment_bytes between 1 and 10485760);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- File storage: private bucket for announcement PDFs
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hr-engage', 'hr-engage', false, 10485760, array['application/pdf'])
on conflict (id) do nothing;

create or replace function public.hr_engage_storage_can_write(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or p_name is null or p_name !~ '^ann/[0-9a-f-]{36}\.pdf$' then return false; end if;
  if not exists (select 1 from hr.user_profiles where user_id = auth.uid() and is_active) then return false; end if;
  return hr.has_perm('ENGAGE_MANAGE');
end $$;

create or replace function public.hr_engage_storage_can_read(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or p_name is null or p_name !~ '^ann/[0-9a-f-]{36}\.pdf$' then return false; end if;
  if not exists (select 1 from hr.user_profiles where user_id = auth.uid() and is_active) then return false; end if;
  if hr.engage_staff() then return true; end if;
  return exists (select 1 from hr.announcements a
                 where a.attachment_path = p_name and hr.ann_live(a) and hr.engage_in_audience(a.entity_id, a.department_id));
end $$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                 and policyname = 'hr_engage_read') then
    create policy hr_engage_read on storage.objects for select to authenticated
      using (bucket_id = 'hr-engage' and public.hr_engage_storage_can_read(name));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                 and policyname = 'hr_engage_insert') then
    create policy hr_engage_insert on storage.objects for insert to authenticated
      with check (bucket_id = 'hr-engage' and public.hr_engage_storage_can_write(name));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Save an announcement (1.14.0 + attachment)
-- ---------------------------------------------------------------------------
create or replace function public.hr_save_announcement(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.announcements; v_id uuid := hr.juuid(p, 'id'); v_ent uuid := hr.juuid(p, 'entity_id'); v_dep uuid := hr.juuid(p, 'department_id');
        v_cat text := upper(coalesce(hr.jtext(p, 'category'), 'GENERAL')); v_from date := coalesce(hr.jdate(p, 'publish_on'), hr.today());
        v_to date := hr.jdate(p, 'expires_on');
        v_path text := nullif(btrim(coalesce(hr.jtext(p, 'attachment_path'), '')), '');
        v_fname text := left(nullif(btrim(coalesce(hr.jtext(p, 'attachment_name'), '')), ''), 200);
        v_bytes integer;
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
  if v_path is not null then
    if v_path !~ '^ann/[0-9a-f-]{36}\.pdf$' then raise exception 'INVALID: The attachment was not uploaded as an announcement PDF.'; end if;
    begin
      v_bytes := nullif(hr.jtext(p, 'attachment_bytes'), '')::integer;
    exception when others then
      raise exception 'INVALID: The attachment size is not valid.';
    end;
    if v_bytes is not null and (v_bytes < 1 or v_bytes > 10485760) then raise exception 'INVALID: The PDF is larger than 10 MB.'; end if;
    v_fname := coalesce(v_fname, 'announcement.pdf');
  else
    v_fname := null;
  end if;
  if v_id is null then
    if v_from < hr.today() then raise exception 'INVALID: The publish date cannot be in the past.'; end if;
    insert into hr.announcements(entity_id, department_id, category, title_en, title_ar, body_en, body_ar, pinned, require_ack, publish_on, expires_on,
                                 attachment_path, attachment_name, attachment_bytes, created_by)
    values (v_ent, v_dep, v_cat, btrim(hr.jtext(p, 'title_en')), nullif(btrim(coalesce(hr.jtext(p, 'title_ar'), '')), ''),
            btrim(hr.jtext(p, 'body_en')), nullif(btrim(coalesce(hr.jtext(p, 'body_ar'), '')), ''),
            hr.jbool(p, 'pinned'), hr.jbool(p, 'require_ack'), v_from, v_to, v_path, v_fname, v_bytes, auth.uid())
    returning * into a;
  else
    select * into a from hr.announcements where id = v_id for update;
    if a.id is null then raise exception 'NOT_FOUND: Announcement not found.'; end if;
    if a.status not in ('DRAFT','REJECTED') then raise exception 'INVALID: Only a draft or a rejected announcement can be changed.'; end if;
    if v_from < hr.today() then raise exception 'INVALID: The publish date cannot be in the past.'; end if;
    -- keep the stored size when the same file is sent back without one
    if v_path is not null and v_path = a.attachment_path and v_bytes is null then v_bytes := a.attachment_bytes; end if;
    update hr.announcements set entity_id = v_ent, department_id = v_dep, category = v_cat,
           title_en = btrim(hr.jtext(p, 'title_en')), title_ar = nullif(btrim(coalesce(hr.jtext(p, 'title_ar'), '')), ''),
           body_en = btrim(hr.jtext(p, 'body_en')), body_ar = nullif(btrim(coalesce(hr.jtext(p, 'body_ar'), '')), ''),
           pinned = hr.jbool(p, 'pinned'), require_ack = hr.jbool(p, 'require_ack'), publish_on = v_from, expires_on = v_to,
           attachment_path = v_path, attachment_name = v_fname, attachment_bytes = v_bytes,
           status = 'DRAFT', decided_by = null, decided_at = null, decision_note = null
     where id = v_id returning * into a;
  end if;
  return hr.ann_json(a);
end $$;

-- ---------------------------------------------------------------------------
-- Translation requests (log + daily limit + glossary)
-- ---------------------------------------------------------------------------
create table if not exists hr.translation_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references hr.user_profiles(user_id),
  created_at  timestamptz not null default now(),
  direction   text not null check (direction in ('en-ar','ar-en')),
  chars       integer not null check (chars between 1 and 6000)
);
create index if not exists translation_log_user_idx on hr.translation_log(user_id, created_at desc);

insert into hr.settings(key, value) values ('translation_glossary', '[]')
on conflict (key) do nothing;

-- Called by the translate edge function with the person's own sign-in. Returns the extra company glossary.
create or replace function public.hr_translate_begin(p_direction text, p_chars integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_limit numeric := hr.engage_setting('translate_daily_limit', 100); v_used int; v_gl jsonb;
begin
  perform hr.require_perm('ENGAGE_MANAGE');
  if p_direction is null or p_direction not in ('en-ar','ar-en') then raise exception 'INVALID: Unknown translation direction.'; end if;
  if p_chars is null or p_chars < 1 then raise exception 'REQUIRED: There is nothing to translate.'; end if;
  if p_chars > 6000 then raise exception 'INVALID: The text is too long to translate at once (6,000 characters at most).'; end if;
  select count(*) into v_used from hr.translation_log
   where user_id = auth.uid() and created_at >= (hr.today()::timestamp at time zone 'Asia/Muscat');
  if v_used >= v_limit then
    raise exception 'LIMIT: You have reached today''s translation limit (%). Try again tomorrow.', v_limit::int;
  end if;
  insert into hr.translation_log(user_id, direction, chars) values (auth.uid(), p_direction, p_chars);
  select value into v_gl from hr.settings where key = 'translation_glossary';
  if v_gl is null or jsonb_typeof(v_gl) <> 'array' then v_gl := '[]'::jsonb; end if;
  return jsonb_build_object('ok', true, 'used', v_used + 1, 'limit', v_limit::int,
    'glossary', coalesce((select jsonb_agg(jsonb_build_object('en', g->>'en', 'ar', g->>'ar'))
                          from jsonb_array_elements(v_gl) g
                          where jsonb_typeof(g) = 'object' and coalesce(g->>'en', '') <> '' and coalesce(g->>'ar', '') <> ''), '[]'::jsonb));
end $$;

select hr.attach_audit();
select hr.secure_api();
