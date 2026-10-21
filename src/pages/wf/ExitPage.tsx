import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { addMonthsIso, exitProgress, wfapi, type ExitCase, type ExitTask } from '../../lib/api_wf';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, ErrorNote, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { ExitBadge } from '../../components/wf';
import { OMR } from '../../components/pay';
import { fmtDate, fmtDateTime, todayMuscat } from '../../lib/format';

const REASONS = ['SALARY', 'CAREER', 'FAMILY', 'MANAGER', 'WORKLOAD', 'RELOCATION', 'HEALTH', 'OTHER'] as const;

export default function ExitPage() {
  const { id = '' } = useParams();
  const { t, L, tk } = useI18n();
  const { can } = useSession();
  const { data: x, error, loading, reload, setData } = useAsync(() => wfapi.getExit(id), [id]);
  const [iv, setIv] = useState(false);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  if (loading && !x) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!x) return null;
  const tasks = x.tasks ?? [];
  const prog = exitProgress(tasks);
  const setTask = async (task: ExitTask, status: ExitTask['status']) => {
    let note: string | null = null;
    if (status === 'NOT_NEEDED') {
      const n = await confirm.ask({ title: L(task.title_en, task.title_ar), reason: 'required', reasonLabel: t('ex.why_not_needed') });
      if (n === null) return;
      note = n;
    }
    const r = await run(() => wfapi.exitTask(task.id, status, note));
    if (r) setData(r);
  };
  const complete = async () => {
    if ((await confirm.ask({ title: t('ex.complete'), body: t('ex.complete_q', { d: fmtDate(x.last_working_date) }) })) === null) return;
    const r = await run(() => wfapi.completeExit(x.id), t('ex.completed'));
    if (r) setData(r);
  };
  const cancel = async () => {
    const reason = await confirm.ask({ title: t('ex.cancel'), body: t('ex.cancel_hint'), reason: 'required', danger: true });
    if (reason === null) return;
    const r = await run(() => wfapi.cancelExit(x.id, reason), t('c.saved'));
    if (r) setData(r);
  };
  const lastPassed = x.last_working_date <= todayMuscat();
  return (
    <div className="stack">
      <PageHead title={<>{L(x.full_name_en, x.full_name_ar)} <span className="muted num">{x.employee_no}</span></>}
        sub={<>{t(`ex.t_${x.exit_type}` as Key)} · {t('ex.last_day')} <span className="num">{fmtDate(x.last_working_date)}</span> · <ExitBadge s={x.status} /></>}
        actions={<div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          {x.can_manage && <Button kind="primary" busy={busy} disabled={prog.done < prog.total || !lastPassed} onClick={() => void complete()}>{t('ex.complete')}</Button>}
          {x.can_manage && <Button kind="danger" busy={busy} onClick={() => void cancel()}>{t('ex.cancel')}</Button>}
          <Link className="btn" to="/exits">{t('c.back')}</Link>
        </div>} />
      <div className="grid-2" style={{ alignItems: 'start' }}>
        <section className="panel panel-pad stack">
          <dl className="kv">
            <div><dt>{t('c.status')}</dt><dd>{tk(`st.${x.employee_status}`, x.employee_status)}</dd></div>
            <div><dt>{t('ex.notice_given')}</dt><dd className="num">{fmtDate(x.notice_given_on)}</dd></div>
            <div><dt>{t('ex.notice')}</dt><dd className="num">{x.notice_days} / {x.min_notice_days}{x.pay_in_lieu && <span className="sub">{t('ex.pay_in_lieu')}</span>}</dd></div>
            <div><dt>{t('ex.nc')}</dt><dd className="num">{x.non_compete_months
              ? <>{x.non_compete_months} · {fmtDate(x.last_working_date)} – {fmtDate(addMonthsIso(x.last_working_date, x.non_compete_months))}</> : '—'}</dd></div>
          </dl>
          {x.reason && <p className="quote">{x.reason}</p>}
          {x.cancel_reason && <div className="note note-warn">{t('ex.st_CANCELLED')}: {x.cancel_reason}</div>}
          {x.completed_at && <div className="muted">{t('ex.st_COMPLETED')} · {x.completed_by_name} · {fmtDateTime(x.completed_at)}</div>}
        </section>
        <section className="panel panel-pad stack">
          <h2 style={{ margin: 0 }}>{t('ex.settlement')}</h2>
          {x.settlement ? <div><Badge tone={x.settlement.status === 'APPROVED' || x.settlement.status === 'PAID' ? 'ok' : 'warn'}>{tk(`st.st_${x.settlement.status}`, x.settlement.status)}</Badge>
            {' '}<b className="num">OMR {OMR(x.settlement.net)}</b>{can('PAY_READ') && <> · <Link to={`/payroll/settlements/${x.settlement.id}`}>{t('sap.open')}</Link></>}</div>
            : <div className="muted">—{can('PAY_READ') && <> · <Link to="/payroll/settlements">{t('ex.prepare_settlement')}</Link></>}</div>}
          <h2 style={{ margin: 0 }}>{t('ex.interview')}</h2>
          {x.interview ? <div className="stack" style={{ gap: 4 }}>
            <div>{x.interview.reason_code ? t(`ex.r_${x.interview.reason_code}` as Key) : '—'} · {t('ex.rating')}: <span className="num">{x.interview.rating ?? '—'}</span>
              {x.interview.would_return && <> · {t('ex.would_return')}</>}</div>
            {x.interview.comments && <p className="quote">{x.interview.comments}</p>}
            <div className="muted">{x.interview.recorded_by} · {fmtDateTime(x.interview.recorded_at)}</div>
          </div> : <div className="muted">—</div>}
          {x.can_manage && <div><Button small onClick={() => setIv(true)}>{t('ex.record_interview')}</Button></div>}
        </section>
      </div>
      <section className="panel">
        <div className="panel-head"><h2>{t('ex.clearance')} <span className="muted num">{t('ex.steps', { d: prog.done, n: prog.total })}</span></h2>
          <progress max={Math.max(prog.total, 1)} value={prog.done} aria-label={t('ex.steps', { d: prog.done, n: prog.total })} /></div>
        <ul className="plain panel-pad checklist">{tasks.map((task) => (
          <li key={task.id} className={`check-item${task.status !== 'PENDING' ? ' is-done' : ''}`}>
            <span className="check-mark" aria-hidden="true">{task.status === 'DONE' ? '✓' : task.status === 'NOT_NEEDED' ? '–' : '○'}</span>
            <span className="check-text"><b>{L(task.title_en, task.title_ar)}</b>
              <span className="sub">{task.status !== 'PENDING' && <>{t(task.status === 'DONE' ? 'ex.done' : 'ex.not_needed')} · {task.done_by_name} {fmtDate(task.done_at)}</>}
                {task.note ? ` · ${task.note}` : ''}
                {task.status === 'PENDING' && task.ref_id && task.code.startsWith('ASSET_') && <Link to="/assets">{t('ex.asset_hint')}</Link>}</span></span>
            {x.can_manage && <span className="row" style={{ gap: 4 }}>
              {task.status === 'PENDING' ? <>
                {!task.code.startsWith('ASSET_') && <Button small kind="primary" busy={busy} onClick={() => void setTask(task, 'DONE')}>{t('ex.done')}</Button>}
                <Button small busy={busy} onClick={() => void setTask(task, 'NOT_NEEDED')}>{t('ex.not_needed')}</Button></>
                : <Button small busy={busy} onClick={() => void setTask(task, 'PENDING')}>{t('ex.reopen')}</Button>}
            </span>}
          </li>))}
        </ul>
      </section>
      <InterviewDialog open={iv} x={x} onClose={() => setIv(false)} onDone={(r) => { setIv(false); setData(r); }} />
      {confirm.node}
    </div>
  );
}

function InterviewDialog({ open, x, onClose, onDone }: { open: boolean; x: ExitCase; onClose: () => void; onDone: (r: ExitCase) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ reason_code: '', would_return: false, rating: '', comments: '' });
  useEffect(() => {
    if (open) setF({ reason_code: x.interview?.reason_code ?? '', would_return: x.interview?.would_return ?? false, rating: x.interview?.rating ? String(x.interview.rating) : '', comments: x.interview?.comments ?? '' });
  }, [open, x]);
  const submit = async () => {
    const r = await run(() => wfapi.exitInterview(x.id, { reason_code: f.reason_code || null, would_return: f.would_return, rating: f.rating ? Number(f.rating) : null, comments: f.comments || null }), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={open} title={t('ex.record_interview')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="grid-2">
          <Select label={t('ex.reason_code')} value={f.reason_code} onChange={(e) => setF({ ...f, reason_code: e.target.value })}>
            <option value="">{t('c.select')}</option>
            {REASONS.map((r) => <option key={r} value={r}>{t(`ex.r_${r}` as Key)}</option>)}
          </Select>
          <Select label={t('ex.rating')} value={f.rating} onChange={(e) => setF({ ...f, rating: e.target.value })}>
            <option value="">—</option>{[1, 2, 3, 4, 5].map((n) => <option key={n} value={n}>{n}</option>)}
          </Select>
        </div>
        <Check label={t('ex.would_return')} checked={f.would_return} onChange={(v) => setF({ ...f, would_return: v })} />
        <Textarea label={t('ex.comments')} value={f.comments} onChange={(e) => setF({ ...f, comments: e.target.value })} />
      </div>
    </Modal>
  );
}
