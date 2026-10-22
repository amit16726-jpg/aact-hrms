-- AACT HRMS — 1.9.0: separate monthly payroll run for management (MG) employees.
-- One run per company, month and pay group. Run once; safe to re-run.
-- Cloud test project: this file contains schema changes the database connector does not run, so it is applied in the
-- Supabase SQL editor. No employee data is removed.

alter table hr.payroll_runs drop constraint if exists payroll_runs_entity_id_period_start_key;
create unique index if not exists payroll_runs_entity_period_group on hr.payroll_runs(entity_id, period_start, pay_group);

-- Calculation takes only the employees of the run's pay group.
CREATE OR REPLACE FUNCTION hr.calc_run(p_run uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare run hr.payroll_runs; v_m1 date; x record; v_n int := 0;
begin
  select * into run from hr.payroll_runs where id = p_run for update;
  v_m1 := (run.period_start + interval '1 month - 1 day')::date;
  delete from hr.payslips where run_id = p_run
    and employee_id not in (select e.id from hr.employees e where e.entity_id = run.entity_id and e.pay_group = run.pay_group and e.join_date <= v_m1
                            and (e.separation_date is null or e.separation_date >= run.period_start));
  for x in select e.id from hr.employees e where e.entity_id = run.entity_id and e.pay_group = run.pay_group and e.join_date <= v_m1
           and (e.separation_date is null or e.separation_date >= run.period_start) order by e.employee_no loop
    if hr.calc_payslip(p_run, x.id) is not null then v_n := v_n + 1; end if;
  end loop;
  update hr.payroll_runs set totals = (
      select jsonb_build_object('employees', count(*), 'earnings', coalesce(sum(s.total_earnings), 0), 'deductions', coalesce(sum(s.total_deductions), 0),
        'net', coalesce(sum(s.net), 0), 'employer_cost', coalesce(sum(s.employer_cost), 0), 'basic', coalesce(sum(s.basic), 0),
        'spf_employee', coalesce((select sum(l.amount) from hr.payslip_lines l join hr.payslips s2 on s2.id = l.payslip_id
                                   where s2.run_id = p_run and l.code like 'SPF_EE%'), 0),
        'spf_employer', coalesce((select sum(l.amount) from hr.payslip_lines l join hr.payslips s2 on s2.id = l.payslip_id
                                   where s2.run_id = p_run and l.code like 'SPF_ER%'), 0),
        'overtime', coalesce((select sum(l.amount) from hr.payslip_lines l join hr.payslips s2 on s2.id = l.payslip_id
                               where s2.run_id = p_run and l.code like 'OT_%'), 0),
        'eosb', coalesce((select sum(l.amount) from hr.payslip_lines l join hr.payslips s2 on s2.id = l.payslip_id
                           where s2.run_id = p_run and l.code in ('EOSB_ACCRUAL','SAVINGS_FUND')), 0),
        'loans', coalesce((select sum(l.amount) from hr.payslip_lines l join hr.payslips s2 on s2.id = l.payslip_id
                            where s2.run_id = p_run and l.code = 'LOAN'), 0),
        'omani', count(*) filter (where s.is_omani), 'expat', count(*) filter (where not s.is_omani))
      from hr.payslips s where s.run_id = p_run),
    warning_count = (select count(*) from hr.payslips s, jsonb_array_elements(s.warnings) w where s.run_id = p_run)
  where id = p_run;
  return v_n;
end $function$
;

CREATE OR REPLACE FUNCTION public.hr_reopen_payroll(p_run uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r hr.payroll_runs;
begin
  perform hr.require_perm('PAY_APPROVE');
  perform hr.require_run(p_run);
  if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'REQUIRED: Give a reason for reopening.'; end if;
  select * into r from hr.payroll_runs where id = p_run for update;
  if r.id is null or r.status <> 'APPROVED' then raise exception 'NOT_FOUND: Only an approved, unpaid run can be reopened.'; end if;
  delete from hr.loan_repayments where run_id = p_run;
  update hr.employee_loans set status = 'APPROVED' where status = 'CLOSED' and hr.loan_outstanding(id) > 0;
  update hr.payroll_runs set status = 'DRAFT', verified_by = null, verified_at = null, approved_by = null, approved_at = null,
         reopen_reason = btrim(p_reason) where id = p_run returning * into r;
  return hr.run_json(r);
end $function$
;

CREATE OR REPLACE FUNCTION public.hr_save_parallel(p_run uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare x jsonb; v_n int := 0; v_err jsonb := '[]'::jsonb; i int := 0;
begin
  perform hr.require_perm('PAY_PREPARE');
  perform hr.require_run(p_run);
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
end $function$
;

-- Creating a run now names the pay group; MG runs need the management payroll permission.
drop function if exists public.hr_create_payroll_run(uuid, text, date);
create or replace function public.hr_create_payroll_run(p_entity uuid, p_month text, p_pay_date date default null, p_pay_group text default 'NMG')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_m0 date := hr.month_start(p_month); r hr.payroll_runs; v_day int; v_g text := upper(btrim(coalesce(p_pay_group, 'NMG')));
begin
  perform hr.require_perm('PAY_PREPARE');
  if v_g not in ('NMG','MG') then raise exception 'INVALID: Unknown pay group.'; end if;
  if not hr.run_ok(v_g) then
    raise exception 'MG_ONLY: The management (MG) payroll is restricted to the management payroll team.' using errcode = '42501';
  end if;
  if not exists (select 1 from hr.legal_entities where id = p_entity) then raise exception 'NOT_FOUND: Company not found.'; end if;
  if v_m0 > date_trunc('month', hr.today())::date then raise exception 'INVALID: Payroll cannot be prepared for a future month.'; end if;
  if exists (select 1 from hr.payroll_runs where entity_id = p_entity and period_start = v_m0 and pay_group = v_g) then
    raise exception 'DUPLICATE: A payroll run for this month already exists.';
  end if;
  v_day := coalesce((select (value #>> '{}')::int from hr.settings where key = 'pay_day'), 28);
  insert into hr.payroll_runs(entity_id, period_start, pay_date, pay_group, created_by)
  values (p_entity, v_m0, coalesce(p_pay_date, least(v_m0 + (v_day - 1), (v_m0 + interval '1 month - 1 day')::date)), v_g, auth.uid())
  returning * into r;
  return hr.run_json(r);
end $$;

select hr.attach_audit();
select hr.secure_api();
