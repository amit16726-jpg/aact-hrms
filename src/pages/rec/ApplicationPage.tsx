import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { offerLines, recapi, type Application, type Interview, type Offer, type OnboardingTask, type Stage } from '../../lib/api_rec';
import { api } from '../../lib/api';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm, useToast } from '../../components/ui';
import { EmployeePicker, MasterSelect } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { InterviewerSelect, OfferBadge, StageBadge, Stars } from '../../components/rec';
import { OMR } from '../../components/pay';
import { addDays, fmtDate, fmtDateTime, todayMuscat } from '../../lib/format';

export default function ApplicationPage() {
  const { id = '' } = useParams();
  const { t, L } = useI18n();
  const { data: a, error, loading, reload, setData } = useAsync(() => recapi.getApplication(id), [id]);
  const [dlg, setDlg] = useState<null | 'schedule' | 'offer' | 'hire'>(null);
  const [rec, setRec] = useState<Interview | null>(null);
  const [editOffer, setEditOffer] = useState<Offer | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  if (loading && !a) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!a) return null;
  const refresh = (x: Application | null | undefined) => { if (x) setData(x); };
  const move = async (stage: Stage) => {
    const needReason = stage === 'REJECTED' || stage === 'WITHDRAWN';
    const note = await confirm.ask({ title: `${t('ap2.move')}: ${t(`stg.${stage}` as Key)} — ${a.full_name_en}`, reason: needReason ? 'required' : undefined, danger: needReason });
    if (note === null) return;
    refresh(await run(() => recapi.moveApplication(a.id, stage, note || null)));
  };
  const open = a.stage !== 'HIRED' && a.stage !== 'REJECTED' && a.stage !== 'WITHDRAWN';
  const activeOffer = a.offers.find((o) => ['PENDING', 'APPROVED', 'ACCEPTED'].includes(o.status));
  const c = a.candidate;
  return (
    <div className="stack">
      <PageHead title={L(a.full_name_en, a.full_name_ar)}
        sub={<><Link to={`/recruitment/req/${a.requisition_id}`}>{t('ap2.back_req', { r: a.requisition.ref_no })}</Link> · {L(a.requisition.job_en, a.requisition.job_ar)} · <StageBadge s={a.stage} /></>}
        actions={a.can_manage && open && <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          {a.stage === 'APPLIED' && <Button onClick={() => void move('SHORTLISTED')}>{t('stg.SHORTLISTED')}</Button>}
          {a.stage !== 'OFFER' && <Button onClick={() => setDlg('schedule')}>{t('iv.schedule')}</Button>}
          {!activeOffer && (a.stage === 'INTERVIEW' || a.stage === 'SHORTLISTED') && <Button kind="primary" onClick={() => { setEditOffer(null); setDlg('offer'); }}>{t('of.new')}</Button>}
          {a.stage !== 'OFFER' && <><Button kind="danger" busy={busy} onClick={() => void move('REJECTED')}>{t('ap2.reject')}</Button>
            <Button busy={busy} onClick={() => void move('WITHDRAWN')}>{t('ap2.withdraw')}</Button></>}
        </div>} />
      {a.rejection_reason && <div className="note note-warn">{a.rejection_reason}</div>}
      {a.employee_id && <div className="note note-ok"><Link to={`/employees/${a.employee_id}`}>{t('hr2.open_employee')}</Link></div>}
      {a.prior_employee_id && <div className="note">{t('cd.prior')} <Link to={`/employees/${a.prior_employee_id}`}>{t('hr2.open_employee')}</Link></div>}
      <div className="grid-2" style={{ alignItems: 'start' }}>
        <section className="panel panel-pad stack">
          <h2 style={{ margin: 0 }}>{t('iv.candidate')}</h2>
          <dl className="kv">
            <div><dt>{t('cd.nationality')}</dt><dd>{L(c.nationality_en, c.nationality_ar) || c.nationality}{c.in_oman === false && <span className="sub">{t('cd.abroad')}</span>}</dd></div>
            {c.email !== undefined && <div><dt>{t('cd.email')}</dt><dd className="ltr-inline">{c.email || '—'}</dd></div>}
            {c.phone !== undefined && <div><dt>{t('cd.phone')}</dt><dd className="ltr-inline num">{c.phone || '—'}</dd></div>}
            {c.date_of_birth !== undefined && <div><dt>{t('cd.dob')}</dt><dd className="num">{fmtDate(c.date_of_birth)}</dd></div>}
            {c.civil_number !== undefined && <div><dt>{t('cd.civil')}</dt><dd className="num">{c.civil_number || '—'}</dd></div>}
            {c.passport_no !== undefined && <div><dt>{t('cd.passport')}</dt><dd className="num">{c.passport_no || '—'}</dd></div>}
            <div><dt>{t('cd.experience')}</dt><dd className="num">{c.experience_years ?? '—'}</dd></div>
            <div><dt>{t('cd.qualification')}</dt><dd>{c.qualification || '—'}</dd></div>
            <div><dt>{t('cd.employer')}</dt><dd>{c.current_employer || '—'}</dd></div>
            {c.source !== undefined && <div><dt>{t('cd.source')}</dt><dd>{t(`cd.s_${c.source}` as Key)}</dd></div>}
          </dl>
          {c.notes && <p className="muted" style={{ margin: 0 }}>{c.notes}</p>}
        </section>
        <section className="panel">
          <div className="panel-head"><h2>{t('rc.tab_interviews')}</h2></div>
          {!a.interviews.length ? <Empty>{t('iv.none')}</Empty> : (
            <ul className="plain panel-pad">{a.interviews.map((i) => (
              <li key={i.id} className="iv-item">
                <div className="row" style={{ justifyContent: 'space-between' }}>
                  <span><b className="num">{fmtDateTime(i.scheduled_at)}</b> · {t(`iv.m_${i.mode}` as Key)}{i.location ? ` · ${i.location}` : ''}<span className="sub">{i.interviewer_name}</span></span>
                  {i.status === 'DONE' ? <Stars n={i.rating} /> : <Badge tone={i.status === 'SCHEDULED' ? 'warn' : undefined}>{t(`iv.st_${i.status}` as Key)}</Badge>}
                </div>
                {i.recommendation && <div><Badge tone={i.recommendation === 'HIRE' ? 'ok' : i.recommendation === 'NO' ? 'bad' : 'warn'}>{t(`iv.r_${i.recommendation}` as Key)}</Badge> {i.feedback}</div>}
                {(i.can_record || i.can_cancel) && <div className="row" style={{ gap: 4 }}>
                  {i.can_record && <Button small kind="primary" onClick={() => setRec(i)}>{t('iv.record')}</Button>}
                  {i.can_cancel && <Button small busy={busy} onClick={async () => { if ((await confirm.ask({ title: t('iv.cancel'), danger: true })) !== null) refresh(await run(() => recapi.recordInterview(i.id, { status: 'CANCELLED' }))); }}>{t('iv.cancel')}</Button>}
                </div>}
              </li>))}
            </ul>)}
        </section>
      </div>
      {a.offers.length > 0 && <Offers a={a} refresh={refresh} onEdit={(o) => { setEditOffer(o); setDlg('offer'); }} onHire={() => setDlg('hire')} />}
      {a.onboarding.length > 0 && <Checklist tasks={a.onboarding} refresh={refresh} canManage={a.can_manage} />}
      <ScheduleDialog open={dlg === 'schedule'} appId={a.id} onClose={() => setDlg(null)} onDone={refresh} />
      <RecordDialog i={rec} onClose={() => setRec(null)} onDone={refresh} />
      <OfferDialog open={dlg === 'offer'} a={a} edit={editOffer} onClose={() => setDlg(null)} onDone={refresh} />
      {activeOffer && <HireDialog open={dlg === 'hire'} a={a} offer={activeOffer} onClose={() => setDlg(null)} onDone={refresh} />}
      {confirm.node}
    </div>
  );
}

function Offers({ a, refresh, onEdit, onHire }: { a: Application; refresh: (x: Application | null | undefined) => void; onEdit: (o: Offer) => void; onHire: () => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const decide = async (o: Offer, approve: boolean) => {
    const note = await confirm.ask({ title: `${t(approve ? 'of.approve_title' : 'of.reject_title')} — ${o.ref_no}`, reason: approve ? 'optional' : 'required',
      reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    refresh(await run(() => recapi.decideOffer(o.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject')));
  };
  const respond = async (o: Offer, accepted: boolean) => {
    const note = await confirm.ask({ title: `${t(accepted ? 'of.accepted' : 'of.declined')} — ${o.ref_no}`, body: accepted ? t('of.accept_q') : undefined,
      reason: accepted ? 'optional' : 'required', reasonLabel: accepted ? t('c.notes') : t('of.decline_reason'), danger: !accepted });
    if (note === null) return;
    refresh(await run(() => recapi.offerResponse(o.id, accepted, note || null)));
  };
  const withdraw = async (o: Offer) => {
    const note = await confirm.ask({ title: `${t('of.withdraw')} — ${o.ref_no}`, reason: 'required', danger: true });
    if (note === null) return;
    refresh(await run(() => recapi.withdrawOffer(o.id, note)));
  };
  return (
    <section className="panel">
      <div className="panel-head"><h2>{t('of.title')}</h2></div>
      {a.offers.map((o) => (
        <div key={o.id} className="panel-pad stack offer-box">
          <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}>
            <span><b className="num">{o.ref_no}</b> <OfferBadge s={o.status} /></span>
            <div className="row" style={{ gap: 4, flexWrap: 'wrap' }}>
              {['APPROVED', 'ACCEPTED'].includes(o.status) && <Link className="btn btn-sm" to={`/recruitment/offer/${o.id}`}>{t('of.print')}</Link>}
              {o.can_edit && <Button small onClick={() => onEdit(o)}>{t('c.edit')}</Button>}
              {o.can_decide && <><Button small kind="primary" busy={busy} onClick={() => void decide(o, true)}>{t('c.approve')}</Button>
                <Button small kind="danger" busy={busy} onClick={() => void decide(o, false)}>{t('c.reject')}</Button></>}
              {o.can_respond && <><Button small kind="primary" busy={busy} onClick={() => void respond(o, true)}>{t('of.accepted')}</Button>
                <Button small busy={busy} onClick={() => void respond(o, false)}>{t('of.declined')}</Button></>}
              {o.can_hire && <Button small kind="primary" onClick={onHire}>{t('hr2.hire')}</Button>}
              {o.can_withdraw && <Button small kind="danger" busy={busy} onClick={() => void withdraw(o)}>{t('of.withdraw')}</Button>}
            </div>
          </div>
          <dl className="kv">
            <div><dt>{t('rq2.job')}</dt><dd>{L(o.job_en, o.job_ar)}<span className="sub">{L(o.department_en, o.department_ar)}</span></dd></div>
            <div><dt>{t('of.start')}</dt><dd className="num">{fmtDate(o.start_date)}</dd></div>
            <div><dt>{t('of.contract')}</dt><dd>{t(`of.c_${o.contract_type}` as Key)}{o.contract_months ? ` · ${o.contract_months}` : ''}</dd></div>
            <div><dt>{t('of.probation')}</dt><dd className="num">{o.probation_months}</dd></div>
            <div><dt>{t('of.notice')}</dt><dd className="num">{o.notice_days}</dd></div>
            <div><dt>{t('of.category')}</dt><dd>{L(o.category_en, o.category_ar)}</dd></div>
            {o.gross != null && <div><dt>{t('of.gross')}</dt><dd><b className="num">OMR {OMR(o.gross)}</b><span className="sub">{o.lines.map((l) => `${L(l.name_en, l.name_ar)} ${OMR(l.amount)}`).join(' · ')}</span></dd></div>}
            {o.valid_until && <div><dt>{t('of.valid_until')}</dt><dd className="num">{fmtDate(o.valid_until)}</dd></div>}
          </dl>
          {o.benefits && <p style={{ margin: 0 }}>{o.benefits}</p>}
          <div className="muted">{t('of.prepared_by', { n: o.prepared_by_name ?? '' })}{o.approved_by_name ? ` · ${t('of.approved_by', { n: o.approved_by_name })}` : ''}
            {o.decision_note ? ` — ${o.decision_note}` : ''}{o.response_note ? ` · ${o.response_note}` : ''}</div>
        </div>))}
      {confirm.node}
    </section>
  );
}

function Checklist({ tasks, refresh, canManage }: { tasks: OnboardingTask[]; refresh: (x: Application | null | undefined) => void; canManage: boolean }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const done = tasks.filter((x) => x.status !== 'PENDING').length;
  const set = async (task: OnboardingTask, status: OnboardingTask['status']) => {
    let note: string | null = null;
    if (status === 'NOT_NEEDED') {
      note = await confirm.ask({ title: `${t('ob.not_needed')} — ${L(task.title_en, task.title_ar)}`, reason: 'required', reasonLabel: t('ob.why_not') });
      if (note === null) return;
    }
    refresh(await run(() => recapi.setTask(task.id, status, note)));
  };
  return (
    <section className="panel">
      <div className="panel-head"><h2>{t('ob.title')}</h2><span className="muted">{t('ob.progress', { d: done, t: tasks.length })}</span></div>
      <ul className="plain panel-pad checklist">{tasks.map((x) => (
        <li key={x.id} className={`check-item${x.status !== 'PENDING' ? ' is-done' : ''}`}>
          <span className="check-mark" aria-hidden="true">{x.status === 'DONE' ? '✓' : x.status === 'NOT_NEEDED' ? '–' : '○'}</span>
          <span className="check-text"><b>{L(x.title_en, x.title_ar)}</b>
            <span className="sub">{x.due_date && <span className={x.overdue ? 'bad-text num' : 'num'}>{t('ob.due')} {fmtDate(x.due_date)}</span>}
              {x.status !== 'PENDING' && <> · {t(`ob.st_${x.status}` as Key)} · {x.done_by_name} {fmtDate(x.done_at)}</>}{x.note ? ` · ${x.note}` : ''}</span></span>
          {canManage && <span className="row" style={{ gap: 4 }}>
            {x.status === 'PENDING' ? <><Button small kind="primary" busy={busy} onClick={() => void set(x, 'DONE')}>{t('ob.done')}</Button>
              <Button small busy={busy} onClick={() => void set(x, 'NOT_NEEDED')}>{t('ob.not_needed')}</Button></>
              : <Button small busy={busy} onClick={() => void set(x, 'PENDING')}>{t('ob.reopen')}</Button>}
          </span>}
        </li>))}
      </ul>
      {confirm.node}
    </section>
  );
}

function ScheduleDialog({ open, appId, onClose, onDone }: { open: boolean; appId: string; onClose: () => void; onDone: (a: Application | null | undefined) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ when: '', mode: 'IN_PERSON', location: '', interviewer_id: '' });
  useEffect(() => { if (open) setF({ when: `${addDays(todayMuscat(), 1)}T10:00`, mode: 'IN_PERSON', location: '', interviewer_id: '' }); }, [open]);
  const submit = async () => {
    const r = await run(() => recapi.scheduleInterview({ application_id: appId, scheduled_at: `${f.when}:00+04:00`, mode: f.mode, location: f.location, interviewer_id: f.interviewer_id }));
    if (r) { onDone(r); onClose(); }
  };
  return (
    <Modal open={open} title={t('iv.schedule')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.when || !f.interviewer_id} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="form-grid">
        <Input label={t('iv.when')} type="datetime-local" ltr required value={f.when} onChange={(e) => setF({ ...f, when: e.target.value })} />
        <Select label={t('iv.mode')} value={f.mode} onChange={(e) => setF({ ...f, mode: e.target.value })}>
          {['IN_PERSON', 'PHONE', 'VIDEO'].map((m) => <option key={m} value={m}>{t(`iv.m_${m}` as Key)}</option>)}
        </Select>
        <InterviewerSelect label={t('iv.interviewer')} value={f.interviewer_id} onChange={(v) => setF({ ...f, interviewer_id: v })} />
        <Input label={t('iv.location')} value={f.location} onChange={(e) => setF({ ...f, location: e.target.value })} />
      </div>
    </Modal>
  );
}

function RecordDialog({ i, onClose, onDone }: { i: Interview | null; onClose: () => void; onDone: (a: Application | null | undefined) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ status: 'DONE', rating: '', recommendation: '', feedback: '' });
  useEffect(() => { if (i) setF({ status: 'DONE', rating: '', recommendation: '', feedback: '' }); }, [i]);
  const ok = f.status === 'NO_SHOW' || (f.rating && f.recommendation && f.feedback.trim().length >= 10);
  const submit = async () => {
    if (!i) return;
    const r = await run(() => recapi.recordInterview(i.id, { status: f.status, rating: f.rating, recommendation: f.recommendation, feedback: f.feedback }));
    if (r) { onDone(r); onClose(); }
  };
  return (
    <Modal open={!!i} title={t('iv.record')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!ok} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <Check label={t('iv.no_show')} checked={f.status === 'NO_SHOW'} onChange={(v) => setF({ ...f, status: v ? 'NO_SHOW' : 'DONE' })} />
        {f.status === 'DONE' && <>
          <fieldset className="choice-list"><legend>{t('iv.rating')}</legend>
            <div className="row" style={{ gap: 6 }}>{[1, 2, 3, 4, 5].map((n) => (
              <label key={n} className={`choice${f.rating === String(n) ? ' on' : ''}`} style={{ minWidth: 48, justifyContent: 'center' }}>
                <input type="radio" name="rating" checked={f.rating === String(n)} onChange={() => setF({ ...f, rating: String(n) })} /><span className="num">{n}</span>
              </label>))}</div>
          </fieldset>
          <Select label={t('iv.recommendation')} value={f.recommendation} onChange={(e) => setF({ ...f, recommendation: e.target.value })}>
            <option value="">{t('c.select')}</option>{['HIRE', 'MAYBE', 'NO'].map((r) => <option key={r} value={r}>{t(`iv.r_${r}` as Key)}</option>)}
          </Select>
        </>}
        <Textarea label={t('iv.feedback')} required={f.status === 'DONE'} value={f.feedback} onChange={(e) => setF({ ...f, feedback: e.target.value })} />
      </div>
    </Modal>
  );
}

function OfferDialog({ open, a, edit, onClose, onDone }: { open: boolean; a: Application; edit: Offer | null; onClose: () => void; onDone: (a: Application | null | undefined) => void }) {
  const { t, L } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const { data: comps } = useAsync(() => api.listPayComponents(), []);
  const earnings = (comps ?? []).filter((c) => c.kind === 'EARNING');
  const r = a.requisition;
  const init = () => ({
    start_date: edit?.start_date ?? addDays(todayMuscat(), 30), category_id: edit?.category_id ?? r.category_id, grade_id: edit?.grade_id ?? r.grade_id,
    location_id: edit?.location_id ?? r.location_id, contract_type: edit?.contract_type ?? 'FIXED_TERM', contract_months: String(edit?.contract_months ?? 24),
    probation_months: String(edit?.probation_months ?? (a.prior_employee_id ? 0 : a.probation_max_months)), notice_days: String(edit?.notice_days ?? 30),
    benefits: edit?.benefits ?? '', valid_until: edit?.valid_until ?? addDays(todayMuscat(), 14),
    lines: Object.fromEntries((edit?.lines ?? []).map((l) => [l.code, String(l.amount)])) as Record<string, string> });
  const [f, setF] = useState(init);
  useEffect(() => { if (open) setF(init()); }, [open]);
  const lines = offerLines(earnings.map((c) => ({ code: c.code, amount: f.lines[c.code] ?? '' })));
  const gross = lines.reduce((s, l) => s + Number(l.amount), 0);
  const basicOk = lines.some((l) => earnings.find((c) => c.code === l.code)?.is_basic);
  const submit = async () => {
    const res = await run(() => recapi.saveOffer({ id: edit?.id ?? null, application_id: a.id, start_date: f.start_date, category_id: f.category_id, grade_id: f.grade_id,
      location_id: f.location_id, contract_type: f.contract_type, contract_months: f.contract_type === 'FIXED_TERM' ? f.contract_months : null,
      probation_months: f.probation_months, notice_days: f.notice_days, benefits: f.benefits, valid_until: f.valid_until || null, lines }));
    if (res) { push(t('of.saved')); onDone(res); onClose(); }
  };
  return (
    <Modal open={open} title={`${edit ? t('of.edit') : t('of.new')} — ${L(a.full_name_en, a.full_name_ar)}`} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!basicOk || !f.start_date || !f.category_id} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="form-grid">
          <Input label={t('of.start')} type="date" ltr required value={f.start_date} min={todayMuscat()} onChange={(e) => setF({ ...f, start_date: e.target.value })} />
          <MasterSelect kind="category" entityId={r.entity_id} label={t('of.category')} required value={f.category_id} onChange={(v) => setF({ ...f, category_id: v })} />
          <MasterSelect kind="grade" entityId={r.entity_id} label={t('of.grade')} value={f.grade_id} onChange={(v) => setF({ ...f, grade_id: v })} />
          <MasterSelect kind="location" entityId={r.entity_id} label={t('of.location')} value={f.location_id} onChange={(v) => setF({ ...f, location_id: v })} />
          <Select label={t('of.contract')} value={f.contract_type} onChange={(e) => setF({ ...f, contract_type: e.target.value as typeof f.contract_type })}>
            <option value="FIXED_TERM">{t('of.c_FIXED_TERM')}</option><option value="INDEFINITE">{t('of.c_INDEFINITE')}</option>
          </Select>
          {f.contract_type === 'FIXED_TERM' && <Input label={t('of.months')} type="number" min={1} max={60} value={f.contract_months} onChange={(e) => setF({ ...f, contract_months: e.target.value })} />}
          <Input label={t('of.probation')} type="number" min={0} max={a.prior_employee_id ? 0 : a.probation_max_months} value={f.probation_months}
            hint={a.prior_employee_id ? t('cd.prior') : t('of.probation_max', { n: a.probation_max_months })} onChange={(e) => setF({ ...f, probation_months: e.target.value })} />
          <Input label={t('of.notice')} type="number" min={0} max={180} value={f.notice_days} onChange={(e) => setF({ ...f, notice_days: e.target.value })} />
          <Input label={t('of.valid_until')} type="date" ltr value={f.valid_until} onChange={(e) => setF({ ...f, valid_until: e.target.value })} />
        </div>
        <fieldset className="contact-box"><legend>{t('of.salary')}</legend>
          <div className="form-grid">{earnings.map((c) => (
            <Input key={c.code} label={`${L(c.name_en, c.name_ar)}${c.is_basic ? ' *' : ''}`} ltr inputMode="decimal" value={f.lines[c.code] ?? ''}
              onChange={(e) => setF({ ...f, lines: { ...f.lines, [c.code]: e.target.value } })} />))}</div>
          <div><b>{t('of.gross')}: <span className="num">OMR {OMR(gross)}</span></b>
            {r.salary_min != null && r.salary_max != null && <span className="muted"> · {t('rq2.salary_range')}: {OMR(r.salary_min)} – {OMR(r.salary_max)}</span>}</div>
        </fieldset>
        <Textarea label={t('of.benefits')} placeholder={t('of.benefits_ph')} value={f.benefits} onChange={(e) => setF({ ...f, benefits: e.target.value })} />
      </div>
    </Modal>
  );
}

function HireDialog({ open, a, offer, onClose, onDone }: { open: boolean; a: Application; offer: Offer; onClose: () => void; onDone: (a: Application | null | undefined) => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { can } = useSession();
  const { busy, run } = useAction();
  const [f, setF] = useState({ manager_id: null as string | null, employee_no: '', work_email: '', shift_code: '', exception_reason: '', confirm_duplicate: false });
  useEffect(() => { if (open) setF({ manager_id: null, employee_no: '', work_email: '', shift_code: '', exception_reason: '', confirm_duplicate: false }); }, [open]);
  const submit = async () => {
    const r = await run(() => recapi.hire(offer.id, { ...f }));
    if (r) { push(t('hr2.done', { n: r.employee_no ?? '' })); onDone(r); onClose(); }
  };
  return (
    <Modal open={open} title={t('hr2.hire_title')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void submit()}>{t('hr2.hire')}</Button></>}>
      <div className="stack">
        <p className="muted" style={{ margin: 0 }}>{t('hr2.hint')}</p>
        <div className="form-grid">
          <EmployeePicker label={t('hr2.manager')} value={f.manager_id} onChange={(v) => setF({ ...f, manager_id: v })} />
          <Input label={t('hr2.employee_no')} ltr value={f.employee_no} onChange={(e) => setF({ ...f, employee_no: e.target.value.toUpperCase() })} />
          <Input label={t('hr2.work_email')} type="email" ltr value={f.work_email} onChange={(e) => setF({ ...f, work_email: e.target.value })} />
          <Input label={t('hr2.shift')} ltr value={f.shift_code} onChange={(e) => setF({ ...f, shift_code: e.target.value })} />
        </div>
        {a.requisition.job_omani_only && !a.is_omani && can('EXCEPTION_APPROVE') &&
          <Textarea label={t('hr2.exception')} value={f.exception_reason} onChange={(e) => setF({ ...f, exception_reason: e.target.value })} />}
        <Check label={t('hr2.duplicate')} checked={f.confirm_duplicate} onChange={(v) => setF({ ...f, confirm_duplicate: v })} />
      </div>
    </Modal>
  );
}
