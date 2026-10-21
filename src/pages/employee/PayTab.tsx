import { useState } from 'react';
import { api, type EmployeeFile, type PayComponent, type Revision } from '../../lib/api';
import { useI18n } from '../../i18n';
import { Badge, Button, DateText, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync } from '../../components/ui';
import { fmtMoney, parseMoney, todayMuscat } from '../../lib/format';
import type { ConfirmFn } from './ProfileTab';
import { PayrollPanel } from './PayrollPanel';

function RevisionTable({ r }: { r: Revision }) {
  const { t, L } = useI18n();
  const earnings = r.lines.filter((l) => l.kind === 'EARNING');
  const deductions = r.lines.filter((l) => l.kind === 'DEDUCTION');
  return (
    <table className="t">
      <tbody>
        {earnings.map((l) => <tr key={l.component_code}><td>{L(l.name_en, l.name_ar)}</td><td className="r num">{fmtMoney(l.amount)}</td></tr>)}
      </tbody>
      <tfoot>
        <tr><td>{t('pay.gross')}</td><td className="r num">{fmtMoney(r.total_monthly)}</td></tr>
        {deductions.map((l) => <tr key={l.component_code}><td className="muted-2">{L(l.name_en, l.name_ar)}</td><td className="r num">−{fmtMoney(l.amount)}</td></tr>)}
      </tfoot>
    </table>
  );
}

export function PayTab({ file, confirm }: { file: EmployeeFile; confirm: ConfirmFn }) {
  const { t, tk, L } = useI18n();
  const e = file.employee;
  const { data, error, loading, reload, setData } = useAsync(() => api.getCompensation(e.id), [e.id]);
  const comps = useAsync(() => api.listPayComponents(), []);
  const [form, setForm] = useState<{ effective_from: string; reason: string; notes: string; amounts: Record<string, string> } | null>(null);
  const [warnings, setWarnings] = useState<string[]>([]);
  const { busy, run } = useAction();

  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;

  const startPropose = () => {
    const amounts: Record<string, string> = {};
    for (const l of data.current?.lines ?? []) amounts[l.component_code] = String(l.amount);
    setForm({ effective_from: data.current ? todayMuscat() : e.join_date, reason: data.current ? 'INCREMENT' : 'JOIN', notes: '', amounts });
  };

  const components: PayComponent[] = comps.data ?? [];
  const parsed = form ? components.map((c) => ({ c, raw: form.amounts[c.code] ?? '', v: parseMoney(form.amounts[c.code] ?? '') })) : [];
  const invalid = parsed.some((x) => x.raw.trim() !== '' && x.v === null);
  const gross = parsed.filter((x) => x.c.kind === 'EARNING').reduce((s, x) => s + (x.v ?? 0), 0);
  const basic = parsed.find((x) => x.c.is_basic)?.v ?? 0;
  const band = data.grade;
  const outOfBand = !!band && basic > 0 && ((band.min_basic !== null && basic < Number(band.min_basic)) || (band.max_basic !== null && basic > Number(band.max_basic)));

  const submit = async () => {
    if (!form) return;
    const lines = parsed.filter((x) => x.v !== null && (x.v > 0 || x.c.is_basic)).map((x) => ({ component_code: x.c.code, amount: x.raw.replace(/,/g, '').trim() }));
    const r = await run(() => api.proposeCompensation(e.id, { effective_from: form.effective_from, reason: form.reason, notes: form.notes.trim() || null, lines }), t('pay.pending'));
    if (r) { setData(r.compensation); setWarnings(r.warnings.map((w) => w.message)); setForm(null); }
  };

  const decide = async (rev: Revision, approve: boolean) => {
    const note = await confirm({ title: t(approve ? 'pay.approve_title' : 'pay.reject_title'), reason: approve ? 'optional' : 'required',
      reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    const r = await run(() => api.decideCompensation(rev.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'));
    if (r) setData(r);
  };

  return (
    <div className="grid-side">
      <div className="stack">
        <section className="panel">
          <div className="panel-head">
            <h2>{t('pay.current')}</h2>
            {file.caps.salary_write && !data.pending && e.status !== 'SEPARATED' && <Button small kind="primary" onClick={startPropose}>{t('pay.propose')}</Button>}
          </div>
          <div className="panel-body">
            {data.current ? <>
              <RevisionTable r={data.current} />
              <p className="muted" style={{ marginTop: 10, fontSize: 13.5 }}>{t('as.effective_from')} <DateText v={data.current.effective_from} />, {tk(`pay.${data.current.reason}`, data.current.reason)}</p>
            </> : <Empty>{t('pay.none')}</Empty>}
            {band && <p className="muted" style={{ fontSize: 13.5 }}>{t('pay.grade_band', { grade: band.code, min: fmtMoney(band.min_basic), max: fmtMoney(band.max_basic) })}</p>}
          </div>
        </section>

        {warnings.length > 0 && <div className="note note-warn">{warnings.join(' ')}</div>}

        {data.pending && (
          <section className="panel">
            <div className="panel-head"><h2>{t('pay.pending')}</h2><Badge tone="warn">{t('pay.PENDING')}</Badge></div>
            <div className="panel-body stack">
              <RevisionTable r={data.pending} />
              <div className="muted" style={{ fontSize: 13.5 }}>
                {t('as.effective_from')} <DateText v={data.pending.effective_from} />, {tk(`pay.${data.pending.reason}`, data.pending.reason)}
                <br />{t('pay.proposed_by', { name: data.pending.proposed_by_name ?? '' })}
              </div>
              {data.pending.notes && <p>{data.pending.notes}</p>}
              <div className="row">
                {file.caps.salary_approve && <>
                  <Button kind="primary" busy={busy} onClick={() => void decide(data.pending!, true)}>{t('c.approve')}</Button>
                  <Button kind="danger" busy={busy} onClick={() => void decide(data.pending!, false)}>{t('c.reject')}</Button>
                </>}
                {file.caps.salary_write && <Button busy={busy} onClick={async () => {
                  const r = await run(() => api.withdrawCompensation(data.pending!.id), t('c.saved'));
                  if (r) setData(r);
                }}>{t('pay.withdraw')}</Button>}
              </div>
            </div>
          </section>
        )}

        {data.scheduled.map((s) => (
          <section className="panel" key={s.id}>
            <div className="panel-head"><h2>{t('pay.scheduled')}</h2><DateText v={s.effective_from} /></div>
            <div className="panel-body"><RevisionTable r={s} /></div>
          </section>
        ))}
      </div>

      <section className="panel">
        <div className="panel-head"><h2>{t('c.history')}</h2></div>
        {data.history.length === 0 ? <Empty>—</Empty> : (
          <ul className="panel-body stack" style={{ margin: 0, listStyle: 'none' }}>
            {data.history.map((h) => (
              <li key={h.id}>
                <div className="row">
                  <DateText v={h.effective_from} />
                  <span className="num" style={{ fontWeight: 600 }}>{fmtMoney(h.total_monthly)}</span>
                  <Badge tone={h.status === 'APPROVED' ? 'ok' : h.status === 'PENDING' ? 'warn' : h.status === 'REJECTED' ? 'bad' : undefined}>{tk(`pay.${h.status}`, h.status)}</Badge>
                </div>
                <div className="muted" style={{ fontSize: 12.5 }}>
                  {tk(`pay.${h.reason}`, h.reason)} — {t('pay.proposed_by', { name: h.proposed_by_name ?? '' })}
                  {h.decided_by_name && <>; {t('pay.decided_by', { name: h.decided_by_name })}</>}
                </div>
                {h.decision_note && <div style={{ fontSize: 13 }}>{h.decision_note}</div>}
              </li>
            ))}
          </ul>
        )}
      </section>

      <Modal open={!!form} title={t('pay.propose')} onClose={() => setForm(null)}
        footer={<><Button onClick={() => setForm(null)}>{t('c.cancel')}</Button>
          <Button kind="primary" busy={busy} disabled={invalid || basic <= 0} onClick={() => void submit()}>{t('c.save')}</Button></>}>
        {form && (
          <div className="stack">
            <div className="form-grid">
              <Input type="date" label={t('as.effective_from')} required value={form.effective_from} min={e.join_date}
                onChange={(ev) => setForm({ ...form, effective_from: ev.target.value })} />
              <Select label={t('c.reason')} value={form.reason} onChange={(ev) => setForm({ ...form, reason: ev.target.value })}>
                {['JOIN', 'INCREMENT', 'PROMOTION', 'ADJUSTMENT', 'CORRECTION', 'REHIRE'].map((r) => <option key={r} value={r}>{tk(`pay.${r}`, r)}</option>)}
              </Select>
            </div>
            <table className="t">
              <thead><tr><th>{t('pay.component')}</th><th className="r">{t('pay.amount')}</th></tr></thead>
              <tbody>
                {parsed.map(({ c, raw, v }) => (
                  <tr key={c.code}>
                    <td><label htmlFor={`amt-${c.code}`}>{c.kind === 'DEDUCTION' ? '− ' : ''}{c.is_basic ? <b>{L(c.name_en, c.name_ar)}</b> : L(c.name_en, c.name_ar)}</label></td>
                    <td className="r" style={{ width: 160 }}>
                      <input id={`amt-${c.code}`} className="input ltr num" inputMode="decimal" value={raw} aria-invalid={raw.trim() !== '' && v === null ? true : undefined}
                        onChange={(ev) => setForm({ ...form, amounts: { ...form.amounts, [c.code]: ev.target.value } })} />
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot><tr><td>{t('pay.gross')}</td><td className="r num">{fmtMoney(gross)}</td></tr></tfoot>
            </table>
            {invalid && <div className="note note-bad">{t('err.INVALID_AMOUNT')}</div>}
            {outOfBand && <div className="note note-warn">{t('pay.warning_band')}</div>}
            <Textarea label={t('c.notes')} value={form.notes} onChange={(ev) => setForm({ ...form, notes: ev.target.value })} />
          </div>
        )}
      </Modal>
      <PayrollPanel employeeId={e.id} />
    </div>
  );
}
