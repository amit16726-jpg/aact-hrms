-- AACT HRMS — 020 Phase 3: payroll & end of service — tables, dated Oman pay rules, calculation engine.
-- Idempotent; no destructive statements.

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------
insert into hr.permissions(code, module, description) values
  ('PAY_READ',    'Payroll', 'View payroll runs, payslips, loans, settlements and payroll reports'),
  ('PAY_PREPARE', 'Payroll', 'Calculate payroll; propose loans, one-off adjustments and final settlements'),
  ('PAY_VERIFY',  'Payroll', 'Verify a calculated payroll run (second person)'),
  ('PAY_APPROVE', 'Payroll', 'Approve payroll runs, loans, adjustments and settlements; export the bank salary file')
on conflict (code) do nothing;

insert into hr.role_permissions(role_code, perm_code)
select 'SUPER_ADMIN', code from hr.permissions
on conflict do nothing;

insert into hr.role_permissions(role_code, perm_code)
select r, p from (values
  ('HR_MANAGER','PAY_READ'),('HR_MANAGER','PAY_PREPARE'),('HR_MANAGER','PAY_VERIFY'),
  ('HR_OFFICER','PAY_READ'),('HR_OFFICER','PAY_PREPARE'),
  ('FINANCE','PAY_READ'),('FINANCE','PAY_VERIFY'),('FINANCE','PAY_APPROVE'),
  ('AUDITOR','PAY_READ')
) v(r, p)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Set-up: GL accounts per component, SPF base flag, employer bank details per company
-- ---------------------------------------------------------------------------
alter table hr.pay_components add column if not exists gl_account text;
alter table hr.pay_components add column if not exists spf_base boolean not null default true;
alter table hr.legal_entities add column if not exists spf_employer_no text;
alter table hr.legal_entities add column if not exists wps_bank_code text;
alter table hr.legal_entities add column if not exists wps_account text;
alter table hr.legal_entities add column if not exists wps_payer_cr text;

insert into hr.settings(key, value) values
  ('payroll_gl', '{"salary_payable":"2100","spf_payable":"2110","eosb_provision":"2120","loans_receivable":"1150","salary_expense":"5100","overtime_expense":"5110","spf_expense":"5120","eosb_expense":"5130","deductions_income":"4900","income_tax_payable":"2130"}'::jsonb),
  ('pay_day', '28')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Pay rules — dated values with legal source; maker-checker for changes (same pattern as time rules)
-- ---------------------------------------------------------------------------
create table if not exists hr.pay_rules (
  id               uuid primary key default gen_random_uuid(),
  code             text not null check (code in ('SPF_OMANI','SPF_EXPAT','GRATUITY','SAVINGS_EXPAT','DEDUCTIONS','INCOME_TAX','PAY_BASIS')),
  value            jsonb not null,
  effective_from   date not null,
  effective_to     date,
  rule_basis       text not null default 'LEGAL' check (rule_basis in ('LEGAL','COMPANY_POLICY')),
  legal_basis      text not null,
  status           text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED')),
  proposed_by      uuid,
  proposed_at      timestamptz not null default now(),
  decided_by       uuid,
  decided_at       timestamptz,
  decision_note    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (decided_by is null or proposed_by is null or decided_by <> proposed_by)
);
create index if not exists pay_rules_code on hr.pay_rules(code, effective_from desc) where status = 'APPROVED';

insert into hr.pay_rules(code, value, effective_from, effective_to, rule_basis, legal_basis, status)
select v.code, v.value::jsonb, v.f::date, v.t::date, v.basis, v.src, 'APPROVED'
from (values
  ('SPF_OMANI', '{"er_old_age":11,"ee_old_age":7.5,"er_injury":1,"er_job_security":0.5,"ee_job_security":0.5,"er_maternity":1,"er_sick":0,"ceiling":3000}',
   '2024-01-01', '2026-07-18', 'LEGAL', 'Social Protection Law RD 52/2023 — confirm rates with the Social Protection Fund'),
  ('SPF_OMANI', '{"er_old_age":11,"ee_old_age":7.5,"er_injury":1,"er_job_security":0.5,"ee_job_security":0.5,"er_maternity":1,"er_sick":1,"ceiling":3000}',
   '2026-07-19', null, 'LEGAL', 'Social Protection Law RD 52/2023 (sick-leave branch from 19 Jul 2026) — confirm with the Fund'),
  ('SPF_EXPAT', '{"er_maternity":1,"er_sick":1,"er_injury":0,"ceiling":0}',
   '2026-07-19', null, 'LEGAL', 'RD 52/2023 as amended by RD 60/2025 — work-injury date for expatriates to be confirmed'),
  ('GRATUITY', '{"cutoff":"2023-07-31","old_first_years":3,"old_first_days":15,"old_after_days":30,"new_days":30,"min_service_months":12}',
   '2023-07-26', null, 'LEGAL', 'Labour Law RD 53/2023, Art. 61 (expatriates; service to 31 Jul 2023 under the old rule)'),
  ('SAVINGS_EXPAT', '{"employer_pct":9,"active":0}',
   '2027-07-19', null, 'LEGAL', 'RD 52/2023 Art. 137–139, RD 60/2025 — switched off until the regulations are confirmed'),
  ('DEDUCTIONS', '{"max_pct":25}',
   '2023-07-26', null, 'LEGAL', 'Labour Law RD 53/2023, Art. 68, 95, 96'),
  ('INCOME_TAX', '{"rate_pct":5,"annual_threshold":42000,"active":0}',
   '2028-01-01', null, 'LEGAL', 'RD 56/2025 — switched off until the executive regulations are confirmed'),
  ('PAY_BASIS', '{"days_divisor":30,"hours_per_day":8,"absent_unpaid":1,"missing_punch_unpaid":0,"fund_leave_unpaid":0}',
   '2023-07-26', null, 'COMPANY_POLICY', 'AACT payroll policy (default) — daily rate = monthly / 30; hourly = daily / 8')
) v(code, value, f, t, basis, src)
where not exists (select 1 from hr.pay_rules r where r.code = v.code and r.effective_from = v.f::date);

create or replace function hr.pay_rule(p_code text, p_on date default null)
returns jsonb language sql stable security definer set search_path = '' as $$
  select r.value from hr.pay_rules r
  where r.code = p_code and r.status = 'APPROVED'
    and r.effective_from <= coalesce(p_on, hr.today())
    and (r.effective_to is null or r.effective_to >= coalesce(p_on, hr.today()))
  order by r.effective_from desc limit 1
$$;

create or replace function hr.pnum(p jsonb, k text, d numeric default 0)
returns numeric language sql immutable set search_path = '' as $$
  select coalesce(nullif(p->>k, '')::numeric, d)
$$;

-- ---------------------------------------------------------------------------
-- Payroll runs, payslips and lines
-- ---------------------------------------------------------------------------
create table if not exists hr.payroll_runs (
  id            uuid primary key default gen_random_uuid(),
  entity_id     uuid not null references hr.legal_entities(id),
  period_start  date not null check (extract(day from period_start) = 1),
  pay_date      date,
  status        text not null default 'DRAFT' check (status in ('DRAFT','CALCULATED','VERIFIED','APPROVED','PAID')),
  calc_count    int not null default 0,
  calculated_by uuid, calculated_at timestamptz,
  verified_by   uuid, verified_at timestamptz,
  approved_by   uuid, approved_at timestamptz,
  paid_by       uuid, paid_at timestamptz,
  return_note   text,
  reopen_reason text,
  notes         text,
  totals        jsonb not null default '{}'::jsonb,
  warning_count int not null default 0,
  created_by    uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (entity_id, period_start),
  check (verified_by is null or calculated_by is null or verified_by <> calculated_by),
  check (approved_by is null or ((calculated_by is null or approved_by <> calculated_by) and (verified_by is null or approved_by <> verified_by)))
);

create table if not exists hr.payslips (
  id               uuid primary key default gen_random_uuid(),
  run_id           uuid not null references hr.payroll_runs(id),
  employee_id      uuid not null references hr.employees(id),
  employee_no      text not null,
  full_name_en     text not null,
  full_name_ar     text,
  department_en    text, department_ar text,
  job_en           text, job_ar text,
  cost_centre      text,
  nationality      char(2),
  is_omani         boolean not null default false,
  civil_number     text,
  days_in_period   int not null,
  employed_days    int not null,
  paid_days        numeric(6,2) not null default 0,
  unpaid_days      numeric(6,2) not null default 0,
  basic            numeric(12,3) not null default 0,
  gross_fixed      numeric(12,3) not null default 0,
  total_earnings   numeric(12,3) not null default 0,
  total_deductions numeric(12,3) not null default 0,
  employer_cost    numeric(12,3) not null default 0,
  net              numeric(12,3) not null default 0,
  bank_name        text, account_number text, iban text, swift_code text,
  warnings         jsonb not null default '[]'::jsonb,
  created_at       timestamptz not null default now(),
  unique (run_id, employee_id)
);
create index if not exists payslips_employee on hr.payslips(employee_id);

create table if not exists hr.payslip_lines (
  id         uuid primary key default gen_random_uuid(),
  payslip_id uuid not null references hr.payslips(id) on delete cascade,
  code       text not null,
  name_en    text not null,
  name_ar    text not null,
  kind       text not null check (kind in ('EARNING','DEDUCTION','EMPLOYER')),
  amount     numeric(12,3) not null,
  qty        numeric(10,3),
  rate       numeric(12,4),
  gl_account text,
  ref_id     uuid,
  sort       int not null default 100
);
create index if not exists payslip_lines_slip on hr.payslip_lines(payslip_id);

-- ---------------------------------------------------------------------------
-- Loans & advances, one-off adjustments, final settlements, parallel run
-- ---------------------------------------------------------------------------
create table if not exists hr.employee_loans (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references hr.employees(id),
  kind          text not null check (kind in ('LOAN','ADVANCE')),
  amount        numeric(12,3) not null check (amount > 0),
  installment   numeric(12,3) not null check (installment > 0),
  first_month   date not null check (extract(day from first_month) = 1),
  reason        text not null check (length(btrim(reason)) >= 3),
  status        text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','CLOSED','CANCELLED')),
  proposed_by   uuid not null,
  proposed_at   timestamptz not null default now(),
  decided_by    uuid,
  decided_at    timestamptz,
  decision_note text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (installment <= amount),
  check (decided_by is null or decided_by <> proposed_by)
);
create index if not exists employee_loans_emp on hr.employee_loans(employee_id);

create table if not exists hr.final_settlements (
  id                 uuid primary key default gen_random_uuid(),
  employee_id        uuid not null references hr.employees(id),
  last_working_date  date not null,
  reason             text not null check (reason in ('RESIGNATION','TERMINATION','END_OF_CONTRACT','RETIREMENT','DEATH','OTHER')),
  notice_days        numeric(6,2) not null default 0,
  basic              numeric(12,3) not null default 0,
  gross              numeric(12,3) not null default 0,
  gratuity           numeric(12,3) not null default 0,
  leave_days         numeric(7,2) not null default 0,
  leave_pay          numeric(12,3) not null default 0,
  notice_pay         numeric(12,3) not null default 0,
  loan_recovery      numeric(12,3) not null default 0,
  other_earnings     numeric(12,3) not null default 0,
  other_deductions   numeric(12,3) not null default 0,
  net                numeric(12,3) not null default 0,
  details            jsonb not null default '{}'::jsonb,
  note               text,
  status             text not null default 'PREPARED' check (status in ('PREPARED','APPROVED','PAID','CANCELLED')),
  prepared_by        uuid not null,
  prepared_at        timestamptz not null default now(),
  approved_by        uuid,
  approved_at        timestamptz,
  decision_note      text,
  paid_at            timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (approved_by is null or approved_by <> prepared_by)
);
create index if not exists final_settlements_emp on hr.final_settlements(employee_id);

create table if not exists hr.loan_repayments (
  id            uuid primary key default gen_random_uuid(),
  loan_id       uuid not null references hr.employee_loans(id),
  month         date not null,
  amount        numeric(12,3) not null check (amount > 0),
  kind          text not null check (kind in ('PAYROLL','SETTLEMENT')),
  run_id        uuid references hr.payroll_runs(id),
  settlement_id uuid references hr.final_settlements(id),
  created_at    timestamptz not null default now()
);
create index if not exists loan_repayments_loan on hr.loan_repayments(loan_id);
create index if not exists loan_repayments_run on hr.loan_repayments(run_id);
create index if not exists loan_repayments_settlement on hr.loan_repayments(settlement_id);

create table if not exists hr.payroll_adjustments (
  id            uuid primary key default gen_random_uuid(),
  employee_id   uuid not null references hr.employees(id),
  period_start  date not null check (extract(day from period_start) = 1),
  kind          text not null check (kind in ('EARNING','DEDUCTION')),
  code          text not null check (code in ('BONUS','COMMISSION','ARREARS','ALLOWANCE','OTHER_EARN','PENALTY','DAMAGE','OTHER_DED')),
  amount        numeric(12,3) not null check (amount > 0),
  reason        text not null check (length(btrim(reason)) >= 3),
  status        text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED')),
  proposed_by   uuid not null,
  proposed_at   timestamptz not null default now(),
  decided_by    uuid,
  decided_at    timestamptz,
  decision_note text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check ((kind = 'EARNING' and code in ('BONUS','COMMISSION','ARREARS','ALLOWANCE','OTHER_EARN'))
      or (kind = 'DEDUCTION' and code in ('PENALTY','DAMAGE','OTHER_DED'))),
  check (decided_by is null or decided_by <> proposed_by)
);
create index if not exists payroll_adjustments_emp on hr.payroll_adjustments(employee_id, period_start);

create table if not exists hr.payroll_parallel (
  run_id      uuid not null references hr.payroll_runs(id),
  employee_no text not null,
  legacy_gross numeric(12,3),
  legacy_net  numeric(12,3) not null,
  note        text,
  loaded_by   uuid,
  loaded_at   timestamptz not null default now(),
  primary key (run_id, employee_no)
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Approved salary structure in force on a date
create or replace function hr.comp_on(p_employee uuid, p_on date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('revision_id', r.id, 'effective_from', r.effective_from,
    'basic', coalesce((select sum(l.amount) from hr.compensation_lines l join hr.pay_components c on c.code = l.component_code
                       where l.revision_id = r.id and c.is_basic), 0),
    'gross', coalesce((select sum(l.amount) from hr.compensation_lines l join hr.pay_components c on c.code = l.component_code
                       where l.revision_id = r.id and c.kind = 'EARNING'), 0),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('code', c.code, 'name_en', c.name_en, 'name_ar', c.name_ar, 'kind', c.kind,
                         'amount', l.amount, 'is_basic', c.is_basic, 'spf_base', c.spf_base, 'gl', c.gl_account, 'sort', c.sort) order by c.sort)
                       from hr.compensation_lines l join hr.pay_components c on c.code = l.component_code
                       where l.revision_id = r.id and l.amount > 0), '[]'::jsonb))
  from hr.compensation_revisions r
  where r.employee_id = p_employee and r.status in ('APPROVED','SUPERSEDED') and r.effective_from <= p_on
  order by r.effective_from desc, r.decided_at desc nulls last limit 1
$$;

create or replace function hr.loan_outstanding(p_loan uuid)
returns numeric language sql stable security definer set search_path = '' as $$
  select l.amount - coalesce((select sum(x.amount) from hr.loan_repayments x where x.loan_id = l.id), 0)
  from hr.employee_loans l where l.id = p_loan
$$;

-- End-of-service gratuity (expatriates, Art. 61): old rule for service up to the cut-off, one month's basic per year after it.
create or replace function hr.gratuity_calc(p_employee uuid, p_as_of date, p_basic numeric)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  e hr.employees; g jsonb; sav jsonb; v_cut date; v_start date; v_end date; v_old_days int := 0; v_new_days int := 0;
  v_old_years numeric; v_new_years numeric; v_first numeric; v_old numeric := 0; v_new numeric := 0; v_daily numeric;
  v_service int; v_sav_from date;
begin
  select * into e from hr.employees where id = p_employee;
  if e.id is null or e.nationality = 'OM' then
    return jsonb_build_object('applies', false, 'total', 0, 'service_days', 0, 'old_years', 0, 'new_years', 0, 'old_amount', 0, 'new_amount', 0);
  end if;
  g := coalesce(hr.pay_rule('GRATUITY', p_as_of), '{}'::jsonb);
  sav := hr.pay_rule('SAVINGS_EXPAT', p_as_of);
  v_cut := coalesce((g->>'cutoff')::date, date '2023-07-31');
  v_start := e.join_date; v_end := p_as_of;
  if sav is not null and hr.pnum(sav, 'active') = 1 then
    select min(effective_from) into v_sav_from from hr.pay_rules where code = 'SAVINGS_EXPAT' and status = 'APPROVED';
    if v_sav_from is not null and v_end >= v_sav_from then v_end := v_sav_from - 1; end if;
  end if;
  v_service := greatest(0, p_as_of - e.join_date + 1);
  if v_end < v_start then
    return jsonb_build_object('applies', true, 'total', 0, 'service_days', v_service, 'old_years', 0, 'new_years', 0, 'old_amount', 0, 'new_amount', 0);
  end if;
  if v_service < hr.pnum(g, 'min_service_months', 12) * 365.0 / 12 then
    return jsonb_build_object('applies', true, 'total', 0, 'service_days', v_service, 'old_years', 0, 'new_years', 0, 'old_amount', 0, 'new_amount', 0,
                              'below_minimum', true);
  end if;
  v_old_days := greatest(0, least(v_end, v_cut) - v_start + 1);
  v_new_days := greatest(0, v_end - greatest(v_start, v_cut + 1) + 1);
  v_old_years := round(v_old_days / 365.0, 4);
  v_new_years := round(v_new_days / 365.0, 4);
  v_daily := p_basic / 30.0;
  v_first := least(v_old_years, hr.pnum(g, 'old_first_years', 3));
  v_old := round(v_daily * (hr.pnum(g, 'old_first_days', 15) * v_first + hr.pnum(g, 'old_after_days', 30) * greatest(v_old_years - v_first, 0)), 3);
  v_new := round(v_daily * hr.pnum(g, 'new_days', 30) * v_new_years, 3);
  return jsonb_build_object('applies', true, 'service_days', v_service, 'old_years', v_old_years, 'new_years', v_new_years,
    'old_amount', v_old, 'new_amount', v_new, 'total', v_old + v_new, 'basic', p_basic, 'cutoff', v_cut);
end $$;

-- Sick (tiered) leave days in a range that are paid below 100 %, as day-equivalents of lost pay.
create or replace function hr.tiered_unpaid_days(p_employee uuid, p_from date, p_to date)
returns numeric language plpgsql stable security definer set search_path = '' as $$
declare r record; t jsonb; k int; v_w numeric; v_pct numeric; v_cum numeric; d date; v_total numeric := 0;
begin
  for r in select lr.* from hr.leave_requests lr join hr.leave_types lt on lt.code = lr.leave_type
           where lr.employee_id = p_employee and lr.status = 'APPROVED' and lt.pay_mode = 'TIERED'
             and lr.pay_breakdown is not null and lr.start_date <= p_to and lr.end_date >= p_from loop
    for k in 1..ceil(r.days)::int loop
      d := r.start_date + (k - 1);
      continue when d < p_from or d > p_to;
      v_w := least(1, r.days - (k - 1));
      v_cum := 0; v_pct := 0;
      for t in select * from jsonb_array_elements(r.pay_breakdown) loop
        v_cum := v_cum + (t->>'days')::numeric;
        if k <= v_cum then v_pct := (t->>'pct')::numeric; exit; end if;
      end loop;
      v_total := v_total + v_w * (100 - v_pct) / 100.0;
    end loop;
  end loop;
  return round(v_total, 2);
end $$;

-- Calculate one employee's payslip for a run (replaces any earlier payslip in the run).
create or replace function hr.calc_payslip(p_run uuid, p_employee uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  run hr.payroll_runs; e hr.employees; a hr.employee_assignments; v_m0 date; v_m1 date; v_dim int; v_s0 date; v_s1 date;
  v_full boolean; basis jsonb; v_div numeric; v_hpd numeric; comp jsonb; seg record; ln jsonb; v_slip uuid;
  v_basic numeric := 0; v_gross numeric := 0; v_daily_gross numeric; v_daily_basic numeric; v_hourly numeric;
  v_warn jsonb := '[]'::jsonb; v_amt numeric; v_fixed_earn numeric := 0; v_absent numeric := 0; v_missing numeric := 0;
  v_unpaid_leave numeric := 0; v_fund numeric := 0; v_tier numeric := 0; v_unpaid_total numeric; v_unpaid_amt numeric;
  v_ot_hours numeric := 0; v_ot_days numeric := 0; v_has_att boolean; v_spf_wage numeric; spf jsonb; v_cap numeric; v_capped numeric;
  g jsonb; sav jsonb; v_e numeric; v_d numeric; v_er numeric; v_debt numeric; v_debt_cap numeric; ded jsonb; x record;
  v_inst numeric; v_net_before numeric; tax jsonb; v_bank hr.employee_bank_accounts; v_dep hr.departments; v_job hr.job_titles;
  v_cc hr.cost_centres; v_lines jsonb := '[]'::jsonb; v_seg_days int; v_factor numeric; v_tmp jsonb; v_code text;
  v_comp_amt jsonb := '{}'::jsonb; v_comp_meta jsonb := '{}'::jsonb; gl jsonb := coalesce((select value from hr.settings where key = 'payroll_gl'), '{}'::jsonb);
  v_unpaid_days numeric; v_employed int;
begin
  select * into run from hr.payroll_runs where id = p_run;
  select * into e from hr.employees where id = p_employee;
  v_m0 := run.period_start; v_m1 := (v_m0 + interval '1 month - 1 day')::date; v_dim := extract(day from v_m1)::int;
  v_s0 := greatest(v_m0, e.join_date); v_s1 := least(v_m1, coalesce(e.separation_date, v_m1));
  if v_s1 < v_s0 then return null; end if;
  v_employed := v_s1 - v_s0 + 1;
  v_full := v_s0 = v_m0 and v_s1 = v_m1;
  basis := coalesce(hr.pay_rule('PAY_BASIS', v_m1), '{}'::jsonb);
  v_div := hr.pnum(basis, 'days_divisor', 30); if v_div <= 0 then v_div := v_dim; end if;
  v_hpd := hr.pnum(basis, 'hours_per_day', 8); if v_hpd <= 0 then v_hpd := 8; end if;

  delete from hr.payslips where run_id = p_run and employee_id = p_employee;

  -- 1. Fixed pay, prorated per salary segment (a mid-month revision splits the month)
  for seg in
    with b as (
      select v_s0 as d union
      select r.effective_from from hr.compensation_revisions r
       where r.employee_id = p_employee and r.status in ('APPROVED','SUPERSEDED') and r.effective_from > v_s0 and r.effective_from <= v_s1)
    select d as seg_from, coalesce(lead(d) over (order by d) - 1, v_s1) as seg_to from b order by d
  loop
    comp := hr.comp_on(p_employee, seg.seg_from);
    continue when comp is null;
    v_seg_days := seg.seg_to - seg.seg_from + 1;
    v_factor := case when v_full then v_seg_days::numeric / v_dim else least(1, v_seg_days::numeric / v_div) end;
    for ln in select * from jsonb_array_elements(comp->'lines') loop
      v_code := ln->>'code';
      v_comp_amt := v_comp_amt || jsonb_build_object(v_code, hr.pnum(v_comp_amt, v_code) + (ln->>'amount')::numeric * v_factor);
      v_comp_meta := v_comp_meta || jsonb_build_object(v_code, ln);
    end loop;
  end loop;
  comp := hr.comp_on(p_employee, v_s1);
  if comp is null then
    v_warn := v_warn || jsonb_build_array('No approved salary structure — nothing paid.');
  else
    v_basic := (comp->>'basic')::numeric; v_gross := (comp->>'gross')::numeric;
  end if;
  v_daily_gross := v_gross / v_div; v_daily_basic := v_basic / v_div; v_hourly := v_daily_basic / v_hpd;

  for x in select key, value from jsonb_each(v_comp_amt) loop
    ln := v_comp_meta->x.key;
    v_amt := round((x.value #>> '{}')::numeric, 3);
    continue when v_amt = 0;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', x.key, 'name_en', ln->>'name_en', 'name_ar', ln->>'name_ar',
      'kind', ln->>'kind', 'amount', v_amt, 'qty', v_employed, 'rate', null,
      'gl', coalesce(ln->>'gl', case when ln->>'kind' = 'EARNING' then gl->>'salary_expense' else gl->>'deductions_income' end),
      'sort', (ln->>'sort')::int, 'spf_base', coalesce((ln->>'spf_base')::boolean, true)));
    if ln->>'kind' = 'EARNING' then v_fixed_earn := v_fixed_earn + v_amt; end if;
  end loop;

  -- 2. Unpaid days from locked attendance and leave
  select count(*) > 0,
         coalesce(sum(case when a2.status = 'ABSENT' then 1 else 0 end), 0),
         coalesce(sum(case when a2.status = 'MISSING_PUNCH' then 1 else 0 end), 0),
         coalesce(sum(case when lt.pay_mode = 'UNPAID' then a2.leave_fraction else 0 end), 0),
         coalesce(sum(case when lt.paid_by = 'FUND' and lt.pay_mode <> 'UNPAID' then a2.leave_fraction else 0 end), 0)
    into v_has_att, v_absent, v_missing, v_unpaid_leave, v_fund
    from hr.attendance_days a2 left join hr.leave_types lt on lt.code = a2.leave_type
   where a2.employee_id = p_employee and a2.work_date between v_s0 and v_s1;
  if not v_has_att then
    v_warn := v_warn || jsonb_build_array('No attendance recorded this month — paid without attendance deductions.');
  end if;
  v_tier := hr.tiered_unpaid_days(p_employee, v_s0, v_s1);
  if hr.pnum(basis, 'absent_unpaid', 1) <> 1 then v_absent := 0; end if;
  if hr.pnum(basis, 'missing_punch_unpaid', 0) <> 1 then
    if v_missing > 0 then v_warn := v_warn || jsonb_build_array(v_missing || ' day(s) with a missing punch were paid.'); end if;
    v_missing := 0;
  end if;
  if hr.pnum(basis, 'fund_leave_unpaid', 0) <> 1 then v_fund := 0; end if;
  v_unpaid_total := 0;
  for x in select * from (values ('UNPAID_ABSENCE', 'Unpaid absence', 'غياب بدون أجر', v_absent + v_missing),
                                 ('UNPAID_LEAVE', 'Unpaid leave', 'إجازة بدون أجر', v_unpaid_leave),
                                 ('SICK_REDUCED', 'Sick leave below full pay', 'إجازة مرضية بأجر مخفض', v_tier),
                                 ('FUND_LEAVE', 'Leave paid by the Social Protection Fund', 'إجازة يدفعها صندوق الحماية الاجتماعية', v_fund)) t(code, en, ar, days) loop
    continue when x.days <= 0;
    v_amt := round(x.days * v_daily_gross, 3);
    v_amt := least(v_amt, greatest(v_fixed_earn - v_unpaid_total, 0));
    continue when v_amt <= 0;
    v_unpaid_total := v_unpaid_total + v_amt;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', x.code, 'name_en', x.en, 'name_ar', x.ar, 'kind', 'DEDUCTION',
      'amount', v_amt, 'qty', x.days, 'rate', round(v_daily_gross, 4), 'gl', gl->>'salary_expense', 'sort', 60));
  end loop;
  v_unpaid_days := v_absent + v_missing + v_unpaid_leave + v_tier + v_fund;

  -- 3. Overtime approved for pay
  select coalesce(sum(o.pay_hours) filter (where o.day_kind = 'WORKDAY'), 0), coalesce(sum(o.pay_days) filter (where o.day_kind <> 'WORKDAY'), 0)
    into v_ot_hours, v_ot_days
    from hr.overtime_requests o where o.employee_id = p_employee and o.status = 'APPROVED' and o.comp_choice = 'PAY'
     and o.work_date between v_s0 and v_s1;
  if v_ot_hours > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', 'OT_WORKDAY', 'name_en', 'Overtime (working days)', 'name_ar', 'عمل إضافي (أيام العمل)',
      'kind', 'EARNING', 'amount', round(v_ot_hours * v_hourly, 3), 'qty', v_ot_hours, 'rate', round(v_hourly, 4), 'gl', gl->>'overtime_expense', 'sort', 20));
  end if;
  if v_ot_days > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', 'OT_RESTDAY', 'name_en', 'Overtime (rest days and holidays)', 'name_ar', 'عمل إضافي (أيام الراحة والعطل)',
      'kind', 'EARNING', 'amount', round(v_ot_days * v_daily_basic, 3), 'qty', v_ot_days, 'rate', round(v_daily_basic, 4), 'gl', gl->>'overtime_expense', 'sort', 21));
  end if;

  -- 4. Approved one-off adjustments; debt deductions capped (Art. 95/96)
  ded := coalesce(hr.pay_rule('DEDUCTIONS', v_m1), '{}'::jsonb);
  v_debt_cap := round((v_fixed_earn - v_unpaid_total) * hr.pnum(ded, 'max_pct', 25) / 100.0, 3);
  v_debt := 0;
  for x in select pa.* from hr.payroll_adjustments pa where pa.employee_id = p_employee and pa.period_start = v_m0 and pa.status = 'APPROVED'
           order by pa.kind, pa.proposed_at loop
    v_amt := x.amount;
    if x.kind = 'DEDUCTION' then
      if v_debt + v_amt > v_debt_cap then
        v_warn := v_warn || jsonb_build_array('Deduction ' || x.code || ' of ' || v_amt || ' reduced to the ' || hr.pnum(ded, 'max_pct', 25) || ' % limit.');
        v_amt := greatest(v_debt_cap - v_debt, 0);
      end if;
      v_debt := v_debt + v_amt;
      continue when v_amt <= 0;
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', x.code,
      'name_en', case x.code when 'BONUS' then 'Bonus' when 'COMMISSION' then 'Commission' when 'ARREARS' then 'Arrears'
                 when 'ALLOWANCE' then 'One-off allowance' when 'OTHER_EARN' then 'Other earning' when 'PENALTY' then 'Penalty'
                 when 'DAMAGE' then 'Damage recovery' else 'Other deduction' end,
      'name_ar', case x.code when 'BONUS' then 'مكافأة' when 'COMMISSION' then 'عمولة' when 'ARREARS' then 'فروقات مستحقة'
                 when 'ALLOWANCE' then 'بدل لمرة واحدة' when 'OTHER_EARN' then 'استحقاق آخر' when 'PENALTY' then 'جزاء'
                 when 'DAMAGE' then 'استرداد أضرار' else 'استقطاع آخر' end,
      'kind', x.kind, 'amount', v_amt, 'qty', null, 'rate', null, 'ref', x.id,
      'gl', case when x.kind = 'EARNING' then gl->>'salary_expense' else gl->>'deductions_income' end, 'sort', case when x.kind = 'EARNING' then 30 else 70 end));
  end loop;

  -- 5. Social Protection Fund
  select coalesce(sum((l->>'amount')::numeric), 0) into v_spf_wage from jsonb_array_elements(v_lines) l
   where l->>'kind' = 'EARNING' and coalesce((l->>'spf_base')::boolean, false);
  v_spf_wage := greatest(v_spf_wage - v_unpaid_total, 0);
  if e.nationality = 'OM' then
    spf := coalesce(hr.pay_rule('SPF_OMANI', v_m1), '{}'::jsonb);
    v_cap := hr.pnum(spf, 'ceiling', 0);
    v_capped := case when v_cap > 0 then least(v_spf_wage, v_cap) else v_spf_wage end;
    for x in select * from (values
        ('SPF_EE_OLD_AGE', 'Social protection – old age (employee)', 'الحماية الاجتماعية – الشيخوخة (الموظف)', 'DEDUCTION', 'ee_old_age', true),
        ('SPF_EE_JOB_SECURITY', 'Social protection – job security (employee)', 'الحماية الاجتماعية – الأمان الوظيفي (الموظف)', 'DEDUCTION', 'ee_job_security', false),
        ('SPF_ER_OLD_AGE', 'Social protection – old age (employer)', 'الحماية الاجتماعية – الشيخوخة (صاحب العمل)', 'EMPLOYER', 'er_old_age', true),
        ('SPF_ER_INJURY', 'Social protection – work injury (employer)', 'الحماية الاجتماعية – إصابات العمل (صاحب العمل)', 'EMPLOYER', 'er_injury', true),
        ('SPF_ER_JOB_SECURITY', 'Social protection – job security (employer)', 'الحماية الاجتماعية – الأمان الوظيفي (صاحب العمل)', 'EMPLOYER', 'er_job_security', false),
        ('SPF_ER_MATERNITY', 'Social protection – maternity (employer)', 'الحماية الاجتماعية – الأمومة (صاحب العمل)', 'EMPLOYER', 'er_maternity', false),
        ('SPF_ER_SICK', 'Social protection – sick leave (employer)', 'الحماية الاجتماعية – الإجازات المرضية (صاحب العمل)', 'EMPLOYER', 'er_sick', false)
      ) t(code, en, ar, kind, k, capped) loop
      continue when hr.pnum(spf, x.k) <= 0;
      v_amt := round(case when x.capped then v_capped else v_spf_wage end * hr.pnum(spf, x.k) / 100.0, 3);
      continue when v_amt <= 0;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', x.code, 'name_en', x.en, 'name_ar', x.ar, 'kind', x.kind,
        'amount', v_amt, 'qty', case when x.capped then v_capped else v_spf_wage end, 'rate', hr.pnum(spf, x.k),
        'gl', case when x.kind = 'DEDUCTION' then gl->>'spf_payable' else gl->>'spf_expense' end, 'sort', case when x.kind = 'DEDUCTION' then 80 else 90 end));
    end loop;
    if v_cap > 0 and v_spf_wage > v_cap then v_warn := v_warn || jsonb_build_array('Old-age and injury contributions capped at OMR ' || v_cap || '.'); end if;
  else
    spf := hr.pay_rule('SPF_EXPAT', v_m1);
    if spf is not null then
      v_cap := hr.pnum(spf, 'ceiling', 0);
      v_capped := case when v_cap > 0 then least(v_spf_wage, v_cap) else v_spf_wage end;
      for x in select * from (values
          ('SPF_ER_MATERNITY', 'Social protection – maternity (employer)', 'الحماية الاجتماعية – الأمومة (صاحب العمل)', 'er_maternity'),
          ('SPF_ER_SICK', 'Social protection – sick leave (employer)', 'الحماية الاجتماعية – الإجازات المرضية (صاحب العمل)', 'er_sick'),
          ('SPF_ER_INJURY', 'Social protection – work injury (employer)', 'الحماية الاجتماعية – إصابات العمل (صاحب العمل)', 'er_injury')) t(code, en, ar, k) loop
        continue when hr.pnum(spf, x.k) <= 0;
        v_amt := round(v_capped * hr.pnum(spf, x.k) / 100.0, 3);
        continue when v_amt <= 0;
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', x.code, 'name_en', x.en, 'name_ar', x.ar, 'kind', 'EMPLOYER',
          'amount', v_amt, 'qty', v_capped, 'rate', hr.pnum(spf, x.k), 'gl', gl->>'spf_expense', 'sort', 90));
      end loop;
    end if;
    -- 6. End-of-service: gratuity accrual, or savings fund once active
    sav := hr.pay_rule('SAVINGS_EXPAT', v_m1);
    if sav is not null and hr.pnum(sav, 'active') = 1 then
      v_amt := round(v_basic * v_employed / v_dim * hr.pnum(sav, 'employer_pct', 9) / 100.0, 3);
      if v_amt > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', 'SAVINGS_FUND', 'name_en', 'Expatriate savings fund (employer)',
          'name_ar', 'صندوق ادخار الوافدين (صاحب العمل)', 'kind', 'EMPLOYER', 'amount', v_amt, 'qty', v_basic, 'rate', hr.pnum(sav, 'employer_pct', 9),
          'gl', gl->>'eosb_expense', 'sort', 95));
      end if;
    else
      g := coalesce(hr.pay_rule('GRATUITY', v_m1), '{}'::jsonb);
      v_amt := round(v_basic * hr.pnum(g, 'new_days', 30) / 30.0 / 12.0 * v_employed / v_dim, 3);
      if v_amt > 0 then
        v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', 'EOSB_ACCRUAL', 'name_en', 'End-of-service gratuity accrual',
          'name_ar', 'استحقاق مكافأة نهاية الخدمة', 'kind', 'EMPLOYER', 'amount', v_amt, 'qty', v_basic, 'rate', null,
          'gl', gl->>'eosb_expense', 'sort', 95));
      end if;
    end if;
  end if;

  -- 7. Income tax (inactive until the regulations are confirmed)
  tax := hr.pay_rule('INCOME_TAX', v_m1);
  if tax is not null and hr.pnum(tax, 'active') = 1 then
    select coalesce(sum((l->>'amount')::numeric), 0) into v_e from jsonb_array_elements(v_lines) l where l->>'kind' = 'EARNING';
    v_amt := round(greatest((v_e - v_unpaid_total) * 12 - hr.pnum(tax, 'annual_threshold', 42000), 0) * hr.pnum(tax, 'rate_pct', 5) / 100.0 / 12, 3);
    if v_amt > 0 then
      v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', 'INCOME_TAX', 'name_en', 'Personal income tax withheld',
        'name_ar', 'ضريبة الدخل الشخصي المستقطعة', 'kind', 'DEDUCTION', 'amount', v_amt, 'qty', null, 'rate', hr.pnum(tax, 'rate_pct', 5),
        'gl', gl->>'income_tax_payable', 'sort', 85));
    end if;
  end if;

  -- 8. Loan and advance instalments (never driving net pay below zero)
  select coalesce(sum((l->>'amount')::numeric) filter (where l->>'kind' = 'EARNING'), 0),
         coalesce(sum((l->>'amount')::numeric) filter (where l->>'kind' = 'DEDUCTION'), 0)
    into v_e, v_d from jsonb_array_elements(v_lines) l;
  v_net_before := v_e - v_d;
  for x in select l.* from hr.employee_loans l where l.employee_id = p_employee and l.status = 'APPROVED' and l.first_month <= v_m0
           order by l.first_month, l.proposed_at loop
    v_inst := least(x.installment, hr.loan_outstanding(x.id));
    continue when v_inst <= 0;
    if v_inst > v_net_before then
      v_warn := v_warn || jsonb_build_array(case when v_net_before <= 0 then 'Loan instalment skipped: no net pay left.'
                                                  else 'Loan instalment reduced to the net pay available.' end);
      v_inst := greatest(v_net_before, 0);
    end if;
    continue when v_inst <= 0;
    v_net_before := v_net_before - v_inst;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('code', 'LOAN',
      'name_en', case when x.kind = 'ADVANCE' then 'Salary advance recovery' else 'Loan instalment' end,
      'name_ar', case when x.kind = 'ADVANCE' then 'استرداد سلفة راتب' else 'قسط قرض' end,
      'kind', 'DEDUCTION', 'amount', v_inst, 'qty', null, 'rate', null, 'ref', x.id, 'gl', gl->>'loans_receivable', 'sort', 75));
  end loop;

  -- 9. Totals, bank details, snapshot
  select coalesce(sum((l->>'amount')::numeric) filter (where l->>'kind' = 'EARNING'), 0),
         coalesce(sum((l->>'amount')::numeric) filter (where l->>'kind' = 'DEDUCTION'), 0),
         coalesce(sum((l->>'amount')::numeric) filter (where l->>'kind' = 'EMPLOYER'), 0)
    into v_e, v_d, v_er from jsonb_array_elements(v_lines) l;
  if v_e - v_d < 0 then v_warn := v_warn || jsonb_build_array('Net pay is negative — check deductions.'); end if;
  -- salaries are paid after the month ends: use the account approved as at calculation
  select * into v_bank from hr.employee_bank_accounts b where b.employee_id = p_employee and b.status = 'APPROVED' and b.effective_from <= greatest(v_m1, hr.today())
   order by b.effective_from desc, b.decided_at desc nulls last limit 1;
  if v_bank.id is null and v_e - v_d > 0 then v_warn := v_warn || jsonb_build_array('No approved bank account — cannot be paid by WPS.'); end if;
  a := hr.current_assignment(p_employee, v_s1);
  select * into v_dep from hr.departments where id = a.department_id;
  select * into v_job from hr.job_titles where id = a.job_title_id;
  select * into v_cc from hr.cost_centres where id = coalesce(a.cost_centre_id, v_dep.cost_centre_id);

  insert into hr.payslips(run_id, employee_id, employee_no, full_name_en, full_name_ar, department_en, department_ar, job_en, job_ar,
                          cost_centre, nationality, is_omani, civil_number, days_in_period, employed_days, paid_days, unpaid_days,
                          basic, gross_fixed, total_earnings, total_deductions, employer_cost, net,
                          bank_name, account_number, iban, swift_code, warnings)
  values (p_run, p_employee, e.employee_no, e.full_name_en, e.full_name_ar, v_dep.name_en, v_dep.name_ar, v_job.name_en, v_job.name_ar,
          coalesce(v_cc.gl_code, v_cc.code), e.nationality, e.nationality = 'OM', e.civil_number, v_dim, v_employed,
          greatest(v_employed - v_unpaid_days, 0), v_unpaid_days, v_basic, v_gross, v_e, v_d, v_er, v_e - v_d,
          v_bank.bank_name, v_bank.account_number, v_bank.iban, v_bank.swift_code, v_warn)
  returning id into v_slip;
  insert into hr.payslip_lines(payslip_id, code, name_en, name_ar, kind, amount, qty, rate, gl_account, ref_id, sort)
  select v_slip, l->>'code', l->>'name_en', coalesce(l->>'name_ar', l->>'name_en'), l->>'kind', (l->>'amount')::numeric,
         nullif(l->>'qty','')::numeric, nullif(l->>'rate','')::numeric, l->>'gl', nullif(l->>'ref','')::uuid, coalesce((l->>'sort')::int, 100)
  from jsonb_array_elements(v_lines) l;
  return v_slip;
end $$;

-- Calculate a whole run.
create or replace function hr.calc_run(p_run uuid)
returns int language plpgsql security definer set search_path = '' as $$
declare run hr.payroll_runs; v_m1 date; x record; v_n int := 0;
begin
  select * into run from hr.payroll_runs where id = p_run for update;
  v_m1 := (run.period_start + interval '1 month - 1 day')::date;
  delete from hr.payslips where run_id = p_run
    and employee_id not in (select e.id from hr.employees e where e.entity_id = run.entity_id and e.join_date <= v_m1
                            and (e.separation_date is null or e.separation_date >= run.period_start));
  for x in select e.id from hr.employees e where e.entity_id = run.entity_id and e.join_date <= v_m1
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
end $$;

-- Final settlement figures (not saved).
create or replace function hr.settlement_calc(p_employee uuid, p_last date, p_notice_days numeric, p_other jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
  if exists (select 1 from hr.payroll_runs r where r.entity_id = e.entity_id and r.period_start = date_trunc('month', p_last)::date
             and r.status in ('APPROVED','PAID')) is false then
    v_warn := v_warn || jsonb_build_array('Salary for ' || to_char(p_last, 'MM/YYYY') || ' up to the last working day is paid through that month''s payroll run.');
  end if;
  return jsonb_build_object('employee_id', p_employee, 'last_working_date', p_last, 'basic', v_basic, 'gross', v_gross,
    'gratuity', coalesce((g->>'total')::numeric, 0), 'gratuity_detail', g, 'leave_days', v_leave, 'leave_partial_accrual', v_part,
    'leave_pay', v_leave_pay, 'notice_days', coalesce(p_notice_days, 0), 'notice_pay', v_notice, 'loan_recovery', v_loans, 'loans', v_loan_list,
    'other_earnings', v_oe, 'other_deductions', v_od, 'other', coalesce(p_other, '[]'::jsonb),
    'net', coalesce((g->>'total')::numeric, 0) + v_leave_pay + v_notice + v_oe - v_loans - v_od,
    'daily_gross', round(v_gross / v_div, 4), 'warnings', v_warn);
end $$;

-- Payroll runs can only be calculated for a locked attendance month.
create or replace function hr.attendance_locked(p_entity uuid, p_month date)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from hr.attendance_periods where entity_id = p_entity and period_start = p_month and status = 'LOCKED')
$$;

select hr.attach_audit();
select hr.secure_api();
