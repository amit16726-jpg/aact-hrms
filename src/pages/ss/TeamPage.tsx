import { Link } from 'react-router-dom';
import { ssapi } from '../../lib/api_ss';
import { useI18n } from '../../i18n';
import { Badge, Empty, ErrorNote, Loading, useAsync } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { AttBadge } from '../../components/time';
import type { AttStatus } from '../../lib/api_time';
import { fmtDate } from '../../lib/format';

export default function TeamPage() {
  const { t, L } = useI18n();
  const { data, error, loading, reload } = useAsync(() => ssapi.myTeam(), []);
  const present = (data ?? []).filter((m) => m.today?.status === 'PRESENT').length;
  const away = (data ?? []).filter((m) => m.on_leave).length;
  const waiting = (data ?? []).reduce((s, m) => s + m.pending, 0);
  return (
    <div className="stack">
      <PageHead title={t('tm.title')} sub={data?.length ? t('tm.counts', { n: data.length, p: present, l: away }) : t('tm.hint')}
        actions={waiting > 0 && <Link className="btn btn-primary" to="/approvals">{t('tm.pending', { n: waiting })}</Link>} />
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('tm.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('me.job')}</th><th>{t('tm.today')}</th><th>{t('c.status')}</th><th>{t('tm.contact')}</th></tr></thead>
            <tbody>{data.map((m) => (
              <tr key={m.employee_id}>
                <td data-label={t('c.employee')}><Link to={`/employees/${m.employee_id}`}>{L(m.full_name_en, m.full_name_ar)}</Link>
                  <span className="sub num">{m.employee_no} · {m.direct ? t('tm.direct') : t('tm.indirect')}</span></td>
                <td data-label={t('me.job')}>{L(m.job_en, m.job_ar) || '—'}<span className="sub">{L(m.department_en, m.department_ar)}</span></td>
                <td data-label={t('tm.today')}>{m.on_leave ? <Badge tone="info">{t('tm.on_leave', { d: fmtDate(m.on_leave.end_date) })}</Badge>
                  : m.today ? <AttBadge status={m.today.status as AttStatus} late={m.today.late_minutes} /> : <span className="muted">{t('tm.no_record')}</span>}</td>
                <td data-label={t('c.status')}>
                  {m.pending > 0 && <div><Link to="/approvals">{t('tm.pending', { n: m.pending })}</Link></div>}
                  {m.expiring > 0 && <div className="warn-text">{t('tm.expiring', { n: m.expiring })}</div>}
                  {m.status === 'PROBATION' && m.probation_end_date && <div className="muted">{t('tm.probation', { d: fmtDate(m.probation_end_date) })}</div>}
                  {!m.pending && !m.expiring && m.status !== 'PROBATION' && <span className="muted">—</span>}
                </td>
                <td data-label={t('tm.contact')}>{m.mobile && <a className="num ltr-inline" href={`tel:${m.mobile.replace(/[^+0-9]/g, '')}`}>{m.mobile}</a>}
                  {m.work_email && <span className="sub"><a href={`mailto:${m.work_email}`}>{m.work_email}</a></span>}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
    </div>
  );
}
