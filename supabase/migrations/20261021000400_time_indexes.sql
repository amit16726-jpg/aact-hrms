-- AACT HRMS — 013 Phase 2 hardening: indexes on the remaining foreign keys (Supabase performance advisor).
create index if not exists holidays_entity on hr.holidays(entity_id);
create index if not exists punch_batches_entity on hr.punch_batches(entity_id);
