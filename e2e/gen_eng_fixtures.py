"""Dump 1.14.0 / 1.15.0 engagement RPC responses into e2e/fixtures_eng.json for screens.py.

Run after `npm run db:test` (it uses the test users and employees that the database tests create).
Everything is done inside one transaction that is rolled back, so the test database is left as it was.
  python3 e2e/gen_eng_fixtures.py
"""
import json, os, pathlib, subprocess

PSQL = ['psql', '-h', os.environ.get('PGHOST', '/tmp'), '-p', os.environ.get('PGPORT', '5433'), '-U', 'postgres',
        '-d', os.environ.get('PGDATABASE', 'aact_test'), '-At', '-q', '-v', 'ON_ERROR_STOP=1']

SETUP = r"""
begin;
create temp table fx(k text primary key, v jsonb) on commit drop;
update hr.employees set status = 'ACTIVE', separation_date = null where id in (tst.id('emp_mgr'), tst.id('emp_w'));
update hr.settings set value = '{"survey_min_responses": 2, "peer_daily_limit": 5}' where key = 'engagement';
do $$
declare a1 uuid; a2 uuid; a3 uuid; a4 uuid; s1 uuid; s2 uuid; aw uuid; aw2 uuid; v_ent uuid := tst.id('ent');
begin
  perform tst.as_user('hro');
  a1 := (public.hr_save_announcement(jsonb_build_object('entity_id', v_ent, 'category', 'SAFETY', 'pinned', true, 'require_ack', true,
          'attachment_path', 'ann/5b0e7c1e-2f4a-4d7b-9c1e-8a6f3d2b1c0e.pdf', 'attachment_name', 'Safety circular 14-2026 (signed).pdf', 'attachment_bytes', 248000,
          'title_en', 'New safety shoes for the production floor', 'title_ar', 'أحذية سلامة جديدة لأرضية الإنتاج',
          'body_en', E'From Sunday, safety shoes with a steel toe cap are required on the production floor.\nCollect your pair from the store, 7:00–15:00, by Thursday.',
          'body_ar', E'اعتباراً من يوم الأحد، يلزم ارتداء أحذية السلامة ذات المقدمة الفولاذية في أرضية الإنتاج.\nاستلم حذاءك من المخزن من 7:00 إلى 15:00 قبل يوم الخميس.'))->>'id')::uuid;
  perform public.hr_submit_announcement(a1);
  a2 := (public.hr_save_announcement(jsonb_build_object('entity_id', v_ent, 'category', 'EVENT',
          'title_en', 'Family day at Qurum beach', 'title_ar', 'يوم العائلة في شاطئ القرم',
          'body_en', 'Join us with your family on Friday from 4 pm. Food, games and prizes for the children.',
          'body_ar', 'انضم إلينا مع عائلتك يوم الجمعة من الساعة 4 مساءً. طعام وألعاب وجوائز للأطفال.'))->>'id')::uuid;
  perform public.hr_submit_announcement(a2);
  a3 := (public.hr_save_announcement(jsonb_build_object('category', 'HR_POLICY',
          'title_en', 'Updated annual leave request rules', 'title_ar', 'تحديث قواعد طلب الإجازة السنوية',
          'body_en', 'Annual leave of more than 5 days should be requested at least two weeks ahead in the app.',
          'body_ar', 'يجب طلب الإجازة السنوية التي تزيد عن 5 أيام قبل أسبوعين على الأقل من خلال التطبيق.'))->>'id')::uuid;
  perform public.hr_submit_announcement(a3);
  a4 := (public.hr_save_announcement(jsonb_build_object('entity_id', v_ent, 'category', 'HOLIDAY',
          'title_en', 'National Day holiday', 'title_ar', 'إجازة العيد الوطني',
          'body_en', 'The office and plant will be closed for the National Day holiday. Shift teams will receive their rota.',
          'body_ar', 'سيغلق المكتب والمصنع بمناسبة إجازة العيد الوطني. ستتلقى فرق الورديات جداولها.'))->>'id')::uuid;
  perform public.hr_submit_announcement(a4);
  s1 := (public.hr_save_survey(jsonb_build_object('entity_id', v_ent, 'title_en', 'Canteen and transport pulse', 'title_ar', 'استبيان المقصف والنقل',
          'intro_en', 'Four quick questions. It takes about two minutes.', 'intro_ar', 'أربعة أسئلة سريعة. يستغرق دقيقتين تقريباً.',
          'closes_on', hr.today() + 10, 'anonymous', true,
          'questions', jsonb_build_array(
            jsonb_build_object('kind', 'RATING', 'text_en', 'How satisfied are you with the canteen food?', 'text_ar', 'ما مدى رضاك عن طعام المقصف؟'),
            jsonb_build_object('kind', 'RATING', 'text_en', 'How satisfied are you with company transport?', 'text_ar', 'ما مدى رضاك عن نقل الشركة؟'),
            jsonb_build_object('kind', 'CHOICE', 'text_en', 'Which lunch time suits you best?', 'text_ar', 'أي وقت للغداء يناسبك أكثر؟',
              'options', jsonb_build_array(jsonb_build_object('en', '12:00', 'ar', '12:00'), jsonb_build_object('en', '12:30', 'ar', '12:30'), jsonb_build_object('en', '13:00', 'ar', '13:00'))),
            jsonb_build_object('kind', 'TEXT', 'text_en', 'What one thing would make your working day better?', 'text_ar', 'ما الشيء الذي يجعل يوم عملك أفضل؟'))))->>'id')::uuid;
  perform public.hr_submit_survey(s1);
  s2 := (public.hr_save_survey(jsonb_build_object('title_en', 'Training needs 2027', 'closes_on', hr.today() + 20, 'anonymous', false,
          'questions', jsonb_build_array(jsonb_build_object('kind', 'TEXT', 'text_en', 'Which course would help you most next year?', 'required', true))))->>'id')::uuid;
  perform public.hr_submit_survey(s2);
  aw := (public.hr_propose_award(jsonb_build_object('employee_id', tst.id('emp_w'), 'award_title', 'Employee of the month', 'category', 'QUALITY',
          'message', 'Zero defects on line 2 for three months and helped train two new operators.'))->>'id')::uuid;
  aw2 := (public.hr_propose_award(jsonb_build_object('employee_id', tst.id('emp_mgr'), 'award_title', 'Safety champion', 'category', 'SAFETY',
          'message', '500 days without a lost-time injury in Production.'))->>'id')::uuid;
  perform tst.as_user('hrm');
  perform public.hr_decide_announcement(a1, true, null);
  perform public.hr_decide_announcement(a2, true, null);
  perform public.hr_decide_announcement(a4, true, null);
  perform public.hr_decide_survey(s1, true, null);
  perform public.hr_decide_award(aw, true, null);
  perform tst.as_user('emp');
  perform public.hr_get_announcement(a2);
  perform public.hr_give_recognition(jsonb_build_object('employee_id', tst.id('emp_mgr'), 'category', 'TEAMWORK',
          'message', 'Covered the night shift at short notice so the order shipped on time. Thank you, Salim!'));
  -- the employee's view (before answering, so the screens show the survey form)
  insert into fx values ('hr_engage_home', public.hr_engage_home());
  insert into fx values ('hr_engage_counts', public.hr_engage_counts());
  insert into fx values ('hr_get_announcement', public.hr_get_announcement(a1));
  insert into fx values ('hr_get_survey', public.hr_get_survey(s1));
  perform public.hr_answer_survey(s1, '{"q1":4,"q2":3,"q3":1,"q4":"A shaded parking area"}'::jsonb);
  perform tst.as_user('mgr');
  perform public.hr_give_recognition(jsonb_build_object('employee_id', tst.id('emp_w'), 'category', 'SAFETY',
          'message', 'Stopped the press when a guard was missing and reported it straight away.'));
  perform public.hr_answer_survey(s1, '{"q1":3,"q2":4,"q3":0,"q4":"More fruit in the canteen"}'::jsonb);
  perform public.hr_applaud_recognition((select id from hr.recognitions where kind = 'AWARD' and status = 'APPROVED' order by decided_at desc limit 1));

  -- the HR manager's view
  perform tst.as_user('hrm');
  insert into fx values ('hr_list_announcements', public.hr_list_announcements());
  insert into fx values ('hr_list_surveys', public.hr_list_surveys());
  insert into fx values ('hr_list_recognitions', public.hr_list_recognitions('{"scope":"all"}'::jsonb) || public.hr_list_recognitions('{"scope":"pending"}'::jsonb));
  insert into fx values ('hr_survey_results', public.hr_survey_results(s1));
  insert into fx values ('hr_announcement_readers', public.hr_announcement_readers(a1));
  insert into fx values ('hr_engage_colleagues', public.hr_engage_colleagues(''));
end $$;
select jsonb_object_agg(k, v)::text from fx;
rollback;
"""

res = subprocess.run(PSQL, input=SETUP, capture_output=True, text=True, check=True).stdout.strip().split('\n')
line = next(x for x in reversed(res) if x.startswith('{'))
out = json.loads(line)
# the screens show an HR manager who is also an employee: let them manage and approve on the engagement page
out['hr_engage_home']['caps'].update({'manage': True, 'approve': True})
path = pathlib.Path(__file__).with_name('fixtures_eng.json')
path.write_text(json.dumps(out, ensure_ascii=False), encoding='utf-8')
print(f'wrote {path} ({path.stat().st_size // 1024} KB, {len(out)} calls)')
