import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { addMonthsIso, wfapi, type PerfCycle, type PerfPlan, type PerfReview } from '../../lib/api_wf';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { EntitySelect, EmpCell, useEntity } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { PlanBadge, ReviewBadge } from '../../components/wf';
import { fmtDate, todayMuscat } from '../../lib/format';

type Tab = 'mine' | 'team' | 'all' | 'cycles' | 'plans';

export default function PerformancePage() {
  const { t } = useI18n();
  const { can, me } = useSession();
  const [sp, setSp] = useSearchParams();
  const hr = can('PERF_MANAGE');
  const tabs: { id: Tab; label: string }[] = [
    ...(me?.employee_id ? [{ id: 'mine' as Tab, label: t('pf.tab_mine') }] : []),
    ...(me?.is_manager ? [{ id: 'team' as Tab, label: t('pf.tab_team') }] : []),
    ...(hr ? [{ id: 'all' as Tab, label: t('pf.tab_all') }, { id: 'cycles' as Tab, label: t('pf.tab_cycles') }] : []),
    { id: 'plans', label: t('pf.tab_plans') }];
  const tab = (tabs.some((x) => x.id === sp.get('tab')) ? sp.get('tab') : tabs[0].id) as Tab;
  return (
    <div className="stack">
      <PageHead title={t('pf.title')} sub={t('pf.hint')} />
      <Tabs label={t('pf.title')} value={tab} onChange={(v) => setSp({ tab: v }, { replace: true })} tabs={tabs} />
      {(tab === 'mine' || tab === 'team' || tab === 'all') && <Reviews scope={tab} />}
      {tab === 'cycles' && <Cycles />}
      {tab === 'plans' && <Plans />}
    </div>
  );
}

// ---------------------------------------------------------------------------
function Reviews({ scope }: { scope: 'mine' | 'team' | 'all' }) {
  const { t, L } = useI18n();
  const cycles = useAsync(() => (scope === 'all' ? wfapi.listCycles() : Promise.resolve([] as PerfCycle[])), [scope]);
  const [cycle, setCycle] = useState('');
  const { data, error, loading, reload } = useAsync(() => wfapi.listReviews({ scope, cycle_id: cycle || null }), [scope, cycle]);
  return (
    <>
      {scope === 'all' && (cycles.data ?? []).length > 0 && (
        <div className="panel panel-pad row">
          <div className="field" style={{ minWidth: 240 }}><label htmlFor="pf-cy">{t('pf.cycle')}</label>
            <select id="pf-cy" className="select" value={cycle} onChange={(e) => setCycle(e.target.value)}>
              <option value="">{t('c.all')}</option>
              {(cycles.data ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select></div>
        </div>)}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('pf.none_reviews')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr>{scope !== 'mine' && <th>{t('c.employee')}</th>}<th>{t('pf.cycle')}</th><th>{t('pf.reviewer')}</th><th>{t('c.status')}</th><th className="r">{t('pf.rating')}</th><th /></tr></thead>
            <tbody>{data.map((r) => (
              <tr key={r.id}>
                {scope !== 'mine' && <td data-label={t('c.employee')}><EmpCell r={r} /></td>}
                <td data-label={t('pf.cycle')}>{r.cycle_name}<span className="sub num">{fmtDate(r.period_start)} – {fmtDate(r.period_end)}</span></td>
                <td data-label={t('pf.reviewer')}>{L(r.reviewer_en, r.reviewer_ar) || '—'}</td>
                <td data-label={t('c.status')}><ReviewBadge s={r.status} />{r.due_date && r.status !== 'DONE' && <span className="sub">{t('pf.due')} {fmtDate(r.due_date)}</span>}</td>
                <td data-label={t('pf.rating')} className="r num">{r.overall_rating ?? '—'}</td>
                <td className="r"><Link className={`btn btn-sm${r.can_self || r.can_manager || r.can_finalise || r.can_ack ? ' btn-primary' : ''}`} to={`/performance/review/${r.id}`}>{t('sap.open')}</Link></td>
              </tr>))}
            </tbody></table></div>)}
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------
function Cycles() {
  const { t } = useI18n();
  const { data, error, loading, reload, setData } = useAsync(() => wfapi.listCycles(), []);
  const [edit, setEdit] = useState<PerfCycle | 'new' | null>(null);
  const [opening, setOpening] = useState<PerfCycle | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const close = async (c: PerfCycle) => {
    if ((await confirm.ask({ title: `${t('pf.close')} — ${c.name}`, body: t('pf.close_q') })) === null) return;
    const r = await run(() => wfapi.closeCycle(c.id));
    if (r) setData(r);
  };
  return (
    <>
      <div className="row" style={{ justifyContent: 'flex-end' }}><Button kind="primary" onClick={() => setEdit('new')}>{t('pf.new_cycle')}</Button></div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('pf.none_cycles')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('pf.name')}</th><th>{t('pf.period')}</th><th>{t('c.status')}</th><th>{t('pf.st_DONE')}</th><th className="r">{t('pf.avg')}</th><th /></tr></thead>
            <tbody>{data.map((c) => (
              <tr key={c.id}>
                <td data-label={t('pf.name')}><b>{c.name}</b><span className="sub">{c.entity_code}{c.due_date ? ` · ${t('pf.due')} ${fmtDate(c.due_date)}` : ''}</span></td>
                <td data-label={t('pf.period')} className="num">{fmtDate(c.period_start)} – {fmtDate(c.period_end)}</td>
                <td data-label={t('c.status')}><Badge tone={c.status === 'OPEN' ? 'warn' : c.status === 'CLOSED' ? 'ok' : undefined}>{t(`pf.cst_${c.status}` as Key)}</Badge></td>
                <td data-label={t('pf.rating')}>{c.status !== 'DRAFT' && <><span className="num">{t('pf.reviews_n', { d: c.done, n: c.reviews })}</span>
                  <progress max={Math.max(c.reviews, 1)} value={c.done} aria-label={t('pf.reviews_n', { d: c.done, n: c.reviews })} /></>}</td>
                <td data-label={t('pf.avg')} className="r num">{c.avg_rating ?? '—'}</td>
                <td className="r"><div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  {c.status === 'DRAFT' && <><Button small onClick={() => setEdit(c)}>{t('c.edit')}</Button><Button small kind="primary" onClick={() => setOpening(c)}>{t('pf.open')}</Button></>}
                  {c.status === 'OPEN' && <Button small busy={busy} onClick={() => void close(c)}>{t('pf.close')}</Button>}
                </div></td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <CycleDialog edit={edit} onClose={() => setEdit(null)} onDone={(r) => { setData(r); setEdit(null); }} />
      <OpenDialog c={opening} onClose={() => setOpening(null)} onDone={(r) => { setData(r); setOpening(null); }} />
      {confirm.node}
    </>
  );
}

function CycleDialog({ edit, onClose, onDone }: { edit: PerfCycle | 'new' | null; onClose: () => void; onDone: (r: PerfCycle[]) => void }) {
  const { t } = useI18n();
  const [entity, setEntity] = useEntity();
  const { busy, run } = useAction();
  const blank = () => { const y = todayMuscat().slice(0, 4); return { name: `${y} annual review`, period_start: `${y}-01-01`, period_end: `${y}-12-31`, due_date: '', self_review: true }; };
  const [f, setF] = useState(blank);
  useEffect(() => {
    if (edit === 'new') setF(blank());
    else if (edit) setF({ name: edit.name, period_start: edit.period_start, period_end: edit.period_end, due_date: edit.due_date ?? '', self_review: edit.self_review });
  }, [edit]);
  const save = async () => {
    const r = await run(() => wfapi.saveCycle({ ...(edit && edit !== 'new' ? { id: edit.id } : { entity_id: entity }), ...f, due_date: f.due_date || null }), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? 'pf.new_cycle' : 'pf.edit_cycle')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.name.trim() || !f.period_start || !f.period_end} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {edit === 'new' && <EntitySelect value={entity} onChange={setEntity} />}
        <Input label={t('pf.name')} required value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} />
        <div className="grid-2">
          <Input label={t('pf.from')} type="date" ltr required value={f.period_start} onChange={(e) => setF({ ...f, period_start: e.target.value })} />
          <Input label={t('pf.to')} type="date" ltr required value={f.period_end} min={f.period_start} onChange={(e) => setF({ ...f, period_end: e.target.value })} />
        </div>
        <Input label={t('pf.due')} type="date" ltr value={f.due_date} onChange={(e) => setF({ ...f, due_date: e.target.value })} />
        <Check label={t('pf.self_review')} checked={f.self_review} onChange={(v) => setF({ ...f, self_review: v })} />
      </div>
    </Modal>
  );
}

function OpenDialog({ c, onClose, onDone }: { c: PerfCycle | null; onClose: () => void; onDone: (r: PerfCycle[]) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [goals, setGoals] = useState<{ title: string; weight: string }[]>([]);
  useEffect(() => { if (c) setGoals([{ title: 'Quality and accuracy of work', weight: '1' }, { title: 'Productivity and targets', weight: '1' }, { title: 'Safety and company rules', weight: '1' }, { title: 'Teamwork and attendance', weight: '1' }]); }, [c]);
  const submit = async () => {
    if (!c) return;
    const r = await run(() => wfapi.openCycle(c.id, goals.filter((g) => g.title.trim()).map((g) => ({ title: g.title.trim(), weight: Number(g.weight) || 1 }))), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={!!c} title={`${t('pf.open_title')} — ${c?.name ?? ''}`} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void submit()}>{t('pf.open')}</Button></>}>
      <div className="stack">
        <div className="note">{t('pf.open_hint')}</div>
        <b>{t('pf.std_goals')}</b>
        {goals.map((g, i) => (
          <div key={i} style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) 80px auto', gap: 8, alignItems: 'end' }}>
            <Input label={`${t('pf.goal')} ${i + 1}`} value={g.title} onChange={(e) => setGoals(goals.map((x, j) => (j === i ? { ...x, title: e.target.value } : x)))} />
            <Input label={t('pf.weight')} type="number" min={0} step="0.5" ltr value={g.weight} onChange={(e) => setGoals(goals.map((x, j) => (j === i ? { ...x, weight: e.target.value } : x)))} />
            <Button small kind="ghost" aria-label={t('c.remove')} onClick={() => setGoals(goals.filter((_, j) => j !== i))}>✕</Button>
          </div>))}
        <div><Button small onClick={() => setGoals([...goals, { title: '', weight: '1' }])}>{t('pf.add_goal')}</Button></div>
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function Plans() {
  const { t } = useI18n();
  const { can, me } = useSession();
  const { data, error, loading, reload } = useAsync(() => wfapi.listPlans(), []);
  const [issue, setIssue] = useState(false);
  const [closing, setClosing] = useState<PerfPlan | null>(null);
  const { busy, run } = useAction();
  const ack = async (p: PerfPlan) => { if (await run(() => wfapi.ackPlan(p.id), t('c.saved'))) void reload(); };
  return (
    <>
      {(can('PERF_MANAGE') || me?.is_manager) && <div className="row" style={{ justifyContent: 'flex-end' }}><Button kind="primary" onClick={() => setIssue(true)}>{t('ip.new')}</Button></div>}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('ip.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('ip.areas')}</th><th>{t('ip.ends_on')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((p) => (
              <tr key={p.id}>
                <td data-label={t('c.employee')}><EmpCell r={p} /></td>
                <td data-label={t('ip.areas')}><span className="wrap-text">{p.areas}</span>{p.support && <span className="sub">{t('ip.support')}: {p.support}</span>}</td>
                <td data-label={t('ip.ends_on')}><span className="num">{fmtDate(p.issued_on)} – {fmtDate(p.ends_on)}</span>
                  {p.status === 'ACTIVE' && p.days_left >= 0 && <span className="sub">{t('ip.days_left', { n: p.days_left })}</span>}</td>
                <td data-label={t('c.status')}><PlanBadge s={p.status} />
                  <span className="sub">{p.acknowledged_at ? t('ip.acked', { d: fmtDate(p.acknowledged_at) }) : ''}{p.outcome_note ? ` · ${p.outcome_note}` : ''}</span></td>
                <td className="r">
                  {p.can_ack && <Button small kind="primary" busy={busy} onClick={() => void ack(p)}>{t('ip.ack')}</Button>}
                  {p.can_close && <Button small onClick={() => setClosing(p)}>{t('ip.close')}</Button>}
                </td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <PlanDialog open={issue} onClose={() => setIssue(false)} onDone={() => { setIssue(false); void reload(); }} />
      <ClosePlanDialog p={closing} onClose={() => setClosing(null)} onDone={() => { setClosing(null); void reload(); }} />
    </>
  );
}

export function PlanDialog({ open, onClose, onDone, review }: { open: boolean; onClose: () => void; onDone: () => void; review?: PerfReview | null }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const pol = useAsync(() => (open ? wfapi.policies() : Promise.resolve(null)), [open]);
  const min = pol.data?.pip_min_months ?? 6;
  const [f, setF] = useState({ employee_id: null as string | null, label: '', issued_on: '', ends_on: '', areas: '', support: '' });
  useEffect(() => {
    if (!open) return;
    const today = todayMuscat();
    setF({ employee_id: review?.employee_id ?? null, label: review ? `${review.employee_no} — ${L(review.full_name_en, review.full_name_ar)}` : '',
      issued_on: today, ends_on: addMonthsIso(today, min), areas: '', support: '' });
  }, [open, review, min, L]);
  const minEnd = f.issued_on ? addMonthsIso(f.issued_on, min) : '';
  const submit = async () => {
    if (await run(() => wfapi.issuePlan({ employee_id: f.employee_id, review_id: review?.id ?? null, issued_on: f.issued_on, ends_on: f.ends_on, areas: f.areas, support: f.support || null }), t('ip.issued'))) onDone();
  };
  return (
    <Modal open={open} title={t('ip.new')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!f.employee_id || f.areas.trim().length < 10 || !f.ends_on || f.ends_on < minEnd} onClick={() => void submit()}>{t('ip.new')}</Button></>}>
      <div className="stack">
        <div className="note note-warn">{t('ip.min_hint', { n: min })}</div>
        {review ? <div><b>{L(review.full_name_en, review.full_name_ar)}</b> <span className="muted num">{review.employee_no}</span></div>
          : <EmployeePicker label={t('c.employee')} value={f.employee_id} valueLabel={f.label} onChange={(id, l) => setF({ ...f, employee_id: id, label: l ?? '' })} />}
        <div className="grid-2">
          <Input label={t('ip.issued_on')} type="date" ltr value={f.issued_on} onChange={(e) => setF({ ...f, issued_on: e.target.value, ends_on: e.target.value ? addMonthsIso(e.target.value, min) : f.ends_on })} />
          <Input label={t('ip.ends_on')} type="date" ltr value={f.ends_on} min={minEnd} onChange={(e) => setF({ ...f, ends_on: e.target.value })} />
        </div>
        <Textarea label={t('ip.areas')} required value={f.areas} onChange={(e) => setF({ ...f, areas: e.target.value })} />
        <Textarea label={t('ip.support')} value={f.support} onChange={(e) => setF({ ...f, support: e.target.value })} />
      </div>
    </Modal>
  );
}

function ClosePlanDialog({ p, onClose, onDone }: { p: PerfPlan | null; onClose: () => void; onDone: () => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ outcome: 'IMPROVED' as PerfPlan['status'], note: '' });
  useEffect(() => { if (p) setF({ outcome: 'IMPROVED', note: '' }); }, [p]);
  const early = !!p && todayMuscat() < p.ends_on;
  const submit = async () => { if (p && (await run(() => wfapi.closePlan(p.id, f.outcome, f.note), t('c.saved')))) onDone(); };
  return (
    <Modal open={!!p} title={`${t('ip.close')} — ${p ? L(p.full_name_en, p.full_name_ar) : ''}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={f.note.trim().length < 10 || (early && f.outcome === 'NOT_IMPROVED')} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <Select label={t('ip.outcome')} value={f.outcome} onChange={(e) => setF({ ...f, outcome: e.target.value as PerfPlan['status'] })}
          hint={early && p ? t('ip.not_before', { d: fmtDate(p.ends_on) }) : undefined}>
          {(['IMPROVED', 'NOT_IMPROVED', 'CANCELLED'] as const).map((s) => <option key={s} value={s} disabled={early && s === 'NOT_IMPROVED'}>{t(`ip.st_${s}` as Key)}</option>)}
        </Select>
        <Textarea label={t('ip.outcome_note')} required value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} />
      </div>
    </Modal>
  );
}
