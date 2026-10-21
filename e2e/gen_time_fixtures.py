"""Dump Phase 2 RPC responses from a seeded local database (as the demo HR manager) into e2e/fixtures_time.json.

Usage (after loading supabase/seed.sql and supabase/seed_phase2.sql into the local test database):
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
}

out = {}
for name, call in CALLS.items():
    sql = ("select set_config('request.jwt.claim.sub', (select id::text from auth.users where email = 'hr.manager@aact.test'), false);"
           f"select {call}::text;")
    res = subprocess.run(PSQL + ['-c', sql], capture_output=True, text=True, check=True).stdout.strip().split('\n')
    out[name] = json.loads(res[-1])
path = pathlib.Path(__file__).with_name('fixtures_time.json')
path.write_text(json.dumps(out, ensure_ascii=False), encoding='utf-8')
print(f'wrote {path} ({path.stat().st_size // 1024} KB, {len(out)} calls)')
