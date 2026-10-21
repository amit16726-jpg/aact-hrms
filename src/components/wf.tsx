import { useEffect, useState } from 'react';
import { useI18n, type Key } from '../i18n';
import { Badge, Button, ErrorNote, Input, Loading, useAction, useAsync } from './ui';
import { EmployeePicker } from './pickers';
import { REVIEW_STEPS, wfapi, type CaseStatus, type ExitCase, type Injury, type PerfPlan, type ReviewStatus } from '../lib/api_wf';

export function ReviewBadge({ s }: { s: ReviewStatus }) {
  const { t } = useI18n();
  return <Badge tone={s === 'DONE' ? 'ok' : s === 'ACK' ? 'info' : 'warn'}>{t(`pf.st_${s}` as Key)}</Badge>;
}

/** The five review steps with the current one highlighted. */
export function ReviewSteps({ s }: { s: ReviewStatus }) {
  const { t } = useI18n();
  const at = REVIEW_STEPS.indexOf(s);
  return (
    <ol className="steps steps-5" aria-label={t('pf.rating')}>
      {REVIEW_STEPS.map((x, i) => <li key={x} className={i < at ? 'done' : i === at ? 'now' : ''} aria-current={i === at ? 'step' : undefined}>{t(`pf.st_${x}` as Key)}</li>)}
    </ol>
  );
}

export function PlanBadge({ s }: { s: PerfPlan['status'] }) {
  const { t } = useI18n();
  return <Badge tone={s === 'ACTIVE' ? 'warn' : s === 'IMPROVED' ? 'ok' : s === 'NOT_IMPROVED' ? 'bad' : undefined}>{t(`ip.st_${s}` as Key)}</Badge>;
}

export function CaseBadge({ s }: { s: CaseStatus }) {
  const { t } = useI18n();
  return <Badge tone={s === 'DECIDED' ? 'bad' : s === 'DISMISSED' ? undefined : s === 'PROPOSED' ? 'warn' : 'info'}>{t(`dc.st_${s}` as Key)}</Badge>;
}

export function SeverityBadge({ s }: { s: Injury['severity'] }) {
  const { t } = useI18n();
  return <Badge tone={s === 'FIRST_AID' ? undefined : s === 'MEDICAL' ? 'info' : s === 'LOST_TIME' ? 'warn' : 'bad'}>{t(`in.sev_${s}` as Key)}</Badge>;
}

export function ExitBadge({ s }: { s: ExitCase['status'] }) {
  const { t } = useI18n();
  return <Badge tone={s === 'OPEN' ? 'warn' : s === 'COMPLETED' ? 'ok' : undefined}>{t(`ex.st_${s}` as Key)}</Badge>;
}

/** 1–5 rating as a select (empty = not rated). */
export function RatingSelect({ value, onChange, label, disabled }: { value: number | null | undefined; onChange: (v: number | null) => void; label: string; disabled?: boolean }) {
  return (
    <select className="select rating-select" aria-label={label} value={value ?? ''} disabled={disabled}
      onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)}>
      <option value="">—</option>
      {[1, 2, 3, 4, 5].map((n) => <option key={n} value={n}>{n}</option>)}
    </select>
  );
}

/** Choose several employees: a picker plus removable chips. */
export function MultiEmployeePicker({ value, onChange, label }: { value: { id: string; label: string }[]; onChange: (v: { id: string; label: string }[]) => void; label: string }) {
  const { t } = useI18n();
  const [k, setK] = useState(0);
  return (
    <div className="stack" style={{ gap: 6 }}>
      <EmployeePicker key={k} label={label} value={null} onChange={(id, l) => {
        if (id && !value.some((x) => x.id === id)) onChange([...value, { id, label: l ?? id }]);
        setK((n) => n + 1);
      }} />
      {value.length > 0 && <div className="chips">{value.map((x) => (
        <span key={x.id} className="chip">{x.label}
          <button type="button" className="chip-x" aria-label={`${t('c.remove')} ${x.label}`} onClick={() => onChange(value.filter((y) => y.id !== x.id))}>✕</button></span>))}
      </div>}
    </div>
  );
}

/** Settings panel: the HR policy limits that a company may set (Labour Law values shown read-only). */
export function HrPoliciesPanel() {
  const { t } = useI18n();
  const { data, error, loading, reload } = useAsync(() => wfapi.policies(), []);
  const { busy, run } = useAction();
  const [f, setF] = useState({ ded: '', susp: '', inj: '' });
  useEffect(() => { if (data) setF({ ded: String(data.discipline_max_deduction_days), susp: String(data.discipline_max_suspension_days), inj: String(data.injury_report_days) }); }, [data]);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  const save = async () => {
    if (await run(() => wfapi.savePolicies({ discipline_max_deduction_days: Number(f.ded), discipline_max_suspension_days: Number(f.susp), injury_report_days: Number(f.inj) }), t('hp.saved'))) void reload();
  };
  return (
    <section className="panel panel-pad stack">
      <h2 style={{ margin: 0 }}>{t('hp.title')}</h2>
      <p className="muted" style={{ margin: 0 }}>{t('hp.hint')}</p>
      <div className="grid-3">
        <Input label={t('hp.ded')} type="number" min={0} max={30} step="0.5" ltr value={f.ded} onChange={(e) => setF({ ...f, ded: e.target.value })} hint={data.discipline_legal_basis} />
        <Input label={t('hp.susp')} type="number" min={0} max={30} ltr value={f.susp} onChange={(e) => setF({ ...f, susp: e.target.value })} />
        <Input label={t('hp.injury')} type="number" min={1} max={30} ltr value={f.inj} onChange={(e) => setF({ ...f, inj: e.target.value })} hint={data.injury_legal_basis} />
      </div>
      <dl className="kv">
        <div><dt>{t('ip.title')}</dt><dd>{data.pip_min_months} · <span className="muted">{data.pip_legal_basis}</span></dd></div>
        <div><dt>{t('ex.notice_given')}</dt><dd className="num">{data.notice_monthly_days} / {data.notice_other_days} · <span className="muted">{data.notice_legal_basis}</span></dd></div>
        <div><dt>{t('ex.non_compete', { n: data.non_compete_max_months })}</dt><dd><span className="muted">{data.non_compete_legal_basis}</span></dd></div>
      </dl>
      <div className="muted">{t('hp.fixed')}</div>
      <div><Button kind="primary" busy={busy} onClick={() => void save()}>{t('c.save')}</Button></div>
    </section>
  );
}
