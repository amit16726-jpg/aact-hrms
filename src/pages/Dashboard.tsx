import { Link } from 'react-router-dom';
import { api, type ExpiryRow } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { DateText, DaysLeft, Empty, ErrorNote, Loading, useAsync } from '../components/ui';
import { PageHead } from '../components/Layout';
import { Runway } from '../components/Runway';
import { TimePanels } from '../components/TimePanels';
import { fmtPct } from '../lib/format';
import { ChevronRight } from 'lucide-react';

function ExpiryTable({ rows, showEmployee = true }: { rows: ExpiryRow[]; showEmployee?: boolean }) {
  const { t, L } = useI18n();
  return (
    <div className="table-wrap">
      <table className="t cards">
        <thead><tr>
          {showEmployee && <th>{t('c.employee')}</th>}
          <th>{t('doc.type')}</th><th>{t('cp.expiry')}</th><th>{t('cp.days_left')}</th>
        </tr></thead>
        <tbody>
          {rows.map((r) => (
            <tr key={`${r.source}-${r.ref_id}`}>
              {showEmployee && <td data-label={t('c.employee')}>
                <Link to={`/employees/${r.employee_id}?tab=documents`}>{L(r.full_name_en, r.full_name_ar)}</Link>
                <span className="sub num">{r.employee_no}</span></td>}
              <td data-label={t('doc.type')}>{L(r.name_en, r.name_ar)}</td>
              <td data-label={t('cp.expiry')}><DateText v={r.expiry_date} /></td>
              <td data-label={t('cp.days_left')}><DaysLeft days={r.days_left} /></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function DashboardPage() {
  const { t, L, lang } = useI18n();
  const { me } = useSession();
  const { data: d, error, loading, reload } = useAsync(() => api.dashboard(), []);

  if (loading && !d) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!d) return null;

  const w = d.workforce;
  const c = d.compliance;
  const ap = d.approvals;
  const apTotal = ap.salary + ap.bank + ap.targets;
  const name = me?.employee_name ? L(me.employee_name, me.employee_name_ar) : (me?.display_name ?? me?.email ?? '');

  return (
    <div className="stack">
      <PageHead title={t('dash.welcome', { name })}
        sub={new Intl.DateTimeFormat(lang === 'ar' ? 'ar-OM-u-nu-latn' : 'en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date())} />
      <TimePanels />

      {c && (
        <section className="stack" aria-labelledby="runway-h">
          <div className="row" style={{ alignItems: 'baseline' }}>
            <h2 id="runway-h">{t('dash.runway')}</h2>
            <span className="muted">{t('dash.runway_hint')}</span>
          </div>
          <Runway expired={c.expired} d30={c.d30} d60={c.d60} d90={c.d90} />
          {c.missing > 0 && (
            <Link to="/compliance/missing" className="note note-warn" style={{ textDecoration: 'none' }}>
              {t('dash.missing', { n: c.missing, m: c.employees_missing })}
            </Link>
          )}
        </section>
      )}

      {w && (
        <div className="figures" role="list">
          <div className="figure" role="listitem"><b className="num">{w.headcount}</b><span>{t('dash.headcount')}</span></div>
          <div className="figure" role="listitem"><b className="num">{w.omani}</b><span>{t('dash.omani')}</span></div>
          <div className="figure" role="listitem"><b className="num">{w.expat}</b><span>{t('dash.expat')}</span></div>
          <div className="figure" role="listitem"><b className="num">{w.probation}</b><span>{t('dash.probation')}</span></div>
          <div className="figure" role="listitem"><b className="num">{w.notice}</b><span>{t('dash.notice')}</span></div>
          <div className="figure" role="listitem"><b className="num">{w.joiners_30}</b><span>{t('dash.joiners')}</span></div>
          <div className="figure" role="listitem"><b className="num">{w.leavers_30}</b><span>{t('dash.leavers')}</span></div>
        </div>
      )}

      <div className="grid-side">
        <div className="stack">
          {d.expiring_soon && (
            <section className="panel">
              <div className="panel-head"><h2>{t('dash.expiring_soon')}</h2>
                <Link to="/compliance/expiries">{t('nav.expiries')}</Link></div>
              {d.expiring_soon.length ? <ExpiryTable rows={d.expiring_soon} /> : <Empty>{t('dash.nothing_expiring')}</Empty>}
            </section>
          )}

          {d.omanisation && d.omanisation.length > 0 && (
            <section className="panel">
              <div className="panel-head"><h2>{t('dash.omanisation')}</h2>
                <Link to="/compliance/omanisation">{t('nav.omanisation')}</Link></div>
              <div className="table-wrap">
                <table className="t">
                  <thead><tr><th>{t('c.company')}</th><th className="r">{t('om.headcount')}</th><th className="r">{t('om.ratio')}</th>
                    <th className="r">{t('om.target')}</th><th className="r">{t('om.gap')}</th></tr></thead>
                  <tbody>
                    {d.omanisation.map((o) => (
                      <tr key={o.entity_id}>
                        <td>{L(o.name_en, o.name_ar)}</td>
                        <td className="r num">{o.total}</td>
                        <td className="r num">{fmtPct(o.pct)}</td>
                        <td className="r num">{o.target_pct === null ? <span className="muted">{t('dash.no_target')}</span> : fmtPct(o.target_pct)}</td>
                        <td className="r num">{o.omanis_needed ?? '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          )}

          {d.by_department && d.by_department.length > 0 && (
            <section className="panel">
              <div className="panel-head"><h2>{t('dash.by_department')}</h2></div>
              <div className="table-wrap">
                <table className="t">
                  <thead><tr><th>{t('c.department')}</th><th className="r">{t('dash.headcount')}</th><th className="r">{t('dash.omani')}</th><th>{t('om.ratio')}</th></tr></thead>
                  <tbody>
                    {d.by_department.map((r) => {
                      const pct = r.total ? (100 * r.omani) / r.total : 0;
                      return (
                        <tr key={r.department_id}>
                          <td><Link to={`/employees?department_id=${r.department_id}`}>{L(r.name_en, r.name_ar)}</Link></td>
                          <td className="r num">{r.total}</td>
                          <td className="r num">{r.omani}</td>
                          <td style={{ minWidth: 140 }}><div className="bar" aria-label={fmtPct(pct)}><i style={{ width: `${pct}%` }} /></div></td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </section>
          )}

          {d.me && (
            <section className="panel">
              <div className="panel-head"><h2>{t('dash.my_job')}</h2><Link to="/my">{t('nav.my_record')}</Link></div>
              <div className="panel-body stack">
                {d.me.assignment && (
                  <dl className="facts">
                    <dt>{t('emp.job')}</dt><dd>{L(d.me.assignment.job_title_en, d.me.assignment.job_title_ar)}</dd>
                    <dt>{t('c.department')}</dt><dd>{L(d.me.assignment.department_en, d.me.assignment.department_ar)}</dd>
                    <dt>{t('emp.manager')}</dt><dd>{L(d.me.assignment.manager_name_en, d.me.assignment.manager_name_ar) || '—'}</dd>
                    <dt>{t('emp.joined')}</dt><dd><DateText v={d.me.join_date} /></dd>
                  </dl>
                )}
                <h3>{t('dash.my_documents')}</h3>
                {d.me.my_expiries.length ? <ExpiryTable rows={d.me.my_expiries} showEmployee={false} /> : <p className="muted">{t('dash.nothing_expiring')}</p>}
              </div>
            </section>
          )}

          {d.me && d.me.team_size > 0 && (
            <section className="panel">
              <div className="panel-head"><h2>{t('dash.team', { n: d.me.team_size })}</h2><Link to="/employees">{t('nav.employees')}</Link></div>
              <div className="panel-body">
                <h3 style={{ marginBottom: 8 }}>{t('dash.team_expiries')}</h3>
                {d.me.team_expiries.length ? <ExpiryTable rows={d.me.team_expiries} /> : <p className="muted">{t('dash.no_team_expiries')}</p>}
              </div>
            </section>
          )}
        </div>

        <div className="stack">
          {me?.permissions.some((p) => ['SALARY_APPROVE', 'BANK_APPROVE', 'RULES_APPROVE'].includes(p)) && (
            <section className="panel">
              <div className="panel-head"><h2>{t('dash.approvals')}</h2></div>
              {apTotal === 0 ? <div className="panel-body"><p className="muted" style={{ margin: 0 }}>{t('dash.approvals_none')}</p></div> : (
                <ul className="todo">
                  {([['salary', ap.salary, 'dash.salary_approvals'], ['bank', ap.bank, 'dash.bank_approvals'], ['targets', ap.targets, 'dash.target_approvals']] as const)
                    .filter(([, n]) => n > 0).map(([k, n, key]) => (
                      <li key={k}><Link to="/approvals"><span className="todo-n num">{n}</span><span className="todo-t">{t(key, { n }).replace(/^\s*\d+\s*/, '')}</span><ChevronRight size={16} aria-hidden="true" /></Link></li>
                    ))}
                </ul>
              )}
            </section>
          )}

          {d.probation_due && d.probation_due.length > 0 && (
            <section className="panel">
              <div className="panel-head"><h2>{t('dash.probation_due')}</h2></div>
              <ul className="panel-body" style={{ margin: 0, listStyle: 'none' }}>
                {d.probation_due.map((p) => (
                  <li key={p.id} className="row" style={{ padding: '4px 0' }}>
                    <Link to={`/employees/${p.id}`}>{L(p.full_name_en, p.full_name_ar)}</Link>
                    <span className="spacer" /><DateText v={p.probation_end_date} />
                  </li>
                ))}
              </ul>
            </section>
          )}

          {d.by_nationality && d.by_nationality.length > 0 && (
            <section className="panel">
              <div className="panel-head"><h2>{t('dash.by_nationality')}</h2></div>
              <ul className="panel-body" style={{ margin: 0, listStyle: 'none' }}>
                {d.by_nationality.map((n) => (
                  <li key={n.code} className="row" style={{ padding: '3px 0' }}>
                    <span>{L(n.name_en, n.name_ar)}</span><span className="spacer" /><span className="num">{n.total}</span>
                  </li>
                ))}
              </ul>
            </section>
          )}
        </div>
      </div>
    </div>
  );
}
