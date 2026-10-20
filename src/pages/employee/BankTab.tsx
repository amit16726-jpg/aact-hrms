import { useState } from 'react';
import { api, type BankAccount, type EmployeeFile } from '../../lib/api';
import { useI18n } from '../../i18n';
import { Badge, Button, DateText, Empty, ErrorNote, Input, Loading, Modal, useAction, useAsync } from '../../components/ui';
import type { ConfirmFn } from './ProfileTab';

function BankFacts({ b }: { b: BankAccount }) {
  const { t } = useI18n();
  return (
    <dl className="facts">
      <dt>{t('bk.bank')}</dt><dd>{b.bank_name}{b.branch ? `, ${b.branch}` : ''}</dd>
      <dt>{t('bk.holder')}</dt><dd>{b.account_name}</dd>
      <dt>{t('bk.account')}</dt><dd className="num">{b.account_number}</dd>
      <dt>{t('bk.iban')}</dt><dd className="num">{b.iban ?? '—'}</dd>
      <dt>{t('bk.swift')}</dt><dd className="num">{b.swift_code ?? '—'}</dd>
      <dt>{t('as.effective_from')}</dt><dd><DateText v={b.effective_from} /></dd>
    </dl>
  );
}

const blank = { bank_name: '', branch: '', account_name: '', account_number: '', iban: '', swift_code: '', effective_from: '' };

export function BankTab({ file, confirm }: { file: EmployeeFile; confirm: ConfirmFn }) {
  const { t } = useI18n();
  const e = file.employee;
  const { data, error, loading, reload, setData } = useAsync(() => api.getBank(e.id), [e.id]);
  const [form, setForm] = useState<typeof blank | null>(null);
  const { busy, run } = useAction();

  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;

  const set = (k: keyof typeof blank, v: string) => setForm((s) => (s ? { ...s, [k]: v } : s));
  const submit = async () => {
    if (!form) return;
    const r = await run(() => api.requestBankChange(e.id, { ...form, effective_from: form.effective_from || null }), t('bk.pending'));
    if (r) { setData(r); setForm(null); }
  };
  const decide = async (approve: boolean) => {
    if (!data.pending) return;
    const note = await confirm({ title: t(approve ? 'bk.approve_title' : 'bk.reject_title'), body: t('bk.check_hint'),
      reason: approve ? 'optional' : 'required', reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    const r = await run(() => api.decideBank(data.pending!.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'));
    if (r) setData(r);
  };
  const anyMasked = data.current?.masked || data.pending?.masked;

  return (
    <div className="grid-2">
      <section className="panel">
        <div className="panel-head"><h2>{t('bk.current')}</h2>
          {file.caps.bank_write && !data.pending && e.status !== 'SEPARATED' &&
            <Button small kind="primary" onClick={() => setForm({ ...blank, account_name: e.full_name_en })}>{t('bk.request')}</Button>}
        </div>
        <div className="panel-body">
          {data.current ? <BankFacts b={data.current} /> : <Empty>{t('bk.none')}</Empty>}
          {anyMasked && <p className="muted" style={{ marginTop: 10, fontSize: 13 }}>{t('bk.masked')}</p>}
        </div>
      </section>

      {data.pending && (
        <section className="panel">
          <div className="panel-head"><h2>{t('bk.pending')}</h2><Badge tone="warn">{t('pay.PENDING')}</Badge></div>
          <div className="panel-body stack">
            <BankFacts b={data.pending} />
            <div className="muted" style={{ fontSize: 13.5 }}>{t('pay.proposed_by', { name: data.pending.requested_by_name ?? '' })}</div>
            {file.caps.bank_approve && (
              <div className="row">
                <Button kind="primary" busy={busy} onClick={() => void decide(true)}>{t('c.approve')}</Button>
                <Button kind="danger" busy={busy} onClick={() => void decide(false)}>{t('c.reject')}</Button>
              </div>
            )}
          </div>
        </section>
      )}

      {data.history.length > 0 && (
        <section className="panel" style={{ gridColumn: '1 / -1' }}>
          <div className="panel-head"><h2>{t('c.history')}</h2></div>
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('bk.bank')}</th><th>{t('bk.account')}</th><th>{t('as.effective_from')}</th><th>{t('c.status')}</th><th>{t('c.by')}</th></tr></thead>
            <tbody>{data.history.map((h) => (
              <tr key={h.id}>
                <td data-label={t('bk.bank')}>{h.bank_name}</td>
                <td data-label={t('bk.account')} className="num">{h.account_number}</td>
                <td data-label={t('as.effective_from')}><DateText v={h.effective_from} /></td>
                <td data-label={t('c.status')}><Badge tone={h.status === 'REJECTED' ? 'bad' : undefined}>{t(`pay.${h.status}` as 'pay.APPROVED')}</Badge>
                  {h.decision_note && <span className="sub">{h.decision_note}</span>}</td>
                <td data-label={t('c.by')}>{h.requested_by_name}<span className="sub">{h.decided_by_name}</span></td>
              </tr>))}
            </tbody></table></div>
        </section>
      )}

      <Modal open={!!form} title={t('bk.request')} onClose={() => setForm(null)}
        footer={<><Button onClick={() => setForm(null)}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void submit()}>{t('c.save')}</Button></>}>
        {form && (
          <div className="form-grid">
            <Input label={t('bk.bank')} required value={form.bank_name} onChange={(ev) => set('bank_name', ev.target.value)} />
            <Input label={t('bk.branch')} value={form.branch} onChange={(ev) => set('branch', ev.target.value)} />
            <Input label={t('bk.holder')} required className="span-2" value={form.account_name} onChange={(ev) => set('account_name', ev.target.value)} />
            <Input label={t('bk.account')} required ltr autoComplete="off" value={form.account_number} onChange={(ev) => set('account_number', ev.target.value)} />
            <Input label={t('bk.iban')} ltr autoComplete="off" placeholder="OM.." value={form.iban} onChange={(ev) => set('iban', ev.target.value.toUpperCase())} />
            <Input label={t('bk.swift')} ltr value={form.swift_code} onChange={(ev) => set('swift_code', ev.target.value.toUpperCase())} />
            <Input type="date" label={t('as.effective_from')} value={form.effective_from} onChange={(ev) => set('effective_from', ev.target.value)} />
          </div>
        )}
      </Modal>
    </div>
  );
}
