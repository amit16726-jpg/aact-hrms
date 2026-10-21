import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { goalsRating, wfapi, type Goal, type PerfReview } from '../../lib/api_wf';
import { useI18n } from '../../i18n';
import { useSession } from '../../lib/session';
import { Button, ErrorNote, Loading, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { PlanBadge, RatingSelect, ReviewBadge, ReviewSteps } from '../../components/wf';
import { fmtDate } from '../../lib/format';
import { PlanDialog } from './PerformancePage';

export default function ReviewPage() {
  const { id = '' } = useParams();
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data: r, error, loading, reload, setData } = useAsync(() => wfapi.getReview(id), [id]);
  const [goals, setGoals] = useState<Goal[]>([]);
  const [f, setF] = useState({ self_comments: '', manager_comments: '', hr_comments: '', employee_comment: '' });
  const [plan, setPlan] = useState(false);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  useEffect(() => {
    if (!r) return;
    setGoals(r.goals.map((g) => ({ ...g, weight: g.weight ?? 1 })));
    setF({ self_comments: r.self_comments ?? '', manager_comments: r.manager_comments ?? '', hr_comments: r.hr_comments ?? '', employee_comment: r.employee_comment ?? '' });
  }, [r]);
  if (loading && !r) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!r) return null;

  const editSelf = r.can_self; const editMgr = r.can_manager && !r.is_mine;
  const editable = editSelf || editMgr;
  const setGoal = (i: number, patch: Partial<Goal>) => setGoals(goals.map((g, j) => (j === i ? { ...g, ...patch } : g)));
  const save = async (step: 'SELF' | 'MANAGER' | 'FINALISE' | 'RETURN' | 'ACK', submit: boolean) => {
    if (submit && step !== 'ACK') {
      const ok = await confirm.ask({ title: t(step === 'FINALISE' ? 'pf.finalise' : step === 'RETURN' ? 'pf.return' : 'pf.submit'), body: step === 'MANAGER' ? `${t('pf.overall')}: ${goalsRating(goals) ?? '—'}` : undefined });
      if (ok === null) return;
    }
    const p = step === 'SELF' ? { step, submit, goals, self_comments: f.self_comments || null }
      : step === 'MANAGER' ? { step, submit, goals, manager_comments: f.manager_comments || null }
      : step === 'ACK' ? { step, employee_comment: f.employee_comment || null }
      : { step, hr_comments: f.hr_comments || null };
    const x = await run(() => wfapi.saveReview(r.id, p), t(step === 'ACK' ? 'pf.acked' : submit || step === 'FINALISE' || step === 'RETURN' ? 'pf.submitted' : 'pf.saved'));
    if (x) setData(x);
  };
  const live = editMgr ? goalsRating(goals) : r.overall_rating;

  return (
    <div className="stack">
      <PageHead title={<>{L(r.full_name_en, r.full_name_ar)} <span className="muted num">{r.employee_no}</span></>}
        sub={<>{r.cycle_name} · <span className="num">{fmtDate(r.period_start)} – {fmtDate(r.period_end)}</span> · <ReviewBadge s={r.status} /></>}
        actions={<Link className="btn" to={r.is_mine ? '/performance?tab=mine' : '/performance'}>{t('c.back')}</Link>} />
      <section className="panel panel-pad stack">
        <ReviewSteps s={r.status} />
        <dl className="kv">
          <div><dt>{t('pf.reviewer')}</dt><dd>{L(r.reviewer_en, r.reviewer_ar) || '—'}</dd></div>
          <div><dt>{t('pf.due')}</dt><dd className="num">{fmtDate(r.due_date)}</dd></div>
          <div><dt>{t('pf.overall')}</dt><dd className="num">{live ?? '—'}</dd></div>
        </dl>
        <div className="muted">{t('pf.scale')}</div>
      </section>

      <section className="panel">
        <div className="panel-head"><h2>{t('pf.goal')}</h2></div>
        <div className="table-wrap"><table className="t cards goals-table">
          <thead><tr><th>{t('pf.goal')}</th><th className="r">{t('pf.weight')}</th><th>{t('pf.self_rating')}</th><th>{t('pf.mgr_rating')}</th><th>{t('pf.comment')}</th>{editMgr && <th />}</tr></thead>
          <tbody>{goals.map((g, i) => (
            <tr key={i}>
              <td data-label={t('pf.goal')}>{editMgr ? <input className="input" aria-label={t('pf.goal')} value={g.title} onChange={(e) => setGoal(i, { title: e.target.value })} /> : <b>{g.title}</b>}</td>
              <td data-label={t('pf.weight')} className="r">{editMgr ? <input className="input ltr" type="number" min={0} step="0.5" style={{ width: 70 }} aria-label={t('pf.weight')}
                value={g.weight ?? ''} onChange={(e) => setGoal(i, { weight: e.target.value })} /> : <span className="num">{g.weight ?? 1}</span>}</td>
              <td data-label={t('pf.self_rating')}>{editSelf ? <RatingSelect label={`${t('pf.self_rating')} — ${g.title}`} value={g.self_rating} onChange={(v) => setGoal(i, { self_rating: v })} />
                : <span className="num">{g.self_rating ?? '—'}</span>}</td>
              <td data-label={t('pf.mgr_rating')}>{editMgr ? <RatingSelect label={`${t('pf.mgr_rating')} — ${g.title}`} value={g.rating} onChange={(v) => setGoal(i, { rating: v })} />
                : <span className="num">{g.rating ?? '—'}</span>}</td>
              <td data-label={t('pf.comment')}>{editMgr ? <input className="input" aria-label={t('pf.comment')} value={g.comment ?? ''} onChange={(e) => setGoal(i, { comment: e.target.value })} />
                : <span className="wrap-text">{g.comment ?? ''}</span>}</td>
              {editMgr && <td className="r"><Button small kind="ghost" aria-label={t('c.remove')} onClick={() => setGoals(goals.filter((_, j) => j !== i))}>✕</Button></td>}
            </tr>))}
          </tbody></table></div>
        {editMgr && <div className="panel-pad"><Button small onClick={() => setGoals([...goals, { title: '', weight: 1 }])}>{t('pf.add_goal')}</Button></div>}
      </section>

      <section className="panel panel-pad stack">
        {editSelf ? <Textarea label={t('pf.self_comments')} value={f.self_comments} onChange={(e) => setF({ ...f, self_comments: e.target.value })} />
          : r.self_comments && <div><b>{t('pf.self_comments')}</b><p className="quote">{r.self_comments}</p></div>}
        {editMgr ? <Textarea label={t('pf.manager_comments')} required value={f.manager_comments} onChange={(e) => setF({ ...f, manager_comments: e.target.value })} />
          : r.manager_comments && <div><b>{t('pf.manager_comments')}</b><p className="quote">{r.manager_comments}</p></div>}
        {r.can_finalise ? <Textarea label={t('pf.hr_comments')} value={f.hr_comments} onChange={(e) => setF({ ...f, hr_comments: e.target.value })} />
          : r.hr_comments && <div><b>{t('pf.hr_comments')}</b><p className="quote">{r.hr_comments}</p></div>}
        {r.can_ack ? <><div className="note">{t('pf.ack_hint')}</div>
          <Textarea label={t('pf.employee_comment')} value={f.employee_comment} onChange={(e) => setF({ ...f, employee_comment: e.target.value })} /></>
          : r.employee_comment && <div><b>{t('pf.employee_comment')}</b><p className="quote">{r.employee_comment}</p></div>}
        <div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          {editable && <Button busy={busy} onClick={() => void save(editSelf ? 'SELF' : 'MANAGER', false)}>{t('pf.save_draft')}</Button>}
          {editable && <Button kind="primary" busy={busy} disabled={editMgr && (goals.length === 0 || goals.some((g) => !g.rating) || f.manager_comments.trim().length < 10)}
            onClick={() => void save(editSelf ? 'SELF' : 'MANAGER', true)}>{t('pf.submit')}</Button>}
          {r.can_finalise && <><Button kind="primary" busy={busy} onClick={() => void save('FINALISE', true)}>{t('pf.finalise')}</Button>
            <Button busy={busy} onClick={() => void save('RETURN', true)}>{t('pf.return')}</Button></>}
          {r.can_ack && <Button kind="primary" busy={busy} onClick={() => void save('ACK', true)}>{t('pf.ack')}</Button>}
          {!r.is_mine && (can('PERF_MANAGE') || r.is_reviewer) && <Button onClick={() => setPlan(true)}>{t('pf.issue_plan')}</Button>}
        </div>
      </section>

      {(r.plans ?? []).length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('ip.title')}</h2></div>
          <div className="panel-pad stack">{(r.plans ?? []).map((p) => (
            <div key={p.id}><PlanBadge s={p.status} /> <span className="num">{fmtDate(p.issued_on)} – {fmtDate(p.ends_on)}</span><p className="quote">{p.areas}</p></div>))}
          </div>
        </section>)}
      <PlanDialog open={plan} review={r as PerfReview} onClose={() => setPlan(false)} onDone={() => { setPlan(false); void reload(); }} />
      {confirm.node}
    </div>
  );
}
