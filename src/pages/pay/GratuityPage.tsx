import { useState } from 'react';
import { papi } from '../../lib/api_pay';
import { useI18n } from '../../i18n';
import { Button, Empty, ErrorNote, Loading, useAsync } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { EntitySelect, useEntity } from '../../components/time';
import { EmpLink, OMR } from '../../components/pay';
import { fmtDate, todayMuscat } from '../../lib/format';
import { downloadCsv } from '../../lib/csv';

export default function GratuityPage() {
  const { t } = useI18n();
  const [entity, setEntity] = useEntity();
  const [asOf, setAsOf] = useState(todayMuscat());
  const { data, error, loading, reload } = useAsync(() => papi.gratuityReport(entity || null, asOf), [entity, asOf]);
  const rows = data?.rows ?? [];
  const total = rows.reduce((s, r) => s + Number(r.total ?? 0), 0);
  const exportCsv = () => downloadCsv(`gratuity-${asOf}.csv`,
    ['Employee no', 'Name', 'Joined', 'Basic', 'Years to 31/07/2023', 'Amount (old rule)', 'Years from 01/08/2023', 'Amount (new rule)', 'Total'],
    rows.map((r) => [r.employee_no, r.full_name_en, r.join_date, r.basic ?? '', r.old_years, r.old_amount, r.new_years, r.new_amount, r.total]));
  return (
    <div className="stack">
      <PageHead title={t('gr.title')} sub={t('gr.hint')} actions={<Button onClick={exportCsv} disabled={!rows.length}>{t('c.export')}</Button>} />
      <div className="panel panel-pad row" style={{ alignItems: 'flex-end', gap: 16 }}>
        <EntitySelect value={entity} onChange={setEntity} />
        <div className="field"><label htmlFor="gr-asof">{t('gr.as_of')}</label>
          <input id="gr-asof" type="date" className="input ltr" value={asOf} onChange={(e) => e.target.value && setAsOf(e.target.value)} /></div>
        <span className="spacer" />
        <div className="tile" style={{ minWidth: 200 }}><span>{t('gr.total')}</span><b>OMR {OMR(total)}</b></div>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !rows.length ? <Empty>{t('gr.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('gr.join')}</th><th className="r">{t('gr.basic')}</th><th className="r">{t('gr.old')}</th>
              <th className="r">{t('gr.new')}</th><th className="r">{t('gr.amount')}</th></tr></thead>
            <tbody>{rows.map((r) => (
              <tr key={r.employee_id}>
                <td data-label={t('c.employee')}><EmpLink id={r.employee_id} no={r.employee_no} en={r.full_name_en} ar={r.full_name_ar} /></td>
                <td data-label={t('gr.join')} className="num">{fmtDate(r.join_date)}</td>
                <td data-label={t('gr.basic')} className="r num">{OMR(r.basic)}</td>
                <td data-label={t('gr.old')} className="r num">{OMR(r.old_amount)}<span className="sub">{t('st.years', { n: r.old_years })}</span></td>
                <td data-label={t('gr.new')} className="r num">{OMR(r.new_amount)}<span className="sub">{t('st.years', { n: r.new_years })}</span></td>
                <td data-label={t('gr.amount')} className="r num"><b>{r.below_minimum ? '—' : OMR(r.total)}</b>{r.below_minimum && <span className="sub">{t('st.below_min')}</span>}</td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
    </div>
  );
}
