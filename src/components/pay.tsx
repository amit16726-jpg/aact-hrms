import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { translate, useI18n, type Key } from '../i18n';
import { Badge } from './ui';
import type { PayLine, Payslip, PayrollRun, RunStatus } from '../lib/api_pay';
import { fmtDate, fmtDateTime, fmtMoney } from '../lib/format';

export const OMR = (v: number | string | null | undefined) => fmtMoney(v, 3);

export function monthName(m: string, lang: 'en' | 'ar'): string {
  return new Date(`${m}-01T00:00:00`).toLocaleDateString(lang === 'ar' ? 'ar-OM' : 'en-GB', { month: 'long', year: 'numeric' });
}

export function RunBadge({ status }: { status: RunStatus }) {
  const { t } = useI18n();
  const tone = status === 'PAID' || status === 'APPROVED' ? 'ok' : status === 'VERIFIED' ? 'info' : status === 'CALCULATED' ? 'warn' : undefined;
  return <Badge tone={tone}>{t(`prs.${status}` as Key)}</Badge>;
}

/** Management (MG) or non-management (NMG) pay group. */
export function PayGroupBadge({ group, short }: { group?: 'NMG' | 'MG' | null; short?: boolean }) {
  const { t } = useI18n();
  const g = group ?? 'NMG';
  return <Badge tone={g === 'MG' ? 'warn' : undefined}>{short ? g : t(`pg.${g}` as Key)}</Badge>;
}

/** Calculated → verified → approved → paid, with who and when. */
export function RunSteps({ run }: { run: PayrollRun }) {
  const { t } = useI18n();
  const steps: { key: Key; by: string | null; at: string | null }[] = [
    { key: 'pr.step_calc', by: run.calculated_by_name, at: run.calculated_at },
    { key: 'pr.step_verify', by: run.verified_by_name, at: run.verified_at },
    { key: 'pr.step_approve', by: run.approved_by_name, at: run.approved_at },
    { key: 'pr.step_paid', by: run.paid_by_name, at: run.paid_at },
  ];
  const order: RunStatus[] = ['DRAFT', 'CALCULATED', 'VERIFIED', 'APPROVED', 'PAID'];
  const reached = order.indexOf(run.status);
  return (
    <ol className="steps" aria-label={t('pr.chain')}>
      {steps.map((s, i) => {
        const done = reached >= i + 1;
        return (
          <li key={s.key} className={done ? 'done' : reached === i ? 'next' : ''}>
            <b>{t(s.key)}</b>
            <span className="sub">{done && s.by ? `${s.by} · ${fmtDateTime(s.at)}` : '—'}</span>
          </li>);
      })}
    </ol>
  );
}

function Bi({ k, vars }: { k: Key; vars?: Record<string, string | number> }) {
  const { lang } = useI18n();
  const other = lang === 'ar' ? 'en' : 'ar';
  return <>{translate(lang, k, vars)}<span className="bi" lang={other}>{translate(other, k, vars)}</span></>;
}

function LineName({ l }: { l: PayLine }) {
  const { lang } = useI18n();
  return <>{lang === 'ar' ? l.name_ar : l.name_en}<span className="bi" lang={lang === 'ar' ? 'en' : 'ar'}>{lang === 'ar' ? l.name_en : l.name_ar}</span></>;
}

function LineTable({ lines, kind, total }: { lines: PayLine[]; kind: PayLine['kind']; total?: number }) {
  const { t } = useI18n();
  const rows = lines.filter((l) => l.kind === kind);
  if (!rows.length) return null;
  const head: Key = kind === 'EARNING' ? 'ps.earnings' : kind === 'DEDUCTION' ? 'ps.deductions' : 'ps.employer';
  return (
    <table className="t slip-lines">
      <thead><tr><th><Bi k={head} /></th><th className="r num">{t('ps.qty')}</th><th className="r num">{t('ps.rate')}</th><th className="r">OMR</th></tr></thead>
      <tbody>{rows.map((l) => (
        <tr key={l.id}><td><LineName l={l} /></td><td className="r num">{l.qty ?? ''}</td><td className="r num">{l.rate ?? ''}</td><td className="r num">{OMR(l.amount)}</td></tr>))}
      </tbody>
      {total !== undefined && <tfoot><tr><th colSpan={3}><Bi k={kind === 'EARNING' ? 'ps.total_earnings' : 'ps.total_deductions'} /></th><th className="r num">{OMR(total)}</th></tr></tfoot>}
    </table>
  );
}

/** A printable bilingual payslip. */
export function PayslipView({ slip, back }: { slip: Payslip; back?: ReactNode }) {
  const { t, L, lang } = useI18n();
  const draft = slip.run_status !== 'APPROVED' && slip.run_status !== 'PAID';
  return (
    <article className="slip panel panel-pad">
      <header className="slip-head">
        <div>
          <h2 style={{ margin: 0 }}>{L(slip.entity_en, slip.entity_ar)}</h2>
          {slip.entity_cr && <span className="sub">CR {slip.entity_cr}</span>}
        </div>
        <div className="slip-title">
          <b><Bi k="ps.title" /></b>
          <span className="num">{monthName(slip.month, lang)}</span>
          {draft && <Badge tone="warn">{t('ps.draft')}</Badge>}
        </div>
      </header>
      <dl className="kv slip-kv">
        <div><dt><Bi k="ps.employee" /></dt><dd>{L(slip.full_name_en, slip.full_name_ar)}<span className="sub num">{slip.employee_no}</span></dd></div>
        <div><dt><Bi k="ps.department" /></dt><dd>{L(slip.department_en, slip.department_ar) || '—'}</dd></div>
        <div><dt><Bi k="ps.job" /></dt><dd>{L(slip.job_en, slip.job_ar) || '—'}</dd></div>
        <div><dt><Bi k="ps.paid_days" /></dt><dd className="num">{slip.paid_days} / {slip.days_in_period}</dd></div>
        <div><dt><Bi k="ps.unpaid_days" /></dt><dd className="num">{slip.unpaid_days}</dd></div>
        <div><dt><Bi k="ps.basic" /></dt><dd className="num">{OMR(slip.basic)}</dd></div>
      </dl>
      <div className="slip-cols">
        <LineTable lines={slip.lines} kind="EARNING" total={slip.total_earnings} />
        <LineTable lines={slip.lines} kind="DEDUCTION" total={slip.total_deductions} />
      </div>
      <div className="slip-net"><span><Bi k="ps.net" /></span><b className="num">OMR {OMR(slip.net)}</b></div>
      <dl className="kv slip-kv">
        <div><dt><Bi k="ps.bank" /></dt><dd>{slip.bank_name ?? '—'}<span className="sub num">{slip.iban ?? slip.account_number ?? slip.account_masked ?? ''}</span></dd></div>
        <div><dt><Bi k="ps.pay_date" /></dt><dd className="num">{fmtDate(slip.pay_date)}</dd></div>
      </dl>
      <LineTable lines={slip.lines} kind="EMPLOYER" />
      {slip.warnings.length > 0 && (
        <div className="note note-warn no-print"><b>{t('ps.warnings')}</b><ul style={{ margin: '4px 0 0' }}>{slip.warnings.map((w, i) => <li key={i}>{w}</li>)}</ul></div>
      )}
      {back && <div className="no-print" style={{ marginTop: 12 }}>{back}</div>}
    </article>
  );
}

export function EmpLink({ id, no, en, ar }: { id: string; no: string; en: string; ar: string | null }) {
  const { L } = useI18n();
  return <><Link to={`/employees/${id}?tab=pay`}>{L(en, ar)}</Link><span className="sub num">{no}</span></>;
}
