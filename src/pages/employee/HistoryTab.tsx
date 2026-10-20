import { api, type EmployeeFile } from '../../lib/api';
import { useI18n } from '../../i18n';
import { Badge, DateText, Empty, ErrorNote, Loading, useAsync } from '../../components/ui';
import { fmtDateTime } from '../../lib/format';
import { diffRows, show } from '../../lib/diff';

export function HistoryTab({ file, canAudit }: { file: EmployeeFile; canAudit: boolean }) {
  const { t, tk } = useI18n();
  const audit = useAsync(() => (canAudit ? api.listAudit({ employee_id: file.employee.id, limit: 200 }) : Promise.resolve(null)),
    [file.employee.id, canAudit]);

  return (
    <div className="grid-2">
      <section className="panel">
        <div className="panel-head"><h2>{t('h.events')}</h2></div>
        <div className="panel-body">
          {file.events.length === 0 ? <Empty>{t('h.no_events')}</Empty> : (
            <ol className="tl">
              {file.events.map((ev) => (
                <li key={ev.id}>
                  <div className="row" style={{ gap: 8 }}><b>{tk(`ev.${ev.event_type}`, ev.event_type)}</b><DateText v={ev.event_date} /></div>
                  <div className="muted" style={{ fontSize: 12.5 }}>{ev.created_by_name ?? '—'}, {fmtDateTime(ev.created_at)}</div>
                  {typeof ev.details?.notes === 'string' && ev.details.notes && <div style={{ fontSize: 13.5 }}>{ev.details.notes}</div>}
                  {typeof ev.details?.reason === 'string' && ev.event_type === 'OMANISATION_EXCEPTION' && <div style={{ fontSize: 13.5 }}>{ev.details.reason}</div>}
                </li>
              ))}
            </ol>
          )}
        </div>
      </section>

      {canAudit && (
        <section className="panel">
          <div className="panel-head"><h2>{t('h.changes')}</h2></div>
          <ErrorNote error={audit.error} onRetry={audit.reload} />
          {audit.loading && !audit.data ? <Loading /> : audit.data && audit.data.rows.length === 0 ? <Empty>{t('au.empty')}</Empty> : (
            <ul className="panel-body stack" style={{ margin: 0, listStyle: 'none' }}>
              {(audit.data?.rows ?? []).map((r) => {
                const ch = diffRows(r.old_data, r.new_data);
                return (
                  <li key={r.id}>
                    <div className="row" style={{ gap: 8 }}>
                      <Badge>{tk(`au.${r.action}`, r.action)}</Badge><span className="muted-2">{r.table_name}</span>
                      <span className="spacer" /><span className="muted" style={{ fontSize: 12.5 }}>{r.user_name ?? '—'}, {fmtDateTime(r.at)}</span>
                    </div>
                    {r.action === 'UPDATE' && (
                      <div className="diff">
                        {ch.slice(0, 12).map((c) => (
                          <div key={c.key}><span className="k">{c.key}: </span><del>{show(c.from)}</del> <ins>{show(c.to)}</ins></div>
                        ))}
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </section>
      )}
    </div>
  );
}
