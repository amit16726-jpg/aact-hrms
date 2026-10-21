import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { OPEN_STAGES, groupByStage, recapi, type Candidate, type RequisitionFull } from '../../lib/api_rec';
import { useI18n, type Key } from '../../i18n';
import { Badge, Button, Empty, ErrorNote, Input, Loading, Modal, Tabs, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { OfferBadge, OmanisationCheck, ReqBadgeRec, StageBadge, Stars } from '../../components/rec';
import { RequisitionDialog, CandidateFields, blankCandidate, candidateOk } from './RecruitmentPage';
import { OMR } from '../../components/pay';
import { fmtDate } from '../../lib/format';

export default function RequisitionPage() {
  const { id = '' } = useParams();
  const { t, L } = useI18n();
  const { data: r, error, loading, reload } = useAsync(() => recapi.getRequisition(id), [id]);
  const [edit, setEdit] = useState(false);
  const [add, setAdd] = useState(false);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  if (loading && !r) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!r) return null;
  const decide = async (approve: boolean) => {
    const note = await confirm.ask({ title: `${t(approve ? 'rq2.approve_title' : 'rq2.reject_title')} — ${r.ref_no}`, reason: approve ? 'optional' : 'required',
      reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    if (await run(() => recapi.decideRequisition(r.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'))) void reload();
  };
  const setStatus = async (status: string, key: Key, needReason: boolean) => {
    const note = await confirm.ask({ title: `${t(key)} — ${r.ref_no}`, reason: needReason ? 'required' : undefined, danger: status === 'CANCELLED' });
    if (note === null) return;
    if (await run(() => recapi.setRequisitionStatus(r.id, status, note || null))) void reload();
  };
  const g = groupByStage(r.applications);
  const closed = [...g.HIRED, ...g.REJECTED, ...g.WITHDRAWN];
  return (
    <div className="stack">
      <PageHead title={<>{L(r.job_en, r.job_ar)} <span className="muted num">{r.ref_no}</span></>}
        sub={<>{L(r.department_en, r.department_ar)} · {t('rq2.filled_of', { h: r.hired, n: r.positions })} · <ReqBadgeRec s={r.status} /></>}
        actions={<div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          {r.can_decide && <><Button kind="primary" busy={busy} onClick={() => void decide(true)}>{t('c.approve')}</Button>
            <Button kind="danger" busy={busy} onClick={() => void decide(false)}>{t('c.reject')}</Button></>}
          {r.can_edit && <Button onClick={() => setEdit(true)}>{t('c.edit')}</Button>}
          {r.status === 'APPROVED' && r.can_manage && <Button kind="primary" onClick={() => setAdd(true)}>{t('cd.add')}</Button>}
          {r.status === 'APPROVED' && r.can_manage && <Button onClick={() => void setStatus('ON_HOLD', 'rq2.hold', true)}>{t('rq2.hold')}</Button>}
          {r.status === 'ON_HOLD' && r.can_manage && <Button onClick={() => void setStatus('APPROVED', 'rq2.reopen', false)}>{t('rq2.reopen')}</Button>}
          {(r.can_manage || (r.status === 'PENDING' && r.can_edit)) && <Button kind="danger" onClick={() => void setStatus('CANCELLED', 'rq2.cancel', true)}>{t('rq2.cancel')}</Button>}
        </div>} />
      <div className="grid-2" style={{ alignItems: 'start' }}>
        <section className="panel panel-pad stack">
          <h2 style={{ margin: 0 }}>{t('rq2.details')}</h2>
          <dl className="kv">
            <div><dt>{t('rq2.positions')}</dt><dd className="num">{r.positions}</dd></div>
            <div><dt>{t('rq2.reason')}</dt><dd>{t(`rq2.r_${r.reason}` as Key)}{r.replaces_name ? <span className="sub">{t('rq2.replaces')}: {r.replaces_name}</span> : null}</dd></div>
            <div><dt>{t('rq2.nat_rule')}</dt><dd>{r.nationality_rule === 'ANY' ? t('rq2.n_ANY') : <Badge tone="info">{t(`rq2.n_${r.nationality_rule}` as Key)}</Badge>}</dd></div>
            <div><dt>{t('ef.grade')}</dt><dd>{L(r.grade_en, r.grade_ar) || '—'}</dd></div>
            <div><dt>{t('ef.category')}</dt><dd>{L(r.category_en, r.category_ar) || '—'}</dd></div>
            <div><dt>{t('rq2.salary_range')}</dt><dd className="num">{r.salary_min != null || r.salary_max != null ? `${r.salary_min != null ? OMR(r.salary_min) : '…'} – ${r.salary_max != null ? OMR(r.salary_max) : '…'}` : '—'}</dd></div>
            <div><dt>{t('rq2.target_date')}</dt><dd className="num">{fmtDate(r.target_date)}</dd></div>
          </dl>
          <p style={{ margin: 0 }}>{r.justification}</p>
          <div className="muted">{t('rq2.requested', { n: r.requested_by_name ?? '', d: fmtDate(r.requested_at) })}
            {r.decided_at && <> · {r.decided_by_name} {fmtDate(r.decided_at)}{r.decision_note ? ` — ${r.decision_note}` : ''}</>}
            {r.closed_reason && <> · {r.closed_reason}</>}</div>
        </section>
        <OmanisationCheck o={r.omanisation} />
      </div>
      <div className="pipeline" role="list">
        {OPEN_STAGES.map((s) => (
          <section key={s} className="pipe-col panel" role="listitem" aria-label={t(`stg.${s}` as Key)}>
            <div className="panel-head"><h2>{t(`stg.${s}` as Key)} <span className="muted num">{g[s].length}</span></h2></div>
            <div className="pipe-cards">
              {g[s].length === 0 ? <div className="muted panel-pad">—</div> : g[s].map((a) => (
                <Link key={a.id} to={`/recruitment/app/${a.id}`} className="pipe-card">
                  <b>{L(a.full_name_en, a.full_name_ar)}</b>
                  <span className="sub">{a.is_omani ? <Badge tone="ok">OM</Badge> : <span className="num">{a.nationality}</span>}{!a.in_oman && <> · {t('cd.abroad')}</>}
                    {a.experience_years != null && <> · {t('rc.years', { n: a.experience_years })}</>}</span>
                  {a.avg_rating != null && <Stars n={a.avg_rating} />}
                  {a.offer_status && <OfferBadge s={a.offer_status} />}
                </Link>))}
            </div>
          </section>))}
      </div>
      {closed.length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('stg.HIRED')} / {t('ap2.closed')}</h2></div>
          <div className="table-wrap"><table className="t cards">
            <tbody>{closed.map((a) => (
              <tr key={a.id}><td><Link to={`/recruitment/app/${a.id}`}>{L(a.full_name_en, a.full_name_ar)}</Link></td><td><StageBadge s={a.stage} /></td>
                <td className="muted">{a.rejection_reason ?? ''}</td></tr>))}
            </tbody></table></div>
        </section>)}
      {r.applications.length === 0 && r.status === 'APPROVED' && <Empty>{t('cd.none')}</Empty>}
      <RequisitionDialog open={edit} edit={r} onClose={() => setEdit(false)} onDone={() => void reload()} />
      <AddCandidateDialog open={add} req={r} onClose={() => setAdd(false)} />
      {confirm.node}
    </div>
  );
}

function AddCandidateDialog({ open, req, onClose }: { open: boolean; req: RequisitionFull; onClose: () => void }) {
  const { t, L } = useI18n();
  const nav = useNavigate();
  const { busy, run } = useAction();
  const [mode, setMode] = useState<'new' | 'existing'>('new');
  const [f, setF] = useState(blankCandidate);
  const [q, setQ] = useState('');
  const [hits, setHits] = useState<Candidate[]>([]);
  const [pick, setPick] = useState<string | null>(null);
  useEffect(() => { if (open) { setF(blankCandidate()); setQ(''); setHits([]); setPick(null); setMode('new'); } }, [open]);
  useEffect(() => {
    if (mode !== 'existing' || q.trim().length < 2) { setHits([]); return; }
    const h = window.setTimeout(() => { recapi.listCandidates(q.trim()).then(setHits).catch(() => setHits([])); }, 300);
    return () => window.clearTimeout(h);
  }, [q, mode]);
  const submit = async () => {
    const r = await run(() => recapi.addApplication(mode === 'new' ? { requisition_id: req.id, candidate: { ...f } } : { requisition_id: req.id, candidate_id: pick }), t('cd.added'));
    if (r) { onClose(); nav(`/recruitment/app/${r.id}`); }
  };
  return (
    <Modal open={open} title={`${t('cd.add')} — ${L(req.job_en, req.job_ar)}`} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={mode === 'new' ? !candidateOk(f) : !pick} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {req.nationality_rule === 'OMANI_ONLY' && <div className="note note-warn">{t('rq2.n_OMANI_ONLY')}</div>}
        <Tabs label={t('cd.add')} value={mode} onChange={setMode} tabs={[{ id: 'new', label: t('cd.new') }, { id: 'existing', label: t('cd.existing') }]} />
        {mode === 'new' ? <CandidateFields f={f} setF={setF} /> : (
          <div className="stack">
            <Input label={t('c.search')} placeholder={t('cd.search_ph')} value={q} onChange={(e) => setQ(e.target.value)} />
            <div className="choice-list">{hits.map((c) => (
              <label key={c.id} className={`choice${pick === c.id ? ' on' : ''}`}>
                <input type="radio" name="cand" checked={pick === c.id} onChange={() => setPick(c.id)} />
                <span><b>{L(c.full_name_en, c.full_name_ar)}</b><span className="sub">{c.nationality} · {[c.email, c.phone].filter(Boolean).join(' · ')}</span></span>
              </label>))}</div>
          </div>)}
      </div>
    </Modal>
  );
}
