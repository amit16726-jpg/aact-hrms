-- AACT HRMS — 1.9.0: management (MG) pay confidentiality.
-- Employees are in pay group NMG (non-management, default) or MG (management). Every money item of an MG employee —
-- salary, bank account, payslips, loans and advances, one-off pay items, final settlement, gratuity, salary letters —
-- is visible only to holders of the MG_PAY permission, which belongs only to the "Management payroll" role.
-- HR keeps every non-financial record of MG employees (personal details, documents, attendance, leave, performance).
-- MG employees are paid in their own monthly payroll run (payroll_runs.pay_group = 'MG').
-- Idempotent. No destructive statements.

-- ---------------------------------------------------------------------------
-- Pay group on employees and payroll runs
-- ---------------------------------------------------------------------------
alter table hr.employees add column if not exists pay_group text not null default 'NMG';
alter table hr.payroll_runs add column if not exists pay_group text not null default 'NMG';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'employees_pay_group_check' and conrelid = 'hr.employees'::regclass) then
    alter table hr.employees add constraint employees_pay_group_check check (pay_group in ('NMG','MG'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'payroll_runs_pay_group_check' and conrelid = 'hr.payroll_runs'::regclass) then
    alter table hr.payroll_runs add constraint payroll_runs_pay_group_check check (pay_group in ('NMG','MG'));
  end if;
end $$;

create index if not exists employees_mg on hr.employees(id) where pay_group = 'MG';

-- ---------------------------------------------------------------------------
-- Permission and role
-- ---------------------------------------------------------------------------
insert into hr.permissions(code, module, description) values
  ('MG_PAY', 'Compensation', 'See and process salaries, payroll and all money items of management (MG) employees')
on conflict (code) do nothing;

insert into hr.roles(code, name_en, name_ar, description, sort) values
  ('MG_PAYROLL', 'Management payroll', 'رواتب الإدارة', 'Salaries, payroll, bank and all money items of management (MG) employees', 8)
on conflict (code) do nothing;

-- MG_PAY can belong only to the Management payroll role. A later "give the super administrator every permission"
-- statement simply skips it instead of failing.
create or replace function hr.guard_mg_perm()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.perm_code = 'MG_PAY' and new.role_code <> 'MG_PAYROLL' then return null; end if;
  return new;
end $$;
create or replace trigger aa_guard_mg before insert or update on hr.role_permissions
  for each row execute function hr.guard_mg_perm();

insert into hr.role_permissions(role_code, perm_code)
select 'MG_PAYROLL', p from unnest(array['MG_PAY','ORG_READ','EMP_READ','EMP_SALARY_READ','EMP_SALARY_WRITE','SALARY_APPROVE',
  'EMP_BANK_READ','EMP_BANK_WRITE','BANK_APPROVE','PAY_READ','PAY_PREPARE','PAY_VERIFY','PAY_APPROVE','LETTER_PREPARE','LETTER_APPROVE']) p
where exists (select 1 from hr.permissions where code = p)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Central checks
-- ---------------------------------------------------------------------------
create or replace function hr.is_mg(p_employee uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select e.pay_group = 'MG' from hr.employees e where e.id = p_employee), false)
$$;

-- May the signed-in user see or process this employee's money items? (no exception for the employee themself:
-- self-service functions check is_me separately)
create or replace function hr.money_ok(p_employee uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select not hr.is_mg(p_employee) or hr.has_perm('MG_PAY')
$$;

create or replace function hr.require_money(p_employee uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not hr.money_ok(p_employee) then
    raise exception 'MG_ONLY: Pay details of management (MG) employees are restricted to the management payroll team.' using errcode = '42501';
  end if;
end $$;

create or replace function hr.run_ok(p_group text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(p_group, 'NMG') <> 'MG' or hr.has_perm('MG_PAY')
$$;

create or replace function hr.require_run(p_run uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
declare v_group text;
begin
  select pay_group into v_group from hr.payroll_runs where id = p_run;
  if not hr.run_ok(v_group) then
    raise exception 'MG_ONLY: The management (MG) payroll is restricted to the management payroll team.' using errcode = '42501';
  end if;
end $$;

-- Users who hold p_perm and may see this employee's (or this pay group's) money: used for approval notifications.
create or replace function hr.money_users(p_perm text, p_employee uuid, p_group text default null)
returns table(user_id uuid) language sql stable security definer set search_path = '' as $$
  select h.user_id from hr.users_with_perm(p_perm) h
  where not (hr.is_mg(p_employee) or coalesce(p_group, 'NMG') = 'MG')
     or h.user_id in (select m.user_id from hr.users_with_perm('MG_PAY') m)
$$;

create or replace function hr.notify_money(p_employee uuid, p_group text, p_perm text, p_kind text, p_title_en text, p_title_ar text,
                                           p_link text, p_ref text)
returns void language plpgsql security definer set search_path = '' as $$
declare u record;
begin
  for u in select m.user_id from hr.money_users(p_perm, p_employee, p_group) m loop
    continue when u.user_id = auth.uid();
    perform hr.notify(u.user_id, p_kind, 'NORMAL', p_title_en, p_title_ar, null, null, p_link, p_ref);
  end loop;
end $$;

-- Audit rows about money items of MG employees (or the MG payroll) are shown only to MG_PAY holders.
-- Rows that can no longer be traced to an employee (e.g. lines of a recalculated payslip) are hidden from others.
create or replace function hr.audit_ok(a hr.audit_log)
returns boolean language sql stable security definer set search_path = '' as $$
  select hr.has_perm('MG_PAY') or case
    when a.table_name = 'payroll_runs' then coalesce(a.new_data->>'pay_group', a.old_data->>'pay_group', 'NMG') <> 'MG'
    when a.table_name in ('compensation_revisions','compensation_lines','employee_bank_accounts','payslips','employee_loans',
                          'payroll_adjustments','final_settlements','letters') then not hr.is_mg(a.employee_id)
    when a.table_name = 'payslip_lines' then coalesce((select not hr.is_mg(s.employee_id) from hr.payslips s
                          where s.id = nullif(coalesce(a.new_data->>'payslip_id', a.old_data->>'payslip_id'), '')::uuid), false)
    when a.table_name = 'loan_repayments' then coalesce((select not hr.is_mg(l.employee_id) from hr.employee_loans l
                          where l.id = nullif(coalesce(a.new_data->>'loan_id', a.old_data->>'loan_id'), '')::uuid), false)
    when a.table_name = 'payroll_parallel' then coalesce((select r.pay_group <> 'MG' from hr.payroll_runs r
                          where r.id = nullif(coalesce(a.new_data->>'run_id', a.old_data->>'run_id'), '')::uuid), false)
    else true end
$$;

select hr.attach_audit();
select hr.secure_api();
