-- AACT HRMS — 1.15.0 announcements: signed PDF attachment, translation log and daily limit.
set client_min_messages = warning;
reset role;

do $$
declare v jsonb; v_ann uuid; v_ent uuid := tst.id('ent');
        v_path text := 'ann/' || gen_random_uuid()::text || '.pdf';
        v_path2 text := 'ann/' || gen_random_uuid()::text || '.pdf';
begin
  update hr.employees set status = 'ACTIVE', separation_date = null where id in (tst.id('emp_mgr'), tst.id('emp_w')) and status = 'SEPARATED';

  -- ------------------------------------------------------------------ storage policies
  perform tst.check(exists (select 1 from storage.buckets where id = 'hr-engage' and not public and allowed_mime_types = array['application/pdf']), 'private PDF bucket');
  set role authenticated;
  perform tst.as_user('emp');
  perform tst.expect_error(format('insert into storage.objects(bucket_id, name) values (''hr-engage'', %L)', v_path), 'row-level security');
  perform tst.as_user('hro');
  perform tst.expect_error('insert into storage.objects(bucket_id, name) values (''hr-engage'', ''ann/not-a-uuid.pdf'')', 'row-level security');
  perform tst.expect_error(format('insert into storage.objects(bucket_id, name) values (''hr-engage'', %L)', replace(v_path, '.pdf', '.exe')), 'row-level security');
  insert into storage.objects(bucket_id, name) values ('hr-engage', v_path), ('hr-engage', v_path2);
  reset role;

  -- ------------------------------------------------------------------ save with an attachment
  perform tst.expect_error(format($q$select public.hr_save_announcement('{"title_en":"Circular","body_en":"See the PDF","attachment_path":"%s"}'::jsonb)$q$,
            tst.id('emp_w') || '/PASSPORT/x.pdf'), 'announcement PDF');
  perform tst.expect_error(format($q$select public.hr_save_announcement('{"title_en":"Circular","body_en":"See the PDF","attachment_path":"%s","attachment_bytes":"abc"}'::jsonb)$q$,
            v_path), 'size is not valid');
  perform tst.expect_error(format($q$select public.hr_save_announcement('{"title_en":"Circular","body_en":"See the PDF","attachment_path":"%s","attachment_bytes":20000000}'::jsonb)$q$,
            v_path), '10 MB');
  v := public.hr_save_announcement(jsonb_build_object('entity_id', v_ent, 'category', 'HR_POLICY', 'title_en', 'Signed circular: working hours in Ramadan',
         'title_ar', 'تعميم موقّع: ساعات العمل في شهر رمضان', 'body_en', 'Please read the signed circular attached.',
         'attachment_path', v_path, 'attachment_name', 'Circular 12-2026.pdf', 'attachment_bytes', 245000));
  v_ann := (v->>'id')::uuid;
  perform tst.check(v->>'attachment_path' = v_path and v->>'attachment_name' = 'Circular 12-2026.pdf' and (v->>'attachment_bytes')::int = 245000, 'attachment saved');

  -- editing with the same file and no size keeps the size; a name is given when none is sent
  v := public.hr_save_announcement(jsonb_build_object('id', v_ann, 'entity_id', v_ent, 'category', 'HR_POLICY', 'title_en', 'Signed circular: working hours in Ramadan',
         'body_en', 'Please read the signed circular attached.', 'attachment_path', v_path));
  perform tst.check((v->>'attachment_bytes')::int = 245000 and v->>'attachment_name' = 'announcement.pdf', 'same file keeps its size');
  -- replace, then remove, then attach again
  v := public.hr_save_announcement(jsonb_build_object('id', v_ann, 'entity_id', v_ent, 'title_en', 'Signed circular: working hours in Ramadan',
         'body_en', 'Please read the signed circular attached.', 'attachment_path', v_path2, 'attachment_name', 'v2.pdf', 'attachment_bytes', 1000));
  perform tst.check(v->>'attachment_path' = v_path2 and (v->>'attachment_bytes')::int = 1000, 'attachment replaced');
  v := public.hr_save_announcement(jsonb_build_object('id', v_ann, 'entity_id', v_ent, 'title_en', 'Signed circular: working hours in Ramadan',
         'body_en', 'Please read the signed circular attached.', 'attachment_path', null));
  perform tst.check(v->'attachment_path' = 'null'::jsonb and v->'attachment_name' = 'null'::jsonb and v->'attachment_bytes' = 'null'::jsonb, 'attachment removed');
  v := public.hr_save_announcement(jsonb_build_object('id', v_ann, 'entity_id', v_ent, 'category', 'HR_POLICY', 'title_en', 'Signed circular: working hours in Ramadan',
         'title_ar', 'تعميم موقّع: ساعات العمل في شهر رمضان', 'body_en', 'Please read the signed circular attached.',
         'attachment_path', v_path, 'attachment_name', 'Circular 12-2026.pdf', 'attachment_bytes', 245000));

  -- ------------------------------------------------------------------ who may open the file
  perform tst.check(public.hr_engage_storage_can_read(v_path), 'HR can open the draft PDF');
  perform tst.as_user('emp');
  perform tst.check(not public.hr_engage_storage_can_read(v_path), 'employee cannot open a draft PDF');
  perform tst.check(not public.hr_engage_storage_can_read(v_path2), 'employee cannot open an unlinked PDF');
  perform tst.as_user('hro');
  perform public.hr_submit_announcement(v_ann);
  perform tst.as_user('hrm');
  v := public.hr_decide_announcement(v_ann, true, null);
  perform tst.check(v->>'status' = 'PUBLISHED' and v->>'attachment_path' = v_path, 'published with the PDF');
  perform tst.as_user('emp');
  perform tst.check(public.hr_engage_storage_can_read(v_path), 'employee in the audience can open the live PDF');
  perform tst.check(not public.hr_engage_storage_can_read(v_path2), 'still not an unlinked PDF');
  perform tst.check(not public.hr_engage_storage_can_read('../' || v_path), 'odd paths refused');
  v := public.hr_get_announcement(v_ann);
  perform tst.check(v->>'attachment_name' = 'Circular 12-2026.pdf', 'reader sees the attachment');
  -- archived: the employee can no longer open it
  perform tst.as_user('hro');
  perform public.hr_archive_announcement(v_ann);
  perform tst.as_user('emp');
  perform tst.check(not public.hr_engage_storage_can_read(v_path), 'archived PDF closed to employees');

  -- ------------------------------------------------------------------ translation requests
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_translate_begin(''en-ar'', 100)', 'ENGAGE_MANAGE');
  perform tst.as_user('hro');
  perform tst.expect_error('select public.hr_translate_begin(''en-fr'', 100)', 'direction');
  perform tst.expect_error('select public.hr_translate_begin(''en-ar'', 0)', 'nothing to translate');
  perform tst.expect_error('select public.hr_translate_begin(''en-ar'', 7000)', 'too long');
  reset role;
  update hr.settings set value = value || '{"translate_daily_limit": 2}' where key = 'engagement';
  update hr.settings set value = '[{"en":"plant","ar":"المصنع"},{"en":"","ar":"x"},"junk"]' where key = 'translation_glossary';
  perform tst.as_user('hro');
  v := public.hr_translate_begin('en-ar', 120);
  perform tst.check((v->>'ok')::boolean and (v->>'used')::int = 1 and (v->>'limit')::int = 2, 'first request recorded');
  perform tst.check(v->'glossary' = '[{"en":"plant","ar":"المصنع"}]'::jsonb, 'company glossary returned, junk dropped');
  perform public.hr_translate_begin('ar-en', 80);
  perform tst.expect_error('select public.hr_translate_begin(''en-ar'', 50)', 'LIMIT');
  reset role;
  perform tst.check((select count(*) from hr.translation_log where user_id = tst.id('user_hro')) = 2, 'two requests logged');
  perform tst.check(exists (select 1 from hr.audit_log where table_name = 'translation_log'), 'translation log is audited');
  update hr.settings set value = value - 'translate_daily_limit' where key = 'engagement';
  update hr.settings set value = '[]' where key = 'translation_glossary';
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', false);
select 'ALL ANNOUNCEMENT PDF AND TRANSLATION TESTS PASSED' as result;
