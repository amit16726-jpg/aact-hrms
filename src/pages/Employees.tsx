import { useEffect, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { api, type EmployeeRow } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, DateText, Empty, ErrorNote, Loading, Pager, SortHead, StatusBadge, useAction, useAsync } from '../components/ui';
import { MasterSelect } from '../components/pickers';
import { PageHead } from '../components/Layout';
import { downloadCsv } from '../lib/csv';
import { fmtDate } from '../lib/format';

const LIMIT = 50;

export default function EmployeesPage() {
  const { t, L, tk } = useI18n();
  const { me, can } = useSession();
  const nav = useNavigate();
  const [params, setParams] = useSearchParams();
  const [search, setSearch] = useState(params.get('search') ?? '');
  const [debounced, setDebounced] = useState(search);
  const entityId = params.get('entity_id') ?? (me?.entities.length === 1 ? me.entities[0].id : '');
  const status = params.get('status') ?? 'CURRENT';
  const departmentId = params.get('department_id') ?? '';
  const nationality = params.get('nationality') ?? '';
  const sort = params.get('sort') ?? 'employee_no';
  const dir = (params.get('dir') ?? 'asc') as 'asc' | 'desc';
  const offset = Number(params.get('offset') ?? 0) || 0;
  const { busy, run } = useAction();

  useEffect(() => { const id = window.setTimeout(() => setDebounced(search), 300); return () => window.clearTimeout(id); }, [search]);

  const set = (k: string, v: string | null) => {
    const p = new URLSearchParams(params);
    if (v) p.set(k, v); else p.delete(k);
    if (k !== 'offset') p.delete('offset');
    setParams(p, { replace: true });
  };
  useEffect(() => { if ((params.get('search') ?? '') !== debounced) set('search', debounced || null); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [debounced]);

  const query = {
    search: debounced || null, status, entity_id: entityId || null, department_id: departmentId || null,
    nationality: nationality || null, sort, dir, limit: LIMIT, offset,
  };
  const { data, error, loading, reload } = useAsync(() => api.listEmployees(query), [JSON.stringify(query)]);

  const onSort = (id: string) => {
    const p = new URLSearchParams(params);
    p.set('sort', id); p.set('dir', sort === id && dir === 'asc' ? 'desc' : 'asc'); p.delete('offset');
    setParams(p, { replace: true });
  };

  const exportCsv = () => run(async () => {
    const all: EmployeeRow[] = [];
    for (let off = 0; off < 5000; off += 500) {
      const r = await api.listEmployees({ ...query, limit: 500, offset: off });
      all.push(...r.rows);
      if (all.length >= r.total) break;
    }
    downloadCsv(`employees-${new Date().toISOString().slice(0, 10)}.csv`,
      [t('emp.no'), t('ef.full_name_en'), t('ef.full_name_ar'), t('emp.nationality'), t('c.department'), t('emp.job'),
        t('emp.location'), t('emp.manager'), t('emp.joined'), t('c.status'), t('ef.mobile'), t('ef.work_email')],
      all.map((r) => [r.employee_no, r.full_name_en, r.full_name_ar, L(r.nationality_en, r.nationality_ar), L(r.department_en, r.department_ar),
        L(r.job_title_en, r.job_title_ar), L(r.location_en, r.location_ar), L(r.manager_en, r.manager_ar), fmtDate(r.join_date),
        tk(`st.${r.status}`, r.status), r.mobile, r.work_email]));
  });

  const hasFilter = !!(debounced || departmentId || nationality || status !== 'CURRENT');

  return (
    <div className="stack">
      <PageHead title={t('emp.title')} actions={<>
        <Button onClick={() => void exportCsv()} busy={busy}>{t('c.export')}</Button>
        {can('EMP_WRITE') && <Link className="btn btn-primary" to="/employees/new">{t('emp.new')}</Link>}
      </>} />

      <div className="panel panel-pad">
        <div className="form-grid" style={{ gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))' }}>
          <div className="field">
            <label htmlFor="emp-search">{t('c.search')}</label>
            <input id="emp-search" className="input" type="search" value={search} placeholder={t('emp.search_ph')}
              onChange={(e) => setSearch(e.target.value)} />
          </div>
          {me && me.entities.length > 1 && (
            <div className="field">
              <label htmlFor="emp-ent">{t('c.company')}</label>
              <select id="emp-ent" className="select" value={entityId} onChange={(e) => set('entity_id', e.target.value || null)}>
                <option value="">{t('c.all')}</option>
                {me.entities.map((en) => <option key={en.id} value={en.id}>{L(en.name_en, en.name_ar)}</option>)}
              </select>
            </div>
          )}
          {entityId && (
            <MasterSelect kind="department" entityId={entityId} label={t('c.department')} value={departmentId}
              onChange={(v) => set('department_id', v)} activeOnly={false} />
          )}
          <div className="field">
            <label htmlFor="emp-nat">{t('emp.nationality')}</label>
            <select id="emp-nat" className="select" value={nationality} onChange={(e) => set('nationality', e.target.value || null)}>
              <option value="">{t('c.all')}</option>
              <option value="OMANI">{t('emp.omani_filter')}</option>
              <option value="EXPAT">{t('emp.expat_filter')}</option>
            </select>
          </div>
          <div className="field">
            <label htmlFor="emp-st">{t('c.status')}</label>
            <select id="emp-st" className="select" value={status} onChange={(e) => set('status', e.target.value)}>
              {['CURRENT', 'ALL', 'PROBATION', 'ACTIVE', 'NOTICE', 'SUSPENDED', 'SEPARATED'].map((s) => (
                <option key={s} value={s}>{tk(`st.${s}`, s)}</option>
              ))}
            </select>
          </div>
        </div>
      </div>

      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : data && data.rows.length === 0 ? (
          <Empty>{hasFilter ? t('emp.empty') : t('emp.empty_none')}</Empty>
        ) : data ? (
          <>
            <div className="table-wrap">
              <table className="t cards">
                <thead><tr>
                  <SortHead id="employee_no" label={t('emp.no')} sort={sort} dir={dir} onSort={onSort} />
                  <SortHead id="name" label={t('emp.name')} sort={sort} dir={dir} onSort={onSort} />
                  <SortHead id="department" label={t('c.department')} sort={sort} dir={dir} onSort={onSort} />
                  <th>{t('emp.nationality')}</th>
                  <SortHead id="join_date" label={t('emp.joined')} sort={sort} dir={dir} onSort={onSort} />
                  <SortHead id="status" label={t('c.status')} sort={sort} dir={dir} onSort={onSort} />
                </tr></thead>
                <tbody>
                  {data.rows.map((r) => (
                    <tr key={r.id} className="clickable" onClick={() => nav(`/employees/${r.id}`)}>
                      <td data-label={t('emp.no')} className="num">{r.employee_no}</td>
                      <td data-label={t('emp.name')}>
                        <Link to={`/employees/${r.id}`} onClick={(e) => e.stopPropagation()}>{L(r.full_name_en, r.full_name_ar)}</Link>
                        <span className="sub">{L(r.job_title_en, r.job_title_ar)}</span>
                      </td>
                      <td data-label={t('c.department')}>{L(r.department_en, r.department_ar)}
                        {r.location_en && <span className="sub">{L(r.location_en, r.location_ar)}</span>}</td>
                      <td data-label={t('emp.nationality')}>{L(r.nationality_en, r.nationality_ar)}</td>
                      <td data-label={t('emp.joined')}><DateText v={r.join_date} /></td>
                      <td data-label={t('c.status')}><StatusBadge status={r.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <Pager total={data.total} limit={LIMIT} offset={offset} onChange={(o) => set('offset', String(o))} />
          </>
        ) : null}
      </div>
    </div>
  );
}
