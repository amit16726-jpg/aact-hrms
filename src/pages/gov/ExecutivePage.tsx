import { govapi, absencePct, turnoverPct } from '../../lib/api_gov';
import { useI18n } from '../../i18n';
import { ErrorNote, Loading, useAsync } from '../../components/ui';
import { EntitySelect, useEntity } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { BreakdownBars, MonthChart } from '../../components/gov';
import { OMR } from '../../components/pay';
import { fmtMoney } from '../../lib/format';

const pct = (v: number | null | undefined) => (v == null ? '—' : `${v}%`);
import { fmtDate } from '../../lib/format';

export default function ExecutivePage() {
  const { t, L } = useI18n();
  const [entity, setEntity] = useEntity();
  const { data: d, error, loading, reload } = useAsync(() => (entity ? govapi.execDashboard(entity) : Promise.resolve(null)), [entity]);
  const last = d?.months[d.months.length - 1];
  const prev = d && d.months.length > 1 ? d.months[d.months.length - 2] : null;
  return (
    <div className="stack">
      <PageHead title={t('xd.title')} sub={<>{t('xd.hint')}{d && <> · <span className="num">{fmtDate(d.as_of)}</span></>}</>}
        actions={<EntitySelect value={entity} onChange={setEntity} />} />
      <ErrorNote error={error} onRetry={reload} />
      {loading && !d ? <Loading /> : d && last && (
        <>
          <div className="tile-row">
            <div className="tile kpi"><span>{t('xd.headcount')}</span><b className="num">{d.snapshot.headcount}</b>
              <span className="sub">{t('xd.probation')} {d.snapshot.probation} · {t('xd.notice')} {d.snapshot.notice}</span></div>
            <div className="tile kpi"><span>{t('xd.omani')}</span><b className="num">{pct(last.omani_pct)}</b>
              <span className="sub num">{d.snapshot.omani} / {d.snapshot.headcount}</span></div>
            <div className="tile kpi"><span>{t('xd.turnover')}</span><b className="num">{pct(turnoverPct(d.months))}</b>
              <span className="sub">{t('xd.leavers')} {d.months.reduce((s, m) => s + m.leavers, 0)} · {t('xd.joiners')} {d.months.reduce((s, m) => s + m.joiners, 0)}</span></div>
            <div className="tile kpi"><span>{t('xd.absence')}</span><b className="num">{pct(prev ? absencePct(prev) : null)}</b></div>
            <div className="tile kpi"><span>{t('xd.tenure')}</span><b className="num">{t('xd.years', { n: d.snapshot.avg_tenure_years ?? '—' })}</b>
              <span className="sub">{t('xd.age')} {d.snapshot.avg_age ?? '—'} · {t('xd.female')} {d.snapshot.female}</span></div>
            {d.show_pay && d.risks.gratuity_liability != null && <div className="tile kpi"><span>{t('xd.gratuity')}</span><b className="num">{fmtMoney(d.risks.gratuity_liability, 0)}</b></div>}
          </div>
          <div className="grid-2" style={{ alignItems: 'start' }}>
            <section className="panel panel-pad stack">
              <h2 style={{ margin: 0 }}>{t('xd.headcount')}</h2>
              <MonthChart label={t('xd.headcount')} data={d.months.map((m) => ({ month: m.month, value: m.headcount }))} />
            </section>
            <section className="panel panel-pad stack">
              <h2 style={{ margin: 0 }}>{t('xd.trend_om')}</h2>
              <MonthChart label={t('xd.trend_om')} kind="line" unit="%" max={100} data={d.months.map((m) => ({ month: m.month, value: m.omani_pct }))} />
            </section>
            {d.show_pay && <section className="panel panel-pad stack">
              <h2 style={{ margin: 0 }}>{t('xd.trend_cost')}</h2>
              <MonthChart label={t('xd.trend_cost')} data={d.months.map((m) => ({ month: m.month, value: m.payroll_cost }))} />
            </section>}
            <section className="panel panel-pad stack">
              <h2 style={{ margin: 0 }}>{t('xd.trend_ot')}</h2>
              <MonthChart label={t('xd.trend_ot')} data={d.months.map((m) => ({ month: m.month, value: m.overtime_hours }))} />
            </section>
          </div>
          <section className="panel">
            <div className="panel-head"><h2>{t('xd.trend_head')}</h2></div>
            <div className="table-wrap"><table className="t">
              <thead><tr><th /><th className="r">{t('xd.headcount')}</th><th className="r">{t('xd.joiners')}</th><th className="r">{t('xd.leavers')}</th>
                <th className="r">{t('xd.omani')}</th><th className="r">{t('xd.absence_col')}</th>{d.show_pay && <th className="r">{t('xd.trend_cost')}</th>}</tr></thead>
              <tbody>{d.months.map((m) => (
                <tr key={m.month}><td className="num">{m.month}</td><td className="r num">{m.headcount}</td><td className="r num">{m.joiners}</td><td className="r num">{m.leavers}</td>
                  <td className="r num">{pct(m.omani_pct)}</td><td className="r num">{pct(absencePct(m))}</td>
                  {d.show_pay && <td className="r num">{m.payroll_cost != null ? OMR(m.payroll_cost) : '—'}</td>}</tr>))}
              </tbody></table></div>
          </section>
          <div className="grid-3" style={{ alignItems: 'start' }}>
            <section className="panel panel-pad stack">
              <h2 style={{ margin: 0 }}>{t('xd.by_dept')}</h2>
              <BreakdownBars label={t('xd.by_dept')} rows={d.by_department.map((x) => ({ name: L(x.name_en, x.name_ar), value: x.total, sub: `${t('ml.omani')} ${x.omani}` }))} />
            </section>
            <section className="panel panel-pad stack">
              <h2 style={{ margin: 0 }}>{t('xd.by_nat')}</h2>
              <BreakdownBars label={t('xd.by_nat')} rows={d.by_nationality.slice(0, 8).map((x) => ({ name: L(x.name_en ?? x.code, x.name_ar), value: x.total }))} />
            </section>
            <section className="panel panel-pad stack">
              <h2 style={{ margin: 0 }}>{t('xd.risks')}</h2>
              <dl className="kv">
                <div><dt>{t('xd.docs_expired')}</dt><dd className={`num${d.risks.documents_expired ? ' bad-text' : ''}`}>{d.risks.documents_expired}</dd></div>
                <div><dt>{t('xd.docs_30')}</dt><dd className="num">{d.risks.documents_30}</dd></div>
                <div><dt>{t('xd.open_pos')}</dt><dd className="num">{d.risks.open_positions}</dd></div>
                <div><dt>{t('xd.injuries')}</dt><dd className="num">{d.risks.injuries_ytd}</dd></div>
                <div><dt>{t('xd.lost_days')}</dt><dd className="num">{d.risks.lost_days_ytd}</dd></div>
                <div><dt>{t('xd.cases')}</dt><dd className="num">{d.risks.open_cases}</dd></div>
                <div><dt>{t('xd.exits')}</dt><dd className="num">{d.risks.exits_open}</dd></div>
              </dl>
            </section>
          </div>
        </>)}
    </div>
  );
}
