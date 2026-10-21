import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { papi, type GratuityDetail, type Settlement, type SettlementOther, type SettlementPreview, type SettlementReason } from '../../lib/api_pay';
import { translate, useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm, useToast } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { EmpLink, OMR } from '../../components/pay';
import { fmtDate, fmtDateTime, todayMuscat } from '../../lib/format';

const REASONS: SettlementReason[] = ['RESIGNATION', 'TERMINATION', 'END_OF_CONTRACT', 'RETIREMENT', 'DEATH', 'OTHER'];
const tone = (s: Settlement['status']) => s === 'PAID' ? 'ok' : s === 'APPROVED' ? 'info' : s === 'PREPARED' ? 'warn' : undefined;

export default function SettlementsPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const [status, setStatus] = useState('');
  const { data, error, loading, reload } = useAsync(() => papi.listSettlements({ status: status || null }), [status]);
  const [open, setOpen] = useState(false);
  return (
    <div className="stack">
      <PageHead title={t('st.title')} sub={t('st.salary_note')} actions={can('PAY_PREPARE') && <Button kind="primary" onClick={() => setOpen(true)}>{t('st.new')}</Button>} />
      <div className="panel panel-pad row">
        <div className="field" style={{ minWidth: 220 }}><label htmlFor="st-st">{t('c.status')}</label>
          <select id="st-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">{t('c.all')}</option>
            {['PREPARED', 'APPROVED', 'PAID', 'CANCELLED'].map((s) => <option key={s} value={s}>{t(`st.st_${s}` as Key)}</option>)}
          </select></div>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('st.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('st.last_day')}</th><th>{t('st.reason')}</th><th className="r">{t('st.gratuity')}</th>
              <th className="r">{t('st.leave')}</th><th className="r">{t('st.loans')}</th><th className="r">{t('st.net')}</th><th>{t('c.status')}</th></tr></thead>
            <tbody>{data.map((s) => (
              <tr key={s.id}>
                <td data-label={t('c.employee')}><EmpLink id={s.employee_id} no={s.employee_no} en={s.full_name_en} ar={s.full_name_ar} /></td>
                <td data-label={t('st.last_day')} className="num"><Link to={`/payroll/settlements/${s.id}`}>{fmtDate(s.last_working_date)}</Link></td>
                <td data-label={t('st.reason')}>{t(`st.r_${s.reason}` as Key)}</td>
                <td data-label={t('st.gratuity')} className="r num">{OMR(s.gratuity)}</td>
                <td data-label={t('st.leave')} className="r num">{OMR(s.leave_pay)}<span className="sub">{s.leave_days}</span></td>
                <td data-label={t('st.loans')} className="r num">{s.loan_recovery > 0 ? `−${OMR(s.loan_recovery)}` : '—'}</td>
                <td data-label={t('st.net')} className="r num"><b>{OMR(s.net)}</b></td>
                <td data-label={t('c.status')}><Badge tone={tone(s.status)}>{t(`st.st_${s.status}` as Key)}</Badge>
                  <span className="sub">{s.prepared_by_name} · {fmtDateTime(s.prepared_at)}</span></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
      <SettlementDialog open={open} onClose={() => setOpen(false)} onDone={() => void reload()} />
    </div>
  );
}

export function GratuityLines({ g }: { g: GratuityDetail }) {
  const { t } = useI18n();
  if (!g.applies) return <p className="muted" style={{ margin: 0 }}>{t('st.no_gratuity')}</p>;
  if (g.below_minimum) return <p className="muted" style={{ margin: 0 }}>{t('st.below_min')}</p>;
  return (
    <dl className="kv">
      <div><dt>{t('st.gratuity_old', { d: fmtDate(g.cutoff ?? '2023-07-31') })}</dt><dd className="num">{OMR(g.old_amount)}<span className="sub">{t('st.years', { n: g.old_years })}</span></dd></div>
      <div><dt>{t('st.gratuity_new', { d: fmtDate('2023-08-01') })}</dt><dd className="num">{OMR(g.new_amount)}<span className="sub">{t('st.years', { n: g.new_years })}</span></dd></div>
    </dl>
  );
}

function Figures({ p }: { p: SettlementPreview | Settlement['details'] }) {
  const { t } = useI18n();
  return (
    <div className="stack">
      <div className="tile-row">
        <div className="tile"><span>{t('st.basic')}</span><b>{OMR(p.basic)}</b></div>
        <div className="tile"><span>{t('st.gross')}</span><b>{OMR(p.gross)}</b></div>
        <div className="tile"><span>{t('st.gratuity')}</span><b>{OMR(p.gratuity)}</b></div>
        <div className="tile"><span>{t('st.leave')}</span><b>{OMR(p.leave_pay)}</b><span>{t('st.leave_days', { n: p.leave_days, r: OMR(p.daily_gross) })}</span></div>
        <div className="tile"><span>{t('st.notice')}</span><b>{OMR(p.notice_pay)}</b></div>
        <div className="tile"><span>{t('st.loans')}</span><b>{p.loan_recovery > 0 ? `−${OMR(p.loan_recovery)}` : OMR(0)}</b></div>
        <div className="tile"><span>{t('st.net')}</span><b>{OMR(p.net)}</b></div>
      </div>
      <GratuityLines g={p.gratuity_detail} />
      {p.warnings.length > 0 && <div className="note note-warn"><ul style={{ margin: 0 }}>{p.warnings.map((w, i) => <li key={i}>{w}</li>)}</ul></div>}
    </div>
  );
}

function SettlementDialog({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const init = () => ({ employee_id: null as string | null, last_working_date: todayMuscat(), reason: 'RESIGNATION' as SettlementReason, notice_days: '0', note: '' });
  const [f, setF] = useState(init);
  const [other, setOther] = useState<SettlementOther[]>([]);
  const [prev, setPrev] = useState<SettlementPreview | null>(null);
  useEffect(() => { if (open) { setF(init()); setOther([]); setPrev(null); } }, [open]);
  const body = () => ({ ...f, notice_days: f.notice_days || '0', other: other.filter((o) => o.label.trim() && Number(o.amount) > 0) });
  const preview = async () => { const r = await run(() => papi.previewSettlement(body())); if (r) setPrev(r); };
  const save = async () => {
    const r = await run(() => papi.saveSettlement(body()));
    if (r) { push(t('st.saved')); onDone(); onClose(); }
  };
  const ch = (patch: Partial<ReturnType<typeof init>>) => { setF({ ...f, ...patch }); setPrev(null); };
  return (
    <Modal open={open} title={t('st.new')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button busy={busy} disabled={!f.employee_id || !f.last_working_date} onClick={() => void preview()}>{t('st.preview')}</Button>
        <Button kind="primary" busy={busy} disabled={!prev} onClick={() => void save()}>{t('st.save')}</Button></>}>
      <div className="stack">
        <EmployeePicker label={t('c.employee')} value={f.employee_id} onChange={(v) => ch({ employee_id: v })} />
        <div className="form-grid">
          <Input label={t('st.last_day')} type="date" ltr required value={f.last_working_date} onChange={(e) => ch({ last_working_date: e.target.value })} />
          <Select label={t('st.reason')} value={f.reason} onChange={(e) => ch({ reason: e.target.value as SettlementReason })}>
            {REASONS.map((r) => <option key={r} value={r}>{t(`st.r_${r}` as Key)}</option>)}
          </Select>
          <Input label={t('st.notice_days')} ltr inputMode="decimal" hint={t('st.notice_hint')} value={f.notice_days} onChange={(e) => ch({ notice_days: e.target.value })} />
        </div>
        <fieldset style={{ border: 0, padding: 0, margin: 0 }}>
          <legend style={{ fontWeight: 600, marginBottom: 6 }}>{t('st.other')}</legend>
          {other.map((o, i) => (
            <div key={i} className="row" style={{ gap: 8, alignItems: 'flex-end', marginBottom: 6 }}>
              <div style={{ flex: 2, minWidth: 160 }}><Input label={t('st.label')} value={o.label} onChange={(e) => { const n = [...other]; n[i] = { ...o, label: e.target.value }; setOther(n); setPrev(null); }} /></div>
              <div style={{ flex: 1, minWidth: 130 }}><Select label={t('pr.kind')} value={o.kind} onChange={(e) => { const n = [...other]; n[i] = { ...o, kind: e.target.value as SettlementOther['kind'] }; setOther(n); setPrev(null); }}>
                <option value="EARNING">{t('pr.k_EARNING')}</option><option value="DEDUCTION">{t('pr.k_DEDUCTION')}</option></Select></div>
              <div style={{ flex: 1, minWidth: 110 }}><Input label={t('pr.amount')} ltr inputMode="decimal" value={o.amount} onChange={(e) => { const n = [...other]; n[i] = { ...o, amount: e.target.value }; setOther(n); setPrev(null); }} /></div>
              <Button small onClick={() => { setOther(other.filter((_, j) => j !== i)); setPrev(null); }}>{t('c.remove')}</Button>
            </div>))}
          <Button small onClick={() => setOther([...other, { label: '', kind: 'EARNING', amount: '' }])}>{t('st.add_line')}</Button>
        </fieldset>
        <Textarea label={t('c.notes')} value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} />
        {prev && <Figures p={prev} />}
        <p className="muted small" style={{ margin: 0 }}>{t('st.salary_note')}</p>
      </div>
    </Modal>
  );
}

/** Printable bilingual statement with approve / pay actions. */
export function SettlementPage() {
  const { id = '' } = useParams();
  const { t, L, lang } = useI18n();
  const nav = useNavigate();
  const { data: s, error, loading, reload, setData } = useAsync(() => papi.getSettlement(id), [id]);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  if (loading && !s) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!s) return null;
  const other = lang === 'ar' ? 'en' : 'ar';
  const bi = (k: Key, v?: Record<string, string | number>) => <>{t(k, v)}<span className="bi" lang={other}>{translate(other, k, v)}</span></>;
  const rows: [Key, number, string?][] = [
    ['st.gratuity', s.gratuity], ['st.leave', s.leave_pay, t('st.leave_days', { n: s.leave_days, r: OMR(s.details.daily_gross) })],
    ['st.notice', s.notice_pay, s.notice_days ? `${s.notice_days} d` : undefined],
    ...(s.details.other ?? []).filter((o) => o.kind === 'EARNING').map((o) => ['st.other', Number(o.amount), o.label] as [Key, number, string]),
    ['st.loans', -s.loan_recovery],
    ...(s.details.other ?? []).filter((o) => o.kind === 'DEDUCTION').map((o) => ['st.other', -Number(o.amount), o.label] as [Key, number, string]),
  ];
  return (
    <div className="stack">
      <div className="row no-print" style={{ justifyContent: 'space-between' }}>
        <Button onClick={() => nav(-1)}>{t('c.back')}</Button>
        <div className="row" style={{ gap: 6 }}>
          {s.can_decide && <><Button kind="primary" busy={busy} onClick={async () => {
            const note = await confirm.ask({ title: `${t('c.approve')} — ${s.full_name_en}`, reason: 'optional', okLabel: t('c.approve') });
            if (note !== null) { const r = await run(() => papi.decideSettlement(s.id, true, note || null), t('ap.done_approve')); if (r) setData(r); }
          }}>{t('c.approve')}</Button>
          <Button kind="danger" busy={busy} onClick={async () => {
            const note = await confirm.ask({ title: `${t('c.reject')} — ${s.full_name_en}`, reason: 'required', danger: true, okLabel: t('c.reject') });
            if (note) { const r = await run(() => papi.decideSettlement(s.id, false, note), t('ap.done_reject')); if (r) setData(r); }
          }}>{t('c.reject')}</Button></>}
          {s.can_cancel && !s.can_decide && <Button busy={busy} onClick={async () => { const r = await run(() => papi.cancelSettlement(s.id, null)); if (r) setData(r); }}>{t('st.withdraw')}</Button>}
          {s.can_pay && <Button busy={busy} onClick={async () => { const r = await run(() => papi.markSettlementPaid(s.id), t('st.paid_done')); if (r) setData(r); }}>{t('st.mark_paid')}</Button>}
          <Button kind="primary" onClick={() => window.print()}>{t('st.print')}</Button>
        </div>
      </div>
      <article className="slip panel panel-pad stack">
        <header className="slip-head">
          <div><h2 style={{ margin: 0 }}>{L(s.entity_en, s.entity_ar)}</h2></div>
          <div className="slip-title"><b>{bi('st.statement')}</b><Badge tone={tone(s.status)}>{t(`st.st_${s.status}` as Key)}</Badge></div>
        </header>
        <dl className="kv slip-kv">
          <div><dt>{bi('ps.employee')}</dt><dd>{L(s.full_name_en, s.full_name_ar)}<span className="sub num">{s.employee_no}</span></dd></div>
          <div><dt>{bi('ps.job')}</dt><dd>{L(s.job_en, s.job_ar) || '—'}</dd></div>
          <div><dt>{bi('gr.join')}</dt><dd className="num">{fmtDate(s.join_date)}</dd></div>
          <div><dt>{bi('st.last_day')}</dt><dd className="num">{fmtDate(s.last_working_date)}</dd></div>
          <div><dt>{bi('st.reason')}</dt><dd>{t(`st.r_${s.reason}` as Key)}</dd></div>
          <div><dt>{bi('st.basic')}</dt><dd className="num">{OMR(s.basic)}</dd></div>
          <div><dt>{bi('st.gross')}</dt><dd className="num">{OMR(s.gross)}</dd></div>
        </dl>
        <table className="t slip-lines">
          <tbody>{rows.filter((r) => r[1] !== 0 || r[0] === 'st.gratuity').map((r, i) => (
            <tr key={i}><td>{bi(r[0])}{r[2] && <span className="sub">{r[2]}</span>}</td><td className={`r num ${r[1] < 0 ? 'diff-neg' : ''}`}>{OMR(r[1])}</td></tr>))}
          </tbody>
        </table>
        <GratuityLines g={s.details.gratuity_detail} />
        <div className="slip-net"><span>{bi('st.net')}</span><b className="num">OMR {OMR(s.net)}</b></div>
        {s.note && <p style={{ margin: 0 }}>{s.note}</p>}
        <p className="muted small" style={{ margin: 0 }}>{t('st.salary_note')}</p>
        <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}>
          <div className="small muted">{s.prepared_by_name} · {fmtDateTime(s.prepared_at)}{s.approved_by_name && <> → {s.approved_by_name} · {fmtDateTime(s.approved_at)}</>}</div>
          <div className="sig-line">{bi('st.signature')}</div>
        </div>
      </article>
      {confirm.node}
    </div>
  );
}
