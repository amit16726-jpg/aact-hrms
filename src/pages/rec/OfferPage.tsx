import { useParams } from 'react-router-dom';
import { offerText, recapi, type OfferFull } from '../../lib/api_rec';
import { useI18n } from '../../i18n';
import { Button, ErrorNote, Loading, useAsync } from '../../components/ui';
import { OfferBadge } from '../../components/rec';
import { canPrint } from '../../lib/native';

const dmy = (iso: string | null | undefined) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : '');

export default function OfferPage() {
  const { id = '' } = useParams();
  const { t } = useI18n();
  const { data, error, loading, reload } = useAsync(() => recapi.getOffer(id), [id]);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  return (
    <div className="stack">
      <div className="row no-print" style={{ justifyContent: 'space-between' }}>
        <div className="row"><Button onClick={() => window.history.back()}>{t('c.back')}</Button><OfferBadge s={data.status} /></div>
        {canPrint() && <Button kind="primary" onClick={() => window.print()}>{t('c.print')}</Button>}
      </div>
      <OfferSheet o={data} />
    </div>
  );
}

function OfferSheet({ o }: { o: OfferFull }) {
  const { t } = useI18n();
  const draft = o.status !== 'APPROVED' && o.status !== 'ACCEPTED';
  const set = o.settings;
  return (
    <article className={`letter letter-two panel panel-pad${draft ? ' letter-draft' : ''}`} aria-label={t('of.title')}>
      {draft && <div className="letter-watermark" aria-hidden="true">{t('lt.draft')}</div>}
      <header className="letter-head">
        <div lang="en" dir="ltr"><b>{o.entity_en}</b>{o.entity_cr && <span className="sub">CR {o.entity_cr}</span>}</div>
        <div lang="ar" dir="rtl" className="r"><b>{o.entity_ar || o.entity_en}</b>{o.entity_cr && <span className="sub">س.ت {o.entity_cr}</span>}</div>
      </header>
      <div className="letter-meta num" dir="ltr">
        <span>Ref / الرقم: <b>{o.ref_no}</b></span>
        <span>Date / التاريخ: <b>{dmy(o.approved_at?.slice(0, 10) ?? o.today)}</b></span>
      </div>
      <div className="letter-body">
        {(['en', 'ar'] as const).map((lg) => {
          const x = offerText(o, o.candidate, lg);
          return (
            <section key={lg} lang={lg} dir={lg === 'ar' ? 'rtl' : 'ltr'} className="letter-col">
              <h2 className="letter-title">{x.title}</h2>
              <p><b>{x.greeting}</b></p>
              <p>{x.intro}</p>
              <table className="t letter-salary"><tbody>{x.terms.map((r, i) => <tr key={i}><th scope="row">{r.label}</th><td>{r.value}</td></tr>)}</tbody></table>
              <table className="t letter-salary">
                <thead><tr><th>{lg === 'ar' ? 'الراتب الشهري' : 'Monthly salary'}</th><th className="r">{lg === 'ar' ? 'المبلغ (ر.ع)' : 'Amount (OMR)'}</th></tr></thead>
                <tbody>{x.salary.map((r, i) => <tr key={i}><td>{r.label}</td><td className="r num">{r.amount}</td></tr>)}</tbody>
                <tfoot><tr><th>{lg === 'ar' ? 'الإجمالي' : 'Total'}</th><th className="r num">{x.total}</th></tr></tfoot>
              </table>
              {x.closing.map((p, i) => <p key={i}>{p}</p>)}
              <div className="letter-sign">
                <span className="sub">{lg === 'ar' ? 'عن الشركة' : 'For the company'}</span>
                <div className="sig-line" />
                <b>{lg === 'ar' ? set?.signatory_name_ar : set?.signatory_name_en}</b>
                <span>{lg === 'ar' ? set?.signatory_ar || 'مدير الموارد البشرية' : set?.signatory_en || 'HR Manager'}</span>
              </div>
              <div className="letter-sign">
                <span>{x.accept}</span>
                <div className="sig-line" />
                <span className="sub">{lg === 'ar' ? 'توقيع المرشح والتاريخ' : 'Candidate signature and date'}</span>
              </div>
            </section>);
        })}
      </div>
    </article>
  );
}
