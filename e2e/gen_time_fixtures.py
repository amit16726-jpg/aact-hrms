"""Dump Phase 2–7 RPC responses from a seeded local database (as the demo HR manager) into e2e/fixtures_time.json.

Usage (after loading supabase/seed.sql, seed_phase2.sql, seed_phase3.sql, seed_phase4.sql, seed_phase5.sql, seed_phase6.sql and seed_phase7.sql into the local test database):
  python3 e2e/gen_time_fixtures.py
"""
import json, subprocess, pathlib, os

PSQL = ['psql', '-h', os.environ.get('PGHOST', '/tmp'), '-p', os.environ.get('PGPORT', '5433'), '-U', 'postgres', '-d', os.environ.get('PGDATABASE', 'aact_test'), '-At', '-v', 'ON_ERROR_STOP=1']

CALLS = {
    'hr_time_dashboard': "public.hr_time_dashboard()",
    'hr_list_my_tasks': "public.hr_list_my_tasks()",
    'hr_list_time_rules': "public.hr_list_time_rules()",
    'hr_list_shifts': "public.hr_list_shifts((select id from hr.legal_entities limit 1))",
    'hr_list_shift_assignments': "public.hr_list_shift_assignments(jsonb_build_object('employee_id', (select id from hr.employees where full_name_en='Ravi Kumar')))",
    'hr_list_holidays': "public.hr_list_holidays(2026, null)",
    'hr_list_device_users': "public.hr_list_device_users(null)",
    'hr_list_punch_batches': "public.hr_list_punch_batches(null)",
    'hr_attendance_day': "public.hr_attendance_day(jsonb_build_object('date', (current_date - 1)::text))",
    'hr_attendance_month': "public.hr_attendance_month((select id from hr.employees where full_name_en='Ravi Kumar'), to_char(current_date, 'YYYY-MM'))",
    'hr_attendance_grid': "public.hr_attendance_grid(jsonb_build_object('month', to_char(current_date, 'YYYY-MM')))",
    'hr_attendance_summary': "public.hr_attendance_summary(jsonb_build_object('entity_id', (select id from hr.legal_entities limit 1), 'month', to_char(current_date - interval '1 month', 'YYYY-MM')))",
    'hr_list_corrections': "public.hr_list_corrections(jsonb_build_object())",
    'hr_list_overtime': "public.hr_list_overtime(jsonb_build_object())",
    'hr_list_periods': "public.hr_list_periods((select id from hr.legal_entities limit 1), null)",
    'hr_list_leave_types': "public.hr_list_leave_types()",
    'hr_leave_balances': "public.hr_leave_balances((select id from hr.employees where full_name_en='Ravi Kumar'), null)",
    'hr_list_leave_balances': "public.hr_list_leave_balances(jsonb_build_object('leave_type', 'ANNUAL'))",
    'hr_list_leave_requests': "public.hr_list_leave_requests(jsonb_build_object('scope', 'all'))",
    'hr_leave_calendar': "public.hr_leave_calendar(jsonb_build_object('month', to_char(current_date, 'YYYY-MM')))",
    'hr_list_leave_adjustments': "public.hr_list_leave_adjustments(jsonb_build_object())",
    'hr_list_pending_approvals': "public.hr_list_pending_approvals()",
    # Phase 3 — payroll
    'hr_list_payroll_runs': "public.hr_list_payroll_runs(null, null)",
    'hr_get_payroll_run': "public.hr_get_payroll_run((select id from hr.payroll_runs order by period_start desc limit 1))",
    'hr_get_payslip': "public.hr_get_payslip((select s.id from hr.payslips s join hr.payroll_runs r on r.id = s.run_id where s.employee_no = 'AACT-00001' order by r.period_start desc limit 1))",
    'hr_my_payslips': "(select jsonb_agg(jsonb_build_object('id', s.id, 'month', to_char(r.period_start,'YYYY-MM'), 'pay_date', r.pay_date, 'status', r.status, 'net', s.net, 'total_earnings', s.total_earnings, 'total_deductions', s.total_deductions) order by r.period_start desc) from hr.payslips s join hr.payroll_runs r on r.id = s.run_id where s.employee_no = 'AACT-00017')",
    'hr_employee_payroll': "public.hr_employee_payroll((select id from hr.employees where employee_no = 'AACT-00003'))",
    'hr_list_loans': "public.hr_list_loans(jsonb_build_object())",
    'hr_list_pay_adjustments': "public.hr_list_pay_adjustments(jsonb_build_object())",
    'hr_list_settlements': "public.hr_list_settlements(jsonb_build_object())",
    'hr_get_settlement': "public.hr_get_settlement((select id from hr.final_settlements limit 1))",
    'hr_gratuity_report': "public.hr_gratuity_report(null, null)",
    'hr_list_pay_rules': "public.hr_list_pay_rules()",
    'hr_payroll_setup': "public.hr_payroll_setup()",
    'hr_get_compensation': "public.hr_get_compensation((select id from hr.employees where employee_no = 'AACT-00003'))",
    'hr_list_pay_components': "public.hr_list_pay_components()",
    'hr_parallel_report': "public.hr_parallel_report((select id from hr.payroll_runs order by period_start desc limit 1))",
    # Phase 4 — self-service & letters (some as the demo employee or line manager)
    'hr_my_portal': ("public.hr_my_portal()", 'employee@aact.test'),
    'hr_my_team': ("public.hr_my_team()", 'manager@aact.test'),
    'hr_get_letter': ("public.hr_get_letter((select id from hr.letters where status = 'ISSUED' limit 1))", 'employee@aact.test'),
    'hr_list_change_requests': "public.hr_list_change_requests(null, null)",
    'hr_list_letters': "public.hr_list_letters(null, null)",
    'hr_letter_settings': "public.hr_letter_settings()",
    'hr_my_email_pref': "public.hr_my_email_pref()",
    'hr_email_settings': ("public.hr_email_settings()", 'admin@aact.test'),
    'hr_verify_letter': "(select public.hr_verify_letter(ref_no, verify_code) from hr.letters where status = 'ISSUED' limit 1)",
    # Phase 5 — recruitment & onboarding
    'hr_list_requisitions': "public.hr_list_requisitions('{}'::jsonb)",
    'hr_get_requisition': "public.hr_get_requisition((select id from hr.job_requisitions where positions = 3 limit 1))",
    'hr_get_application': "public.hr_get_application((select a.id from hr.applications a join hr.job_offers o on o.application_id = a.id where o.status = 'ACCEPTED' limit 1))",
    'hr_get_offer': "public.hr_get_offer((select id from hr.job_offers where status = 'ACCEPTED' limit 1))",
    'hr_list_candidates': "public.hr_list_candidates('{}'::jsonb)",
    'hr_my_interviews': "public.hr_my_interviews()",
    'hr_list_onboarding': "public.hr_list_onboarding('{}'::jsonb)",
    'hr_recruitment_settings': "public.hr_recruitment_settings()",
    'hr_list_probation': "public.hr_list_probation()",
    'hr_rec_interviewers': "public.hr_rec_interviewers()",
    # Phase 6 — performance, training, discipline, assets, housing & transport, injuries, exit
    'hr_list_perf_cycles': "public.hr_list_perf_cycles()",
    'hr_list_perf_reviews': "public.hr_list_perf_reviews('{\"scope\":\"all\"}'::jsonb)",
    'hr_get_perf_review': "public.hr_get_perf_review((select r.id from hr.perf_reviews r join hr.employees e on e.id = r.employee_id where e.employee_no = 'AACT-00017'))",
    'hr_list_perf_plans': "public.hr_list_perf_plans()",
    'hr_list_courses': "public.hr_list_courses()",
    'hr_list_training': "public.hr_list_training('{}'::jsonb)",
    'hr_training_gaps': "public.hr_training_gaps()",
    'hr_list_cases': "public.hr_list_cases('{}'::jsonb)",
    'hr_get_case': "public.hr_get_case((select id from hr.disciplinary_cases where status = 'PROPOSED' limit 1))",
    'hr_list_asset_items': "public.hr_list_asset_items()",
    'hr_list_asset_issues': "public.hr_list_asset_issues('{\"open_only\":true}'::jsonb)",
    'hr_list_facilities': "public.hr_list_facilities('ACCOMMODATION')",
    'hr_list_injuries': "public.hr_list_injuries('{}'::jsonb)",
    'hr_list_exits': "public.hr_list_exits('{}'::jsonb)",
    'hr_get_exit': "public.hr_get_exit((select id from hr.exit_cases limit 1))",
    'hr_hr_policies': "public.hr_hr_policies()",
    # Phase 7 — privacy, statutory reports, executive dashboard, import
    'hr_pdpl_overview': "public.hr_pdpl_overview()",
    'hr_list_notices': "public.hr_list_notices()",
    'hr_my_privacy': ("public.hr_my_privacy()", 'employee@aact.test'),
    'hr_list_consents': "public.hr_list_consents()",
    'hr_list_dsr': "public.hr_list_dsr('{}'::jsonb)",
    'hr_list_breaches': "public.hr_list_breaches()",
    'hr_list_activities': "public.hr_list_activities()",
    'hr_retention_report': "public.hr_retention_report()",
    'hr_pdpl_settings': "public.hr_pdpl_settings()",
    'hr_mol_report': "public.hr_mol_report((select id from hr.legal_entities order by created_at limit 1), null)",
    'hr_spf_report': "public.hr_spf_report((select id from hr.payroll_runs where status in ('APPROVED','PAID') order by period_start desc limit 1))",
    'hr_exec_dashboard': "public.hr_exec_dashboard((select id from hr.legal_entities order by created_at limit 1))",
    'hr_list_imports': "public.hr_list_imports()",
}

out = {}
for name, call in CALLS.items():
    call, who = call if isinstance(call, tuple) else (call, 'hr.manager@aact.test')
    sql = (f"select set_config('request.jwt.claim.sub', (select id::text from auth.users where email = '{who}'), false);"
           f"select {call}::text;")
    res = subprocess.run(PSQL + ['-c', sql], capture_output=True, text=True, check=True).stdout.strip().split('\n')
    out[name] = json.loads(res[-1])
path = pathlib.Path(__file__).with_name('fixtures_time.json')
path.write_text(json.dumps(out, ensure_ascii=False), encoding='utf-8')
print(f'wrote {path} ({path.stat().st_size // 1024} KB, {len(out)} calls)')
