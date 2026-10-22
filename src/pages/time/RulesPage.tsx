import { useEffect, useState } from 'react';
import { tapi, type RuleCode, type TimeRule } from '../../lib/api_time';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, DateText, ErrorNote, Input, Loading, Modal, Select, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { addDays, fmtDate, fmtDateTime, todayMuscat } from '../../lib/format';
import { ArrowRight, Building2, CalendarClock, CalendarDays, ChevronDown, CircleCheck, Clock, Fingerprint, History, Hourglass, MoonStar, PencilLine, Scale, Timer, TriangleAlert } from 'lucide-react';

export const RULE_KEYS: Record<RuleCode, string[]> = {
  WORK_HOURS: ['daily_max_hours', 'weekly_max_hours', 'break_minutes', 'max_continuous_hours'],
  RAMADAN_HOURS: ['daily_max_hours', 'weekly_max_hours'],
  WEEKLY_REST: ['min_consecutive_days'],
  OVERTIME: ['day_premium', 'night_premium', 'rest_day_premium', 'max_total_daily_hours', 'night_start', 'night_end'],
  OVERTIME_NO_CONSENT: ['day_premium', 'night_premium', 'rest_day_premium', 'max_inventory_days_per_year'],
  ATTENDANCE: ['late_grace_minutes', 'window_before_minutes', 'window_after_minutes', 'min_minutes_between_punches'],
};
const CODES = Object.keys(RULE_KEYS) as RuleCode[];
const TEXT_KEYS = new Set(['night_start', 'night_end']);

type Phase = 'current' | 'future' | 'past' | 'pending' | 'rejected';
function phase(r: TimeRule, today: string): Phase {
  if (r.status === 'PENDING') return 'pending';
  if (r.status === 'REJECTED') return 'rejected';
  if (r.effective_from > today) return 'future';
  if (r.effective_to && r.effective_to < today) return 'past';
  return 'current';
}

export function RuleValues({ code, value }: { code: RuleCode; value: Record<string, number | string> }) {
  const { t } = useI18n();
  return (
    <dl className="kv">{RULE_KEYS[code].map((k) => <div key={k}><dt>{t(`rk.${k}` as Key)}</dt><dd className="num">{String(value[k] ?? '—')}</dd></div>)}</dl>
  );
}

type Unit = 'h' | 'min' | 'days' | 'pct' | 'time';
const UNITS: Record<string, Unit> = {
  daily_max_hours: 'h', weekly_max_hours: 'h', max_continuous_hours: 'h', max_total_daily_hours: 'h',
  break_minutes: 'min', late_grace_minutes: 'min', window_before_minutes: 'min', window_after_minutes: 'min', min_minutes_between_punches: 'min',
  min_consecutive_days: 'days', max_inventory_days_per_year: 'days',
  day_premium: 'pct', night_premium: 'pct', rest_day_premium: 'pct', night_start: 'time', night_end: 'time',
};
const ICONS: Record<RuleCode, typeof Clock> = {
  WORK_HOURS: Clock, RAMADAN_HOURS: MoonStar, WEEKLY_REST: CalendarDays, OVERTIME: Timer, OVERTIME_NO_CONSENT: TriangleAlert, ATTENDANCE: Fingerprint,
};
const GROUPS: { key: 'TIME' | 'OT' | 'ATT'; codes: RuleCode[] }[] = [
  { key: 'TIME', codes: ['WORK_HOURS', 'RAMADAN_HOURS', 'WEEKLY_REST'] },
  { key: 'OT', codes: ['OVERTIME', 'OVERTIME_NO_CONSENT'] },
  { key: 'ATT', codes: ['ATTENDANCE'] },
];

/** A rule value split into the number and its unit, e.g. 0.25 → "+25" "%". */
function useValueText() {
  const { t } = useI18n();
  return (k: string, v: number | string | undefined): { num: string; unit: string } => {
    if (v === undefined || v === null || v === '') return { num: '—', unit: '' };
    const u = UNITS[k];
    if (u === 'pct') { const n = Math.round(Number(v) * 10000) / 100; return { num: `+${n}`, unit: '%' }; }
    if (u === 'time') return { num: String(v), unit: '' };
    if (u === 'h' || u === 'min' || u === 'days') return { num: String(v), unit: t(`u.${u}` as Key) };
    return { num: String(v), unit: '' };
  };
}

function Metric({ k, v }: { k: string; v: number | string | undefined }) {
  const { t } = useI18n();
  const vt = useValueText();
  const x = vt(k, v);
  return (
    <div className="tr-metric">
      {x.unit === '%'
        ? <div className="tr-metric-val"><span dir="ltr" className="num">{x.num}<span className="tr-unit">%</span></span></div>
        : <div className="tr-metric-val"><bdi dir="ltr" className="num">{x.num}</bdi>{x.unit && <span className="tr-unit">{x.unit}</span>}</div>}
      <div className="tr-metric-label">{t(`rl.${k}` as Key)}</div>
    </div>
  );
}

/** Old → new values of a proposed or scheduled version, changed rows highlighted. */
function ChangeTable({ code, cur, next }: { code: RuleCode; cur: TimeRule | undefined; next: TimeRule }) {
  const { t } = useI18n();
  const vt = useValueText();
  const keys = RULE_KEYS[code];
  const show = (k: string, v: number | string | undefined) => { const x = vt(k, v); return `${x.num}${x.unit ? (x.unit === '%' ? '%' : ` ${x.unit}`) : ''}`; };
  const changed = keys.filter((k) => String(cur?.value[k] ?? '') !== String(next.value[k] ?? ''));
  if (cur && changed.length === 0) return <div className="muted small">{t('rule.no_change')}</div>;
  return (
    <table className="tr-diff">
      <thead><tr><th>{t('rule.col_value')}</th><th>{t('rule.col_now')}</th><th aria-hidden="true" /><th>{t('rule.col_new')}</th></tr></thead>
      <tbody>{(cur ? changed : keys).map((k) => (
        <tr key={k}><td>{t(`rl.${k}` as Key)}</td><td className="num" dir="ltr">{cur ? show(k, cur.value[k]) : '—'}</td>
          <td aria-hidden="true"><ArrowRight size={14} className="tr-arrow" /></td><td className="num tr-new" dir="ltr">{show(k, next.value[k])}</td></tr>))}
      </tbody>
    </table>
  );
}

function BasisChip({ basis }: { basis: TimeRule['rule_basis'] }) {
  const { t } = useI18n();
  const Icon = basis === 'LEGAL' ? Scale : Building2;
  return <span className={`tr-basis ${basis === 'LEGAL' ? 'is-law' : 'is-policy'}`}><Icon size={13} aria-hidden="true" />{t(`rule.${basis}` as Key)}</span>;
}

export default function RulesPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload, setData } = useAsync(() => tapi.listTimeRules(), []);
  const [prop, setProp] = useState<TimeRule | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const today = todayMuscat();

  const decide = async (r: TimeRule, approve: boolean) => {
    const note = await confirm.ask({ title: `${t(`rule.${r.code}` as Key)} — ${r.effective_from}`, body: <RuleValues code={r.code} value={r.value} />,
      reason: approve ? 'optional' : 'required', reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    const res = await run(() => tapi.decideTimeRule(r.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'));
    if (res) setData(res);
  };

  const all = data ?? [];
  const inForce = CODES.filter((c) => all.some((r) => r.code === c && phase(r, today) === 'current')).length;
  const pendingN = all.filter((r) => r.status === 'PENDING').length;
  const futureN = all.filter((r) => phase(r, today) === 'future').length;
  const lastDecided = all.filter((r) => r.status === 'APPROVED' && r.decided_at).map((r) => r.decided_at as string).sort().pop() ?? null;

  const card = (code: RuleCode) => {
    const rows = all.filter((r) => r.code === code).sort((a, b) => b.effective_from.localeCompare(a.effective_from));
    const cur = rows.find((r) => phase(r, today) === 'current');
    const pend = rows.filter((r) => phase(r, today) === 'pending');
    const fut = rows.filter((r) => phase(r, today) === 'future');
    const hist = rows.filter((r) => phase(r, today) === 'past' || phase(r, today) === 'rejected');
    const Icon = ICONS[code];
    return (
      <section key={code} className="tr-card" aria-labelledby={`tr-${code}`}>
        <header className="tr-head">
          <span className="tr-icon" aria-hidden="true"><Icon size={20} /></span>
          <div className="tr-title">
            <h3 id={`tr-${code}`}>{t(`rule.${code}` as Key)}</h3>
            <p>{t(`rule.d_${code}` as Key)}</p>
          </div>
          {cur && <div className="tr-head-end"><BasisChip basis={cur.rule_basis} /></div>}
        </header>

        {pend.map((r) => (
          <div key={r.id} className="tr-change is-pending">
            <div className="tr-change-head">
              <Hourglass size={16} aria-hidden="true" />
              <b>{t('rule.pending_title')}</b>
              <span className="muted">· {t('rule.starts', { d: fmtDate(r.effective_from) })}</span>
            </div>
            <ChangeTable code={code} cur={cur} next={r} />
            <div className="tr-change-foot">
              <span className="muted small">{t('rule.proposed_by', { n: r.proposed_by_name ?? '—', t: fmtDateTime(r.proposed_at) })}</span>
              {r.can_decide && <span className="row" style={{ gap: 6 }}>
                <Button small kind="primary" busy={busy} onClick={() => void decide(r, true)}>{t('c.approve')}</Button>
                <Button small kind="danger" busy={busy} onClick={() => void decide(r, false)}>{t('c.reject')}</Button></span>}
            </div>
          </div>))}

        {fut.map((r) => (
          <div key={r.id} className="tr-change is-future">
            <div className="tr-change-head">
              <CalendarClock size={16} aria-hidden="true" />
              <b>{t('rule.future_title')}</b>
              <span className="muted">· {t('rule.starts', { d: fmtDate(r.effective_from) })}</span>
            </div>
            <ChangeTable code={code} cur={cur} next={r} />
          </div>))}

        {cur ? (
          <div className={`tr-metrics n${RULE_KEYS[code].length}`}>
            {RULE_KEYS[code].map((k) => <Metric key={k} k={k} v={cur.value[k]} />)}
          </div>
        ) : <div className="tr-empty">{t('rule.none_in_force')}</div>}
        {(code === 'OVERTIME' || code === 'OVERTIME_NO_CONSENT') && cur && <p className="tr-hint">{t('rule.premium_hint')}</p>}

        {cur && (
          <footer className="tr-foot">
            <div className="tr-foot-info">
              <div className="tr-ref"><Scale size={14} aria-hidden="true" /><span><span className="tr-ref-label">{t('rule.reference')}:</span> {cur.legal_basis}</span></div>
              <div className="tr-since">
                <CircleCheck size={14} aria-hidden="true" />
                <span>{t('rule.since', { d: fmtDate(cur.effective_from) })}{cur.decided_by_name && <> · {t('rule.by', { n: cur.decided_by_name })}</>}</span>
              </div>
            </div>
            {can('RULES_PROPOSE') && pend.length === 0 && (
              <Button small onClick={() => setProp(cur)}><PencilLine size={14} aria-hidden="true" /> {t('rule.propose')}</Button>)}
          </footer>)}

        {hist.length > 0 && (
          <details className="tr-history">
            <summary><History size={14} aria-hidden="true" /> {t('rule.history', { n: hist.length })}<ChevronDown size={14} className="tr-chev" aria-hidden="true" /></summary>
            <ol>{hist.map((r) => {
              const ph = phase(r, today);
              return (
                <li key={r.id}>
                  <div className="row" style={{ gap: 8, justifyContent: 'space-between' }}>
                    <span><Badge tone={ph === 'rejected' ? 'bad' : undefined}>{ph === 'rejected' ? t('rst.REJECTED') : t('rule.past')}</Badge>{' '}
                      <span className="num"><DateText v={r.effective_from} />{r.effective_to && <> – <DateText v={r.effective_to} /></>}</span></span>
                    <BasisChip basis={r.rule_basis} />
                  </div>
                  <RuleValues code={code} value={r.value} />
                  <div className="muted small">{r.legal_basis}{r.proposed_by_name && <> · {r.proposed_by_name}</>}
                    {r.decided_by_name && <> → {r.decided_by_name}</>}{r.decision_note && <> — {r.decision_note}</>}</div>
                </li>);
            })}</ol>
          </details>)}
      </section>
    );
  };

  return (
    <div className="stack tr-page">
      <PageHead title={t('rule.title')} sub={t('rule.hint')} />
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : (
        <>
          <div className="tr-stats">
            <div className="tr-stat"><span className="tr-stat-num num">{inForce} / {CODES.length}</span><span className="tr-stat-label">{t('rule.s_inforce')}</span></div>
            <div className={`tr-stat ${pendingN ? 'is-warn' : ''}`}><span className="tr-stat-num num">{pendingN}</span><span className="tr-stat-label">{t('rule.s_pending')}</span></div>
            <div className="tr-stat"><span className="tr-stat-num num">{futureN}</span><span className="tr-stat-label">{t('rule.s_future')}</span></div>
            <div className="tr-stat"><span className="tr-stat-num num">{lastDecided ? fmtDate(lastDecided.slice(0, 10)) : '—'}</span><span className="tr-stat-label">{t('rule.s_last')}</span></div>
          </div>
          {GROUPS.map((g) => (
            <section key={g.key} className="tr-group" aria-labelledby={`trg-${g.key}`}>
              <div className="tr-group-head">
                <h2 id={`trg-${g.key}`}>{t(`rule.g_${g.key}` as Key)}</h2>
                <p>{t(`rule.gd_${g.key}` as Key)}</p>
              </div>
              <div className={`tr-grid ${g.codes.length === 1 ? 'is-single' : g.codes.length === 3 ? 'is-three' : ''}`}>{g.codes.map(card)}</div>
            </section>))}
        </>
      )}
      <ProposeDialog base={prop} onClose={() => setProp(null)} onDone={(d) => setData(d)} />
      {confirm.node}
    </div>
  );
}

function ProposeDialog({ base, onClose, onDone }: { base: TimeRule | null; onClose: () => void; onDone: (d: TimeRule[]) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [vals, setVals] = useState<Record<string, string>>({});
  const [from, setFrom] = useState(addDays(todayMuscat(), 1));
  const [basis, setBasis] = useState<'LEGAL' | 'COMPANY_POLICY'>('LEGAL');
  const [legal, setLegal] = useState('');
  useEffect(() => {
    if (!base) return;
    setVals(Object.fromEntries(RULE_KEYS[base.code].map((k) => [k, String(base.value[k] ?? '')])));
    setFrom(addDays(todayMuscat(), 1)); setBasis(base.rule_basis); setLegal(base.legal_basis);
  }, [base]);
  if (!base) return null;
  const keys = RULE_KEYS[base.code];
  const badKey = keys.find((k) => TEXT_KEYS.has(k) ? !/^\d{2}:\d{2}$/.test(vals[k] ?? '') : !(vals[k] !== '' && Number.isFinite(Number(vals[k])) && Number(vals[k]) >= 0));
  const submit = async () => {
    const value = Object.fromEntries(keys.map((k) => [k, TEXT_KEYS.has(k) ? vals[k] : Number(vals[k])]));
    const r = await run(() => tapi.proposeTimeRule({ code: base.code, value, effective_from: from, rule_basis: basis, legal_basis: legal }), t('rule.proposed'));
    if (r) { onDone(r); onClose(); }
  };
  return (
    <Modal open title={`${t('rule.propose')} — ${t(`rule.${base.code}` as Key)}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!!badKey || !from || legal.trim().length < 3} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="form-grid">
        {keys.map((k) => (
          <Input key={k} label={t(`rk.${k}` as Key)} ltr type={TEXT_KEYS.has(k) ? 'time' : 'text'} inputMode={TEXT_KEYS.has(k) ? undefined : 'decimal'}
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
