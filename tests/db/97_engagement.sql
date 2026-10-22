-- AACT HRMS — 1.14.0 employee engagement: announcements, surveys, recognition.
set client_min_messages = warning;
reset role;

do $$
declare v jsonb; v_ann uuid; v_ann2 uuid; v_sv uuid; v_sv2 uuid; v_rec uuid; v_award uuid; v_ent uuid := tst.id('ent');
        v_dep uuid; v_n int; v_mgr_emp uuid := tst.id('emp_mgr'); v_w_emp uuid := tst.id('emp_w');
begin
  -- the people used here are current employees of the test company
  update hr.employees set status = 'ACTIVE', separation_date = null where id in (v_mgr_emp, v_w_emp) and status = 'SEPARATED';
  select (hr.current_assignment(v_w_emp, hr.today())).department_id into v_dep;

  -- permissions
  perform tst.as_user('emp');
  perform tst.expect_error('select public.hr_list_announcements()', 'ENGAGE_MANAGE');
  perform tst.expect_error($q$select public.hr_save_announcement('{"title_en":"Hello","body_en":"World"}'::jsonb)$q$, 'ENGAGE_MANAGE');
  perform tst.expect_error('select public.hr_list_surveys()', 'ENGAGE_MANAGE');

  -- ------------------------------------------------------------------ announcements
  perform tst.as_user('hro');
  perform tst.expect_error($q$select public.hr_save_announcement('{"title_en":"Hi","body_en":"World"}'::jsonb)$q$, 'title');
  perform tst.expect_error(format($q$select public.hr_save_announcement('{"title_en":"Past","body_en":"Body","publish_on":"%s"}'::jsonb)$q$, hr.today() - 1), 'past');
  v := public.hr_save_announcement(jsonb_build_object('entity_id', v_ent, 'category', 'SAFETY', 'title_en', 'New safety shoes',
         'title_ar', 'أحذية سلامة جديدة', 'body_en', 'Collect your new safety shoes from the store.', 'require_ack', true, 'pinned', true));
  v_ann := (v->>'id')::uuid;
  perform tst.check(v->>'status' = 'DRAFT' and (v->>'can_edit')::boolean, 'announcement drafted');
  -- not visible to employees while a draft
  perform tst.as_user('emp');
  perform tst.check(jsonb_array_length(public.hr_engage_home()->'announcements') = 0, 'draft not in the feed');
  perform tst.expect_error(format('select public.hr_get_announcement(%L)', v_ann), 'NOT_FOUND');

  perform tst.as_user('hro');
  v := public.hr_submit_announcement(v_ann);
  perform tst.check(v->>'status' = 'PENDING', 'sent for approval');
  perform tst.expect_error(format($q$select public.hr_save_announcement('{"id":"%s","title_en":"Changed","body_en":"Body"}'::jsonb)$q$, v_ann), 'draft or a rejected');
  perform tst.check(exists (select 1 from hr.notifications n where n.user_id = tst.id('user_hrm') and n.ref_key like 'ann-approve:%'), 'approver told');

  -- maker-checker: an officer cannot approve; the proposer cannot approve
  perform tst.expect_error(format('select public.hr_decide_announcement(%L, true)', v_ann), 'ENGAGE_APPROVE');
  perform tst.as_user('hrm');
  perform tst.expect_error(format('select public.hr_decide_announcement(%L, false)', v_ann), 'reason');
  v := public.hr_decide_announcement(v_ann, false, 'Add the store opening hours');
  perform tst.check(v->>'status' = 'REJECTED', 'rejected with a reason');
  perform tst.as_user('hro');
  v := public.hr_save_announcement(jsonb_build_object('id', v_ann, 'entity_id', v_ent, 'category', 'SAFETY', 'title_en', 'New safety shoes',
         'body_en', 'Collect your new safety shoes from the store, 7:00–15:00.', 'require_ack', true, 'pinned', true));
  perform tst.check(v->>'status' = 'DRAFT', 'rejected announcement edited back to draft');
  perform public.hr_submit_announcement(v_ann);
  perform tst.as_user('hrm');
  v := public.hr_decide_announcement(v_ann, true, null);
  perform tst.check(v->>'status' = 'PUBLISHED' and (v->>'live')::boolean, 'published and live');
  perform tst.check(exists (select 1 from hr.notifications n where n.user_id = tst.id('user_emp') and n.ref_key = 'ann:' || v_ann and n.priority = 'HIGH'),
                    'employee notified (high priority: needs confirmation)');
  perform tst.check((v->'stats'->>'audience')::int >= 2 and (v->'stats'->>'read')::int = 0, 'audience counted');

  -- hrm prepares one, hro cannot approve (no permission); self approval is refused
  v := public.hr_save_announcement(jsonb_build_object('title_en', 'Family day', 'body_en', 'Family day on Friday at the beach.', 'category', 'EVENT',
         'department_id', tst.id('dep_hr')));
  v_ann2 := (v->>'id')::uuid;
  perform public.hr_submit_announcement(v_ann2);
  perform tst.expect_error(format('select public.hr_decide_announcement(%L, true)', v_ann2), 'SELF_APPROVAL');
  perform tst.as_user('admin');
  perform public.hr_decide_announcement(v_ann2, true, 'OK');

  -- the employee reads and confirms; a department-only announcement stays out of other departments
  perform tst.as_user('emp');
  v := public.hr_engage_home();
  perform tst.check(jsonb_array_length(v->'announcements') = 1 and (v->>'unread')::int = 1 and (v->>'to_confirm')::int = 1, 'feed shows the one for this department');
  perform tst.check((public.hr_engage_counts()->>'unread')::int = 1, 'menu badge count');
  perform tst.expect_error(format('select public.hr_get_announcement(%L)', v_ann2), 'NOT_FOUND');
  v := public.hr_get_announcement(v_ann);
  perform tst.check(v->>'read_at' is not null and (v->>'in_audience')::boolean, 'opening marks it read');
  perform tst.check((public.hr_engage_home()->>'unread')::int = 0, 'nothing unread');
  v := public.hr_ack_announcement(v_ann);
  perform tst.check(v->>'acknowledged_at' is not null, 'confirmed');
  perform tst.expect_error(format('select public.hr_ack_announcement(%L)', v_ann2), 'NOT_FOUND');
  perform tst.as_user('hro');
  v := public.hr_announcement_readers(v_ann);
  perform tst.check(exists (select 1 from jsonb_array_elements(v) x where (x->>'employee_id')::uuid = v_w_emp and x->>'acknowledged_at' is not null), 'reader list shows the confirmation');
  v := public.hr_archive_announcement(v_ann);
  perform tst.check(v->>'status' = 'ARCHIVED', 'archived');
  perform tst.as_user('emp');
  perform tst.check(jsonb_array_length(public.hr_engage_home()->'announcements') = 0, 'archived leaves the feed');

  -- ------------------------------------------------------------------ surveys
  perform tst.as_user('hro');
  perform tst.expect_error(format($q$select public.hr_save_survey('{"title_en":"Pulse","closes_on":"%s","questions":[]}'::jsonb)$q$, hr.today() + 7), 'at least one question');
  perform tst.expect_error(format($q$select public.hr_save_survey('{"title_en":"Pulse","closes_on":"%s","questions":[{"kind":"CHOICE","text_en":"Pick one","options":[{"en":"Only"}]}]}'::jsonb)$q$, hr.today() + 7), 'between 2 and 10');
  v := public.hr_save_survey(jsonb_build_object('entity_id', v_ent, 'title_en', 'Canteen pulse', 'closes_on', hr.today() + 7, 'anonymous', true,
         'questions', jsonb_build_array(
           jsonb_build_object('kind', 'RATING', 'text_en', 'How happy are you with the canteen food?'),
           jsonb_build_object('kind', 'CHOICE', 'text_en', 'Best lunch time?', 'options', jsonb_build_array(jsonb_build_object('en','12:00'), jsonb_build_object('en','13:00'))),
           jsonb_build_object('kind', 'TEXT', 'text_en', 'Any other comments?'))));
  v_sv := (v->>'id')::uuid;
  perform tst.check(v->'questions'->0->>'key' = 'q1' and v->'questions'->2->>'required' = 'false', 'questions keyed; text optional');
  perform public.hr_submit_survey(v_sv);
  perform tst.as_user('emp');
  perform tst.expect_error(format($q$select public.hr_answer_survey(%L, '{"q1":4}'::jsonb)$q$, v_sv), 'NOT_FOUND');
  perform tst.as_user('hrm');
  v := public.hr_decide_survey(v_sv, true, null);
  perform tst.check(v->>'status' = 'OPEN' and (v->>'live')::boolean, 'survey open');
  perform tst.check(exists (select 1 from hr.notifications n where n.user_id = tst.id('user_emp') and n.ref_key = 'survey:' || v_sv), 'employees told');

  perform tst.as_user('emp');
  v := public.hr_get_survey(v_sv);
  perform tst.check((v->>'can_answer')::boolean and v->>'responses' is null, 'employee can answer; no counts shown to them');
  perform tst.expect_error(format($q$select public.hr_answer_survey(%L, '{"q2":0}'::jsonb)$q$, v_sv), 'Please answer');
  perform tst.expect_error(format($q$select public.hr_answer_survey(%L, '{"q1":6,"q2":0}'::jsonb)$q$, v_sv), '1 to 5');
  perform tst.expect_error(format($q$select public.hr_answer_survey(%L, '{"q1":4,"q2":5}'::jsonb)$q$, v_sv), 'not valid');
  v := public.hr_answer_survey(v_sv, '{"q1":4,"q2":1,"q3":"More fruit please"}'::jsonb);
  perform tst.check((v->>'answered')::int = 3, 'answered');
  perform tst.expect_error(format($q$select public.hr_answer_survey(%L, '{"q1":5,"q2":0}'::jsonb)$q$, v_sv), 'already answered');
  perform tst.check(not (public.hr_get_survey(v_sv)->>'can_answer')::boolean, 'cannot answer twice');
  -- anonymity: the answer carries no person, and is not in the audit trail
  perform tst.check(not exists (select 1 from hr.survey_answers a where a.survey_id = v_sv and a.employee_id is not null), 'anonymous answers carry no employee');
  perform tst.check(not exists (select 1 from hr.audit_log l where l.table_name = 'survey_answers'), 'answers kept out of the audit trail');
  perform tst.check(exists (select 1 from hr.survey_participants sp where sp.survey_id = v_sv and sp.user_id = tst.id('user_emp')), 'participation recorded');

  perform tst.as_user('mgr');
  perform public.hr_answer_survey(v_sv, '{"q1":2,"q2":0}'::jsonb);
  -- results hidden below the minimum group size
  perform tst.as_user('hro');
  v := public.hr_survey_results(v_sv);
  perform tst.check((v->>'hidden')::boolean and (v->>'responses')::int = 2 and jsonb_array_length(v->'questions') = 0, 'results hidden below 5 answers');
  perform tst.expect_error('select public.hr_survey_results(gen_random_uuid())', 'NOT_FOUND');
  perform tst.as_user('emp');
  perform tst.expect_error(format('select public.hr_survey_results(%L)', v_sv), 'ENGAGE_MANAGE');
  -- with the minimum lowered, results appear
  reset role;
  update hr.settings set value = '{"survey_min_responses": 2, "peer_daily_limit": 2}' where key = 'engagement';
  perform tst.as_user('hro');
  v := public.hr_survey_results(v_sv);
  perform tst.check(not (v->>'hidden')::boolean, 'results shown');
  perform tst.check((v->'questions'->0->>'average')::numeric = 3 and (v->'questions'->0->'ratings'->>3)::int = 1, 'rating average and spread');
  perform tst.check((v->'questions'->1->'choices'->>0)::int = 1 and (v->'questions'->1->'choices'->>1)::int = 1, 'choice counts');
  perform tst.check(v->'questions'->2->'texts'->>0 = 'More fruit please', 'comments listed without names');
  perform tst.check(exists (select 1 from hr.access_log l where l.detail = 'SURVEY_RESULTS ' || v_sv), 'opening results is logged');

  -- a named (not anonymous) survey keeps the employee
  v := public.hr_save_survey(jsonb_build_object('title_en', 'Training needs', 'closes_on', hr.today() + 3, 'anonymous', false,
         'questions', jsonb_build_array(jsonb_build_object('kind', 'TEXT', 'text_en', 'Which course would help you most?', 'required', true))));
  v_sv2 := (v->>'id')::uuid;
  perform public.hr_submit_survey(v_sv2);
  perform tst.as_user('hrm');
  perform public.hr_decide_survey(v_sv2, true, null);
  perform tst.as_user('emp');
  perform public.hr_answer_survey(v_sv2, '{"q1":"Forklift"}'::jsonb);
  perform tst.check(exists (select 1 from hr.survey_answers a where a.survey_id = v_sv2 and a.employee_id = v_w_emp), 'named survey stores the employee');
  perform tst.as_user('hro');
  v := public.hr_close_survey(v_sv2);
  perform tst.check(v->>'status' = 'CLOSED', 'closed by HR');
  perform tst.as_user('emp');
  perform tst.expect_error(format($q$select public.hr_answer_survey(%L, '{"q1":"Again"}'::jsonb)$q$, v_sv2), 'not open|already');

  -- ------------------------------------------------------------------ recognition
  perform tst.as_user('emp');
  perform tst.check(jsonb_array_length(public.hr_engage_colleagues('')) >= 1, 'colleague search');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_engage_colleagues('')) x where (x->>'employee_id')::uuid = v_w_emp), 'self not offered');
  perform tst.expect_error(format($q$select public.hr_give_recognition('{"employee_id":"%s","message":"Great"}'::jsonb)$q$, v_w_emp), 'yourself');
  perform tst.expect_error(format($q$select public.hr_give_recognition('{"employee_id":"%s","message":"x"}'::jsonb)$q$, v_mgr_emp), 'short message');
  v := public.hr_give_recognition(jsonb_build_object('employee_id', v_mgr_emp, 'category', 'SAFETY', 'message', 'Stopped the line when a guard was missing.'));
  v_rec := (v->>'id')::uuid;
  perform tst.check(v->>'status' = 'APPROVED' and v->'employee'->>'employee_id' = v_mgr_emp::text, 'recognition posted');
  perform tst.check(exists (select 1 from hr.notifications n where n.user_id = tst.id('user_mgr') and n.ref_key = 'recog:' || v_rec), 'colleague told');
  perform public.hr_give_recognition(jsonb_build_object('employee_id', v_mgr_emp, 'message', 'Thanks for the help with the night shift.'));
  perform tst.expect_error(format($q$select public.hr_give_recognition('{"employee_id":"%s","message":"Third today"}'::jsonb)$q$, v_mgr_emp), 'a day');
  perform tst.as_user('mgr');
  v := public.hr_applaud_recognition(v_rec);
  v := public.hr_applaud_recognition(v_rec);
  perform tst.check((v->>'applause')::int = 1 and (v->>'applauded')::boolean, 'applause counted once');
  v := public.hr_engage_home();
  perform tst.check(jsonb_array_length(v->'recognitions') >= 2 and (v->>'my_count')::int >= 2, 'wall and my count');
  perform tst.check((v->'top_month'->0->>'employee_id')::uuid = v_mgr_emp, 'most recognised this month');
  perform tst.check(jsonb_array_length(public.hr_list_recognitions('{"scope":"mine"}'::jsonb)) >= 2, 'my recognitions');
  perform tst.expect_error($q$select public.hr_list_recognitions('{"scope":"pending"}'::jsonb)$q$, 'ENGAGE_MANAGE');
  perform tst.expect_error(format($q$select public.hr_hide_recognition(%L, 'spam')$q$, v_rec), 'ENGAGE_MANAGE');
  -- HR hides an unsuitable post (reason needed)
  perform tst.as_user('hro');
  perform tst.expect_error(format($q$select public.hr_hide_recognition(%L, '')$q$, v_rec), 'reason');
  v := public.hr_hide_recognition(v_rec, 'Duplicate post');
  perform tst.check(v->>'status' = 'HIDDEN', 'hidden');
  perform tst.as_user('emp');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_engage_home()->'recognitions') x where (x->>'id')::uuid = v_rec), 'hidden leaves the wall');
  perform tst.check(public.hr_engage_home()->'recognitions'->0->>'hidden_reason' is null, 'reason not shown to employees');

  -- awards: proposed by HR, approved by someone else
  perform tst.as_user('hro');
  perform tst.expect_error(format($q$select public.hr_propose_award('{"employee_id":"%s","message":"Well done"}'::jsonb)$q$, v_w_emp), 'award name');
  v := public.hr_propose_award(jsonb_build_object('employee_id', v_w_emp, 'award_title', 'Employee of the month', 'category', 'QUALITY',
         'message', 'Zero defects for three months.'));
  v_award := (v->>'id')::uuid;
  perform tst.check(v->>'status' = 'PENDING', 'award waiting');
  perform tst.check((public.hr_list_recognitions('{"scope":"pending"}'::jsonb)->0->>'id')::uuid = v_award, 'pending list');
  perform tst.as_user('emp');
  perform tst.check(not exists (select 1 from jsonb_array_elements(public.hr_engage_home()->'recognitions') x where (x->>'id')::uuid = v_award), 'pending award not on the wall');
  perform tst.as_user('hrm');
  perform tst.check((public.hr_engage_counts()->>'to_approve')::int >= 1, 'approver badge');
  v := public.hr_decide_award(v_award, true, null);
  perform tst.check(v->>'status' = 'APPROVED', 'award approved');
  perform tst.check(exists (select 1 from hr.notifications n where n.user_id = tst.id('user_emp') and n.ref_key = 'recog:' || v_award), 'winner told');
  perform tst.as_user('emp');
  perform tst.check(exists (select 1 from jsonb_array_elements(public.hr_engage_home()->'recognitions') x where (x->>'id')::uuid = v_award), 'award on the wall');

  -- users without an employee record cannot recognise; their home still works
  perform tst.as_user('fin');
  v := public.hr_engage_home();
  perform tst.check(not (v->'caps'->>'recognise')::boolean and jsonb_array_length(v->'recognitions') = 0, 'no employee: empty wall, cannot recognise');
  perform tst.expect_error(format($q$select public.hr_give_recognition('{"employee_id":"%s","message":"Hello there"}'::jsonb)$q$, v_mgr_emp), 'NOT_LINKED');

  -- daily job closes surveys past their date
  reset role;
  update hr.surveys set closes_on = hr.today() - 1, opens_on = hr.today() - 3 where id = v_sv;
  perform hr.engage_daily(hr.today());
  perform tst.check((select status from hr.surveys where id = v_sv) = 'CLOSED', 'daily job closes surveys');
  update hr.settings set value = '{"survey_min_responses": 5, "peer_daily_limit": 5}' where key = 'engagement';
end $$;

reset role;
select set_config('request.jwt.claim.sub', '', false);
select 'ALL ENGAGEMENT TESTS PASSED' as result;
