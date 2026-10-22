import { useEffect, useState } from 'react';
import { govapi, spfCsv } from '../../lib/api_gov';
import { papi, type RunStatus } from '../../lib/api_pay';
import { useI18n } from '../../i18n';
import { Button, Empty, ErrorNote, Loading, useAsync } from '../../components/ui';
import { EntitySelect, useEntity } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { OMR, RunBadge, monthName } from '../../components/pay';
import { downloadCsv } from '../../lib/csv';
import { canPrint } from '../../lib/native';

export default function SpfReportPage() {
  const { t, L, lang } = useI18n();
  const [entity, setEntity] = useEntity();
  const runs = useAsync(() => (entity ? papi.listRuns(entity, null) : Promise.resolve([])), [entity]);
  const [run, setRun] = useState('');
  useEffect(() => {
    const list = runs.data ?? [];
    if (!list.some((r) => r.id === run)) setRun((list.find((r) => r.status === 'APPROVED' || r.status === 'PAID') ?? list[0])?.id ?? '');
  }, [runs.data, run]);
  const { data: r, error, loading, reload } = useAsync(() => (run ? govapi.spfReport(run) : Promise.resolve(null)), [run]);
  const codes = r ? [...r.codes].sort((a, b) => a.code.localeCompare(b.code)) : [];
  const ee = r ? r.rows.reduce((s, x) => s + x.employee_total, 0) : 0;
  const er = r ? r.rows.reduce((s, x) => s + x.employer_total, 0) : 0;
  const exportCsv = () => { if (!r) return; const c = spfCsv(r); downloadCsv(`spf-${r.entity.code}-${r.run.month}.csv`, c.headers, c.rows); };
  const table = (rows: NonNullable<typeof r>['rows'], title: string) => {
    if (!rows.length) return null;
    const used = codes.filter((c) => rows.some((x) => (x.lines[c.code] ?? 0) !== 0));
    return (
    <section className="panel">
      <div className="panel-head"><h2>{title} <span className="muted num">{rows.length}</span></h2></div>
      <div className="table-wrap"><table className="t">
        <thead><tr><th>{t('c.employee')}</th><th className="r">{t('sp.wage')}</th>
          {used.map((c) => <th key={c.code} className="r" title={L(c.name_en, c.name_ar)}>{L(c.name_en, c.name_ar).replace(/^Social protection – |^الحماية الاجتماعية – /, '')}</th>)}
          <th className="r">{t('sp.ee')}</th><th className="r">{t('sp.er')}</th></tr></thead>
        <tbody>{rows.map((x) => (
          <tr key={x.employee_id}>
            <td style={{ minWidth: '12rem' }}>{L(x.full_name_en, x.full_name_ar)}<span className="sub num">{x.employee_no}{x.civil_number ? ` · ${x.civil_number}` : ''} · {x.nationality}</span></td>
            <td className="r num">{x.wage != null ? OMR(x.wage) : '—'}</td>
            {used.map((c) => <td key={c.code} className="r num">{x.lines[c.code] != null ? OMR(x.lines[c.code]) : ''}</td>)}
            <td className="r num">{OMR(x.employee_total)}</td><td className="r num">{OMR(x.employer_total)}</td>
          </tr>))}
        </tbody>
      </table></div>
    </section>);
  };
  return (
    <div className="stack">
      <PageHead title={t('sp.title')} sub={t('sp.hint')} actions={<><Button kind="primary" disabled={!r || !r.rows.length} onClick={exportCsv}>{t('sp.export')}</Button>
        {canPrint() && <Button onClick={() => window.print()}>{t('c.print')}</Button>}</>} />
      <div className="panel panel-pad row no-print">
        <EntitySelect value={entity} onChange={setEntity} />
        <div className="field" style={{ minWidth: 220 }}><label htmlFor="sp-run">{t('sp.run')}</label>
          <select id="sp-run" className="select" value={run} onChange={(e) => setRun(e.target.value)}>
            {(runs.data ?? []).map((x) => <option key={x.id} value={x.id}>{monthName(x.month, lang)} {x.month.slice(0, 4)}</option>)}
          </select></div>
      </div>
      <ErrorNote error={error ?? runs.error} onRetry={reload} />
      {runs.data && !runs.data.length ? <div className="panel"><Empty>{t('sp.no_runs')}</Empty></div> : loading && !r ? <Loading /> : r && (
        <>
          <section className="panel panel-pad stack">
            <div className="report-head">
              <b>{L(r.entity.name_en, r.entity.name_ar)}</b>
              <span>{t('ml.cr')}: <b className="num">{r.entity.cr_number ?? '—'}</b></span>
              <span>{t('sp.employer_no')}: <b className="num">{r.entity.spf_employer_no ?? '—'}</b></span>
              <span>{monthName(r.run.month, lang)} {r.run.month.slice(0, 4)} <RunBadge status={r.run.status as RunStatus} /></span>
            </div>
            {!r.run.final && <div className="note note-warn">{t('sp.not_final')}</div>}
            <div className="tile-row">
              <div className="tile kpi"><span>{t('sp.ee')}</span><b className="num">{OMR(ee)}</b></div>
              <div className="tile kpi"><span>{t('sp.er')}</span><b className="num">{OMR(er)}</b></div>
              <div className="tile kpi"><span>{t('sp.total_due')}</span><b className="num">{OMR(ee + er)}</b></div>
            </div>
          </section>
          {!r.rows.length ? <div className="panel"><Empty>{t('sp.none')}</Empty></div> : <>
            {table(r.rows.filter((x) => x.is_omani), t('sp.omanis'))}
            {table(r.rows.filter((x) => !x.is_omani), t('sp.expats'))}
          </>}
        </>)}
    </div>
  );
}
