import { rpc, type Json } from './api';
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
