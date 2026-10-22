-- =============================================================================
-- 1.10.0 — support for the AACT masters and the first real data load
--  * departments and job titles get "also known as" names (aliases), so an import file can use
--    the names people actually write ("Lab", "Plant 1", "Jr.Supervisor") instead of codes
--  * import matches masters by code, name or alias, ignoring spaces, dots and case
--  * plain employee numbers in a file ("472") become the company format ("AACT-0472")
--  * the next automatic employee number continues after the highest number in use
--  * import accepts day-first dates (12.05.1998, 12/05/1998, 12-05-1998) and OMANI as a nationality
--  * import can place management staff in the MG pay group (management payroll team only)
--  * pay component names can be corrected and components switched off in Payroll set-up
-- =============================================================================

alter table hr.departments add column if not exists aliases text[] not null default '{}';
alter table hr.job_titles  add column if not exists aliases text[] not null default '{}';

create or replace function hr.master_def(p_kind text, out tbl text, out cols text[], out keycol text, out has_entity boolean)
language plpgsql immutable set search_path = '' as $$
begin
  keycol := 'id'; has_entity := true;
  case p_kind
    when 'entity' then tbl := 'legal_entities'; has_entity := false;
      cols := array['code','name_en','name_ar','cr_number','mol_establishment_no','sector','country','currency','address','is_active'];
    when 'location' then tbl := 'locations';
      cols := array['entity_id','code','name_en','name_ar','location_type','address','city','governorate','is_active'];
    when 'cost_centre' then tbl := 'cost_centres';
      cols := array['entity_id','code','name_en','name_ar','gl_code','is_active'];
    when 'department' then tbl := 'departments';
      cols := array['entity_id','code','name_en','name_ar','parent_id','cost_centre_id','head_employee_id','aliases','is_active'];
    when 'grade' then tbl := 'grades';
      cols := array['entity_id','code','name_en','name_ar','level','min_basic','max_basic','is_active'];
    when 'job_title' then tbl := 'job_titles';
      cols := array['entity_id','code','name_en','name_ar','profession_code','omani_only','omani_only_source',
                    'omani_only_verified','description','required_qualifications','aliases','is_active'];
    when 'category' then tbl := 'employee_categories';
      cols := array['entity_id','code','name_en','name_ar','pay_basis','counts_for_omanisation','is_active'];
    when 'document_type' then tbl := 'document_types'; keycol := 'code'; has_entity := false;
      cols := array['code','name_en','name_ar','category','has_number','has_expiry','alert_days','applies_to',
                    'is_mandatory','allow_multiple','is_sensitive','rule_basis','rule_reference','sort','is_active'];
    else raise exception 'INVALID: Unknown master %.', p_kind;
  end case;
end $$;

-- "Jr. Supervisor", "JR SUPERVISOR" and "jr.supervisor" are the same key.
create or replace function hr.match_key(p text)
returns text language sql immutable set search_path = '' as $$
  select nullif(upper(regexp_replace(coalesce(p, ''), '[^[:alnum:]]+', '', 'g')), '')
$$;

create or replace function hr.master_id(p_table text, p_entity uuid, p_code text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v uuid; v_key text := hr.match_key(p_code);
begin
  if v_key is null then return null; end if;
  -- an exact code always wins
  execute format('select id from hr.%I where entity_id = $1 and upper(code) = upper($2) limit 1', p_table) into v using p_entity, btrim(p_code);
  if v is null then
    if p_table in ('departments', 'job_titles') then
      execute format('select id from hr.%I where entity_id = $1 and is_active and (hr.match_key(code) = $2 or hr.match_key(name_en) = $2
                        or hr.match_key(name_ar) = $2 or exists (select 1 from unnest(aliases) a where hr.match_key(a) = $2)) order by code limit 1', p_table)
        into v using p_entity, v_key;
    else
      execute format('select id from hr.%I where entity_id = $1 and is_active and (hr.match_key(code) = $2 or hr.match_key(name_en) = $2
                        or hr.match_key(name_ar) = $2) order by code limit 1', p_table)
        into v using p_entity, v_key;
    end if;
  end if;
  if v is null then raise exception 'Unknown % "%".', replace(rtrim(p_table, 's'), '_', ' '), p_code; end if;
  return v;
end $$;

-- "472" → "AACT-0472" (prefix and digits from Settings); anything else is kept as written.
create or replace function hr.norm_employee_no(p text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v text := upper(btrim(coalesce(p, ''))); v_prefix text; v_digits int;
begin
  if v = '' then return null; end if;
  if v ~ '^[0-9]+(\.0+)?$' then
    select value #>> '{}' into v_prefix from hr.settings where key = 'employee_no_prefix';
    select (value #>> '{}')::int into v_digits from hr.settings where key = 'employee_no_digits';
    v := split_part(v, '.', 1);
    v := coalesce(v_prefix, '') || lpad(ltrim(v, '0'), greatest(coalesce(v_digits, 5), length(ltrim(v, '0'))), '0');
  end if;
  return v;
end $$;

create or replace function hr.employee_by_no(p_no text, p_label text)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v uuid;
begin
  if p_no is null or btrim(p_no) = '' then return null; end if;
  select id into v from hr.employees where upper(employee_no) = upper(btrim(p_no));
  if v is null then
    select id into v from hr.employees where upper(employee_no) = hr.norm_employee_no(p_no);
  end if;
  if v is null then raise exception 'Unknown %employee number "%".', p_label, p_no; end if;
  return v;
end $$;

-- The next automatic number continues after the highest number already used with the company prefix.
create or replace function hr.next_employee_no()
returns text language plpgsql security definer set search_path = '' as $$
declare v_prefix text; v_digits int; v_no text; v_max bigint; v_n bigint;
begin
  select value #>> '{}' into v_prefix from hr.settings where key = 'employee_no_prefix';
  select (value #>> '{}')::int into v_digits from hr.settings where key = 'employee_no_digits';
  v_prefix := coalesce(v_prefix, '');
  select max(substr(employee_no, length(v_prefix) + 1)::bigint) into v_max
    from hr.employees
   where left(employee_no, length(v_prefix)) = v_prefix and substr(employee_no, length(v_prefix) + 1) ~ '^[0-9]{1,15}$';
  loop
    v_n := nextval('hr.employee_no_seq');
    if v_max is not null and v_n <= v_max then
      perform setval('hr.employee_no_seq', v_max + 1, false);
      v_n := nextval('hr.employee_no_seq');
    end if;
    v_no := v_prefix || lpad(v_n::text, coalesce(v_digits, 5), '0');
    exit when not exists (select 1 from hr.employees where employee_no = v_no);
  end loop;
  return v_no;
end $$;

-- Day-first dates as typed in Oman: 12.05.1998, 12/05/1998, 12-05-1998, 12.05-1998. ISO dates pass through.
create or replace function hr.norm_date(p text)
returns text language plpgsql immutable set search_path = '' as $$
declare v text := btrim(coalesce(p, '')); m text[]; d date;
begin
  if v = '' then return null; end if;
  if v ~ '^\d{4}-\d{2}-\d{2}$' then return v; end if;
  m := regexp_match(v, '^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$');
  if m is null then
    m := regexp_match(v, '^(\d{4})-(\d{1,2})-(\d{1,2})');
    if m is null then raise exception 'Date "%" is not in a known format (use DD/MM/YYYY).', v; end if;
    m := array[m[3], m[2], m[1]];
  end if;
  begin
    d := make_date(m[3]::int, m[2]::int, m[1]::int);
  exception when others then
    raise exception 'Date "%" does not exist.', v;
  end;
  return to_char(d, 'YYYY-MM-DD');
end $$;

create or replace function hr.norm_nationality(p text)
returns text language sql immutable set search_path = '' as $$
  select case when upper(btrim(coalesce(p, ''))) in ('OMANI', 'OMANIS', 'OMAN') then 'OM' else nullif(upper(btrim(coalesce(p, ''))), '') end
$$;

-- Rows are objects keyed by column heading. A dry run checks every row and undoes everything.
create or replace function public.hr_import(p_kind text, p_rows jsonb, p_dry_run boolean default true, p_file_name text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_kind text := upper(coalesce(p_kind,'')); r jsonb; i int := 0; v_ok int := 0; v_res jsonb := '[]'::jsonb; v_out jsonb; v_emp uuid; v_ent uuid;
        v_p jsonb; k text; v_lines jsonb; v_batch uuid; v_skip text[] := array['employee_no','effective_from','notes','reason'];
        v_pg text; v_cat uuid;
begin
  perform hr.require_perm('DATA_IMPORT');
  if v_kind not in ('EMPLOYEES','DOCUMENTS','SALARIES') then raise exception 'INVALID: Unknown import type.'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'REQUIRED: The file has no rows.'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'INVALID: At most 2000 rows at a time.'; end if;
  begin
    for r in select * from jsonb_array_elements(p_rows) loop
      i := i + 1;
      begin
        if v_kind = 'EMPLOYEES' then
          v_ent := coalesce((select id from hr.legal_entities where upper(code) = upper(hr.jtext(r,'company_code'))),
                            (select id from hr.legal_entities where is_active order by created_at limit 1));
          if hr.jtext(r,'company_code') is not null and not exists (select 1 from hr.legal_entities where upper(code) = upper(hr.jtext(r,'company_code'))) then
            raise exception 'Unknown company code "%".', hr.jtext(r,'company_code');
          end if;
          v_cat := hr.master_id('employee_categories', v_ent, coalesce(hr.jtext(r,'category_code'), hr.jtext(r,'category')));
          v_pg := upper(hr.jtext(r,'pay_group'));
          if v_pg is null and v_cat is not null then
            v_pg := case when (select upper(code) from hr.employee_categories where id = v_cat) = 'MG' then 'MG' end;
          end if;
          if v_pg is not null and v_pg not in ('MG','NMG') then raise exception 'Pay group must be MG or NMG.'; end if;
          if v_pg = 'MG' and not hr.has_perm('MG_PAY') then
            raise exception 'Only the management payroll team can import management (MG) staff.';
          end if;
          v_p := jsonb_strip_nulls(jsonb_build_object('entity_id', v_ent, 'employee_no', hr.norm_employee_no(hr.jtext(r,'employee_no')),
            'full_name_en', hr.jtext(r,'full_name_en'),
            'full_name_ar', hr.jtext(r,'full_name_ar'), 'nationality', hr.norm_nationality(hr.jtext(r,'nationality')), 'gender', upper(hr.jtext(r,'gender')),
            'date_of_birth', hr.norm_date(hr.jtext(r,'date_of_birth')), 'marital_status', upper(hr.jtext(r,'marital_status')), 'civil_number', hr.jtext(r,'civil_number'),
            'mobile', hr.jtext(r,'mobile'), 'personal_email', hr.jtext(r,'personal_email'), 'work_email', hr.jtext(r,'work_email'),
            'join_date', hr.norm_date(hr.jtext(r,'join_date')), 'probation_end_date', hr.norm_date(hr.jtext(r,'probation_end_date')),
            'exception_reason', hr.jtext(r,'exception_reason'),
            'confirm_duplicate', hr.jbool(r,'confirm_duplicate'),
            'assignment', jsonb_strip_nulls(jsonb_build_object(
              'department_id', hr.master_id('departments', v_ent, coalesce(hr.jtext(r,'department_code'), hr.jtext(r,'department'))),
              'job_title_id', hr.master_id('job_titles', v_ent, coalesce(hr.jtext(r,'job_code'), hr.jtext(r,'designation'), hr.jtext(r,'job_title'))),
              'grade_id', hr.master_id('grades', v_ent, hr.jtext(r,'grade_code')),
              'category_id', v_cat,
              'location_id', hr.master_id('locations', v_ent, hr.jtext(r,'location_code')),
              'manager_id', hr.employee_by_no(hr.jtext(r,'manager_employee_no'), 'manager '),
              'employment_type', upper(hr.jtext(r,'employment_type')), 'shift_code', hr.jtext(r,'shift_code')))));
          v_out := public.hr_save_employee(v_p);
          if v_pg = 'MG' then
            perform public.hr_set_pay_group((v_out->'employee'->>'id')::uuid, 'MG', 'Imported from the management staff list');
          end if;
          v_res := v_res || jsonb_build_array(jsonb_build_object('row', i, 'ok', true, 'key', v_out->'employee'->>'employee_no', 'id', v_out->'employee'->>'id'));
        else
          if hr.jtext(r,'employee_no') is null then raise exception 'The employee number is blank.'; end if;
          v_emp := hr.employee_by_no(hr.jtext(r,'employee_no'), '');
          if v_kind = 'DOCUMENTS' then
            v_out := public.hr_save_document(v_emp, jsonb_strip_nulls(jsonb_build_object('doc_type', upper(hr.jtext(r,'doc_type')), 'doc_number', hr.jtext(r,'doc_number'),
              'issue_date', hr.norm_date(hr.jtext(r,'issue_date')), 'expiry_date', hr.norm_date(hr.jtext(r,'expiry_date')), 'issuing_authority', hr.jtext(r,'issuing_authority'),
              'issue_place', hr.jtext(r,'issue_place'), 'notes', coalesce(hr.jtext(r,'notes'), 'Imported'))));
          else
            v_lines := '[]'::jsonb;
            for k in select key from jsonb_each(r) loop
              continue when lower(k) = any(v_skip) or nullif(btrim(r->>k), '') is null;
              continue when upper(k) in ('GROSS', 'GROSS_SALARY', 'NAME', 'EMP_NAME', 'FULL_NAME_EN', 'TOTAL');
              v_lines := v_lines || jsonb_build_array(jsonb_build_object('component_code', upper(k), 'amount', r->>k));
            end loop;
            v_out := public.hr_propose_compensation(v_emp, jsonb_build_object('effective_from', coalesce(hr.norm_date(hr.jtext(r,'effective_from')),
                       (select join_date::text from hr.employees where id = v_emp)), 'reason', coalesce(upper(hr.jtext(r,'reason')), 'JOIN'),
                       'notes', coalesce(hr.jtext(r,'notes'), 'Imported opening salary'), 'lines', v_lines));
          end if;
          v_res := v_res || jsonb_build_array(jsonb_build_object('row', i, 'ok', true, 'key', hr.jtext(r,'employee_no')));
        end if;
        v_ok := v_ok + 1;
      exception when others then
        v_res := v_res || jsonb_build_array(jsonb_build_object('row', i, 'ok', false, 'key', coalesce(hr.jtext(r,'employee_no'), hr.jtext(r,'full_name_en')),
                   'message', regexp_replace(sqlerrm, '^[A-Z_]+:\s*', '')));
      end;
    end loop;
    if coalesce(p_dry_run, true) then raise exception 'HR_IMPORT_DRY_RUN'; end if;
  exception when others then
    if sqlerrm <> 'HR_IMPORT_DRY_RUN' then raise; end if;
  end;
  insert into hr.import_batches(kind, file_name, dry_run, rows_total, rows_ok, rows_failed, results, created_by)
  values (v_kind, p_file_name, coalesce(p_dry_run, true), i, v_ok, i - v_ok, v_res, auth.uid()) returning id into v_batch;
  return jsonb_build_object('batch_id', v_batch, 'dry_run', coalesce(p_dry_run, true), 'total', i, 'ok', v_ok, 'failed', i - v_ok, 'results', v_res);
end $$;

-- Payroll set-up: component names can be corrected and components switched off (never the basic salary).
create or replace function public.hr_save_payroll_setup(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x jsonb; k text; c hr.pay_components;
begin
  perform hr.require_perm('PAY_APPROVE');
  for x in select * from jsonb_array_elements(coalesce(p->'entities', '[]'::jsonb)) loop
    update hr.legal_entities set cr_number = coalesce(hr.jtext(x,'cr_number'), cr_number),
           spf_employer_no = hr.jtext(x,'spf_employer_no'), wps_bank_code = upper(hr.jtext(x,'wps_bank_code')),
           wps_account = hr.jtext(x,'wps_account'), wps_payer_cr = hr.jtext(x,'wps_payer_cr')
     where id = hr.juuid(x,'id');
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p->'components', '[]'::jsonb)) loop
    select * into c from hr.pay_components where code = hr.jtext(x,'code');
    continue when c.code is null;
    if x ? 'name_en' and hr.jtext(x,'name_en') is null then raise exception 'REQUIRED: Every component needs an English name (%).', c.code; end if;
    if x ? 'name_ar' and hr.jtext(x,'name_ar') is null then raise exception 'REQUIRED: Every component needs an Arabic name (%).', c.code; end if;
    if c.is_basic and x ? 'is_active' and not hr.jbool(x,'is_active', true) then
      raise exception 'INVALID: The basic salary component cannot be switched off.';
    end if;
    update hr.pay_components set gl_account = hr.jtext(x,'gl_account'),
           spf_base = case when x ? 'spf_base' then hr.jbool(x,'spf_base', true) else spf_base end,
           name_en  = case when x ? 'name_en' then hr.jtext(x,'name_en') else name_en end,
           name_ar  = case when x ? 'name_ar' then hr.jtext(x,'name_ar') else name_ar end,
           is_active = case when x ? 'is_active' then hr.jbool(x,'is_active', true) else is_active end
     where code = c.code;
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

select hr.attach_audit();
select hr.secure_api();
