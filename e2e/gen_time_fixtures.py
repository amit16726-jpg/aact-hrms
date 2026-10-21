"""Dump Phase 2, 3 and 4 RPC responses from a seeded local database (as the demo HR manager) into e2e/fixtures_time.json.

Usage (after loading supabase/seed.sql, seed_phase2.sql, seed_phase3.sql and seed_phase4.sql into the local test database):
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
