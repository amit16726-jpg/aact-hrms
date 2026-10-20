import { useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useI18n } from '../i18n';
import { Badge, Empty, ErrorNote, Input, Loading, Pager, Tabs, useAsync } from '../components/ui';
import { PageHead } from '../components/Layout';
import { fmtDateTime } from '../lib/format';
import { diffRows, show } from '../lib/diff';

const TABLES = ['employees', 'employee_assignments', 'employee_contracts', 'employee_documents', 'compensation_revisions',
  'employee_bank_accounts', 'omanisation_targets', 'omanisation_exceptions', 'user_roles', 'user_profiles', 'job_titles',
  'departments', 'document_types', 'settings'];
const LIMIT = 100;

export default function AuditPage() {
  const { t, tk } = useI18n();
  const [tab, setTab] = useState<'changes' | 'access'>('changes');
  const [table, setTable] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [offset, setOffset] = useState(0);
  const changes = useAsync(() => api.listAudit({ table_name: table || null, from: from || null, to: to || null, limit: LIMIT, offset }), [table, from, to, offset]);
  const access = useAsync(() => (tab === 'access' ? api.listAccessLog({ limit: 300 }) : Promise.resolve([])), [tab]);

  return (
    <div className="stack">
      <PageHead title={t('au.title')} />
      <Tabs tabs={[{ id: 'changes', label: t('h.changes') }, { id: 'access', label: t('au.access') }]} value={tab} onChange={setTab} label={t('au.title')} />
      {tab === 'changes' ? (
        <>
          <div className="panel panel-pad row" style={{ gap: 16 }}>
            <div className="field" style={{ minWidth: 220 }}>
              <label htmlFor="au-t">{t('au.table')}</label>
              <select id="au-t" className="select" value={table} onChange={(e) => { setTable(e.target.value); setOffset(0); }}>
                <option value="">{t('c.all')}</option>
                {TABLES.map((x) => <option key={x} value={x}>{x}</option>)}
              </select>
            </div>
            <Input type="date" label={t('c.from')} value={from} onChange={(e) => { setFrom(e.target.value); setOffset(0); }} style={{ maxWidth: 180 }} />
            <Input type="date" label={t('c.to')} value={to} onChange={(e) => { setTo(e.target.value); setOffset(0); }} style={{ maxWidth: 180 }} />
          </div>
          <div className="panel">
            <ErrorNote error={changes.error} onRetry={changes.reload} />
            {changes.loading && !changes.data ? <Loading /> : !changes.data || changes.data.rows.length === 0 ? <Empty>{t('au.empty')}</Empty> : (
              <>
                <div className="table-wrap"><table className="t cards">
                  <thead><tr><th>{t('au.when')}</th><th>{t('au.user')}</th><th>{t('au.table')}</th><th>{t('au.action')}</th><th>{t('c.employee')}</th><th>{t('au.changes')}</th></tr></thead>
                  <tbody>{changes.data.rows.map((r) => {
                    const ch = diffRows(r.old_data, r.new_data);
                    return (
                      <tr key={r.id}>
                        <td data-label={t('au.when')} className="num nowrap">{fmtDateTime(r.at)}</td>
                        <td data-label={t('au.user')}>{r.user_name ?? '—'}</td>
                        <td data-label={t('au.table')}>{r.table_name}</td>
                        <td data-label={t('au.action')}><Badge>{tk(`au.${r.action}`, r.action)}</Badge></td>
                        <td data-label={t('c.employee')}>{r.employee_id ? <Link to={`/employees/${r.employee_id}?tab=history`}>{r.employee_no}</Link> : '—'}</td>
                        <td data-label={t('au.changes')} className="diff">
                          {r.action === 'UPDATE'
                            ? ch.slice(0, 8).map((c) => <div key={c.key}><span className="k">{c.key}: </span><del>{show(c.from)}</del> <ins>{show(c.to)}</ins></div>)
                            : <span className="muted">{show((r.new_data ?? r.old_data)?.code ?? (r.new_data ?? r.old_data)?.employee_no ?? r.row_key)}</span>}
                        </td>
                      </tr>);
                  })}</tbody></table></div>
                <Pager total={changes.data.total} limit={LIMIT} offset={offset} onChange={setOffset} />
              </>
            )}
          </div>
        </>
      ) : (
        <div className="panel">
          <ErrorNote error={access.error} onRetry={access.reload} />
          {access.loading && !access.data ? <Loading /> : !access.data || access.data.length === 0 ? <Empty>{t('au.empty')}</Empty> : (
            <div className="table-wrap"><table className="t cards">
              <thead><tr><th>{t('au.when')}</th><th>{t('au.user')}</th><th>{t('c.employee')}</th><th>{t('au.kind')}</th><th>{t('c.details')}</th></tr></thead>
              <tbody>{access.data.map((r) => (
                <tr key={r.id}>
                  <td data-label={t('au.when')} className="num nowrap">{fmtDateTime(r.at)}</td>
                  <td data-label={t('au.user')}>{r.user_name ?? '—'}</td>
                  <td data-label={t('c.employee')}>{r.employee_no ?? '—'}<span className="sub">{r.full_name_en}</span></td>
                  <td data-label={t('au.kind')}>{r.data_kind}</td>
                  <td data-label={t('c.details')}>{r.detail ?? '—'}</td>
                </tr>))}
              </tbody></table></div>
          )}
        </div>
      )}
    </div>
  );
}
