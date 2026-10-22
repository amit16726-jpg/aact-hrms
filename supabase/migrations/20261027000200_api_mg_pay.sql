-- AACT HRMS — 1.9.0 API: management (MG) pay confidentiality.
-- Each function below is the current definition with the MG checks added (hr.require_money / hr.money_ok for an employee's
-- money items, hr.require_run / hr.run_ok for payroll runs, hr.money_users / hr.notify_money for approval notifications).
-- Idempotent. No destructive statements.

CREATE OR REPLACE FUNCTION hr.change_json(c hr.change_requests)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select hr.emp_brief(c.employee_id) || jsonb_build_object(
    'id', c.id, 'kind', c.kind,
    -- bank details are only shown to people who may see bank data, or the employee
    'changes', case when c.kind = 'BANK' and not ((hr.has_perm('EMP_BANK_READ') and hr.money_ok(c.employee_id)) or hr.is_me(c.employee_id))
                    then jsonb_build_object('bank_name', c.changes->>'bank_name', 'account_number', hr.mask_tail(c.changes->>'account_number'))
                    else c.changes end,
    'reason', c.reason, 'status', c.status, 'requested_by', c.requested_by, 'requested_by_name', hr.user_label(c.requested_by),
    'requested_at', c.requested_at, 'due_date', c.due_date,
    'overdue', c.status = 'PENDING' and c.due_date < hr.today(),
    'decided_by_name', hr.user_label(c.decided_by), 'decided_at', c.decided_at, 'decision_note', c.decision_note,
    'can_decide', c.status = 'PENDING' and hr.has_perm('SS_APPROVE') and auth.uid() <> c.requested_by and not hr.is_me(c.employee_id),
    'can_cancel', c.status = 'PENDING' and auth.uid() = c.requested_by)
$function$
;
CREATE OR REPLACE FUNCTION hr.exit_json(x hr.exit_cases)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select hr.emp_brief(x.employee_id) || to_jsonb(x) || jsonb_build_object(
    'min_notice_days', hr.notice_min_days(x.employee_id), 'is_omani', (select nationality = 'OM' from hr.employees where id = x.employee_id),
    'employee_status', (select status from hr.employees where id = x.employee_id),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'title_en', t.title_en, 'title_ar', t.title_ar, 'ref_id', t.ref_id,
               'status', t.status, 'note', t.note, 'done_by_name', hr.user_label(t.done_by), 'done_at', t.done_at) order by t.sort) from hr.exit_tasks t where t.exit_id = x.id), '[]'::jsonb),
    'settlement', (select jsonb_build_object('id', s.id, 'status', s.status, 'net', case when hr.money_ok(x.employee_id) then s.net end) from hr.final_settlements s where s.employee_id = x.employee_id
                   and s.status not in ('CANCELLED') order by s.prepared_at desc limit 1),
    'open_assets', (select count(*) from hr.asset_issues a where a.employee_id = x.employee_id and a.status = 'ISSUED'),
    'created_by_name', hr.user_label(x.created_by), 'completed_by_name', hr.user_label(x.completed_by),
    'can_manage', x.status = 'OPEN' and hr.has_perm('EXIT_MANAGE') and not hr.is_me(x.employee_id))
$function$
;
CREATE OR REPLACE FUNCTION hr.letter_json(l hr.letters)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_snap jsonb := l.snapshot; v_salary_ok boolean := (hr.has_perm('EMP_SALARY_READ') and hr.money_ok(l.employee_id)) or hr.is_me(l.employee_id);
begin
  if v_snap is not null and not v_salary_ok then v_snap := v_snap - 'salary'; end if;
  return hr.emp_brief(l.employee_id) || jsonb_build_object(
    'id', l.id, 'letter_type', l.letter_type, 'language', l.language, 'addressee', l.addressee, 'purpose', l.purpose,
    'details', l.details, 'include_salary', l.include_salary, 'status', l.status,
    'requested_by_name', hr.user_label(l.requested_by), 'requested_at', l.requested_at, 'self_requested', hr.employee_user(l.employee_id) = l.requested_by,
    'prepared_by_name', hr.user_label(l.prepared_by), 'prepared_at', l.prepared_at,
    'approved_by_name', hr.user_label(l.approved_by), 'approved_at', l.approved_at, 'decision_note', l.decision_note,
    'ref_no', l.ref_no, 'verify_code', case when l.status = 'ISSUED' and (hr.is_me(l.employee_id) or hr.has_perm('LETTER_PREPARE')) then l.verify_code end,
    'issue_date', l.issue_date, 'snapshot', v_snap, 'salary_hidden', l.include_salary and not v_salary_ok,
    'revoked', l.revoked_at is not null, 'revoked_at', l.revoked_at, 'revoke_reason', l.revoke_reason,
    'can_prepare', l.status = 'REQUESTED' and hr.has_perm('LETTER_PREPARE') and not hr.is_me(l.employee_id)
                   and (not l.include_salary or hr.money_ok(l.employee_id)),
    'can_approve', l.status = 'PREPARED' and hr.has_perm('LETTER_APPROVE') and not hr.is_me(l.employee_id)
                   and auth.uid() is distinct from l.prepared_by
                   and (not l.include_salary or (hr.has_perm('EMP_SALARY_READ') and hr.money_ok(l.employee_id))),
    'can_cancel', l.status in ('REQUESTED','PREPARED') and (auth.uid() = l.requested_by or hr.has_perm('LETTER_PREPARE')) ,
    'can_revoke', l.status = 'ISSUED' and l.revoked_at is null and hr.has_perm('LETTER_APPROVE'));
end $function$
;
CREATE OR REPLACE FUNCTION hr.loan_json(l hr.employee_loans)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select hr.emp_brief(l.employee_id) || to_jsonb(l) - 'proposed_by' - 'decided_by' || jsonb_build_object(
    'repaid', l.amount - hr.loan_outstanding(l.id), 'outstanding', hr.loan_outstanding(l.id),
    'months_left', case when l.installment > 0 then ceil(hr.loan_outstanding(l.id) / l.installment) else null end,
    'proposed_by_name', hr.user_label(l.proposed_by), 'decided_by_name', hr.user_label(l.decided_by),
    'can_decide', l.status = 'PENDING' and hr.has_perm('PAY_APPROVE') and auth.uid() is distinct from l.proposed_by and not hr.is_me(l.employee_id) and hr.money_ok(l.employee_id),
    'can_cancel', hr.money_ok(l.employee_id) and ((l.status = 'PENDING' and (auth.uid() = l.proposed_by or hr.has_perm('PAY_APPROVE')))
                  or (l.status = 'APPROVED' and hr.has_perm('PAY_APPROVE') and not exists (select 1 from hr.loan_repayments x where x.loan_id = l.id))),
    'repayments', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(x.month,'YYYY-MM'), 'amount', x.amount, 'kind', x.kind) order by x.month)
                            from hr.loan_repayments x where x.loan_id = l.id), '[]'::jsonb))
$function$
;
CREATE OR REPLACE FUNCTION hr.pay_adj_json(a hr.payroll_adjustments)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select hr.emp_brief(a.employee_id) || to_jsonb(a) - 'proposed_by' - 'decided_by' || jsonb_build_object(
    'month', to_char(a.period_start,'YYYY-MM'),
    'proposed_by_name', hr.user_label(a.proposed_by), 'decided_by_name', hr.user_label(a.decided_by),
    'can_decide', a.status = 'PENDING' and hr.has_perm('PAY_APPROVE') and auth.uid() is distinct from a.proposed_by and not hr.is_me(a.employee_id) and hr.money_ok(a.employee_id))
$function$
;
CREATE OR REPLACE FUNCTION hr.run_json(r hr.payroll_runs)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select to_jsonb(r) - 'calculated_by' - 'verified_by' - 'approved_by' - 'paid_by' - 'created_by' || jsonb_build_object(
    'month', to_char(r.period_start, 'YYYY-MM'),
    'entity_code', le.code, 'entity_en', le.name_en, 'entity_ar', le.name_ar,
    'calculated_by_name', hr.user_label(r.calculated_by), 'verified_by_name', hr.user_label(r.verified_by),
    'approved_by_name', hr.user_label(r.approved_by), 'paid_by_name', hr.user_label(r.paid_by),
    'attendance_locked', hr.attendance_locked(r.entity_id, r.period_start),
    'can_calculate', r.status in ('DRAFT','CALCULATED') and hr.has_perm('PAY_PREPARE') and hr.run_ok(r.pay_group),
    'can_verify', r.status = 'CALCULATED' and hr.has_perm('PAY_VERIFY') and auth.uid() is distinct from r.calculated_by and not hr.my_slip_in_run(r.id) and hr.run_ok(r.pay_group),
    'can_approve', r.status = 'VERIFIED' and hr.has_perm('PAY_APPROVE') and auth.uid() is distinct from r.calculated_by
                   and auth.uid() is distinct from r.verified_by and not hr.my_slip_in_run(r.id) and hr.run_ok(r.pay_group),
    'can_return', r.status in ('CALCULATED','VERIFIED') and (hr.has_perm('PAY_VERIFY') or hr.has_perm('PAY_APPROVE')) and hr.run_ok(r.pay_group),
    'can_pay', r.status = 'APPROVED' and hr.has_perm('PAY_APPROVE') and hr.run_ok(r.pay_group),
    'can_reopen', r.status = 'APPROVED' and hr.has_perm('PAY_APPROVE') and hr.run_ok(r.pay_group),
    'can_export_bank', r.status in ('APPROVED','PAID') and hr.has_perm('PAY_APPROVE') and hr.run_ok(r.pay_group))
  from hr.legal_entities le where le.id = r.entity_id
$function$
;
CREATE OR REPLACE FUNCTION hr.salary_access(p_employee uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v text;
begin
  v := hr.require_employee_access(p_employee);
  if not hr.is_me(p_employee) then perform hr.require_money(p_employee); end if;
  if hr.is_me(p_employee) and not hr.has_perm('EMP_SALARY_READ') then return 'SELF'; end if;
  if hr.has_perm('EMP_SALARY_READ') or hr.has_perm('EMP_SALARY_WRITE') or hr.has_perm('SALARY_APPROVE') then
    return 'FULL';
  end if;
  raise exception 'NOT_ALLOWED: You cannot see salary details.' using errcode = '42501';
end $function$
;
CREATE OR REPLACE FUNCTION hr.settlement_calc(p_employee uuid, p_last date, p_notice_days numeric, p_other jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e hr.employees; comp jsonb; v_basic numeric := 0; v_gross numeric := 0; g jsonb; basis jsonb; v_div numeric; b jsonb;
  v_leave numeric := 0; v_dim int; v_part numeric := 0; v_leave_pay numeric; v_notice numeric; v_loans numeric := 0;
  v_oe numeric := 0; v_od numeric := 0; x jsonb; v_lines jsonb := '[]'::jsonb; v_warn jsonb := '[]'::jsonb; t hr.leave_types;
  v_loan_list jsonb;
begin
  select * into e from hr.employees where id = p_employee;
  comp := hr.comp_on(p_employee, p_last);
  if comp is null then v_warn := v_warn || jsonb_build_array('No approved salary structure.');
  else v_basic := (comp->>'basic')::numeric; v_gross := (comp->>'gross')::numeric; end if;
  basis := coalesce(hr.pay_rule('PAY_BASIS', p_last), '{}'::jsonb);
  v_div := hr.pnum(basis, 'days_divisor', 30); if v_div <= 0 then v_div := 30; end if;
  g := hr.gratuity_calc(p_employee, p_last, v_basic);
  -- annual leave available on the last day, plus the accrual for the part of the last month not yet accrued
  b := hr.leave_balance(p_employee, 'ANNUAL', p_last);
  select * into t from hr.leave_types where code = 'ANNUAL';
  if b is not null then
    v_leave := coalesce((b->>'available')::numeric, 0);
    v_dim := extract(day from (date_trunc('month', p_last) + interval '1 month - 1 day'))::int;
    if t.accrual = 'MONTHLY' and p_last < (date_trunc('month', p_last) + interval '1 month - 1 day')::date
       and not exists (select 1 from hr.leave_ledger where employee_id = p_employee and leave_type = 'ANNUAL' and kind = 'ACCRUAL'
                       and period_key = to_char(p_last, 'YYYY-MM')) then
      v_part := round(t.quota_days / 12.0 * (p_last - greatest(date_trunc('month', p_last)::date, e.join_date) + 1) / v_dim, 2);
      v_leave := v_leave + v_part;
    end if;
  end if;
  v_leave := round(v_leave, 2);
  v_leave_pay := round(greatest(v_leave, 0) * v_gross / v_div, 3);
  if v_leave < 0 then v_warn := v_warn || jsonb_build_array('Annual leave balance is negative (' || v_leave || ' days) — not recovered automatically.'); end if;
  v_notice := round(coalesce(p_notice_days, 0) * v_gross / v_div, 3);
  select coalesce(sum(hr.loan_outstanding(l.id)), 0),
         coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'outstanding', hr.loan_outstanding(l.id))), '[]'::jsonb)
    into v_loans, v_loan_list
    from hr.employee_loans l where l.employee_id = p_employee and l.status = 'APPROVED';
  for x in select * from jsonb_array_elements(coalesce(p_other, '[]'::jsonb)) loop
    if x->>'kind' = 'EARNING' then v_oe := v_oe + coalesce((x->>'amount')::numeric, 0);
    else v_od := v_od + coalesce((x->>'amount')::numeric, 0); end if;
  end loop;
  if exists (select 1 from hr.payroll_runs r where r.entity_id = e.entity_id and r.pay_group = e.pay_group and r.period_start = date_trunc('month', p_last)::date
             and r.status in ('APPROVED','PAID')) is false then
    v_warn := v_warn || jsonb_build_array('Salary for ' || to_char(p_last, 'MM/YYYY') || ' up to the last working day is paid through that month''s payroll run.');
  end if;
  return jsonb_build_object('employee_id', p_employee, 'last_working_date', p_last, 'basic', v_basic, 'gross', v_gross,
    'gratuity', coalesce((g->>'total')::numeric, 0), 'gratuity_detail', g, 'leave_days', v_leave, 'leave_partial_accrual', v_part,
    'leave_pay', v_leave_pay, 'notice_days', coalesce(p_notice_days, 0), 'notice_pay', v_notice, 'loan_recovery', v_loans, 'loans', v_loan_list,
    'other_earnings', v_oe, 'other_deductions', v_od, 'other', coalesce(p_other, '[]'::jsonb),
    'net', coalesce((g->>'total')::numeric, 0) + v_leave_pay + v_notice + v_oe - v_loans - v_od,
    'daily_gross', round(v_gross / v_div, 4), 'warnings', v_warn);
end $function$
;
CREATE OR REPLACE FUNCTION hr.settlement_json(s hr.final_settlements)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select hr.emp_brief(s.employee_id) || to_jsonb(s) - 'prepared_by' - 'approved_by' || jsonb_build_object(
    'join_date', e.join_date, 'nationality', e.nationality, 'civil_number', e.civil_number,
    'job_en', j.name_en, 'job_ar', j.name_ar, 'entity_en', le.name_en, 'entity_ar', le.name_ar,
    'prepared_by_name', hr.user_label(s.prepared_by), 'approved_by_name', hr.user_label(s.approved_by),
    'can_decide', s.status = 'PREPARED' and hr.has_perm('PAY_APPROVE') and auth.uid() is distinct from s.prepared_by and not hr.is_me(s.employee_id) and hr.money_ok(s.employee_id),
    'can_cancel', s.status = 'PREPARED' and (auth.uid() = s.prepared_by or hr.has_perm('PAY_APPROVE')) and hr.money_ok(s.employee_id),
    'can_pay', s.status = 'APPROVED' and hr.has_perm('PAY_APPROVE') and hr.money_ok(s.employee_id))
  from hr.employees e
  join hr.legal_entities le on le.id = e.entity_id
  left join hr.employee_assignments a on a.id = (hr.current_assignment(e.id, s.last_working_date)).id
  left join hr.job_titles j on j.id = a.job_title_id
  where e.id = s.employee_id
$function$
;
CREATE OR REPLACE FUNCTION public.hr_approve_payroll(p_run uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs; x record; u record;
begin
  perform hr.require_perm('PAY_APPROVE');
  perform hr.require_run(p_run);
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
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_calculate_payroll(p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_PREPARE');
  perform hr.require_run(p_run);
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
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_cancel_loan(p_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l hr.employee_loans;
begin
  perform hr.require_user();
  select * into l from hr.employee_loans where id = p_id for update;
  if l.id is null then raise exception 'NOT_FOUND: Loan not found.'; end if;
  perform hr.require_money(l.employee_id);
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
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_cancel_settlement(p_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s hr.final_settlements;
begin
  perform hr.require_user();
  select * into s from hr.final_settlements where id = p_id for update;
  if s.id is null or s.status <> 'PREPARED' then raise exception 'NOT_FOUND: Only a prepared settlement can be withdrawn.'; end if;
  perform hr.require_money(s.employee_id);
  if not (auth.uid() = s.prepared_by or hr.has_perm('PAY_APPROVE')) then raise exception 'NOT_ALLOWED: Only the preparer can withdraw it.' using errcode = '42501'; end if;
  update hr.final_settlements set status = 'CANCELLED', decision_note = nullif(btrim(p_reason),'') where id = p_id returning * into s;
  return hr.settlement_json(s);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_res jsonb := '{}'::jsonb; v_me uuid := hr.my_employee_id(); v_uid uuid := hr.require_user();
begin
  if hr.has_perm('EMP_READ') then
    v_res := v_res || jsonb_build_object('workforce', (
      select jsonb_build_object(
        'headcount', count(*) filter (where e.status <> 'SEPARATED'),
        'omani', count(*) filter (where e.status <> 'SEPARATED' and e.nationality = 'OM'),
        'expat', count(*) filter (where e.status <> 'SEPARATED' and e.nationality <> 'OM'),
        'probation', count(*) filter (where e.status = 'PROBATION'),
        'notice', count(*) filter (where e.status = 'NOTICE'),
        'suspended', count(*) filter (where e.status = 'SUSPENDED'),
        'joiners_30', count(*) filter (where e.join_date between current_date - 30 and current_date),
        'leavers_30', count(*) filter (where e.separation_date between current_date - 30 and current_date),
        'probation_due_30', count(*) filter (where e.status = 'PROBATION' and e.probation_end_date <= current_date + 30))
      from hr.employees e),
      'by_department', coalesce((
        select jsonb_agg(jsonb_build_object('department_id', x.department_id, 'name_en', d.name_en, 'name_ar', d.name_ar,
                 'total', x.total, 'omani', x.omani) order by x.total desc, d.name_en)
        from (select a.department_id, count(*)::int total, count(*) filter (where e.nationality = 'OM')::int omani
              from hr.employees e join hr.employee_assignments a on a.employee_id = e.id
                   and a.effective_from <= current_date and (a.effective_to is null or a.effective_to >= current_date)
              where e.status <> 'SEPARATED' group by a.department_id) x
        join hr.departments d on d.id = x.department_id), '[]'::jsonb),
      'by_nationality', coalesce((
        select jsonb_agg(jsonb_build_object('code', x.nationality, 'name_en', c.nationality_en, 'name_ar', c.nationality_ar,
                 'total', x.total) order by x.total desc)
        from (select nationality, count(*)::int total from hr.employees where status <> 'SEPARATED' group by nationality) x
        join hr.countries c on c.code = x.nationality), '[]'::jsonb),
      'probation_due', coalesce((
        select jsonb_agg(jsonb_build_object('id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en,
                 'full_name_ar', e.full_name_ar, 'probation_end_date', e.probation_end_date) order by e.probation_end_date)
        from hr.employees e where e.status = 'PROBATION' and e.probation_end_date <= current_date + 30), '[]'::jsonb));
  end if;

  if hr.has_perm('COMPLIANCE_READ') then
    v_res := v_res || jsonb_build_object('compliance', (
      select jsonb_build_object(
        'expired', count(*) filter (where x.bucket = 'EXPIRED'),
        'd30', count(*) filter (where x.bucket = 'D30'),
        'd60', count(*) filter (where x.bucket = 'D60'),
        'd90', count(*) filter (where x.bucket = 'D90'),
        'missing', (select count(*) from hr.missing_documents() m join hr.document_types t on t.code = m.doc_type
                    where not t.is_sensitive or hr.has_perm('DOC_SENSITIVE')),
        'employees_missing', (select count(distinct m.employee_id) from hr.missing_documents() m))
      from hr.visible_expiries() x),
      'expiring_soon', coalesce((select jsonb_agg(to_jsonb(x) order by x.days_left) from (
          select * from hr.visible_expiries() v where v.days_left <= 30 order by v.days_left limit 10) x), '[]'::jsonb),
      'omanisation', coalesce((
        select jsonb_agg(jsonb_build_object('entity_id', le.id, 'code', le.code, 'name_en', le.name_en, 'name_ar', le.name_ar)
                 || hr.omanisation_row(
                      (select count(*)::int from hr.omanisation_population(le.id)),
                      (select count(*)::int from hr.omanisation_population(le.id) p where p.is_omani),
                      hr.target_for(le.id, 'ENTITY', null, null, current_date)) order by le.code)
        from hr.legal_entities le where le.is_active), '[]'::jsonb));
  end if;

  v_res := v_res || jsonb_build_object('approvals', (
    select jsonb_build_object(
      'salary', case when hr.has_perm('SALARY_APPROVE') then (select count(*) from hr.compensation_revisions r
                     where r.status = 'PENDING' and r.proposed_by <> v_uid and r.employee_id is distinct from v_me and hr.money_ok(r.employee_id)) else 0 end,
      'bank', case when hr.has_perm('BANK_APPROVE') then (select count(*) from hr.employee_bank_accounts b
                   where b.status = 'PENDING' and b.requested_by <> v_uid and b.employee_id is distinct from v_me and hr.money_ok(b.employee_id)) else 0 end,
      'targets', case when hr.has_perm('RULES_APPROVE') then (select count(*) from hr.omanisation_targets t
                      where t.status = 'PENDING' and t.proposed_by <> v_uid) else 0 end)));

  if v_me is not null then
    v_res := v_res || jsonb_build_object('me', (
      select jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en,
               'full_name_ar', e.full_name_ar, 'status', e.status, 'join_date', e.join_date,
               'assignment', hr.assignment_json(hr.current_assignment(e.id)),
               'my_expiries', coalesce((select jsonb_agg(to_jsonb(x) order by x.days_left)
                                        from hr.visible_expiries() x where x.employee_id = e.id and x.days_left <= 90), '[]'::jsonb),
               'team_size', (select count(*) from hr.team_of(e.id)),
               'team_expiries', coalesce((select jsonb_agg(to_jsonb(x) order by x.days_left) from (
                    select * from hr.visible_expiries() v
                    where v.employee_id in (select t.employee_id from hr.team_of(e.id) t) and v.days_left <= 60
                    order by v.days_left limit 20) x), '[]'::jsonb))
      from hr.employees e where e.id = v_me));
  end if;
  return v_res;
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_decide_bank(p_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare b hr.employee_bank_accounts; v_emp hr.employees;
begin
  perform hr.require_perm('BANK_APPROVE');
  select * into b from hr.employee_bank_accounts where id = p_id for update;
  if b.id is null then raise exception 'NOT_FOUND: Bank change not found.'; end if;
  perform hr.require_money(b.employee_id);
  if b.status <> 'PENDING' then raise exception 'INVALID: This change has already been decided.'; end if;
  if b.requested_by = auth.uid() then raise exception 'SELF_APPROVAL: You requested this change; someone else must approve it.' using errcode = '42501'; end if;
  if hr.is_me(b.employee_id) then raise exception 'NOT_ALLOWED: You cannot approve your own bank account.' using errcode = '42501'; end if;
  if not p_approve and nullif(btrim(p_note),'') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  select * into v_emp from hr.employees where id = b.employee_id;
  if p_approve then
    update hr.employee_bank_accounts set status = 'SUPERSEDED' where employee_id = b.employee_id and status = 'APPROVED';
    update hr.employee_bank_accounts set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(),
           decision_note = nullif(btrim(p_note),'') where id = b.id;
    perform hr.add_event(b.employee_id, 'BANK_CHANGE', coalesce(b.effective_from, current_date),
                         jsonb_build_object('bank_name', b.bank_name, 'account_ending', right(b.account_number, 4)));
  else
    update hr.employee_bank_accounts set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(),
           decision_note = btrim(p_note) where id = b.id;
  end if;
  perform hr.notify(b.requested_by, 'DECISION', 'NORMAL',
    'Bank change ' || case when p_approve then 'approved' else 'rejected' end || ' — ' || v_emp.full_name_en,
    case when p_approve then 'تم اعتماد تغيير الحساب البنكي' else 'تم رفض تغيير الحساب البنكي' end || ' — ' || coalesce(v_emp.full_name_ar, v_emp.full_name_en),
    nullif(btrim(p_note),''), nullif(btrim(p_note),''), '/employees/' || b.employee_id || '?tab=bank', 'BANKDEC:' || b.id);
  return public.hr_get_bank(b.employee_id);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_decide_change(p_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c hr.change_requests; e hr.employees; x jsonb; v_bank uuid; ch jsonb; u record;
begin
  perform hr.require_perm('SS_APPROVE');
  select * into c from hr.change_requests where id = p_id for update;
  if c.id is null then raise exception 'NOT_FOUND: Request not found.'; end if;
  if c.status <> 'PENDING' then raise exception 'NOT_PENDING: This request has already been decided.'; end if;
  if c.requested_by = auth.uid() or hr.is_me(c.employee_id) then
    raise exception 'SELF_APPROVAL: You cannot decide a request about yourself.' using errcode = '42501';
  end if;
  if not p_approve and nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  if p_approve and c.kind = 'CORRECTION' and nullif(btrim(coalesce(p_note,'')), '') is null then
    raise exception 'REQUIRED: Say what was corrected.';
  end if;
  select * into e from hr.employees where id = c.employee_id;
  ch := c.changes;
  if p_approve then
    if c.kind = 'PROFILE' then
      update hr.employees set
        preferred_name  = case when ch ? 'preferred_name'  then ch->'preferred_name'->>'new'  else preferred_name end,
        marital_status  = case when ch ? 'marital_status'  then ch->'marital_status'->>'new'  else marital_status end,
        personal_email  = case when ch ? 'personal_email'  then ch->'personal_email'->>'new'  else personal_email end,
        mobile          = case when ch ? 'mobile'          then ch->'mobile'->>'new'          else mobile end,
        alt_phone       = case when ch ? 'alt_phone'       then ch->'alt_phone'->>'new'       else alt_phone end,
        address_line    = case when ch ? 'address_line'    then ch->'address_line'->>'new'    else address_line end,
        city            = case when ch ? 'city'            then ch->'city'->>'new'            else city end,
        wilayat         = case when ch ? 'wilayat'         then ch->'wilayat'->>'new'         else wilayat end,
        governorate     = case when ch ? 'governorate'     then ch->'governorate'->>'new'     else governorate end,
        address_country = case when ch ? 'address_country' then ch->'address_country'->>'new' else address_country end
      where id = c.employee_id;
      perform hr.add_event(c.employee_id, 'PERSONAL_UPDATE', hr.today(),
                           jsonb_build_object('source', 'EMPLOYEE_REQUEST', 'request_id', c.id, 'fields', (select jsonb_agg(k) from jsonb_object_keys(ch) k)));
    elsif c.kind = 'EMERGENCY' then
      update hr.emergency_contacts set is_active = false where employee_id = c.employee_id and is_active;
      for x in select * from jsonb_array_elements(ch->'contacts') loop
        insert into hr.emergency_contacts(employee_id, name, relationship, phone, alt_phone, address, is_next_of_kin)
        values (c.employee_id, x->>'name', x->>'relationship', x->>'phone', nullif(x->>'alt_phone',''), nullif(x->>'address',''),
                coalesce((x->>'is_next_of_kin')::boolean, false));
      end loop;
    elsif c.kind = 'BANK' then
      if exists (select 1 from hr.employee_bank_accounts where employee_id = c.employee_id and status = 'PENDING') then
        raise exception 'PENDING_EXISTS: A bank change for this employee is already waiting for Finance.';
      end if;
      -- the employee is the requester; Finance (BANK_APPROVE) gives the final approval as for any bank change
      insert into hr.employee_bank_accounts(employee_id, bank_name, branch, account_name, account_number, iban, swift_code, effective_from, requested_by)
      values (c.employee_id, ch->>'bank_name', ch->>'branch', ch->>'account_name', ch->>'account_number', ch->>'iban', ch->>'swift_code',
              hr.today(), c.requested_by)
      returning id into v_bank;
      for u in select h.user_id from hr.money_users('BANK_APPROVE', c.employee_id) h where h.user_id <> auth.uid() and h.user_id <> c.requested_by loop
        perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
          'Bank account change awaiting approval — ' || e.full_name_en, 'تغيير الحساب البنكي بانتظار الاعتماد — ' || coalesce(e.full_name_ar, e.full_name_en),
          e.employee_no, e.employee_no, '/employees/' || c.employee_id || '?tab=bank', 'BANK:' || v_bank);
      end loop;
    end if;
  end if;
  update hr.change_requests set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(btrim(coalesce(p_note,'')), ''), result_ref = v_bank
   where id = c.id returning * into c;
  perform hr.notify(c.requested_by, 'INFO', 'NORMAL',
    case when p_approve then case when c.kind = 'BANK' then 'Your bank change was checked by HR and sent to Finance' else 'Your change request was approved' end
         else 'Your change request was rejected' end,
    case when p_approve then case when c.kind = 'BANK' then 'تمت مراجعة تغيير الحساب البنكي وأُحيل إلى المالية' else 'تم اعتماد طلب تعديل بياناتك' end
         else 'تم رفض طلب تعديل بياناتك' end,
    c.decision_note, c.decision_note, '/me?tab=requests', 'CHGD:' || c.id);
  return hr.change_json(c);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_decide_compensation(p_revision uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.compensation_revisions; v_emp hr.employees;
begin
  perform hr.require_perm('SALARY_APPROVE');
  select * into r from hr.compensation_revisions where id = p_revision for update;
  if r.id is null then raise exception 'NOT_FOUND: Salary revision not found.'; end if;
  perform hr.require_money(r.employee_id);
  if r.status <> 'PENDING' then raise exception 'INVALID: This revision has already been decided.'; end if;
  if r.proposed_by = auth.uid() then
    raise exception 'SELF_APPROVAL: You proposed this revision; someone else must approve it.' using errcode = '42501';
  end if;
  if hr.is_me(r.employee_id) then
    raise exception 'NOT_ALLOWED: You cannot approve your own salary.' using errcode = '42501';
  end if;
  if not p_approve and nullif(btrim(p_note),'') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  select * into v_emp from hr.employees where id = r.employee_id;

  if p_approve then
    update hr.compensation_revisions set status = 'SUPERSEDED'
     where employee_id = r.employee_id and status = 'APPROVED' and effective_from = r.effective_from;
    update hr.compensation_revisions set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(),
           decision_note = nullif(btrim(p_note),'') where id = r.id;
    perform hr.add_event(r.employee_id, 'SALARY_REVISION', r.effective_from,
                         jsonb_build_object('revision_id', r.id, 'reason', r.reason));
  else
    update hr.compensation_revisions set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(),
           decision_note = btrim(p_note) where id = r.id;
  end if;
  perform hr.notify(r.proposed_by, 'DECISION', 'NORMAL',
    'Salary revision ' || case when p_approve then 'approved' else 'rejected' end || ' — ' || v_emp.full_name_en,
    case when p_approve then 'تم اعتماد مراجعة الراتب' else 'تم رفض مراجعة الراتب' end || ' — ' || coalesce(v_emp.full_name_ar, v_emp.full_name_en),
    nullif(btrim(p_note),''), nullif(btrim(p_note),''), '/employees/' || r.employee_id || '?tab=pay', 'SALDEC:' || r.id);
  return public.hr_get_compensation(r.employee_id);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_decide_letter(p_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l hr.letters; e hr.employees; v_today date := hr.today();
begin
  perform hr.require_user();
  select * into l from hr.letters where id = p_id for update;
  if l.id is null then raise exception 'NOT_FOUND: Letter not found.'; end if;
  if p_approve then
    perform hr.require_perm('LETTER_APPROVE');
    if l.status <> 'PREPARED' then raise exception 'NOT_PENDING: Only a prepared letter can be approved.'; end if;
    if l.prepared_by = auth.uid() then raise exception 'SELF_APPROVAL: The person who prepared a letter cannot approve it.' using errcode = '42501'; end if;
    if hr.is_me(l.employee_id) then raise exception 'SELF_APPROVAL: You cannot approve your own letter.' using errcode = '42501'; end if;
    if l.include_salary and not (hr.has_perm('EMP_SALARY_READ') and hr.money_ok(l.employee_id)) then
      raise exception 'NOT_ALLOWED: Only someone who may see salaries can approve a letter that states the salary.' using errcode = '42501';
    end if;
    select * into e from hr.employees where id = l.employee_id;
    if l.include_salary and hr.comp_on(l.employee_id, v_today) is null then
      raise exception 'NO_SALARY: This employee has no approved salary structure to state.';
    end if;
    update hr.letters set status = 'ISSUED', approved_by = auth.uid(), approved_at = now(), decision_note = nullif(btrim(coalesce(p_note,'')), ''),
           issue_date = v_today, ref_no = hr.next_letter_ref(e.entity_id, v_today), verify_code = hr.new_verify_code(),
           snapshot = hr.letter_snapshot(l.employee_id, l.include_salary, v_today)
     where id = p_id returning * into l;
    perform hr.notify(hr.employee_user(l.employee_id), 'INFO', 'NORMAL', 'Your letter is ready: ' || l.ref_no, 'خطابك جاهز: ' || l.ref_no,
      null, null, '/letters/' || l.id, 'LTRI:' || l.id);
  else
    if not (hr.has_perm('LETTER_PREPARE') or hr.has_perm('LETTER_APPROVE')) then
      raise exception 'NOT_ALLOWED: You cannot reject letters.' using errcode = '42501';
    end if;
    if l.status not in ('REQUESTED','PREPARED') then raise exception 'NOT_PENDING: This letter has already been decided.'; end if;
    if hr.is_me(l.employee_id) then raise exception 'SELF_APPROVAL: You cannot decide your own letter.' using errcode = '42501'; end if;
    if l.include_salary then perform hr.require_money(l.employee_id); end if;
    if nullif(btrim(coalesce(p_note,'')), '') is null then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
    update hr.letters set status = 'REJECTED', decision_note = btrim(p_note), approved_by = case when prepared_by = auth.uid() then null else auth.uid() end,
           approved_at = now()
     where id = p_id returning * into l;
    perform hr.notify(l.requested_by, 'INFO', 'NORMAL', 'Your letter request was rejected', 'تم رفض طلب الخطاب', l.decision_note, l.decision_note,
      '/me?tab=letters', 'LTRR:' || l.id);
  end if;
  return hr.letter_json(l);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_decide_loan(p_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l hr.employee_loans;
begin
  perform hr.require_perm('PAY_APPROVE');
  select * into l from hr.employee_loans where id = p_id for update;
  if l.id is null or l.status <> 'PENDING' then raise exception 'NOT_FOUND: This loan is no longer waiting.'; end if;
  perform hr.require_money(l.employee_id);
  if l.proposed_by = auth.uid() or hr.is_me(l.employee_id) then raise exception 'SELF_APPROVAL: Someone other than you must approve this.'; end if;
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  update hr.employee_loans set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(), decided_at = now(),
         decision_note = nullif(btrim(p_note),'') where id = p_id returning * into l;
  perform hr.notify(hr.employee_user(l.employee_id), 'LOAN', 'NORMAL', initcap(lower(l.kind)) || ' ' || lower(l.status) || ': OMR ' || l.amount,
    case when l.status = 'APPROVED' then 'تم اعتماد ' else 'تم رفض ' end || case when l.kind = 'ADVANCE' then 'السلفة' else 'القرض' end,
    l.decision_note, l.decision_note, '/payslips', 'loan-done:' || l.id);
  return hr.loan_json(l);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_decide_pay_adjustments(p_ids uuid[], p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a hr.payroll_adjustments; v_n int := 0;
begin
  perform hr.require_perm('PAY_APPROVE');
  if not p_approve and coalesce(btrim(p_note),'') = '' then raise exception 'REQUIRED: Give a reason for rejecting.'; end if;
  for a in select * from hr.payroll_adjustments where id = any(p_ids) and status = 'PENDING' for update loop
    if a.proposed_by = auth.uid() then raise exception 'SELF_APPROVAL: Someone other than the proposer must approve this.'; end if;
    if hr.is_me(a.employee_id) then raise exception 'SELF_APPROVAL: You cannot approve your own pay.'; end if;
    perform hr.require_money(a.employee_id);
    if exists (select 1 from hr.payroll_runs x join hr.employees e on e.entity_id = x.entity_id
               where e.id = a.employee_id and x.pay_group = e.pay_group and x.period_start = a.period_start and x.status in ('VERIFIED','APPROVED','PAID')) then
      raise exception 'PERIOD_LOCKED: Payroll for % is already verified or approved.', to_char(a.period_start,'MM/YYYY');
    end if;
    update hr.payroll_adjustments set status = case when p_approve then 'APPROVED' else 'REJECTED' end, decided_by = auth.uid(),
           decided_at = now(), decision_note = nullif(btrim(p_note),'') where id = a.id;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'NOT_FOUND: Nothing is waiting.'; end if;
  return jsonb_build_object('decided', v_n);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_decide_settlement(p_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s hr.final_settlements; c jsonb; x jsonb; v_left numeric; v_amt numeric;
begin
  perform hr.require_perm('PAY_APPROVE');
  select * into s from hr.final_settlements where id = p_id for update;
  if s.id is null or s.status <> 'PREPARED' then raise exception 'NOT_FOUND: This settlement is not waiting for approval.'; end if;
  perform hr.require_money(s.employee_id);
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
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_employee_payroll(p_employee uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_basic numeric;
begin
  perform hr.require_user();
  if not (hr.has_perm('PAY_READ') or hr.is_me(p_employee)) then
    raise exception 'NOT_ALLOWED: You cannot see payroll details.' using errcode = '42501';
  end if;
  if not hr.is_me(p_employee) then perform hr.require_money(p_employee); end if;
  v_basic := coalesce((hr.comp_on(p_employee, hr.today())->>'basic')::numeric, 0);
  return jsonb_build_object(
    'payslips', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'month', to_char(r.period_start,'YYYY-MM'), 'status', r.status,
              'net', s.net, 'total_earnings', s.total_earnings, 'total_deductions', s.total_deductions) order by r.period_start desc)
            from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
            where s.employee_id = p_employee and (hr.has_perm('PAY_READ') or r.status in ('APPROVED','PAID'))), '[]'::jsonb),
    'loans', coalesce((select jsonb_agg(hr.loan_json(l) order by l.proposed_at desc) from hr.employee_loans l where l.employee_id = p_employee), '[]'::jsonb),
    'gratuity', case when hr.has_perm('PAY_READ') then hr.gratuity_calc(p_employee, hr.today(), v_basic) end);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_exec_dashboard(p_entity uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_today date := hr.today(); v_pay boolean := hr.has_perm('PAY_READ'); v_start date;
begin
  perform hr.require_perm('EXEC_VIEW');
  if not exists (select 1 from hr.legal_entities where id = p_entity) then raise exception 'NOT_FOUND: Company not found.'; end if;
  v_start := (date_trunc('month', v_today) - interval '11 months')::date;
  return jsonb_build_object(
    'as_of', v_today,
    'months', (select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'),
        'headcount', (select count(*) from hr.employees e where e.entity_id = p_entity and e.join_date <= me and (e.separation_date is null or e.separation_date > me)),
        'joiners', (select count(*) from hr.employees e where e.entity_id = p_entity and e.join_date between m and me),
        'leavers', (select count(*) from hr.employees e where e.entity_id = p_entity and e.separation_date between m and me),
        'omani_pct', (select case when count(*) > 0 then round(100.0 * count(*) filter (where p.is_omani) / count(*), 1) end from hr.omanisation_population(p_entity, me) p),
        'overtime_hours', (select round(coalesce(sum(o.minutes), 0) / 60.0, 1) from hr.overtime_requests o join hr.employees e on e.id = o.employee_id
                           where e.entity_id = p_entity and o.status = 'APPROVED' and o.work_date between m and me),
        'absent_days', (select count(*) from hr.attendance_days a join hr.employees e on e.id = a.employee_id
                        where e.entity_id = p_entity and a.status = 'ABSENT' and a.work_date between m and least(me, v_today)),
        'worked_days', (select count(*) from hr.attendance_days a join hr.employees e on e.id = a.employee_id
                        where e.entity_id = p_entity and a.status in ('PRESENT','ABSENT','MISSING_PUNCH') and a.work_date between m and least(me, v_today)),
        'payroll_cost', case when v_pay then (select sum(s.total_earnings + s.employer_cost) from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
                        where r.entity_id = p_entity and r.period_start = m and r.status in ('APPROVED','PAID') and hr.run_ok(r.pay_group)) end) order by m)
      from (select m::date m, (m + interval '1 month' - interval '1 day')::date me from generate_series(v_start, date_trunc('month', v_today)::date, interval '1 month') m) mm),
    'snapshot', (select jsonb_build_object(
        'headcount', count(*), 'omani', count(*) filter (where e.nationality = 'OM'), 'female', count(*) filter (where e.gender = 'F'),
        'probation', count(*) filter (where e.status = 'PROBATION'), 'notice', count(*) filter (where e.status = 'NOTICE'),
        'avg_tenure_years', round(avg((v_today - e.join_date) / 365.25)::numeric, 1),
        'avg_age', round(avg(extract(year from age(v_today, e.date_of_birth)))::numeric, 1))
      from hr.employees e where e.entity_id = p_entity and e.status <> 'SEPARATED' and e.join_date <= v_today),
    'by_department', coalesce((select jsonb_agg(jsonb_build_object('name_en', d.name_en, 'name_ar', d.name_ar, 'total', x.total, 'omani', x.omani) order by x.total desc)
        from (select department_id, count(*)::int total, count(*) filter (where is_omani)::int omani from hr.omanisation_population(p_entity, v_today) group by department_id) x
        join hr.departments d on d.id = x.department_id), '[]'::jsonb),
    'by_nationality', coalesce((select jsonb_agg(jsonb_build_object('code', x.nationality, 'name_en', c.name_en, 'name_ar', c.name_ar, 'total', x.n) order by x.n desc)
        from (select nationality, count(*)::int n from hr.employees where entity_id = p_entity and status <> 'SEPARATED' and join_date <= v_today group by nationality) x
        left join hr.countries c on c.code = x.nationality), '[]'::jsonb),
    'risks', jsonb_build_object(
        'documents_expired', (select count(*) from hr.expiry_items(v_today) x join hr.employees e on e.id = x.employee_id where e.entity_id = p_entity and x.days_left < 0),
        'documents_30', (select count(*) from hr.expiry_items(v_today) x join hr.employees e on e.id = x.employee_id where e.entity_id = p_entity and x.days_left between 0 and 30),
        'open_positions', (select coalesce(sum(r.positions - (select count(*) from hr.applications a where a.requisition_id = r.id and a.stage = 'HIRED')), 0)
                           from hr.job_requisitions r where r.entity_id = p_entity and r.status in ('APPROVED','ON_HOLD')),
        'injuries_ytd', (select count(*) from hr.work_injuries w join hr.employees e on e.id = w.employee_id
                         where e.entity_id = p_entity and w.occurred_at >= date_trunc('year', now())),
        'lost_days_ytd', (select coalesce(sum(w.lost_days), 0) from hr.work_injuries w join hr.employees e on e.id = w.employee_id
                          where e.entity_id = p_entity and w.occurred_at >= date_trunc('year', now())),
        'open_cases', (select count(*) from hr.disciplinary_cases d join hr.employees e on e.id = d.employee_id
                       where e.entity_id = p_entity and d.status in ('DRAFT','INVESTIGATION','PROPOSED')),
        'exits_open', (select count(*) from hr.exit_cases x join hr.employees e on e.id = x.employee_id where e.entity_id = p_entity and x.status = 'OPEN'),
        'gratuity_liability', case when v_pay then (select round(coalesce(sum((hr.gratuity_calc(e.id, v_today, coalesce((hr.comp_on(e.id, v_today)->>'basic')::numeric, 0))->>'total')::numeric), 0), 3)
                              from hr.employees e where e.entity_id = p_entity and e.nationality <> 'OM' and e.status <> 'SEPARATED' and e.join_date <= v_today and hr.money_ok(e.id)) end),
    'show_pay', v_pay);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_get_bank(p_employee uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_access text; v_full boolean;
begin
  v_access := hr.require_employee_access(p_employee);
  if not hr.is_me(p_employee) then perform hr.require_money(p_employee); end if;
  if not hr.is_me(p_employee)
     and not (hr.has_perm('EMP_BANK_READ') or hr.has_perm('EMP_BANK_WRITE') or hr.has_perm('BANK_APPROVE')) then
    raise exception 'NOT_ALLOWED: You cannot see bank details.' using errcode = '42501';
  end if;
  v_full := hr.is_me(p_employee) or hr.has_perm('EMP_BANK_READ') or hr.has_perm('BANK_APPROVE');
  if v_full then
    insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), p_employee, 'BANK', 'view');
  end if;
  return jsonb_build_object(
    'current', (select hr.bank_json(b, v_full) from hr.employee_bank_accounts b where b.employee_id = p_employee and b.status = 'APPROVED'),
    'pending', (select hr.bank_json(b, v_full) from hr.employee_bank_accounts b where b.employee_id = p_employee and b.status = 'PENDING'),
    'history', coalesce((select jsonb_agg(hr.bank_json(b, v_full) order by b.requested_at desc)
                         from hr.employee_bank_accounts b where b.employee_id = p_employee
                           and b.status in ('SUPERSEDED','REJECTED')), '[]'::jsonb));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_get_employee(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_access text; e hr.employees; v_emp jsonb; v_cur hr.employee_assignments; v_self boolean; v_money boolean;
begin
  v_access := hr.require_employee_access(p_id);
  v_self := hr.is_me(p_id);
  v_money := v_self or hr.money_ok(p_id);
  select * into e from hr.employees where id = p_id;
  v_cur := hr.current_assignment(p_id);
  if v_cur.id is null then
    select * into v_cur from hr.employee_assignments
     where employee_id = p_id and effective_from <= current_date order by effective_from desc limit 1;
  end if;

  if v_access = 'TEAM' then
    v_emp := jsonb_build_object('id', e.id, 'entity_id', e.entity_id, 'employee_no', e.employee_no,
               'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar, 'preferred_name', e.preferred_name,
               'nationality', e.nationality, 'gender', e.gender, 'work_email', e.work_email, 'mobile', e.mobile,
               'photo_path', e.photo_path, 'join_date', e.join_date, 'status', e.status,
               'probation_end_date', e.probation_end_date, 'confirmation_date', e.confirmation_date,
               'last_working_date', e.last_working_date);
  else
    v_emp := to_jsonb(e);
  end if;
  v_emp := v_emp || jsonb_build_object(
    'nationality_en', (select nationality_en from hr.countries where code = e.nationality),
    'nationality_ar', (select nationality_ar from hr.countries where code = e.nationality),
    'entity_en', (select name_en from hr.legal_entities where id = e.entity_id),
    'entity_ar', (select name_ar from hr.legal_entities where id = e.entity_id),
    'is_omani', e.nationality = 'OM');

  return jsonb_build_object(
    'employee', v_emp,
    'access', v_access,
    'current_assignment', hr.assignment_json(v_cur),
    'assignments', case when v_access = 'TEAM' then '[]'::jsonb else coalesce((
        select jsonb_agg(hr.assignment_json(a) order by a.effective_from desc)
        from hr.employee_assignments a where a.employee_id = p_id), '[]'::jsonb) end,
    'contracts', case when v_access = 'TEAM' then '[]'::jsonb else coalesce((
        select jsonb_agg(to_jsonb(c) || jsonb_build_object('created_by_name', hr.user_label(c.created_by))
                         order by c.version desc)
        from hr.employee_contracts c where c.employee_id = p_id), '[]'::jsonb) end,
    'emergency_contacts', case when v_access = 'TEAM' then '[]'::jsonb else coalesce((
        select jsonb_agg(to_jsonb(x) order by x.is_next_of_kin desc, x.created_at)
        from hr.emergency_contacts x where x.employee_id = p_id and x.is_active), '[]'::jsonb) end,
    'events', case when v_access = 'TEAM' then '[]'::jsonb else coalesce((
        select jsonb_agg(to_jsonb(v) || jsonb_build_object('created_by_name', hr.user_label(v.created_by))
                         order by v.event_date desc, v.created_at desc)
        from hr.employee_events v where v.employee_id = p_id), '[]'::jsonb) end,
    'omanisation_exceptions', case when v_access = 'FULL' then coalesce((
        select jsonb_agg(to_jsonb(x) || jsonb_build_object('job_title_en', j.name_en, 'job_title_ar', j.name_ar,
                         'approved_by_name', hr.user_label(x.approved_by)) order by x.approved_at desc)
        from hr.omanisation_exceptions x join hr.job_titles j on j.id = x.job_title_id
        where x.employee_id = p_id), '[]'::jsonb) else '[]'::jsonb end,
    'linked_user', case when v_access = 'FULL' then (
        select jsonb_build_object('user_id', up.user_id, 'email', up.email, 'is_active', up.is_active)
        from hr.user_profiles up where up.employee_id = p_id) end,
    'caps', jsonb_build_object(
      'edit',            hr.has_perm('EMP_WRITE'),
      'salary_read',     v_money and (v_self or hr.has_perm('EMP_SALARY_READ') or hr.has_perm('EMP_SALARY_WRITE') or hr.has_perm('SALARY_APPROVE')),
      'salary_write',    hr.has_perm('EMP_SALARY_WRITE') and not v_self and v_money,
      'salary_approve',  hr.has_perm('SALARY_APPROVE') and not v_self and v_money,
      'bank_read',       v_money and (v_self or hr.has_perm('EMP_BANK_READ') or hr.has_perm('EMP_BANK_WRITE') or hr.has_perm('BANK_APPROVE')),
      'bank_write',      hr.has_perm('EMP_BANK_WRITE') and not v_self and v_money,
      'bank_approve',    hr.has_perm('BANK_APPROVE') and not v_self and v_money,
      'docs_read',       v_self or hr.has_perm('DOC_READ'),
      'docs_write',      hr.has_perm('DOC_WRITE'),
      'docs_sensitive',  v_self or hr.has_perm('DOC_SENSITIVE'),
      'history',         hr.has_perm('EMP_READ'),
      'exception_approve', hr.has_perm('EXCEPTION_APPROVE'),
      'pay_restricted',  not v_money,
      'pay_group_change', hr.has_perm('MG_PAY') and not v_self and v_access <> 'TEAM'));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_get_letter(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l hr.letters;
begin
  perform hr.require_user();
  select * into l from hr.letters where id = p_id;
  if l.id is null then raise exception 'NOT_FOUND: Letter not found.'; end if;
  if not (hr.is_me(l.employee_id) or hr.has_perm('LETTER_PREPARE') or hr.has_perm('LETTER_APPROVE') or hr.has_perm('EMP_READ')) then
    raise exception 'NOT_ALLOWED: You cannot see this letter.' using errcode = '42501';
  end if;
  return hr.letter_json(l) || jsonb_build_object('settings', (select value from hr.settings where key = 'letters'),
    'preview', case when l.status <> 'ISSUED' then hr.letter_snapshot(l.employee_id, l.include_salary and hr.has_perm('EMP_SALARY_READ') and hr.money_ok(l.employee_id), hr.today()) end);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_get_payroll_run(p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_READ');
  perform hr.require_run(p_run);
  select * into r from hr.payroll_runs where id = p_run;
  if r.id is null then raise exception 'NOT_FOUND: Payroll run not found.'; end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'PAYROLL', 'run ' || to_char(r.period_start,'YYYY-MM'));
  return hr.run_json(r) || jsonb_build_object(
    'payslips', coalesce((select jsonb_agg(hr.slip_brief(s) order by s.employee_no) from hr.payslips s where s.run_id = p_run and hr.money_ok(s.employee_id)), '[]'::jsonb),
    'by_code', coalesce((select jsonb_agg(x order by x->>'kind', (x->>'sort')::int) from (
        select jsonb_build_object('code', l.code, 'name_en', min(l.name_en), 'name_ar', min(l.name_ar), 'kind', l.kind,
               'amount', sum(l.amount), 'employees', count(distinct l.payslip_id), 'sort', min(l.sort)) x
        from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id where s.run_id = p_run group by l.code, l.kind) t), '[]'::jsonb),
    'pending_inputs', jsonb_build_object(
        'adjustments', (select count(*) from hr.payroll_adjustments a join hr.employees e on e.id = a.employee_id
                        where e.entity_id = r.entity_id and e.pay_group = r.pay_group and a.period_start = r.period_start and a.status = 'PENDING'),
        'loans', (select count(*) from hr.employee_loans l join hr.employees e on e.id = l.employee_id
                  where e.entity_id = r.entity_id and e.pay_group = r.pay_group and l.status = 'PENDING' and l.first_month <= r.period_start)));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_get_payslip(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s hr.payslips; r hr.payroll_runs;
begin
  perform hr.require_user();
  select * into s from hr.payslips where id = p_id;
  if s.id is null then raise exception 'NOT_FOUND: Payslip not found.'; end if;
  select * into r from hr.payroll_runs where id = s.run_id;
  if not ((hr.has_perm('PAY_READ') and hr.run_ok(r.pay_group) and hr.money_ok(s.employee_id)) or (hr.is_me(s.employee_id) and r.status in ('APPROVED','PAID'))) then
    raise exception 'NOT_ALLOWED: You cannot see this payslip.' using errcode = '42501';
  end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), s.employee_id, 'PAYSLIP', to_char(r.period_start,'YYYY-MM'));
  return hr.slip_full(s);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_get_settlement(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s hr.final_settlements;
begin
  perform hr.require_user();
  select * into s from hr.final_settlements where id = p_id;
  if s.id is null then raise exception 'NOT_FOUND: Settlement not found.'; end if;
  if not ((hr.has_perm('PAY_READ') and hr.money_ok(s.employee_id)) or (hr.is_me(s.employee_id) and s.status in ('APPROVED','PAID'))) then
    raise exception 'NOT_ALLOWED: You cannot see this settlement.' using errcode = '42501';
  end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), s.employee_id, 'SETTLEMENT', 'view');
  return hr.settlement_json(s);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_gratuity_report(p_entity uuid DEFAULT NULL::uuid, p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on date := coalesce(p_as_of, hr.today());
begin
  perform hr.require_perm('PAY_READ');
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'SALARY', 'gratuity report ' || v_on);
  return jsonb_build_object('as_of', v_on, 'rows', coalesce((select jsonb_agg(x.j order by x.no) from (
      select e.employee_no as no, hr.emp_brief(e.id) || jsonb_build_object('join_date', e.join_date, 'nationality', e.nationality, 'status', e.status)
             || hr.gratuity_calc(e.id, v_on, coalesce((hr.comp_on(e.id, v_on)->>'basic')::numeric, 0)) as j
      from hr.employees e
      where e.nationality <> 'OM' and e.status <> 'SEPARATED' and e.join_date <= v_on and (p_entity is null or e.entity_id = p_entity) and hr.money_ok(e.id)) x), '[]'::jsonb));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_list_audit(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_limit int := least(greatest(coalesce(hr.jint(p,'limit'), 100), 1), 500);
  v_offset int := greatest(coalesce(hr.jint(p,'offset'), 0), 0);
  v_table text := hr.jtext(p,'table_name'); v_emp uuid := hr.juuid(p,'employee_id');
  v_from date := hr.jdate(p,'from'); v_to date := hr.jdate(p,'to'); v_user uuid := hr.juuid(p,'user_id');
  v_salary boolean := hr.has_perm('EMP_SALARY_READ'); v_bank boolean := hr.has_perm('EMP_BANK_READ');
begin
  perform hr.require_perm('AUDIT_READ');
  return jsonb_build_object(
    'total', (select count(*) from hr.audit_log a
              where (v_table is null or a.table_name = v_table) and (v_emp is null or a.employee_id = v_emp)
                and (v_user is null or a.user_id = v_user)
                and (v_from is null or a.at >= v_from) and (v_to is null or a.at < v_to + 1)
                and (v_salary or a.table_name not in ('compensation_revisions','compensation_lines'))
                and (v_bank or a.table_name <> 'employee_bank_accounts') and hr.audit_ok(a)),
    'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.id desc) from (
              select a.*, hr.user_label(a.user_id) as user_name, e.employee_no, e.full_name_en
              from hr.audit_log a left join hr.employees e on e.id = a.employee_id
              where (v_table is null or a.table_name = v_table) and (v_emp is null or a.employee_id = v_emp)
                and (v_user is null or a.user_id = v_user)
                and (v_from is null or a.at >= v_from) and (v_to is null or a.at < v_to + 1)
                and (v_salary or a.table_name not in ('compensation_revisions','compensation_lines'))
                and (v_bank or a.table_name <> 'employee_bank_accounts') and hr.audit_ok(a)
              order by a.id desc limit v_limit offset v_offset) x), '[]'::jsonb));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_list_loans(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_status text := hr.jtext(p,'status'); v_emp uuid := hr.juuid(p,'employee_id');
begin
  perform hr.require_perm('PAY_READ');
  return coalesce((select jsonb_agg(hr.loan_json(l) order by l.proposed_at desc) from hr.employee_loans l
                   where (v_status is null or l.status = v_status or (v_status = 'OPEN' and l.status in ('PENDING','APPROVED')))
                     and (v_emp is null or l.employee_id = v_emp) and hr.money_ok(l.employee_id)), '[]'::jsonb);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_list_my_tasks()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_res jsonb; v_me uuid := hr.my_employee_id();
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
                       where l.status = 'PENDING' and l.proposed_by <> auth.uid() and not hr.is_me(l.employee_id) and hr.money_ok(l.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'pay_adjustments', case when hr.has_perm('PAY_APPROVE') then coalesce((select jsonb_agg(hr.pay_adj_json(a) order by a.proposed_at) from hr.payroll_adjustments a
                       where a.status = 'PENDING' and a.proposed_by <> auth.uid() and not hr.is_me(a.employee_id) and hr.money_ok(a.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'settlements', case when hr.has_perm('PAY_APPROVE') then coalesce((select jsonb_agg(hr.settlement_json(s) order by s.prepared_at) from hr.final_settlements s
                       where s.status = 'PREPARED' and s.prepared_by <> auth.uid() and not hr.is_me(s.employee_id) and hr.money_ok(s.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'changes', case when hr.has_perm('SS_APPROVE') then coalesce((select jsonb_agg(hr.change_json(c) order by c.due_date, c.requested_at) from hr.change_requests c
                       where c.status = 'PENDING' and c.requested_by <> auth.uid() and not hr.is_me(c.employee_id)), '[]'::jsonb) else '[]'::jsonb end,
    'letters', case when hr.has_perm('LETTER_PREPARE') or hr.has_perm('LETTER_APPROVE') then coalesce((select jsonb_agg(j - 'snapshot' order by j->>'requested_at')
                       from (select hr.letter_json(l) j from hr.letters l where l.status in ('REQUESTED','PREPARED')) t
                       where (j->>'can_prepare')::boolean or (j->>'can_approve')::boolean), '[]'::jsonb) else '[]'::jsonb end,
    'requisitions', case when hr.has_perm('REC_APPROVE') then coalesce((select jsonb_agg(hr.requisition_json(r) order by r.requested_at)
                       from hr.job_requisitions r where r.status = 'PENDING' and r.requested_by <> auth.uid()), '[]'::jsonb) else '[]'::jsonb end,
    'offers', case when hr.has_perm('REC_APPROVE') then coalesce((select jsonb_agg(hr.offer_json(o) || jsonb_build_object('full_name_en', c.full_name_en,
                         'full_name_ar', c.full_name_ar) order by o.prepared_at)
                       from hr.job_offers o join hr.applications a on a.id = o.application_id join hr.candidates c on c.id = a.candidate_id
                       where o.status = 'PENDING' and o.prepared_by <> auth.uid()), '[]'::jsonb) else '[]'::jsonb end,
    'interviews', coalesce((select jsonb_agg(hr.interview_json(i) || jsonb_build_object('full_name_en', c.full_name_en, 'full_name_ar', c.full_name_ar)
                         order by i.scheduled_at)
                       from hr.interviews i join hr.applications a on a.id = i.application_id join hr.candidates c on c.id = a.candidate_id
                       where i.interviewer_id = auth.uid() and i.status = 'SCHEDULED' and i.scheduled_at < now()), '[]'::jsonb),
    'reviews', coalesce((select jsonb_agg(hr.review_json(r) order by c.due_date nulls last) from hr.perf_reviews r join hr.perf_cycles c on c.id = r.cycle_id
                       where c.status = 'OPEN' and ((r.status = 'SELF' and r.employee_id = v_me)
                         or (r.status = 'MANAGER' and r.reviewer_id = v_me)
                         or (r.status = 'HR' and hr.has_perm('PERF_MANAGE') and not hr.is_me(r.employee_id) and r.reviewer_id is distinct from v_me)
                         or (r.status = 'ACK' and r.employee_id = v_me))), '[]'::jsonb),
    'cases', case when hr.has_perm('DISC_APPROVE') then coalesce((select jsonb_agg(hr.case_json(d, true) order by d.proposed_at) from hr.disciplinary_cases d
                       where d.status = 'PROPOSED' and d.opened_by <> auth.uid() and d.proposed_by is distinct from auth.uid() and not hr.is_me(d.employee_id)), '[]'::jsonb)
                       else '[]'::jsonb end,
    'my_cases', coalesce((select jsonb_agg(hr.case_json(d, false)) from hr.disciplinary_cases d
                       where d.employee_id = v_me and d.status = 'INVESTIGATION' and d.employee_response is null), '[]'::jsonb))
  into v_res;
  return v_res || jsonb_build_object('count',
    jsonb_array_length(v_res->'leave') + jsonb_array_length(v_res->'corrections') + jsonb_array_length(v_res->'overtime')
    + jsonb_array_length(v_res->'adjustments') + jsonb_array_length(v_res->'rules') + jsonb_array_length(v_res->'pay_rules')
    + jsonb_array_length(v_res->'payroll') + jsonb_array_length(v_res->'loans') + jsonb_array_length(v_res->'pay_adjustments')
    + jsonb_array_length(v_res->'settlements') + jsonb_array_length(v_res->'changes') + jsonb_array_length(v_res->'letters')
    + jsonb_array_length(v_res->'requisitions') + jsonb_array_length(v_res->'offers') + jsonb_array_length(v_res->'interviews')
    + jsonb_array_length(v_res->'reviews') + jsonb_array_length(v_res->'cases') + jsonb_array_length(v_res->'my_cases'));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_list_pay_adjustments(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_status text := hr.jtext(p,'status'); v_month text := hr.jtext(p,'month'); v_emp uuid := hr.juuid(p,'employee_id');
begin
  perform hr.require_perm('PAY_READ');
  return coalesce((select jsonb_agg(hr.pay_adj_json(a) order by a.period_start desc, a.proposed_at desc) from (
      select * from hr.payroll_adjustments a where (v_status is null or a.status = v_status)
        and (v_month is null or a.period_start = hr.month_start(v_month)) and (v_emp is null or a.employee_id = v_emp) and hr.money_ok(a.employee_id)
      order by a.period_start desc, a.proposed_at desc limit 500) a), '[]'::jsonb);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_list_payroll_runs(p_entity uuid DEFAULT NULL::uuid, p_year integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform hr.require_perm('PAY_READ');
  return coalesce((select jsonb_agg(hr.run_json(r) order by r.period_start desc, r.entity_id)
                   from hr.payroll_runs r where (p_entity is null or r.entity_id = p_entity)
                     and (p_year is null or extract(year from r.period_start) = p_year) and hr.run_ok(r.pay_group)), '[]'::jsonb);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_list_pending_approvals()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid := hr.require_user(); v_emp uuid := hr.my_employee_id();
begin
  return jsonb_build_object(
    'salary', case when hr.has_perm('SALARY_APPROVE') then coalesce((
       select jsonb_agg(jsonb_build_object('id', r.id, 'employee_id', r.employee_id, 'employee_no', e.employee_no,
              'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar, 'effective_from', r.effective_from,
              'reason', r.reason, 'total_monthly', r.total_monthly, 'proposed_by_name', hr.user_label(r.proposed_by),
              'proposed_at', r.proposed_at, 'can_decide', r.proposed_by <> v_me and r.employee_id is distinct from v_emp)
              order by r.proposed_at)
       from hr.compensation_revisions r join hr.employees e on e.id = r.employee_id where r.status = 'PENDING' and hr.money_ok(r.employee_id)), '[]'::jsonb)
       else '[]'::jsonb end,
    'bank', case when hr.has_perm('BANK_APPROVE') then coalesce((
       select jsonb_agg(jsonb_build_object('id', b.id, 'employee_id', b.employee_id, 'employee_no', e.employee_no,
              'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar, 'bank_name', b.bank_name,
              'account_number', hr.mask_tail(b.account_number), 'requested_by_name', hr.user_label(b.requested_by),
              'requested_at', b.requested_at, 'can_decide', b.requested_by <> v_me and b.employee_id is distinct from v_emp)
              order by b.requested_at)
       from hr.employee_bank_accounts b join hr.employees e on e.id = b.employee_id where b.status = 'PENDING' and hr.money_ok(b.employee_id)), '[]'::jsonb)
       else '[]'::jsonb end,
    'targets', case when hr.has_perm('RULES_APPROVE') then coalesce((
       select jsonb_agg(jsonb_build_object('id', t.id, 'entity_id', t.entity_id, 'scope_type', t.scope_type,
              'target_pct', t.target_pct, 'effective_from', t.effective_from, 'source_reference', t.source_reference,
              'proposed_by_name', hr.user_label(t.proposed_by), 'proposed_at', t.proposed_at,
              'can_decide', t.proposed_by <> v_me) order by t.proposed_at)
       from hr.omanisation_targets t where t.status = 'PENDING'), '[]'::jsonb)
       else '[]'::jsonb end);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_list_settlements(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_status text := hr.jtext(p,'status');
begin
  perform hr.require_perm('PAY_READ');
  return coalesce((select jsonb_agg(hr.settlement_json(s) order by s.prepared_at desc) from hr.final_settlements s
                   where (v_status is null or s.status = v_status) and hr.money_ok(s.employee_id)), '[]'::jsonb);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_mark_payroll_paid(p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_APPROVE');
  perform hr.require_run(p_run);
  update hr.payroll_runs set status = 'PAID', paid_by = auth.uid(), paid_at = now() where id = p_run and status = 'APPROVED' returning * into r;
  if r.id is null then raise exception 'NOT_FOUND: Only an approved run can be marked paid.'; end if;
  return hr.run_json(r);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_mark_settlement_paid(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s hr.final_settlements;
begin
  perform hr.require_perm('PAY_APPROVE');
  perform hr.require_money((select x.employee_id from hr.final_settlements x where x.id = p_id));
  update hr.final_settlements set status = 'PAID', paid_at = now() where id = p_id and status = 'APPROVED' returning * into s;
  if s.id is null then raise exception 'NOT_FOUND: Only an approved settlement can be marked paid.'; end if;
  return hr.settlement_json(s);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_mol_report(p_entity uuid, p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_on date := coalesce(p_as_of, hr.today()); en hr.legal_entities; v_sal boolean := hr.has_perm('EMP_SALARY_READ');
begin
  perform hr.require_perm('COMPLIANCE_READ');
  select * into en from hr.legal_entities where id = p_entity;
  if en.id is null then raise exception 'NOT_FOUND: Company not found.'; end if;
  insert into hr.access_log(user_id, employee_id, data_kind, detail) values (auth.uid(), null, 'MOL_REPORT', 'Localisation report ' || en.code || ' as of ' || v_on);
  return jsonb_build_object(
    'entity', jsonb_build_object('id', en.id, 'code', en.code, 'name_en', en.name_en, 'name_ar', en.name_ar, 'cr_number', en.cr_number, 'mol_establishment_no', en.mol_establishment_no),
    'as_of', v_on,
    'overall', public.hr_get_omanisation(p_entity, v_on)->'overall',
    'by_profession', coalesce((select jsonb_agg(jsonb_build_object('profession_code', x.profession_code, 'job_en', x.job_en, 'job_ar', x.job_ar,
          'omani_only', x.omani_only, 'total', x.total, 'omani', x.omani, 'expat', x.total - x.omani,
          'pct', case when x.total > 0 then round(100.0 * x.omani / x.total, 1) end,
          'expat_in_omani_only', case when x.omani_only then x.total - x.omani else 0 end) order by x.profession_code nulls last, x.job_en)
        from (select j.profession_code, j.name_en job_en, j.name_ar job_ar, j.omani_only, count(*)::int total, count(*) filter (where p.is_omani)::int omani
              from hr.omanisation_population(p_entity, v_on) p join hr.job_titles j on j.id = p.job_title_id
              group by j.profession_code, j.name_en, j.name_ar, j.omani_only) x), '[]'::jsonb),
    'employees', coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'full_name_en', e.full_name_en, 'full_name_ar', e.full_name_ar,
          'nationality', e.nationality, 'gender', e.gender, 'date_of_birth', e.date_of_birth, 'civil_number', e.civil_number,
          'passport_no', (select d.doc_number from hr.employee_documents d where d.employee_id = e.id and d.doc_type = 'PASSPORT' and d.is_current and d.status = 'ACTIVE' limit 1),
          'resident_card_no', (select d.doc_number from hr.employee_documents d where d.employee_id = e.id and d.doc_type = 'RESIDENT_CARD' and d.is_current and d.status = 'ACTIVE' limit 1),
          'job_en', j.name_en, 'job_ar', j.name_ar, 'profession_code', j.profession_code, 'omani_only', j.omani_only,
          'department_en', dp.name_en, 'department_ar', dp.name_ar, 'join_date', e.join_date, 'status', e.status,
          'contract_type', ct.contract_type, 'contract_end', ct.end_date, 'mol_registration_no', ct.mol_registration_no,
          'basic', case when v_sal and hr.money_ok(e.id) then (hr.comp_on(e.id, v_on)->>'basic')::numeric end) order by e.employee_no)
        from hr.omanisation_population(p_entity, v_on) p join hr.employees e on e.id = p.employee_id
        join hr.job_titles j on j.id = p.job_title_id left join hr.departments dp on dp.id = p.department_id
        left join lateral (select c.contract_type, c.end_date, c.mol_registration_no from hr.employee_contracts c
                           where c.employee_id = e.id and c.status = 'ACTIVE' order by c.start_date desc limit 1) ct on true), '[]'::jsonb),
    'show_salary', v_sal);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_parallel_report(p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform hr.require_perm('PAY_READ');
  perform hr.require_run(p_run);
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
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_payroll_export(p_run uuid, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs; le hr.legal_entities;
begin
  perform hr.require_perm('PAY_READ');
  perform hr.require_run(p_run);
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
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_prepare_letter(p_id uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l hr.letters; e hr.employees; v_lang text; v_details jsonb; u record;
begin
  perform hr.require_perm('LETTER_PREPARE');
  select * into l from hr.letters where id = p_id for update;
  if l.id is null then raise exception 'NOT_FOUND: Letter not found.'; end if;
  if l.status <> 'REQUESTED' then raise exception 'NOT_PENDING: This letter is not waiting to be prepared.'; end if;
  if hr.is_me(l.employee_id) then raise exception 'SELF_APPROVAL: You cannot prepare your own letter.' using errcode = '42501'; end if;
  if l.letter_type = 'SALARY_CERT' or (l.letter_type = 'EMPLOYMENT' and case when p ? 'include_salary' then hr.jbool(p,'include_salary') else l.include_salary end) then
    perform hr.require_money(l.employee_id);
  end if;
  v_lang := upper(coalesce(hr.jtext(p,'language'), l.language));
  v_details := coalesce(p->'details', l.details);
  perform hr.letter_validate(l.letter_type, v_lang, v_details);
  update hr.letters set language = v_lang, addressee = coalesce(hr.jtext(p,'addressee'), addressee), purpose = coalesce(hr.jtext(p,'purpose'), purpose),
         details = v_details,
         include_salary = case when letter_type = 'SALARY_CERT' then true when letter_type = 'EMPLOYMENT' and p ? 'include_salary' then hr.jbool(p,'include_salary') else include_salary end,
         status = 'PREPARED', prepared_by = auth.uid(), prepared_at = now()
   where id = p_id returning * into l;
  select * into e from hr.employees where id = l.employee_id;
  for u in select h.user_id from hr.money_users('LETTER_APPROVE', case when l.include_salary then l.employee_id end) h where h.user_id <> auth.uid() and h.user_id is distinct from hr.employee_user(l.employee_id) loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL', 'Letter waiting for approval — ' || e.full_name_en,
      'خطاب بانتظار الاعتماد — ' || coalesce(e.full_name_ar, e.full_name_en), e.employee_no, e.employee_no, '/requests?tab=letters', 'LTR:' || l.id || ':PREPARED');
  end loop;
  return hr.letter_json(l);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_propose_compensation(p_employee uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e hr.employees; v_from date := hr.jdate(p,'effective_from'); v_reason text := coalesce(hr.jtext(p,'reason'),'INCREMENT');
  v_line jsonb; v_code text; v_amt numeric; v_basic numeric; v_gross numeric := 0; v_rev uuid;
  v_codes text[] := '{}'; v_warn jsonb := '[]'::jsonb; v_grade hr.grades; u record;
begin
  perform hr.require_perm('EMP_SALARY_WRITE');
  select * into e from hr.employees where id = p_employee;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  perform hr.require_money(p_employee);
  if hr.is_me(p_employee) then
    raise exception 'NOT_ALLOWED: You cannot propose your own salary.' using errcode = '42501';
  end if;
  if e.status = 'SEPARATED' then raise exception 'INVALID: This employee has left.'; end if;
  if v_from is null then raise exception 'REQUIRED: Effective date is required.'; end if;
  if v_from < e.join_date then raise exception 'INVALID: The salary cannot start before the joining date.'; end if;
  if v_reason not in ('JOIN','INCREMENT','PROMOTION','ADJUSTMENT','CORRECTION','REHIRE') then
    raise exception 'INVALID: Unknown reason.';
  end if;
  if jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then
    raise exception 'REQUIRED: Enter at least the basic salary.';
  end if;
  if exists (select 1 from hr.compensation_revisions where employee_id = p_employee and status = 'PENDING') then
    raise exception 'PENDING_EXISTS: A salary revision for this employee is already waiting for approval.';
  end if;

  insert into hr.compensation_revisions(employee_id, effective_from, reason, notes, proposed_by)
  values (p_employee, v_from, v_reason, hr.jtext(p,'notes'), auth.uid())
  returning id into v_rev;

  for v_line in select * from jsonb_array_elements(p->'lines') loop
    v_code := upper(hr.jtext(v_line,'component_code'));
    v_amt := hr.jmoney(v_line,'amount');
    if v_code is null or not exists (select 1 from hr.pay_components where code = v_code and is_active) then
      raise exception 'INVALID: Unknown pay component %.', coalesce(v_code,'(blank)');
    end if;
    if v_code = any(v_codes) then raise exception 'INVALID: % is entered twice.', v_code; end if;
    v_codes := v_codes || v_code;
    continue when v_amt is null or (v_amt = 0 and v_code <> 'BASIC');
    insert into hr.compensation_lines(revision_id, employee_id, component_code, amount) values (v_rev, p_employee, v_code, v_amt);
    if v_code = 'BASIC' then v_basic := v_amt; end if;
    if (select kind from hr.pay_components where code = v_code) = 'EARNING' then v_gross := v_gross + v_amt; end if;
  end loop;
  if coalesce(v_basic, 0) <= 0 then raise exception 'REQUIRED: The basic salary must be more than zero.'; end if;
  update hr.compensation_revisions set total_monthly = v_gross where id = v_rev;

  select g.* into v_grade from hr.grades g
   join hr.employee_assignments a on a.grade_id = g.id
  where a.employee_id = p_employee and a.effective_from <= v_from and (a.effective_to is null or a.effective_to >= v_from);
  if v_grade.id is not null and ((v_grade.min_basic is not null and v_basic < v_grade.min_basic)
                              or (v_grade.max_basic is not null and v_basic > v_grade.max_basic)) then
    v_warn := v_warn || jsonb_build_object('code', 'OUTSIDE_GRADE_BAND',
                'message', format('Basic %s is outside grade %s band (%s – %s).', v_basic, v_grade.code,
                                  coalesce(v_grade.min_basic::text,'—'), coalesce(v_grade.max_basic::text,'—')));
  end if;

  for u in select h.user_id from hr.money_users('SALARY_APPROVE', p_employee) h where h.user_id <> auth.uid() loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
      'Salary revision awaiting approval — ' || e.full_name_en, 'مراجعة راتب بانتظار الاعتماد — ' || coalesce(e.full_name_ar, e.full_name_en),
      e.employee_no || ': effective ' || to_char(v_from,'DD/MM/YYYY') || '.', e.employee_no || ': اعتباراً من ' || to_char(v_from,'DD/MM/YYYY') || '.',
      '/employees/' || p_employee || '?tab=pay', 'SAL:' || v_rev);
  end loop;
  return jsonb_build_object('revision_id', v_rev, 'warnings', v_warn, 'compensation', public.hr_get_compensation(p_employee));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_propose_loan(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_amt numeric := hr.jmoney(p,'amount'); v_inst numeric := hr.jmoney(p,'installment');
        v_kind text := coalesce(upper(hr.jtext(p,'kind')), 'LOAN'); v_first date := hr.month_start(hr.jtext(p,'first_month')); l hr.employee_loans; e hr.employees;
begin
  perform hr.require_perm('PAY_PREPARE');
  select * into e from hr.employees where id = v_emp;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  perform hr.require_money(v_emp);
  if e.status = 'SEPARATED' then raise exception 'INVALID: The employee has left.'; end if;
  if hr.is_me(v_emp) then raise exception 'SELF_APPROVAL: You cannot propose a loan for yourself.'; end if;
  if v_kind not in ('LOAN','ADVANCE') then raise exception 'INVALID: Choose loan or advance.'; end if;
  if v_amt is null or v_amt <= 0 then raise exception 'INVALID_AMOUNT: Give the amount.'; end if;
  v_inst := coalesce(v_inst, case when v_kind = 'ADVANCE' then v_amt end);
  if v_inst is null or v_inst <= 0 or v_inst > v_amt then raise exception 'INVALID_AMOUNT: The instalment must be more than 0 and not more than the amount.'; end if;
  if exists (select 1 from hr.payroll_runs r where r.entity_id = e.entity_id and r.pay_group = e.pay_group and r.period_start = v_first and r.status in ('APPROVED','PAID')) then
    raise exception 'PERIOD_LOCKED: Payroll for % is already approved — start next month.', to_char(v_first,'MM/YYYY');
  end if;
  insert into hr.employee_loans(employee_id, kind, amount, installment, first_month, reason, proposed_by)
  values (v_emp, v_kind, v_amt, v_inst, v_first, btrim(coalesce(hr.jtext(p,'reason'), '')), auth.uid()) returning * into l;
  perform hr.notify_money(v_emp, null, 'PAY_APPROVE', 'LOAN', initcap(lower(v_kind)) || ' waiting: ' || e.full_name_en || ', OMR ' || v_amt,
    case when v_kind = 'ADVANCE' then 'سلفة' else 'قرض' end || ' بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en), '/approvals', 'loan:' || l.id);
  return hr.loan_json(l);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_propose_pay_adjustments(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; i int := 0; v_ok int := 0; v_err jsonb := '[]'::jsonb; v_emp uuid; e hr.employees; v_m date; v_code text; v_kind text; v_amt numeric; v_okm int := 0;
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
      if not hr.money_ok(v_emp) then raise exception 'Pay details of management (MG) employees are restricted to the management payroll team.'; end if;
      if hr.is_me(v_emp) then raise exception 'You cannot propose an adjustment for yourself.'; end if;
      v_m := hr.month_start(hr.jtext(r,'month'));
      v_code := upper(coalesce(hr.jtext(r,'code'), ''));
      v_kind := case when v_code in ('BONUS','COMMISSION','ARREARS','ALLOWANCE','OTHER_EARN') then 'EARNING'
                     when v_code in ('PENALTY','DAMAGE','OTHER_DED') then 'DEDUCTION' end;
      if v_kind is null then raise exception 'Unknown code %.', v_code; end if;
      v_amt := hr.jmoney(r,'amount');
      if v_amt is null or v_amt <= 0 then raise exception 'Amount must be more than 0.'; end if;
      if coalesce(length(btrim(hr.jtext(r,'reason'))), 0) < 3 then raise exception 'Give a reason.'; end if;
      if exists (select 1 from hr.payroll_runs x where x.entity_id = e.entity_id and x.pay_group = e.pay_group and x.period_start = v_m and x.status in ('VERIFIED','APPROVED','PAID')) then
        raise exception 'Payroll for % is already verified or approved.', to_char(v_m,'MM/YYYY');
      end if;
      insert into hr.payroll_adjustments(employee_id, period_start, kind, code, amount, reason, proposed_by)
      values (v_emp, v_m, v_kind, v_code, v_amt, btrim(hr.jtext(r,'reason')), auth.uid());
      v_ok := v_ok + 1;
      if e.pay_group = 'MG' then v_okm := v_okm + 1; end if;
    exception when others then
      if jsonb_array_length(v_err) < 200 then
        v_err := v_err || jsonb_build_array(jsonb_build_object('row', i, 'message', regexp_replace(sqlerrm, '^[A-Z_]+: ', '')));
      end if;
    end;
  end loop;
  if v_ok - v_okm > 0 then
    perform hr.notify_money(null, 'NMG', 'PAY_APPROVE', 'PAY_ADJ', (v_ok - v_okm) || ' payroll adjustments waiting',
      (v_ok - v_okm) || ' تعديلات رواتب بانتظار الاعتماد', '/approvals', 'pay-adj:' || now()::text);
  end if;
  if v_okm > 0 then
    perform hr.notify_money(null, 'MG', 'PAY_APPROVE', 'PAY_ADJ', v_okm || ' management payroll adjustments waiting',
      v_okm || ' تعديلات رواتب الإدارة بانتظار الاعتماد', '/approvals', 'pay-adj-mg:' || now()::text);
  end if;
  return jsonb_build_object('proposed', v_ok, 'errors', v_err);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_request_bank_change(p_employee uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e hr.employees; v_acc text := upper(regexp_replace(coalesce(p->>'account_number',''), '\s', '', 'g'));
        v_iban text := nullif(upper(regexp_replace(coalesce(p->>'iban',''), '\s', '', 'g')), '');
        v_swift text := nullif(upper(btrim(coalesce(p->>'swift_code',''))), ''); v_id uuid; u record;
begin
  perform hr.require_perm('EMP_BANK_WRITE');
  select * into e from hr.employees where id = p_employee;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  perform hr.require_money(p_employee);
  if hr.is_me(p_employee) then raise exception 'NOT_ALLOWED: You cannot change your own bank account here.' using errcode = '42501'; end if;
  if hr.jtext(p,'bank_name') is null then raise exception 'REQUIRED: Bank name is required.'; end if;
  if hr.jtext(p,'account_name') is null then raise exception 'REQUIRED: Account holder name is required.'; end if;
  if v_acc !~ '^[A-Z0-9-]{5,34}$' then raise exception 'INVALID: Account number must be 5–34 letters or digits.'; end if;
  if v_iban is not null and v_iban !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$' then raise exception 'INVALID: IBAN format is not valid.'; end if;
  if v_swift is not null and v_swift !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then raise exception 'INVALID: SWIFT / BIC must be 8 or 11 characters.'; end if;
  if exists (select 1 from hr.employee_bank_accounts where employee_id = p_employee and status = 'PENDING') then
    raise exception 'PENDING_EXISTS: A bank change for this employee is already waiting for approval.';
  end if;
  insert into hr.employee_bank_accounts(employee_id, bank_name, branch, account_name, account_number, iban, swift_code,
                                        effective_from, requested_by)
  values (p_employee, hr.jtext(p,'bank_name'), hr.jtext(p,'branch'), hr.jtext(p,'account_name'), v_acc, v_iban, v_swift,
          coalesce(hr.jdate(p,'effective_from'), current_date), auth.uid())
  returning id into v_id;
  for u in select h.user_id from hr.money_users('BANK_APPROVE', p_employee) h where h.user_id <> auth.uid() loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
      'Bank account change awaiting approval — ' || e.full_name_en, 'تغيير الحساب البنكي بانتظار الاعتماد — ' || coalesce(e.full_name_ar, e.full_name_en),
      e.employee_no, e.employee_no, '/employees/' || p_employee || '?tab=bank', 'BANK:' || v_id);
  end loop;
  return public.hr_get_bank(p_employee);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_request_letter(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_emp uuid := coalesce(hr.juuid(p,'employee_id'), hr.my_employee_id()); v_hr boolean := hr.has_perm('LETTER_PREPARE');
  v_type text := upper(coalesce(hr.jtext(p,'letter_type'), '')); v_lang text := upper(coalesce(hr.jtext(p,'language'), 'BOTH'));
  v_details jsonb := coalesce(p->'details', '{}'::jsonb); v_salary boolean; e hr.employees; l hr.letters; u record; v_prepare boolean;
begin
  perform hr.require_user();
  if v_emp is null then raise exception 'NOT_LINKED: Your login is not linked to an employee record. Ask HR to link it.'; end if;
  if not hr.is_me(v_emp) and not v_hr then raise exception 'NOT_ALLOWED: You can only request letters for yourself.' using errcode = '42501'; end if;
  select * into e from hr.employees where id = v_emp;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  perform hr.letter_validate(v_type, v_lang, v_details);
  if v_type = 'EXPERIENCE' and e.status not in ('NOTICE','SEPARATED') and not v_hr then
    raise exception 'NOT_ALLOWED: An experience letter is issued when you leave. Ask for an employment letter instead.';
  end if;
  if exists (select 1 from hr.letters where employee_id = v_emp and letter_type = v_type and status in ('REQUESTED','PREPARED')) then
    raise exception 'PENDING_EXISTS: A letter of this type is already being prepared.';
  end if;
  v_salary := v_type = 'SALARY_CERT' or (v_type = 'EMPLOYMENT' and hr.jbool(p,'include_salary'));
  -- HR starting a letter for someone else may prepare it in the same step; approval is still by another person
  v_prepare := v_hr and not hr.is_me(v_emp) and hr.jbool(p,'prepare');
  if v_salary and not hr.is_me(v_emp) then perform hr.require_money(v_emp); end if;
  insert into hr.letters(employee_id, letter_type, language, addressee, purpose, details, include_salary, requested_by,
                         status, prepared_by, prepared_at)
  values (v_emp, v_type, v_lang, hr.jtext(p,'addressee'), hr.jtext(p,'purpose'), v_details, v_salary, auth.uid(),
          case when v_prepare then 'PREPARED' else 'REQUESTED' end, case when v_prepare then auth.uid() end, case when v_prepare then now() end)
  returning * into l;
  for u in select h.user_id from hr.money_users(case when v_prepare then 'LETTER_APPROVE' else 'LETTER_PREPARE' end, case when v_salary then v_emp end) h
           where h.user_id <> auth.uid() and h.user_id is distinct from hr.employee_user(v_emp) loop
    perform hr.notify(u.user_id, 'APPROVAL', 'NORMAL',
      case when v_prepare then 'Letter waiting for approval — ' else 'Letter requested — ' end || e.full_name_en,
      case when v_prepare then 'خطاب بانتظار الاعتماد — ' else 'طلب خطاب — ' end || coalesce(e.full_name_ar, e.full_name_en),
      e.employee_no, e.employee_no, '/requests?tab=letters', 'LTR:' || l.id || ':' || l.status);
  end loop;
  return hr.letter_json(l);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_return_payroll(p_run uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs;
begin
  perform hr.require_run(p_run);
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
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_save_settlement(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_emp uuid := hr.juuid(p,'employee_id'); v_last date := hr.jdate(p,'last_working_date'); e hr.employees; c jsonb; s hr.final_settlements;
        v_reason text := coalesce(upper(hr.jtext(p,'reason')), 'RESIGNATION'); x jsonb;
begin
  perform hr.require_perm('PAY_PREPARE');
  select * into e from hr.employees where id = v_emp;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  perform hr.require_money(v_emp);
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
  perform hr.notify_money(v_emp, null, 'PAY_APPROVE', 'SETTLEMENT', 'Final settlement waiting: ' || e.full_name_en,
    'تسوية نهائية بانتظار الاعتماد: ' || coalesce(e.full_name_ar, e.full_name_en), '/approvals', 'settlement:' || s.id);
  return hr.settlement_json(s);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_set_user_roles(p_user uuid, p_roles text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me uuid; v_bad text; v_roles text[] := coalesce(p_roles, '{}');
begin
  perform hr.require_perm('USERS_ADMIN');
  v_me := auth.uid();
  if not exists (select 1 from hr.user_profiles where user_id = p_user) then
    raise exception 'NOT_FOUND: User not found.';
  end if;
  select r into v_bad from unnest(v_roles) r where not exists (select 1 from hr.roles where code = r) limit 1;
  if v_bad is not null then raise exception 'INVALID: Unknown role %.', v_bad; end if;
  if p_user = v_me and not ('SUPER_ADMIN' = any(v_roles))
     and exists (select 1 from hr.user_roles where user_id = v_me and role_code = 'SUPER_ADMIN' and revoked_at is null) then
    raise exception 'NOT_ALLOWED: You cannot remove your own administrator role.';
  end if;
  if not ('SUPER_ADMIN' = any(v_roles))
     and exists (select 1 from hr.user_roles where user_id = p_user and role_code = 'SUPER_ADMIN' and revoked_at is null)
     and not exists (select 1 from hr.user_roles where role_code = 'SUPER_ADMIN' and revoked_at is null and user_id <> p_user) then
    raise exception 'NOT_ALLOWED: At least one super administrator must remain.';
  end if;
  if 'SUPER_ADMIN' = any(v_roles) and not hr.has_perm('USERS_ADMIN') then
    raise exception 'NOT_ALLOWED';
  end if;

  if (exists (select 1 from hr.user_roles where user_id = p_user and role_code = 'MG_PAYROLL' and revoked_at is null)) <> ('MG_PAYROLL' = any(v_roles))
     and not hr.has_perm('MG_PAY')
     and exists (select 1 from hr.users_with_perm('MG_PAY')) then
    raise exception 'MG_ONLY: Only a member of the management payroll team can give or remove the Management payroll role.' using errcode = '42501';
  end if;
  if 'MG_PAYROLL' = any(v_roles) and p_user = v_me and exists (select 1 from hr.users_with_perm('MG_PAY')) and not hr.has_perm('MG_PAY') then
    raise exception 'NOT_ALLOWED: You cannot give yourself the Management payroll role.' using errcode = '42501';
  end if;
  update hr.user_roles set revoked_at = now(), revoked_by = v_me
   where user_id = p_user and revoked_at is null and not (role_code = any(v_roles));
  insert into hr.user_roles(user_id, role_code, granted_by)
  select p_user, r, v_me from unnest(v_roles) r
  on conflict (user_id, role_code) do update
    set revoked_at = null, revoked_by = null, granted_by = excluded.granted_by, granted_at = now()
    where hr.user_roles.revoked_at is not null;
  return public.hr_list_users();
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_spf_report(p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs; en hr.legal_entities;
begin
  perform hr.require_perm('PAY_READ');
  perform hr.require_run(p_run);
  select * into r from hr.payroll_runs where id = p_run;
  if r.id is null then raise exception 'NOT_FOUND: Payroll run not found.'; end if;
  select * into en from hr.legal_entities where id = r.entity_id;
  return jsonb_build_object(
    'run', jsonb_build_object('id', r.id, 'month', to_char(r.period_start, 'YYYY-MM'), 'status', r.status, 'final', r.status in ('APPROVED','PAID')),
    'entity', jsonb_build_object('code', en.code, 'name_en', en.name_en, 'name_ar', en.name_ar, 'cr_number', en.cr_number, 'spf_employer_no', en.spf_employer_no),
    'rows', coalesce((select jsonb_agg(x order by x->>'is_omani' desc, x->>'employee_no') from (
        select jsonb_build_object('employee_id', s.employee_id, 'employee_no', s.employee_no, 'full_name_en', s.full_name_en, 'full_name_ar', s.full_name_ar,
          'nationality', s.nationality, 'is_omani', s.is_omani, 'civil_number', s.civil_number, 'paid_days', s.paid_days,
          'wage', (select max(l.qty) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_%' and l.rate is not null),
          'lines', coalesce((select jsonb_object_agg(l.code, l.amount) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_%'), '{}'::jsonb),
          'employee_total', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_EE\_%'),
          'employer_total', (select coalesce(sum(l.amount), 0) from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_ER\_%')) x
        from hr.payslips s where s.run_id = r.id
          and exists (select 1 from hr.payslip_lines l where l.payslip_id = s.id and l.code like 'SPF\_%')) q), '[]'::jsonb),
    'totals', (select coalesce(jsonb_object_agg(code, amt), '{}'::jsonb) from (select l.code, sum(l.amount) amt from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id
               where s.run_id = r.id and l.code like 'SPF\_%' group by l.code) t),
    'codes', coalesce((select jsonb_agg(distinct jsonb_build_object('code', l.code, 'name_en', l.name_en, 'name_ar', l.name_ar, 'kind', l.kind))
               from hr.payslip_lines l join hr.payslips s on s.id = l.payslip_id where s.run_id = r.id and l.code like 'SPF\_%'), '[]'::jsonb));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_time_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
                       where s.employee_id = v_me and r.status in ('APPROVED','PAID') order by r.period_start desc limit 1),
      'requests_open', (select count(*) from hr.change_requests c where c.employee_id = v_me and c.status = 'PENDING')
                     + (select count(*) from hr.letters l where l.employee_id = v_me and l.status in ('REQUESTED','PREPARED')),
      'letters_ready', (select count(*) from hr.letters l where l.employee_id = v_me and l.status = 'ISSUED' and l.revoked_at is null
                          and l.approved_at > now() - interval '14 days')));
  end if;
  if hr.has_perm('PAY_READ') then
    v_res := v_res || jsonb_build_object('payroll', (select hr.run_json(r) from hr.payroll_runs r where hr.run_ok(r.pay_group) order by r.period_start desc, r.created_at desc limit 1));
  end if;
  if hr.has_perm('REC_READ') then
    v_res := v_res || jsonb_build_object('recruitment', jsonb_build_object(
      'open_requisitions', (select count(*) from hr.job_requisitions where status in ('APPROVED','ON_HOLD')),
      'open_positions', (select coalesce(sum(r.positions - (select count(*) from hr.applications a where a.requisition_id = r.id and a.stage = 'HIRED')), 0)
                         from hr.job_requisitions r where r.status in ('APPROVED','ON_HOLD')),
      'in_pipeline', (select count(*) from hr.applications a join hr.job_requisitions r on r.id = a.requisition_id
                      where a.stage not in ('HIRED','REJECTED','WITHDRAWN') and r.status in ('APPROVED','ON_HOLD')),
      'joining_30', (select count(*) from hr.job_offers o join hr.applications a on a.id = o.application_id
                     where o.status = 'ACCEPTED' and a.stage <> 'HIRED' and o.start_date <= v_today + 30),
      'onboarding_overdue', (select count(*) from hr.onboarding_tasks where status = 'PENDING' and due_date < v_today),
      'probation_due_30', (select count(*) from hr.employees where status = 'PROBATION' and probation_end_date <= v_today + 30)));
  end if;
  if hr.has_perm('TRAIN_WRITE') or hr.has_perm('ASSET_WRITE') or hr.has_perm('HSE_WRITE') or hr.has_perm('EXIT_MANAGE') then
    v_res := v_res || jsonb_build_object('workforce', jsonb_build_object(
      'training_expiring_30', (select count(*) from hr.expiry_items(v_today) x where x.source = 'TRAINING' and x.days_left <= 30),
      'assets_overdue', (select count(*) from hr.asset_issues where status = 'ISSUED' and due_return_on < v_today),
      'injuries_open', (select count(*) from hr.work_injuries where status = 'OPEN'),
      'injuries_unreported', (select count(*) from hr.work_injuries w where w.spf_reported_on is null and w.severity <> 'FIRST_AID'
                              and v_today > ((w.occurred_at at time zone 'Asia/Muscat')::date + hr.policy_num('injury_report_days', 7)::int)),
      'exits_open', (select count(*) from hr.exit_cases where status = 'OPEN'),
      'plans_active', (select count(*) from hr.perf_plans where status = 'ACTIVE')));
  end if;
  v_tasks := public.hr_list_my_tasks();
  return v_res || jsonb_build_object('tasks', jsonb_build_object(
    'leave', jsonb_array_length(v_tasks->'leave'), 'corrections', jsonb_array_length(v_tasks->'corrections'),
    'overtime', jsonb_array_length(v_tasks->'overtime'), 'adjustments', jsonb_array_length(v_tasks->'adjustments'),
    'rules', jsonb_array_length(v_tasks->'rules') + jsonb_array_length(v_tasks->'pay_rules'),
    'payroll', jsonb_array_length(v_tasks->'payroll'), 'loans', jsonb_array_length(v_tasks->'loans'),
    'pay_adjustments', jsonb_array_length(v_tasks->'pay_adjustments'), 'settlements', jsonb_array_length(v_tasks->'settlements'),
    'changes', jsonb_array_length(v_tasks->'changes'), 'letters', jsonb_array_length(v_tasks->'letters'),
    'requisitions', jsonb_array_length(v_tasks->'requisitions'), 'offers', jsonb_array_length(v_tasks->'offers'),
    'interviews', jsonb_array_length(v_tasks->'interviews'), 'reviews', jsonb_array_length(v_tasks->'reviews'),
    'cases', jsonb_array_length(v_tasks->'cases'), 'my_cases', jsonb_array_length(v_tasks->'my_cases'),
    'count', (v_tasks->>'count')::int));
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_verify_payroll(p_run uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_VERIFY');
  perform hr.require_run(p_run);
  select * into r from hr.payroll_runs where id = p_run for update;
  if r.id is null or r.status <> 'CALCULATED' then raise exception 'NOT_FOUND: This run is not waiting for verification.'; end if;
  if r.calculated_by = auth.uid() then raise exception 'SELF_APPROVAL: Someone other than the person who calculated it must verify.'; end if;
  if hr.my_slip_in_run(p_run) then raise exception 'SELF_APPROVAL: You cannot verify a payroll that contains your own salary.'; end if;
  update hr.payroll_runs set status = 'VERIFIED', verified_by = auth.uid(), verified_at = now(),
         notes = coalesce(nullif(btrim(p_note),''), notes) where id = p_run returning * into r;
  perform hr.notify_money(null, r.pay_group, 'PAY_APPROVE', 'PAYROLL', 'Payroll ' || to_char(r.period_start,'MM/YYYY') || ' waiting for approval',
    'رواتب ' || to_char(r.period_start,'MM/YYYY') || ' بانتظار الاعتماد', '/payroll/' || r.id, 'payroll-approve:' || r.id || ':' || r.calc_count);
  return hr.run_json(r);
end $function$
;
CREATE OR REPLACE FUNCTION public.hr_withdraw_compensation(p_revision uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.compensation_revisions;
begin
  perform hr.require_perm('EMP_SALARY_WRITE');
  select * into r from hr.compensation_revisions where id = p_revision for update;
  if r.id is null or r.status <> 'PENDING' then raise exception 'NOT_FOUND: No pending revision to withdraw.'; end if;
  perform hr.require_money(r.employee_id);
  if r.proposed_by <> auth.uid() then raise exception 'NOT_ALLOWED: Only the person who proposed it can withdraw it.' using errcode = '42501'; end if;
  update hr.compensation_revisions set status = 'REJECTED', decided_at = now(), decision_note = 'Withdrawn by proposer' where id = r.id;
  return public.hr_get_compensation(r.employee_id);
end $function$
;
-- Move an employee between the management (MG) and non-management (NMG) pay groups. Management payroll team only.
create or replace function public.hr_set_pay_group(p_employee uuid, p_group text, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e hr.employees; v_g text := upper(btrim(coalesce(p_group, '')));
begin
  perform hr.require_perm('MG_PAY');
  select * into e from hr.employees where id = p_employee for update;
  if e.id is null then raise exception 'NOT_FOUND: Employee not found.'; end if;
  if hr.is_me(p_employee) then raise exception 'NOT_ALLOWED: You cannot change your own pay group.' using errcode = '42501'; end if;
  if v_g not in ('NMG','MG') then raise exception 'INVALID: Choose management (MG) or non-management (NMG).'; end if;
  if v_g = e.pay_group then raise exception 'INVALID: The employee is already in this pay group.'; end if;
  if coalesce(length(btrim(p_reason)), 0) < 5 then raise exception 'REQUIRED: Give the reason (at least 5 characters).'; end if;
  if exists (select 1 from hr.payslips s join hr.payroll_runs r on r.id = s.run_id
             where s.employee_id = p_employee and r.status in ('CALCULATED','VERIFIED')) then
    raise exception 'PAYROLL_OPEN: This employee is in a payroll run waiting for verification or approval. Approve or return that run first.';
  end if;
  update hr.employees set pay_group = v_g where id = p_employee;
  insert into hr.access_log(user_id, employee_id, data_kind, detail)
  values (auth.uid(), p_employee, 'PAY_GROUP', e.pay_group || ' to ' || v_g || ': ' || btrim(p_reason));
  return public.hr_get_employee(p_employee);
end $$;

-- The management payroll team manages its own members (the Users page cannot add or remove this role once a member exists).
create or replace function public.hr_list_mg_access()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform hr.require_perm('MG_PAY');
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', up.user_id, 'name', coalesce(up.display_name, up.email), 'email', up.email,
      'member', exists (select 1 from hr.user_roles ur where ur.user_id = up.user_id and ur.role_code = 'MG_PAYROLL' and ur.revoked_at is null),
      'is_me', up.user_id = auth.uid()) order by coalesce(up.display_name, up.email))
    from hr.user_profiles up where up.is_active), '[]'::jsonb);
end $$;

create or replace function public.hr_set_mg_access(p_user uuid, p_member boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_name text; u record; v_on boolean := coalesce(p_member, false);
begin
  perform hr.require_perm('MG_PAY');
  if p_user = auth.uid() then raise exception 'NOT_ALLOWED: You cannot change your own access.' using errcode = '42501'; end if;
  select coalesce(display_name, email) into v_name from hr.user_profiles where user_id = p_user and is_active;
  if v_name is null then raise exception 'NOT_FOUND: User not found.'; end if;
  if v_on then
    insert into hr.user_roles(user_id, role_code, granted_by) values (p_user, 'MG_PAYROLL', auth.uid())
    on conflict (user_id, role_code) do update set revoked_at = null, revoked_by = null, granted_by = excluded.granted_by, granted_at = now()
      where hr.user_roles.revoked_at is not null;
  else
    update hr.user_roles set revoked_at = now(), revoked_by = auth.uid() where user_id = p_user and role_code = 'MG_PAYROLL' and revoked_at is null;
  end if;
  for u in select m.user_id from hr.users_with_perm('MG_PAY') m where m.user_id <> auth.uid() loop
    perform hr.notify(u.user_id, 'INFO', 'HIGH',
      case when v_on then 'Added to the management payroll team: ' else 'Removed from the management payroll team: ' end || v_name,
      case when v_on then 'أضيف إلى فريق رواتب الإدارة: ' else 'أزيل من فريق رواتب الإدارة: ' end || v_name,
      null, null, '/settings', 'MGACC:' || p_user || ':' || now()::text);
  end loop;
  return public.hr_list_mg_access();
end $$;

select hr.attach_audit();
select hr.secure_api();
