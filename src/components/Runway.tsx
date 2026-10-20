import { Link } from 'react-router-dom';
import { useI18n } from '../i18n';

/** Expiry runway: expired / 30 / 60 / 90 days, each segment links to the filtered tracker. */
export function Runway({ expired, d30, d60, d90, linkable = true }:
  { expired: number; d30: number; d60: number; d90: number; linkable?: boolean }) {
  const { t } = useI18n();
  const segs = [
    { b: 'EXPIRED', n: expired }, { b: 'D30', n: d30 }, { b: 'D60', n: d60 }, { b: 'D90', n: d90 },
  ] as const;
  return (
    <div className="runway" role="list">
      {segs.map((s) => {
        const cls = `seg seg-${s.b} ${s.n === 0 ? 'seg-zero' : ''}`;
        const body = (<><b className="num">{s.n}</b><span>{t(`b.${s.b}`)}</span></>);
        return linkable
          ? <Link key={s.b} role="listitem" className={cls} to={`/compliance/expiries?bucket=${s.b}`}>{body}</Link>
          : <div key={s.b} role="listitem" className={cls}>{body}</div>;
      })}
    </div>
  );
}
