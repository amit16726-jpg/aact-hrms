-- AACT HRMS — hardening after Supabase advisor review (20 Oct 2026)
-- Idempotent; no destructive statements.

-- 1. Supabase's own RLS auto-enable event-trigger function: not an API function.
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'rls_auto_enable') then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;

-- 2. Covering indexes for foreign keys (advisor 0001).
create index if not exists compensation_lines_component_idx  on hr.compensation_lines (component_code);
create index if not exists compensation_lines_employee_idx   on hr.compensation_lines (employee_id);
create index if not exists departments_cost_centre_idx       on hr.departments (cost_centre_id);
create index if not exists departments_head_idx              on hr.departments (head_employee_id);
create index if not exists employee_assignments_category_idx on hr.employee_assignments (category_id);
create index if not exists employee_assignments_cc_idx       on hr.employee_assignments (cost_centre_id);
create index if not exists employee_assignments_dept_idx     on hr.employee_assignments (department_id);
create index if not exists employee_assignments_exc_idx      on hr.employee_assignments (omanisation_exception_id);
create index if not exists employee_assignments_grade_idx    on hr.employee_assignments (grade_id);
create index if not exists employee_assignments_job_idx      on hr.employee_assignments (job_title_id);
create index if not exists employee_assignments_loc_idx      on hr.employee_assignments (location_id);
create index if not exists employee_contracts_document_idx   on hr.employee_contracts (document_id);
create index if not exists employee_contracts_supersedes_idx on hr.employee_contracts (supersedes_id);
create index if not exists employee_documents_type_idx       on hr.employee_documents (doc_type);
create index if not exists employee_documents_supersedes_idx on hr.employee_documents (supersedes_id);
create index if not exists employees_address_country_idx     on hr.employees (address_country);
create index if not exists employees_nationality_idx         on hr.employees (nationality);
create index if not exists legal_entities_country_idx        on hr.legal_entities (country);
create index if not exists omanisation_exceptions_emp_idx    on hr.omanisation_exceptions (employee_id);
create index if not exists omanisation_exceptions_job_idx    on hr.omanisation_exceptions (job_title_id);
create index if not exists role_permissions_perm_idx         on hr.role_permissions (perm_code);
create index if not exists user_roles_role_idx               on hr.user_roles (role_code);
