import { supabase, DOC_BUCKET } from './supabase';
import { parseError } from './errors';

export type Json = Record<string, unknown>;

export async function rpc<T>(fn: string, args: Json = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw parseError(error);
  return data as T;
}

// ---------------------------------------------------------------------------
// Types returned by the server
// ---------------------------------------------------------------------------
export type Lang = 'en' | 'ar';

export interface Entity { id: string; code: string; name_en: string; name_ar: string | null }

export interface Me {
  user_id: string; email: string; display_name: string | null; language: Lang; is_active: boolean;
  employee_id: string | null; employee_no: string | null; employee_name: string | null; employee_name_ar: string | null;
  roles: string[]; permissions: string[]; is_manager: boolean; admin_exists: boolean;
  settings: Record<string, unknown>; entities: Entity[]; unread_notifications: number;
}

export interface Named { id: string; code: string; name_en: string; name_ar: string | null; is_active: boolean; entity_id?: string }

export interface Assignment {
  id: string; employee_id: string; effective_from: string; effective_to: string | null;
  department_id: string; job_title_id: string; grade_id: string | null; category_id: string; location_id: string | null;
  cost_centre_id: string | null; manager_id: string | null; employment_type: string; shift_code: string | null;
  reason: string; notes: string | null; omanisation_exception_id: string | null;
  department_en: string | null; department_ar: string | null; job_title_en: string | null; job_title_ar: string | null;
  grade_en: string | null; grade_ar: string | null; grade_code: string | null; category_en: string | null; category_ar: string | null;
  location_en: string | null; location_ar: string | null; cost_centre_en: string | null; cost_centre_ar: string | null;
  manager_name_en: string | null; manager_name_ar: string | null; manager_no: string | null;
  profession_code: string | null; omani_only: boolean | null; created_by_name: string | null;
}

export interface Employee {
  id: string; entity_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null;
  preferred_name: string | null; date_of_birth?: string | null; gender: 'M' | 'F' | null; nationality: string;
  nationality_en?: string; nationality_ar?: string; marital_status?: string | null; civil_number?: string | null;
  personal_email?: string | null; work_email: string | null; mobile: string | null; alt_phone?: string | null;
  address_line?: string | null; city?: string | null; wilayat?: string | null; governorate?: string | null;
  address_country?: string | null; photo_path: string | null; original_join_date?: string; join_date: string;
  probation_end_date: string | null; confirmation_date: string | null; status: EmployeeStatus;
  notice_given_date?: string | null; last_working_date?: string | null; separation_date?: string | null;
  separation_type?: string | null; separation_reason?: string | null; is_omani: boolean;
  entity_en?: string; entity_ar?: string | null;
}

export type EmployeeStatus = 'PROBATION' | 'ACTIVE' | 'NOTICE' | 'SUSPENDED' | 'SEPARATED';

export interface Contract {
  id: string; contract_no: string | null; contract_type: 'FIXED_TERM' | 'INDEFINITE'; start_date: string; end_date: string | null;
  probation_days: number | null; notice_days: number | null; working_hours_per_week: number | null;
  mol_registration_no: string | null; version: number; status: string; document_id: string | null; notes: string | null;
  created_at: string; created_by_name: string | null;
}

export interface EmergencyContact {
  id: string; name: string; relationship: string; phone: string; alt_phone: string | null; address: string | null; is_next_of_kin: boolean;
}

export interface EmployeeEvent {
  id: string; event_type: string; event_date: string; details: Record<string, unknown>; created_at: string; created_by_name: string | null;
}

export interface OmanisationException {
  id: string; job_title_en: string; job_title_ar: string | null; reason: string; status: string; valid_to: string | null;
  approved_by_name: string | null; approved_at: string;
}

export interface Caps {
  edit: boolean; salary_read: boolean; salary_write: boolean; salary_approve: boolean; bank_read: boolean; bank_write: boolean;
  bank_approve: boolean; docs_read: boolean; docs_write: boolean; docs_sensitive: boolean; history: boolean; exception_approve: boolean;
}

export interface EmployeeFile {
  employee: Employee; access: 'FULL' | 'SELF' | 'TEAM'; current_assignment: Assignment | null; assignments: Assignment[];
  contracts: Contract[]; emergency_contacts: EmergencyContact[]; events: EmployeeEvent[];
  omanisation_exceptions: OmanisationException[]; linked_user: { user_id: string; email: string; is_active: boolean } | null;
  caps: Caps;
}

export interface EmployeeRow {
  id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; nationality: string; is_omani: boolean;
  nationality_en: string | null; nationality_ar: string | null; status: EmployeeStatus; join_date: string;
  department_en: string | null; department_ar: string | null; job_title_en: string | null; job_title_ar: string | null;
  location_en: string | null; location_ar: string | null; manager_en: string | null; manager_ar: string | null;
  mobile: string | null; work_email: string | null; photo_path: string | null; access: string;
}

export interface PayLine { component_code: string; amount: number; name_en: string; name_ar: string; kind: 'EARNING' | 'DEDUCTION' }
export interface Revision {
  id: string; employee_id: string; effective_from: string; reason: string; status: string; total_monthly: number; notes: string | null;
  proposed_by_name: string | null; proposed_at: string; decided_by_name: string | null; decided_at: string | null;
  decision_note: string | null; lines: PayLine[];
}
export interface Compensation {
  current: Revision | null; scheduled: Revision[]; pending: Revision | null; history: Revision[];
  grade: { code: string; name_en: string; name_ar: string | null; min_basic: number | null; max_basic: number | null } | null;
  access: 'FULL' | 'SELF';
}
export interface PayComponent { code: string; name_en: string; name_ar: string; kind: 'EARNING' | 'DEDUCTION'; is_basic: boolean; sort: number }

export interface BankAccount {
  id: string; bank_name: string; branch: string | null; account_name: string; account_number: string; iban: string | null;
  swift_code: string | null; effective_from: string; status: string; masked: boolean; requested_by_name: string | null;
  requested_at: string; decided_by_name: string | null; decided_at: string | null; decision_note: string | null;
}
export interface Bank { current: BankAccount | null; pending: BankAccount | null; history: BankAccount[] }

export interface DocType {
  code: string; name_en: string; name_ar: string; category: string; has_number: boolean; has_expiry: boolean;
  alert_days: number[]; applies_to: 'ALL' | 'OMANI' | 'EXPAT'; is_mandatory: boolean; allow_multiple: boolean;
  is_sensitive: boolean; rule_basis: string; rule_reference: string | null; sort: number; is_active: boolean;
}
export interface EmpDocument {
  id: string; employee_id: string; doc_type: string; doc_number: string | null; title: string | null; issue_date: string | null;
  expiry_date: string | null; issuing_authority: string | null; issue_place: string | null; version: number; is_current: boolean;
  status: 'ACTIVE' | 'SUPERSEDED' | 'CANCELLED'; file_path: string | null; file_name: string | null; mime_type: string | null;
  file_size: number | null; verified_at: string | null; verified_by_name: string | null; uploaded_by_name: string | null;
  cancel_reason: string | null; notes: string | null; created_at: string; name_en: string; name_ar: string; category: string;
  is_sensitive: boolean; has_expiry: boolean; days_left: number | null; bucket: string | null; supersedes_id: string | null;
}
export interface ChecklistItem { doc_type: string; name_en: string; name_ar: string; status: 'MISSING' | 'EXPIRED' | 'EXPIRING' | 'OK'; expiry_date: string | null }
export interface EmpDocuments { documents: EmpDocument[]; checklist: ChecklistItem[]; scope: 'ALL' | 'NON_SENSITIVE' }

export interface ExpiryRow {
  employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; nationality: string;
  entity_id: string; department_id: string | null; department_en: string | null; department_ar: string | null;
  source: 'DOCUMENT' | 'CONTRACT'; ref_id: string; doc_type: string; name_en: string; name_ar: string;
  doc_number: string | null; expiry_date: string; days_left: number; bucket: string; is_sensitive: boolean;
}
export interface MissingRow {
  employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; nationality: string;
  status: string; join_date: string; department_en: string | null; department_ar: string | null; doc_type: string; name_en: string; name_ar: string;
}

export interface OmanRow {
  total: number; omani: number; expat: number; pct: number | null; target_pct: number | null; target_id: string | null;
  target_source: string | null; rule_basis: string | null; omanis_needed: number | null; meets_target: boolean | null;
}
export interface Omanisation {
  entity_id: string; as_of: string; overall: OmanRow;
  by_department: (OmanRow & { id: string; code: string; name_en: string; name_ar: string | null })[];
  by_job_title: (OmanRow & { id: string; code: string; name_en: string; name_ar: string | null; profession_code: string | null; omani_only: boolean })[];
  by_profession: (OmanRow & { profession_code: string })[];
  omani_only_placements: { employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; nationality: string;
    job_title_en: string; job_title_ar: string | null; exception_id: string | null; exception_reason: string | null; exception_status: string | null }[];
  counting_basis: string;
}
export interface Target {
  id: string; entity_id: string; scope_type: 'ENTITY' | 'DEPARTMENT' | 'JOB_TITLE' | 'PROFESSION_CODE'; scope_id: string | null;
  profession_code: string | null; target_pct: number; effective_from: string; effective_to: string | null;
  rule_basis: 'LEGAL' | 'COMPANY_POLICY'; source_reference: string; notes: string | null; status: string;
  proposed_by_name: string | null; proposed_at: string; decided_by_name: string | null; decided_at: string | null;
  decision_note: string | null; scope_name_en: string | null; scope_name_ar: string | null; can_decide: boolean;
}

export interface Notification {
  id: string; kind: string; priority: 'NORMAL' | 'HIGH'; title_en: string; title_ar: string; body_en: string | null;
  body_ar: string | null; link: string | null; created_at: string; read_at: string | null;
}

export interface UserRow {
  user_id: string; email: string; display_name: string | null; is_active: boolean; language: Lang; created_at: string;
  employee_id: string | null; employee_no: string | null; employee_name: string | null; roles: string[];
}
export interface RoleDef { code: string; name_en: string; name_ar: string; description: string | null; permissions: string[] }
export interface PermDef { code: string; module: string; description: string }

export interface AuditRow {
  id: number; at: string; user_id: string | null; user_name: string | null; table_name: string; row_key: string | null;
  employee_id: string | null; employee_no: string | null; full_name_en: string | null; action: string;
  old_data: Record<string, unknown> | null; new_data: Record<string, unknown> | null;
}
export interface AccessRow { id: number; at: string; user_name: string | null; employee_no: string | null; full_name_en: string | null; data_kind: string; detail: string | null }

export interface Pending {
  salary: { id: string; employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; effective_from: string;
    reason: string; total_monthly: number; proposed_by_name: string; proposed_at: string; can_decide: boolean }[];
  bank: { id: string; employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; bank_name: string;
    account_number: string; requested_by_name: string; requested_at: string; can_decide: boolean }[];
  targets: { id: string; entity_id: string; scope_type: string; target_pct: number; effective_from: string; source_reference: string;
    proposed_by_name: string; proposed_at: string; can_decide: boolean }[];
}

export interface Country { code: string; name_en: string; name_ar: string; nationality_en: string; nationality_ar: string }

// ---------------------------------------------------------------------------
// Calls
// ---------------------------------------------------------------------------
export const api = {
  me: () => rpc<Me>('hr_me'),
  claimFirstAdmin: () => rpc<Me>('hr_claim_first_admin'),
  setMyProfile: (p: Json) => rpc<Me>('hr_set_my_profile', { p }),

  listRoles: () => rpc<{ roles: RoleDef[]; permissions: PermDef[] }>('hr_list_roles'),
  listUsers: () => rpc<UserRow[]>('hr_list_users'),
  setUserRoles: (userId: string, roles: string[]) => rpc<UserRow[]>('hr_set_user_roles', { p_user: userId, p_roles: roles }),
  setUserActive: (userId: string, active: boolean) => rpc<UserRow[]>('hr_set_user_active', { p_user: userId, p_active: active }),
  linkUserEmployee: (userId: string, employeeId: string | null) =>
    rpc<UserRow[]>('hr_link_user_employee', { p_user: userId, p_employee: employeeId }),
  saveSetting: (key: string, value: unknown) => rpc<Record<string, unknown>>('hr_save_setting', { p_key: key, p_value: value }),

  listMaster: <T = Named>(kind: string, entityId?: string | null) =>
    rpc<T[]>('hr_list_master', { p_kind: kind, p_entity: entityId ?? null }),
  saveMaster: <T = Named>(kind: string, row: Json) => rpc<T>('hr_save_master', { p_kind: kind, p_row: row }),
  listCountries: () => rpc<Country[]>('hr_list_countries'),
  listPayComponents: () => rpc<PayComponent[]>('hr_list_pay_components'),

  listEmployees: (p: Json) => rpc<{ total: number; rows: EmployeeRow[] }>('hr_list_employees', { p }),
  employeeLookup: (search: string) =>
    rpc<{ id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; status: string; entity_id: string }[]>(
      'hr_employee_lookup', { p_search: search, p_limit: 20 }),
  getEmployee: (id: string) => rpc<EmployeeFile>('hr_get_employee', { p_id: id }),
  saveEmployee: (p: Json) => rpc<EmployeeFile>('hr_save_employee', { p }),
  setPhoto: (id: string, path: string | null) => rpc<EmployeeFile>('hr_set_employee_photo', { p_employee: id, p_path: path }),
  addAssignment: (id: string, p: Json) => rpc<EmployeeFile>('hr_add_assignment', { p_employee: id, p }),
  changeStatus: (id: string, p: Json) => rpc<EmployeeFile>('hr_change_status', { p_employee: id, p }),
  saveContract: (id: string, p: Json) => rpc<EmployeeFile>('hr_save_contract', { p_employee: id, p }),
  saveEmergencyContact: (id: string, p: Json) => rpc<EmployeeFile>('hr_save_emergency_contact', { p_employee: id, p }),
  removeEmergencyContact: (contactId: string) => rpc<EmployeeFile>('hr_remove_emergency_contact', { p_id: contactId }),

  getCompensation: (id: string) => rpc<Compensation>('hr_get_compensation', { p_employee: id }),
  proposeCompensation: (id: string, p: Json) =>
    rpc<{ revision_id: string; warnings: { code: string; message: string }[]; compensation: Compensation }>(
      'hr_propose_compensation', { p_employee: id, p }),
  decideCompensation: (revId: string, approve: boolean, note: string | null) =>
    rpc<Compensation>('hr_decide_compensation', { p_revision: revId, p_approve: approve, p_note: note }),
  withdrawCompensation: (revId: string) => rpc<Compensation>('hr_withdraw_compensation', { p_revision: revId }),
  pendingApprovals: () => rpc<Pending>('hr_list_pending_approvals'),

  getBank: (id: string) => rpc<Bank>('hr_get_bank', { p_employee: id }),
  requestBankChange: (id: string, p: Json) => rpc<Bank>('hr_request_bank_change', { p_employee: id, p }),
  decideBank: (bankId: string, approve: boolean, note: string | null) =>
    rpc<Bank>('hr_decide_bank', { p_id: bankId, p_approve: approve, p_note: note }),

  listDocuments: (id: string, history: boolean) =>
    rpc<EmpDocuments>('hr_list_employee_documents', { p_employee: id, p_include_history: history }),
  saveDocument: (id: string, p: Json) => rpc<EmpDocument>('hr_save_document', { p_employee: id, p }),
  cancelDocument: (docId: string, reason: string) => rpc<EmpDocument>('hr_cancel_document', { p_id: docId, p_reason: reason }),
  verifyDocument: (docId: string) => rpc<EmpDocument>('hr_verify_document', { p_id: docId }),
  documentFile: (docId: string) => rpc<{ file_path: string; file_name: string | null; mime_type: string | null }>('hr_document_file', { p_id: docId }),

  listExpiries: (p: Json) => rpc<ExpiryRow[]>('hr_list_expiries', { p }),
  listMissing: (p: Json) => rpc<MissingRow[]>('hr_list_missing_documents', { p }),
  getOmanisation: (entityId: string, asOf: string | null) =>
    rpc<Omanisation>('hr_get_omanisation', { p_entity: entityId, p_as_of: asOf }),
  listTargets: (entityId: string | null) => rpc<Target[]>('hr_list_omanisation_targets', { p_entity: entityId }),
  proposeTarget: (p: Json) => rpc<Target[]>('hr_propose_omanisation_target', { p }),
  decideTarget: (id: string, approve: boolean, note: string | null) =>
    rpc<Target[]>('hr_decide_omanisation_target', { p_id: id, p_approve: approve, p_note: note }),
  retireTarget: (id: string, to: string | null, note: string) =>
    rpc<Target[]>('hr_retire_omanisation_target', { p_id: id, p_to: to, p_note: note }),
  revokeException: (id: string, note: string) => rpc<EmployeeFile>('hr_revoke_omanisation_exception', { p_id: id, p_note: note }),

  dashboard: () => rpc<Dashboard>('hr_dashboard'),
  listNotifications: (unreadOnly = false) =>
    rpc<{ unread: number; rows: Notification[] }>('hr_list_notifications', { p_unread_only: unreadOnly, p_limit: 50 }),
  markRead: (ids: string[] | null) => rpc<{ unread: number; rows: Notification[] }>('hr_mark_notifications_read', { p_ids: ids }),
  runExpiryScan: () => rpc<{ created: number }>('hr_run_expiry_scan'),

  listAudit: (p: Json) => rpc<{ total: number; rows: AuditRow[] }>('hr_list_audit', { p }),
  listAccessLog: (p: Json) => rpc<AccessRow[]>('hr_list_access_log', { p }),
};

export interface Dashboard {
  workforce?: { headcount: number; omani: number; expat: number; probation: number; notice: number; suspended: number;
    joiners_30: number; leavers_30: number; probation_due_30: number };
  by_department?: { department_id: string; name_en: string; name_ar: string | null; total: number; omani: number }[];
  by_nationality?: { code: string; name_en: string; name_ar: string; total: number }[];
  probation_due?: { id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; probation_end_date: string }[];
  compliance?: { expired: number; d30: number; d60: number; d90: number; missing: number; employees_missing: number };
  expiring_soon?: ExpiryRow[];
  omanisation?: (OmanRow & { entity_id: string; code: string; name_en: string; name_ar: string | null })[];
  approvals: { salary: number; bank: number; targets: number };
  me?: { employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null; status: string; join_date: string;
    assignment: Assignment | null; my_expiries: ExpiryRow[]; team_size: number; team_expiries: ExpiryRow[] };
}

// ---------------------------------------------------------------------------
// Files (private bucket; path = <employee_id>/<DOC_TYPE|PHOTO>/<random>.<ext>)
// ---------------------------------------------------------------------------
export const ALLOWED_MIME = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'];
export const MAX_FILE_BYTES = 10 * 1024 * 1024;

export function checkFile(f: File): string | null {
  if (!ALLOWED_MIME.includes(f.type)) return 'FILE_TYPE';
  if (f.size > MAX_FILE_BYTES) return 'FILE_SIZE';
  return null;
}

function extOf(f: File): string {
  const fromName = /\.([a-z0-9]{2,5})$/i.exec(f.name)?.[1]?.toLowerCase();
  if (fromName) return fromName;
  return f.type === 'application/pdf' ? 'pdf' : f.type.split('/')[1] ?? 'bin';
}

export function buildPath(employeeId: string, folder: string, f: File): string {
  const rand = crypto.randomUUID();
  return `${employeeId}/${folder}/${rand}.${extOf(f)}`;
}

export async function uploadFile(employeeId: string, folder: string, f: File): Promise<string> {
  const path = buildPath(employeeId, folder, f);
  const { error } = await supabase.storage.from(DOC_BUCKET).upload(path, f, { contentType: f.type, upsert: false });
  if (error) throw parseError(error);
  return path;
}

export async function signedUrl(path: string, seconds = 120): Promise<string> {
  const { data, error } = await supabase.storage.from(DOC_BUCKET).createSignedUrl(path, seconds);
  if (error) throw parseError(error);
  return data.signedUrl;
}
