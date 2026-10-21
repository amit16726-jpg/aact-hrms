import { useEffect, useState } from 'react';
import { papi, type Loan } from '../../lib/api_pay';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm, useToast } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { EmpLink, OMR } from '../../components/pay';
import { addMonths, fmtDateTime, todayMuscat } from '../../lib/format';

const tone = (s: Loan['status']) => s === 'APPROVED' ? 'info' : s === 'CLOSED' ? 'ok' : s === 'PENDING' ? 'warn' : s === 'REJECTED' ? 'bad' : undefined;

export default function LoansPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const [status, setStatus] = useState('OPEN');
  const { data, error, loading, reload } = useAsync(() => papi.listLoans({ status: status || null }), [status]);
  const [open, setOpen] = useState(false);
  const [view, setView] = useState<Loan | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const decide = async (l: Loan, approve: boolean) => {
    const note = await confirm.ask({ title: `${t(`ln.k_${l.kind}` as Key)} — ${l.full_name_en} — OMR ${OMR(l.amount)}`, reason: approve ? 'optional' : 'required',
      reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    if (await run(() => papi.decideLoan(l.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'))) void reload();
  };
  const cancel = async (l: Loan) => {
    const note = await confirm.ask({ title: `${t('ln.cancel')} — ${l.full_name_en}`, reason: l.status === 'APPROVED' ? 'required' : 'optional', danger: true });
    if (note === null) return;
    if (await run(() => papi.cancelLoan(l.id, note || null))) void reload();
  };
  return (
    <div className="stack">
      <PageHead title={t('ln.title')} sub={t('ln.hint')} actions={can('PAY_PREPARE') && <Button kind="primary" onClick={() => setOpen(true)}>{t('ln.new')}</Button>} />
      <div className="panel panel-pad row">
        <div className="field" style={{ minWidth: 220 }}><label htmlFor="ln-st">{t('c.status')}</label>
          <select id="ln-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">{t('c.all')}</option>
            {['OPEN', 'PENDING', 'APPROVED', 'CLOSED', 'REJECTED', 'CANCELLED'].map((s) => <option key={s} value={s}>{t(`ln.st_${s}` as Key)}</option>)}
          </select></div>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('ln.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('ln.kind')}</th><th className="r">{t('ln.amount')}</th><th className="r">{t('ln.installment')}</th>
              <th>{t('ln.first_month')}</th><th className="r">{t('ln.outstanding')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((l) => (
              <tr key={l.id}>
                <td data-label={t('c.employee')}><EmpLink id={l.employee_id} no={l.employee_no} en={l.full_name_en} ar={l.full_name_ar} /></td>
                <td data-label={t('ln.kind')}>{t(`ln.k_${l.kind}` as Key)}<span className="sub">{l.reason}</span></td>
                <td data-label={t('ln.amount')} className="r num">{OMR(l.amount)}</td>
                <td data-label={t('ln.installment')} className="r num">{OMR(l.installment)}</td>
                <td data-label={t('ln.first_month')} className="num">{l.first_month.slice(0, 7)}</td>
                <td data-label={t('ln.outstanding')} className="r num"><b>{OMR(l.outstanding)}</b>{l.months_left ? <span className="sub">{t('ln.months_left')}: {l.months_left}</span> : null}</td>
                <td data-label={t('c.status')}><Badge tone={tone(l.status)}>{t(`ln.st_${l.status}` as Key)}</Badge>
                  <span className="sub">{l.proposed_by_name} · {fmtDateTime(l.proposed_at)}</span>{l.decision_note && <span className="sub">{l.decision_note}</span>}</td>
                <td className="r"><div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  {l.repayments.length > 0 && <Button small onClick={() => setView(l)}>{t('ln.schedule')}</Button>}
                  {l.can_decide && <><Button small kind="primary" busy={busy} onClick={() => void decide(l, true)}>{t('c.approve')}</Button>
                    <Button small kind="danger" busy={busy} onClick={() => void decide(l, false)}>{t('c.reject')}</Button></>}
                  {l.can_cancel && <Button small busy={busy} onClick={() => void cancel(l)}>{t('ln.cancel')}</Button>}
                </div></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
      <LoanDialog open={open} onClose={() => setOpen(false)} onDone={() => void reload()} />
      <Modal open={!!view} title={`${t('ln.schedule')} — ${view?.full_name_en ?? ''}`} onClose={() => setView(null)} footer={<Button onClick={() => setView(null)}>{t('c.close')}</Button>}>
        <div className="table-wrap"><table className="t">
          <thead><tr><th>{t('pr.month')}</th><th>{t('ln.kind')}</th><th className="r">{t('pr.amount')}</th></tr></thead>
          <tbody>{(view?.repayments ?? []).map((r, i) => <tr key={i}><td className="num">{r.month}</td><td>{t(`ln.r_${r.kind}` as Key)}</td><td className="r num">{OMR(r.amount)}</td></tr>)}</tbody>
        </table></div>
      </Modal>
      {confirm.node}
    </div>
  );
}

function LoanDialog({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const init = () => ({ employee_id: null as string | null, kind: 'LOAN', amount: '', installment: '', first_month: addMonths(todayMuscat().slice(0, 7), 1), reason: '' });
  const [f, setF] = useState(init);
  useEffect(() => { if (open) setF(init()); }, [open]);
  const amt = Number(f.amount); const inst = Number(f.kind === 'ADVANCE' && !f.installment ? f.amount : f.installment);
  const months = amt > 0 && inst > 0 ? Math.ceil(amt / inst) : null;
  const submit = async () => {
    const r = await run(() => papi.proposeLoan({ ...f, installment: f.installment || (f.kind === 'ADVANCE' ? f.amount : '') }));
    if (r) { push(t('ln.proposed')); onDone(); onClose(); }
  };
  return (
    <Modal open={open} title={t('ln.new')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy}
        disabled={!f.employee_id || !(amt > 0) || !(inst > 0) || inst > amt || f.reason.trim().length < 3} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <EmployeePicker label={t('c.employee')} value={f.employee_id} onChange={(v) => setF({ ...f, employee_id: v })} />
        <div className="form-grid">
          <Select label={t('ln.kind')} value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>
            <option value="LOAN">{t('ln.k_LOAN')}</option><option value="ADVANCE">{t('ln.k_ADVANCE')}</option>
          </Select>
          <Input label={t('ln.first_month')} type="month" ltr value={f.first_month} onChange={(e) => setF({ ...f, first_month: e.target.value })} />
          <Input label={t('ln.amount')} ltr inputMode="decimal" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} />
          <Input label={t('ln.installment')} ltr inputMode="decimal" value={f.installment} placeholder={f.kind === 'ADVANCE' ? f.amount : ''}
            hint={months ? `${t('ln.months_left')}: ${months}` : undefined} onChange={(e) => setF({ ...f, installment: e.target.value })} />
        </div>
        <Textarea label={t('c.reason')} required value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} />
      </div>
    </Modal>
  );
}
