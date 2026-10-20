import { useNavigate } from 'react-router-dom';
import { api, type Notification } from '../lib/api';
import { useI18n } from '../i18n';
import { Badge, Button, Empty, ErrorNote, Loading, useAction, useAsync } from '../components/ui';
import { PageHead } from '../components/Layout';
import { fmtDateTime } from '../lib/format';

export default function NotificationsPage() {
  const { t, L } = useI18n();
  const nav = useNavigate();
  const { data, error, loading, reload, setData } = useAsync(() => api.listNotifications(false), []);
  const { busy, run } = useAction();

  const open = async (n: Notification) => {
    if (!n.read_at) { const r = await run(() => api.markRead([n.id])); if (r) setData(r); }
    if (n.link) nav(n.link);
  };

  return (
    <div className="stack">
      <PageHead title={t('nt.title')} sub={data ? t('nt.unread', { n: data.unread }) : undefined}
        actions={data && data.unread > 0 && <Button busy={busy} onClick={async () => { const r = await run(() => api.markRead(null)); if (r) setData(r); }}>{t('nt.mark_all')}</Button>} />
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data || data.rows.length === 0 ? <Empty>{t('nt.empty')}</Empty> : (
          <ul style={{ margin: 0, padding: 0, listStyle: 'none' }}>
            {data.rows.map((n) => (
              <li key={n.id} style={{ borderBottom: '1px solid var(--line-soft)' }}>
                <button type="button" onClick={() => void open(n)} className="btn btn-ghost"
                  style={{ display: 'block', width: '100%', height: 'auto', textAlign: 'start', padding: '12px 20px', color: 'var(--ink)', whiteSpace: 'normal' }}>
                  <div className="row" style={{ gap: 8 }}>
                    {!n.read_at && <span aria-hidden="true" style={{ width: 8, height: 8, borderRadius: 4, background: 'var(--petrol)' }} />}
                    <b style={{ fontWeight: n.read_at ? 500 : 600 }}>{L(n.title_en, n.title_ar)}</b>
                    {n.priority === 'HIGH' && <Badge tone="bad">{t('b.EXPIRED')}</Badge>}
                    <span className="spacer" />
                    <span className="muted num" style={{ fontSize: 12.5 }}>{fmtDateTime(n.created_at)}</span>
                  </div>
                  {(n.body_en || n.body_ar) && <div className="muted-2" style={{ fontSize: 13.5, marginTop: 2 }}>{L(n.body_en, n.body_ar)}</div>}
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
