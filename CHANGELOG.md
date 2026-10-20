# Changelog

## 1.0.1 — 20 Oct 2026 — live install

- Installed on the live Supabase project; full test suite passed on live and rolled back.
- Hardening migration `20261020001000_hardening.sql`: indexes on 22 foreign keys; Supabase's `rls_auto_enable` helper closed to API roles.

## 1.0.0 — 20 Oct 2026 — Priority 1: HR foundation

- **Organisation masters:**
  - companies, locations, cost centres and departments;
  - grades with salary bands;
  - job titles with Ministry profession code and Omani-only flag;
  - employee categories;
  - document types.
- **Employee master** in English and Arabic, with duplicate checks and automatic numbering.
- **Effective-dated job history** (transfer, promotion, correction) and lifecycle actions: confirm, notice, suspend, separate, rehire.
- **Contracts** with versions.
- **Salary structure and bank account**, each proposed by one person and approved by another.
- **Documents:**
  - versions, renewal and second-person verification;
  - cancellation with a reason;
  - mandatory checklist;
  - private file storage.
- **Expiry tracker and reminders:**
  - expired / 30 / 60 / 90 days for documents and contracts;
  - daily scan;
  - missing-documents report.
- **Omanisation:**
  - ratios by company, department, job and profession code;
  - targets with source and maker-checker;
  - Omani-only exceptions;
  - what-if planner.
- **Dashboards** for HR, line managers and employees.
- **Administration:** users and roles, settings, audit trail and sensitive-data access log.
