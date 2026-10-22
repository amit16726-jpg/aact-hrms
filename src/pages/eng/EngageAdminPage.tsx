import { useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { ArrowDown, ArrowUp, ChartColumn, Eye, Plus, Trash2, Users } from 'lucide-react';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import {
  ANN_CATEGORIES, RECOG_CATEGORIES, eapi, type AnnCategory, type Announcement, type Question, type QuestionKind, type RecogCategory,
  type Recognition, type Survey,
} from '../../lib/api_eng';
import {
  Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync, useConfirm,
} from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { MasterSelect, EmployeePicker } from '../../components/pickers';
import { AnnCategoryChip, Bar, EngStatus, RecogCategoryChip, audienceText } from '../../components/eng';
import { fmtDate, fmtDateTime, todayMuscat, addDays } from '../../lib/format';

type Tab = 'news' | 'surveys' | 'awards';

export default function EngageAdminPage() {
  const { t } = useI18n();
  const [sp, setSp] = useSearchParams();
  const tab = (['news', 'surveys', 'awards'].includes(sp.get('tab') ?? '') ? sp.get('tab') : 'news') as Tab;
  return (
    <div className="stack">
      <PageHead title={t('ea.title')} sub={t('ea.sub')} actions={<Link className="btn" to="/engage">{t('eg.title')}</Link>} />
      <Tabs label={t('ea.title')} value={tab} onChange={(v) => setSp(v === 'news' ? {} : { tab: v }, { replace: true })}
        tabs={[{ id: 'news', label: t('ea.tab_news') }, { id: 'surveys', label: t('ea.tab_surveys') }, { id: 'awards', label: t('ea.tab_awards') }]} />
      {tab === 'news' && <NewsAdmin />}
      {tab === 'surveys' && <SurveysAdmin />}
      {tab === 'awards' && <AwardsAdmin />}
    </div>
  );
}

/** Approve / reject with a note (reason required to reject). */
function useDecide() {
  const { t } = useI18n();
  const confirm = useConfirm();
  const ask = async (title: string, approve: boolean) =>
    confirm.ask({ title, reason: approve ? 'optional' : 'required', reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
  return { ask, node: confirm.node };
}

function Meta({ x }: { x: { created_by_name: string | null; decided_by_name: string | null; status: string; decision_note: string | null } }) {
  const { t } = useI18n();
  return (
    <div className="muted small">
      {x.created_by_name && t('ea.prepared_by', { n: x.created_by_name })}
      {x.decided_by_name && <> · {t('ea.decided_by', { n: x.decided_by_name })}</>}
      {x.status === 'REJECTED' && x.decision_note && <> · <span className="eg-returned">{t('ea.returned', { n: x.decision_note })}</span></>}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------- announcements
function NewsAdmin() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload, setData } = useAsync(() => eapi.listAnnouncements(), []);
  const [edit, setEdit] = useState<Announcement | 'new' | null>(null);
  const [readers, setReaders] = useState<Announcement | null>(null);
  const { busy, run } = useAction();
  const decide = useDecide();
  const put = (a: Announcement) => setData((data ?? []).some((x) => x.id === a.id) ? (data ?? []).map((x) => (x.id === a.id ? a : x)) : [a, ...(data ?? [])]);

  const onDecide = async (a: Announcement, approve: boolean) => {
    const note = await decide.ask(L(a.title_en, a.title_ar), approve);
    if (note === null) return;
    const r = await run(() => eapi.decideAnnouncement(a.id, approve, note || null), t(approve ? 'ea.approved' : 'ea.rejected'));
    if (r) put(r);
  };
  return (
    <section className="stack">
      {can('ENGAGE_MANAGE') && <div className="row"><Button kind="primary" onClick={() => setEdit('new')}><Plus size={16} aria-hidden="true" /> {t('ea.new_ann')}</Button></div>}
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('ea.none')}</Empty> : (
        <div className="eg-admin-list">
          {data.map((a) => (
            <div key={a.id} className="eg-admin-row">
              <div className="eg-admin-main">
                <div className="eg-ann-top"><AnnCategoryChip c={a.category} /><EngStatus s={a.status} />
                  {a.status === 'PUBLISHED' && !a.live && a.publish_on > todayMuscat() && <span className="eg-flag">{t('ea.scheduled')}</span>}</div>
                <h3>{L(a.title_en, a.title_ar)}</h3>
                <div className="eg-meta">
                  <span>{fmtDate(a.publish_on)}{a.expires_on && <> – {fmtDate(a.expires_on)}</>}</span>
                  <span><Users size={13} aria-hidden="true" /> {audienceText(a, t, L)}</span>
                  {a.stats && <span>{t('ea.read_stats', { r: a.stats.read, a: a.stats.audience })}{a.require_ack && <> · {t('ea.ack_stats', { c: a.stats.acknowledged })}</>}</span>}
                </div>
                <Meta x={a} />
              </div>
              <div className="eg-admin-actions">
                {a.can_edit && <Button small onClick={() => setEdit(a)}>{t('c.edit')}</Button>}
                {a.can_edit && <Button small kind="primary" busy={busy} onClick={() => void run(() => eapi.submitAnnouncement(a.id), t('ea.submitted')).then((r) => r && put(r))}>{t('ea.submit')}</Button>}
                {a.can_decide && <Button small kind="primary" busy={busy} onClick={() => void onDecide(a, true)}>{t('c.approve')}</Button>}
                {a.can_decide && <Button small kind="danger" busy={busy} onClick={() => void onDecide(a, false)}>{t('c.reject')}</Button>}
                {a.stats && <Button small onClick={() => setReaders(a)}><Eye size={14} aria-hidden="true" /> {t('ea.readers')}</Button>}
                {a.can_archive && <Button small kind="ghost" busy={busy} onClick={() => void run(() => eapi.archiveAnnouncement(a.id), t('ea.archived')).then((r) => r && put(r))}>{t('ea.archive')}</Button>}
                <Link className="btn btn-sm btn-ghost" to={`/engage/news/${a.id}`}>{t('c.view')}</Link>
              </div>
            </div>))}
        </div>)}
      {edit && <AnnouncementEditor base={edit === 'new' ? null : edit} onClose={() => setEdit(null)} onDone={(a) => { put(a); setEdit(null); }} />}
      {readers && <ReadersDialog a={readers} onClose={() => setReaders(null)} />}
      {decide.node}
    </section>
  );
}

function AnnouncementEditor({ base, onClose, onDone }: { base: Announcement | null; onClose: () => void; onDone: (a: Announcement) => void }) {
  const { t, L } = useI18n();
  const { me } = useSession();
  const { busy, run } = useAction();
  const today = todayMuscat();
  const [f, setF] = useState({
    entity_id: base ? base.entity_id : (me?.entities.length === 1 ? me.entities[0].id : null) as string | null,
    department_id: base?.department_id ?? null as string | null, category: (base?.category ?? 'GENERAL') as AnnCategory,
    title_en: base?.title_en ?? '', title_ar: base?.title_ar ?? '', body_en: base?.body_en ?? '', body_ar: base?.body_ar ?? '',
    pinned: base?.pinned ?? false, require_ack: base?.require_ack ?? false,
    publish_on: base && base.publish_on >= today ? base.publish_on : today, expires_on: base?.expires_on ?? '',
  });
  const save = async (submit: boolean) => {
    const a = await run(() => eapi.saveAnnouncement({ ...f, id: base?.id ?? null, expires_on: f.expires_on || null }), submit ? undefined : t('ea.saved'));
    if (!a) return;
    if (submit) { const s = await run(() => eapi.submitAnnouncement(a.id), t('ea.submitted')); onDone(s ?? a); } else onDone(a);
  };
  const ok = f.title_en.trim().length >= 3 && f.body_en.trim().length >= 3 && !!f.publish_on && (!f.expires_on || f.expires_on >= f.publish_on);
  return (
    <Modal open wide title={base ? t('ea.edit_ann') : t('ea.new_ann')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button busy={busy} disabled={!ok} onClick={() => void save(false)}>{t('ea.save_draft')}</Button>
        <Button kind="primary" busy={busy} disabled={!ok} onClick={() => void save(true)}>{t('ea.submit')}</Button></>}>
      <div className="form-grid">
        <Input label={t('ea.title_en')} required maxLength={150} value={f.title_en} onChange={(e) => setF({ ...f, title_en: e.target.value })} />
        <Input label={t('ea.title_ar')} dir="rtl" lang="ar" maxLength={150} value={f.title_ar} onChange={(e) => setF({ ...f, title_ar: e.target.value })} />
        <Textarea label={t('ea.body_en')} required rows={6} maxLength={5000} value={f.body_en} onChange={(e) => setF({ ...f, body_en: e.target.value })} />
        <Textarea label={t('ea.body_ar')} dir="rtl" lang="ar" rows={6} maxLength={5000} value={f.body_ar} onChange={(e) => setF({ ...f, body_ar: e.target.value })} />
        <Select label={t('ea.category')} value={f.category} onChange={(e) => setF({ ...f, category: e.target.value as AnnCategory })}>
          {ANN_CATEGORIES.map((c) => <option key={c} value={c}>{t(`eg.cat_${c}` as Key)}</option>)}
        </Select>
        <Select label={t('ea.company')} value={f.entity_id ?? ''} onChange={(e) => setF({ ...f, entity_id: e.target.value || null, department_id: null })}>
          <option value="">{t('ea.all_companies')}</option>
          {(me?.entities ?? []).map((x) => <option key={x.id} value={x.id}>{L(x.name_en, x.name_ar)}</option>)}
        </Select>
        {f.entity_id && <MasterSelect kind="department" entityId={f.entity_id} label={t('ea.department')} hint={t('ea.dept_hint')}
          value={f.department_id} onChange={(v) => setF({ ...f, department_id: v })} />}
        <Input label={t('ea.publish_on')} type="date" ltr required min={today} value={f.publish_on} onChange={(e) => setF({ ...f, publish_on: e.target.value })} />
        <Input label={t('ea.expires_on')} type="date" ltr min={f.publish_on} value={f.expires_on} onChange={(e) => setF({ ...f, expires_on: e.target.value })} />
        <div className="span-2 stack" style={{ gap: 6 }}>
          <Check label={t('ea.pinned')} checked={f.pinned} onChange={(v) => setF({ ...f, pinned: v })} />
          <Check label={t('ea.require_ack')} checked={f.require_ack} onChange={(v) => setF({ ...f, require_ack: v })} />
        </div>
      </div>
    </Modal>
  );
}

function ReadersDialog({ a, onClose }: { a: Announcement; onClose: () => void }) {
  const { t, L } = useI18n();
  const { data, error, loading } = useAsync(() => eapi.readers(a.id), [a.id]);
  return (
    <Modal open wide title={`${t('ea.readers')} — ${L(a.title_en, a.title_ar)}`} onClose={onClose} footer={<Button onClick={onClose}>{t('c.close')}</Button>}>
      <ErrorNote error={error} />
      {loading ? <Loading /> : !data?.length ? <Empty>{t('ea.none')}</Empty> : (
        <div className="table-wrap"><table className="t">
          <thead><tr><th>{t('c.employee')}</th><th>{t('c.department')}</th><th>{t('ea.st_PUBLISHED')}</th>{a.require_ack && <th>{t('eg.needs_ack')}</th>}</tr></thead>
          <tbody>{data.map((r) => (
            <tr key={r.employee_id}>
              <td><b>{L(r.full_name_en, r.full_name_ar)}</b><div className="muted small num">{r.employee_no}</div></td>
              <td>{L(r.department_en, r.department_ar)}</td>
              <td className="num">{r.read_at ? fmtDateTime(r.read_at) : <span className="muted">{t('ea.not_read')}</span>}</td>
              {a.require_ack && <td className="num">{r.acknowledged_at ? fmtDateTime(r.acknowledged_at) : '—'}</td>}
            </tr>))}
          </tbody></table></div>)}
    </Modal>
  );
}

// ---------------------------------------------------------------------------------------------- surveys
function SurveysAdmin() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload, setData } = useAsync(() => eapi.listSurveys(), []);
  const [edit, setEdit] = useState<Survey | 'new' | null>(null);
  const [results, setResults] = useState<Survey | null>(null);
  const { busy, run } = useAction();
  const decide = useDecide();
  const put = (s: Survey) => setData((data ?? []).some((x) => x.id === s.id) ? (data ?? []).map((x) => (x.id === s.id ? s : x)) : [s, ...(data ?? [])]);
  const onDecide = async (s: Survey, approve: boolean) => {
    const note = await decide.ask(L(s.title_en, s.title_ar), approve);
    if (note === null) return;
    const r = await run(() => eapi.decideSurvey(s.id, approve, note || null), t(approve ? 'ea.approved' : 'ea.rejected'));
    if (r) put(r);
  };
  return (
    <section className="stack">
      {can('ENGAGE_MANAGE') && <div className="row"><Button kind="primary" onClick={() => setEdit('new')}><Plus size={16} aria-hidden="true" /> {t('ea.new_survey')}</Button></div>}
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('ea.none')}</Empty> : (
        <div className="eg-admin-list">
          {data.map((s) => (
            <div key={s.id} className="eg-admin-row">
              <div className="eg-admin-main">
                <div className="eg-ann-top"><EngStatus s={s.status} /><span className={`eg-chip ${s.anonymous ? 'eg-anon' : ''}`}>{s.anonymous ? t('eg.anonymous') : t('eg.named')}</span></div>
                <h3>{L(s.title_en, s.title_ar)}</h3>
                <div className="eg-meta">
                  <span>{fmtDate(s.opens_on)} – {fmtDate(s.closes_on)}</span>
                  <span>{(s.questions.length === 1 ? t('eg.one_question') : t('eg.n_questions', { n: s.questions.length }))}</span>
                  <span><Users size={13} aria-hidden="true" /> {audienceText(s, t, L)}</span>
                  {(s.status === 'OPEN' || s.status === 'CLOSED') && <span>{t('ea.responses', { r: s.responses ?? 0, a: s.audience ?? 0 })}</span>}
                </div>
                {(s.status === 'OPEN' || s.status === 'CLOSED') && <div className="eg-progress" aria-hidden="true"><span style={{ width: `${s.audience ? Math.min(100, Math.round((100 * (s.responses ?? 0)) / s.audience)) : 0}%` }} /></div>}
                <Meta x={s} />
              </div>
              <div className="eg-admin-actions">
                {s.can_edit && <Button small onClick={() => setEdit(s)}>{t('c.edit')}</Button>}
                {s.can_edit && <Button small kind="primary" busy={busy} onClick={() => void run(() => eapi.submitSurvey(s.id), t('ea.submitted')).then((r) => r && put(r))}>{t('ea.submit')}</Button>}
                {s.can_decide && <Button small kind="primary" busy={busy} onClick={() => void onDecide(s, true)}>{t('c.approve')}</Button>}
                {s.can_decide && <Button small kind="danger" busy={busy} onClick={() => void onDecide(s, false)}>{t('c.reject')}</Button>}
                {(s.status === 'OPEN' || s.status === 'CLOSED') && <Button small onClick={() => setResults(s)}><ChartColumn size={14} aria-hidden="true" /> {t('ea.results')}</Button>}
                {s.can_close && <Button small kind="ghost" busy={busy} onClick={() => void run(() => eapi.closeSurvey(s.id), t('ea.closed')).then((r) => r && put(r))}>{t('ea.close')}</Button>}
                <Link className="btn btn-sm btn-ghost" to={`/engage/survey/${s.id}`}>{t('c.view')}</Link>
              </div>
            </div>))}
        </div>)}
      {edit && <SurveyEditor base={edit === 'new' ? null : edit} onClose={() => setEdit(null)} onDone={(s) => { put(s); setEdit(null); }} />}
      {results && <ResultsDialog s={results} onClose={() => setResults(null)} />}
      {decide.node}
    </section>
  );
}

const blankQuestion = (kind: QuestionKind = 'RATING'): Question => ({ kind, text_en: '', text_ar: null, required: kind !== 'TEXT', options: kind === 'CHOICE' ? [{ en: '', ar: null }, { en: '', ar: null }] : [] });

function SurveyEditor({ base, onClose, onDone }: { base: Survey | null; onClose: () => void; onDone: (s: Survey) => void }) {
  const { t, L } = useI18n();
  const { me } = useSession();
  const { busy, run } = useAction();
  const today = todayMuscat();
  const [f, setF] = useState({
    entity_id: base ? base.entity_id : (me?.entities.length === 1 ? me.entities[0].id : null) as string | null,
    department_id: base?.department_id ?? null as string | null,
    title_en: base?.title_en ?? '', title_ar: base?.title_ar ?? '', intro_en: base?.intro_en ?? '', intro_ar: base?.intro_ar ?? '',
    anonymous: base?.anonymous ?? true,
    opens_on: base && base.opens_on >= today ? base.opens_on : today, closes_on: base?.closes_on ?? addDays(today, 14),
  });
  const [qs, setQs] = useState<Question[]>(base?.questions?.length ? base.questions.map((q) => ({ ...q, options: q.options ?? [] })) : [blankQuestion()]);
  const setQ = (i: number, q: Partial<Question>) => setQs(qs.map((x, j) => (j === i ? { ...x, ...q } : x)));
  const move = (i: number, d: -1 | 1) => { const n = [...qs]; const j = i + d; if (j < 0 || j >= n.length) return; [n[i], n[j]] = [n[j], n[i]]; setQs(n); };
  const okQ = qs.length > 0 && qs.every((q) => q.text_en.trim().length >= 3 && (q.kind !== 'CHOICE' || (q.options.length >= 2 && q.options.every((o) => o.en.trim()))));
  const ok = f.title_en.trim().length >= 3 && !!f.closes_on && f.closes_on >= f.opens_on && okQ;
  const save = async (submit: boolean) => {
    const p = { ...f, id: base?.id ?? null, questions: qs.map((q) => ({ kind: q.kind, text_en: q.text_en, text_ar: q.text_ar, required: q.required, options: q.kind === 'CHOICE' ? q.options : [] })) };
    const s = await run(() => eapi.saveSurvey(p), submit ? undefined : t('ea.saved'));
    if (!s) return;
    if (submit) { const r = await run(() => eapi.submitSurvey(s.id), t('ea.submitted')); onDone(r ?? s); } else onDone(s);
  };
  return (
    <Modal open wide title={base ? t('ea.edit_survey') : t('ea.new_survey')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button busy={busy} disabled={!ok} onClick={() => void save(false)}>{t('ea.save_draft')}</Button>
        <Button kind="primary" busy={busy} disabled={!ok} onClick={() => void save(true)}>{t('ea.submit')}</Button></>}>
      <div className="stack">
        <div className="form-grid">
          <Input label={t('ea.title_en')} required maxLength={150} value={f.title_en} onChange={(e) => setF({ ...f, title_en: e.target.value })} />
          <Input label={t('ea.title_ar')} dir="rtl" lang="ar" maxLength={150} value={f.title_ar} onChange={(e) => setF({ ...f, title_ar: e.target.value })} />
          <Textarea label={t('ea.intro_en')} rows={3} maxLength={2000} value={f.intro_en} onChange={(e) => setF({ ...f, intro_en: e.target.value })} />
          <Textarea label={t('ea.intro_ar')} dir="rtl" lang="ar" rows={3} maxLength={2000} value={f.intro_ar} onChange={(e) => setF({ ...f, intro_ar: e.target.value })} />
          <Select label={t('ea.company')} value={f.entity_id ?? ''} onChange={(e) => setF({ ...f, entity_id: e.target.value || null, department_id: null })}>
            <option value="">{t('ea.all_companies')}</option>
            {(me?.entities ?? []).map((x) => <option key={x.id} value={x.id}>{L(x.name_en, x.name_ar)}</option>)}
          </Select>
          {f.entity_id ? <MasterSelect kind="department" entityId={f.entity_id} label={t('ea.department')} hint={t('ea.dept_hint')}
            value={f.department_id} onChange={(v) => setF({ ...f, department_id: v })} /> : <div />}
          <Input label={t('ea.opens_on')} type="date" ltr required min={today} value={f.opens_on} onChange={(e) => setF({ ...f, opens_on: e.target.value })} />
          <Input label={t('ea.closes_on')} type="date" ltr required min={f.opens_on} value={f.closes_on} onChange={(e) => setF({ ...f, closes_on: e.target.value })} />
          <div className="span-2">
            <Check label={t('ea.anonymous')} checked={f.anonymous} onChange={(v) => setF({ ...f, anonymous: v })} />
            <p className="muted small" style={{ margin: '4px 0 0' }}>{t('ea.anonymous_hint')}</p>
          </div>
        </div>
        <h3>{t('ea.questions')}</h3>
        {qs.map((q, i) => (
          <fieldset key={i} className="eg-qedit">
            <legend>{t('ea.q_n', { n: i + 1 })}</legend>
            <div className="eg-qedit-tools">
              <Button small kind="ghost" aria-label={t('ea.move_up')} title={t('ea.move_up')} disabled={i === 0} onClick={() => move(i, -1)}><ArrowUp size={14} aria-hidden="true" /></Button>
              <Button small kind="ghost" aria-label={t('ea.move_down')} title={t('ea.move_down')} disabled={i === qs.length - 1} onClick={() => move(i, 1)}><ArrowDown size={14} aria-hidden="true" /></Button>
              <Button small kind="ghost" aria-label={t('ea.remove_q')} title={t('ea.remove_q')} disabled={qs.length === 1} onClick={() => setQs(qs.filter((_, j) => j !== i))}><Trash2 size={14} aria-hidden="true" /></Button>
            </div>
            <div className="form-grid">
              <Select label={t('ea.q_kind')} value={q.kind} onChange={(e) => {
                const k = e.target.value as QuestionKind;
                setQ(i, { kind: k, required: k !== 'TEXT', options: k === 'CHOICE' ? (q.options.length >= 2 ? q.options : [{ en: '', ar: null }, { en: '', ar: null }]) : [] });
              }}>
                {(['RATING', 'CHOICE', 'TEXT'] as QuestionKind[]).map((k) => <option key={k} value={k}>{t(`ea.k_${k}` as Key)}</option>)}
              </Select>
              <div className="eg-qedit-req"><Check label={t('ea.q_required')} checked={q.required} onChange={(v) => setQ(i, { required: v })} /></div>
              <Input label={t('ea.q_text_en')} required maxLength={300} value={q.text_en} onChange={(e) => setQ(i, { text_en: e.target.value })} />
              <Input label={t('ea.q_text_ar')} dir="rtl" lang="ar" maxLength={300} value={q.text_ar ?? ''} onChange={(e) => setQ(i, { text_ar: e.target.value || null })} />
            </div>
            {q.kind === 'CHOICE' && (
              <div className="stack" style={{ gap: 8 }}>
                <b className="small">{t('ea.options')}</b>
                {q.options.map((o, oi) => (
                  <div key={oi} className="eg-opt-row">
                    <Input label={t('ea.option_en', { n: oi + 1 })} required maxLength={120} value={o.en}
                      onChange={(e) => setQ(i, { options: q.options.map((x, j) => (j === oi ? { ...x, en: e.target.value } : x)) })} />
                    <Input label={t('ea.option_ar', { n: oi + 1 })} dir="rtl" lang="ar" maxLength={120} value={o.ar ?? ''}
                      onChange={(e) => setQ(i, { options: q.options.map((x, j) => (j === oi ? { ...x, ar: e.target.value || null } : x)) })} />
                    <Button small kind="ghost" aria-label={t('ea.remove_option')} title={t('ea.remove_option')} disabled={q.options.length <= 2}
                      onClick={() => setQ(i, { options: q.options.filter((_, j) => j !== oi) })}><Trash2 size={14} aria-hidden="true" /></Button>
                  </div>))}
                {q.options.length < 10 && <div><Button small onClick={() => setQ(i, { options: [...q.options, { en: '', ar: null }] })}><Plus size={14} aria-hidden="true" /> {t('ea.add_option')}</Button></div>}
              </div>)}
          </fieldset>))}
        {qs.length < 30 && <div><Button onClick={() => setQs([...qs, blankQuestion()])}><Plus size={16} aria-hidden="true" /> {t('ea.add_question')}</Button></div>}
      </div>
    </Modal>
  );
}

function ResultsDialog({ s, onClose }: { s: Survey; onClose: () => void }) {
  const { t, L } = useI18n();
  const { data, error, loading } = useAsync(() => eapi.results(s.id), [s.id]);
  return (
    <Modal open wide title={`${t('ea.results')} — ${L(s.title_en, s.title_ar)}`} onClose={onClose} footer={<Button onClick={onClose}>{t('c.close')}</Button>}>
      <ErrorNote error={error} />
      {loading || !data ? <Loading /> : (
        <div className="stack">
          <div className="eg-meta"><span>{t('ea.responses', { r: data.responses, a: data.audience })}</span>
            <span className={`eg-chip ${data.survey.anonymous ? 'eg-anon' : ''}`}>{data.survey.anonymous ? t('eg.anonymous') : t('eg.named')}</span></div>
          {data.hidden ? <div className="note">{t('ea.hidden_results', { n: data.min_responses, r: data.responses })}</div>
            : data.questions.map((q, i) => (
              <section key={q.key ?? i} className="eg-result">
                <h3><span className="eg-q-n num">{i + 1}</span>{L(q.text_en, q.text_ar)}</h3>
                <div className="muted small">{t('ea.answers_n', { n: q.answered })}{q.average !== null && <> · <b>{t('ea.avg', { v: q.average })}</b></>}</div>
                {q.kind === 'RATING' && q.ratings && q.ratings.map((n, ri) => (
                  <Bar key={ri} label={`${ri + 1} · ${t(`eg.rate_${ri + 1}` as Key)}`} value={n} total={q.answered} strong={n === Math.max(...(q.ratings ?? [0]))} />))}
                {q.kind === 'CHOICE' && q.choices && q.choices.map((n, ci) => (
                  <Bar key={ci} label={L(q.options[ci]?.en, q.options[ci]?.ar)} value={n} total={q.answered} strong={n === Math.max(...(q.choices ?? [0]))} />))}
                {q.kind === 'TEXT' && (q.texts?.length ? (
                  <ul className="eg-comments">{q.texts.map((x, ti) => (
                    <li key={ti}>{typeof x === 'string' ? x : <>{x.text}{x.employee && <span className="muted small"> — {x.employee}</span>}</>}</li>))}</ul>
                ) : <p className="muted small">{t('ea.no_answers')}</p>)}
              </section>))}
        </div>)}
    </Modal>
  );
}

// ---------------------------------------------------------------------------------------------- awards and moderation
function AwardsAdmin() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const pending = useAsync(() => eapi.listRecognitions('pending'), []);
  const history = useAsync(() => eapi.listRecognitions('all', 100), []);
  const [open, setOpen] = useState(false);
  const { busy, run } = useAction();
  const decide = useDecide();
  const onDecide = async (r: Recognition, approve: boolean) => {
    const note = await decide.ask(`${r.award_title} — ${L(r.employee.full_name_en, r.employee.full_name_ar)}`, approve);
    if (note === null) return;
    const res = await run(() => eapi.decideAward(r.id, approve, note || null), t(approve ? 'ea.approved' : 'ea.rejected'));
    if (res) { void pending.reload(); void history.reload(); }
  };
  return (
    <section className="stack">
      {can('ENGAGE_MANAGE') && <div className="row"><Button kind="primary" onClick={() => setOpen(true)}><Plus size={16} aria-hidden="true" /> {t('ea.new_award')}</Button></div>}
      <div className="panel">
        <div className="panel-head"><h2>{t('ea.pending')}</h2></div>
        <div className="panel-pad">
          <ErrorNote error={pending.error} onRetry={pending.reload} />
          {pending.loading && !pending.data ? <Loading /> : !pending.data?.length ? <p className="muted">{t('ea.no_pending')}</p> : (
            <div className="eg-admin-list">{pending.data.map((r) => (
              <div key={r.id} className="eg-admin-row">
                <div className="eg-admin-main">
                  <div className="eg-ann-top"><EngStatus s={r.status} /><RecogCategoryChip c={r.category} /></div>
                  <h3>{r.award_title} — {L(r.employee.full_name_en, r.employee.full_name_ar)}</h3>
                  <p className="eg-recog-msg">{r.message}</p>
                  <div className="muted small">{t('ea.prepared_by', { n: r.giver_name ?? '—' })} · {fmtDateTime(r.created_at)}</div>
                </div>
                <div className="eg-admin-actions">
                  {r.can_decide && <Button small kind="primary" busy={busy} onClick={() => void onDecide(r, true)}>{t('c.approve')}</Button>}
                  {r.can_decide && <Button small kind="danger" busy={busy} onClick={() => void onDecide(r, false)}>{t('c.reject')}</Button>}
                </div>
              </div>))}</div>)}
        </div>
      </div>
      <div className="panel">
        <div className="panel-head"><h2>{t('ea.history')}</h2></div>
        <div className="panel-pad">
          <ErrorNote error={history.error} onRetry={history.reload} />
          {history.loading && !history.data ? <Loading /> : !history.data?.length ? <p className="muted">{t('ea.none')}</p> : (
            <div className="table-wrap"><table className="t">
              <thead><tr><th>{t('c.date')}</th><th>{t('c.employee')}</th><th>{t('c.type')}</th><th>{t('eg.message')}</th><th>{t('c.status')}</th></tr></thead>
              <tbody>{history.data.map((r) => (
                <tr key={r.id}>
                  <td className="num nowrap">{fmtDate(r.posted_at.slice(0, 10))}</td>
                  <td><b>{L(r.employee.full_name_en, r.employee.full_name_ar)}</b><div className="muted small num">{r.employee.employee_no}</div></td>
                  <td>{r.kind === 'AWARD' ? r.award_title : t(`eg.rc_${r.category}` as Key)}</td>
                  <td className="eg-cell-msg">{r.message}{r.status === 'HIDDEN' && r.hidden_reason && <div className="muted small">{t('ea.hidden_reason', { r: r.hidden_reason })}</div>}
                    {r.status === 'REJECTED' && r.decision_note && <div className="muted small">{t('ea.returned', { n: r.decision_note })}</div>}</td>
                  <td><EngStatus s={r.status} /></td>
                </tr>))}
              </tbody></table></div>)}
        </div>
      </div>
      {open && <AwardDialog onClose={() => setOpen(false)} onDone={() => { setOpen(false); void pending.reload(); void history.reload(); }} />}
      {decide.node}
    </section>
  );
}

function AwardDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [emp, setEmp] = useState<{ id: string | null; label: string | null }>({ id: null, label: null });
  const [title, setTitle] = useState('');
  const [cat, setCat] = useState<RecogCategory>('EXTRA_MILE');
  const [msg, setMsg] = useState('');
  const ok = !!emp.id && title.trim().length >= 3 && msg.trim().length >= 3;
  const submit = async () => {
    const r = await run(() => eapi.proposeAward({ employee_id: emp.id, award_title: title.trim(), category: cat, message: msg.trim() }), t('ea.award_sent'));
    if (r) onDone();
  };
  return (
    <Modal open title={t('ea.new_award')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!ok} onClick={() => void submit()}>{t('ea.submit')}</Button></>}>
      <div className="stack">
        <EmployeePicker label={t('ea.employee')} value={emp.id} valueLabel={emp.label} onChange={(id, label) => setEmp({ id, label })} />
        <Input label={t('ea.award_title')} required maxLength={100} placeholder={t('ea.award_title_ph')} value={title} onChange={(e) => setTitle(e.target.value)} />
        <Select label={t('eg.for')} value={cat} onChange={(e) => setCat(e.target.value as RecogCategory)}>
          {RECOG_CATEGORIES.map((c) => <option key={c} value={c}>{t(`eg.rc_${c}` as Key)}</option>)}
        </Select>
        <Textarea label={t('ea.citation')} required rows={4} maxLength={500} value={msg} onChange={(e) => setMsg(e.target.value)} />
      </div>
    </Modal>
  );
}
