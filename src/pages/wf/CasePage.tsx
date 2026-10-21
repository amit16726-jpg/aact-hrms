import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { PENALTIES, wfapi, type DiscCase, type Penalty } from '../../lib/api_wf';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Button, Check, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { CaseBadge } from '../../components/wf';
import { fmtDate, fmtDateTime } from '../../lib/format';
import { CaseDialog } from './DisciplinePage';

export default function CasePage() {
  const { id = '' } = useParams();
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data: d, error, loading, reload, setData } = useAsync(() => wfapi.getCase(id), [id]);
  const [edit, setEdit] = useState(false);
  const [pen, setPen] = useState<'PROPOSE' | 'DECIDE' | null>(null);
  const [text, setText] = useState('');
  const { busy, run } = useAction();
  const confirm = useConfirm();
  if (loading && !d) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!d) return null;
  const act = async (action: 'INVESTIGATE' | 'RETURN' | 'DISMISS') => {
    const note = await confirm.ask({ title: t(action === 'INVESTIGATE' ? 'dc.investigate' : action === 'RETURN' ? 'dc.return' : 'dc.drop'),
      body: action === 'INVESTIGATE' ? t('dc.investigate_q') : action === 'DISMISS' ? t('dc.drop_q') : undefined,
      reason: action === 'INVESTIGATE' ? undefined : 'required', danger: action === 'DISMISS' });
    if (note === null) return;
    const r = await run(() => wfapi.caseAction(d.id, action, { note: note || null }), t('c.saved'));
    if (r) void reload();
  };
  const respond = async () => {
    const r = await run(() => wfapi.respondCase(d.id, text), t('dc.response_sent'));
    if (r) { setText(''); setData({ ...d, ...r }); }
  };
  const full = can('DISC_READ');
  return (
    <div className="stack">
      <PageHead title={<>{d.ref_no} <span className="muted">· {L(d.full_name_en, d.full_name_ar)}</span></>}
        sub={<>{t(`dc.cat_${d.category}` as Key)} · <span className="num">{fmtDate(d.incident_date)}</span> · <CaseBadge s={d.status} /></>}
        actions={<div className="row" style={{ gap: 6, flexWrap: 'wrap' }}>
          {d.can_edit && <Button onClick={() => setEdit(true)}>{t('c.edit')}</Button>}
          {d.can_edit && d.status === 'DRAFT' && <Button kind="primary" busy={busy} onClick={() => void act('INVESTIGATE')}>{t('dc.investigate')}</Button>}
          {d.can_propose && <Button kind="primary" onClick={() => setPen('PROPOSE')}>{t('dc.propose')}</Button>}
          {d.can_decide && <><Button kind="primary" onClick={() => setPen('DECIDE')}>{t('dc.decide')}</Button>
            <Button busy={busy} onClick={() => void act('RETURN')}>{t('dc.return')}</Button></>}
          {full && can('DISC_WRITE') && ['DRAFT', 'INVESTIGATION', 'PROPOSED'].includes(d.status) && <Button kind="danger" busy={busy} onClick={() => void act('DISMISS')}>{t('dc.drop')}</Button>}
          <Link className="btn" to="/discipline">{t('c.back')}</Link>
        </div>} />
      <div className="grid-2" style={{ alignItems: 'start' }}>
        <section className="panel panel-pad stack">
          <h2 style={{ margin: 0 }}>{t('dc.description')}</h2>
          <p className="quote">{d.description}</p>
          {d.investigation_notes && <><b>{t('dc.notes')}</b><p className="quote">{d.investigation_notes}</p></>}
          {d.opened_by_name && <div className="muted">{t('dc.opened_by', { n: d.opened_by_name })} · {fmtDateTime(d.created_at)}</div>}
        </section>
        <section className="panel panel-pad stack">
          <h2 style={{ margin: 0 }}>{t('dc.response')}</h2>
          {d.employee_response ? <><p className="quote">{d.employee_response}</p><div className="muted num">{fmtDateTime(d.response_at)}</div></> : <div className="muted">{t('dc.no_response')}</div>}
          {d.can_respond && d.status === 'INVESTIGATION' && <>
            <Textarea label={t('dc.respond')} required value={text} onChange={(e) => setText(e.target.value)} />
            <div><Button kind="primary" busy={busy} disabled={text.trim().length < 10} onClick={() => void respond()}>{t('c.save')}</Button></div></>}
        </section>
      </div>
      {(d.proposed_penalty || d.penalty) && (
        <section className="panel panel-pad stack">
          <h2 style={{ margin: 0 }}>{t('dc.decision')}</h2>
          <dl className="kv">
            {d.proposed_penalty && <div><dt>{t('dc.propose')}</dt><dd>{t(`dc.pen_${d.proposed_penalty}` as Key)}{d.proposed_days ? ` · ${t('dc.days_n', { n: d.proposed_days })}` : ''}
              {d.proposed_by_name && <span className="sub">{d.proposed_by_name}</span>}</dd></div>}
            {d.penalty && <div><dt>{t('dc.penalty')}</dt><dd>{t(`dc.pen_${d.penalty}` as Key)}{d.penalty_days ? ` · ${t('dc.days_n', { n: d.penalty_days })}` : ''}
              <span className="sub">{d.decided_by_name} · {fmtDate(d.decided_at)}</span></dd></div>}
          </dl>
          {d.decision_note && <p className="quote">{d.decision_note}</p>}
          {d.adjustment_id && <div className="note">{t('dc.to_payroll')}{full && <> · <Link to="/payroll/items">{t('pnav.adjustments')}</Link></>}</div>}
          {d.appeal && <><b>{t('dc.appeal')}</b><p className="quote">{d.appeal}</p><div className="muted num">{fmtDateTime(d.appeal_at)}</div></>}
          {d.can_respond && d.status === 'DECIDED' && <>
            <Textarea label={t('dc.appeal_btn')} required value={text} onChange={(e) => setText(e.target.value)} />
            <div><Button kind="primary" busy={busy} disabled={text.trim().length < 10} onClick={() => void respond()}>{t('dc.appeal_btn')}</Button></div></>}
        </section>)}
      {(d.history ?? []).length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('dc.history')}</h2></div>
          <div className="table-wrap"><table className="t cards">
            <tbody>{(d.history ?? []).map((h) => (
              <tr key={h.ref_no}><td className="num">{h.ref_no}</td><td className="num">{fmtDate(h.incident_date)}</td><td>{t(`dc.cat_${h.category}` as Key)}</td>
                <td><CaseBadge s={h.status} /></td><td>{h.penalty ? t(`dc.pen_${h.penalty}` as Key) : '—'}</td></tr>))}
            </tbody></table></div>
        </section>)}
      <CaseDialog open={edit} edit={d} onClose={() => setEdit(false)} onDone={() => void reload()} />
      <PenaltyDialog mode={pen} c={d} onClose={() => setPen(null)} onDone={(r) => { setPen(null); setData(r); void reload(); }} />
      {confirm.node}
    </div>
  );
}

function PenaltyDialog({ mode, c, onClose, onDone }: { mode: 'PROPOSE' | 'DECIDE' | null; c: DiscCase; onClose: () => void; onDone: (r: DiscCase) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const pol = useAsync(() => (mode ? wfapi.policies() : Promise.resolve(null)), [mode]);
  const [f, setF] = useState({ penalty: '' as Penalty | '', days: '', note: '', no_resp: false });
  useEffect(() => {
    if (mode) setF({ penalty: mode === 'DECIDE' ? c.proposed_penalty ?? '' : '', days: mode === 'DECIDE' && c.proposed_days ? String(c.proposed_days) : '', note: '', no_resp: false });
  }, [mode, c]);
  const needDays = f.penalty === 'DEDUCTION' || f.penalty === 'SUSPENSION';
  const max = f.penalty === 'DEDUCTION' ? pol.data?.discipline_max_deduction_days ?? 5 : pol.data?.discipline_max_suspension_days ?? 5;
  const daysOk = !needDays || (Number(f.days) > 0 && Number(f.days) <= max);
  const needConfirm = mode === 'PROPOSE' && !c.employee_response;
  const submit = async () => {
    const r = await run(() => wfapi.caseAction(c.id, mode as 'PROPOSE' | 'DECIDE', { penalty: f.penalty, days: needDays ? f.days : null, note: f.note || null, no_response_confirmed: f.no_resp }), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={!!mode} title={`${t(mode === 'DECIDE' ? 'dc.decide' : 'dc.propose')} — ${c.ref_no}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!f.penalty || !daysOk || (needConfirm && !f.no_resp)} onClick={() => void submit()}>{t(mode === 'DECIDE' ? 'dc.decide' : 'dc.propose')}</Button></>}>
      <div className="stack">
        {mode === 'DECIDE' && <div className="note">{t('dc.decide_hint')}</div>}
        <Select label={t('dc.penalty')} required value={f.penalty} onChange={(e) => setF({ ...f, penalty: e.target.value as Penalty })}>
          <option value="">{t('c.select')}</option>
          {PENALTIES.map((p) => <option key={p} value={p}>{t(`dc.pen_${p}` as Key)}</option>)}
        </Select>
        {needDays && <Input label={t('dc.days')} type="number" min={0.5} max={max} step="0.5" ltr value={f.days}
          hint={t(f.penalty === 'DEDUCTION' ? 'dc.days_hint_DEDUCTION' : 'dc.days_hint_SUSPENSION', { n: max })} error={f.days && !daysOk ? t('err.PENALTY_LIMIT') : null}
          onChange={(e) => setF({ ...f, days: e.target.value })} />}
        {needConfirm && <Check label={t('dc.no_response_confirmed')} checked={f.no_resp} onChange={(v) => setF({ ...f, no_resp: v })} />}
        <Textarea label={t('c.notes')} value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} />
        {pol.data && <div className="muted">{pol.data.discipline_legal_basis}</div>}
      </div>
    </Modal>
  );
}
