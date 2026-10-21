#!/usr/bin/env python3
"""Generates supabase/seed.sql — DUMMY data for local development and testing only.
Run:  python scripts/gen-seed.py   (output is deterministic; commit the generated seed.sql)"""
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "supabase" / "seed.sql"
PASSWORD = "Demo@AACT2026"

USERS = [  # email, display name, roles, linked employee row
    ("admin@aact.test",      "Demo Administrator", ["SUPER_ADMIN"],            None),
    ("hr.manager@aact.test", "Demo HR Manager",    ["HR_MANAGER"],             None),
    ("hr.officer@aact.test", "Demo HR Officer",    ["HR_OFFICER"],             None),
    ("finance@aact.test",    "Demo Finance",       ["FINANCE"],                None),
    ("auditor@aact.test",    "Demo Auditor",       ["AUDITOR"],                None),
    ("manager@aact.test",    "Salim Al Harthy",    ["MANAGER", "EMPLOYEE"],    1),
    ("employee@aact.test",   "Ravi Kumar",         ["EMPLOYEE"],               17),
]

LOCATIONS = [("SOHAR", "Sohar factory", "مصنع صحار", "FACTORY"), ("MCT", "Muscat head office", "المكتب الرئيسي - مسقط", "OFFICE"),
             ("WH1", "Sohar warehouse", "مستودع صحار", "WAREHOUSE")]
COST_CENTRES = [("CC100", "Production", "الإنتاج"), ("CC200", "Administration", "الإدارة"), ("CC300", "Maintenance", "الصيانة"),
                ("CC400", "Sales and marketing", "المبيعات والتسويق"), ("CC500", "Warehouse and logistics", "المستودعات والخدمات اللوجستية")]
DEPARTMENTS = [  # code, en, ar, parent, cost centre
    ("OPS", "Operations", "العمليات", None, "CC100"), ("PROD", "Production", "الإنتاج", "OPS", "CC100"),
    ("MAINT", "Maintenance", "الصيانة", "OPS", "CC300"), ("QC", "Quality control", "مراقبة الجودة", "OPS", "CC100"),
    ("WH", "Warehouse and logistics", "المستودعات والخدمات اللوجستية", "OPS", "CC500"), ("HR", "Human resources", "الموارد البشرية", None, "CC200"),
    ("FIN", "Finance", "المالية", None, "CC200"), ("SALES", "Sales", "المبيعات", None, "CC400"), ("ADMIN", "Administration", "الشؤون الإدارية", None, "CC200")]
GRADES = [("W1", "Worker I", 1, 150, 300), ("W2", "Worker II", 2, 250, 450), ("S1", "Staff I", 3, 400, 900),
          ("S2", "Supervisor", 4, 700, 1300), ("M1", "Manager I", 5, 1200, 2500), ("M2", "Manager II", 6, 2000, 3500)]
JOBS = [  # code, en, ar, omani_only
    ("OPSMGR", "Operations manager", "مدير العمليات", False), ("HRMGR", "HR manager", "مدير الموارد البشرية", False),
    ("FINMGR", "Finance manager", "مدير المالية", False), ("SLSMGR", "Sales manager", "مدير المبيعات", False),
    ("PSUP", "Production supervisor", "مشرف الإنتاج", False), ("MENG", "Maintenance engineer", "مهندس صيانة", False),
    ("QCSUP", "Quality control supervisor", "مشرف مراقبة الجودة", False), ("STK", "Storekeeper", "أمين مخزن", False),
    ("HRO", "HR officer", "أخصائي موارد بشرية", True), ("ACC", "Accountant", "محاسب", False),
    ("SLSE", "Sales executive", "مندوب مبيعات", False), ("ADM", "Administrative assistant", "مساعد إداري", False),
    ("OPR", "Machine operator", "مشغل آلة", False), ("HLP", "Production helper", "عامل إنتاج", False),
    ("MTECH", "Maintenance technician", "فني صيانة", False), ("QCI", "Quality inspector", "مفتش جودة", False),
    ("FLD", "Forklift operator", "مشغل رافعة شوكية", False), ("DRV", "Driver", "سائق", False)]
CATEGORIES = [("STAFF", "Monthly staff", "موظفون شهريون", True), ("WRK", "Workers", "العمال", True),
              ("TRN", "Trainees (not counted)", "متدربون (غير محتسبين)", False)]

# no, name_en, name_ar, nat, gender, dept, job, grade, cat, manager_no, special
P = [
 (1, "Salim Al Harthy", "سالم الحارثي", "OM", "M", "OPS", "OPSMGR", "M2", "STAFF", None, ""),
 (2, "Fatma Al Balushi", "فاطمة البلوشي", "OM", "F", "HR", "HRMGR", "M1", "STAFF", None, ""),
 (3, "Anil Sharma", None, "IN", "M", "FIN", "FINMGR", "M1", "STAFF", None, ""),
 (4, "Khalid Al Hinai", "خالد الهنائي", "OM", "M", "SALES", "SLSMGR", "M1", "STAFF", None, ""),
 (5, "Suresh Nair", None, "IN", "M", "PROD", "PSUP", "S2", "STAFF", 1, ""),
 (6, "Hamad Al Rawahi", "حمد الرواحي", "OM", "M", "PROD", "PSUP", "S2", "STAFF", 1, ""),
 (7, "Rajesh Pillai", None, "IN", "M", "MAINT", "MENG", "S2", "STAFF", 1, ""),
 (8, "Maryam Al Hinai", "مريم الهنائي", "OM", "F", "QC", "QCSUP", "S1", "STAFF", 1, ""),
 (9, "Imran Khan", None, "PK", "M", "WH", "STK", "S1", "STAFF", 1, ""),
 (10, "Aisha Al Saadi", "عائشة السعدي", "OM", "F", "HR", "HRO", "S1", "STAFF", 2, ""),
 (11, "Shaima Al Busaidi", "شيماء البوسعيدي", "OM", "F", "HR", "HRO", "S1", "STAFF", 2, "PROBATION PENDING_SALARY"),
 (12, "Vijay Menon", None, "IN", "M", "FIN", "ACC", "S1", "STAFF", 3, "PENDING_BANK"),
 (13, "Muna Al Maskari", "منى المسكري", "OM", "F", "FIN", "ACC", "S1", "STAFF", 3, ""),
 (14, "Faisal Al Kindi", "فيصل الكندي", "OM", "M", "SALES", "SLSE", "S1", "STAFF", 4, "PENDING_INCREMENT"),
 (15, "Mahmoud Hassan", None, "EG", "M", "SALES", "SLSE", "S1", "STAFF", 4, ""),
 (16, "Huda Al Abri", "هدى العبري", "OM", "F", "ADMIN", "ADM", "W2", "STAFF", 2, ""),
 (17, "Ravi Kumar", None, "IN", "M", "PROD", "OPR", "W1", "WRK", 5, ""),
]
workers = [
 ("Deepak Singh", "IN", "OPR", 5), ("Rahim Uddin", "BD", "HLP", 5), ("Ram Thapa", "NP", "HLP", 5), ("Asif Ali", "PK", "OPR", 5),
 ("Ahmed Al Amri", "OM", "OPR", 6), ("Kamal Hossain", "BD", "HLP", 6), ("Bikash Gurung", "NP", "OPR", 6), ("Manoj Thomas", "IN", "OPR", 6),
 ("Said Al Shukaili", "OM", "OPR", 5), ("Jamal Mia", "BD", "HLP", 5), ("Sanjay Patel", "IN", "OPR", 6), ("Bilal Ahmed", "PK", "HLP", 6),
 ("Mohammed Al Zadjali", "OM", "OPR", 5), ("Hari Shrestha", "NP", "HLP", 5), ("Sunil Yadav", "IN", "OPR", 6), ("Nazrul Islam", "BD", "HLP", 6),
 ("Hilal Al Maskari", "OM", "OPR", 5), ("Usman Tariq", "PK", "OPR", 6), ("Prakash Rai", "NP", "HLP", 5), ("Sultan Al Saadi", "OM", "OPR", 6),
 ("Mohan Lal", "IN", "HLP", 5), ("Shahid Hussain", "PK", "OPR", 6), ("Yaqoob Al Balushi", "OM", "OPR", 5),
 ("Rashid Al Hinai", "OM", "OPR", 6),
]
OMANI_AR = {"Ahmed Al Amri": "أحمد العامري", "Said Al Shukaili": "سعيد الشكيلي", "Mohammed Al Zadjali": "محمد الزدجالي",
            "Hilal Al Maskari": "هلال المسكري", "Sultan Al Saadi": "سلطان السعدي", "Yaqoob Al Balushi": "يعقوب البلوشي", "Rashid Al Hinai": "راشد الهنائي",
            "Nasser Al Kindi": "ناصر الكندي", "Zainab Al Rawahi": "زينب الرواحي", "Badar Al Harthy": "بدر الحارثي",
            "Yousuf Al Amri": "يوسف العامري", "Badar Al Shukaili": "بدر الشكيلي", "Asma Al Zadjali": "أسماء الزدجالي",
            "Nasser Al Zadjali": "ناصر الزدجالي", "Khamis Al Abri": "خميس العبري"}
n = 18
for name, nat, job, mgr in workers:
    P.append((n, name, OMANI_AR.get(name), nat, "M", "PROD", job, "W1", "WRK", mgr, "")); n += 1
for name, nat, g in [("Nuwan Perera", "LK", "M"), ("Tarek Fouad", "EG", "M"), ("Nasser Al Kindi", "OM", "M"),
                     ("Shoaib Malik", "PK", "M"), ("Ajith Kumar", "IN", "M"), ("Khamis Al Abri", "OM", "M")]:
    P.append((n, name, OMANI_AR.get(name), nat, g, "MAINT", "MTECH", "W2", "WRK", 7, "")); n += 1
for name, nat, g in [("Zainab Al Rawahi", "OM", "F"), ("Kiran Reddy", "IN", "M"), ("Maria Reyes", "PH", "F"), ("Badar Al Harthy", "OM", "M")]:
    P.append((n, name, OMANI_AR.get(name), nat, g, "QC", "QCI", "W2", "WRK", 8, "")); n += 1
for name, nat, job in [("Abdul Karim", "BD", "FLD"), ("Dil Bahadur", "NP", "FLD"), ("Nasser Al Zadjali", "OM", "DRV"), ("Zafar Iqbal", "PK", "DRV")]:
    P.append((n, name, OMANI_AR.get(name), nat, "M", "WH", job, "W1", "WRK", 9, "")); n += 1
for name, dept, job, mgr, g in [("Yousuf Al Amri", "PROD", "OPR", 5, "M"), ("Badar Al Shukaili", "PROD", "OPR", 6, "M"), ("Asma Al Zadjali", "QC", "QCI", 8, "F")]:
    P.append((n, name, OMANI_AR[name], "OM", g, dept, job, None, "TRN", mgr, "PROBATION TRAINEE")); n += 1
P.append((n, "Arun Das", None, "IN", "M", "PROD", "OPR", "W1", "WRK", 6, "NOTICE")); n += 1
P.append((n, "Jose Santos", None, "PH", "M", "WH", "DRV", "W1", "WRK", 9, "SEPARATE")); n += 1
assert len(P) == 60 and [x[0] for x in P] == list(range(1, 61)), len(P)

BANKS = [("Bank Muscat", "BMUSOMRX", "027"), ("Bank Dhofar", "BDOFOMRU", "028"), ("National Bank of Oman", "NBOMOMRX", "018"),
         ("Sohar International", "BSHROMRU", "029"), ("HSBC Oman", "BBMEOMRX", "037")]
PASS_OFF = [1500, 900, 2100, 45, 1200, 3000, 700, -5, 1800, 2500, 1100, 160]
EXP_OFF = [-12, 8, 19, 27, 41, 55, 66, 83, 120, 200, 310, 450, 600, 720, 900, 365]
CID_OFF = [1400, 25, 900, 2000, 70, 1600, -20, 1100]
CON_OFF = [75, 20, 300, 500, 150, 640, 45, 400]

def q(v):
    if v is None: return "null"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return str(v)
    return "'" + str(v).replace("'", "''") + "'"

rows = []
expat_i = om_i = 0
for (no, en, ar, nat, g, dept, job, grade, cat, mgr, special) in P:
    om = nat == "OM"
    if "PROBATION" in special:
        join = f"(current_date - {35 + no % 40})"; dob = f"date '{2002 + no % 3}-{no % 12 + 1:02d}-{no % 27 + 1:02d}'" if "TRAINEE" in special else f"date '{1990 + no % 8}-{no % 12 + 1:02d}-{no % 27 + 1:02d}'"
    elif no <= 4:
        join = f"date '{2012 + no}-{(no * 3) % 12 + 1:02d}-01'"; dob = f"date '{1968 + no * 2}-{no % 12 + 1:02d}-{no % 27 + 1:02d}'"
    else:
        join = f"date '{2013 + (no * 5) % 13}-{(no * 7) % 12 + 1:02d}-{(no * 3) % 27 + 1:02d}'"; dob = f"date '{1972 + (no * 7) % 26}-{no % 12 + 1:02d}-{no % 27 + 1:02d}'"
    staff = cat == "STAFF"
    email = (en.lower().replace(" al ", ".al").replace(" ", ".") + "@aact.test") if staff else None
    civil = (str(20000000 + no * 1301) if om else str(60000000 + no * 1301))
    mobile = f"+968 9{(no * 7351) % 10000000:07d}"
    if om:
        cid = None if om_i % 7 == 6 else CID_OFF[om_i % len(CID_OFF)]; rc = visa = wp = None; om_i += 1
        con = None
    else:
        e = EXP_OFF; rc = e[expat_i % len(e)]; visa = None if expat_i % 9 == 4 else e[(expat_i + 3) % len(e)]
        wp = None if expat_i % 11 == 7 else e[(expat_i + 5) % len(e)]; cid = None
        con = CON_OFF[expat_i % len(CON_OFF)]; expat_i += 1
    pp = PASS_OFF[no % len(PASS_OFF)]
    med = EXP_OFF[(no * 5) % len(EXP_OFF)] if (not om and no % 4 == 0) else None
    lic = (40 if no % 2 == 0 else 500) if job in ("DRV", "FLD") else None
    contract_doc = no % 6 != 0
    lo, hi = next((x[3], x[4]) for x in GRADES if x[0] == (grade or "W1"))
    frac = ((no * 37) % 100) / 100 * 0.8 + 0.1
    basic = round(lo + (hi - lo) * frac) if grade else 120
    if no == 5: basic = 1350  # above S2 band → shows the grade-band warning
    housing = round(basic * 0.25)
    transport = 150 if grade in ("M1", "M2") else 50 if staff else 20
    bank = None if (no % 5 == 0 or "TRAINEE" in special) else BANKS[no % len(BANKS)]
    loc = "MCT" if dept in ("HR", "FIN", "SALES", "ADMIN") else ("WH1" if dept == "WH" else "SOHAR")
    rows.append("(" + ", ".join([
        q(no), q(en), q(ar), q(nat), q(g), q(dept), q(job), q(grade), q(cat), q(mgr), q(special), join, dob,
        q(email), q(civil), q(mobile), q(loc), q(pp), q(cid), q(rc), q(visa), q(wp), q(med), q(lic), q(con), q(contract_doc),
        q(basic), q(housing), q(transport),
        q(bank[0] if bank else None), q(bank[1] if bank else None), q(bank[2] if bank else None)]) + ")")

def vals(items): return ",\n  ".join(items)

sql = f"""-- =============================================================================
-- AACT HRMS — DUMMY DATA for local development and testing ONLY.
-- Generated by scripts/gen-seed.py — do not edit by hand; edit the generator and re-run it.
-- Loaded automatically by `npx supabase db reset` on the laptop.
-- NEVER run this on the company (production) server.
--
-- Demo logins (password for all: {PASSWORD}):
""" + "".join(f"--   {u[0]:<22} {', '.join(u[2])}\n" for u in USERS) + f"""-- Everything else (people, numbers, documents, decisions) is fictitious.
-- =============================================================================

do $$
begin
  if exists (select 1 from hr.employees) then
    raise exception 'seed.sql: the database already has employees. Dummy data is only for an empty local database.';
  end if;
end $$;

-- ---------------------------------------------------------------- demo logins
create temp table seed_users(email text, display_name text, roles text[], emp_no int, id uuid default gen_random_uuid());
insert into seed_users(email, display_name, roles, emp_no) values
  {vals(f"({q(u[0])}, {q(u[1])}, array[{', '.join(q(r) for r in u[2])}]::text[], {q(u[3])})" for u in USERS)};

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
       extensions.crypt({q(PASSWORD)}, extensions.gen_salt('bf')), now(),
       '{{"provider":"email","providers":["email"]}}'::jsonb, jsonb_build_object('full_name', display_name), now(), now(),
       '', '', '', ''
from seed_users;

insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select id::text, id, jsonb_build_object('sub', id::text, 'email', email, 'email_verified', true), 'email', now(), now(), now()
from seed_users;

-- ---------------------------------------------------------------- reference data
create temp table seed_people(
  no int primary key, name_en text, name_ar text, nat text, gender text, dept text, job text, grade text, cat text,
  mgr int, special text, join_date date, dob date, email text, civil text, mobile text, loc text,
  pass_off int, cid_off int, rc_off int, visa_off int, wp_off int, med_off int, lic_off int, contract_off int,
  contract_doc boolean, basic numeric, housing numeric, transport numeric, bank text, swift text, bank_code text,
  emp_id uuid);
insert into seed_people(no, name_en, name_ar, nat, gender, dept, job, grade, cat, mgr, special, join_date, dob, email, civil,
  mobile, loc, pass_off, cid_off, rc_off, visa_off, wp_off, med_off, lic_off, contract_off, contract_doc, basic, housing,
  transport, bank, swift, bank_code) values
  {vals(rows)};

create temp table seed_ids(k text primary key, id uuid);

do $seed$
declare
  v jsonb; r record; d record; u record; v_ent uuid; v_id uuid; v_rev uuid; v_doc uuid; i int := 0;
  admin uuid; hrm uuid; hro uuid; fin uuid; boss uuid;
begin
  select id into admin from seed_users where email = 'admin@aact.test';
  select id into hrm   from seed_users where email = 'hr.manager@aact.test';
  select id into hro   from seed_users where email = 'hr.officer@aact.test';
  select id into fin   from seed_users where email = 'finance@aact.test';

  -- roles (through the same API the app uses, so the audit trail is real).
  -- If a real administrator already exists (e.g. the cloud test project), that administrator grants the demo roles.
  select ur.user_id into boss from hr.user_roles ur
   where ur.role_code = 'SUPER_ADMIN' and ur.revoked_at is null and ur.user_id not in (select id from seed_users)
   order by ur.granted_at limit 1;
  if boss is null then
    perform set_config('request.jwt.claim.sub', admin::text, false);
    perform public.hr_claim_first_admin();
    boss := admin;
  end if;
  perform set_config('request.jwt.claim.sub', boss::text, false);
  for u in select * from seed_users where id <> boss loop
    perform public.hr_set_user_roles(u.id, u.roles);
  end loop;

  -- organisation (HR manager)
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  v := public.hr_save_master('entity', '{{"code":"AACT","name_en":"AACT Industries LLC (DEMO)","name_ar":"شركة أ.أ.س.ت للصناعات (تجريبي)","cr_number":"0000000"}}');
  v_ent := (v->>'id')::uuid;
"""
for code, en, ar, typ in LOCATIONS:
    sql += f"  insert into seed_ids values ('loc:{code}', (public.hr_save_master('location', jsonb_build_object('entity_id', v_ent, 'code', {q(code)}, 'name_en', {q(en)}, 'name_ar', {q(ar)}, 'location_type', {q(typ)}))->>'id')::uuid);\n"
for code, en, ar in COST_CENTRES:
    sql += f"  insert into seed_ids values ('cc:{code}', (public.hr_save_master('cost_centre', jsonb_build_object('entity_id', v_ent, 'code', {q(code)}, 'name_en', {q(en)}, 'name_ar', {q(ar)}))->>'id')::uuid);\n"
for code, en, ar, parent, cc in DEPARTMENTS:
    par = f"(select id from seed_ids where k = 'dep:{parent}')" if parent else "null"
    sql += f"  insert into seed_ids values ('dep:{code}', (public.hr_save_master('department', jsonb_build_object('entity_id', v_ent, 'code', {q(code)}, 'name_en', {q(en)}, 'name_ar', {q(ar)}, 'parent_id', {par}, 'cost_centre_id', (select id from seed_ids where k = 'cc:{cc}')))->>'id')::uuid);\n"
for code, en, lvl, lo, hi in GRADES:
    sql += f"  insert into seed_ids values ('gr:{code}', (public.hr_save_master('grade', jsonb_build_object('entity_id', v_ent, 'code', {q(code)}, 'name_en', {q(en)}, 'level', {lvl}, 'min_basic', {lo}, 'max_basic', {hi}))->>'id')::uuid);\n"
for code, en, ar, oo in JOBS:
    extra = ", 'omani_only', true, 'omani_only_source', 'DUMMY DATA - replace with the applicable Ministerial decision'" if oo else ""
    sql += f"  insert into seed_ids values ('job:{code}', (public.hr_save_master('job_title', jsonb_build_object('entity_id', v_ent, 'code', {q(code)}, 'name_en', {q(en)}, 'name_ar', {q(ar)}{extra}))->>'id')::uuid);\n"
for code, en, ar, counts in CATEGORIES:
    sql += f"  insert into seed_ids values ('cat:{code}', (public.hr_save_master('category', jsonb_build_object('entity_id', v_ent, 'code', {q(code)}, 'name_en', {q(en)}, 'name_ar', {q(ar)}, 'counts_for_omanisation', {q(counts)}))->>'id')::uuid);\n"

sql += """
  -- employees (HR officer), managers first
  perform set_config('request.jwt.claim.sub', hro::text, false);
  for r in select * from seed_people order by no loop
    v := public.hr_save_employee(jsonb_strip_nulls(jsonb_build_object(
      'entity_id', v_ent, 'full_name_en', r.name_en, 'full_name_ar', r.name_ar, 'nationality', r.nat, 'gender', r.gender,
      'date_of_birth', r.dob::text, 'join_date', r.join_date::text, 'civil_number', r.civil, 'work_email', r.email,
      'mobile', r.mobile, 'marital_status', case when r.no % 3 = 0 then 'SINGLE' else 'MARRIED' end,
      'probation_end_date', case when r.special like '%PROBATION%' then (r.join_date + 90)::text end,
      'assignment', jsonb_strip_nulls(jsonb_build_object(
        'department_id', (select id from seed_ids where k = 'dep:' || r.dept),
        'job_title_id',  (select id from seed_ids where k = 'job:' || r.job),
        'grade_id',      (select id from seed_ids where k = 'gr:' || r.grade),
        'category_id',   (select id from seed_ids where k = 'cat:' || r.cat),
        'location_id',   (select id from seed_ids where k = 'loc:' || r.loc),
        'manager_id',    (select emp_id from seed_people m where m.no = r.mgr),
        'employment_type', case when r.cat = 'TRN' then 'TRAINEE' else 'FULL_TIME' end)))));
    update seed_people set emp_id = (v->'employee'->>'id')::uuid where no = r.no;
  end loop;

  -- contracts
  for r in select * from seed_people order by no loop
    if r.nat = 'OM' then
      perform public.hr_save_contract(r.emp_id, jsonb_build_object('contract_type', 'INDEFINITE', 'start_date', r.join_date::text,
              'probation_days', 90, 'notice_days', case when r.grade like 'M%' then 90 else 30 end));
    else
      perform public.hr_save_contract(r.emp_id, jsonb_build_object('contract_type', 'FIXED_TERM',
              'start_date', greatest(r.join_date, current_date + r.contract_off - 730)::text,
              'end_date', (current_date + r.contract_off)::text, 'probation_days', 90, 'notice_days', 30));
    end if;
  end loop;

  -- documents (metadata only; no files are attached in dummy data)
  for r in select * from seed_people order by no loop
    v := public.hr_save_document(r.emp_id, jsonb_build_object('doc_type', 'PASSPORT', 'doc_number', 'DP' || lpad((r.no * 48271 % 9000000 + 1000000)::text, 7, '0'),
           'issue_date', (current_date + r.pass_off - 3650)::text, 'expiry_date', (current_date + r.pass_off)::text,
           'issuing_authority', 'Passport office (dummy)'));
    if r.no % 3 <> 0 then insert into seed_ids values ('verify:' || r.no, (v->>'id')::uuid); end if;
    if r.cid_off is not null then
      perform public.hr_save_document(r.emp_id, jsonb_build_object('doc_type', 'CIVIL_ID', 'doc_number', r.civil,
              'expiry_date', (current_date + r.cid_off)::text, 'issuing_authority', 'Royal Oman Police (dummy)'));
    end if;
    if r.rc_off is not null then
      perform public.hr_save_document(r.emp_id, jsonb_build_object('doc_type', 'RESIDENT_CARD', 'doc_number', r.civil,
              'expiry_date', (current_date + r.rc_off)::text, 'issuing_authority', 'Royal Oman Police (dummy)'));
    end if;
    if r.visa_off is not null then
      perform public.hr_save_document(r.emp_id, jsonb_build_object('doc_type', 'EMPLOYMENT_VISA', 'doc_number', 'EV' || (r.no * 7919),
              'expiry_date', (current_date + r.visa_off)::text));
    end if;
    if r.wp_off is not null then
      perform public.hr_save_document(r.emp_id, jsonb_build_object('doc_type', 'WORK_PERMIT', 'doc_number', 'WP' || (r.no * 104729),
              'expiry_date', (current_date + r.wp_off)::text, 'issuing_authority', 'Ministry of Labour (dummy)'));
    end if;
    if r.med_off is not null then
      perform public.hr_save_document(r.emp_id, jsonb_build_object('doc_type', 'MEDICAL_FITNESS', 'doc_number', 'MF' || r.no,
              'expiry_date', (current_date + r.med_off)::text));
    end if;
    if r.lic_off is not null then
      perform public.hr_save_document(r.emp_id, jsonb_build_object('doc_type', 'DRIVING_LICENCE', 'doc_number', 'DL' || r.civil,
              'expiry_date', (current_date + r.lic_off)::text, 'issuing_authority', 'Royal Oman Police (dummy)'));
    end if;
    if r.contract_doc then
      perform public.hr_save_document(r.emp_id, jsonb_build_object('doc_type', 'CONTRACT_COPY', 'doc_number', 'C-' || r.no));
    end if;
  end loop;

  -- salary proposals (HR officer) → approvals (HR manager); a few left pending
  for r in select * from seed_people order by no loop
    v := public.hr_propose_compensation(r.emp_id, jsonb_build_object('effective_from', r.join_date::text, 'reason', 'JOIN',
           'lines', jsonb_build_array(jsonb_build_object('component_code', 'BASIC', 'amount', r.basic::text),
                                      jsonb_build_object('component_code', 'HOUSING', 'amount', r.housing::text),
                                      jsonb_build_object('component_code', 'TRANSPORT', 'amount', r.transport::text))));
    if r.special not like '%PENDING_SALARY%' then
      insert into seed_ids values ('rev:' || r.no, (v->>'revision_id')::uuid);
    end if;
  end loop;
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  for d in select id from seed_ids where k like 'rev:%' loop
    perform public.hr_decide_compensation(d.id, true, 'Approved per offer letter (dummy)');
  end loop;
  perform set_config('request.jwt.claim.sub', hro::text, false);
  for r in select * from seed_people where special like '%PENDING_INCREMENT%' loop
    perform public.hr_propose_compensation(r.emp_id, jsonb_build_object('effective_from', (date_trunc('month', current_date) + interval '1 month')::date::text,
            'reason', 'INCREMENT', 'lines', jsonb_build_array(
              jsonb_build_object('component_code', 'BASIC', 'amount', (r.basic + 50)::text),
              jsonb_build_object('component_code', 'HOUSING', 'amount', r.housing::text),
              jsonb_build_object('component_code', 'TRANSPORT', 'amount', r.transport::text))));
  end loop;

  -- bank accounts (HR officer requests → Finance approves); one left pending
  for r in select * from seed_people where bank is not null order by no loop
    v := public.hr_request_bank_change(r.emp_id, jsonb_build_object('bank_name', r.bank, 'account_name', r.name_en,
           'account_number', lpad((r.no * 9176543 % 10000000000000)::text, 16, '0'),
           'iban', 'OM' || lpad((r.no % 90 + 10)::text, 2, '0') || r.bank_code || lpad((r.no * 9176543 % 10000000000000)::text, 16, '0'),
           'swift_code', r.swift));
    if r.special not like '%PENDING_BANK%' then insert into seed_ids values ('bank:' || r.no, (v->'pending'->>'id')::uuid); end if;
  end loop;
  perform set_config('request.jwt.claim.sub', fin::text, false);
  for d in select id from seed_ids where k like 'bank:%' loop
    perform public.hr_decide_bank(d.id, true, 'Checked bank letter (dummy)');
  end loop;

  -- document verification by a second person (HR manager)
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  for d in select id from seed_ids where k like 'verify:%' loop
    perform public.hr_verify_document(d.id);
  end loop;

  -- Omanisation target: proposed by HR officer, approved by HR manager — DUMMY percentage
  perform set_config('request.jwt.claim.sub', hro::text, false);
  v := public.hr_propose_omanisation_target(jsonb_build_object('entity_id', v_ent, 'scope_type', 'ENTITY', 'target_pct', 40,
         'effective_from', date_trunc('year', current_date)::date::text, 'rule_basis', 'COMPANY_POLICY',
         'source_reference', 'DUMMY DATA - replace with the applicable Ministry decision before go-live'));
  v_id := (select (x->>'id')::uuid from jsonb_array_elements(v) x where x->>'status' = 'PENDING' limit 1);
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  perform public.hr_decide_omanisation_target(v_id, true, 'Dummy target for testing');

  -- lifecycle examples
  perform set_config('request.jwt.claim.sub', hro::text, false);
  for r in select * from seed_people where special = 'NOTICE' loop
    perform public.hr_change_status(r.emp_id, jsonb_build_object('action', 'NOTICE', 'date', current_date::text,
            'last_working_date', (current_date + 30)::text, 'separation_type', 'RESIGNATION'));
  end loop;
  for r in select * from seed_people where special = 'SEPARATE' loop
    perform public.hr_change_status(r.emp_id, jsonb_build_object('action', 'SEPARATE', 'date', current_date::text,
            'separation_type', 'END_OF_CONTRACT'));
  end loop;

  -- link demo logins to their employee records
  perform set_config('request.jwt.claim.sub', boss::text, false);
  for u in select su.id, sp.emp_id from seed_users su join seed_people sp on sp.no = su.emp_no loop
    perform public.hr_link_user_employee(u.id, u.emp_id);
  end loop;

  -- reminders
  perform set_config('request.jwt.claim.sub', hrm::text, false);
  perform public.hr_run_expiry_scan();

  perform set_config('request.jwt.claim.sub', '', false);
  raise notice 'AACT HRMS dummy data loaded: % employees.', (select count(*) from seed_people);
end
$seed$;

drop table seed_ids;
drop table seed_people;
drop table seed_users;
"""
OUT.write_text(sql, encoding="utf-8")
print(f"wrote {OUT} ({len(P)} employees, {len(USERS)} logins)")
