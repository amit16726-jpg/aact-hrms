import { useState } from 'react';
import { Link } from 'react-router-dom';
import { govapi } from '../../lib/api_gov';
import { useI18n } from '../../i18n';
import { Badge, Button, Empty, ErrorNote, Input, Loading, useAsync } from '../../components/ui';
import { EntitySelect, useEntity } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { OMR } from '../../components/pay';
import { downloadCsv } from '../../lib/csv';
import { fmtDate, todayMuscat } from '../../lib/format';

export default function MolReportPage() {
  const { t, L, tk } = useI18n();
  const [entity, setEntity] = useEntity();
  const [asOf, setAsOf] = useState(todayMuscat());
  const { data: r, error, loading, reload } = useAsync(() => (entity ? govapi.molReport(entity, asOf || null) : Promise.resolve(null)), [entity, asOf]);
  const exportEmp = () => r && downloadCsv(`mol-localisation-${r.entity.code}-${r.as_of}.csv`,
    ['Employee no', 'Name (English)', 'Name (Arabic)', 'Nationality', 'Gender', 'Date of birth', 'Civil no', 'Passport no', 'Resident card no', 'Job', 'Profession code',
      'Omani-only job', 'Department', 'Joined', 'Contract type', 'Contract end', 'MoL contract no', ...(r.show_salary ? ['Basic salary'] : [])],
    r.employees.map((e) => [e.employee_no, e.full_name_en, e.full_name_ar, e.nationality, e.gender, e.date_of_birth, e.civil_number, e.passport_no, e.resident_card_no,
      e.job_en, e.profession_code, e.omani_only ? 'Y' : 'N', e.department_en, e.join_date, e.contract_type, e.contract_end, e.mol_registration_no, ...(r.show_salary ? [e.basic] : [])]));
  const exportProf = () => r && downloadCsv(`mol-professions-${r.entity.code}-${r.as_of}.csv`, ['Profession code', 'Job', 'Omani-only', 'Total', 'Omani', 'Expatriate', 'Omani %'],
    r.by_profession.map((p) => [p.profession_code, p.job_en, p.omani_only ? 'Y' : 'N', p.total, p.omani, p.expat, p.pct]));
  const violations = r ? r.by_profession.reduce((s, p) => s + p.expat_in_omani_only, 0) : 0;
  return (
    <div className="stack">
      <PageHead title={t('ml.title')} sub={t('ml.hint')} actions={<><Button onClick={exportProf} disabled={!r}>{t('ml.export_prof')}</Button>
        <Button kind="primary" onClick={exportEmp} disabled={!r}>{t('ml.export')}</Button><Button onClick={() => window.print()}>{t('c.print')}</Button></>} />
      <div className="panel panel-pad row no-print">
        <EntitySelect value={entity} onChange={setEntity} />
        <Input label={t('ml.as_of')} type="date" ltr value={asOf} max={todayMuscat()} onChange={(e) => setAsOf(e.target.value)} />
      </div>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !r ? <Loading /> : r && (
        <>
          <section className="panel panel-pad stack">
            <h2 style={{ margin: 0 }}>{L(r.entity.name_en, r.entity.name_ar)}</h2>
            <div className="report-head">
              <span>{t('ml.cr')}: <b className="num">{r.entity.cr_number ?? '—'}</b></span>
              <span>{t('ml.est_no')}: <b className="num">{r.entity.mol_establishment_no ?? '—'}</b></span>
              <span>{t('ml.as_of')}: <b className="num">{fmtDate(r.as_of)}</b></span>
            </div>
            <div className="tile-row">
              <div className="tile kpi"><span>{t('ml.total')}</span><b className="num">{r.overall.total}</b></div>
              <div className="tile kpi"><span>{t('ml.omani')}</span><b className="num">{r.overall.omani}</b></div>
              <div className="tile kpi"><span>{t('ml.pct')}</span><b className="num">{r.overall.pct ?? '—'}%</b>
                {r.overall.target_pct != null && <span className="sub"><Badge tone={r.overall.meets_target ? 'ok' : 'bad'}>{t('ml.target', { p: r.overall.target_pct })}</Badge></span>}</div>
            </div>
            {violations > 0 && <div className="note note-bad">{t('ml.violation', { n: violations })} · <Link to="/compliance/omanisation">{t('nav.omanisation')}</Link></div>}
          </section>
          <section className="panel">
            <div className="panel-head"><h2>{t('ml.professions')}</h2></div>
            <div className="table-wrap"><table className="t cards">
              <thead><tr><th>{t('ml.profession')}</th><th>{t('rq2.job')}</th><th className="r">{t('ml.total')}</th><th className="r">{t('ml.omani')}</th><th className="r">{t('ml.expat')}</th><th className="r">{t('ml.pct')}</th></tr></thead>
              <tbody>{r.by_profession.map((p, i) => (
                <tr key={`${p.profession_code}-${i}`}>
                  <td data-label={t('ml.profession')} className="num">{p.profession_code ?? '—'}</td>
                  <td data-label={t('rq2.job')}>{L(p.job_en, p.job_ar)}{p.omani_only && <> <Badge tone="info">{t('ml.omani_only')}</Badge></>}
                    {p.expat_in_omani_only > 0 && <span className="sub bad-text">{t('ml.violation', { n: p.expat_in_omani_only })}</span>}</td>
                  <td data-label={t('ml.total')} className="r num">{p.total}</td><td data-label={t('ml.omani')} className="r num">{p.omani}</td>
                  <td data-label={t('ml.expat')} className="r num">{p.expat}</td><td data-label={t('ml.pct')} className="r num">{p.pct ?? '—'}%</td>
                </tr>))}
              </tbody></table></div>
          </section>
          <section className="panel">
            <div className="panel-head"><h2>{t('ml.employees')} <span className="muted num">{r.employees.length}</span></h2></div>
            {!r.employees.length ? <Empty>—</Empty> : <div className="table-wrap"><table className="t cards">
              <thead><tr><th>{t('c.employee')}</th><th>{t('ml.nat')}</th><th>{t('rq2.job')}</th><th>{t('pb.joined')}</th><th>{t('co.type')}</th>{r.show_salary && <th className="r">{t('ml.basic')}</th>}</tr></thead>
              <tbody>{r.employees.map((e) => (
                <tr key={e.employee_id}>
                  <td data-label={t('c.employee')}><Link to={`/employees/${e.employee_id}`}>{L(e.full_name_en, e.full_name_ar)}</Link>
                    <span className="sub num">{e.employee_no}{e.civil_number ? ` · ${e.civil_number}` : ''}{e.passport_no ? ` · ${e.passport_no}` : ''}</span></td>
                  <td data-label={t('ml.nat')}>{e.nationality === 'OM' ? <Badge tone="ok">OM</Badge> : <span className="num">{e.nationality}</span>}</td>
                  <td data-label={t('rq2.job')}>{L(e.job_en, e.job_ar)}<span className="sub num">{e.profession_code ?? ''}{e.department_en ? ` · ${L(e.department_en, e.department_ar)}` : ''}</span></td>
                  <td data-label={t('pb.joined')} className="num">{fmtDate(e.join_date)}<span className="sub">{tk(`st.${e.status}`, e.status)}</span></td>
                  <td data-label={t('co.type')}>{e.contract_type ? tk(`co.${e.contract_type}`, e.contract_type) : '—'}{e.contract_end && <span className="sub num">{fmtDate(e.contract_end)}</span>}</td>
                  {r.show_salary && <td data-label={t('ml.basic')} className="r num">{e.basic != null ? OMR(e.basic) : '—'}</td>}
                </tr>))}
              </tbody></table></div>}
          </section>
        </>)}
    </div>
  );
}
