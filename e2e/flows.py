"""Browser checks of real interactions (test harness, network faked):
  * answering a survey sends exactly the chosen answers; incomplete forms are not sent
  * posting a recognition from the colleague picker
  * typing a reason in a confirm dialog keeps it open (bug fixed in 1.14.0)
  * announcement editor (1.15.0): English -> Arabic translation fills the Arabic fields, Undo restores them,
    Arabic -> English works, a signed PDF is uploaded to hr-engage and sent with the announcement
Usage:  VITE_SUPABASE_URL=https://mockref.supabase.co VITE_SUPABASE_ANON_KEY=test npx vite build --outDir <dist> && python3 e2e/flows.py <dist>
"""
import json, sys, threading, time, http.server, functools, pathlib
from playwright.sync_api import sync_playwright
DIST = sys.argv[1]; FX = json.loads(pathlib.Path(__file__).with_name('fixtures_eng.json').read_text())
TIME = json.loads(pathlib.Path(__file__).with_name('fixtures_time.json').read_text())
ME = {'user_id':'u1','email':'emp@example.com','display_name':'Ravi Kumar','language':'en','is_active':True,'employee_id':FX['hr_engage_home']['caps']['employee_id'],
      'roles':['EMPLOYEE'],'permissions':[],'is_manager':False,'admin_exists':True,'settings':{},'entities':[],'unread_notifications':0,'mfa_state':'OK','mfa_enrolled':False}
calls = []
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_GET(self):
        if '.' not in self.path.split('?')[0].rsplit('/',1)[-1]: self.path='/index.html'
        return super().do_GET()
srv = http.server.ThreadingHTTPServer(('127.0.0.1',4311), functools.partial(H, directory=DIST)); threading.Thread(target=srv.serve_forever,daemon=True).start()
SESSION = json.dumps({'access_token':'x.y.z','refresh_token':'r','token_type':'bearer','expires_in':3600,'expires_at':int(time.time())+36000,'user':{'id':'u1','aud':'authenticated','role':'authenticated'}})
errors=[]
with sync_playwright() as p:
    br = p.chromium.launch(); ctx = br.new_context(viewport={'width':390,'height':844}, service_workers='block')
    ctx.add_init_script(f"localStorage.setItem('sb-mockref-auth-token', {json.dumps(SESSION)});")
    def handle(route):
        fn = route.request.url.split('/rpc/')[-1].split('?')[0]; body = route.request.post_data_json or {}
        calls.append((fn, body))
        out = {'hr_me': ME, 'hr_answer_survey': {'ok': True, 'answered': 4}, 'hr_list_notifications': {'items': [], 'unread': 0}, 'hr_list_my_tasks': {'count':0}}.get(fn, FX.get(fn, {}))
        if fn == 'hr_give_recognition':
            r = dict(FX['hr_engage_home']['recognitions'][1]); r['id']='new1'; r['message']=body['p']['message']; out = r
        route.fulfill(status=200, content_type='application/json', body=json.dumps(out))
    ctx.route('**/rest/v1/rpc/**', handle); ctx.route('**/auth/v1/**', lambda r: r.fulfill(status=200, content_type='application/json', body='{}'))
    pg = ctx.new_page(); pg.on('pageerror', lambda e: errors.append(str(e)))
    sid = FX['hr_get_survey']['id']
    pg.goto(f'http://127.0.0.1:4311/engage/survey/{sid}'); pg.wait_for_load_state('networkidle')
    # submit with nothing → required warning, no request
    pg.get_by_role('button', name='Send answers').click(); pg.wait_for_timeout(300)
    assert not any(c[0]=='hr_answer_survey' for c in calls), 'sent while incomplete'
    pg.locator('#sq-q1 .eg-scale-opt').nth(3).click()
    pg.locator('#sq-q2 .eg-scale-opt').nth(4).click()
    pg.locator('#sq-q3 .eg-choice').nth(0).click()
    pg.locator('#sq-q4 textarea').fill('  Shaded parking  ')
    pg.get_by_role('button', name='Send answers').click(); pg.wait_for_timeout(500)
    sent = [c for c in calls if c[0]=='hr_answer_survey']
    assert sent and sent[-1][1]['p_answers'] == {'q1':4,'q2':5,'q3':0,'q4':'Shaded parking'}, sent
    assert pg.get_by_text('Thank you — your answers were sent.').first.is_visible()
    # recognition
    pg.goto('http://127.0.0.1:4311/engage?tab=recognition'); pg.wait_for_load_state('networkidle')
    pg.get_by_role('button', name='Recognise a colleague').last.click()
    pg.get_by_placeholder('Type a name or employee number').click(); pg.wait_for_timeout(600)
    pg.locator('.eg-pick-list button').first.click()
    pg.locator('dialog textarea').fill('Great help with the audit')
    pg.get_by_role('button', name='Post recognition').click(); pg.wait_for_timeout(500)
    g = [c for c in calls if c[0]=='hr_give_recognition']
    assert g and g[-1][1]['p']['message']=='Great help with the audit' and g[-1][1]['p']['employee_id'], g
    assert pg.get_by_text('Great help with the audit').first.is_visible()
    # regression (1.14.0): typing a reason in a confirm dialog must not close it
    ctx2 = br.new_context(service_workers='block')
    ctx2.add_init_script(f"localStorage.setItem('sb-mockref-auth-token', {json.dumps(SESSION)});")
    HRM = {**ME, 'employee_id': None, 'roles': ['HR_MANAGER'], 'permissions': ['ATT_READ', 'RULES_PROPOSE', 'RULES_APPROVE']}
    ctx2.route('**/rest/v1/rpc/**', lambda r: r.fulfill(status=200, content_type='application/json',
               body=json.dumps({'hr_me': HRM}.get(r.request.url.split('/rpc/')[-1].split('?')[0], TIME.get(r.request.url.split('/rpc/')[-1].split('?')[0], {})))))
    ctx2.route('**/auth/v1/**', lambda r: r.fulfill(status=200, content_type='application/json', body='{}'))
    pg2 = ctx2.new_page(); pg2.on('pageerror', lambda e: errors.append(str(e)))
    pg2.goto('http://127.0.0.1:4311/time/rules'); pg2.wait_for_load_state('networkidle')
    pg2.get_by_role('button', name='Reject').first.click(); pg2.wait_for_timeout(300)
    pg2.locator('dialog[open] textarea').type('Not agreed yet', delay=20); pg2.wait_for_timeout(400)
    assert pg2.locator('dialog[open]').count() == 1, 'dialog closed while typing'

    # 1.15.0: announcement editor — translation and signed PDF
    ctx3 = br.new_context(viewport={'width': 1280, 'height': 900}, service_workers='block')
    ctx3.add_init_script(f"localStorage.setItem('sb-mockref-auth-token', {json.dumps(SESSION)});")
    ENT = {'id': FX['hr_list_announcements'][0].get('entity_id') or 'e1', 'code': 'DEMO', 'name_en': 'Demo Tiles LLC', 'name_ar': 'شركة ديمو للبلاط'}
    HRO = {**ME, 'roles': ['HR_OFFICER'], 'permissions': ['ENGAGE_MANAGE'], 'entities': [ENT]}
    tr_calls, up_calls, saved = [], [], []
    def handle3(route):
        fn = route.request.url.split('/rpc/')[-1].split('?')[0]; body = route.request.post_data_json or {}
        if fn == 'hr_save_announcement':
            saved.append(body['p']); a = dict(FX['hr_list_announcements'][0]); a.update(body['p']); a['id'] = 'new-ann'; a['status'] = 'DRAFT'
            route.fulfill(status=200, content_type='application/json', body=json.dumps(a)); return
        out = {'hr_me': HRO, 'hr_list_notifications': {'items': [], 'unread': 0}, 'hr_list_my_tasks': {'count': 0},
               'hr_list_master': [{'id': 'd1', 'code': 'PROD', 'name_en': 'Production', 'name_ar': 'الإنتاج', 'is_active': True}]}.get(fn, FX.get(fn, {}))
        route.fulfill(status=200, content_type='application/json', body=json.dumps(out))
    def handle_tr(route):
        if route.request.method == 'OPTIONS': route.fulfill(status=200, body='ok'); return
        b = route.request.post_data_json; tr_calls.append(b)
        out = {'title': 'إجازة العيد الوطني', 'body': 'سيغلق المكتب والمصنع بمناسبة إجازة العيد الوطني.'} if b['direction'] == 'en-ar' \
              else {'title': 'National Day holiday', 'body': 'The office and plant will be closed for the National Day holiday.'}
        route.fulfill(status=200, content_type='application/json', body=json.dumps({**out, 'model': 'test'}), headers={'Access-Control-Allow-Origin': '*'})
    def handle_up(route):
        if route.request.method == 'OPTIONS': route.fulfill(status=200, body='ok', headers={'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*'}); return
        up_calls.append(route.request.url)
        route.fulfill(status=200, content_type='application/json', body=json.dumps({'Key': 'hr-engage/' + route.request.url.split('/hr-engage/')[-1], 'Id': 'x'}),
                      headers={'Access-Control-Allow-Origin': '*'})
    ctx3.route('**/rest/v1/rpc/**', handle3); ctx3.route('**/auth/v1/**', lambda r: r.fulfill(status=200, content_type='application/json', body='{}'))
    ctx3.route('**/functions/v1/translate', handle_tr); ctx3.route('**/storage/v1/object/hr-engage/**', handle_up)
    pg3 = ctx3.new_page(); pg3.on('pageerror', lambda e: errors.append(str(e)))
    pg3.goto('http://127.0.0.1:4311/engage/admin'); pg3.wait_for_load_state('networkidle')
    pg3.get_by_role('button', name='New announcement').click(); pg3.wait_for_timeout(300)
    dlg = pg3.locator('dialog[open]')
    assert dlg.get_by_role('button', name='English → Arabic').is_disabled(), 'translate enabled with no English text'
    dlg.get_by_label('Title (English)').fill('National Day holiday')
    dlg.get_by_label('Message (English)').fill('The office and plant will be closed for the National Day holiday.')
    dlg.get_by_role('button', name='English → Arabic').click(); pg3.wait_for_timeout(500)
    assert tr_calls and tr_calls[-1] == {'direction': 'en-ar', 'title': 'National Day holiday', 'body': 'The office and plant will be closed for the National Day holiday.'}, tr_calls
    assert dlg.get_by_label('Title (Arabic)').input_value() == 'إجازة العيد الوطني'
    assert dlg.get_by_label('Message (Arabic)').input_value().startswith('سيغلق المكتب')
    pg3.screenshot(path='/tmp/claude-0/-home-claude/7be0054e-dbd1-5fae-b93a-fc6575da434a/scratchpad/flow-translate.png')
    dlg.get_by_role('button', name='Undo').click(); pg3.wait_for_timeout(200)
    assert dlg.get_by_label('Title (Arabic)').input_value() == '', 'undo did not restore'
    dlg.get_by_role('button', name='English → Arabic').click(); pg3.wait_for_timeout(500)
    dlg.get_by_label('Title (English)').fill('')
    dlg.get_by_role('button', name='Arabic → English').click(); pg3.wait_for_timeout(500)
    assert tr_calls[-1]['direction'] == 'ar-en' and dlg.get_by_label('Title (English)').input_value() == 'National Day holiday', tr_calls[-1]
    # a non-PDF is refused without uploading; a PDF is uploaded
    fi = dlg.locator('input[type=file]')
    fi.set_input_files(files=[{'name': 'photo.png', 'mimeType': 'image/png', 'buffer': b'png'}]); pg3.wait_for_timeout(300)
    assert not up_calls, 'non-PDF uploaded'
    fi.set_input_files(files=[{'name': 'Circular 15-2026 signed.pdf', 'mimeType': 'application/pdf', 'buffer': b'%PDF-1.4 test'}]); pg3.wait_for_timeout(600)
    assert len(up_calls) == 1 and '/hr-engage/ann/' in up_calls[0], up_calls
    assert dlg.get_by_text('Circular 15-2026 signed.pdf').is_visible()
    pg3.screenshot(path='/tmp/claude-0/-home-claude/7be0054e-dbd1-5fae-b93a-fc6575da434a/scratchpad/flow-pdf.png')
    dlg.get_by_role('button', name='Save draft').click(); pg3.wait_for_timeout(500)
    assert saved and saved[-1]['attachment_name'] == 'Circular 15-2026 signed.pdf' and saved[-1]['attachment_bytes'] == 13 \
        and saved[-1]['attachment_path'].startswith('ann/') and saved[-1]['title_ar'] == 'إجازة العيد الوطني', saved[-1]
    br.close()
srv.shutdown()
print('ERRORS', errors) if errors else print('FLOW OK')
