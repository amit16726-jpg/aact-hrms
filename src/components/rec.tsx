import { useEffect, useState } from 'react';
import { recapi, type Interviewer, type OfferStatus, type ReqStatusRec, type Stage, type HireOmanisation, type OmaniRow } from '../lib/api_rec';
import { useI18n, type Key } from '../i18n';
import { Badge, Field } from './ui';
import { fmtPct } from '../lib/format';

export function ReqBadgeRec({ s }: { s: ReqStatusRec }) {
  const { t } = useI18n();
  const tone = s === 'APPROVED' ? 'info' : s === 'FILLED' ? 'ok' : s === 'PENDING' || s === 'ON_HOLD' ? 'warn' : s === 'REJECTED' ? 'bad' : undefined;
  return <Badge tone={tone}>{t(`rq2.st_${s}` as Key)}</Badge>;
}

export function StageBadge({ s }: { s: Stage }) {
  const { t } = useI18n();
  const tone = s === 'HIRED' ? 'ok' : s === 'OFFER' ? 'info' : s === 'REJECTED' || s === 'WITHDRAWN' ? 'bad' : s === 'INTERVIEW' ? 'warn' : undefined;
  return <Badge tone={tone}>{t(`stg.${s}` as Key)}</Badge>;
}

export function OfferBadge({ s }: { s: OfferStatus }) {
  const { t } = useI18n();
  const tone = s === 'ACCEPTED' ? 'ok' : s === 'APPROVED' ? 'info' : s === 'PENDING' ? 'warn' : 'bad';
  return <Badge tone={tone}>{t(`of.st_${s}` as Key)}</Badge>;
}

/** 1–5 rating shown as filled and empty stars, with the number for screen readers. */
export function Stars({ n }: { n: number | null | undefined }) {
  const { t } = useI18n();
  if (n === null || n === undefined) return <span className="muted">—</span>;
  const r = Math.round(n);
  return <span className="stars" aria-label={`${t('ap2.rating')}: ${n} / 5`}>{'★'.repeat(r)}<span className="muted">{'★'.repeat(5 - r)}</span> <span className="num">{n}</span></span>;
}

export function InterviewerSelect({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  const { t, L } = useI18n();
  const [rows, setRows] = useState<Interviewer[]>([]);
  useEffect(() => { recapi.interviewers().then(setRows).catch(() => setRows([])); }, []);
  return (
    <Field label={label} required htmlFor="iv-who">
      <select id="iv-who" className="select" value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">{t('c.select')}</option>
        {rows.map((r) => <option key={r.user_id} value={r.user_id}>{r.name}{r.job_en ? ` — ${L(r.job_en, r.job_ar)}` : ''}</option>)}
      </select>
    </Field>
  );
}

function OmRow({ label, r }: { label: string; r: OmaniRow }) {
  const { t } = useI18n();
  return (
    <div className="tile"><span>{label}</span><b>{r.pct === null ? '—' : fmtPct(r.pct)}</b>
      <span>{r.omani} / {r.total}{r.target_pct !== null ? ` · ${t('rq2.om_target')} ${fmtPct(r.target_pct)}` : ''}</span></div>
  );
}

/** The Omanisation check shown before hiring. */
export function OmanisationCheck({ o }: { o: HireOmanisation }) {
  const { t } = useI18n();
  return (
    <section className="panel panel-pad stack">
      <h2 style={{ margin: 0 }}>{t('rq2.omanisation')}</h2>
      {o.job_omani_only && <div className="note note-warn">{t('rq2.omani_only_job', { s: o.job_omani_only_source ?? '—' })}</div>}
      <div className="tile-row">
        <OmRow label={t('rq2.om_now')} r={o.entity} />
        <OmRow label={t('rq2.om_dept')} r={o.department} />
        <div className="tile"><span>{t('rq2.om_if_omani')}</span><b className="ok-text">{o.pct_if_omani === null ? '—' : fmtPct(o.pct_if_omani)}</b></div>
        {!o.job_omani_only && <div className="tile"><span>{t('rq2.om_if_expat')}</span><b className={o.expat_breaks_target ? 'bad-text' : ''}>{o.pct_if_expat === null ? '—' : fmtPct(o.pct_if_expat)}</b></div>}
      </div>
      {o.target_pct === null && <div className="muted">{t('rq2.om_no_target')}</div>}
      {o.expat_breaks_target && !o.job_omani_only && <div className="note note-bad">{t('rq2.om_breaks')}</div>}
    </section>
  );
}
