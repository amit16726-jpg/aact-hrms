import { useEffect, useState } from 'react';
import { papi, type PayrollSetup } from '../../lib/api_pay';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Button, Check, ErrorNote, Input, Loading, useAction, useAsync } from '../../components/ui';
import { PageHead } from '../../components/Layout';

const ACCOUNTS = ['salary_expense', 'overtime_expense', 'spf_expense', 'eosb_expense', 'salary_payable', 'spf_payable', 'eosb_provision',
  'loans_receivable', 'deductions_income', 'income_tax_payable'];

export default function PayrollSetupPage() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload } = useAsync(() => papi.setup(), []);
  const [f, setF] = useState<PayrollSetup | null>(null);
  const { busy, run } = useAction();
  useEffect(() => { if (data) setF(JSON.parse(JSON.stringify(data)) as PayrollSetup); }, [data]);
  const edit = can('PAY_APPROVE');
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!f) return null;
  const save = async () => {
    const r = await run(() => papi.saveSetup({ entities: f.entities, components: f.components.map((c) => ({ code: c.code, gl_account: c.gl_account, spf_base: c.spf_base })),
      gl: f.gl, pay_day: f.pay_day ?? '28' }), t('psu.saved'));
    if (r) setF(JSON.parse(JSON.stringify(r)) as PayrollSetup);
  };
  return (
    <div className="stack">
      <PageHead title={t('psu.title')} actions={edit && <Button kind="primary" busy={busy} onClick={() => void save()}>{t('c.save')}</Button>} />
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('psu.companies')}</h2>
        <p className="muted" style={{ margin: 0 }}>{t('px.wps_hint')}</p>
        {f.entities.map((e, i) => (
          <div key={e.id} className="form-grid">
            <b className="span-2">{L(e.name_en, e.name_ar)} <span className="muted num">{e.code}</span></b>
            {(['cr_number', 'spf_employer_no', 'wps_bank_code', 'wps_account', 'wps_payer_cr'] as const).map((k) => (
              <Input key={k} ltr disabled={!edit} label={t(k === 'cr_number' ? 'psu.cr' : k === 'spf_employer_no' ? 'psu.spf_no' : k === 'wps_bank_code' ? 'psu.bank_code'
                : k === 'wps_account' ? 'psu.account' : 'psu.payer_cr')} value={e[k] ?? ''}
                onChange={(ev) => { const n = [...f.entities]; n[i] = { ...e, [k]: ev.target.value }; setF({ ...f, entities: n }); }} />))}
          </div>))}
        <div style={{ maxWidth: 260 }}><Input label={t('psu.pay_day')} ltr inputMode="numeric" disabled={!edit} value={String(f.pay_day ?? '').replace(/"/g, '')}
          onChange={(e) => setF({ ...f, pay_day: e.target.value })} /></div>
      </section>
      <section className="panel">
        <div className="panel-head"><h2>{t('psu.components')}</h2></div>
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('c.code')}</th><th>{t('pr.kind')}</th><th>{t('psu.gl')}</th><th>{t('psu.spf_base')}</th></tr></thead>
          <tbody>{f.components.map((c, i) => (
            <tr key={c.code}>
              <td data-label={t('c.code')}>{L(c.name_en, c.name_ar)}<span className="sub num">{c.code}{c.is_basic ? ` · ${t('psu.basic')}` : ''}</span></td>
              <td data-label={t('pr.kind')}>{t(`pr.k_${c.kind}` as Key)}</td>
              <td data-label={t('psu.gl')}><input className="input ltr" style={{ maxWidth: 160 }} disabled={!edit} aria-label={`${t('psu.gl')} ${c.code}`} value={c.gl_account ?? ''}
                onChange={(e) => { const n = [...f.components]; n[i] = { ...c, gl_account: e.target.value }; setF({ ...f, components: n }); }} /></td>
              <td data-label={t('psu.spf_base')}>{c.kind === 'EARNING' && <Check label={t('psu.spf_base')} disabled={!edit} checked={c.spf_base}
                onChange={(v) => { const n = [...f.components]; n[i] = { ...c, spf_base: v }; setF({ ...f, components: n }); }} />}</td>
            </tr>))}
          </tbody></table></div>
      </section>
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('psu.accounts')}</h2>
        <div className="form-grid">
          {ACCOUNTS.map((k) => <Input key={k} ltr disabled={!edit} label={t(`psu.a_${k}` as Key)} value={f.gl[k] ?? ''} onChange={(e) => setF({ ...f, gl: { ...f.gl, [k]: e.target.value } })} />)}
        </div>
      </section>
    </div>
  );
}
