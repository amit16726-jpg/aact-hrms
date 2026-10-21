import { useEffect, useState } from 'react';
import { papi, type PayRule, type PayRuleCode } from '../../lib/api_pay';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, DateText, ErrorNote, Input, Loading, Modal, Select, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { addDays, fmtDateTime, todayMuscat } from '../../lib/format';

export const PAY_RULE_KEYS: Record<PayRuleCode, string[]> = {
  SPF_OMANI: ['er_old_age', 'ee_old_age', 'er_injury', 'er_job_security', 'ee_job_security', 'er_maternity', 'er_sick', 'ceiling'],
  SPF_EXPAT: ['er_maternity', 'er_sick', 'er_injury', 'ceiling'],
  GRATUITY: ['cutoff', 'old_first_years', 'old_first_days', 'old_after_days', 'new_days', 'min_service_months'],
  SAVINGS_EXPAT: ['employer_pct', 'active'],
  DEDUCTIONS: ['max_pct'],
  INCOME_TAX: ['rate_pct', 'annual_threshold', 'active'],
  PAY_BASIS: ['days_divisor', 'hours_per_day', 'absent_unpaid', 'missing_punch_unpaid', 'fund_leave_unpaid'],
};
const CODES = Object.keys(PAY_RULE_KEYS) as PayRuleCode[];
const DATE_KEYS = new Set(['cutoff']);

type Phase = 'current' | 'future' | 'past' | 'pending' | 'rejected';
function phase(r: PayRule, today: string): Phase {
  if (r.status === 'PENDING') return 'pending';
  if (r.status === 'REJECTED') return 'rejected';
  if (r.effective_from > today) return 'future';
  if (r.effective_to && r.effective_to < today) return 'past';
  return 'current';
}

export function PayRuleValues({ code, value }: { code: PayRuleCode; value: Record<string, number | string> }) {
  const { t } = useI18n();
  return <dl className="kv">{PAY_RULE_KEYS[code].map((k) => <div key={k}><dt>{t(`prk.${k}` as Key)}</dt><dd className="num">{String(value[k] ?? '—')}</dd></div>)}</dl>;
}

export default function PayRulesPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload, setData } = useAsync(() => papi.listPayRules(), []);
  const [prop, setProp] = useState<PayRule | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const today = todayMuscat();
  const decide = async (r: PayRule, approve: boolean) => {
    const note = await confirm.ask({ title: `${t(`prl.${r.code}` as Key)} — ${r.effective_from}`, body: <PayRuleValues code={r.code} value={r.value} />,
      reason: approve ? 'optional' : 'required', reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    const res = await run(() => papi.decidePayRule(r.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'));
    if (res) setData(res);
  };
  return (
    <div className="stack">
      <PageHead title={t('prl.title')} />
      <div className="note">{t('prl.hint')}</div>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : (
        <div className="grid-2" style={{ alignItems: 'start' }}>
          {CODES.map((code) => {
            const rows = (data ?? []).filter((r) => r.code === code).sort((a, b) => b.effective_from.localeCompare(a.effective_from));
            const base = rows.find((r) => phase(r, today) === 'current') ?? rows.find((r) => r.status === 'APPROVED');
            const pending = rows.some((r) => r.status === 'PENDING');
            return (
              <section key={code} className="panel">
                <div className="panel-head"><h2>{t(`prl.${code}` as Key)}</h2>
                  {can('RULES_PROPOSE') && base && !pending && <Button small onClick={() => setProp(base)}>{t('rule.propose')}</Button>}</div>
                <div className="panel-pad stack">
                  {rows.map((r) => {
                    const ph = phase(r, today);
                    return (
                      <div key={r.id} className="rule-card" style={{ opacity: ph === 'past' || ph === 'rejected' ? 0.6 : 1 }}>
                        <div className="row" style={{ gap: 8, justifyContent: 'space-between' }}>
                          <div><Badge tone={ph === 'current' ? 'ok' : ph === 'pending' ? 'warn' : ph === 'future' ? 'info' : ph === 'rejected' ? 'bad' : undefined}>
                            {ph === 'rejected' ? t('rst.REJECTED') : t(`rule.${ph}` as Key)}</Badge>{' '}
                            <span className="num"><DateText v={r.effective_from} />{r.effective_to && <> – <DateText v={r.effective_to} /></>}</span></div>
                          <Badge>{t(`rule.${r.rule_basis}` as Key)}</Badge>
                        </div>
                        <PayRuleValues code={code} value={r.value} />
                        <div className="muted small">{r.legal_basis}</div>
                        {r.proposed_by_name && <div className="muted small">{r.proposed_by_name} · {fmtDateTime(r.proposed_at)}
                          {r.decided_by_name && <> → {r.decided_by_name} · {fmtDateTime(r.decided_at)}</>}{r.decision_note && <> — {r.decision_note}</>}</div>}
                        {r.can_decide && <div className="row" style={{ gap: 6, marginTop: 6 }}>
                          <Button small kind="primary" busy={busy} onClick={() => void decide(r, true)}>{t('c.approve')}</Button>
                          <Button small kind="danger" busy={busy} onClick={() => void decide(r, false)}>{t('c.reject')}</Button></div>}
                      </div>);
                  })}
                </div>
              </section>);
          })}
        </div>
      )}
      <ProposeDialog base={prop} onClose={() => setProp(null)} onDone={(d) => setData(d)} />
      {confirm.node}
    </div>
  );
}

function ProposeDialog({ base, onClose, onDone }: { base: PayRule | null; onClose: () => void; onDone: (d: PayRule[]) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [vals, setVals] = useState<Record<string, string>>({});
  const [from, setFrom] = useState(addDays(todayMuscat(), 1));
  const [basis, setBasis] = useState<'LEGAL' | 'COMPANY_POLICY'>('LEGAL');
  const [legal, setLegal] = useState('');
  useEffect(() => {
    if (!base) return;
    setVals(Object.fromEntries(PAY_RULE_KEYS[base.code].map((k) => [k, String(base.value[k] ?? '')])));
    setFrom(addDays(todayMuscat(), 1)); setBasis(base.rule_basis); setLegal(base.legal_basis);
  }, [base]);
  if (!base) return null;
  const keys = PAY_RULE_KEYS[base.code];
  const badKey = keys.find((k) => DATE_KEYS.has(k) ? !/^\d{4}-\d{2}-\d{2}$/.test(vals[k] ?? '') : !(vals[k] !== '' && Number.isFinite(Number(vals[k])) && Number(vals[k]) >= 0));
  const submit = async () => {
    const value = Object.fromEntries(keys.map((k) => [k, DATE_KEYS.has(k) ? vals[k] : Number(vals[k])]));
    const r = await run(() => papi.proposePayRule({ code: base.code, value, effective_from: from, rule_basis: basis, legal_basis: legal }), t('rule.proposed'));
    if (r) { onDone(r); onClose(); }
  };
  return (
    <Modal open title={`${t('rule.propose')} — ${t(`prl.${base.code}` as Key)}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!!badKey || !from || legal.trim().length < 3} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="form-grid">
        {keys.map((k) => (
          <Input key={k} label={t(`prk.${k}` as Key)} ltr type={DATE_KEYS.has(k) ? 'date' : 'text'} inputMode={DATE_KEYS.has(k) ? undefined : 'decimal'}
            value={vals[k] ?? ''} error={badKey === k && vals[k] !== '' ? t('err.INVALID_NUMBER') : undefined}
            onChange={(e) => setVals({ ...vals, [k]: e.target.value })} />))}
        <Input label={t('la.effective')} type="date" ltr required value={from} onChange={(e) => setFrom(e.target.value)} />
        <Select label={t('rule.basis')} value={basis} onChange={(e) => setBasis(e.target.value as 'LEGAL' | 'COMPANY_POLICY')}>
          <option value="LEGAL">{t('rule.LEGAL')}</option><option value="COMPANY_POLICY">{t('rule.COMPANY_POLICY')}</option>
        </Select>
        <Input label={t('rule.legal')} className="span-2" required value={legal} onChange={(e) => setLegal(e.target.value)} />
      </div>
    </Modal>
  );
}
