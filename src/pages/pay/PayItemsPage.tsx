import { useEffect, useState } from 'react';
import { papi, type AdjCode, type PayAdjustment } from '../../lib/api_pay';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm, useToast } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { EmpLink, OMR } from '../../components/pay';
import { addMonths, fmtDateTime, todayMuscat } from '../../lib/format';
import { parseCsv } from '../../lib/punches';

const EARN: AdjCode[] = ['BONUS', 'COMMISSION', 'ARREARS', 'ALLOWANCE', 'OTHER_EARN'];
const DED: AdjCode[] = ['PENALTY', 'DAMAGE', 'OTHER_DED'];

export default function PayItemsPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const { push } = useToast();
  const [status, setStatus] = useState('PENDING');
  const [month, setMonth] = useState('');
  const { data, error, loading, reload } = useAsync(() => papi.listAdjustments({ status: status || null, month: month || null }), [status, month]);
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [open, setOpen] = useState(false);
  const [errs, setErrs] = useState<{ row: number; message: string }[]>([]);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  useEffect(() => setSel(new Set()), [data]);
  const decidable = (data ?? []).filter((a) => a.can_decide);
  const decide = async (approve: boolean) => {
    const note = await confirm.ask({ title: t(approve ? 'pa.approve_selected' : 'pa.reject_selected'), reason: approve ? 'optional' : 'required',
      reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    if (await run(() => papi.decideAdjustments([...sel], approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'))) void reload();
  };
  const importCsv = async (file: File) => {
    const rows = parseCsv(await file.text()).filter((r) => r.some((c) => c.trim() !== ''));
    const head = (rows[0] ?? []).map((h) => h.toLowerCase().trim());
    const ix = (k: string) => head.indexOf(k);
    if (rows.length < 2 || ['employee_no', 'month', 'code', 'amount'].some((k) => ix(k) < 0)) { push(t('pa.csv_hint'), true); return; }
    const payload = rows.slice(1).map((r) => ({ employee_no: r[ix('employee_no')] ?? '', month: r[ix('month')] ?? '', code: (r[ix('code')] ?? '').toUpperCase(),
      amount: (r[ix('amount')] ?? '').replace(/,/g, ''), reason: ix('reason') >= 0 ? r[ix('reason')] ?? '' : '' }));
    const res = await run(() => papi.proposeAdjustments(payload));
    if (res) { push(t('pa.proposed', { n: res.proposed })); setErrs(res.errors); void reload(); }
  };
  return (
    <div className="stack">
      <PageHead title={t('pa.title')} sub={t('pa.cap_hint', { p: 25 })} actions={can('PAY_PREPARE') && <>
        <Button kind="primary" onClick={() => setOpen(true)}>{t('pa.new')}</Button>
        <label className="btn">{t('pa.import')}<input type="file" accept=".csv,text/csv" hidden onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void importCsv(f); }} /></label>
      </>} />
      {can('PAY_PREPARE') && <div className="note">{t('pa.csv_hint')}</div>}
      {errs.length > 0 && <div className="note note-warn"><b>{t('pa.errors', { n: errs.length })}</b>
        <ul style={{ margin: '6px 0 0' }}>{errs.slice(0, 20).map((e) => <li key={e.row}>{t('imp.line')} {e.row + 1}: {e.message}</li>)}</ul></div>}
      <div className="panel panel-pad row" style={{ alignItems: 'flex-end', gap: 16 }}>
        <div className="field" style={{ minWidth: 180 }}><label htmlFor="pa-st">{t('c.status')}</label>
          <select id="pa-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">{t('c.all')}</option>
            {['PENDING', 'APPROVED', 'REJECTED'].map((s) => <option key={s} value={s}>{t(`rst.${s}` as Key)}</option>)}
          </select></div>
        <div className="field"><label htmlFor="pa-m">{t('pr.month')}</label>
          <input id="pa-m" type="month" className="input ltr" value={month} onChange={(e) => setMonth(e.target.value)} /></div>
        <span className="spacer" />
        {decidable.length > 0 && <>
          <Button kind="primary" busy={busy} disabled={!sel.size} onClick={() => void decide(true)}>{t('pa.approve_selected')}</Button>
          <Button kind="danger" busy={busy} disabled={!sel.size} onClick={() => void decide(false)}>{t('pa.reject_selected')}</Button></>}
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('pa.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{decidable.length > 0 && <input type="checkbox" aria-label={t('c.all')} checked={sel.size === decidable.length}
              onChange={(e) => setSel(e.target.checked ? new Set(decidable.map((a) => a.id)) : new Set())} />}</th>
              <th>{t('c.employee')}</th><th>{t('pr.month')}</th><th>{t('pa.code')}</th><th className="r">{t('pr.amount')}</th><th>{t('c.reason')}</th><th>{t('c.status')}</th></tr></thead>
            <tbody>{data.map((a: PayAdjustment) => (
              <tr key={a.id}>
                <td>{a.can_decide && <input type="checkbox" aria-label={a.employee_no} checked={sel.has(a.id)}
                  onChange={(e) => { const s = new Set(sel); if (e.target.checked) s.add(a.id); else s.delete(a.id); setSel(s); }} />}</td>
                <td data-label={t('c.employee')}><EmpLink id={a.employee_id} no={a.employee_no} en={a.full_name_en} ar={a.full_name_ar} /></td>
                <td data-label={t('pr.month')} className="num">{a.month}</td>
                <td data-label={t('pa.code')}>{t(`pa.c_${a.code}` as Key)}</td>
                <td data-label={t('pr.amount')} className={`r num ${a.kind === 'DEDUCTION' ? 'diff-neg' : ''}`}>{a.kind === 'DEDUCTION' ? '−' : '+'}{OMR(a.amount)}</td>
                <td data-label={t('c.reason')}>{a.reason}{a.decision_note && <span className="sub">{a.decision_note}</span>}</td>
                <td data-label={t('c.status')}><Badge tone={a.status === 'APPROVED' ? 'ok' : a.status === 'REJECTED' ? 'bad' : 'warn'}>{t(`rst.${a.status}` as Key)}</Badge>
                  <span className="sub">{a.proposed_by_name} · {fmtDateTime(a.proposed_at)}</span></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
      <ItemDialog open={open} onClose={() => setOpen(false)} onDone={() => void reload()} />
      {confirm.node}
    </div>
  );
}

function ItemDialog({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const init = () => ({ employee_id: null as string | null, month: addMonths(todayMuscat().slice(0, 7), 0), code: 'BONUS', amount: '', reason: '' });
  const [f, setF] = useState(init);
  useEffect(() => { if (open) setF(init()); }, [open]);
  const submit = async () => {
    const r = await run(() => papi.proposeAdjustments([f]));
    if (!r) return;
    if (r.errors.length) push(r.errors[0].message, true); else { push(t('pa.proposed', { n: r.proposed })); onDone(); onClose(); }
  };
  return (
    <Modal open={open} title={t('pa.new')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy}
        disabled={!f.employee_id || !(Number(f.amount) > 0) || f.reason.trim().length < 3} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <EmployeePicker label={t('c.employee')} value={f.employee_id} onChange={(v) => setF({ ...f, employee_id: v })} />
        <div className="form-grid">
          <Input label={t('pr.month')} type="month" ltr value={f.month} onChange={(e) => setF({ ...f, month: e.target.value })} />
          <Select label={t('pa.code')} value={f.code} onChange={(e) => setF({ ...f, code: e.target.value })}>
            <optgroup label={t('pr.k_EARNING')}>{EARN.map((c) => <option key={c} value={c}>{t(`pa.c_${c}` as Key)}</option>)}</optgroup>
            <optgroup label={t('pr.k_DEDUCTION')}>{DED.map((c) => <option key={c} value={c}>{t(`pa.c_${c}` as Key)}</option>)}</optgroup>
          </Select>
          <Input label={t('pr.amount')} ltr inputMode="decimal" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} />
        </div>
        <Textarea label={t('c.reason')} required value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} />
      </div>
    </Modal>
  );
}
