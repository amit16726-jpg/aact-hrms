"""Visual check of the main screens with the Supabase network faked (test harness only).

Usage:
  VITE_SUPABASE_URL=https://mockref.supabase.co VITE_SUPABASE_ANON_KEY=test npx vite build --outDir <dist>
  python3 e2e/screens.py <dist> <out-dir>
Serves <dist>, answers /rest/v1/rpc/* from the fixtures below, screenshots each screen at phone and desktop width
in English and Arabic, and fails on any page error, console error or horizontal scroll.
"""
import json, sys, threading, time, http.server, functools, pathlib
from playwright.sync_api import sync_playwright

DIST, OUT = sys.argv[1], pathlib.Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

ENT = 'aaaaaaaa-0000-0000-0000-000000000001'
E1, E2, E3 = ('bbbbbbbb-0000-0000-0000-00000000000%d' % i for i in (1, 2, 3))
perms = ['ORG_READ','ORG_WRITE','EMP_READ','EMP_WRITE','EMP_SALARY_READ','EMP_SALARY_WRITE','SALARY_APPROVE','EMP_BANK_READ',
         'EMP_BANK_WRITE','DOC_READ','DOC_WRITE','DOC_SENSITIVE','COMPLIANCE_READ','RULES_PROPOSE','RULES_APPROVE','EXCEPTION_APPROVE','AUDIT_READ',
         'ATT_READ','ATT_WRITE','ATT_APPROVE','ATT_LOCK','LEAVE_READ','LEAVE_WRITE','LEAVE_APPROVE',
         'PAY_READ','PAY_PREPARE','PAY_VERIFY','PAY_APPROVE','SS_APPROVE','LETTER_PREPARE','LETTER_APPROVE','EMAIL_ADMIN','REC_READ','REC_WRITE','REC_APPROVE','EXCEPTION_APPROVE',
         'PERF_MANAGE','TRAIN_WRITE','DISC_READ','DISC_WRITE','DISC_APPROVE','ASSET_WRITE','HSE_WRITE','EXIT_MANAGE','PDPL_READ','PDPL_MANAGE','EXEC_VIEW','DATA_IMPORT','MG_PAY']
ME = {'user_id': 'u1', 'email': 'hr.manager@aact.om', 'display_name': 'Maryam Al Hinai', 'language': 'en', 'is_active': True,
      'employee_id': None, 'employee_no': None, 'employee_name': None, 'employee_name_ar': None, 'roles': ['HR_MANAGER'],
      'permissions': perms, 'is_manager': False, 'admin_exists': True, 'settings': {'employee_no_prefix': 'AACT-', 'employee_no_digits': 5, 'leave_opening_date': '2026-07-01'},
      'entities': [{'id': ENT, 'code': 'AACT', 'name_en': 'AACT Industries LLC', 'name_ar': 'شركة أ.أ.س.ت للصناعات'}], 'unread_notifications': 3}

def exp(eid, no, name, name_ar, dt, nm, nm_ar, d, days, bucket, src='DOCUMENT', num='X'):
    return {'employee_id': eid, 'employee_no': no, 'full_name_en': name, 'full_name_ar': name_ar, 'nationality': 'IN', 'entity_id': ENT,
            'department_id': None, 'department_en': 'Production', 'department_ar': 'الإنتاج', 'source': src, 'ref_id': no + dt,
            'doc_type': dt, 'name_en': nm, 'name_ar': nm_ar, 'doc_number': num, 'expiry_date': d, 'days_left': days, 'bucket': bucket, 'is_sensitive': False}

EXPIRIES = [
    exp(E2, 'AACT-00002', 'Ravi Kumar', None, 'RESIDENT_CARD', 'Resident card', 'بطاقة المقيم', '2026-10-15', -5, 'EXPIRED', num='RC998877'),
    exp(E3, 'AACT-00007', 'Mohammed Rafiq', None, 'WORK_PERMIT', 'Work permit / labour clearance', 'تصريح العمل', '2026-11-04', 15, 'D30', num='WP-22410'),
    exp(E2, 'AACT-00002', 'Ravi Kumar', None, 'WORK_PERMIT', 'Work permit / labour clearance', 'تصريح العمل', '2026-12-04', 45, 'D60', num='WP-1'),
    exp(E3, 'AACT-00007', 'Mohammed Rafiq', None, 'CONTRACT', 'Employment contract', 'عقد العمل', '2027-01-03', 75, 'D90', 'CONTRACT', 'C-118'),
]

ASG = {'id': 'as1', 'employee_id': E2, 'effective_from': '2026-08-21', 'effective_to': None, 'department_id': 'd1', 'job_title_id': 'j1',
       'grade_id': 'g1', 'category_id': 'c1', 'location_id': 'l1', 'cost_centre_id': 'cc1', 'manager_id': E1, 'employment_type': 'FULL_TIME',
       'shift_code': 'B', 'reason': 'JOIN', 'notes': None, 'omanisation_exception_id': None, 'department_en': 'Production', 'department_ar': 'الإنتاج',
       'job_title_en': 'Machine operator', 'job_title_ar': 'مشغل آلة', 'grade_en': 'Worker 1', 'grade_ar': None, 'grade_code': 'W1',
       'category_en': 'Monthly staff', 'category_ar': 'موظفون شهريون', 'location_en': 'Sohar factory', 'location_ar': 'مصنع صحار',
       'cost_centre_en': 'Production', 'cost_centre_ar': None, 'manager_name_en': 'Salim Al Harthy', 'manager_name_ar': 'سالم الحارثي',
       'manager_no': 'AACT-00001', 'profession_code': '8122', 'omani_only': False, 'created_by_name': 'Maryam Al Hinai'}
CAPS = {k: True for k in ['edit','salary_read','salary_write','salary_approve','bank_read','bank_write','bank_approve','docs_read','docs_write','docs_sensitive','history','exception_approve']}
EMP = {'employee': {'id': E2, 'entity_id': ENT, 'employee_no': 'AACT-00002', 'full_name_en': 'Ravi Kumar', 'full_name_ar': 'رافي كومار',
       'preferred_name': None, 'date_of_birth': '1992-07-01', 'gender': 'M', 'nationality': 'IN', 'nationality_en': 'Indian', 'nationality_ar': 'هندي',
       'marital_status': 'MARRIED', 'civil_number': 'RC998877', 'personal_email': None, 'work_email': 'ravi.k@aact.om', 'mobile': '+968 9123 4567',
       'alt_phone': None, 'address_line': 'Building 12, Falaj', 'city': 'Sohar', 'wilayat': 'Sohar', 'governorate': 'North Al Batinah',
       'address_country': 'OM', 'photo_path': None, 'original_join_date': '2026-08-21', 'join_date': '2026-08-21', 'probation_end_date': '2026-11-20',
       'confirmation_date': None, 'status': 'PROBATION', 'is_omani': False, 'entity_en': 'AACT Industries LLC', 'entity_ar': 'شركة أ.أ.س.ت للصناعات'},
       'access': 'FULL', 'current_assignment': ASG, 'assignments': [ASG], 'contracts': [], 'events': [
           {'id': 'ev1', 'event_type': 'JOIN', 'event_date': '2026-08-21', 'details': {}, 'created_at': '2026-08-21T06:00:00Z', 'created_by_name': 'Maryam Al Hinai'}],
       'emergency_contacts': [{'id': 'ec1', 'name': 'Sunita Kumar', 'relationship': 'Wife', 'phone': '+91 98100 00000', 'alt_phone': None, 'address': None, 'is_next_of_kin': True}],
       'omanisation_exceptions': [], 'linked_user': None, 'caps': CAPS}

def row(no, name, ar, nat, nat_en, dept, job, st, j, eid):
    return {'id': eid, 'employee_no': no, 'full_name_en': name, 'full_name_ar': ar, 'nationality': nat, 'is_omani': nat == 'OM',
            'nationality_en': nat_en, 'nationality_ar': None, 'status': st, 'join_date': j, 'department_en': dept, 'department_ar': None,
            'job_title_en': job, 'job_title_ar': None, 'location_en': 'Sohar factory', 'location_ar': 'مصنع صحار', 'manager_en': None,
            'manager_ar': None, 'mobile': None, 'work_email': None, 'photo_path': None, 'access': 'FULL'}

OMR = lambda t, o, tg=None: {'total': t, 'omani': o, 'expat': t - o, 'pct': round(100 * o / t, 2) if t else None, 'target_pct': tg,
                              'target_id': 't' if tg else None, 'target_source': 'Board resolution 4/2026' if tg else None, 'rule_basis': 'COMPANY_POLICY' if tg else None,
                              'omanis_needed': max(0, -(-tg * t // 100) - o) if tg else None, 'meets_target': (100 * o / t >= tg) if tg else None}

RPC = {
    'hr_me': ME,
    'hr_set_my_profile': ME,
    'hr_list_notifications': {'unread': 3, 'rows': [{'id': 'n1', 'kind': 'EXPIRY', 'priority': 'HIGH', 'title_en': 'Resident card expired — Ravi Kumar',
        'title_ar': 'انتهت صلاحية بطاقة المقيم — رافي كومار', 'body_en': 'AACT-00002: expired on 15/10/2026 (5 days ago).', 'body_ar': None,
        'link': '/employees/' + E2 + '?tab=documents', 'created_at': '2026-10-20T03:00:00Z', 'read_at': None}]},
    'hr_dashboard': {
        'workforce': {'headcount': 186, 'omani': 64, 'expat': 122, 'probation': 9, 'notice': 2, 'suspended': 0, 'joiners_30': 7, 'leavers_30': 3, 'probation_due_30': 2},
        'by_department': [{'department_id': 'd1', 'name_en': 'Production', 'name_ar': 'الإنتاج', 'total': 112, 'omani': 21},
                          {'department_id': 'd2', 'name_en': 'Maintenance', 'name_ar': 'الصيانة', 'total': 31, 'omani': 9},
                          {'department_id': 'd3', 'name_en': 'Human Resources', 'name_ar': 'الموارد البشرية', 'total': 8, 'omani': 8},
                          {'department_id': 'd4', 'name_en': 'Finance', 'name_ar': 'المالية', 'total': 11, 'omani': 7}],
        'by_nationality': [{'code': 'IN', 'name_en': 'Indian', 'name_ar': 'هندي', 'total': 71}, {'code': 'OM', 'name_en': 'Omani', 'name_ar': 'عُماني', 'total': 64},
                           {'code': 'BD', 'name_en': 'Bangladeshi', 'name_ar': 'بنغلاديشي', 'total': 33}, {'code': 'PK', 'name_en': 'Pakistani', 'name_ar': 'باكستاني', 'total': 18}],
        'probation_due': [{'id': E2, 'employee_no': 'AACT-00002', 'full_name_en': 'Ravi Kumar', 'full_name_ar': None, 'probation_end_date': '2026-11-20'}],
        'compliance': {'expired': 3, 'd30': 8, 'd60': 5, 'd90': 11, 'missing': 14, 'employees_missing': 9},
        'expiring_soon': EXPIRIES[:2],
        'omanisation': [{'entity_id': ENT, 'code': 'AACT', 'name_en': 'AACT Industries LLC', 'name_ar': 'شركة أ.أ.س.ت للصناعات', **OMR(180, 64, 40)}],
        'approvals': {'salary': 2, 'bank': 1, 'targets': 0}},
    'hr_list_employees': {'total': 3, 'rows': [
        row('AACT-00001', 'Salim Al Harthy', 'سالم الحارثي', 'OM', 'Omani', 'Production', 'Production manager', 'ACTIVE', '2020-01-05', E1),
        row('AACT-00002', 'Ravi Kumar', 'رافي كومار', 'IN', 'Indian', 'Production', 'Machine operator', 'PROBATION', '2026-08-21', E2),
        row('AACT-00007', 'Mohammed Rafiq', None, 'BD', 'Bangladeshi', 'Maintenance', 'Electrician', 'NOTICE', '2019-03-11', E3)]},
    'hr_get_employee': EMP,
    'hr_list_employee_documents': {'scope': 'ALL', 'documents': [
        {'id': 'doc1', 'employee_id': E2, 'doc_type': 'PASSPORT', 'doc_number': 'Z7654321', 'title': None, 'issue_date': '2026-10-19', 'expiry_date': '2036-10-18',
         'issuing_authority': 'Government of India', 'issue_place': None, 'version': 2, 'is_current': True, 'status': 'ACTIVE', 'file_path': E2 + '/PASSPORT/a.pdf',
         'file_name': 'passport.pdf', 'mime_type': 'application/pdf', 'file_size': 120000, 'verified_at': '2026-10-20T05:00:00Z', 'verified_by_name': 'Maryam Al Hinai',
         'uploaded_by_name': 'Ahmed', 'cancel_reason': None, 'notes': None, 'created_at': '2026-10-20T04:00:00Z', 'name_en': 'Passport', 'name_ar': 'جواز السفر',
         'category': 'IDENTITY', 'is_sensitive': False, 'has_expiry': True, 'days_left': 3650, 'bucket': 'LATER', 'supersedes_id': None},
        {'id': 'doc2', 'employee_id': E2, 'doc_type': 'RESIDENT_CARD', 'doc_number': 'RC998877', 'title': None, 'issue_date': None, 'expiry_date': '2026-10-15',
         'issuing_authority': 'Royal Oman Police', 'issue_place': None, 'version': 1, 'is_current': True, 'status': 'ACTIVE', 'file_path': None,
         'file_name': None, 'mime_type': None, 'file_size': None, 'verified_at': None, 'verified_by_name': None, 'uploaded_by_name': 'Ahmed',
         'cancel_reason': None, 'notes': None, 'created_at': '2026-10-20T04:00:00Z', 'name_en': 'Resident card', 'name_ar': 'بطاقة المقيم',
         'category': 'IMMIGRATION', 'is_sensitive': False, 'has_expiry': True, 'days_left': -5, 'bucket': 'EXPIRED', 'supersedes_id': None}],
        'checklist': [{'doc_type': 'RESIDENT_CARD', 'name_en': 'Resident card', 'name_ar': 'بطاقة المقيم', 'status': 'EXPIRED', 'expiry_date': '2026-10-15'},
                      {'doc_type': 'EMPLOYMENT_VISA', 'name_en': 'Employment visa', 'name_ar': 'تأشيرة العمل', 'status': 'MISSING', 'expiry_date': None},
                      {'doc_type': 'WORK_PERMIT', 'name_en': 'Work permit / labour clearance', 'name_ar': 'تصريح العمل', 'status': 'EXPIRING', 'expiry_date': '2026-11-04'},
                      {'doc_type': 'CONTRACT_COPY', 'name_en': 'Signed employment contract', 'name_ar': 'عقد العمل الموقع', 'status': 'OK', 'expiry_date': None}]},
    'hr_list_master': [],
    'hr_list_countries': [{'code': 'OM', 'name_en': 'Oman', 'name_ar': 'عُمان', 'nationality_en': 'Omani', 'nationality_ar': 'عُماني'},
                          {'code': 'IN', 'name_en': 'India', 'name_ar': 'الهند', 'nationality_en': 'Indian', 'nationality_ar': 'هندي'}],
    'hr_list_expiries': EXPIRIES,
    'hr_get_omanisation': {'entity_id': ENT, 'as_of': '2026-10-20', 'overall': OMR(180, 64, 40),
        'by_department': [{'id': 'd1', 'code': 'PROD', 'name_en': 'Production', 'name_ar': 'الإنتاج', **OMR(110, 21, 30)},
                          {'id': 'd3', 'code': 'HR', 'name_en': 'Human Resources', 'name_ar': 'الموارد البشرية', **OMR(8, 8, 100)},
                          {'id': 'd2', 'code': 'MNT', 'name_en': 'Maintenance', 'name_ar': 'الصيانة', **OMR(31, 9)}],
        'by_job_title': [{'id': 'j1', 'code': 'OPR', 'name_en': 'Machine operator', 'name_ar': 'مشغل آلة', 'profession_code': '8122', 'omani_only': False, **OMR(74, 12)},
                         {'id': 'j2', 'code': 'HRO', 'name_en': 'HR officer', 'name_ar': 'أخصائي موارد بشرية', 'profession_code': '2423', 'omani_only': True, **OMR(4, 3)}],
        'by_profession': [], 'omani_only_placements': [{'employee_id': E3, 'employee_no': 'AACT-00031', 'full_name_en': 'Ahmed Fathy', 'full_name_ar': None,
            'nationality': 'EG', 'job_title_en': 'HR officer', 'job_title_ar': None, 'exception_id': 'x', 'exception_reason': 'Cover while recruitment is open', 'exception_status': 'ACTIVE'}],
        'counting_basis': ''},
}

# Phase 2 (attendance & leave): real responses dumped from the seeded local database by e2e/gen_time_fixtures.py
RPC.update(json.loads((pathlib.Path(__file__).with_name('fixtures_time.json')).read_text(encoding='utf-8')))
# 1.9.0 management (MG) pay
RPC['hr_list_mg_access'] = [{'user_id': 'u1', 'name': 'Maryam Al Hinai', 'email': 'hr.manager@aact.om', 'member': True, 'is_me': True},
                            {'user_id': 'u2', 'name': 'Anil Sharma', 'email': 'cfo@aact.om', 'member': True, 'is_me': False},
                            {'user_id': 'u3', 'name': 'Salim Al Harthy', 'email': 'gm@aact.om', 'member': False, 'is_me': False}]
EMP['employee']['pay_group'] = 'MG'
EMP['caps']['pay_group_change'] = True
if isinstance(RPC.get('hr_list_payroll_runs'), list) and RPC['hr_list_payroll_runs']:
    for _r in RPC['hr_list_payroll_runs']:
        _r.setdefault('pay_group', 'NMG')
    _mg = dict(RPC['hr_list_payroll_runs'][0]); _mg.update({'id': 'run-mg', 'pay_group': 'MG', 'totals': {'employees': 6, 'earnings': 21450, 'deductions': 610.5, 'net': 20839.5, 'employer_cost': 1980.25}})
    RPC['hr_list_payroll_runs'].insert(1, _mg)

class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        p = self.path.split('?')[0]
        if '.' not in p.rsplit('/', 1)[-1]:
            self.path = '/index.html'
        return super().do_GET()

srv = http.server.ThreadingHTTPServer(('127.0.0.1', 4310), functools.partial(H, directory=DIST))
threading.Thread(target=srv.serve_forever, daemon=True).start()

SESSION = json.dumps({'access_token': 'x.y.z', 'refresh_token': 'r', 'token_type': 'bearer', 'expires_in': 3600,
                      'expires_at': int(time.time()) + 36000, 'user': {'id': 'u1', 'email': 'hr.manager@aact.om', 'aud': 'authenticated', 'role': 'authenticated'}})

problems = []
SCREENS = [('dashboard', '/'), ('employees', '/employees'), ('employee', f'/employees/{E2}'), ('documents', f'/employees/{E2}?tab=documents'),
           ('expiries', '/compliance/expiries'), ('omanisation', '/compliance/omanisation'), ('notifications', '/notifications'),
           ('approvals', '/approvals'), ('employee-time', f'/employees/{E2}?tab=time'),
           ('att-day', '/attendance'), ('att-month', '/attendance?tab=month'), ('att-employee', f'/attendance?tab=employee&emp={E2}'),
           ('att-corrections', '/attendance?tab=corrections'), ('overtime', '/overtime'),
           ('leave-requests', '/leave?tab=requests'), ('leave-calendar', '/leave?tab=calendar'),
           ('leave-balances', '/leave/admin?tab=balances'), ('leave-adjust', '/leave/admin?tab=adjust'), ('leave-types', '/leave/admin?tab=types'),
           ('leave-year', '/leave/admin?tab=year'), ('shifts', '/time/shifts'), ('calendar', '/time/calendar'), ('import', '/time/import'),
           ('periods', '/time/periods'), ('rules', '/time/rules'),
           ('payroll', '/payroll'), ('payroll-run', '/payroll/run-1'), ('payslip', '/payslips/slip-1'), ('my-payslips', '/payslips'),
           ('loans', '/payroll/loans'), ('pay-items', '/payroll/items'), ('settlements', '/payroll/settlements'),
           ('settlement', '/payroll/settlements/st-1'), ('gratuity', '/payroll/gratuity'), ('pay-rules', '/payroll/rules'),
           ('pay-setup', '/payroll/setup'), ('employee-pay', f'/employees/{E2}?tab=pay'),
           ('my-hr', '/me'), ('my-hr-details', '/me?tab=details'), ('my-hr-letters', '/me?tab=letters'), ('my-hr-requests', '/me?tab=requests'),
           ('my-hr-privacy', '/me?tab=privacy'), ('requests', '/requests'), ('requests-letters', '/requests?tab=letters'),
           ('requests-setup', '/requests?tab=setup'), ('letter', f"/letters/{RPC['hr_get_letter']['id']}"), ('team', '/team'),
           ('settings', '/settings'),
           ('verify', f"/verify?ref={RPC['hr_verify_letter']['ref_no']}&code=ABCDEFGHJKLM"),
           ('recruitment', '/recruitment'), ('rec-candidates', '/recruitment?tab=candidates'), ('rec-interviews', '/recruitment?tab=interviews'),
           ('rec-onboarding', '/recruitment?tab=onboarding'), ('rec-settings', '/recruitment?tab=settings'),
           ('requisition', f"/recruitment/req/{RPC['hr_get_requisition']['id']}"), ('application', f"/recruitment/app/{RPC['hr_get_application']['id']}"),
           ('offer', f"/recruitment/offer/{RPC['hr_get_offer']['id']}"), ('probation', '/probation'),
           ('performance', '/performance?tab=all'), ('perf-cycles', '/performance?tab=cycles'), ('perf-plans', '/performance?tab=plans'),
           ('review', f"/performance/review/{RPC['hr_get_perf_review']['id']}"),
           ('training', '/training'), ('training-expiring', '/training?tab=expiring'), ('training-gaps', '/training?tab=gaps'), ('training-courses', '/training?tab=courses'),
           ('discipline', '/discipline'), ('case', f"/discipline/{RPC['hr_get_case']['id']}"),
           ('assets', '/assets'), ('asset-items', '/assets?tab=items'), ('facilities', '/facilities'),
           ('injuries', '/injuries'), ('exits', '/exits'), ('exit', f"/exits/{RPC['hr_get_exit']['id']}"),
           ('executive', '/executive'), ('mol-report', '/reports/mol'), ('spf-report', '/reports/spf'), ('import-data', '/admin/import'),
           ('privacy', '/privacy'), ('privacy-notice', '/privacy?tab=notice'), ('privacy-consents', '/privacy?tab=consents'),
           ('privacy-requests', '/privacy?tab=requests'), ('privacy-breaches', '/privacy?tab=breaches'), ('privacy-register', '/privacy?tab=register'),
           ('privacy-retention', '/privacy?tab=retention'), ('privacy-settings', '/privacy?tab=settings')]

with sync_playwright() as p:
    br = p.chromium.launch()
    for lang in ('en', 'ar'):
        for w, h, tag in ((1440, 900, 'desktop'), (390, 844, 'phone')):
            ctx = br.new_context(viewport={'width': w, 'height': h}, device_scale_factor=1)
            ctx.add_init_script(f"localStorage.setItem('sb-mockref-auth-token', {json.dumps(SESSION)}); localStorage.setItem('aact-hrms-lang', '{lang}');")
            def handle(route):
                fn = route.request.url.split('/rpc/')[-1].split('?')[0]
                body = RPC.get(fn)
                if fn == 'hr_me':
                    body = {**ME, 'language': lang}
                if body is None:
                    problems.append(f'no fixture for {fn}')
                    body = {}
                route.fulfill(status=200, content_type='application/json', body=json.dumps(body))
            ctx.route('**/rest/v1/rpc/**', handle)
            ctx.route('**/auth/v1/**', lambda r: r.fulfill(status=200, content_type='application/json', body='{}'))
            page = ctx.new_page()
            page.on('pageerror', lambda e: problems.append(f'pageerror {e}'))
            page.on('console', lambda m: problems.append(f'console {m.text}') if m.type == 'error' else None)
            for name, url in SCREENS:
                page.goto('http://127.0.0.1:4310' + url)
                page.wait_for_load_state('networkidle')
                page.wait_for_timeout(250)
                sw = page.evaluate('document.documentElement.scrollWidth')
                if sw > w + 1:
                    problems.append(f'{lang}/{tag}/{name}: horizontal scroll {sw} > {w}')
                page.screenshot(path=str(OUT / f'{name}-{lang}-{tag}.png'), full_page=True)
            ctx.close()
    br.close()
srv.shutdown()
print('\n'.join(problems) if problems else 'NO PROBLEMS')
sys.exit(1 if problems else 0)
