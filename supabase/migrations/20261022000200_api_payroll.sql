-- AACT HRMS — 021 API: pay rules, payroll set-up, runs (calculate → verify → approve → paid), payslips, exports,
-- loans & advances, one-off adjustments, final settlements, gratuity report, parallel run, tasks.

-- ---------------------------------------------------------------------------
-- Pay rules
-- ---------------------------------------------------------------------------
create or replace function hr.pay_rule_json(r hr.pay_rules)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(r) - 'proposed_by' - 'decided_by'
         || jsonb_build_object('proposed_by_name', hr.user_label(r.proposed_by), 'decided_by_name', hr.user_label(r.decided_by),
                               'can_decide', r.status = 'PENDING' and hr.has_perm('RULES_APPROVE') and auth.uid() is distinct from r.proposed_by)
$$;

create or replace function public.hr_list_pay_rules()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  if not (hr.has_perm('PAY_READ') or hr.has_perm('RULES_PROPOSE') or hr.has_perm('RULES_APPROVE')) then
    raise exception 'NOT_ALLOWED: You do not have the PAY_READ permission.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(hr.pay_rule_json(r) order by r.code, r.effective_from desc, r.proposed_at desc)
                   from hr.pay_rules r where r.status <> 'REJECTED' or r.proposed_at > now() - interval '90 days'), '[]'::jsonb);
end $$;

create or replace function public.hr_propose_pay_rule(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_code text := hr.jtext(p,'code'); v_val jsonb := p->'value'; v_from date := hr.jdate(p,'effective_from'); v_keys text[]; k text; v_id uuid;
begin
  perform hr.require_perm('RULES_PROPOSE');
  if v_code is null or v_val is null or jsonb_typeof(v_val) <> 'object' or v_from is null then
    raise exception 'REQUIRED: Rule, values and effective date are required.';
  end if;
  if coalesce(hr.jtext(p,'legal_basis'), '') = '' then raise exception 'REQUIRED: Give the legal basis or policy reference.'; end if;
  v_keys := case v_code
    when 'SPF_OMANI' then array['er_old_age','ee_old_age','er_injury','er_job_security','ee_job_security','er_maternity','er_sick','ceiling']
    when 'SPF_EXPAT' then array['er_maternity','er_sick','er_injury','ceiling']
    when 'GRATUITY' then array['old_first_years','old_first_days','old_after_days','new_days','min_service_months']
    when 'SAVINGS_EXPAT' then array['employer_pct','active']
    when 'DEDUCTIONS' then array['max_pct']
    when 'INCOME_TAX' then array['rate_pct','annual_threshold','active']
    when 'PAY_BASIS' then array['days_divisor','hours_per_day','absent_unpaid','missing_punch_unpaid','fund_leave_unpaid']
    else null end;
  if v_keys is null then raise exception 'INVALID: Unknown rule %.', v_code; end if;
  foreach k in array v_keys loop
    if jsonb_typeof(v_val->k) <> 'number' or (v_val->>k)::numeric < 0 then
      raise exception 'INVALID: % must be a number of zero or more.', k;
    end if;
  end loop;
  if v_code = 'GRATUITY' and coalesce(v_val->>'cutoff','') !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'INVALID: The cut-off must be a date (YYYY-MM-DD).';
  end if;
  if exists (select 1 from hr.pay_rules where code = v_code and status = 'PENDING') then
    raise exception 'PENDING_EXISTS: A change to this rule is already waiting for approval.';
  end if;
  insert into hr.pay_rules(code, value, effective_from, rule_basis, legal_basis, status, proposed_by)
  values (v_code, v_val, v_from, coalesce(hr.jtext(p,'rule_basis'), 'LEGAL'), hr.jtext(p,'legal_basis'), 'PENDING', auth.uid())
  returning id into v_id;
  perform hr.notify_approvers(null, 'PENDING_HR', 'RULES_APPROVE', 'RULE', 'Payroll rule change waiting: ' || v_code,
                              'تغيير قاعدة رواتب بانتظار الاعتماد: ' || v_code, '/approvals', 'payrule:' || v_id);
  return public.hr_list_pay_rules();
end $$;

create or replace function public.hr_decide_pay_rule(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.pay_rules;
begin
  perform hr.require_perm('RULES_APPROVE');
  select * into r from hr.pay_rules where id = p_id for update;
  if r.id is null or r.status <> 'PENDING' then raise exception 'NOT_FOUND: This rule change is no longer waiting.'; end if;
  if r.proposed_by = auth.uid() then raise exception 'SELF_APPROVAL: Someone other than the proposer must approve this rule.'; end if;
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  if p_approve then
    if exists (select 1 from hr.pay_rules where code = r.code and status = 'APPROVED' and effective_from >= r.effective_from) then
      raise exception 'OVERLAP: An approved value already starts on or after %.', to_char(r.effective_from, 'DD/MM/YYYY');
    end if;
    update hr.pay_rules set effective_to = r.effective_from - 1
     where code = r.code and status = 'APPROVED' and (effective_to is null or effective_to >= r.effective_from);
  end if;
  update hr.pay_rules set status = case when p_approve then 'APPROVED' else 'REJECTED' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note),'') where id = p_id;
  return public.hr_list_pay_rules();
end $$;

-- ---------------------------------------------------------------------------
-- Set-up
-- ---------------------------------------------------------------------------
create or replace function public.hr_payroll_setup()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('PAY_READ');
  return jsonb_build_object(
    'entities', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'code', e.code, 'name_en', e.name_en, 'name_ar', e.name_ar,
                  'cr_number', e.cr_number, 'spf_employer_no', e.spf_employer_no, 'wps_bank_code', e.wps_bank_code,
                  'wps_account', e.wps_account, 'wps_payer_cr', e.wps_payer_cr) order by e.code) from hr.legal_entities e where e.is_active), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('code', c.code, 'name_en', c.name_en, 'name_ar', c.name_ar, 'kind', c.kind,
                  'is_basic', c.is_basic, 'gl_account', c.gl_account, 'spf_base', c.spf_base, 'is_active', c.is_active) order by c.sort)
                  from hr.pay_components c), '[]'::jsonb),
    'gl', coalesce((select value from hr.settings where key = 'payroll_gl'), '{}'::jsonb),
    'pay_day', (select value from hr.settings where key = 'pay_day'));
end $$;

create or replace function public.hr_save_payroll_setup(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x jsonb; k text;
begin
  perform hr.require_perm('PAY_APPROVE');
  for x in select * from jsonb_array_elements(coalesce(p->'entities', '[]'::jsonb)) loop
    update hr.legal_entities set cr_number = coalesce(hr.jtext(x,'cr_number'), cr_number),
           spf_employer_no = hr.jtext(x,'spf_employer_no'), wps_bank_code = upper(hr.jtext(x,'wps_bank_code')),
           wps_account = hr.jtext(x,'wps_account'), wps_payer_cr = hr.jtext(x,'wps_payer_cr')
     where id = hr.juuid(x,'id');
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p->'components', '[]'::jsonb)) loop
    update hr.pay_components set gl_account = hr.jtext(x,'gl_account'),
           spf_base = case when x ? 'spf_base' then hr.jbool(x,'spf_base', true) else spf_base end
     where code = hr.jtext(x,'code');
  end loop;
  if jsonb_typeof(p->'gl') = 'object' then
    for k in select jsonb_object_keys(p->'gl') loop
      if k not in ('salary_payable','spf_payable','eosb_provision','loans_receivable','salary_expense','overtime_expense','spf_expense',
                   'eosb_expense','deductions_income','income_tax_payable') then
        raise exception 'INVALID: Unknown account %.', k;
      end if;
    end loop;
    insert into hr.settings(key, value, updated_by) values ('payroll_gl', p->'gl', auth.uid())
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  end if;
  if p ? 'pay_day' then
    if hr.jint(p,'pay_day') not between 1 and 31 then raise exception 'INVALID: Pay day must be 1–31.'; end if;
    insert into hr.settings(key, value, updated_by) values ('pay_day', to_jsonb(hr.jint(p,'pay_day')::text), auth.uid())
    on conflict (key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  end if;
  return public.hr_payroll_setup();
end $$;

-- ---------------------------------------------------------------------------
-- Runs
-- ---------------------------------------------------------------------------
create or replace function hr.my_slip_in_run(p_run uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from hr.payslips s where s.run_id = p_run and s.employee_id = hr.my_employee_id())
$$;

create or replace function hr.run_json(r hr.payroll_runs)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(r) - 'calculated_by' - 'verified_by' - 'approved_by' - 'paid_by' - 'created_by' || jsonb_build_object(
    'month', to_char(r.period_start, 'YYYY-MM'),
    'entity_code', le.code, 'entity_en', le.name_en, 'entity_ar', le.name_ar,
    'calculated_by_name', hr.user_label(r.calculated_by), 'verified_by_name', hr.user_label(r.verified_by),
    'approved_by_name', hr.user_label(r.approved_by), 'paid_by_name', hr.user_label(r.paid_by),
    'attendance_locked', hr.attendance_locked(r.entity_id, r.period_start),
    'can_calculate', r.status in ('DRAFT','CALCULATED') and hr.has_perm('PAY_PREPARE'),
    'can_verify', r.status = 'CALCULATED' and hr.has_perm('PAY_VERIFY') and auth.uid() is distinct from r.calculated_by and not hr.my_slip_in_run(r.id),
    'can_approve', r.status = 'VERIFIED' and hr.has_perm('PAY_APPROVE') and auth.uid() is distinct from r.calculated_by
                   and auth.uid() is distinct from r.verified_by and not hr.my_slip_in_run(r.id),
    'can_return', r.status in ('CALCULATED','VERIFIED') and (hr.has_perm('PAY_VERIFY') or hr.has_perm('PAY_APPROVE')),
    'can_pay', r.status = 'APPROVED' and hr.has_perm('PAY_APPROVE'),
    'can_reopen', r.status = 'APPROVED' and hr.has_perm('PAY_APPROVE'),
    'can_export_bank', r.status in ('APPROVED','PAID') and hr.has_perm('PAY_APPROVE'))
  from hr.legal_entities le where le.id = r.entity_id
$$;

create or replace function public.hr_list_payroll_runs(p_entity uuid default null, p_year int default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('PAY_READ');
  return coalesce((select jsonb_agg(hr.run_json(r) order by r.period_start desc, r.entity_id)
                   from hr.payroll_runs r where (p_entity is null or r.entity_id = p_entity)
                     and (p_year is null or extract(year from r.period_start) = p_year)), '[]'::jsonb);
end $$;

create or replace function public.hr_create_payroll_run(p_entity uuid, p_month text, p_pay_date date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_m0 date := hr.month_start(p_month); r hr.payroll_runs; v_day int;
begin
  perform hr.require_perm('PAY_PREPARE');
  if not exists (select 1 from hr.legal_entities where id = p_entity) then raise exception 'NOT_FOUND: Company not found.'; end if;
  if v_m0 > date_trunc('month', hr.today())::date then raise exception 'INVALID: Payroll cannot be prepared for a future month.'; end if;
  if exists (select 1 from hr.payroll_runs where entity_id = p_entity and period_start = v_m0) then
    raise exception 'DUPLICATE: A payroll run for this month already exists.';
  end if;
  v_day := coalesce((select (value #>> '{}')::int from hr.settings where key = 'pay_day'), 28);
  insert into hr.payroll_runs(entity_id, period_start, pay_date, created_by)
  values (p_entity, v_m0, coalesce(p_pay_date, least(v_m0 + (v_day - 1), (v_m0 + interval '1 month - 1 day')::date)), auth.uid())
  returning * into r;
  return hr.run_json(r);
end $$;

create or replace function public.hr_calculate_payroll(p_run uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_PREPARE');
  select * into r from hr.payroll_runs where id = p_run for update;
  if r.id is null then raise exception 'NOT_FOUND: Payroll run not found.'; end if;
  if r.status not in ('DRAFT','CALCULATED') then raise exception 'PERIOD_LOCKED: This run is % — return or reopen it first.', lower(r.status); end if;
  if not hr.attendance_locked(r.entity_id, r.period_start) then
    raise exception 'ATTENDANCE_OPEN: Lock attendance for % first, so payroll uses final figures.', to_char(r.period_start, 'MM/YYYY');
  end if;
  perform hr.calc_run(p_run);
  update hr.payroll_runs set status = 'CALCULATED', calc_count = calc_count + 1, calculated_by = auth.uid(), calculated_at = now(),
         verified_by = null, verified_at = null, return_note = null where id = p_run returning * into r;
  return hr.run_json(r);
end $$;

create or replace function public.hr_verify_payroll(p_run uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_VERIFY');
  select * into r from hr.payroll_runs where id = p_run for update;
  if r.id is null or r.status <> 'CALCULATED' then raise exception 'NOT_FOUND: This run is not waiting for verification.'; end if;
  if r.calculated_by = auth.uid() then raise exception 'SELF_APPROVAL: Someone other than the person who calculated it must verify.'; end if;
  if hr.my_slip_in_run(p_run) then raise exception 'SELF_APPROVAL: You cannot verify a payroll that contains your own salary.'; end if;
  update hr.payroll_runs set status = 'VERIFIED', verified_by = auth.uid(), verified_at = now(),
         notes = coalesce(nullif(btrim(p_note),''), notes) where id = p_run returning * into r;
  perform hr.notify_approvers(null, 'PENDING_HR', 'PAY_APPROVE', 'PAYROLL', 'Payroll ' || to_char(r.period_start,'MM/YYYY') || ' waiting for approval',
    'رواتب ' || to_char(r.period_start,'MM/YYYY') || ' بانتظار الاعتماد', '/payroll/' || r.id, 'payroll-approve:' || r.id || ':' || r.calc_count);
  return hr.run_json(r);
end $$;

create or replace function public.hr_approve_payroll(p_run uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.payroll_runs; x record; u record;
begin
  perform hr.require_perm('PAY_APPROVE');
  select * into r from hr.payroll_runs where id = p_run for update;
  if r.id is null or r.status <> 'VERIFIED' then raise exception 'NOT_FOUND: This run is not waiting for approval.'; end if;
  if auth.uid() in (r.calculated_by, r.verified_by) then raise exception 'SELF_APPROVAL: A third person must approve the payroll.'; end if;
  if hr.my_slip_in_run(p_run) then raise exception 'SELF_APPROVAL: You cannot approve a payroll that contains your own salary.'; end if;
  update hr.payroll_runs set status = 'APPROVED', approved_by = auth.uid(), approved_at = now(),
         notes = coalesce(nullif(btrim(p_note),''), notes) where id = p_run returning * into r;
  -- loan instalments become repayments
  insert into hr.loan_repayments(loan_id, month, amount, kind, run_id)
  select l.ref_id, r.period_start, l.amount, 'PAYROLL', r.id
  from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id
  where s.run_id = r.id and l.code = 'LOAN' and l.ref_id is not null and l.amount > 0;
  update hr.employee_loans set status = 'CLOSED'
   where status = 'APPROVED' and id in (select ref_id from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id
                                       where s.run_id = r.id and l.code = 'LOAN') and hr.loan_outstanding(id) <= 0;
  for x in select s.id, s.employee_id from hr.payslips s where s.run_id = r.id loop
    perform hr.notify(hr.employee_user(x.employee_id), 'PAYSLIP', 'NORMAL', 'Payslip for ' || to_char(r.period_start,'MM/YYYY') || ' is ready',
      'كشف راتب ' || to_char(r.period_start,'MM/YYYY') || ' جاهز', null, null, '/payslips', 'payslip:' || x.id);
  end loop;
  return hr.run_json(r);
end $$;

create or replace function public.hr_return_payroll(p_run uuid, p_note text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.payroll_runs;
begin
  if not (hr.has_perm('PAY_VERIFY') or hr.has_perm('PAY_APPROVE')) then
    raise exception 'NOT_ALLOWED: You do not have the PAY_VERIFY permission.' using errcode = '42501';
  end if;
  if coalesce(length(btrim(p_note)), 0) < 3 then raise exception 'REQUIRED: Say what must be corrected.'; end if;
  select * into r from hr.payroll_runs where id = p_run for update;
  if r.id is null or r.status not in ('CALCULATED','VERIFIED') then raise exception 'NOT_FOUND: This run cannot be returned.'; end if;
  update hr.payroll_runs set status = 'DRAFT', verified_by = null, verified_at = null, return_note = btrim(p_note) where id = p_run returning * into r;
  perform hr.notify(r.calculated_by, 'PAYROLL', 'HIGH', 'Payroll ' || to_char(r.period_start,'MM/YYYY') || ' returned for correction',
    'أعيدت رواتب ' || to_char(r.period_start,'MM/YYYY') || ' للتصحيح', r.return_note, r.return_note, '/payroll/' || r.id, 'payroll-return:' || r.id || ':' || now()::text);
  return hr.run_json(r);
end $$;

create or replace function public.hr_mark_payroll_paid(p_run uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_APPROVE');
  update hr.payroll_runs set status = 'PAID', paid_by = auth.uid(), paid_at = now() where id = p_run and status = 'APPROVED' returning * into r;
  if r.id is null then raise exception 'NOT_FOUND: Only an approved run can be marked paid.'; end if;
  return hr.run_json(r);
end $$;

create or replace function public.hr_reopen_payroll(p_run uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_APPROVE');
  if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'REQUIRED: Give a reason for reopening.'; end if;
  select * into r from hr.payroll_runs where id = p_run for update;
  if r.id is null or r.status <> 'APPROVED' then raise exception 'NOT_FOUND: Only an approved, unpaid run can be reopened.'; end if;
  delete from hr.loan_repayments where run_id = p_run;
  update hr.employee_loans set status = 'APPROVED' where status = 'CLOSED' and hr.loan_outstanding(id) > 0;
  update hr.payroll_runs set status = 'DRAFT', verified_by = null, verified_at = null, approved_by = null, approved_at = null,
         reopen_reason = btrim(p_reason) where id = p_run returning * into r;
  return hr.run_json(r);
end $$;

create or replace function hr.slip_brief(s hr.payslips)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(s) - 'account_number' - 'iban' - 'civil_number' || jsonb_build_object(
    'account_masked', case when s.account_number is null then null else hr.mask_tail(coalesce(s.iban, s.account_number)) end,
    'has_bank', s.account_number is not null)
$$;

create or replace function public.hr_get_payroll_run(p_run uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_READ');
  select * into r from hr.payroll_runs where id = p_run;
  if r.id is null then raise exception 'NOT_FOUND: Payroll run not found.'; end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'PAYROLL', 'run ' || to_char(r.period_start,'YYYY-MM'));
  return hr.run_json(r) || jsonb_build_object(
    'payslips', coalesce((select jsonb_agg(hr.slip_brief(s) order by s.employee_no) from hr.payslips s where s.run_id = p_run), '[]'::jsonb),
    'by_code', coalesce((select jsonb_agg(x order by x->>'kind', (x->>'sort')::int) from (
        select jsonb_build_object('code', l.code, 'name_en', min(l.name_en), 'name_ar', min(l.name_ar), 'kind', l.kind,
               'amount', sum(l.amount), 'employees', count(distinct l.payslip_id), 'sort', min(l.sort)) x
        from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id where s.run_id = p_run group by l.code, l.kind) t), '[]'::jsonb),
    'pending_inputs', jsonb_build_object(
        'adjustments', (select count(*) from hr.payroll_adjustments a join hr.employees e on e.id = a.employee_id
                        where e.entity_id = r.entity_id and a.period_start = r.period_start and a.status = 'PENDING'),
        'loans', (select count(*) from hr.employee_loans l join hr.employees e on e.id = l.employee_id
                  where e.entity_id = r.entity_id and l.status = 'PENDING' and l.first_month <= r.period_start)));
end $$;

create or replace function hr.slip_full(s hr.payslips)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.slip_brief(s) || jsonb_build_object(
    'account_number', s.account_number, 'iban', s.iban,
    'month', to_char(r.period_start, 'YYYY-MM'), 'period_start', r.period_start, 'pay_date', r.pay_date, 'run_status', r.status,
    'entity_en', le.name_en, 'entity_ar', le.name_ar, 'entity_cr', le.cr_number,
    'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'payslip_id' order by l.kind, l.sort, l.code) from hr.payslip_lines l where l.payslip_id = s.id), '[]'::jsonb))
  from hr.payroll_runs r join hr.legal_entities le on le.id = r.entity_id where r.id = s.run_id
$$;

create or replace function public.hr_get_payslip(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.payslips; r hr.payroll_runs;
begin
  perform hr.require_user();
  select * into s from hr.payslips where id = p_id;
  if s.id is null then raise exception 'NOT_FOUND: Payslip not found.'; end if;
  select * into r from hr.payroll_runs where id = s.run_id;
  if not (hr.has_perm('PAY_READ') or (hr.is_me(s.employee_id) and r.status in ('APPROVED','PAID'))) then
    raise exception 'NOT_ALLOWED: You cannot see this payslip.' using errcode = '42501';
  end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), s.employee_id, 'PAYSLIP', to_char(r.period_start,'YYYY-MM'));
  return hr.slip_full(s);
end $$;

create or replace function public.hr_my_payslips()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_user();
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'month', to_char(r.period_start,'YYYY-MM'), 'pay_date', r.pay_date,
            'status', r.status, 'net', s.net, 'total_earnings', s.total_earnings, 'total_deductions', s.total_deductions) order by r.period_start desc)
          from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
          where s.employee_id = hr.my_employee_id() and r.status in ('APPROVED','PAID')), '[]'::jsonb);
end $$;

create or replace function public.hr_employee_payroll(p_employee uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_basic numeric;
begin
  perform hr.require_user();
  if not (hr.has_perm('PAY_READ') or hr.is_me(p_employee)) then
    raise exception 'NOT_ALLOWED: You cannot see payroll details.' using errcode = '42501';
  end if;
  v_basic := coalesce((hr.comp_on(p_employee, hr.today())->>'basic')::numeric, 0);
  return jsonb_build_object(
    'payslips', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'month', to_char(r.period_start,'YYYY-MM'), 'status', r.status,
              'net', s.net, 'total_earnings', s.total_earnings, 'total_deductions', s.total_deductions) order by r.period_start desc)
            from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
            where s.employee_id = p_employee and (hr.has_perm('PAY_READ') or r.status in ('APPROVED','PAID'))), '[]'::jsonb),
    'loans', coalesce((select jsonb_agg(hr.loan_json(l) order by l.proposed_at desc) from hr.employee_loans l where l.employee_id = p_employee), '[]'::jsonb),
    'gratuity', case when hr.has_perm('PAY_READ') then hr.gratuity_calc(p_employee, hr.today(), v_basic) end);
end $$;

-- Data for the bank salary file, journal, register and SPF report (CSV is built in the browser).
create or replace function public.hr_payroll_export(p_run uuid, p_kind text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r hr.payroll_runs; le hr.legal_entities;
begin
  perform hr.require_perm('PAY_READ');
  select * into r from hr.payroll_runs where id = p_run;
  if r.id is null then raise exception 'NOT_FOUND: Payroll run not found.'; end if;
  select * into le from hr.legal_entities where id = r.entity_id;
  if p_kind = 'WPS' then
    if not hr.has_perm('PAY_APPROVE') then raise exception 'NOT_ALLOWED: You do not have the PAY_APPROVE permission.' using errcode = '42501'; end if;
    if r.status not in ('APPROVED','PAID') then raise exception 'INVALID: The bank file is available after approval.'; end if;
    insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'BANK', 'WPS file ' || to_char(r.period_start,'YYYY-MM'));
    return jsonb_build_object('employer_cr', coalesce(le.wps_payer_cr, le.cr_number), 'payer_cr', coalesce(le.wps_payer_cr, le.cr_number),
      'bank_code', le.wps_bank_code, 'account', le.wps_account, 'year', extract(year from r.period_start)::int,
      'month', extract(month from r.period_start)::int, 'pay_date', r.pay_date,
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
          'employee_no', s.employee_no, 'id_type', case when s.civil_number is null then 'P' else 'C' end, 'id', coalesce(s.civil_number, s.employee_no),
          'name', s.full_name_en, 'bank', s.swift_code, 'account', coalesce(s.iban, s.account_number), 'days', s.paid_days,
          'net', s.net, 'basic', round(s.basic * s.employed_days / s.days_in_period, 3),
          'extra_hours', (select coalesce(sum(l.qty), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code = 'OT_WORKDAY'),
          'extra_income', s.total_earnings - (select coalesce(sum(l.amount), 0) from hr.payslip_lines l join hr.pay_components c on c.code = l.code
                                                where l.payslip_id = s.id and c.is_basic),
          'deductions', s.total_deductions - (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_EE%'),
          'social_security', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_EE%'),
          'has_bank', s.account_number is not null) order by s.employee_no)
        from hr.payslips s where s.run_id = p_run and s.net > 0), '[]'::jsonb));
  elsif p_kind = 'JOURNAL' then
    return jsonb_build_object('month', to_char(r.period_start,'YYYY-MM'), 'status', r.status, 'gl', (select value from hr.settings where key = 'payroll_gl'),
      'lines', coalesce((select jsonb_agg(x order by x->>'side' desc, x->>'account', x->>'cost_centre') from (
        select jsonb_build_object('account', coalesce(l.gl_account, '—'), 'cost_centre', coalesce(s.cost_centre, ''), 'code', l.code,
               'name', min(l.name_en), 'kind', l.kind, 'side', case when l.kind = 'DEDUCTION' then 'CR' else 'DR' end, 'amount', sum(l.amount)) x
        from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id where s.run_id = p_run
        group by l.gl_account, s.cost_centre, l.code, l.kind) t), '[]'::jsonb),
      'net', (select coalesce(sum(net), 0) from hr.payslips where run_id = p_run),
      'employer_cost', (select coalesce(sum(employer_cost), 0) from hr.payslips where run_id = p_run),
      'spf_employer', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id where s.run_id = p_run and l.code like 'SPF_ER%'),
      'eosb', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id where s.run_id = p_run and l.code in ('EOSB_ACCRUAL','SAVINGS_FUND')));
  elsif p_kind = 'REGISTER' then
    return jsonb_build_object('month', to_char(r.period_start,'YYYY-MM'),
      'codes', coalesce((select jsonb_agg(x order by (x->>'sort')::int, x->>'code') from (
          select jsonb_build_object('code', l.code, 'name_en', min(l.name_en), 'kind', l.kind, 'sort', min(l.sort) + case l.kind when 'EARNING' then 0 when 'DEDUCTION' then 1000 else 2000 end) x
          from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id where s.run_id = p_run group by l.code, l.kind) t), '[]'::jsonb),
      'rows', coalesce((select jsonb_agg(jsonb_build_object('employee_no', s.employee_no, 'name', s.full_name_en, 'department', s.department_en,
          'paid_days', s.paid_days, 'unpaid_days', s.unpaid_days, 'earnings', s.total_earnings, 'deductions', s.total_deductions,
          'net', s.net, 'employer_cost', s.employer_cost,
          'amounts', (select jsonb_object_agg(l.code || ':' || l.kind, l.amount) from hr.payslip_lines l where l.payslip_id = s.id)) order by s.employee_no)
        from hr.payslips s where s.run_id = p_run), '[]'::jsonb));
  elsif p_kind = 'SPF' then
    return jsonb_build_object('month', to_char(r.period_start,'YYYY-MM'), 'employer_no', le.spf_employer_no,
      'rows', coalesce((select jsonb_agg(jsonb_build_object('employee_no', s.employee_no, 'name', s.full_name_en, 'civil_number', s.civil_number,
          'is_omani', s.is_omani,
          'wage', (select max(l.qty) from hr.payslip_lines l where l.payslip_id = s.id and l.code in ('SPF_ER_MATERNITY','SPF_ER_SICK','SPF_ER_JOB_SECURITY')),
          'employee', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_EE%'),
          'employer', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_ER%'),
          'lines', (select jsonb_object_agg(l.code, l.amount) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_%')) order by s.employee_no)
        from hr.payslips s where s.run_id = p_run
          and exists (select 1 from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF_%')), '[]'::jsonb));
  end if;
  raise exception 'INVALID: Unknown export %.', p_kind;
end $$;

-- ---------------------------------------------------------------------------
-- Parallel run: legacy payroll figures compared with this run
-- ---------------------------------------------------------------------------
create or replace function public.hr_save_parallel(p_run uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x jsonb; v_n int := 0; v_err jsonb := '[]'::jsonb; i int := 0;
begin
  perform hr.require_perm('PAY_PREPARE');
  if not exists (select 1 from hr.payroll_runs where id = p_run) then raise exception 'NOT_FOUND: Payroll run not found.'; end if;
  if jsonb_typeof(p->'rows') <> 'array' then raise exception 'REQUIRED: No rows.'; end if;
  if hr.jbool(p, 'replace') then delete from hr.payroll_parallel where run_id = p_run; end if;
  for x in select * from jsonb_array_elements(p->'rows') loop
    i := i + 1;
    begin
      if coalesce(hr.jtext(x,'employee_no'), '') = '' then raise exception 'Employee number is empty.'; end if;
      if coalesce(x->>'net','') !~ '^-?\d{1,9}(\.\d{1,3})?$' then raise exception 'Net pay must be a number with at most 3 decimals.'; end if;
      insert into hr.payroll_parallel(run_id, employee_no, legacy_gross, legacy_net, note, loaded_by)
      values (p_run, upper(hr.jtext(x,'employee_no')), nullif(x->>'gross','')::numeric, (x->>'net')::numeric, hr.jtext(x,'note'), auth.uid())
      on conflict (run_id, employee_no) do update set legacy_gross = excluded.legacy_gross, legacy_net = excluded.legacy_net,
             note = excluded.note, loaded_by = excluded.loaded_by, loaded_at = now();
      v_n := v_n + 1;
    exception when others then
      v_err := v_err || jsonb_build_array(jsonb_build_object('row', i, 'message', sqlerrm));
    end;
  end loop;
  return jsonb_build_object('loaded', v_n, 'errors', v_err);
end $$;

create or replace function public.hr_parallel_report(p_run uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('PAY_READ');
  return jsonb_build_object(
    'loaded', (select count(*) from hr.payroll_parallel where run_id = p_run),
    'rows', coalesce((select jsonb_agg(x order by abs((x->>'diff')::numeric) desc nulls first, x->>'employee_no') from (
      select jsonb_build_object('employee_no', coalesce(s.employee_no, pp.employee_no), 'name', s.full_name_en,
             'system_gross', s.total_earnings, 'system_net', s.net, 'legacy_gross', pp.legacy_gross, 'legacy_net', pp.legacy_net,
             'diff', case when s.id is not null and pp.employee_no is not null then s.net - pp.legacy_net end,
             'status', case when s.id is null then 'ONLY_LEGACY' when pp.employee_no is null then 'ONLY_SYSTEM'
                            when abs(s.net - pp.legacy_net) < 0.001 then 'MATCH' else 'DIFF' end, 'note', pp.note) x
      from (select * from hr.payslips where run_id = p_run) s
      full join (select * from hr.payroll_parallel where run_id = p_run) pp on pp.employee_no = s.employee_no) t), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- Loans & advances
-- ---------------------------------------------------------------------------
create or replace function hr.loan_json(l hr.employee_loans)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(l.employee_id) || to_jsonb(l) - 'proposed_by' - 'decided_by' || jsonb_build_object(
    'repaid', l.amount - hr.loan_outstanding(l.id), 'outstanding', hr.loan_outstanding(l.id),
    'months_left', case when l.installment > 0 then ceil(hr.loan_outstanding(l.id) / l.installment) else null end,
    'proposed_by_name', hr.user_label(l.proposed_by), 'decided_by_name', hr.user_label(l.decided_by),
    'can_decide', l.status = 'PENDING' and hr.has_perm('PAY_APPROVE') and auth.uid() is distinct from l.proposed_by and not hr.is_me(l.employee_id),
    'can_cancel', (l.status = 'PENDING' and (auth.uid() = l.proposed_by or hr.has_perm('PAY_APPROVE')))
                  or (l.status = 'APPROVED' and hr.has_perm('PAY_APPROVE') and not exists (select 1 from hr.loan_repayments x where x.loan_id = l.id)),
    'repayments', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(x.month,'YYYY-MM'), 'amount', x.amount, 'kind', x.kind) order by x.month)
                            from hr.loan_repayments x where x.loan_id = l.id), '[]'::jsonb))
$$;

create or replace function public.hr_list_loans(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_status text := hr.jtext(p,'status'); v_emp uuid := hr.juuid(p,'employee_id');
begin
  perform hr.require_perm('PAY_READ');
  return coalesce((select jsonb_agg(hr.loan_json(l) order by l.proposed_at desc) from hr.employee_loans l
                   where (v_status is null or l.status = v_status or (v_status = 'OPEN' and l.status in ('PENDING','APPROVED')))
                     and (v_emp is null or l.employee_id = v_emp)), '[]'::jsonb);
end $$;

create or replace function public.hr_propose_loan(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_amt numeric := hr.jmoney(p,'amount'); v_inst numeric := hr.jmoney(p,'installment');
        v_kind text := coalesce(upper(hr.jtext(p,'kind')), 'LOAN'); v_first date := hr.month_start(hr.jtext(p,'first_month')); l hr.employee_loans; e hr.employees;
begin
  perform hr.require_perm('PAY_PREPARE');
  select * into e from hr.employees where id = v_emp;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if e.status = 'SEPARATED' then raise exception 'INVALID: The employee has left.'; end if;
  if hr.is_me(v_emp) then raise exception 'SELF_APPROVAL: You cannot propose a loan for yourself.'; end if;
  if v_kind not in ('LOAN','ADVANCE') then raise exception 'INVALID: Choose loan or advance.'; end if;
  if v_amt is null or v_amt <= 0 then raise exception 'INVALID_AMOUNT: Give the amount.'; end if;
  v_inst := coalesce(v_inst, case when v_kind = 'ADVANCE' then v_amt end);
  if v_inst is null or v_inst <= 0 or v_inst > v_amt then raise exception 'INVALID_AMOUNT: The instalment must be more than 0 and not more than the amount.'; end if;
  if exists (select 1 from hr.payroll_runs r where r.entity_id = e.entity_id and r.period_start = v_first and r.status in ('APPROVED','PAID')) then
    raise exception 'PERIOD_LOCKED: Payroll for % is already approved — start next month.', to_char(v_first,'MM/YYYY');
  end if;
  insert into hr.employee_loans(employee_id, kind, amount, installment, first_month, reason, proposed_by)
  values (v_emp, v_kind, v_amt, v_inst, v_first, btrim(coalesce(hr.jtext(p,'reason'), '')), auth.uid()) returning * into l;
  perform hr.notify_approvers(null, 'PENDING_HR', 'PAY_APPROVE', 'LOAN', initcap(lower(v_kind)) || ' waiting: ' || e.full_name_en || ', OMR ' || v_amt,
    case when v_kind = 'ADVANCE' then 'سلفة' else 'قرض' end || ' بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en), '/approvals', 'loan:' || l.id);
  return hr.loan_json(l);
end $$;

create or replace function public.hr_decide_loan(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l hr.employee_loans;
begin
  perform hr.require_perm('PAY_APPROVE');
  select * into l from hr.employee_loans where id = p_id for update;
  if l.id is null or l.status <> 'PENDING' then raise exception 'NOT_FOUND: This loan is no longer waiting.'; end if;
  if l.proposed_by = auth.uid() or hr.is_me(l.employee_id) then raise exception 'SELF_APPROVAL: Someone other than you must approve this.'; end if;
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  update hr.employee_loans set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(btrim(p_note),'') where id = p_id returning * into l;
  perform hr.notify(hr.employee_user(l.employee_id), 'LOAN', 'NORMAL', initcap(lower(l.kind)) || ' ' || lower(l.status) || ': OMR ' || l.amount,
    case when l.status = 'APPROVED' then 'تم اعتماد ' else 'تم رفض ' end || case when l.kind = 'ADVANCE' then 'السلفة' else 'القرض' end,
    l.decision_note, l.decision_note, '/payslips', 'loan-done:' || l.id);
  return hr.loan_json(l);
end $$;

create or replace function public.hr_cancel_loan(p_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare l hr.employee_loans;
begin
  perform hr.require_user();
  select * into l from hr.employee_loans where id = p_id for update;
  if l.id is null then raise exception 'NOT_FOUND: Loan not found.'; end if;
  if l.status = 'PENDING' and (auth.uid() = l.proposed_by or hr.has_perm('PAY_APPROVE')) then null;
  elsif l.status = 'APPROVED' and hr.has_perm('PAY_APPROVE') and not exists (select 1 from hr.loan_repayments where loan_id = l.id) then
    if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'REQUIRED: Give a reason for cancelling an approved loan.'; end if;
    if exists (select 1 from hr.payslip_lines pl join hr.payslips s on s.id = pl.payslip_id join hr.payroll_runs r on r.id = s.run_id
               where pl.ref_id = l.id and r.status in ('CALCULATED','VERIFIED')) then
      raise exception 'INVALID: An instalment is in a payroll waiting for approval — return that payroll first.';
    end if;
  else
    raise exception 'NOT_ALLOWED: This loan cannot be cancelled.' using errcode = '42501';
  end if;
  update hr.employee_loans set status = 'CANCELLED', decision_note = coalesce(nullif(btrim(p_reason),''), decision_note) where id = p_id returning * into l;
  return hr.loan_json(l);
end $$;

-- ---------------------------------------------------------------------------
-- One-off adjustments (bonus, commission, arrears, penalties …) — maker-checker
-- ---------------------------------------------------------------------------
create or replace function hr.pay_adj_json(a hr.payroll_adjustments)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(a.employee_id) || to_jsonb(a) - 'proposed_by' - 'decided_by' || jsonb_build_object(
    'month', to_char(a.period_start,'YYYY-MM'),
    'proposed_by_name', hr.user_label(a.proposed_by), 'decided_by_name', hr.user_label(a.decided_by),
    'can_decide', a.status = 'PENDING' and hr.has_perm('PAY_APPROVE') and auth.uid() is distinct from a.proposed_by and not hr.is_me(a.employee_id))
$$;

create or replace function public.hr_list_pay_adjustments(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_status text := hr.jtext(p,'status'); v_month text := hr.jtext(p,'month'); v_emp uuid := hr.juuid(p,'employee_id');
begin
  perform hr.require_perm('PAY_READ');
  return coalesce((select jsonb_agg(hr.pay_adj_json(a) order by a.period_start desc, a.proposed_at desc) from (
      select * from hr.payroll_adjustments a where (v_status is null or a.status = v_status)
        and (v_month is null or a.period_start = hr.month_start(v_month)) and (v_emp is null or a.employee_id = v_emp)
      order by a.period_start desc, a.proposed_at desc limit 500) a), '[]'::jsonb);
end $$;

create or replace function public.hr_propose_pay_adjustments(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r jsonb; i int := 0; v_ok int := 0; v_err jsonb := '[]'::jsonb; v_emp uuid; e hr.employees; v_m date; v_code text; v_kind text; v_amt numeric;
begin
  perform hr.require_perm('PAY_PREPARE');
  if jsonb_typeof(p->'rows') <> 'array' or jsonb_array_length(p->'rows') = 0 then raise exception 'REQUIRED: No rows.'; end if;
  if jsonb_array_length(p->'rows') > 2000 then raise exception 'INVALID: At most 2000 rows at a time.'; end if;
  for r in select * from jsonb_array_elements(p->'rows') loop
    i := i + 1;
    begin
      v_emp := coalesce(hr.juuid(r,'employee_id'), (select id from hr.employees where upper(employee_no) = upper(hr.jtext(r,'employee_no'))));
      select * into e from hr.employees where id = v_emp;
      if e.id is null then raise exception 'Employee not found.'; end if;
      if hr.is_me(v_emp) then raise exception 'You cannot propose an adjustment for yourself.'; end if;
      v_m := hr.month_start(hr.jtext(r,'month'));
      v_code := upper(coalesce(hr.jtext(r,'code'), ''));
      v_kind := case when v_code in ('BONUS','COMMISSION','ARREARS','ALLOWANCE','OTHER_EARN') then 'EARNING'
                     when v_code in ('PENALTY','DAMAGE','OTHER_DED') then 'DEDUCTION' end;
      if v_kind is null then raise exception 'Unknown code %.', v_code; end if;
      v_amt := hr.jmoney(r,'amount');
      if v_amt is null or v_amt <= 0 then raise exception 'Amount must be more than 0.'; end if;
      if coalesce(length(btrim(hr.jtext(r,'reason'))), 0) < 3 then raise exception 'Give a reason.'; end if;
      if exists (select 1 from hr.payroll_runs x where x.entity_id = e.entity_id and x.period_start = v_m and x.status in ('VERIFIED','APPROVED','PAID')) then
        raise exception 'Payroll for % is already verified or approved.', to_char(v_m,'MM/YYYY');
      end if;
      insert into hr.payroll_adjustments(employee_id, period_start, kind, code, amount, reason, proposed_by)
      values (v_emp, v_m, v_kind, v_code, v_amt, btrim(hr.jtext(r,'reason')), auth.uid());
      v_ok := v_ok + 1;
    exception when others then
      if jsonb_array_length(v_err) < 200 then
        v_err := v_err || jsonb_build_array(jsonb_build_object('row', i, 'message', regexp_replace(sqlerrm, '^[A-Z_]+: ', '')));
      end if;
    end;
  end loop;
  if v_ok > 0 then
    perform hr.notify_approvers(null, 'PENDING_HR', 'PAY_APPROVE', 'PAY_ADJ', v_ok || ' payroll adjustments waiting',
      v_ok || ' تعديلات رواتب بانتظار الاعتماد', '/approvals', 'pay-adj:' || now()::text);
  end if;
  return jsonb_build_object('proposed', v_ok, 'errors', v_err);
end $$;

create or replace function public.hr_decide_pay_adjustments(p_ids uuid[], p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a hr.payroll_adjustments; v_n int := 0;
begin
  perform hr.require_perm('PAY_APPROVE');
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  for a in select * from hr.payroll_adjustments where id = any(p_ids) and status = 'PENDING' for update loop
    if a.proposed_by = auth.uid() then raise exception 'SELF_APPROVAL: Someone other than the proposer must approve this.'; end if;
    if hr.is_me(a.employee_id) then raise exception 'SELF_APPROVAL: You cannot approve your own pay.'; end if;
    if exists (select 1 from hr.payroll_runs x join hr.employees e on e.entity_id = x.entity_id
               where e.id = a.employee_id and x.period_start = a.period_start and x.status in ('VERIFIED','APPROVED','PAID')) then
      raise exception 'PERIOD_LOCKED: Payroll for % is already verified or approved.', to_char(a.period_start,'MM/YYYY');
    end if;
    update hr.payroll_adjustments set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(),
           decided_at = now(), decision_note = nullif(btrim(p_note),'') where id = a.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'NOT_FOUND: Nothing is waiting.'; end if;
  return jsonb_build_object('decided', v_n);
end $$;

-- ---------------------------------------------------------------------------
-- Final settlements
-- ---------------------------------------------------------------------------
create or replace function hr.settlement_json(s hr.final_settlements)
returns jsonb language sql stable security definer set search_path = '' as $$
  select hr.emp_brief(s.employee_id) || to_jsonb(s) - 'prepared_by' - 'approved_by' || jsonb_build_object(
    'join_date', e.join_date, 'nationality', e.nationality, 'civil_number', e.civil_number,
    'job_en', j.name_en, 'job_ar', j.name_ar, 'entity_en', le.name_en, 'entity_ar', le.name_ar,
    'prepared_by_name', hr.user_label(s.prepared_by), 'approved_by_name', hr.user_label(s.approved_by),
    'can_decide', s.status = 'PREPARED' and hr.has_perm('PAY_APPROVE') and auth.uid() is distinct from s.prepared_by and not hr.is_me(s.employee_id),
    'can_cancel', s.status = 'PREPARED' and (auth.uid() = s.prepared_by or hr.has_perm('PAY_APPROVE')),
    'can_pay', s.status = 'APPROVED' and hr.has_perm('PAY_APPROVE'))
  from hr.employees e
  join hr.legal_entities le on le.id = e.entity_id
  left join hr.employee_assignments a on a.id = (hr.current_assignment(e.id, s.last_working_date)).id
  left join hr.job_titles j on j.id = a.job_title_id
  where e.id = s.employee_id
$$;

create or replace function public.hr_preview_settlement(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_last date := hr.jdate(p,'last_working_date'); e hr.employees;
begin
  perform hr.require_perm('PAY_PREPARE');
  select * into e from hr.employees where id = v_emp;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if v_last is null then raise exception 'REQUIRED: Give the last working day.'; end if;
  if v_last < e.join_date then raise exception 'INVALID: The last working day is before the joining date.'; end if;
  return hr.emp_brief(v_emp) || jsonb_build_object('join_date', e.join_date, 'nationality', e.nationality)
         || hr.settlement_calc(v_emp, v_last, coalesce(hr.jnum(p,'notice_days'), 0), coalesce(p->'other', '[]'::jsonb));
end $$;

create or replace function public.hr_save_settlement(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_last date := hr.jdate(p,'last_working_date'); e hr.employees; c jsonb; s hr.final_settlements;
        v_reason text := coalesce(upper(hr.jtext(p,'reason')), 'RESIGNATION'); x jsonb;
begin
  perform hr.require_perm('PAY_PREPARE');
  select * into e from hr.employees where id = v_emp;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if hr.is_me(v_emp) then raise exception 'SELF_APPROVAL: You cannot prepare your own settlement.'; end if;
  if v_last is null or v_last < e.join_date then raise exception 'INVALID: Give a valid last working day.'; end if;
  if v_reason not in ('RESIGNATION','TERMINATION','END_OF_CONTRACT','RETIREMENT','DEATH','OTHER') then raise exception 'INVALID: Unknown reason.'; end if;
  if exists (select 1 from hr.final_settlements where employee_id = v_emp and status in ('PREPARED','APPROVED','PAID')) then
    raise exception 'DUPLICATE: This employee already has a final settlement.';
  end if;
  for x in select * from jsonb_array_elements(coalesce(p->'other', '[]'::jsonb)) loop
    if x->>'kind' not in ('EARNING','DEDUCTION') or coalesce(x->>'amount','') !~ '^\d{1,9}(\.\d{1,3})?$' or coalesce(length(btrim(x->>'label')), 0) < 2 then
      raise exception 'INVALID: Each extra line needs a label, earning or deduction, and an amount.';
    end if;
  end loop;
  c := hr.settlement_calc(v_emp, v_last, coalesce(hr.jnum(p,'notice_days'), 0), coalesce(p->'other', '[]'::jsonb));
  insert into hr.final_settlements(employee_id, last_working_date, reason, notice_days, basic, gross, gratuity, leave_days, leave_pay,
                                   notice_pay, loan_recovery, other_earnings, other_deductions, net, details, note, prepared_by)
  values (v_emp, v_last, v_reason, (c->>'notice_days')::numeric, (c->>'basic')::numeric, (c->>'gross')::numeric, (c->>'gratuity')::numeric,
          (c->>'leave_days')::numeric, (c->>'leave_pay')::numeric, (c->>'notice_pay')::numeric, (c->>'loan_recovery')::numeric,
          (c->>'other_earnings')::numeric, (c->>'other_deductions')::numeric, (c->>'net')::numeric, c, hr.jtext(p,'note'), auth.uid())
  returning * into s;
  perform hr.notify_approvers(null, 'PENDING_HR', 'PAY_APPROVE', 'SETTLEMENT', 'Final settlement waiting: ' || e.full_name_en,
    'تسوية نهائية بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en), '/approvals', 'settlement:' || s.id);
  return hr.settlement_json(s);
end $$;

create or replace function public.hr_decide_settlement(p_id uuid, p_approve boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.final_settlements; c jsonb; x jsonb; v_left numeric; v_amt numeric;
begin
  perform hr.require_perm('PAY_APPROVE');
  select * into s from hr.final_settlements where id = p_id for update;
  if s.id is null or s.status <> 'PREPARED' then raise exception 'NOT_FOUND: This settlement is not waiting for approval.'; end if;
  if s.prepared_by = auth.uid() or hr.is_me(s.employee_id) then raise exception 'SELF_APPROVAL: Someone other than the preparer must approve this.'; end if;
  if not p_approve then
    if coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
    update hr.final_settlements set status = 'CANCELLED', decision_note = btrim(p_note), approved_by = null where id = p_id returning * into s;
    return hr.settlement_json(s);
  end if;
  -- re-check: figures must still match (loans repaid or leave taken since preparing would change them)
  c := hr.settlement_calc(s.employee_id, s.last_working_date, s.notice_days, s.details->'other');
  if abs((c->>'net')::numeric - s.net) >= 0.001 then
    raise exception 'INVALID: The figures changed since this settlement was prepared (net now %). Cancel it and prepare it again.', (c->>'net')::numeric;
  end if;
  update hr.final_settlements set status = 'APPROVED', approved_by = auth.uid(), approved_at = now(), decision_note = nullif(btrim(p_note),'')
   where id = p_id returning * into s;
  for x in select * from jsonb_array_elements(coalesce(s.details->'loans', '[]'::jsonb)) loop
    v_left := hr.loan_outstanding((x->>'id')::uuid);
    if v_left > 0 then
      insert into hr.loan_repayments(loan_id, month, amount, kind, settlement_id)
      values ((x->>'id')::uuid, date_trunc('month', s.last_working_date)::date, v_left, 'SETTLEMENT', s.id);
      update hr.employee_loans set status = 'CLOSED' where id = (x->>'id')::uuid;
    end if;
  end loop;
  if s.leave_days > 0 then
    if (s.details->>'leave_partial_accrual')::numeric > 0 then
      insert into hr.leave_ledger(employee_id, leave_type, entry_date, days, kind, note, created_by)
      values (s.employee_id, 'ANNUAL', s.last_working_date, (s.details->>'leave_partial_accrual')::numeric, 'ADJUSTMENT',
              'Accrual to the last working day (final settlement)', auth.uid());
    end if;
    insert into hr.leave_ledger(employee_id, leave_type, entry_date, days, kind, note, created_by)
    values (s.employee_id, 'ANNUAL', s.last_working_date, -s.leave_days, 'ADJUSTMENT', 'Leave paid out in the final settlement', auth.uid());
  end if;
  return hr.settlement_json(s);
end $$;

create or replace function public.hr_cancel_settlement(p_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.final_settlements;
begin
  perform hr.require_user();
  select * into s from hr.final_settlements where id = p_id for update;
  if s.id is null or s.status <> 'PREPARED' then raise exception 'NOT_FOUND: Only a prepared settlement can be withdrawn.'; end if;
  if not (auth.uid() = s.prepared_by or hr.has_perm('PAY_APPROVE')) then raise exception 'NOT_ALLOWED: Only the preparer can withdraw it.' using errcode = '42501'; end if;
  update hr.final_settlements set status = 'CANCELLED', decision_note = nullif(btrim(p_reason),'') where id = p_id returning * into s;
  return hr.settlement_json(s);
end $$;

create or replace function public.hr_mark_settlement_paid(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.final_settlements;
begin
  perform hr.require_perm('PAY_APPROVE');
  update hr.final_settlements set status = 'PAID', paid_at = now() where id = p_id and status = 'APPROVED' returning * into s;
  if s.id is null then raise exception 'NOT_FOUND: Only an approved settlement can be marked paid.'; end if;
  return hr.settlement_json(s);
end $$;

create or replace function public.hr_list_settlements(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_status text := hr.jtext(p,'status');
begin
  perform hr.require_perm('PAY_READ');
  return coalesce((select jsonb_agg(hr.settlement_json(s) order by s.prepared_at desc) from hr.final_settlements s
                   where v_status is null or s.status = v_status), '[]'::jsonb);
end $$;

create or replace function public.hr_get_settlement(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s hr.final_settlements;
begin
  perform hr.require_user();
  select * into s from hr.final_settlements where id = p_id;
  if s.id is null then raise exception 'NOT_FOUND: Settlement not found.'; end if;
  if not (hr.has_perm('PAY_READ') or (hr.is_me(s.employee_id) and s.status in ('APPROVED','PAID'))) then
    raise exception 'NOT_ALLOWED: You cannot see this settlement.' using errcode = '42501';
  end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), s.employee_id, 'SETTLEMENT', 'view');
  return hr.settlement_json(s);
end $$;

-- ---------------------------------------------------------------------------
-- Gratuity accrued (provision report)
-- ---------------------------------------------------------------------------
create or replace function public.hr_gratuity_report(p_entity uuid default null, p_as_of date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_on date := coalesce(p_as_of, hr.today());
begin
  perform hr.require_perm('PAY_READ');
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'SALARY', 'gratuity report ' || v_on);
  return jsonb_build_object('as_of', v_on, 'rows', coalesce((select jsonb_agg(x.j order by x.no) from (
      select e.employee_no as no, hr.emp_brief(e.id) || jsonb_build_object('join_date', e.join_date, 'nationality', e.nationality, 'status', e.status)
             || hr.gratuity_calc(e.id, v_on, coalesce((hr.comp_on(e.id, v_on)->>'basic')::numeric, 0)) as j
      from hr.employees e
      where e.nationality <> 'OM' and e.status <> 'SEPARATED' and e.join_date <= v_on and (p_entity is null or e.entity_id = p_entity)) x), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------------
-- Tasks: add payroll items to "waiting for my decision"
-- ---------------------------------------------------------------------------
create or replace function public.hr_list_my_tasks()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_res jsonb;
begin
  perform hr.require_user();
  select jsonb_build_object(
    'leave', coalesce((select jsonb_agg(hr.leave_json(r) order by r.start_date) from hr.leave_requests r
                       where r.status like 'PENDING%' and hr.can_decide(r.status, r.employee_id, r.requested_by, 'LEAVE_APPROVE')), '[]'::jsonb),
    'corrections', coalesce((select jsonb_agg(hr.correction_json(c) order by c.work_date) from hr.attendance_corrections c
                       where c.status like 'PENDING%' and hr.can_decide(c.status, c.employee_id, c.requested_by, 'ATT_APPROVE')), '[]'::jsonb),
    'overtime', coalesce((select jsonb_agg(hr.overtime_json(o) order by o.work_date) from hr.overtime_requests o
                       where o.status like 'PENDING%' and hr.can_decide(o.status, o.employee_id, o.requested_by, 'ATT_APPROVE')), '[]'::jsonb),
    'adjustments', case when hr.has_perm('LEAVE_APPROVE') then coalesce((select jsonb_agg(hr.adjustment_json(a) order by a.proposed_at)
                       from hr.leave_adjustments a where a.status = 'PENDING' and a.proposed_by <> auth.uid() and not hr.is_me(a.employee_id)), '[]'::jsonb)
                       else '[]'::jsonb end,
    'rules', case when hr.has_perm('RULES_APPROVE') then coalesce((select jsonb_agg(hr.time_rule_json(t)) from hr.time_rules t
                       where t.status = 'PENDING' and t.proposed_by is distinct from auth.uid()), '[]'::jsonb) else '[]'::jsonb end,
    'pay_rules', case when hr.has_perm('RULES_APPROVE') then coalesce((select jsonb_agg(hr.pay_rule_json(t)) from hr.pay_rules t
                       where t.status = 'PENDING' and t.proposed_by is distinct from auth.uid()), '[]'::jsonb) else '[]'::jsonb end,
    'payroll', coalesce((select jsonb_agg(j order by j->>'period_start') from (select hr.run_json(r) j from hr.payroll_runs r
                       where r.status in ('CALCULATED','VERIFIED')) t
                       where (j->>'can_verify')::boolean or (j->>'can_approve')::boolean), '[]'::jsonb),
    'loans', case when hr.has_perm('PAY_APPROVE') then coalesce((select jsonb_agg(hr.loan_json(l) order by l.proposed_at) from hr.employee_loans l
                       where l.status = 'PENDING' and l.proposed_by <> auth.uid() and not hr.is_me(l.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'pay_adjustments', case when hr.has_perm('PAY_APPROVE') then coalesce((select jsonb_agg(hr.pay_adj_json(a) order by a.proposed_at) from hr.payroll_adjustments a
                       where a.status = 'PENDING' and a.proposed_by <> auth.uid() and not hr.is_me(a.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'settlements', case when hr.has_perm('PAY_APPROVE') then coalesce((select jsonb_agg(hr.settlement_json(s) order by s.prepared_at) from hr.final_settlements s
                       where s.status = 'PREPARED' and s.prepared_by <> auth.uid() and not hr.is_me(s.employee_id)), '[]'::jsonb) else '[]'::jsonb end)
  into v_res;
  return v_res || jsonb_build_object('count',
    jsonb_array_length(v_res->'leave') + jsonb_array_length(v_res->'corrections') + jsonb_array_length(v_res->'overtime')
    + jsonb_array_length(v_res->'adjustments') + jsonb_array_length(v_res->'rules') + jsonb_array_length(v_res->'pay_rules')
    + jsonb_array_length(v_res->'payroll') + jsonb_array_length(v_res->'loans') + jsonb_array_length(v_res->'pay_adjustments')
    + jsonb_array_length(v_res->'settlements'));
end $$;

-- Dashboard: count the new task kinds too
create or replace function public.hr_time_dashboard()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_me uuid := hr.my_employee_id(); v_today date := hr.today(); v_res jsonb := '{}'::jsonb; v_tasks jsonb;
begin
  perform hr.require_user();
  if hr.has_perm('ATT_READ') or exists (select 1 from hr.team_of(v_me)) then
    v_res := v_res || jsonb_build_object('today', (
      select jsonb_build_object(
        'date', v_today,
        'present', count(*) filter (where a.status = 'PRESENT'),
        'absent', count(*) filter (where a.status = 'ABSENT'),
        'missing', count(*) filter (where a.status = 'MISSING_PUNCH'),
        'late', count(*) filter (where a.late_minutes > 0),
        'leave', count(*) filter (where a.status = 'LEAVE'),
        'off', count(*) filter (where a.status in ('REST','HOLIDAY')),
        'scope', case when hr.has_perm('ATT_READ') then 'ALL' else 'TEAM' end)
      from hr.attendance_days a
      where a.work_date = v_today
        and a.employee_id in (select employee_id from hr.visible_employees('ATT_READ', null) where employee_id is distinct from
                              case when hr.has_perm('ATT_READ') then null else v_me end)));
    v_res := v_res || jsonb_build_object('away_next_14', coalesce((
      select jsonb_agg(hr.emp_brief(r.employee_id) || jsonb_build_object('leave_type', r.leave_type, 'name_en', t.name_en, 'name_ar', t.name_ar,
               'start_date', r.start_date, 'end_date', r.end_date, 'status', r.status) order by r.start_date)
      from hr.leave_requests r join hr.leave_types t on t.code = r.leave_type
      where r.status in ('APPROVED','PENDING_MANAGER','PENDING_HR') and r.start_date <= v_today + 14 and r.end_date >= v_today
        and r.employee_id in (select employee_id from hr.visible_employees('LEAVE_READ', null))
        and r.employee_id is distinct from v_me), '[]'::jsonb));
  end if;
  if v_me is not null then
    v_res := v_res || jsonb_build_object('mine', jsonb_build_object(
      'today', (select hr.attendance_json(a) from hr.attendance_days a where a.employee_id = v_me and a.work_date = v_today),
      'annual', hr.leave_balance(v_me, 'ANNUAL', v_today),
      'sick', hr.leave_balance(v_me, 'SICK', v_today),
      'pending', (select count(*) from hr.leave_requests r where r.employee_id = v_me and r.status like 'PENDING%'),
      'next_leave', (select jsonb_build_object('leave_type', r.leave_type, 'name_en', t.name_en, 'name_ar', t.name_ar,
                       'start_date', r.start_date, 'end_date', r.end_date, 'status', r.status)
                     from hr.leave_requests r join hr.leave_types t on t.code = r.leave_type
                     where r.employee_id = v_me and r.status in ('APPROVED','PENDING_MANAGER','PENDING_HR') and r.end_date >= v_today
                     order by r.start_date limit 1),
      'last_payslip', (select jsonb_build_object('id', s.id, 'month', to_char(r.period_start,'YYYY-MM'), 'net', s.net)
                       from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
                       where s.employee_id = v_me and r.status in ('APPROVED','PAID') order by r.period_start desc limit 1)));
  end if;
  if hr.has_perm('PAY_READ') then
    v_res := v_res || jsonb_build_object('payroll', (select hr.run_json(r) from hr.payroll_runs r order by r.period_start desc, r.created_at desc limit 1));
  end if;
  v_tasks := public.hr_list_my_tasks();
  return v_res || jsonb_build_object('tasks', jsonb_build_object(
    'leave', jsonb_array_length(v_tasks->'leave'), 'corrections', jsonb_array_length(v_tasks->'corrections'),
    'overtime', jsonb_array_length(v_tasks->'overtime'), 'adjustments', jsonb_array_length(v_tasks->'adjustments'),
    'rules', jsonb_array_length(v_tasks->'rules') + jsonb_array_length(v_tasks->'pay_rules'),
    'payroll', jsonb_array_length(v_tasks->'payroll'), 'loans', jsonb_array_length(v_tasks->'loans'),
    'pay_adjustments', jsonb_array_length(v_tasks->'pay_adjustments'), 'settlements', jsonb_array_length(v_tasks->'settlements'),
    'count', (v_tasks->>'count')::int));
end $$;

select hr.attach_audit();
select hr.secure_api();
