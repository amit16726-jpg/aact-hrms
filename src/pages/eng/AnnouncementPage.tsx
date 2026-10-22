import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, CircleCheck, Pin, Users } from 'lucide-react';
import { useI18n } from '../../i18n';
import { eapi } from '../../lib/api_eng';
import { Button, ErrorNote, Loading, useAction, useAsync } from '../../components/ui';
import { AnnCategoryChip, EngStatus, audienceText } from '../../components/eng';
import { fmtDate, fmtDateTime } from '../../lib/format';

export default function AnnouncementPage() {
  const { id = '' } = useParams();
  const { t, L } = useI18n();
  const { data: a, error, loading, reload, setData } = useAsync(() => eapi.getAnnouncement(id), [id]);
  const { busy, run } = useAction();
  const ack = async () => {
    const r = await run(() => eapi.ackAnnouncement(id), t('eg.acked_ok'));
    if (r) setData(r);
  };
  return (
    <div className="stack eg-article-wrap">
      <Link to="/engage" className="eg-back"><ArrowLeft size={16} aria-hidden="true" className="eg-back-ico" />{t('eg.title')}</Link>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !a ? <Loading /> : a && (
        <article className="panel eg-article">
          <div className="eg-ann-top">
            <AnnCategoryChip c={a.category} />
            {a.pinned && <span className="eg-flag"><Pin size={12} aria-hidden="true" />{t('eg.pinned')}</span>}
            {!a.live && <EngStatus s={a.status} />}
          </div>
          <h1>{L(a.title_en, a.title_ar)}</h1>
          <div className="eg-meta">
            <span>{t('eg.posted', { d: fmtDate(a.publish_on) })}</span>
            {a.expires_on && <span>{t('eg.until', { d: fmtDate(a.expires_on) })}</span>}
            <span><Users size={13} aria-hidden="true" /> {audienceText(a, t, L)}</span>
          </div>
          <div className="eg-body">{L(a.body_en, a.body_ar)}</div>
          {a.require_ack && a.in_audience && (
            a.acknowledged_at
              ? <div className="note note-ok eg-ack-box"><CircleCheck size={18} aria-hidden="true" />{t('eg.acked', { d: fmtDateTime(a.acknowledged_at) })}</div>
              : <div className="note note-warn eg-ack-box">
                  <span>{t('eg.ack_hint')}</span>
                  <Button kind="primary" busy={busy} onClick={() => void ack()}><CircleCheck size={16} aria-hidden="true" /> {t('eg.ack')}</Button>
                </div>
          )}
          {a.stats && (
            <div className="eg-article-stats muted small">
              {t('ea.read_stats', { r: a.stats.read, a: a.stats.audience })}{a.require_ack && <> · {t('ea.ack_stats', { c: a.stats.acknowledged })}</>}
            </div>)}
        </article>
      )}
    </div>
  );
}
