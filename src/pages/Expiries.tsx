import { useMemo } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { api } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, Check, DateText, DaysLeft, Empty, ErrorNote, Loading, useAction, useAsync, useToast } from '../components/ui';
import { useMasters } from '../components/pickers';
import { PageHead } from '../components/Layout';
import { Runway } from '../components/Runway';
import { downloadCsv } from '../lib/csv';
import { fmtDate } from '../lib/format';

export default function ExpiriesPage() {
  const { t, L, tk } = useI18n();
  const { can } = useSession();
  const [params, setParams] = useSearchParams();
  const within = params.get('within') ?? '90';
  const bucket = params.get('bucket') ?? '';
  const docType = params.get('doc_type') ?? '';
  const includeExpired = params.get('expired') !== '0';
  const types = useMasters('document_type', null);
  const { busy, run } = useAction();
  const { push } = useToast();

  const set = (k: string, v: string | null) => { const p = new URLSearchParams(params); if (v) p.set(k, v); else p.delete(k); setParams(p, { replace: true }); };

  const { data, error, loading, reload } = useAsync(
    () => api.listExpiries({ within_days: within === 'ALL' ? null : Number(within), include_expired: includeExpired, doc_type: docType || null }),
    [within, includeExpired, docType]);

  const rows = useMemo(() => (data ?? []).filter((r) => !bucket || r.bucket === bucket), [data, bucket]);
  const counts = useMemo(() => {
    const c = { EXPIRED: 0, D30: 0, D60: 0, D90: 0 };
    for (const r of data ?? []) if (r.bucket in c) c[r.bucket as keyof typeof c] += 1;
    return c;
  }, [data]);

  const exportCsv = () => downloadCsv(`expiries-${new Date().toISOString().slice(0, 10)}.csv`,
    [t('emp.no'), t('emp.name'), t('c.department'), t('doc.type'), t('doc.number'), t('cp.expiry'), t('cp.days_left')],
    rows.map((r) => [r.employee_no, L(r.full_name_en, r.full_name_ar), L(r.department_en, r.department_ar),
      r.source === 'CONTRACT' ? t('cp.contract') : L(r.name_en, r.name_ar), r.doc_number, fmtDate(r.expiry_date), r.days_left]));

  return (
    <div className="stack">
      <PageHead title={t('cp.expiries_title')} actions={<>
        {can('COMPLIANCE_READ') && <Button busy={busy} onClick={async () => {
          const r = await run(() => api.runExpiryScan());
          if (r) push(t('cp.scan_done', { n: r.created }));
        }}>{t('cp.scan')}</Button>}
        <Button onClick={exportCsv} disabled={!rows.length}>{t('c.export')}</Button>
      </>} />

      <Runway expired={counts.EXPIRED} d30={counts.D30} d60={counts.D60} d90={counts.D90} />

      <div className="panel panel-pad row" style={{ gap: 16 }}>
        <div className="field" style={{ minWidth: 160 }}>
          <label htmlFor="ex-within">{t('cp.within')}</label>
          <select id="ex-within" className="select" value={within} onChange={(e) => set('within', e.target.value)}>
            {['30', '60', '90', '180', '365', 'ALL'].map((d) => <option key={d} value={d}>{d === 'ALL' ? t('c.all') : t('c.days', { n: d })}</option>)}
          </select>
        </div>
        <div className="field" style={{ minWidth: 200 }}>
          <label htmlFor="ex-type">{t('doc.type')}</label>
          <select id="ex-type" className="select" value={docType} onChange={(e) => set('doc_type', e.target.value || null)}>
            <option value="">{t('c.all')}</option>
            <option value="CONTRACT">{t('cp.contract')}</option>
            {types.filter((x) => (x as unknown as { has_expiry: boolean }).has_expiry).map((x) => <option key={x.code} value={x.code}>{L(x.name_en, x.name_ar)}</option>)}
          </select>
        </div>
        <div className="field" style={{ minWidth: 160 }}>
          <label htmlFor="ex-bucket">{t('c.status')}</label>
          <select id="ex-bucket" className="select" value={bucket} onChange={(e) => set('bucket', e.target.value || null)}>
            <option value="">{t('c.all')}</option>
            {['EXPIRED', 'D30', 'D60', 'D90', 'LATER'].map((b) => <option key={b} value={b}>{tk(`b.${b}`, b)}</option>)}
          </select>
        </div>
        <Check label={t('cp.include_expired')} checked={includeExpired} onChange={(v) => set('expired', v ? null : '0')} />
      </div>

      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : rows.length === 0 ? <Empty>{t('cp.no_expiries')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('c.department')}</th><th>{t('doc.type')}</th><th>{t('doc.number')}</th>
              <th>{t('cp.expiry')}</th><th>{t('cp.days_left')}</th></tr></thead>
            <tbody>{rows.map((r) => (
              <tr key={`${r.source}-${r.ref_id}`}>
                <td data-label={t('c.employee')}><Link to={`/employees/${r.employee_id}?tab=${r.source === 'CONTRACT' ? 'contract' : 'documents'}`}>{L(r.full_name_en, r.full_name_ar)}</Link>
                  <span className="sub num">{r.employee_no}</span></td>
                <td data-label={t('c.department')}>{L(r.department_en, r.department_ar) || '—'}</td>
                <td data-label={t('doc.type')}>{r.source === 'CONTRACT' ? t('cp.contract') : L(r.name_en, r.name_ar)}</td>
                <td data-label={t('doc.number')} className="num">{r.doc_number ?? '—'}</td>
                <td data-label={t('cp.expiry')}><DateText v={r.expiry_date} /></td>
                <td data-label={t('cp.days_left')}><DaysLeft days={r.days_left} /></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
    </div>
  );
}
