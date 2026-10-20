import { useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type OmanRow } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Badge, Empty, ErrorNote, Input, Loading, useAsync } from '../components/ui';
import { PageHead } from '../components/Layout';
import { fmtPct, todayMuscat } from '../lib/format';
import { project, type Scenario } from '../lib/omanisation';

function RatioCell({ r }: { r: OmanRow }) {
  const pct = r.pct ?? 0;
  return (
    <div className="bar" title={fmtPct(r.pct)}>
      <i style={{ width: `${Math.min(100, pct)}%` }} />
      {r.target_pct !== null && <em style={{ insetInlineStart: `calc(${Math.min(100, Number(r.target_pct))}% - 1px)` }} />}
    </div>
  );
}

function TargetBadge({ r }: { r: OmanRow }) {
  const { t } = useI18n();
  if (r.target_pct === null) return <span className="muted">{t('om.no_target')}</span>;
  return r.meets_target ? <Badge tone="ok">{t('om.meets')}</Badge> : <Badge tone="bad">{t('om.below')}</Badge>;
}

function RatioTable({ title, rows }: { title: string; rows: (OmanRow & { key: string; label: string; extra?: string })[] }) {
  const { t } = useI18n();
  return (
    <section className="panel">
      <div className="panel-head"><h2>{title}</h2></div>
      {rows.length === 0 ? <Empty>—</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{title}</th><th className="r">{t('om.headcount')}</th><th className="r">{t('dash.omani')}</th><th className="r">{t('om.ratio')}</th>
            <th style={{ minWidth: 140 }} /><th className="r">{t('om.target')}</th><th className="r">{t('om.gap')}</th><th /></tr></thead>
          <tbody>{rows.map((r) => (
            <tr key={r.key}>
              <td data-label={title}>{r.label}{r.extra && <span className="sub">{r.extra}</span>}</td>
              <td data-label={t('om.headcount')} className="r num">{r.total}</td>
              <td data-label={t('dash.omani')} className="r num">{r.omani}</td>
              <td data-label={t('om.ratio')} className="r num">{fmtPct(r.pct)}</td>
              <td><RatioCell r={r} /></td>
              <td data-label={t('om.target')} className="r num">{r.target_pct === null ? '—' : fmtPct(r.target_pct)}</td>
              <td data-label={t('om.gap')} className="r num">{r.omanis_needed ?? '—'}</td>
              <td><TargetBadge r={r} /></td>
            </tr>))}
          </tbody></table></div>
      )}
    </section>
  );
}

export default function OmanisationPage() {
  const { t, L } = useI18n();
  const { me } = useSession();
  const [entityId, setEntityId] = useState(me?.entities[0]?.id ?? '');
  const [asOf, setAsOf] = useState(todayMuscat());
  const [sc, setSc] = useState<Scenario>({ hireOmani: 0, hireExpat: 0, leaveOmani: 0, leaveExpat: 0, replaceExpat: 0 });
  const { data, error, loading, reload } = useAsync(
    () => (entityId ? api.getOmanisation(entityId, asOf || null) : Promise.resolve(null)), [entityId, asOf]);

  if (!me?.entities.length) return <Empty>{t('org.choose_company')}</Empty>;
  const o = data?.overall;
  const proj = o ? project({ total: o.total, omani: o.omani }, sc, o.target_pct) : null;
  const num = (k: keyof Scenario) => (
    <Input type="number" min={0} label={t(({ hireOmani: 'om.hire_omani', hireExpat: 'om.hire_expat', leaveOmani: 'om.leave_omani',
      leaveExpat: 'om.leave_expat', replaceExpat: 'om.replace_expat' } as const)[k])}
      value={String(sc[k])} onChange={(e) => setSc({ ...sc, [k]: Math.max(0, Number(e.target.value) || 0) })} />
  );

  return (
    <div className="stack">
      <PageHead title={t('om.title')} actions={<Link className="btn" to="/compliance/targets">{t('nav.targets')}</Link>} />
      <div className="panel panel-pad row" style={{ gap: 16 }}>
        {me.entities.length > 1 && (
          <div className="field" style={{ minWidth: 220 }}>
            <label htmlFor="om-ent">{t('c.company')}</label>
            <select id="om-ent" className="select" value={entityId} onChange={(e) => setEntityId(e.target.value)}>
              {me.entities.map((en) => <option key={en.id} value={en.id}>{L(en.name_en, en.name_ar)}</option>)}
            </select>
          </div>
        )}
        <Input type="date" label={t('om.as_of')} value={asOf} onChange={(e) => setAsOf(e.target.value)} style={{ maxWidth: 200 }} />
      </div>

      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : data && o ? (
        <>
          <div className="figures">
            <div className="figure"><b className="num">{fmtPct(o.pct)}</b><span>{t('om.overall')}</span></div>
            <div className="figure"><b className="num">{o.target_pct === null ? '—' : fmtPct(o.target_pct)}</b><span>{t('om.target')}</span></div>
            <div className="figure"><b className="num">{o.omani} / {o.total}</b><span>{t('dash.omani')} / {t('om.headcount')}</span></div>
            <div className="figure"><b className="num">{o.omanis_needed ?? '—'}</b><span>{t('om.gap')}</span></div>
          </div>
          {o.target_source && <p className="muted" style={{ margin: 0 }}>{t('tg.source')}: {o.target_source}</p>}

          <div className="grid-side">
            <RatioTable title={t('om.by_department')} rows={data.by_department.map((r) => ({ ...r, key: r.id, label: L(r.name_en, r.name_ar) }))} />
            <section className="panel">
              <div className="panel-head"><h2>{t('om.scenario')}</h2></div>
              <div className="panel-body stack">
                <p className="muted" style={{ margin: 0 }}>{t('om.scenario_hint')}</p>
                <div className="form-grid">{num('hireOmani')}{num('hireExpat')}{num('leaveOmani')}{num('leaveExpat')}<div className="span-2">{num('replaceExpat')}</div></div>
                {proj && (
                  <dl className="facts">
                    <dt>{t('om.projected')}</dt><dd className="num"><b>{fmtPct(proj.pct)}</b></dd>
                    <dt>{t('om.projected_total')}</dt><dd className="num">{proj.omani} / {proj.total}</dd>
                    <dt>{t('om.still_needed')}</dt><dd className="num">{proj.needed ?? '—'}</dd>
                  </dl>
                )}
              </div>
            </section>
          </div>

          <RatioTable title={t('om.by_job')} rows={data.by_job_title.map((r) => ({ ...r, key: r.id, label: L(r.name_en, r.name_ar),
            extra: [r.profession_code, r.omani_only ? t('org.f_omani_only') : null].filter(Boolean).join(' | ') }))} />
          {data.by_profession.length > 0 && (
            <RatioTable title={t('om.by_profession')} rows={data.by_profession.map((r) => ({ ...r, key: r.profession_code, label: r.profession_code }))} />
          )}

          <section className="panel">
            <div className="panel-head"><h2>{t('om.placements')}</h2></div>
            {data.omani_only_placements.length === 0 ? <Empty>{t('om.no_placements')}</Empty> : (
              <div className="table-wrap"><table className="t cards">
                <thead><tr><th>{t('c.employee')}</th><th>{t('emp.job')}</th><th>{t('ed.exceptions')}</th></tr></thead>
                <tbody>{data.omani_only_placements.map((p) => (
                  <tr key={p.employee_id}>
                    <td data-label={t('c.employee')}><Link to={`/employees/${p.employee_id}`}>{L(p.full_name_en, p.full_name_ar)}</Link><span className="sub num">{p.employee_no}</span></td>
                    <td data-label={t('emp.job')}>{L(p.job_title_en, p.job_title_ar)}</td>
                    <td data-label={t('ed.exceptions')}>{p.exception_id && p.exception_status === 'ACTIVE'
                      ? <span>{p.exception_reason}</span> : <Badge tone="bad">{t('om.no_exception')}</Badge>}</td>
                  </tr>))}
                </tbody></table></div>
            )}
          </section>

          <div className="note"><b>{t('om.basis')}.</b> {t('om.basis_text')}</div>
        </>
      ) : null}
    </div>
  );
}
