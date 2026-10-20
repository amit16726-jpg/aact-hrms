import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useI18n } from '../i18n';
import { Button, DateText, Empty, ErrorNote, Loading, StatusBadge, useAsync } from '../components/ui';
import { PageHead } from '../components/Layout';
import { downloadCsv } from '../lib/csv';

export default function MissingPage() {
  const { t, L } = useI18n();
  const [docType, setDocType] = useState('');
  const { data, error, loading, reload } = useAsync(() => api.listMissing({}), []);
  const types = useMemo(() => {
    const m = new Map<string, string>();
    for (const r of data ?? []) m.set(r.doc_type, L(r.name_en, r.name_ar));
    return [...m.entries()];
  }, [data, L]);
  const rows = (data ?? []).filter((r) => !docType || r.doc_type === docType);

  return (
    <div className="stack">
      <PageHead title={t('cp.missing_title')} sub={t('cp.missing_hint')} actions={
        <Button disabled={!rows.length} onClick={() => downloadCsv(`missing-documents-${new Date().toISOString().slice(0, 10)}.csv`,
          [t('emp.no'), t('emp.name'), t('c.department'), t('doc.type')],
          rows.map((r) => [r.employee_no, L(r.full_name_en, r.full_name_ar), L(r.department_en, r.department_ar), L(r.name_en, r.name_ar)]))}>
          {t('c.export')}</Button>} />
      {types.length > 1 && (
        <div className="panel panel-pad">
          <div className="field" style={{ maxWidth: 280 }}>
            <label htmlFor="ms-type">{t('doc.type')}</label>
            <select id="ms-type" className="select" value={docType} onChange={(e) => setDocType(e.target.value)}>
              <option value="">{t('c.all')}</option>
              {types.map(([code, name]) => <option key={code} value={code}>{name}</option>)}
            </select>
          </div>
        </div>
      )}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : rows.length === 0 ? <Empty>{t('cp.no_missing')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('c.department')}</th><th>{t('doc.type')}</th><th>{t('emp.joined')}</th><th>{t('c.status')}</th></tr></thead>
            <tbody>{rows.map((r) => (
              <tr key={`${r.employee_id}-${r.doc_type}`}>
                <td data-label={t('c.employee')}><Link to={`/employees/${r.employee_id}?tab=documents`}>{L(r.full_name_en, r.full_name_ar)}</Link>
                  <span className="sub num">{r.employee_no}</span></td>
                <td data-label={t('c.department')}>{L(r.department_en, r.department_ar) || '—'}</td>
                <td data-label={t('doc.type')}>{L(r.name_en, r.name_ar)}</td>
                <td data-label={t('emp.joined')}><DateText v={r.join_date} /></td>
                <td data-label={t('c.status')}><StatusBadge status={r.status} /></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
    </div>
  );
}
