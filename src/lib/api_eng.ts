import { rpc, type Json } from './api';
import { ApiError, parseError } from './errors';
import { supabase } from './supabase';
import type { EmpBrief } from './api_time';

// ---------------------------------------------------------------------------
// 1.14.0 — Employee engagement: announcements, surveys, recognition
// ---------------------------------------------------------------------------
export type AnnCategory = 'GENERAL' | 'HR_POLICY' | 'EVENT' | 'SAFETY' | 'HOLIDAY' | 'CELEBRATION' | 'IT';
export const ANN_CATEGORIES: AnnCategory[] = ['GENERAL', 'HR_POLICY', 'EVENT', 'SAFETY', 'HOLIDAY', 'CELEBRATION', 'IT'];
export type ApprovalStatus = 'DRAFT' | 'PENDING' | 'REJECTED';

export interface Announcement {
  id: string; entity_id: string | null; department_id: string | null; category: AnnCategory;
  title_en: string; title_ar: string | null; body_en: string; body_ar: string | null;
  pinned: boolean; require_ack: boolean; publish_on: string; expires_on: string | null;
  status: ApprovalStatus | 'PUBLISHED' | 'ARCHIVED'; live: boolean;
  entity_code: string | null; department_en: string | null; department_ar: string | null;
  created_by_name: string | null; created_at: string; decided_by_name: string | null; decided_at: string | null; decision_note: string | null;
  read_at: string | null; acknowledged_at: string | null; in_audience?: boolean;
  can_edit: boolean; can_decide: boolean; can_archive: boolean;
  stats: { audience: number; read: number; acknowledged: number } | null;
  attachment_path: string | null; attachment_name: string | null; attachment_bytes: number | null;
}
export interface Reader extends EmpBrief { read_at: string | null; acknowledged_at: string | null }

export type QuestionKind = 'RATING' | 'CHOICE' | 'TEXT';
export interface Question { key?: string; kind: QuestionKind; text_en: string; text_ar: string | null; required: boolean; options: { en: string; ar: string | null }[] }
export interface Survey {
  id: string; entity_id: string | null; department_id: string | null; title_en: string; title_ar: string | null;
  intro_en: string | null; intro_ar: string | null; anonymous: boolean; questions: Question[]; opens_on: string; closes_on: string;
  status: ApprovalStatus | 'OPEN' | 'CLOSED'; live: boolean; entity_code: string | null; department_en: string | null; department_ar: string | null;
  created_by_name: string | null; created_at: string; decided_by_name: string | null; decided_at: string | null; decision_note: string | null;
  answered: boolean; responses: number | null; audience: number | null; in_audience?: boolean; can_answer?: boolean;
  can_edit: boolean; can_decide: boolean; can_close: boolean;
}
export interface QuestionResult extends Question {
  answered: number; average: number | null; ratings: number[] | null; choices: number[] | null;
  texts: (string | { text: string; employee: string | null })[] | null;
}
export interface SurveyResults { survey: Survey; responses: number; audience: number; min_responses: number; hidden: boolean; questions: QuestionResult[] }

export type RecogCategory = 'TEAMWORK' | 'SAFETY' | 'QUALITY' | 'CUSTOMER' | 'INNOVATION' | 'EXTRA_MILE' | 'LEADERSHIP';
export const RECOG_CATEGORIES: RecogCategory[] = ['TEAMWORK', 'SAFETY', 'QUALITY', 'CUSTOMER', 'INNOVATION', 'EXTRA_MILE', 'LEADERSHIP'];
export interface Recognition {
  id: string; kind: 'PEER' | 'AWARD'; category: RecogCategory; award_title: string | null; message: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED' | 'HIDDEN'; created_at: string; posted_at: string; entity_id: string;
  employee: EmpBrief; giver: EmpBrief | null; giver_name: string | null; giver_name_ar: string | null;
  decided_by_name: string | null; decision_note: string | null; hidden_reason: string | null;
  applause: number; applauded: boolean; is_mine: boolean; can_decide: boolean; can_hide: boolean;
}
export interface EngageHome {
  caps: { manage: boolean; approve: boolean; recognise: boolean; employee_id: string | null };
  announcements: Announcement[]; unread: number; to_confirm: number; surveys: Survey[];
  recognitions: Recognition[]; top_month: (EmpBrief & { count: number })[]; my_count: number;
}
export interface EngageCounts { unread: number; surveys: number; to_approve: number }

export const eapi = {
  home: () => rpc<EngageHome>('hr_engage_home'),
  counts: () => rpc<EngageCounts>('hr_engage_counts'),
  // announcements
  listAnnouncements: () => rpc<Announcement[]>('hr_list_announcements'),
  getAnnouncement: (id: string) => rpc<Announcement>('hr_get_announcement', { p_id: id }),
  saveAnnouncement: (p: Json) => rpc<Announcement>('hr_save_announcement', { p }),
  submitAnnouncement: (id: string) => rpc<Announcement>('hr_submit_announcement', { p_id: id }),
  decideAnnouncement: (id: string, approve: boolean, note: string | null) => rpc<Announcement>('hr_decide_announcement', { p_id: id, p_approve: approve, p_note: note }),
  archiveAnnouncement: (id: string) => rpc<Announcement>('hr_archive_announcement', { p_id: id }),
  ackAnnouncement: (id: string) => rpc<Announcement>('hr_ack_announcement', { p_id: id }),
  readers: (id: string) => rpc<Reader[]>('hr_announcement_readers', { p_id: id }),
  // surveys
  listSurveys: () => rpc<Survey[]>('hr_list_surveys'),
  getSurvey: (id: string) => rpc<Survey>('hr_get_survey', { p_id: id }),
  saveSurvey: (p: Json) => rpc<Survey>('hr_save_survey', { p }),
  submitSurvey: (id: string) => rpc<Survey>('hr_submit_survey', { p_id: id }),
  decideSurvey: (id: string, approve: boolean, note: string | null) => rpc<Survey>('hr_decide_survey', { p_id: id, p_approve: approve, p_note: note }),
  closeSurvey: (id: string) => rpc<Survey>('hr_close_survey', { p_id: id }),
  answerSurvey: (id: string, answers: Record<string, number | string>) => rpc<{ ok: boolean; answered: number }>('hr_answer_survey', { p_id: id, p_answers: answers }),
  results: (id: string) => rpc<SurveyResults>('hr_survey_results', { p_id: id }),
  // recognition
  colleagues: (q: string) => rpc<EmpBrief[]>('hr_engage_colleagues', { p_q: q }),
  give: (p: Json) => rpc<Recognition>('hr_give_recognition', { p }),
  proposeAward: (p: Json) => rpc<Recognition>('hr_propose_award', { p }),
  decideAward: (id: string, approve: boolean, note: string | null) => rpc<Recognition>('hr_decide_award', { p_id: id, p_approve: approve, p_note: note }),
  hide: (id: string, reason: string) => rpc<Recognition>('hr_hide_recognition', { p_id: id, p_reason: reason }),
  applaud: (id: string) => rpc<Recognition>('hr_applaud_recognition', { p_id: id }),
  listRecognitions: (scope: 'wall' | 'mine' | 'pending' | 'all', limit = 50) => rpc<Recognition[]>('hr_list_recognitions', { p: { scope, limit } }),
};

/** Answers ready to send: only the questions that were answered. Returns the key of the first required question left empty. */
export function collectAnswers(questions: Question[], vals: Record<string, number | string | undefined>):
  { answers: Record<string, number | string>; missing: string | null } {
  const answers: Record<string, number | string> = {};
  let missing: string | null = null;
  questions.forEach((q, i) => {
    const key = q.key ?? `q${i + 1}`;
    const v = vals[key];
    const empty = v === undefined || v === null || (typeof v === 'string' && v.trim() === '');
    if (empty) { if (q.required && !missing) missing = key; return; }
    answers[key] = typeof v === 'string' && q.kind === 'TEXT' ? v.trim() : Number(v);
  });
  return { answers, missing };
}

/** Share of a count in a total as a whole percent (0 when the total is 0). */
export function pct(n: number, total: number): number {
  return total > 0 ? Math.round((100 * n) / total) : 0;
}

// ---------------------------------------------------------------------------
// 1.15.0 — signed PDF attached to an announcement (private bucket hr-engage, path ann/<uuid>.pdf)
// ---------------------------------------------------------------------------
export const ENGAGE_BUCKET = 'hr-engage';
export const MAX_PDF_BYTES = 10 * 1024 * 1024;

/** 'FILE_TYPE' / 'FILE_SIZE' when the file cannot be attached, otherwise null. */
export function checkPdf(f: { name: string; type: string; size: number }): 'FILE_TYPE' | 'FILE_SIZE' | null {
  const isPdf = f.type === 'application/pdf' || (f.type === '' && /\.pdf$/i.test(f.name));
  if (!isPdf) return 'FILE_TYPE';
  if (f.size <= 0 || f.size > MAX_PDF_BYTES) return 'FILE_SIZE';
  return null;
}

export function annPdfPath(): string {
  return `ann/${crypto.randomUUID().toLowerCase()}.pdf`;
}

export async function uploadAnnPdf(f: File): Promise<string> {
  const path = annPdfPath();
  const { error } = await supabase.storage.from(ENGAGE_BUCKET).upload(path, f, { contentType: 'application/pdf', upsert: false });
  if (error) throw parseError(error);
  return path;
}

export async function annPdfUrl(path: string, seconds = 300): Promise<string> {
  const { data, error } = await supabase.storage.from(ENGAGE_BUCKET).createSignedUrl(path, seconds);
  if (error) throw parseError(error);
  return data.signedUrl;
}

/** "245 KB" / "1.4 MB" */
export function fileSize(bytes: number | null | undefined): string {
  if (!bytes || bytes < 0) return '';
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

// ---------------------------------------------------------------------------
// 1.15.0 — English <-> Arabic translation (edge function `translate`)
// ---------------------------------------------------------------------------
export type TranslateDirection = 'en-ar' | 'ar-en';
export interface Translation { title: string; body: string; model?: string }

/** Turns an edge-function failure into an ApiError ("CODE: message" from the function, or TRANSLATE_OFF when it is not deployed). */
export async function functionError(error: unknown): Promise<ApiError> {
  const ctx = (error as { context?: unknown } | null)?.context;
  if (ctx && typeof (ctx as Response).text === 'function') {
    const res = ctx as Response;
    let text = '';
    try { text = await res.clone().text(); } catch { text = ''; }
    let msg = '';
    try { msg = String((JSON.parse(text) as { error?: unknown }).error ?? ''); } catch { msg = ''; }
    if (msg) return parseError(msg);
    if (res.status === 404) return new ApiError('TRANSLATE_OFF', 'The translation service is not installed on this server.');
    return new ApiError('TRANSLATE_FAILED', `The translation service answered ${res.status}.`);
  }
  const name = (error as { name?: string } | null)?.name ?? '';
  if (name === 'FunctionsFetchError' || name === 'FunctionsRelayError') {
    return new ApiError('TRANSLATE_OFF', 'The translation service could not be reached.');
  }
  return parseError(error);
}

export async function translateAnn(direction: TranslateDirection, title: string, body: string): Promise<Translation> {
  const { data, error } = await supabase.functions.invoke('translate', { body: { direction, title, body } });
  if (error) throw await functionError(error);
  const d = (data ?? {}) as Partial<Translation> & { error?: string };
  if (d.error) throw parseError(d.error);
  if (typeof d.title !== 'string' || typeof d.body !== 'string') throw new ApiError('TRANSLATE_FAILED', 'The translation could not be read.');
  return { title: d.title, body: d.body, model: d.model };
}
