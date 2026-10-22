-- =============================================================================
-- 1.13.0 — Report centre
--  * hr.report_defs: the catalogue (code, group, permission, money / sensitive flags, filters, names in English and Arabic)
--  * hr.rpt_<code>(params): one function per report, returning {columns, rows, meta}; every report reuses the
--    same visibility rules as the screens (hr.visible_employees), the MG pay confidentiality (hr.money_ok / hr.run_ok)
--    and the audit-trail filter (hr.audit_ok)
--  * public.hr_run_report(code, params): permission check, access log for money and sensitive reports
--  * hr.report_schedules: monthly reminders that a report is ready (in-app and e-mail) — the e-mail carries a link,
--    never the report itself, so no personal data leaves the system by e-mail
--  * public.hr_board_pack(entity): data for the monthly PowerPoint board pack
-- =============================================================================

insert into hr.permissions(code, module, description) values
  ('REPORT_ADMIN', 'Reports', 'Schedule reports for named people (monthly in-app and e-mail reminders)')
on conflict (code) do nothing;
insert into hr.role_permissions(role_code, perm_code) values ('SUPER_ADMIN', 'REPORT_ADMIN'), ('HR_MANAGER', 'REPORT_ADMIN')
on conflict do nothing;

create table if not exists hr.report_defs (
  code       text primary key,
  grp        text not null check (grp in ('WORKFORCE','PAYROLL','TIME','COMPLIANCE','TALENT','AUDIT')),
  sort       int not null default 100,
  perm       text not null references hr.permissions(code),
  money      boolean not null default false,
  sensitive  boolean not null default false,
  params     text[] not null default '{}',
  name_en    text not null,
  name_ar    text not null,
  desc_en    text not null,
  desc_ar    text not null
);
alter table hr.report_defs enable row level security;

-- The company a report is for: the one asked for, else the first active company.
create or replace function hr.rp_entity(p jsonb)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v uuid := hr.juuid(p, 'entity_id');
begin
  if v is null then select id into v from hr.legal_entities where is_active order by created_at limit 1; end if;
  if v is null then raise exception 'REQUIRED: Add a company first.'; end if;
  return v;
end $$;

-- Employees a report may list (same rules as the screens), with their job on the date, and the common filters.
create or replace function hr.rp_people(p jsonb, p_perm text, p_on date, p_include_separated boolean default false)
returns table(employee_id uuid, employee_no text, name_en text, name_ar text, nationality text, nat_en text, is_omani boolean, gender text,
              date_of_birth date, join_date date, status text, pay_group text, separation_date date, separation_type text, separation_reason text,
              department_id uuid, dept_en text, dept_ar text, job_en text, job_ar text, profession_code text, omani_only boolean,
              category_en text, category_code text, grade_code text, location_en text, cost_centre text, manager_id uuid, manager_name text)
language sql stable security definer set search_path = '' as $$
  select e.id, e.employee_no, e.full_name_en, e.full_name_ar, e.nationality::text, coalesce(co.nationality_en, co.name_en, e.nationality::text), e.nationality = 'OM',
         e.gender::text, e.date_of_birth, e.join_date, e.status, e.pay_group, e.separation_date, e.separation_type, e.separation_reason,
         a.department_id, d.name_en, d.name_ar, j.name_en, j.name_ar, j.profession_code, coalesce(j.omani_only, false),
         cat.name_en, cat.code, g.code, l.name_en, coalesce(cc.code, dcc.code), a.manager_id, m.full_name_en
  from hr.employees e
  join hr.visible_employees(p_perm, hr.rp_entity(p)) v on v.employee_id = e.id
  left join hr.countries co on co.code = e.nationality
  left join lateral (select x.* from hr.employee_assignments x
                      where x.employee_id = e.id and x.effective_from <= least(p_on, coalesce(e.separation_date, p_on))
                        and (x.effective_to is null or x.effective_to >= least(p_on, coalesce(e.separation_date, p_on)))
                      order by x.effective_from desc limit 1) a on true
  left join hr.departments d on d.id = a.department_id
  left join hr.job_titles j on j.id = a.job_title_id
  left join hr.employee_categories cat on cat.id = a.category_id
  left join hr.grades g on g.id = a.grade_id
  left join hr.locations l on l.id = a.location_id
  left join hr.cost_centres cc on cc.id = a.cost_centre_id
  left join hr.cost_centres dcc on dcc.id = d.cost_centre_id
  left join hr.employees m on m.id = a.manager_id
  where e.join_date <= p_on
    and (p_include_separated or e.separation_date is null or e.separation_date > p_on)
    and (hr.juuid(p, 'department_id') is null or a.department_id = hr.juuid(p, 'department_id'))
    and (hr.jtext(p, 'pay_group') is null or e.pay_group = upper(hr.jtext(p, 'pay_group')))
    and (hr.jtext(p, 'nationality_group') is null or (upper(hr.jtext(p, 'nationality_group')) = 'OMANI') = (e.nationality = 'OM'))
$$;

-- The payroll run a report is about: the one asked for, else the latest calculated run of the company and pay group.
create or replace function hr.rp_run(p jsonb, p_ent uuid)
returns hr.payroll_runs language plpgsql stable security definer set search_path = '' as $$
declare r hr.payroll_runs; v_g text := coalesce(upper(hr.jtext(p, 'pay_group')), 'NMG');
begin
  if hr.juuid(p, 'run_id') is not null then
    select * into r from hr.payroll_runs where id = hr.juuid(p, 'run_id');
  else
    select * into r from hr.payroll_runs where entity_id = p_ent and pay_group = v_g and status <> 'DRAFT' order by period_start desc limit 1;
  end if;
  if r.id is null then raise exception 'NOT_FOUND: No calculated payroll run found for this company and pay group.'; end if;
  perform hr.require_run(r.id);
  return r;
end $$;

create or replace function hr.rp_run_meta(r hr.payroll_runs)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('run_id', r.id, 'month', to_char(r.period_start, 'YYYY-MM'), 'pay_group', r.pay_group, 'status', r.status, 'pay_date', r.pay_date)
$$;

-- The reports this user may run, with the lists the filter form needs.
create or replace function public.hr_report_catalog()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return jsonb_build_object(
    'reports', coalesce((select jsonb_agg(to_jsonb(d) order by d.sort) from hr.report_defs d where hr.has_perm(d.perm)), '[]'::jsonb),
    'can_schedule', hr.has_perm('REPORT_ADMIN'),
    'board_pack', hr.has_perm('EXEC_VIEW'),
    'audit_tables', case when hr.has_perm('AUDIT_READ') then (select jsonb_agg(c.relname order by c.relname) from pg_class c
                      where c.relnamespace = 'hr'::regnamespace and c.relkind = 'r' and c.relname not in ('audit_log','access_log','email_outbox')) end,
    'cycles', case when hr.has_perm('PERF_MANAGE') then coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'entity_id', c.entity_id, 'name', c.name,
                      'period_end', c.period_end) order by c.period_end desc) from hr.perf_cycles c), '[]'::jsonb) end,
    'runs', case when hr.has_perm('PAY_READ') then coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'entity_id', r.entity_id, 'month', to_char(r.period_start, 'YYYY-MM'),
                      'pay_group', r.pay_group, 'status', r.status) order by r.period_start desc, r.pay_group)
                      from hr.payroll_runs r where r.status <> 'DRAFT' and hr.run_ok(r.pay_group)), '[]'::jsonb) end);
end $$;

create table if not exists hr.report_schedules (
  id            uuid primary key default gen_random_uuid(),
  code          text not null references hr.report_defs(code),
  name          text,
  params        jsonb not null default '{}'::jsonb,
  recipients    uuid[] not null,
  day_of_month  int not null check (day_of_month between 1 and 28),
  is_active     boolean not null default true,
  last_sent_on  date,
  created_by    uuid not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (cardinality(recipients) between 1 and 50)
);
alter table hr.report_schedules enable row level security;

insert into hr.report_defs(code, grp, sort, perm, money, sensitive, params, name_en, name_ar, desc_en, desc_ar) values
  ('W01', 'WORKFORCE', 100, 'EMP_READ', false, false, array['entity','as_of','pay_group']::text[], 'Headcount by department', 'عدد الموظفين حسب القسم', 'Active employees on a date by department: Omani / expatriate, male / female, MG / NMG.', 'الموظفون العاملون في تاريخ محدد حسب القسم: عمانيون / وافدون، ذكور / إناث، إداريون / غير إداريين.'),
  ('W02', 'WORKFORCE', 101, 'EMP_READ', false, false, array['entity','as_of','department','pay_group','nationality_group']::text[], 'Employee list', 'قائمة الموظفين', 'Every employee on a date with job, department, nationality, age, service and status.', 'جميع الموظفين في تاريخ محدد مع الوظيفة والقسم والجنسية والعمر ومدة الخدمة والحالة.'),
  ('W03', 'WORKFORCE', 102, 'EMP_READ', false, false, array['entity','from_to','department']::text[], 'Joiners', 'الموظفون الجدد', 'Employees who joined in the period.', 'الموظفون الذين التحقوا خلال الفترة.'),
  ('W04', 'WORKFORCE', 103, 'EMP_READ', false, false, array['entity','from_to','department']::text[], 'Leavers', 'الموظفون المغادرون', 'Employees who left in the period, with the reason and length of service.', 'الموظفون الذين غادروا خلال الفترة مع السبب ومدة الخدمة.'),
  ('W05', 'WORKFORCE', 104, 'EMP_READ', false, false, array['entity','month']::text[], 'Turnover by month', 'معدل الدوران الشهري', 'Opening and closing headcount, joiners, leavers and turnover for the 12 months to the chosen month.', 'عدد الموظفين في بداية ونهاية كل شهر والمنضمون والمغادرون ومعدل الدوران لـ 12 شهراً.'),
  ('W06', 'WORKFORCE', 105, 'EMP_READ', false, false, array['entity','from_to']::text[], 'Turnover by department', 'معدل الدوران حسب القسم', 'Leavers against average headcount per department for the period.', 'المغادرون مقارنة بمتوسط عدد الموظفين لكل قسم خلال الفترة.'),
  ('W07', 'WORKFORCE', 106, 'EMP_READ', false, false, array['entity','as_of','department']::text[], 'Nationality profile', 'التوزيع حسب الجنسية', 'Headcount by nationality and gender.', 'عدد الموظفين حسب الجنسية والجنس.'),
  ('W08', 'WORKFORCE', 107, 'EMP_READ', false, false, array['entity','as_of','department']::text[], 'Age profile', 'التوزيع حسب العمر', 'Headcount by age band, Omani / expatriate and gender.', 'عدد الموظفين حسب الفئة العمرية والجنسية والجنس.'),
  ('W09', 'WORKFORCE', 108, 'EMP_READ', false, false, array['entity','as_of','department']::text[], 'Length of service', 'مدة الخدمة', 'Headcount by years of service.', 'عدد الموظفين حسب سنوات الخدمة.'),
  ('W10', 'WORKFORCE', 109, 'EMP_READ', false, false, array['entity','days','department']::text[], 'Contracts ending', 'العقود المنتهية', 'Fixed-term contracts ending within the chosen number of days (and already ended but still active).', 'العقود محددة المدة التي تنتهي خلال عدد الأيام المحدد.'),
  ('W11', 'WORKFORCE', 110, 'EMP_READ', false, false, array['entity','days','department']::text[], 'Probation ending', 'انتهاء فترة التجربة', 'Employees on probation whose probation ends within the chosen number of days.', 'الموظفون تحت التجربة التي تنتهي خلال عدد الأيام المحدد.'),
  ('W12', 'WORKFORCE', 111, 'EMP_READ', false, false, array['entity','as_of']::text[], 'Managers and team sizes', 'المديرون وأحجام الفرق', 'Line managers with the number of direct reports.', 'المديرون المباشرون وعدد التابعين لكل منهم.'),
  ('P01', 'PAYROLL', 212, 'PAY_READ', true, false, array['entity','run']::text[], 'Payroll register', 'سجل الرواتب', 'Every payslip of a payroll run: paid days, basic, earnings, deductions, net pay and employer cost.', 'جميع كشوف رواتب الدورة: أيام الدفع والأساسي والاستحقاقات والاستقطاعات وصافي الراتب وتكلفة صاحب العمل.'),
  ('P02', 'PAYROLL', 213, 'PAY_READ', true, false, array['entity','run']::text[], 'Payroll by department', 'الرواتب حسب القسم', 'Headcount, earnings, deductions, net pay and employer cost per department for a run.', 'العدد والاستحقاقات والاستقطاعات والصافي وتكلفة صاحب العمل لكل قسم.'),
  ('P03', 'PAYROLL', 214, 'PAY_READ', true, false, array['entity','run']::text[], 'Payroll by cost centre', 'الرواتب حسب مركز التكلفة', 'Payroll cost per cost centre for a run (for the finance journal).', 'تكلفة الرواتب لكل مركز تكلفة (لقيد المالية).'),
  ('P04', 'PAYROLL', 215, 'PAY_READ', true, false, array['entity','run']::text[], 'Pay items summary', 'ملخص بنود الرواتب', 'Total of each earning, deduction and employer item in a run.', 'إجمالي كل بند استحقاق واستقطاع وبنود صاحب العمل في الدورة.'),
  ('P05', 'PAYROLL', 216, 'PAY_READ', true, false, array['entity','run']::text[], 'Payroll variance (month on month)', 'فروقات الرواتب عن الشهر السابق', 'Net pay of each employee compared with the previous month, largest changes first.', 'صافي راتب كل موظف مقارنة بالشهر السابق، الأكبر تغيراً أولاً.'),
  ('P06', 'PAYROLL', 217, 'PAY_READ', true, false, array['entity','run']::text[], 'Bank transfer summary', 'ملخص التحويلات البنكية', 'Net pay to transfer, by bank, for a run.', 'صافي الرواتب الواجب تحويلها لكل بنك.'),
  ('P07', 'PAYROLL', 218, 'PAY_READ', true, false, array['entity','run']::text[], 'Bank transfer list', 'قائمة التحويلات البنكية', 'Each employee''s net pay and bank account for a run (account numbers masked without bank permission).', 'صافي راتب كل موظف وحسابه البنكي (أرقام الحسابات مخفية بدون صلاحية البنك).'),
  ('P08', 'PAYROLL', 219, 'PAY_READ', true, false, array['entity','run']::text[], 'Social Protection Fund contributions', 'اشتراكات صندوق الحماية الاجتماعية', 'Employee and employer SPF contributions per person for a run.', 'اشتراكات الموظف وصاحب العمل لكل شخص في الدورة.'),
  ('P09', 'PAYROLL', 220, 'PAY_READ', true, false, array['entity','as_of','department']::text[], 'End-of-service (gratuity) liability', 'التزامات مكافأة نهاية الخدمة', 'Accrued gratuity of every expatriate on a date, split before and after 31 July 2023.', 'مكافأة نهاية الخدمة المستحقة لكل وافد في تاريخ محدد، مقسمة قبل وبعد 31 يوليو 2023.'),
  ('P10', 'PAYROLL', 221, 'PAY_READ', true, false, array['entity']::text[], 'Loans and advances outstanding', 'القروض والسلف القائمة', 'Approved loans and advances with the amount repaid and the balance.', 'القروض والسلف المعتمدة مع المسدد والرصيد.'),
  ('P11', 'PAYROLL', 222, 'PAY_READ', true, false, array['entity','month','pay_group']::text[], 'Payroll cost trend', 'اتجاه تكلفة الرواتب', 'Approved payroll totals for the 12 months to the chosen month.', 'إجماليات الرواتب المعتمدة لـ 12 شهراً.'),
  ('P12', 'PAYROLL', 223, 'EMP_SALARY_READ', true, false, array['entity','from_to']::text[], 'Salary changes', 'تغييرات الرواتب', 'Approved salary revisions effective in the period, with the old and new monthly total.', 'تعديلات الرواتب المعتمدة السارية خلال الفترة مع الإجمالي الشهري القديم والجديد.'),
  ('P13', 'PAYROLL', 224, 'PAY_READ', true, false, array['entity','from_to']::text[], 'Final settlements', 'التسويات النهائية', 'Final settlements with a last working day in the period.', 'التسويات النهائية التي يقع آخر يوم عمل فيها ضمن الفترة.'),
  ('P14', 'PAYROLL', 225, 'EMP_SALARY_READ', true, false, array['entity','as_of','department','pay_group']::text[], 'Salary listing', 'كشف الرواتب الحالية', 'Approved monthly salary of every employee on a date: basic, allowances and gross.', 'الراتب الشهري المعتمد لكل موظف في تاريخ محدد: الأساسي والبدلات والإجمالي.'),
  ('P15', 'PAYROLL', 226, 'PAY_READ', true, false, array['entity','month']::text[], 'One-off pay items', 'البنود المتغيرة', 'Bonuses, commissions, arrears and one-off deductions for the month.', 'المكافآت والعمولات والفروقات والاستقطاعات لمرة واحدة خلال الشهر.'),
  ('T01', 'TIME', 327, 'ATT_READ', false, false, array['entity','month','department']::text[], 'Attendance summary', 'ملخص الحضور', 'Present, absent, leave, missing punches, lateness and hours per employee for a month.', 'أيام الحضور والغياب والإجازة والبصمات الناقصة والتأخير والساعات لكل موظف خلال الشهر.'),
  ('T02', 'TIME', 328, 'ATT_READ', false, false, array['entity','from_to','department']::text[], 'Late arrivals', 'التأخير عن الدوام', 'Every late arrival in the period with minutes late.', 'جميع حالات التأخير خلال الفترة مع دقائق التأخير.'),
  ('T03', 'TIME', 329, 'ATT_READ', false, false, array['entity','from_to','department']::text[], 'Absences', 'الغياب', 'Days marked absent (no punch, no approved leave) in the period.', 'الأيام المسجلة غياباً (بلا بصمة ولا إجازة معتمدة) خلال الفترة.'),
  ('T04', 'TIME', 330, 'ATT_READ', false, false, array['entity','from_to','department']::text[], 'Missing punches', 'البصمات الناقصة', 'Days with only one punch, to be corrected before the month is locked.', 'الأيام التي بها بصمة واحدة فقط ويجب تصحيحها قبل إقفال الشهر.'),
  ('T05', 'TIME', 331, 'ATT_READ', false, false, array['entity','from_to','department']::text[], 'Overtime', 'العمل الإضافي', 'Approved overtime in the period with hours and payable hours.', 'العمل الإضافي المعتمد خلال الفترة مع الساعات والساعات المستحقة.'),
  ('T06', 'TIME', 332, 'ATT_READ', false, false, array['entity','from_to']::text[], 'Overtime by department', 'العمل الإضافي حسب القسم', 'Approved overtime hours per department in the period.', 'ساعات العمل الإضافي المعتمدة لكل قسم خلال الفترة.'),
  ('T07', 'TIME', 333, 'LEAVE_READ', false, false, array['entity','as_of','department','leave_type']::text[], 'Leave balances', 'أرصدة الإجازات', 'Entitled, taken, pending and available days per employee for a leave type (annual by default).', 'الأيام المستحقة والمأخوذة والمعلقة والمتاحة لكل موظف لنوع الإجازة (السنوية افتراضياً).'),
  ('T08', 'TIME', 334, 'PAY_READ', true, false, array['entity','as_of','department']::text[], 'Annual leave liability', 'التزامات الإجازات السنوية', 'Value of untaken annual leave on a date (available days × basic ÷ 30).', 'قيمة الإجازات السنوية غير المأخوذة في تاريخ محدد (الأيام المتاحة × الأساسي ÷ 30).'),
  ('T09', 'TIME', 335, 'LEAVE_READ', false, false, array['entity','from_to','department','leave_type']::text[], 'Leave taken', 'الإجازات المأخوذة', 'Approved leave starting in the period.', 'الإجازات المعتمدة التي تبدأ خلال الفترة.'),
  ('T10', 'TIME', 336, 'LEAVE_READ', false, false, array['entity','from_to']::text[], 'Leave by type', 'الإجازات حسب النوع', 'Approved leave days and requests per leave type in the period.', 'أيام وطلبات الإجازات المعتمدة لكل نوع خلال الفترة.'),
  ('C01', 'COMPLIANCE', 437, 'COMPLIANCE_READ', false, false, array['entity','as_of']::text[], 'Omanisation by department', 'التعمين حسب القسم', 'Omani share of the counted workforce per department against the approved target.', 'نسبة العمانيين من القوى العاملة المحتسبة لكل قسم مقارنة بالنسبة المستهدفة المعتمدة.'),
  ('C02', 'COMPLIANCE', 438, 'COMPLIANCE_READ', false, false, array['entity','as_of']::text[], 'Omanisation by profession', 'التعمين حسب المهنة', 'Omani share per job title and Ministry of Labour profession code; Omani-only jobs flagged.', 'نسبة العمانيين لكل مسمى وظيفي ورمز مهنة وزارة العمل مع تمييز المهن المقصورة على العمانيين.'),
  ('C03', 'COMPLIANCE', 439, 'DOC_READ', false, false, array['entity','days','department']::text[], 'Document expiries', 'انتهاء صلاحية الوثائق', 'Documents, contracts and certificates expired or expiring within the chosen number of days.', 'الوثائق والعقود والشهادات المنتهية أو التي تنتهي خلال عدد الأيام المحدد.'),
  ('C04', 'COMPLIANCE', 440, 'DOC_READ', false, false, array['entity','department']::text[], 'Missing mandatory documents', 'الوثائق الإلزامية الناقصة', 'Active employees without a current copy of a mandatory document.', 'الموظفون العاملون الذين ليس لديهم نسخة سارية من وثيقة إلزامية.'),
  ('C05', 'COMPLIANCE', 441, 'DOC_READ', false, false, array['entity','department']::text[], 'Expatriate residence and permits', 'إقامات وتصاريح الوافدين', 'Each expatriate with passport, resident card, visa and work permit expiry dates.', 'كل وافد مع تواريخ انتهاء جواز السفر وبطاقة الإقامة والتأشيرة وتصريح العمل.'),
  ('C06', 'COMPLIANCE', 442, 'COMPLIANCE_READ', false, false, array['entity','as_of']::text[], 'Expatriates in Omani-only jobs', 'وافدون في مهن مقصورة على العمانيين', 'Expatriates assigned to Omani-only job titles, with the approved exception if any.', 'الوافدون المعينون في مسميات مقصورة على العمانيين مع الاستثناء المعتمد إن وجد.'),
  ('R01', 'TALENT', 543, 'REC_READ', false, false, array['entity']::text[], 'Recruitment pipeline', 'مسار التوظيف', 'Open and recent requisitions with candidates at each stage.', 'طلبات التوظيف المفتوحة والحديثة مع المرشحين في كل مرحلة.'),
  ('R02', 'TALENT', 544, 'REC_READ', false, false, array['entity','from_to']::text[], 'Time to hire', 'مدة التوظيف', 'Days from requisition approval to each hire in the period.', 'عدد الأيام من اعتماد طلب التوظيف حتى كل تعيين خلال الفترة.'),
  ('R03', 'TALENT', 545, 'PERF_MANAGE', false, false, array['entity','cycle']::text[], 'Performance ratings', 'تقييمات الأداء', 'Every review of an appraisal cycle with reviewer, stage and overall rating.', 'جميع تقييمات دورة التقييم مع المقيّم والمرحلة والتقييم العام.'),
  ('R04', 'TALENT', 546, 'PERF_MANAGE', false, false, array['entity','cycle']::text[], 'Rating distribution', 'توزيع التقييمات', 'How finalised overall ratings of a cycle are spread.', 'توزيع التقييمات العامة المعتمدة في الدورة.'),
  ('R05', 'TALENT', 547, 'TRAIN_WRITE', false, false, array['entity','from_to']::text[], 'Training completed', 'التدريب المنجز', 'Training completed in the period with certificate expiry and cost.', 'التدريب المنجز خلال الفترة مع انتهاء الشهادة والتكلفة.'),
  ('R06', 'TALENT', 548, 'TRAIN_WRITE', false, false, array['entity','from_to']::text[], 'Training by course', 'التدريب حسب الدورة', 'Participants and cost per course for training completed in the period.', 'المشاركون والتكلفة لكل دورة خلال الفترة.'),
  ('R07', 'TALENT', 549, 'DISC_READ', false, true, array['entity','from_to']::text[], 'Disciplinary cases', 'القضايا التأديبية', 'Disciplinary cases opened in the period with status and penalty (every opening is logged).', 'القضايا التأديبية المفتوحة خلال الفترة مع الحالة والعقوبة (كل اطلاع يُسجل).'),
  ('R08', 'TALENT', 550, 'HSE_WRITE', false, true, array['entity','from_to']::text[], 'Work injuries', 'إصابات العمل', 'Work injuries in the period with severity, lost days and SPF reporting.', 'إصابات العمل خلال الفترة مع الخطورة والأيام الضائعة والإبلاغ للصندوق.'),
  ('R09', 'TALENT', 551, 'ASSET_WRITE', false, false, array['entity']::text[], 'Assets with employees', 'العهد لدى الموظفين', 'Items currently issued to employees, overdue returns first.', 'المواد المسلمة حالياً للموظفين، المتأخرة أولاً.'),
  ('R10', 'TALENT', 552, 'EXIT_MANAGE', false, false, array['entity','from_to']::text[], 'Exits', 'حالات المغادرة', 'Exit cases with a last working day in the period, with type, reason and clearance progress.', 'حالات المغادرة التي يقع آخر يوم عمل فيها ضمن الفترة مع النوع والسبب وإنجاز إخلاء الطرف.'),
  ('R11', 'TALENT', 553, 'TRAIN_WRITE', false, false, array['entity','days']::text[], 'Certificates expiring', 'الشهادات المنتهية', 'Training certificates expired or expiring within the chosen number of days.', 'شهادات التدريب المنتهية أو التي تنتهي خلال عدد الأيام المحدد.'),
  ('A01', 'AUDIT', 654, 'AUDIT_READ', false, false, array['from_to','table']::text[], 'Audit trail', 'سجل التدقيق', 'Every change in the period (who, when, what) — up to 5,000 entries; filter by table.', 'كل تغيير خلال الفترة (من ومتى وماذا) — حتى 5000 سجل؛ يمكن التصفية حسب الجدول.'),
  ('A02', 'AUDIT', 655, 'AUDIT_READ', false, false, array['from_to']::text[], 'Sensitive-data access log', 'سجل الاطلاع على البيانات الحساسة', 'Who opened salaries, bank details, documents, discipline and money reports in the period.', 'من اطلع على الرواتب والبيانات البنكية والوثائق والقضايا التأديبية والتقارير المالية خلال الفترة.'),
  ('A03', 'AUDIT', 656, 'AUDIT_READ', false, false, array[]::text[], 'Users and roles', 'المستخدمون والأدوار', 'Every user with active roles, linked employee and status — for the periodic access review.', 'كل مستخدم مع أدواره الفعالة والموظف المرتبط والحالة — للمراجعة الدورية للصلاحيات.'),
  ('A04', 'AUDIT', 657, 'AUDIT_READ', false, false, array['from_to']::text[], 'Approvals log (maker-checker)', 'سجل الاعتمادات (المُعِد والمعتمِد)', 'Who prepared and who approved each controlled decision in the period.', 'من أعدّ ومن اعتمد كل قرار خاضع للرقابة خلال الفترة.'),
  ('A05', 'AUDIT', 658, 'AUDIT_READ', false, false, array['from_to']::text[], 'Self-approval and control exceptions', 'استثناءات الرقابة', 'Checks that nobody decided their own item and that payroll steps were done by different people. Empty means no exceptions.', 'فحص عدم اعتماد أي شخص لطلبه وأن خطوات الرواتب نفذها أشخاص مختلفون. القائمة الفارغة تعني لا استثناءات.')
on conflict (code) do update set grp = excluded.grp, sort = excluded.sort, perm = excluded.perm, money = excluded.money, sensitive = excluded.sensitive,
  params = excluded.params, name_en = excluded.name_en, name_ar = excluded.name_ar, desc_en = excluded.desc_en, desc_ar = excluded.desc_ar;


create or replace function hr.rpt_w01(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "total", "en": "Headcount", "ar": "العدد", "t": "int", "s": 1}, {"k": "omani", "en": "Omani", "ar": "عمانيون", "t": "int", "s": 1}, {"k": "expat", "en": "Expatriate", "ar": "وافدون", "t": "int", "s": 1}, {"k": "omani_pct", "en": "Omani %", "ar": "نسبة التعمين", "t": "pct"}, {"k": "male", "en": "Male", "ar": "ذكور", "t": "int", "s": 1}, {"k": "female", "en": "Female", "ar": "إناث", "t": "int", "s": 1}, {"k": "mg", "en": "MG", "ar": "إداريون", "t": "int", "s": 1}, {"k": "nmg", "en": "NMG", "ar": "غير إداريين", "t": "int", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(rp.dept_en, '(none)') as _o, coalesce(rp.dept_en, '(none)') as department, count(*)::int as total,
         count(*) filter (where rp.is_omani)::int as omani, count(*) filter (where not rp.is_omani)::int as expat,
         round(100.0 * count(*) filter (where rp.is_omani) / nullif(count(*), 0), 1) as omani_pct,
         count(*) filter (where rp.gender = 'M')::int as male, count(*) filter (where rp.gender = 'F')::int as female,
         count(*) filter (where rp.pay_group = 'MG')::int as mg, count(*) filter (where rp.pay_group = 'NMG')::int as nmg
       from hr.rp_people(p, 'EMP_READ', v_on) rp group by rp.dept_en
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w02(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "name_ar", "en": "Name (Arabic)", "ar": "الاسم بالعربية", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "category", "en": "Category", "ar": "الفئة", "t": "text"}, {"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "gender", "en": "Gender", "ar": "الجنس", "t": "text"}, {"k": "age", "en": "Age", "ar": "العمر", "t": "int"}, {"k": "join_date", "en": "Joined", "ar": "تاريخ الالتحاق", "t": "date"}, {"k": "service_years", "en": "Service (years)", "ar": "الخدمة (سنوات)", "t": "num"}, {"k": "status", "en": "Status", "ar": "الحالة", "t": "text"}, {"k": "pay_group", "en": "Pay group", "ar": "مجموعة الرواتب", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.employee_no as _o, rp.employee_no, rp.name_en, rp.name_ar, rp.dept_en as department, rp.job_en as job, rp.category_en as category,
         rp.nat_en as nationality, rp.gender, extract(year from age(v_on, rp.date_of_birth))::int as age, rp.join_date,
         round((v_on - rp.join_date) / 365.25, 1) as service_years, rp.status, rp.pay_group
       from hr.rp_people(p, 'EMP_READ', v_on) rp
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w03(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "category", "en": "Category", "ar": "الفئة", "t": "text"}, {"k": "join_date", "en": "Joined", "ar": "تاريخ الالتحاق", "t": "date"}, {"k": "pay_group", "en": "Pay group", "ar": "مجموعة الرواتب", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.join_date::text || rp.employee_no as _o, rp.employee_no, rp.name_en, rp.dept_en as department, rp.job_en as job, rp.nat_en as nationality,
         rp.category_en as category, rp.join_date, rp.pay_group
       from hr.rp_people(p, 'EMP_READ', v_to, true) rp where rp.join_date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w04(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "join_date", "en": "Joined", "ar": "تاريخ الالتحاق", "t": "date"}, {"k": "separation_date", "en": "Left", "ar": "تاريخ المغادرة", "t": "date"}, {"k": "separation_type", "en": "Type", "ar": "النوع", "t": "text"}, {"k": "reason", "en": "Reason", "ar": "السبب", "t": "text"}, {"k": "service_years", "en": "Service (years)", "ar": "الخدمة (سنوات)", "t": "num"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.separation_date::text || rp.employee_no as _o, rp.employee_no, rp.name_en, rp.dept_en as department, rp.job_en as job, rp.nat_en as nationality,
         rp.join_date, rp.separation_date, rp.separation_type, rp.separation_reason as reason, round((rp.separation_date - rp.join_date) / 365.25, 1) as service_years
       from hr.rp_people(p, 'EMP_READ', v_to, true) rp where rp.separation_date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w05(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "month", "en": "Month", "ar": "الشهر", "t": "text"}, {"k": "opening", "en": "Opening", "ar": "بداية الشهر", "t": "int"}, {"k": "joiners", "en": "Joiners", "ar": "المنضمون", "t": "int", "s": 1}, {"k": "leavers", "en": "Leavers", "ar": "المغادرون", "t": "int", "s": 1}, {"k": "closing", "en": "Closing", "ar": "نهاية الشهر", "t": "int"}, {"k": "turnover_pct", "en": "Turnover %", "ar": "معدل الدوران", "t": "pct"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select m::text as _o, to_char(m, 'YYYY-MM') as month,
         (select count(*) from hr.employees e join hr.visible_employees('EMP_READ', v_ent) v on v.employee_id = e.id where e.join_date < m and (e.separation_date is null or e.separation_date >= m))::int as opening,
         (select count(*) from hr.employees e join hr.visible_employees('EMP_READ', v_ent) v on v.employee_id = e.id where e.join_date between m and me)::int as joiners,
         (select count(*) from hr.employees e join hr.visible_employees('EMP_READ', v_ent) v on v.employee_id = e.id where e.separation_date between m and me)::int as leavers,
         (select count(*) from hr.employees e join hr.visible_employees('EMP_READ', v_ent) v on v.employee_id = e.id where e.join_date <= me and (e.separation_date is null or e.separation_date > me))::int as closing,
         (select round(100.0 * count(*) filter (where e.separation_date between m and me)
                 / nullif((count(*) filter (where e.join_date < m and (e.separation_date is null or e.separation_date >= m))
                         + count(*) filter (where e.join_date <= me and (e.separation_date is null or e.separation_date > me))) / 2.0, 0), 2)
            from hr.employees e join hr.visible_employees('EMP_READ', v_ent) v on v.employee_id = e.id) as turnover_pct
       from (select g::date as m, (g + interval '1 month - 1 day')::date as me
               from generate_series(v_m0 - interval '11 months', v_m0, interval '1 month') g) mm
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w06(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "opening", "en": "Opening", "ar": "في البداية", "t": "int", "s": 1}, {"k": "closing", "en": "Closing", "ar": "في النهاية", "t": "int", "s": 1}, {"k": "leavers", "en": "Leavers", "ar": "المغادرون", "t": "int", "s": 1}, {"k": "turnover_pct", "en": "Turnover %", "ar": "معدل الدوران", "t": "pct"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(x.department, '(none)') as _o, coalesce(x.department, '(none)') as department,
         count(*) filter (where x.join_date < v_from and (x.separation_date is null or x.separation_date >= v_from))::int as opening,
         count(*) filter (where x.join_date <= v_to and (x.separation_date is null or x.separation_date > v_to))::int as closing,
         count(*) filter (where x.separation_date between v_from and v_to)::int as leavers,
         round(100.0 * count(*) filter (where x.separation_date between v_from and v_to)
               / nullif((count(*) filter (where x.join_date < v_from and (x.separation_date is null or x.separation_date >= v_from))
                       + count(*) filter (where x.join_date <= v_to and (x.separation_date is null or x.separation_date > v_to))) / 2.0, 0), 2) as turnover_pct
       from (select rp.dept_en as department, rp.join_date, rp.separation_date from hr.rp_people(p, 'EMP_READ', v_to, true) rp
              where rp.separation_date is null or rp.separation_date >= v_from) x
       group by x.department
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w07(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "total", "en": "Headcount", "ar": "العدد", "t": "int", "s": 1}, {"k": "male", "en": "Male", "ar": "ذكور", "t": "int", "s": 1}, {"k": "female", "en": "Female", "ar": "إناث", "t": "int", "s": 1}, {"k": "share_pct", "en": "Share %", "ar": "النسبة", "t": "pct"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select lpad((100000 - count(*))::text, 6, '0') || coalesce(rp.nat_en, rp.nationality) as _o, coalesce(rp.nat_en, rp.nationality) as nationality,
         count(*)::int as total, count(*) filter (where rp.gender = 'M')::int as male, count(*) filter (where rp.gender = 'F')::int as female,
         round(100.0 * count(*) / nullif(sum(count(*)) over (), 0), 1) as share_pct
       from hr.rp_people(p, 'EMP_READ', v_on) rp group by coalesce(rp.nat_en, rp.nationality)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w08(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "band", "en": "Age band", "ar": "الفئة العمرية", "t": "text"}, {"k": "total", "en": "Headcount", "ar": "العدد", "t": "int", "s": 1}, {"k": "omani", "en": "Omani", "ar": "عمانيون", "t": "int", "s": 1}, {"k": "expat", "en": "Expatriate", "ar": "وافدون", "t": "int", "s": 1}, {"k": "male", "en": "Male", "ar": "ذكور", "t": "int", "s": 1}, {"k": "female", "en": "Female", "ar": "إناث", "t": "int", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select b.o as _o, b.band, count(rp.employee_id)::int as total, count(*) filter (where rp.is_omani)::int as omani,
         count(*) filter (where rp.employee_id is not null and not rp.is_omani)::int as expat,
         count(*) filter (where rp.gender = 'M')::int as male, count(*) filter (where rp.gender = 'F')::int as female
       from (values (1, 'Under 25', 0, 24), (2, '25–34', 25, 34), (3, '35–44', 35, 44), (4, '45–54', 45, 54), (5, '55–59', 55, 59), (6, '60 and over', 60, 200), (7, 'Unknown', -1, -1)) b(o, band, lo, hi)
       left join (select r.*, extract(year from age(v_on, r.date_of_birth))::int as age from hr.rp_people(p, 'EMP_READ', v_on) r) rp
         on (b.lo = -1 and rp.age is null) or (rp.age between b.lo and b.hi)
       group by b.o, b.band
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w09(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "band", "en": "Service", "ar": "مدة الخدمة", "t": "text"}, {"k": "total", "en": "Headcount", "ar": "العدد", "t": "int", "s": 1}, {"k": "omani", "en": "Omani", "ar": "عمانيون", "t": "int", "s": 1}, {"k": "expat", "en": "Expatriate", "ar": "وافدون", "t": "int", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select b.o as _o, b.band, count(rp.employee_id)::int as total, count(*) filter (where rp.is_omani)::int as omani,
         count(*) filter (where rp.employee_id is not null and not rp.is_omani)::int as expat
       from (values (1, 'Under 1 year', 0, 1), (2, '1–3 years', 1, 3), (3, '3–5 years', 3, 5), (4, '5–10 years', 5, 10), (5, '10–20 years', 10, 20), (6, '20 years and over', 20, 100)) b(o, band, lo, hi)
       left join (select r.*, (v_on - r.join_date) / 365.25 as yrs from hr.rp_people(p, 'EMP_READ', v_on) r) rp on rp.yrs >= b.lo and rp.yrs < b.hi
       group by b.o, b.band
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w10(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "contract_type", "en": "Contract", "ar": "العقد", "t": "text"}, {"k": "start_date", "en": "Start", "ar": "البداية", "t": "date"}, {"k": "end_date", "en": "End", "ar": "النهاية", "t": "date"}, {"k": "days_left", "en": "Days left", "ar": "الأيام المتبقية", "t": "int"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select k.end_date::text || rp.employee_no as _o, rp.employee_no, rp.name_en, rp.dept_en as department, rp.job_en as job, rp.nat_en as nationality,
         k.contract_type, k.start_date, k.end_date, (k.end_date - v_on)::int as days_left
       from hr.rp_people(p, 'EMP_READ', v_on) rp join hr.employee_contracts k on k.employee_id = rp.employee_id and k.status = 'ACTIVE'
      where k.end_date is not null and k.end_date <= v_on + v_days
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w11(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "join_date", "en": "Joined", "ar": "تاريخ الالتحاق", "t": "date"}, {"k": "probation_end", "en": "Probation ends", "ar": "نهاية التجربة", "t": "date"}, {"k": "days_left", "en": "Days left", "ar": "الأيام المتبقية", "t": "int"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select e.probation_end_date::text || rp.employee_no as _o, rp.employee_no, rp.name_en, rp.dept_en as department, rp.job_en as job, rp.join_date,
         e.probation_end_date as probation_end, (e.probation_end_date - v_on)::int as days_left
       from hr.rp_people(p, 'EMP_READ', v_on) rp join hr.employees e on e.id = rp.employee_id
      where e.status = 'PROBATION' and e.probation_end_date is not null and e.probation_end_date <= v_on + v_days
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_w12(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "manager", "en": "Line manager", "ar": "المدير المباشر", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "direct_reports", "en": "Direct reports", "ar": "التابعون المباشرون", "t": "int", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select lpad((100000 - count(*))::text, 6, '0') || max(rp.manager_name) as _o, max(rp.manager_name) as manager,
         (select d.name_en from hr.departments d where d.id = (hr.current_assignment(rp.manager_id, v_on)).department_id) as department,
         count(*)::int as direct_reports
       from hr.rp_people(p, 'EMP_READ', v_on) rp where rp.manager_id is not null group by rp.manager_id
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p01(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  v_run := hr.rp_run(p, v_ent); v_meta := hr.rp_run_meta(v_run);
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "nationality", "en": "Nat.", "ar": "الجنسية", "t": "text"}, {"k": "paid_days", "en": "Paid days", "ar": "أيام الدفع", "t": "num"}, {"k": "basic", "en": "Basic", "ar": "الأساسي", "t": "money", "s": 1}, {"k": "earnings", "en": "Earnings", "ar": "الاستحقاقات", "t": "money", "s": 1}, {"k": "deductions", "en": "Deductions", "ar": "الاستقطاعات", "t": "money", "s": 1}, {"k": "net", "en": "Net pay", "ar": "صافي الراتب", "t": "money", "s": 1}, {"k": "employer_cost", "en": "Employer cost", "ar": "تكلفة صاحب العمل", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select s.employee_no as _o, s.employee_no, s.full_name_en as name_en, s.department_en as department, s.job_en as job, s.nationality,
         s.paid_days, s.basic, s.total_earnings as earnings, s.total_deductions as deductions, s.net, s.employer_cost
       from hr.payslips s where s.run_id = v_run.id and hr.money_ok(s.employee_id)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p02(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  v_run := hr.rp_run(p, v_ent); v_meta := hr.rp_run_meta(v_run);
  return jsonb_build_object('columns', '[{"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "headcount", "en": "Employees", "ar": "الموظفون", "t": "int", "s": 1}, {"k": "basic", "en": "Basic", "ar": "الأساسي", "t": "money", "s": 1}, {"k": "earnings", "en": "Earnings", "ar": "الاستحقاقات", "t": "money", "s": 1}, {"k": "deductions", "en": "Deductions", "ar": "الاستقطاعات", "t": "money", "s": 1}, {"k": "net", "en": "Net pay", "ar": "صافي الراتب", "t": "money", "s": 1}, {"k": "employer_cost", "en": "Employer cost", "ar": "تكلفة صاحب العمل", "t": "money", "s": 1}, {"k": "total_cost", "en": "Total cost", "ar": "إجمالي التكلفة", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(s.department_en, '(none)') as _o, coalesce(s.department_en, '(none)') as department, count(*)::int as headcount, sum(s.basic) as basic,
         sum(s.total_earnings) as earnings, sum(s.total_deductions) as deductions, sum(s.net) as net, sum(s.employer_cost) as employer_cost,
         sum(s.total_earnings + s.employer_cost) as total_cost
       from hr.payslips s where s.run_id = v_run.id and hr.money_ok(s.employee_id) group by s.department_en
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p03(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  v_run := hr.rp_run(p, v_ent); v_meta := hr.rp_run_meta(v_run);
  return jsonb_build_object('columns', '[{"k": "cost_centre", "en": "Cost centre", "ar": "مركز التكلفة", "t": "text"}, {"k": "headcount", "en": "Employees", "ar": "الموظفون", "t": "int", "s": 1}, {"k": "earnings", "en": "Earnings", "ar": "الاستحقاقات", "t": "money", "s": 1}, {"k": "employer_cost", "en": "Employer cost", "ar": "تكلفة صاحب العمل", "t": "money", "s": 1}, {"k": "total_cost", "en": "Total cost", "ar": "إجمالي التكلفة", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(s.cost_centre, '(none)') as _o, coalesce(s.cost_centre, '(none)') as cost_centre, count(*)::int as headcount,
         sum(s.total_earnings) as earnings, sum(s.employer_cost) as employer_cost, sum(s.total_earnings + s.employer_cost) as total_cost
       from hr.payslips s where s.run_id = v_run.id and hr.money_ok(s.employee_id) group by s.cost_centre
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p04(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  v_run := hr.rp_run(p, v_ent); v_meta := hr.rp_run_meta(v_run);
  return jsonb_build_object('columns', '[{"k": "code", "en": "Code", "ar": "الرمز", "t": "text"}, {"k": "item", "en": "Item", "ar": "البند", "t": "text"}, {"k": "kind", "en": "Type", "ar": "النوع", "t": "text"}, {"k": "employees", "en": "Employees", "ar": "الموظفون", "t": "int"}, {"k": "amount", "en": "Amount", "ar": "المبلغ", "t": "money"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select case l.kind when 'EARNING' then 1 when 'DEDUCTION' then 2 else 3 end::text || lpad(min(l.sort)::text, 5, '0') || l.code as _o,
         l.code, max(l.name_en) as item, l.kind, count(distinct s.employee_id)::int as employees, sum(l.amount) as amount
       from hr.payslips s join hr.payslip_lines l on l.payslip_id = s.id where s.run_id = v_run.id and hr.money_ok(s.employee_id)
      group by l.code, l.kind
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p05(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  v_run := hr.rp_run(p, v_ent); v_meta := hr.rp_run_meta(v_run);
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "previous_net", "en": "Previous net", "ar": "الصافي السابق", "t": "money", "s": 1}, {"k": "net", "en": "This month", "ar": "هذا الشهر", "t": "money", "s": 1}, {"k": "difference", "en": "Difference", "ar": "الفرق", "t": "money", "s": 1}, {"k": "change_pct", "en": "Change %", "ar": "نسبة التغير", "t": "pct"}, {"k": "note", "en": "Note", "ar": "ملاحظة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select lpad((1000000000 - round(abs(coalesce(cur.net, 0) - coalesce(prv.net, 0)) * 1000))::text, 12, '0') as _o,
         coalesce(cur.employee_no, prv.employee_no) as employee_no, coalesce(cur.full_name_en, prv.full_name_en) as name_en,
         coalesce(cur.department_en, prv.department_en) as department, prv.net as previous_net, cur.net,
         coalesce(cur.net, 0) - coalesce(prv.net, 0) as difference,
         case when prv.net > 0 then round(100.0 * (coalesce(cur.net, 0) - prv.net) / prv.net, 1) end as change_pct,
         case when prv.employee_id is null then 'New in this month' when cur.employee_id is null then 'Not paid this month' end as note
       from (select * from hr.payslips s where s.run_id = v_run.id and hr.money_ok(s.employee_id)) cur
       full join (select s.* from hr.payslips s where s.run_id = (select r.id from hr.payroll_runs r where r.entity_id = v_run.entity_id and r.pay_group = v_run.pay_group
                    and r.period_start = (v_run.period_start - interval '1 month')::date limit 1) and hr.money_ok(s.employee_id)) prv on prv.employee_id = cur.employee_id
      where coalesce(cur.net, 0) <> coalesce(prv.net, 0)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p06(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  v_run := hr.rp_run(p, v_ent); v_meta := hr.rp_run_meta(v_run);
  return jsonb_build_object('columns', '[{"k": "bank", "en": "Bank", "ar": "البنك", "t": "text"}, {"k": "employees", "en": "Employees", "ar": "الموظفون", "t": "int", "s": 1}, {"k": "amount", "en": "Amount", "ar": "المبلغ", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(s.bank_name, '(no bank account)') as _o, coalesce(s.bank_name, '(no bank account)') as bank, count(*)::int as employees, sum(s.net) as amount
       from hr.payslips s where s.run_id = v_run.id and hr.money_ok(s.employee_id) group by s.bank_name
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p07(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  v_run := hr.rp_run(p, v_ent); v_meta := hr.rp_run_meta(v_run);
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "bank", "en": "Bank", "ar": "البنك", "t": "text"}, {"k": "account", "en": "Account / IBAN", "ar": "الحساب / الآيبان", "t": "text"}, {"k": "net", "en": "Net pay", "ar": "صافي الراتب", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(s.bank_name, '') || s.employee_no as _o, s.employee_no, s.full_name_en as name_en, s.bank_name as bank,
         case when hr.has_perm('EMP_BANK_READ') then coalesce(s.iban, s.account_number)
              when coalesce(s.iban, s.account_number) is null then null
              else '••••' || right(coalesce(s.iban, s.account_number), 4) end as account, s.net
       from hr.payslips s where s.run_id = v_run.id and hr.money_ok(s.employee_id)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p08(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  v_run := hr.rp_run(p, v_ent); v_meta := hr.rp_run_meta(v_run);
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "group", "en": "Omani / Expatriate", "ar": "عماني / وافد", "t": "text"}, {"k": "wage", "en": "Contribution wage", "ar": "الأجر الخاضع", "t": "money"}, {"k": "employee", "en": "Employee share", "ar": "حصة الموظف", "t": "money", "s": 1}, {"k": "employer", "en": "Employer share", "ar": "حصة صاحب العمل", "t": "money", "s": 1}, {"k": "total", "en": "Total", "ar": "الإجمالي", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select (case when s.is_omani then '1' else '2' end) || s.employee_no as _o, s.employee_no, s.full_name_en as name_en,
         case when s.is_omani then 'Omani' else 'Expatriate' end as "group",
         (select max(l.qty) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_ER%') as wage,
         (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_EE%') as employee,
         (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_ER%') as employer,
         (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_E%') as total
       from hr.payslips s where s.run_id = v_run.id and hr.money_ok(s.employee_id) and exists (select 1 from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_E%')
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p09(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "join_date", "en": "Joined", "ar": "تاريخ الالتحاق", "t": "date"}, {"k": "service_years", "en": "Service (years)", "ar": "الخدمة (سنوات)", "t": "num"}, {"k": "basic", "en": "Basic", "ar": "الأساسي", "t": "money", "s": 1}, {"k": "old_amount", "en": "To 31 Jul 2023", "ar": "حتى 31/7/2023", "t": "money", "s": 1}, {"k": "new_amount", "en": "From 1 Aug 2023", "ar": "من 1/8/2023", "t": "money", "s": 1}, {"k": "total", "en": "Total liability", "ar": "إجمالي الالتزام", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select x.employee_no as _o, x.employee_no, x.name_en, x.department, x.nat_en as nationality, x.join_date, round((v_on - x.join_date) / 365.25, 2) as service_years,
         x.basic, (x.g->>'old_amount')::numeric as old_amount, (x.g->>'new_amount')::numeric as new_amount, (x.g->>'total')::numeric as total
       from (select rp.*, rp.dept_en as department, coalesce((hr.comp_on(rp.employee_id, v_on)->>'basic')::numeric, 0) as basic,
                    hr.gratuity_calc(rp.employee_id, v_on, coalesce((hr.comp_on(rp.employee_id, v_on)->>'basic')::numeric, 0)) as g
               from hr.rp_people(p, 'PAY_READ', v_on) rp where not rp.is_omani and hr.money_ok(rp.employee_id)) x
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p10(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "kind", "en": "Type", "ar": "النوع", "t": "text"}, {"k": "first_month", "en": "First instalment", "ar": "أول قسط", "t": "date"}, {"k": "amount", "en": "Amount", "ar": "المبلغ", "t": "money", "s": 1}, {"k": "installment", "en": "Instalment", "ar": "القسط", "t": "money"}, {"k": "repaid", "en": "Repaid", "ar": "المسدد", "t": "money", "s": 1}, {"k": "balance", "en": "Balance", "ar": "الرصيد", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select e.employee_no as _o, e.employee_no, e.full_name_en as name_en, l.kind, l.first_month, l.amount, l.installment,
         coalesce((select sum(r.amount) from hr.loan_repayments r where r.loan_id = l.id), 0) as repaid,
         l.amount - coalesce((select sum(r.amount) from hr.loan_repayments r where r.loan_id = l.id), 0) as balance
       from hr.employee_loans l join hr.employees e on e.id = l.employee_id
       join hr.visible_employees('PAY_READ', v_ent) v on v.employee_id = e.id
      where l.status = 'APPROVED' and hr.money_ok(e.id)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p11(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "month", "en": "Month", "ar": "الشهر", "t": "text"}, {"k": "employees", "en": "Employees", "ar": "الموظفون", "t": "int"}, {"k": "earnings", "en": "Earnings", "ar": "الاستحقاقات", "t": "money", "s": 1}, {"k": "deductions", "en": "Deductions", "ar": "الاستقطاعات", "t": "money", "s": 1}, {"k": "net", "en": "Net pay", "ar": "صافي الراتب", "t": "money", "s": 1}, {"k": "employer_cost", "en": "Employer cost", "ar": "تكلفة صاحب العمل", "t": "money", "s": 1}, {"k": "total_cost", "en": "Total cost", "ar": "إجمالي التكلفة", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select m::text as _o, to_char(m, 'YYYY-MM') as month, count(s.id)::int as employees, coalesce(sum(s.total_earnings), 0) as earnings,
         coalesce(sum(s.total_deductions), 0) as deductions, coalesce(sum(s.net), 0) as net, coalesce(sum(s.employer_cost), 0) as employer_cost,
         coalesce(sum(s.total_earnings + s.employer_cost), 0) as total_cost
       from generate_series(v_m0 - interval '11 months', v_m0, interval '1 month') m
       left join hr.payroll_runs r on r.entity_id = v_ent and r.period_start = m::date and r.status in ('APPROVED','PAID') and hr.run_ok(r.pay_group)
                                   and (hr.jtext(p,'pay_group') is null or r.pay_group = upper(hr.jtext(p,'pay_group')))
       left join hr.payslips s on s.run_id = r.id and hr.money_ok(s.employee_id)
      group by m
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p12(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "effective_from", "en": "Effective", "ar": "السريان", "t": "date"}, {"k": "reason", "en": "Reason", "ar": "السبب", "t": "text"}, {"k": "old_total", "en": "Old total", "ar": "الإجمالي السابق", "t": "money", "s": 1}, {"k": "new_total", "en": "New total", "ar": "الإجمالي الجديد", "t": "money", "s": 1}, {"k": "change", "en": "Change", "ar": "التغير", "t": "money", "s": 1}, {"k": "change_pct", "en": "Change %", "ar": "نسبة التغير", "t": "pct"}, {"k": "approved_by", "en": "Approved by", "ar": "اعتمده", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select r.effective_from::text || e.employee_no as _o, e.employee_no, e.full_name_en as name_en, r.effective_from, r.reason,
         prev.total_monthly as old_total, r.total_monthly as new_total, r.total_monthly - coalesce(prev.total_monthly, 0) as change,
         case when prev.total_monthly > 0 then round(100.0 * (r.total_monthly - prev.total_monthly) / prev.total_monthly, 1) end as change_pct,
         hr.user_label(r.decided_by) as approved_by
       from hr.compensation_revisions r join hr.employees e on e.id = r.employee_id
       join hr.visible_employees('EMP_SALARY_READ', v_ent) v on v.employee_id = e.id
       left join lateral (select p2.total_monthly from hr.compensation_revisions p2 where p2.employee_id = r.employee_id and p2.status in ('APPROVED','SUPERSEDED')
                           and p2.effective_from < r.effective_from order by p2.effective_from desc limit 1) prev on true
      where r.status in ('APPROVED','SUPERSEDED') and r.effective_from between v_from and v_to and hr.money_ok(e.id)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p13(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "last_working_date", "en": "Last day", "ar": "آخر يوم عمل", "t": "date"}, {"k": "reason", "en": "Reason", "ar": "السبب", "t": "text"}, {"k": "gratuity", "en": "Gratuity", "ar": "المكافأة", "t": "money", "s": 1}, {"k": "leave_pay", "en": "Leave pay", "ar": "بدل الإجازة", "t": "money", "s": 1}, {"k": "notice_pay", "en": "Notice pay", "ar": "بدل الإنذار", "t": "money", "s": 1}, {"k": "deductions", "en": "Deductions", "ar": "الاستقطاعات", "t": "money", "s": 1}, {"k": "net", "en": "Net", "ar": "الصافي", "t": "money", "s": 1}, {"k": "status", "en": "Status", "ar": "الحالة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select f.last_working_date::text || e.employee_no as _o, e.employee_no, e.full_name_en as name_en, f.last_working_date, f.reason, f.gratuity, f.leave_pay, f.notice_pay,
         f.loan_recovery + f.other_deductions as deductions, f.net, f.status
       from hr.final_settlements f join hr.employees e on e.id = f.employee_id
       join hr.visible_employees('PAY_READ', v_ent) v on v.employee_id = e.id
      where f.status <> 'CANCELLED' and f.last_working_date between v_from and v_to and hr.money_ok(e.id)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p14(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "effective_from", "en": "Since", "ar": "منذ", "t": "date"}, {"k": "basic", "en": "Basic", "ar": "الأساسي", "t": "money", "s": 1}, {"k": "allowances", "en": "Allowances", "ar": "البدلات", "t": "money", "s": 1}, {"k": "gross", "en": "Gross", "ar": "الإجمالي", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.employee_no as _o, rp.employee_no, rp.name_en, rp.dept_en as department, rp.job_en as job, (k.c->>'effective_from')::date as effective_from,
         coalesce((k.c->>'basic')::numeric, 0) as basic, coalesce((k.c->>'gross')::numeric, 0) - coalesce((k.c->>'basic')::numeric, 0) as allowances,
         coalesce((k.c->>'gross')::numeric, 0) as gross
       from hr.rp_people(p, 'EMP_SALARY_READ', v_on) rp cross join lateral (select hr.comp_on(rp.employee_id, v_on) as c) k
      where hr.money_ok(rp.employee_id)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_p15(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "kind", "en": "Type", "ar": "النوع", "t": "text"}, {"k": "code", "en": "Item", "ar": "البند", "t": "text"}, {"k": "reason", "en": "Reason", "ar": "السبب", "t": "text"}, {"k": "amount", "en": "Amount", "ar": "المبلغ", "t": "money", "s": 1}, {"k": "status", "en": "Status", "ar": "الحالة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select e.employee_no || a.code as _o, e.employee_no, e.full_name_en as name_en, a.kind, a.code, a.reason, a.amount, a.status
       from hr.payroll_adjustments a join hr.employees e on e.id = a.employee_id
       join hr.visible_employees('PAY_READ', v_ent) v on v.employee_id = e.id
      where a.period_start = v_m0 and a.status <> 'REJECTED' and hr.money_ok(e.id)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t01(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "present", "en": "Present", "ar": "حضور", "t": "int", "s": 1}, {"k": "absent", "en": "Absent", "ar": "غياب", "t": "int", "s": 1}, {"k": "leave", "en": "Leave", "ar": "إجازة", "t": "num", "s": 1}, {"k": "missing", "en": "Missing punch", "ar": "بصمة ناقصة", "t": "int", "s": 1}, {"k": "late_days", "en": "Late days", "ar": "أيام التأخير", "t": "int", "s": 1}, {"k": "late_minutes", "en": "Late minutes", "ar": "دقائق التأخير", "t": "int", "s": 1}, {"k": "worked_hours", "en": "Worked hours", "ar": "ساعات العمل", "t": "num", "s": 1}, {"k": "extra_hours", "en": "Extra hours", "ar": "ساعات إضافية", "t": "num", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.employee_no as _o, rp.employee_no, rp.name_en, rp.dept_en as department,
         count(*) filter (where a.status = 'PRESENT')::int as present, count(*) filter (where a.status = 'ABSENT')::int as absent,
         coalesce(sum(a.leave_fraction) filter (where a.status = 'LEAVE' or a.leave_fraction > 0), 0) as leave,
         count(*) filter (where a.status = 'MISSING_PUNCH')::int as missing, count(*) filter (where a.late_minutes > 0)::int as late_days,
         coalesce(sum(a.late_minutes), 0)::int as late_minutes, round(coalesce(sum(a.worked_minutes), 0) / 60.0, 1) as worked_hours,
         round(coalesce(sum(a.extra_minutes), 0) / 60.0, 1) as extra_hours
       from hr.attendance_days a join hr.rp_people(p, 'ATT_READ', v_m1, true) rp on rp.employee_id = a.employee_id
      where a.work_date between v_m0 and v_m1 group by rp.employee_no, rp.name_en, rp.dept_en
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t02(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "work_date", "en": "Date", "ar": "التاريخ", "t": "date"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "scheduled", "en": "Scheduled", "ar": "موعد الدوام", "t": "text"}, {"k": "first_in", "en": "First in", "ar": "أول دخول", "t": "text"}, {"k": "late_minutes", "en": "Minutes late", "ar": "دقائق التأخير", "t": "int", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select a.work_date::text || rp.employee_no as _o, a.work_date, rp.employee_no, rp.name_en, rp.dept_en as department,
         to_char(a.sched_start at time zone 'Asia/Muscat', 'HH24:MI') as scheduled, to_char(a.first_in at time zone 'Asia/Muscat', 'HH24:MI') as first_in, a.late_minutes
       from hr.attendance_days a join hr.rp_people(p, 'ATT_READ', v_to, true) rp on rp.employee_id = a.employee_id
      where a.work_date between v_from and v_to and a.late_minutes > 0
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t03(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "work_date", "en": "Date", "ar": "التاريخ", "t": "date"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select a.work_date::text || rp.employee_no as _o, a.work_date, rp.employee_no, rp.name_en, rp.dept_en as department, rp.job_en as job
       from hr.attendance_days a join hr.rp_people(p, 'ATT_READ', v_to, true) rp on rp.employee_id = a.employee_id
      where a.work_date between v_from and v_to and a.status = 'ABSENT'
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t04(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "work_date", "en": "Date", "ar": "التاريخ", "t": "date"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "first_in", "en": "In", "ar": "دخول", "t": "text"}, {"k": "last_out", "en": "Out", "ar": "خروج", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select a.work_date::text || rp.employee_no as _o, a.work_date, rp.employee_no, rp.name_en, rp.dept_en as department,
         to_char(a.first_in at time zone 'Asia/Muscat', 'HH24:MI') as first_in, to_char(a.last_out at time zone 'Asia/Muscat', 'HH24:MI') as last_out
       from hr.attendance_days a join hr.rp_people(p, 'ATT_READ', v_to, true) rp on rp.employee_id = a.employee_id
      where a.work_date between v_from and v_to and a.status = 'MISSING_PUNCH'
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t05(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "work_date", "en": "Date", "ar": "التاريخ", "t": "date"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "day_kind", "en": "Day", "ar": "نوع اليوم", "t": "text"}, {"k": "hours", "en": "Hours", "ar": "الساعات", "t": "num", "s": 1}, {"k": "pay_hours", "en": "Payable hours", "ar": "الساعات المستحقة", "t": "num", "s": 1}, {"k": "comp", "en": "Compensation", "ar": "التعويض", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select o.work_date::text || rp.employee_no as _o, o.work_date, rp.employee_no, rp.name_en, rp.dept_en as department, o.day_kind,
         round(o.minutes / 60.0, 2) as hours, o.pay_hours, o.comp_choice as comp
       from hr.overtime_requests o join hr.rp_people(p, 'ATT_READ', v_to, true) rp on rp.employee_id = o.employee_id
      where o.status = 'APPROVED' and o.work_date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t06(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "employees", "en": "Employees", "ar": "الموظفون", "t": "int", "s": 1}, {"k": "requests", "en": "Requests", "ar": "الطلبات", "t": "int", "s": 1}, {"k": "hours", "en": "Hours", "ar": "الساعات", "t": "num", "s": 1}, {"k": "pay_hours", "en": "Payable hours", "ar": "الساعات المستحقة", "t": "num", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(rp.dept_en, '(none)') as _o, coalesce(rp.dept_en, '(none)') as department, count(distinct o.employee_id)::int as employees, count(*)::int as requests,
         round(sum(o.minutes) / 60.0, 1) as hours, coalesce(sum(o.pay_hours), 0) as pay_hours
       from hr.overtime_requests o join hr.rp_people(p, 'ATT_READ', v_to, true) rp on rp.employee_id = o.employee_id
      where o.status = 'APPROVED' and o.work_date between v_from and v_to group by rp.dept_en
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t07(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "leave_type", "en": "Leave type", "ar": "نوع الإجازة", "t": "text"}, {"k": "entitled", "en": "Entitled", "ar": "المستحق", "t": "num", "s": 1}, {"k": "used", "en": "Taken", "ar": "المأخوذ", "t": "num", "s": 1}, {"k": "pending", "en": "Pending", "ar": "معلق", "t": "num", "s": 1}, {"k": "available", "en": "Available", "ar": "المتاح", "t": "num", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.employee_no as _o, rp.employee_no, rp.name_en, rp.dept_en as department, b.b->>'name_en' as leave_type,
         (b.b->>'entitled')::numeric as entitled, (b.b->>'used')::numeric as used, (b.b->>'pending')::numeric as pending, (b.b->>'available')::numeric as available
       from hr.rp_people(p, 'LEAVE_READ', v_on) rp
       cross join lateral (select hr.leave_balance(rp.employee_id, coalesce(upper(hr.jtext(p,'leave_type')), 'ANNUAL'), v_on) as b) b
      where b.b is not null
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t08(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "available", "en": "Available days", "ar": "الأيام المتاحة", "t": "num", "s": 1}, {"k": "basic", "en": "Basic", "ar": "الأساسي", "t": "money"}, {"k": "daily_rate", "en": "Daily rate", "ar": "الأجر اليومي", "t": "money"}, {"k": "liability", "en": "Liability", "ar": "الالتزام", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select x.employee_no as _o, x.employee_no, x.name_en, x.department, x.available, x.basic, round(x.basic / 30.0, 3) as daily_rate,
         round(greatest(x.available, 0) * x.basic / 30.0, 3) as liability
       from (select rp.employee_no, rp.name_en, rp.dept_en as department,
                    coalesce((hr.leave_balance(rp.employee_id, 'ANNUAL', v_on)->>'available')::numeric, 0) as available,
                    coalesce((hr.comp_on(rp.employee_id, v_on)->>'basic')::numeric, 0) as basic
               from hr.rp_people(p, 'PAY_READ', v_on) rp where hr.money_ok(rp.employee_id)) x
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t09(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "leave_type", "en": "Leave type", "ar": "نوع الإجازة", "t": "text"}, {"k": "start_date", "en": "From", "ar": "من", "t": "date"}, {"k": "end_date", "en": "To", "ar": "إلى", "t": "date"}, {"k": "days", "en": "Days", "ar": "الأيام", "t": "num", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select r.start_date::text || rp.employee_no as _o, rp.employee_no, rp.name_en, rp.dept_en as department, t.name_en as leave_type, r.start_date, r.end_date, r.days
       from hr.leave_requests r join hr.leave_types t on t.code = r.leave_type
       join hr.rp_people(p, 'LEAVE_READ', v_to, true) rp on rp.employee_id = r.employee_id
      where r.status = 'APPROVED' and r.start_date between v_from and v_to
        and (hr.jtext(p,'leave_type') is null or r.leave_type = upper(hr.jtext(p,'leave_type')))
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_t10(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "leave_type", "en": "Leave type", "ar": "نوع الإجازة", "t": "text"}, {"k": "employees", "en": "Employees", "ar": "الموظفون", "t": "int", "s": 1}, {"k": "requests", "en": "Requests", "ar": "الطلبات", "t": "int", "s": 1}, {"k": "days", "en": "Days", "ar": "الأيام", "t": "num", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select lpad(min(t.sort)::text, 5, '0') as _o, t.name_en as leave_type, count(distinct r.employee_id)::int as employees, count(*)::int as requests, sum(r.days) as days
       from hr.leave_requests r join hr.leave_types t on t.code = r.leave_type
       join hr.rp_people(p, 'LEAVE_READ', v_to, true) rp on rp.employee_id = r.employee_id
      where r.status = 'APPROVED' and r.start_date between v_from and v_to group by t.name_en
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_c01(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "total", "en": "Counted", "ar": "المحتسبون", "t": "int", "s": 1}, {"k": "omani", "en": "Omani", "ar": "عمانيون", "t": "int", "s": 1}, {"k": "omani_pct", "en": "Omani %", "ar": "نسبة التعمين", "t": "pct"}, {"k": "target_pct", "en": "Target %", "ar": "المستهدف", "t": "pct"}, {"k": "omanis_needed", "en": "Omanis needed", "ar": "العمانيون المطلوبون", "t": "int", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(d.name_en, '(none)') as _o, coalesce(d.name_en, '(none)') as department, x.total, x.omani, round(100.0 * x.omani / nullif(x.total, 0), 1) as omani_pct,
         t.target_pct, case when t.target_pct is null then null else greatest(0, ceil(x.total * t.target_pct / 100.0) - x.omani)::int end as omanis_needed
       from (select op.department_id, count(*)::int as total, count(*) filter (where op.is_omani)::int as omani
               from hr.omanisation_population(v_ent, v_on) op group by op.department_id) x
       left join hr.departments d on d.id = x.department_id
       left join lateral (select ot.target_pct from hr.omanisation_targets ot where ot.entity_id = v_ent and ot.status = 'APPROVED' and ot.scope_type = 'DEPARTMENT'
                           and ot.scope_id = x.department_id and ot.effective_from <= v_on and (ot.effective_to is null or ot.effective_to >= v_on)
                          order by ot.effective_from desc limit 1) t on true
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_c02(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "profession_code", "en": "MoL profession code", "ar": "رمز المهنة", "t": "text"}, {"k": "omani_only", "en": "Omani only", "ar": "للعمانيين فقط", "t": "text"}, {"k": "total", "en": "Counted", "ar": "المحتسبون", "t": "int", "s": 1}, {"k": "omani", "en": "Omani", "ar": "عمانيون", "t": "int", "s": 1}, {"k": "expat", "en": "Expatriate", "ar": "وافدون", "t": "int", "s": 1}, {"k": "omani_pct", "en": "Omani %", "ar": "نسبة التعمين", "t": "pct"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(j.name_en, '(none)') as _o, j.name_en as job, j.profession_code, case when j.omani_only then 'Yes' end as omani_only,
         count(*)::int as total, count(*) filter (where op.is_omani)::int as omani, count(*) filter (where not op.is_omani)::int as expat,
         round(100.0 * count(*) filter (where op.is_omani) / nullif(count(*), 0), 1) as omani_pct
       from hr.omanisation_population(v_ent, v_on) op left join hr.job_titles j on j.id = op.job_title_id
      group by j.name_en, j.profession_code, j.omani_only
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_c03(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "expiry_date", "en": "Expiry", "ar": "تاريخ الانتهاء", "t": "date"}, {"k": "days_left", "en": "Days left", "ar": "الأيام المتبقية", "t": "int"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "document", "en": "Document", "ar": "الوثيقة", "t": "text"}, {"k": "doc_number", "en": "Number", "ar": "الرقم", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select x.expiry_date::text || x.employee_no as _o, x.expiry_date, x.days_left, x.employee_no, x.full_name_en as name_en, x.department_en as department,
         x.name_en as document, x.doc_number
       from hr.visible_expiries(v_on) x
      where x.entity_id = v_ent and x.days_left <= v_days and (v_dep is null or x.department_id = v_dep)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_c04(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "document", "en": "Missing document", "ar": "الوثيقة الناقصة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.employee_no || t.sort::text as _o, rp.employee_no, rp.name_en, rp.dept_en as department, rp.nat_en as nationality, t.name_en as document
       from hr.rp_people(p, 'DOC_READ', hr.today()) rp
       join hr.document_types t on t.is_active and t.is_mandatory
         and (t.applies_to = 'ALL' or (t.applies_to = 'OMANI' and rp.is_omani) or (t.applies_to = 'EXPAT' and not rp.is_omani))
      where not exists (select 1 from hr.employee_documents d where d.employee_id = rp.employee_id and d.doc_type = t.code and d.is_current)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_c05(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "passport", "en": "Passport", "ar": "جواز السفر", "t": "date"}, {"k": "resident_card", "en": "Resident card", "ar": "بطاقة الإقامة", "t": "date"}, {"k": "visa", "en": "Visa", "ar": "التأشيرة", "t": "date"}, {"k": "work_permit", "en": "Work permit", "ar": "تصريح العمل", "t": "date"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.employee_no as _o, rp.employee_no, rp.name_en, rp.nat_en as nationality, rp.job_en as job,
         (select max(d.expiry_date) from hr.employee_documents d where d.employee_id = rp.employee_id and d.is_current and d.doc_type = 'PASSPORT') as passport,
         (select max(d.expiry_date) from hr.employee_documents d where d.employee_id = rp.employee_id and d.is_current and d.doc_type = 'RESIDENT_CARD') as resident_card,
         (select max(d.expiry_date) from hr.employee_documents d where d.employee_id = rp.employee_id and d.is_current and d.doc_type = 'EMPLOYMENT_VISA') as visa,
         (select max(d.expiry_date) from hr.employee_documents d where d.employee_id = rp.employee_id and d.is_current and d.doc_type = 'WORK_PERMIT') as work_permit
       from hr.rp_people(p, 'DOC_READ', hr.today()) rp where not rp.is_omani
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_c06(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "nationality", "en": "Nationality", "ar": "الجنسية", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "profession_code", "en": "MoL code", "ar": "رمز المهنة", "t": "text"}, {"k": "exception", "en": "Exception", "ar": "الاستثناء", "t": "text"}, {"k": "valid_to", "en": "Valid to", "ar": "صالح حتى", "t": "date"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select rp.employee_no as _o, rp.employee_no, rp.name_en, rp.nat_en as nationality, rp.job_en as job, rp.profession_code,
         x.reason as exception, x.valid_to
       from hr.rp_people(p, 'COMPLIANCE_READ', v_on) rp
       left join lateral (select oe.reason, oe.valid_to from hr.omanisation_exceptions oe where oe.employee_id = rp.employee_id and oe.status = 'ACTIVE'
                           order by oe.created_at desc limit 1) x on true
      where not rp.is_omani and rp.omani_only
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r01(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "ref_no", "en": "Requisition", "ar": "الطلب", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "positions", "en": "Positions", "ar": "الشواغر", "t": "int", "s": 1}, {"k": "applied", "en": "Applied", "ar": "متقدم", "t": "int", "s": 1}, {"k": "shortlisted", "en": "Shortlisted", "ar": "قائمة مختصرة", "t": "int", "s": 1}, {"k": "interview", "en": "Interview", "ar": "مقابلة", "t": "int", "s": 1}, {"k": "offer", "en": "Offer", "ar": "عرض", "t": "int", "s": 1}, {"k": "hired", "en": "Hired", "ar": "تم التعيين", "t": "int", "s": 1}, {"k": "rejected", "en": "Rejected / withdrawn", "ar": "مرفوض / منسحب", "t": "int", "s": 1}, {"k": "status", "en": "Status", "ar": "الحالة", "t": "text"}, {"k": "age_days", "en": "Days open", "ar": "أيام مفتوح", "t": "int"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select r.requested_at::text as _o, r.ref_no, d.name_en as department, j.name_en as job, r.positions,
         count(a.id) filter (where a.stage = 'APPLIED')::int as applied, count(a.id) filter (where a.stage = 'SHORTLISTED')::int as shortlisted,
         count(a.id) filter (where a.stage = 'INTERVIEW')::int as interview, count(a.id) filter (where a.stage = 'OFFER')::int as offer,
         count(a.id) filter (where a.stage = 'HIRED')::int as hired, count(a.id) filter (where a.stage in ('REJECTED','WITHDRAWN'))::int as rejected,
         r.status, (hr.today() - r.requested_at::date)::int as age_days
       from hr.job_requisitions r left join hr.departments d on d.id = r.department_id left join hr.job_titles j on j.id = r.job_title_id
       left join hr.applications a on a.requisition_id = r.id
      where r.entity_id = v_ent and (r.status in ('PENDING','APPROVED','ON_HOLD') or r.updated_at >= now() - interval '180 days')
      group by r.id, r.ref_no, d.name_en, j.name_en, r.positions, r.status, r.requested_at
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r02(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "ref_no", "en": "Requisition", "ar": "الطلب", "t": "text"}, {"k": "job", "en": "Designation", "ar": "المسمى الوظيفي", "t": "text"}, {"k": "candidate", "en": "Hired", "ar": "المعين", "t": "text"}, {"k": "approved_on", "en": "Approved", "ar": "الاعتماد", "t": "date"}, {"k": "hired_on", "en": "Hired", "ar": "التعيين", "t": "date"}, {"k": "days", "en": "Days to hire", "ar": "أيام التوظيف", "t": "int"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select a.stage_at::text as _o, r.ref_no, j.name_en as job, cd.full_name_en as candidate, r.decided_at::date as approved_on, a.stage_at::date as hired_on,
         (a.stage_at::date - coalesce(r.decided_at, r.requested_at)::date)::int as days
       from hr.applications a join hr.job_requisitions r on r.id = a.requisition_id join hr.candidates cd on cd.id = a.candidate_id
       left join hr.job_titles j on j.id = r.job_title_id
      where r.entity_id = v_ent and a.stage = 'HIRED' and a.stage_at::date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r03(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "department", "en": "Department", "ar": "القسم", "t": "text"}, {"k": "reviewer", "en": "Reviewer", "ar": "المقيّم", "t": "text"}, {"k": "status", "en": "Stage", "ar": "المرحلة", "t": "text"}, {"k": "rating", "en": "Overall rating", "ar": "التقييم العام", "t": "num"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select e.employee_no as _o, e.employee_no, e.full_name_en as name_en, (select d.name_en from hr.departments d where d.id = (hr.current_assignment(e.id, c.period_end)).department_id) as department,
         rv.full_name_en as reviewer, pr.status, pr.overall_rating as rating
       from hr.perf_reviews pr join hr.perf_cycles c on c.id = pr.cycle_id join hr.employees e on e.id = pr.employee_id
       left join hr.employees rv on rv.id = pr.reviewer_id
      where c.entity_id = v_ent and (hr.juuid(p,'cycle_id') is null or c.id = hr.juuid(p,'cycle_id'))
        and (hr.juuid(p,'cycle_id') is not null or c.id = (select c2.id from hr.perf_cycles c2 where c2.entity_id = v_ent order by c2.period_end desc limit 1))
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r04(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "band", "en": "Rating", "ar": "التقييم", "t": "text"}, {"k": "employees", "en": "Employees", "ar": "الموظفون", "t": "int", "s": 1}, {"k": "share_pct", "en": "Share %", "ar": "النسبة", "t": "pct"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select b.o as _o, b.band, count(pr.id)::int as employees, round(100.0 * count(pr.id) / nullif(sum(count(pr.id)) over (), 0), 1) as share_pct
       from (values (1, '4.5 – 5  Outstanding', 4.5, 5.01), (2, '3.5 – 4.49  Exceeds', 3.5, 4.5), (3, '2.5 – 3.49  Meets', 2.5, 3.5), (4, '1.5 – 2.49  Partly meets', 1.5, 2.5), (5, 'Below 1.5  Does not meet', 0, 1.5)) b(o, band, lo, hi)
       left join (select r.* from hr.perf_reviews r join hr.perf_cycles c on c.id = r.cycle_id
                   where c.entity_id = v_ent and r.overall_rating is not null and r.status in ('ACK','DONE')
                     and c.id = coalesce(hr.juuid(p,'cycle_id'), (select c2.id from hr.perf_cycles c2 where c2.entity_id = v_ent order by c2.period_end desc limit 1))) pr
         on pr.overall_rating >= b.lo and pr.overall_rating < b.hi
      group by b.o, b.band
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r05(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "completed_on", "en": "Completed", "ar": "تاريخ الإنجاز", "t": "date"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "course", "en": "Course", "ar": "الدورة", "t": "text"}, {"k": "provider", "en": "Provider", "ar": "الجهة", "t": "text"}, {"k": "expires_on", "en": "Certificate expires", "ar": "انتهاء الشهادة", "t": "date"}, {"k": "score", "en": "Score", "ar": "النتيجة", "t": "text"}, {"k": "cost", "en": "Cost", "ar": "التكلفة", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select t.completed_on::text || e.employee_no as _o, t.completed_on, e.employee_no, e.full_name_en as name_en, k.name_en as course, k.provider, t.expires_on, t.score, t.cost
       from hr.training_records t join hr.training_courses k on k.id = t.course_id join hr.employees e on e.id = t.employee_id
      where e.entity_id = v_ent and t.status = 'COMPLETED' and t.completed_on between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r06(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "course", "en": "Course", "ar": "الدورة", "t": "text"}, {"k": "category", "en": "Category", "ar": "الفئة", "t": "text"}, {"k": "participants", "en": "Participants", "ar": "المشاركون", "t": "int", "s": 1}, {"k": "cost", "en": "Cost", "ar": "التكلفة", "t": "money", "s": 1}, {"k": "cost_per_person", "en": "Cost per person", "ar": "التكلفة للفرد", "t": "money"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select k.name_en as _o, k.name_en as course, k.category, count(*)::int as participants, coalesce(sum(t.cost), 0) as cost,
         round(coalesce(sum(t.cost), 0) / nullif(count(*), 0), 3) as cost_per_person
       from hr.training_records t join hr.training_courses k on k.id = t.course_id join hr.employees e on e.id = t.employee_id
      where e.entity_id = v_ent and t.status = 'COMPLETED' and t.completed_on between v_from and v_to group by k.name_en, k.category
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r07(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "ref_no", "en": "Case", "ar": "القضية", "t": "text"}, {"k": "incident_date", "en": "Incident", "ar": "الواقعة", "t": "date"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "category", "en": "Category", "ar": "الفئة", "t": "text"}, {"k": "status", "en": "Status", "ar": "الحالة", "t": "text"}, {"k": "penalty", "en": "Penalty", "ar": "العقوبة", "t": "text"}, {"k": "penalty_days", "en": "Days", "ar": "الأيام", "t": "num"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select dc.incident_date::text || dc.ref_no as _o, dc.ref_no, dc.incident_date, e.employee_no, e.full_name_en as name_en, dc.category, dc.status, dc.penalty, dc.penalty_days
       from hr.disciplinary_cases dc join hr.employees e on e.id = dc.employee_id
      where e.entity_id = v_ent and dc.incident_date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r08(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "ref_no", "en": "Reference", "ar": "المرجع", "t": "text"}, {"k": "occurred_on", "en": "Date", "ar": "التاريخ", "t": "date"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "injury_type", "en": "Injury", "ar": "الإصابة", "t": "text"}, {"k": "severity", "en": "Severity", "ar": "الخطورة", "t": "text"}, {"k": "lost_days", "en": "Lost days", "ar": "الأيام الضائعة", "t": "int", "s": 1}, {"k": "spf_reported_on", "en": "Reported to SPF", "ar": "إبلاغ الصندوق", "t": "date"}, {"k": "status", "en": "Status", "ar": "الحالة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select w.occurred_at::text as _o, w.ref_no, (w.occurred_at at time zone 'Asia/Muscat')::date as occurred_on, e.employee_no, e.full_name_en as name_en,
         w.injury_type, w.severity, w.lost_days, w.spf_reported_on, w.status
       from hr.work_injuries w join hr.employees e on e.id = w.employee_id
      where e.entity_id = v_ent and (w.occurred_at at time zone 'Asia/Muscat')::date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r09(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "item", "en": "Item", "ar": "المادة", "t": "text"}, {"k": "category", "en": "Category", "ar": "الفئة", "t": "text"}, {"k": "qty", "en": "Qty", "ar": "الكمية", "t": "int", "s": 1}, {"k": "serial_no", "en": "Serial no.", "ar": "الرقم التسلسلي", "t": "text"}, {"k": "issued_on", "en": "Issued", "ar": "التسليم", "t": "date"}, {"k": "due_return_on", "en": "Due back", "ar": "موعد الإرجاع", "t": "date"}, {"k": "overdue_days", "en": "Days overdue", "ar": "أيام التأخير", "t": "int"}, {"k": "value", "en": "Value", "ar": "القيمة", "t": "money", "s": 1}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select lpad((100000 - greatest(coalesce(hr.today() - i.due_return_on, -1), -1))::text, 6, '0') || e.employee_no as _o, e.employee_no, e.full_name_en as name_en,
         it.name_en as item, it.category, i.qty, i.serial_no, i.issued_on, i.due_return_on,
         case when i.due_return_on < hr.today() then (hr.today() - i.due_return_on)::int end as overdue_days, round(coalesce(it.unit_cost, 0) * i.qty, 3) as value
       from hr.asset_issues i join hr.asset_items it on it.id = i.item_id join hr.employees e on e.id = i.employee_id
      where e.entity_id = v_ent and i.status = 'ISSUED' and it.returnable
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r10(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "exit_type", "en": "Type", "ar": "النوع", "t": "text"}, {"k": "notice_given_on", "en": "Notice given", "ar": "تاريخ الإنذار", "t": "date"}, {"k": "last_working_date", "en": "Last day", "ar": "آخر يوم", "t": "date"}, {"k": "reason", "en": "Reason", "ar": "السبب", "t": "text"}, {"k": "clearance", "en": "Clearance done", "ar": "إخلاء الطرف", "t": "text"}, {"k": "status", "en": "Status", "ar": "الحالة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select x.last_working_date::text || e.employee_no as _o, e.employee_no, e.full_name_en as name_en, x.exit_type, x.notice_given_on, x.last_working_date, x.reason,
         (select count(*) filter (where t.status <> 'PENDING') || ' / ' || count(*) from hr.exit_tasks t where t.exit_id = x.id) as clearance, x.status
       from hr.exit_cases x join hr.employees e on e.id = x.employee_id
      where e.entity_id = v_ent and x.status <> 'CANCELLED' and x.last_working_date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_r11(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "expires_on", "en": "Expires", "ar": "تاريخ الانتهاء", "t": "date"}, {"k": "days_left", "en": "Days left", "ar": "الأيام المتبقية", "t": "int"}, {"k": "employee_no", "en": "Employee no.", "ar": "الرقم الوظيفي", "t": "text"}, {"k": "name_en", "en": "Name", "ar": "الاسم", "t": "text"}, {"k": "course", "en": "Course", "ar": "الدورة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select t.expires_on::text || e.employee_no as _o, t.expires_on, (t.expires_on - hr.today())::int as days_left, e.employee_no, e.full_name_en as name_en, k.name_en as course
       from hr.training_records t join hr.training_courses k on k.id = t.course_id join hr.employees e on e.id = t.employee_id
      where e.entity_id = v_ent and e.status <> 'SEPARATED' and t.status = 'COMPLETED' and t.expires_on is not null and t.expires_on <= hr.today() + v_days
        and not exists (select 1 from hr.training_records n where n.employee_id = t.employee_id and n.course_id = t.course_id and n.status = 'COMPLETED'
                         and n.completed_on > t.completed_on)
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_a01(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "at", "en": "When", "ar": "الوقت", "t": "text"}, {"k": "user", "en": "User", "ar": "المستخدم", "t": "text"}, {"k": "table", "en": "Record type", "ar": "نوع السجل", "t": "text"}, {"k": "action", "en": "Action", "ar": "الإجراء", "t": "text"}, {"k": "employee", "en": "Employee", "ar": "الموظف", "t": "text"}, {"k": "fields", "en": "Fields changed", "ar": "الحقول المعدلة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select lpad((9999999999 - extract(epoch from a.at)::bigint)::text, 12, '0') || a.id::text as _o, to_char(a.at at time zone 'Asia/Muscat', 'YYYY-MM-DD HH24:MI') as at,
         coalesce(hr.user_label(a.user_id), 'system') as "user", a.table_name as "table", a.action, e.full_name_en as employee,
         case when a.action = 'UPDATE' then (select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.new_data, '{}'::jsonb)) k
                                              where k not in ('updated_at') and (a.old_data->k) is distinct from (a.new_data->k)) end as fields
       from hr.audit_log a left join hr.employees e on e.id = a.employee_id
      where (a.at at time zone 'Asia/Muscat')::date between v_from and v_to and hr.audit_ok(a)
        and (hr.jtext(p,'table') is null or a.table_name = hr.jtext(p,'table'))
      order by a.at desc limit 5000
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_a02(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "at", "en": "When", "ar": "الوقت", "t": "text"}, {"k": "user", "en": "User", "ar": "المستخدم", "t": "text"}, {"k": "employee", "en": "Employee", "ar": "الموظف", "t": "text"}, {"k": "kind", "en": "Data", "ar": "البيانات", "t": "text"}, {"k": "detail", "en": "Detail", "ar": "التفاصيل", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select lpad((9999999999 - extract(epoch from l.at)::bigint)::text, 12, '0') || l.id::text as _o, to_char(l.at at time zone 'Asia/Muscat', 'YYYY-MM-DD HH24:MI') as at,
         hr.user_label(l.user_id) as "user", e.full_name_en as employee, l.data_kind as kind, l.detail
       from hr.access_log l left join hr.employees e on e.id = l.employee_id
      where (l.at at time zone 'Asia/Muscat')::date between v_from and v_to and (l.employee_id is null or hr.money_ok(l.employee_id) or l.data_kind not in ('SALARY','BANK','PAY_GROUP'))
      order by l.at desc limit 5000
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_a03(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "user", "en": "User", "ar": "المستخدم", "t": "text"}, {"k": "email", "en": "E-mail", "ar": "البريد", "t": "text"}, {"k": "employee", "en": "Employee", "ar": "الموظف", "t": "text"}, {"k": "roles", "en": "Roles", "ar": "الأدوار", "t": "text"}, {"k": "active", "en": "Active", "ar": "فعال", "t": "text"}, {"k": "since", "en": "Since", "ar": "منذ", "t": "date"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select coalesce(up.display_name, up.email) as _o, coalesce(up.display_name, up.email) as "user", up.email, e.full_name_en as employee,
         (select string_agg(r.name_en, ', ' order by r.sort) from hr.user_roles ur join hr.roles r on r.code = ur.role_code where ur.user_id = up.user_id and ur.revoked_at is null) as roles,
         case when up.is_active then 'Yes' else 'No' end as active, up.created_at::date as since
       from hr.user_profiles up left join hr.employees e on e.id = up.employee_id
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_a04(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "decided_at", "en": "Decided", "ar": "وقت القرار", "t": "text"}, {"k": "item", "en": "Decision", "ar": "القرار", "t": "text"}, {"k": "employee", "en": "Employee / record", "ar": "الموظف / السجل", "t": "text"}, {"k": "made_by", "en": "Prepared by", "ar": "أعدّه", "t": "text"}, {"k": "decided_by", "en": "Decided by", "ar": "قرره", "t": "text"}, {"k": "outcome", "en": "Outcome", "ar": "النتيجة", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select lpad((9999999999 - extract(epoch from x.decided_at)::bigint)::text, 12, '0') as _o, to_char(x.decided_at at time zone 'Asia/Muscat', 'YYYY-MM-DD HH24:MI') as decided_at,
         x.item, x.employee, hr.user_label(x.made_by) as made_by, hr.user_label(x.decided_by) as decided_by, x.outcome
       from (
         select 'Salary revision' as item, e.full_name_en as employee, r.proposed_by as made_by, r.decided_by, r.decided_at, r.status as outcome
           from hr.compensation_revisions r join hr.employees e on e.id = r.employee_id where r.decided_at is not null and hr.money_ok(e.id)
         union all select 'Bank account', e.full_name_en, b.requested_by, b.decided_by, b.decided_at, b.status
           from hr.employee_bank_accounts b join hr.employees e on e.id = b.employee_id where b.decided_at is not null and hr.money_ok(e.id)
         union all select 'Payroll run ' || to_char(r.period_start, 'YYYY-MM') || ' ' || r.pay_group, null, r.calculated_by, r.approved_by, r.approved_at, r.status
           from hr.payroll_runs r where r.approved_at is not null and hr.run_ok(r.pay_group)
         union all select 'Loan / advance', e.full_name_en, l.proposed_by, l.decided_by, l.decided_at, l.status
           from hr.employee_loans l join hr.employees e on e.id = l.employee_id where l.decided_at is not null and hr.money_ok(e.id)
         union all select 'One-off pay item', e.full_name_en, a.proposed_by, a.decided_by, a.decided_at, a.status
           from hr.payroll_adjustments a join hr.employees e on e.id = a.employee_id where a.decided_at is not null and hr.money_ok(e.id)
         union all select 'Final settlement', e.full_name_en, f.prepared_by, f.approved_by, f.approved_at, f.status
           from hr.final_settlements f join hr.employees e on e.id = f.employee_id where f.approved_at is not null and hr.money_ok(e.id)
         union all select 'Leave', e.full_name_en, l.requested_by, l.decided_by, l.decided_at, l.status
           from hr.leave_requests l join hr.employees e on e.id = l.employee_id where l.decided_at is not null
         union all select 'Change request (' || c.kind || ')', e.full_name_en, c.requested_by, c.decided_by, c.decided_at, c.status
           from hr.change_requests c join hr.employees e on e.id = c.employee_id where c.decided_at is not null
         union all select 'Pay rule ' || r.code, null, r.proposed_by, r.decided_by, r.decided_at, r.status from hr.pay_rules r where r.decided_at is not null
         union all select 'Time rule ' || r.code, null, r.proposed_by, r.decided_by, r.decided_at, r.status from hr.time_rules r where r.decided_at is not null
       ) x where (x.decided_at at time zone 'Asia/Muscat')::date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


create or replace function hr.rpt_a05(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ent uuid := hr.rp_entity(p);
  v_on date := coalesce(hr.jdate(p, 'as_of'), hr.today());
  v_from date := coalesce(hr.jdate(p, 'from'), date_trunc('month', hr.today())::date);
  v_to date := coalesce(hr.jdate(p, 'to'), hr.today());
  v_m0 date := case when hr.jtext(p, 'month') is null then date_trunc('month', hr.today())::date else hr.month_start(hr.jtext(p, 'month')) end;
  v_m1 date;
  v_days int := least(greatest(coalesce(hr.jint(p, 'days'), 90), 1), 3650);
  v_dep uuid := hr.juuid(p, 'department_id');
  v_run hr.payroll_runs;
  v_meta jsonb := '{}'::jsonb;
begin
  v_m1 := (v_m0 + interval '1 month - 1 day')::date;
  if v_to < v_from then raise exception 'INVALID: The end date is before the start date.'; end if;
  
  return jsonb_build_object('columns', '[{"k": "decided_at", "en": "When", "ar": "الوقت", "t": "text"}, {"k": "item", "en": "Control", "ar": "الضابط", "t": "text"}, {"k": "detail", "en": "Detail", "ar": "التفاصيل", "t": "text"}, {"k": "user", "en": "User", "ar": "المستخدم", "t": "text"}]'::jsonb, 'meta', v_meta,
    'rows', coalesce((select jsonb_agg(to_jsonb(x) - '_o' order by x._o) from (
      select x.decided_at::text as _o, to_char(x.decided_at at time zone 'Asia/Muscat', 'YYYY-MM-DD HH24:MI') as decided_at, x.item, x.detail, hr.user_label(x.uid) as "user"
       from (
         select r.approved_at as decided_at, 'Payroll run steps by the same person' as item, to_char(r.period_start, 'YYYY-MM') || ' ' || r.pay_group as detail, r.approved_by as uid
           from hr.payroll_runs r where r.approved_at is not null and hr.run_ok(r.pay_group)
            and (r.calculated_by = r.verified_by or r.verified_by = r.approved_by or r.calculated_by = r.approved_by)
         union all select r.decided_at, 'Salary revision approved by its proposer', e.employee_no, r.decided_by
           from hr.compensation_revisions r join hr.employees e on e.id = r.employee_id where r.decided_by = r.proposed_by and hr.money_ok(e.id)
         union all select b.decided_at, 'Bank account approved by its requester', e.employee_no, b.decided_by
           from hr.employee_bank_accounts b join hr.employees e on e.id = b.employee_id where b.decided_by = b.requested_by and hr.money_ok(e.id)
         union all select l.decided_at, 'Leave approved by the employee', e.employee_no, l.decided_by
           from hr.leave_requests l join hr.employees e on e.id = l.employee_id join hr.user_profiles up on up.user_id = l.decided_by and up.employee_id = l.employee_id
       ) x where x.decided_at is not null and (x.decided_at at time zone 'Asia/Muscat')::date between v_from and v_to
    ) x), '[]'::jsonb));
end $f$;


-- Runs one report. Checks the report's permission, logs money and sensitive reports in the access log.
create or replace function public.hr_run_report(p_code text, p jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d hr.report_defs; v jsonb; v_code text := upper(btrim(coalesce(p_code, ''))); v_p jsonb := coalesce(p, '{}'::jsonb); v_ent uuid;
begin
  perform hr.require_user();
  select * into d from hr.report_defs where code = v_code;
  if d.code is null then raise exception 'NOT_FOUND: Unknown report.'; end if;
  perform hr.require_perm(d.perm);
  case v_code
    when 'W01' then v := hr.rpt_w01(p);
    when 'W02' then v := hr.rpt_w02(p);
    when 'W03' then v := hr.rpt_w03(p);
    when 'W04' then v := hr.rpt_w04(p);
    when 'W05' then v := hr.rpt_w05(p);
    when 'W06' then v := hr.rpt_w06(p);
    when 'W07' then v := hr.rpt_w07(p);
    when 'W08' then v := hr.rpt_w08(p);
    when 'W09' then v := hr.rpt_w09(p);
    when 'W10' then v := hr.rpt_w10(p);
    when 'W11' then v := hr.rpt_w11(p);
    when 'W12' then v := hr.rpt_w12(p);
    when 'P01' then v := hr.rpt_p01(p);
    when 'P02' then v := hr.rpt_p02(p);
    when 'P03' then v := hr.rpt_p03(p);
    when 'P04' then v := hr.rpt_p04(p);
    when 'P05' then v := hr.rpt_p05(p);
    when 'P06' then v := hr.rpt_p06(p);
    when 'P07' then v := hr.rpt_p07(p);
    when 'P08' then v := hr.rpt_p08(p);
    when 'P09' then v := hr.rpt_p09(p);
    when 'P10' then v := hr.rpt_p10(p);
    when 'P11' then v := hr.rpt_p11(p);
    when 'P12' then v := hr.rpt_p12(p);
    when 'P13' then v := hr.rpt_p13(p);
    when 'P14' then v := hr.rpt_p14(p);
    when 'P15' then v := hr.rpt_p15(p);
    when 'T01' then v := hr.rpt_t01(p);
    when 'T02' then v := hr.rpt_t02(p);
    when 'T03' then v := hr.rpt_t03(p);
    when 'T04' then v := hr.rpt_t04(p);
    when 'T05' then v := hr.rpt_t05(p);
    when 'T06' then v := hr.rpt_t06(p);
    when 'T07' then v := hr.rpt_t07(p);
    when 'T08' then v := hr.rpt_t08(p);
    when 'T09' then v := hr.rpt_t09(p);
    when 'T10' then v := hr.rpt_t10(p);
    when 'C01' then v := hr.rpt_c01(p);
    when 'C02' then v := hr.rpt_c02(p);
    when 'C03' then v := hr.rpt_c03(p);
    when 'C04' then v := hr.rpt_c04(p);
    when 'C05' then v := hr.rpt_c05(p);
    when 'C06' then v := hr.rpt_c06(p);
    when 'R01' then v := hr.rpt_r01(p);
    when 'R02' then v := hr.rpt_r02(p);
    when 'R03' then v := hr.rpt_r03(p);
    when 'R04' then v := hr.rpt_r04(p);
    when 'R05' then v := hr.rpt_r05(p);
    when 'R06' then v := hr.rpt_r06(p);
    when 'R07' then v := hr.rpt_r07(p);
    when 'R08' then v := hr.rpt_r08(p);
    when 'R09' then v := hr.rpt_r09(p);
    when 'R10' then v := hr.rpt_r10(p);
    when 'R11' then v := hr.rpt_r11(p);
    when 'A01' then v := hr.rpt_a01(p);
    when 'A02' then v := hr.rpt_a02(p);
    when 'A03' then v := hr.rpt_a03(p);
    when 'A04' then v := hr.rpt_a04(p);
    when 'A05' then v := hr.rpt_a05(p);
    else raise exception 'NOT_FOUND: Unknown report.';
  end case;
  if d.money or d.sensitive then
    insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'REPORT', d.code || ' ' || d.name_en || ' ' || v_p::text);
  end if;
  v_ent := case when 'entity' = any(d.params) then hr.rp_entity(v_p) end;
  return v || jsonb_build_object('code', d.code, 'name_en', d.name_en, 'name_ar', d.name_ar, 'group', d.grp, 'money', d.money, 'sensitive', d.sensitive,
    'generated_at', now(), 'generated_by', hr.user_label(auth.uid()),
    'entity', (select jsonb_build_object('id', e.id, 'code', e.code, 'name_en', e.name_en, 'name_ar', e.name_ar, 'cr_number', e.cr_number)
               from hr.legal_entities e where e.id = v_ent),
    'department', (select jsonb_build_object('name_en', x.name_en, 'name_ar', x.name_ar) from hr.departments x where x.id = hr.juuid(v_p, 'department_id')));
end $$;


-- ----------------------------------------------------------------------------- schedules
create or replace function hr.user_has_perm(p_user uuid, p_perm text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from hr.user_roles ur join hr.user_profiles up on up.user_id = ur.user_id and up.is_active
                 join hr.role_permissions rp on rp.role_code = ur.role_code
                 where ur.user_id = p_user and ur.revoked_at is null and rp.perm_code = p_perm)
$$;

create or replace function hr.schedule_json(s hr.report_schedules)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(s) || jsonb_build_object(
    'report_en', d.name_en, 'report_ar', d.name_ar, 'created_by_name', hr.user_label(s.created_by),
    'recipient_names', (select jsonb_agg(jsonb_build_object('user_id', u, 'name', hr.user_label(u))) from unnest(s.recipients) u))
  from hr.report_defs d where d.code = s.code
$$;

create or replace function public.hr_list_report_schedules()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('REPORT_ADMIN');
  return coalesce((select jsonb_agg(hr.schedule_json(s) order by s.is_active desc, s.day_of_month, s.code) from hr.report_schedules s), '[]'::jsonb);
end $$;

-- People a schedule can be sent to (active users), for the schedule form.
create or replace function public.hr_report_recipients()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('REPORT_ADMIN');
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', up.user_id, 'name', coalesce(up.display_name, up.email), 'email', up.email,
      'perms', (select coalesce(jsonb_agg(distinct rp.perm_code), '[]'::jsonb) from hr.user_roles ur join hr.role_permissions rp on rp.role_code = ur.role_code
                where ur.user_id = up.user_id and ur.revoked_at is null)) order by coalesce(up.display_name, up.email))
    from hr.user_profiles up where up.is_active), '[]'::jsonb);
end $$;

-- A recipient opening the link in the reminder gets the schedule's filters (only if they are a recipient or manage schedules).
create or replace function public.hr_get_report_schedule(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s hr.report_schedules;
begin
  perform hr.require_user();
  select * into s from hr.report_schedules where id = p_id;
  if s.id is null or not (auth.uid() = any(s.recipients) or hr.has_perm('REPORT_ADMIN')) then
    raise exception 'NOT_FOUND: Schedule not found.';
  end if;
  return hr.schedule_json(s);
end $$;

create or replace function public.hr_save_report_schedule(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d hr.report_defs; v_id uuid := hr.juuid(p, 'id'); v_code text := upper(hr.jtext(p, 'code')); v_rec uuid[]; v_day int := hr.jint(p, 'day_of_month');
        v_params jsonb := coalesce(p->'params', '{}'::jsonb); u uuid; s hr.report_schedules; v_bad text;
begin
  perform hr.require_perm('REPORT_ADMIN');
  select * into d from hr.report_defs where code = v_code;
  if d.code is null then raise exception 'NOT_FOUND: Unknown report.'; end if;
  perform hr.require_perm(d.perm);
  if jsonb_typeof(v_params) <> 'object' then raise exception 'INVALID: Filters must be an object.'; end if;
  if v_day is null or v_day not between 1 and 28 then raise exception 'INVALID: Choose a day between 1 and 28.'; end if;
  select array_agg(distinct x::uuid) into v_rec from jsonb_array_elements_text(coalesce(p->'recipients', '[]'::jsonb)) x;
  if v_rec is null or cardinality(v_rec) = 0 then raise exception 'REQUIRED: Choose at least one recipient.'; end if;
  foreach u in array v_rec loop
    if not hr.user_has_perm(u, d.perm) or (d.money and upper(coalesce(v_params->>'pay_group', '')) = 'MG' and not hr.user_has_perm(u, 'MG_PAY')) then
      v_bad := coalesce(v_bad || ', ', '') || coalesce(hr.user_label(u), u::text);
    end if;
  end loop;
  if v_bad is not null then raise exception 'NOT_ALLOWED: These people may not see this report: %.', v_bad using errcode = '42501'; end if;
  if d.money and upper(coalesce(v_params->>'pay_group', '')) = 'MG' and not hr.has_perm('MG_PAY') then
    raise exception 'MG_ONLY: The management (MG) payroll is restricted to the management payroll team.' using errcode = '42501';
  end if;
  if v_id is null then
    insert into hr.report_schedules(code, name, params, recipients, day_of_month, created_by)
    values (v_code, hr.jtext(p, 'name'), v_params, v_rec, v_day, auth.uid()) returning * into s;
  else
    update hr.report_schedules set code = v_code, name = hr.jtext(p, 'name'), params = v_params, recipients = v_rec, day_of_month = v_day,
           is_active = coalesce(hr.jbool(p, 'is_active', true), true), updated_at = now()
     where id = v_id returning * into s;
    if s.id is null then raise exception 'NOT_FOUND: Schedule not found.'; end if;
  end if;
  return hr.schedule_json(s);
end $$;

create or replace function public.hr_set_report_schedule_active(p_id uuid, p_active boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.report_schedules;
begin
  perform hr.require_perm('REPORT_ADMIN');
  update hr.report_schedules set is_active = coalesce(p_active, false), updated_at = now() where id = p_id returning * into s;
  if s.id is null then raise exception 'NOT_FOUND: Schedule not found.'; end if;
  return hr.schedule_json(s);
end $$;

-- Daily job: on each schedule's day, tell every recipient (who may still see the report) that it is ready.
create or replace function hr.send_due_report_schedules(p_on date default null)
returns int language plpgsql security definer set search_path = '' as $$
declare v_on date := coalesce(p_on, hr.today()); s record; u uuid; n int := 0;
begin
  for s in select rs.*, d.name_en, d.name_ar, d.perm, d.money from hr.report_schedules rs join hr.report_defs d on d.code = rs.code
            where rs.is_active and rs.day_of_month = extract(day from v_on)::int and rs.last_sent_on is distinct from v_on loop
    foreach u in array s.recipients loop
      continue when not hr.user_has_perm(u, s.perm);
      continue when s.money and upper(coalesce(s.params->>'pay_group', '')) = 'MG' and not hr.user_has_perm(u, 'MG_PAY');
      n := n + hr.notify(u, 'REPORT', 'NORMAL',
        'Report ready: ' || coalesce(s.name, s.name_en), 'التقرير جاهز: ' || coalesce(s.name, s.name_ar),
        'Open the report centre to view or download it as PDF or Excel.', 'افتح مركز التقارير لعرضه أو تنزيله بصيغة PDF أو Excel.',
        '/reports?schedule=' || s.id::text, 'report:' || s.id::text || ':' || v_on::text);
    end loop;
    update hr.report_schedules set last_sent_on = v_on where id = s.id;
  end loop;
  return n;
end $$;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('hr-report-schedules', '15 2 * * *', 'select hr.send_due_report_schedules()');
  end if;
end $$;

-- ----------------------------------------------------------------------------- board pack
create or replace function public.hr_board_pack(p_entity uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_exec jsonb; v_run hr.payroll_runs; v_pay boolean := hr.has_perm('PAY_READ'); v_today date := hr.today();
begin
  perform hr.require_perm('EXEC_VIEW');
  v_exec := public.hr_exec_dashboard(p_entity);
  if v_pay then
    select * into v_run from hr.payroll_runs r where r.entity_id = p_entity and r.pay_group = 'NMG' and r.status in ('APPROVED','PAID')
     order by r.period_start desc limit 1;
  end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'REPORT', 'BOARD_PACK ' || p_entity::text);
  return jsonb_build_object(
    'exec', v_exec,
    'entity', (select jsonb_build_object('code', e.code, 'name_en', e.name_en, 'name_ar', e.name_ar) from hr.legal_entities e where e.id = p_entity),
    'generated_at', now(), 'generated_by', hr.user_label(auth.uid()),
    'payroll_month', case when v_run.id is not null then to_char(v_run.period_start, 'YYYY-MM') end,
    'payroll_by_department', case when v_run.id is not null then coalesce((select jsonb_agg(jsonb_build_object('name_en', coalesce(x.department_en, '(none)'),
        'name_ar', coalesce(x.department_ar, x.department_en, '(none)'), 'headcount', x.n, 'cost', x.cost) order by x.cost desc)
        from (select s.department_en, s.department_ar, count(*)::int n, sum(s.total_earnings + s.employer_cost) cost
                from hr.payslips s where s.run_id = v_run.id and hr.money_ok(s.employee_id) group by s.department_en, s.department_ar) x), '[]'::jsonb) end,
    'expiries_by_type', coalesce((select jsonb_agg(jsonb_build_object('name_en', x.name_en, 'name_ar', x.name_ar, 'expired', x.expired, 'd30', x.d30, 'd90', x.d90) order by x.expired desc, x.d30 desc)
        from (select i.name_en, i.name_ar, count(*) filter (where i.days_left < 0)::int expired, count(*) filter (where i.days_left between 0 and 30)::int d30,
                     count(*) filter (where i.days_left between 31 and 90)::int d90
                from hr.expiry_items(v_today) i join hr.employees e on e.id = i.employee_id
               where e.entity_id = p_entity and e.status <> 'SEPARATED' and i.days_left <= 90 group by i.name_en, i.name_ar) x), '[]'::jsonb),
    'leavers_by_type', coalesce((select jsonb_agg(jsonb_build_object('type', x.t, 'n', x.n) order by x.n desc)
        from (select coalesce(e.separation_type, 'OTHER') t, count(*)::int n from hr.employees e
               where e.entity_id = p_entity and e.separation_date between (v_today - interval '12 months')::date and v_today group by 1) x), '[]'::jsonb));
end $$;

-- ----------------------------------------------------------------------------- audit fixes: indexes for foreign keys
create index if not exists asset_issues_recovery_idx on hr.asset_issues(recovery_adjustment_id);
create index if not exists candidates_nationality_idx on hr.candidates(nationality);
create index if not exists consents_employee_idx on hr.consents(employee_id);
create index if not exists disciplinary_adjustment_idx on hr.disciplinary_cases(adjustment_id);
create index if not exists dsr_candidate_idx on hr.dsr_requests(candidate_id);
create index if not exists dsr_employee_idx on hr.dsr_requests(employee_id);
create index if not exists facilities_driver_idx on hr.facilities(driver_employee_id);
create index if not exists job_offers_category_idx on hr.job_offers(category_id);
create index if not exists job_offers_department_idx on hr.job_offers(department_id);
create index if not exists job_offers_grade_idx on hr.job_offers(grade_id);
create index if not exists job_offers_job_idx on hr.job_offers(job_title_id);
create index if not exists job_offers_location_idx on hr.job_offers(location_id);
create index if not exists job_requisitions_category_idx on hr.job_requisitions(category_id);
create index if not exists job_requisitions_entity_idx on hr.job_requisitions(entity_id);
create index if not exists job_requisitions_grade_idx on hr.job_requisitions(grade_id);
create index if not exists job_requisitions_location_idx on hr.job_requisitions(location_id);
create index if not exists job_requisitions_replaces_idx on hr.job_requisitions(replaces_employee_id);
create index if not exists perf_cycles_entity_idx on hr.perf_cycles(entity_id);
create index if not exists perf_plans_review_idx on hr.perf_plans(review_id);
create index if not exists report_schedules_code_idx on hr.report_schedules(code);
create index if not exists audit_log_at_idx on hr.audit_log(at desc);
create index if not exists access_log_at_idx on hr.access_log(at desc);
create index if not exists attendance_days_date_idx on hr.attendance_days(work_date);

select hr.attach_audit();
select hr.secure_api();
