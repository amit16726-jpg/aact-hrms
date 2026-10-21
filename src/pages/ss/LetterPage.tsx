import { Link, useParams } from 'react-router-dom';
import { letterText, ssapi, verifyUrl, type LetterFull, type LetterSnapshot } from '../../lib/api_ss';
import { useI18n, type Key } from '../../i18n';
import { Button, ErrorNote, Loading, useAsync } from '../../components/ui';
import { LetterBadge } from '../../components/ss';

const dmy = (iso: string | null | undefined) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : '');

export default function LetterPage() {
  const { id = '' } = useParams();
  const { t } = useI18n();
  const { data, error, loading, reload } = useAsync(() => ssapi.getLetter(id), [id]);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  const snap = data.snapshot ?? data.preview;
  return (
    <div className="stack">
      <div className="row no-print" style={{ justifyContent: 'space-between' }}>
        <div className="row"><Button onClick={() => window.history.back()}>{t('c.back')}</Button><LetterBadge l={data} /></div>
        {data.status === 'ISSUED' && !data.revoked && <Button kind="primary" onClick={() => window.print()}>{t('c.print')}</Button>}
      </div>
      {data.revoked && <div className="note note-bad no-print">{t('lt.withdrawn_banner', { r: data.revoke_reason ?? '' })}</div>}
      {data.salary_hidden && <div className="note no-print">{t('lt.salary_hidden')}</div>}
      {!snap ? <div className="note">{t('lt.no_salary')}</div> : <LetterSheet l={data} s={snap} />}
      <div className="no-print"><Link to="/me?tab=letters">{t('me.tab_letters')}</Link></div>
    </div>
  );
}

function LetterSheet({ l, s }: { l: LetterFull; s: LetterSnapshot }) {
  const { t } = useI18n();
  const draft = l.status !== 'ISSUED';
  const langs: ('en' | 'ar')[] = l.language === 'EN' ? ['en'] : l.language === 'AR' ? ['ar'] : ['en', 'ar'];
  const set = l.settings;
  const url = l.ref_no && l.verify_code ? verifyUrl(set?.verify_base_url, window.location.origin, l.ref_no, l.verify_code) : null;
  return (
    <article className={`letter panel panel-pad${draft ? ' letter-draft' : ''}${langs.length === 2 ? ' letter-two' : ''}`} aria-label={t(`lt.${l.letter_type}` as Key)}>
      {draft && <div className="letter-watermark" aria-hidden="true">{t('lt.draft')}</div>}
      <header className="letter-head">
        <div lang="en" dir="ltr"><b>{s.entity_en}</b>{s.entity_cr && <span className="sub">CR {s.entity_cr}</span>}</div>
        <div lang="ar" dir="rtl" className="r"><b>{s.entity_ar}</b>{s.entity_cr && <span className="sub">س.ت {s.entity_cr}</span>}</div>
      </header>
      <div className="letter-meta num" dir="ltr">
        <span>Ref / الرقم: <b>{l.ref_no ?? '—'}</b></span>
        <span>Date / التاريخ: <b>{dmy(l.issue_date) || '—'}</b></span>
      </div>
      <div className="letter-body">
        {langs.map((lg) => {
          const x = letterText(l, s, lg);
          return (
            <section key={lg} lang={lg} dir={lg === 'ar' ? 'rtl' : 'ltr'} className="letter-col">
              <h2 className="letter-title">{x.title}</h2>
              <p><b>{x.salutation}</b></p>
              {x.paragraphs.map((p, i) => (
                <div key={i}>
                  <p>{p}</p>
                  {x.salary && i === 1 && (
                    <table className="t letter-salary">
                      <thead><tr><th>{lg === 'ar' ? 'البند' : 'Component'}</th><th className="r">{lg === 'ar' ? 'المبلغ (ر.ع)' : 'Amount (OMR)'}</th></tr></thead>
                      <tbody>{x.salary.map((r, j) => <tr key={j}><td>{r.label}</td><td className="r num">{r.amount}</td></tr>)}</tbody>
                      <tfoot><tr><th>{lg === 'ar' ? 'الإجمالي' : 'Total'}</th><th className="r num">{x.total}</th></tr></tfoot>
                    </table>)}
                </div>))}
              <p>{x.closing}</p>
              <div className="letter-sign">
                <div className="sig-line" />
                <b>{lg === 'ar' ? set?.signatory_name_ar : set?.signatory_name_en}</b>
                <span>{lg === 'ar' ? set?.signatory_ar || 'مدير الموارد البشرية' : set?.signatory_en || 'HR Manager'}</span>
                <span className="sub">{s.entity_en && (lg === 'ar' ? s.entity_ar : s.entity_en)}</span>
              </div>
              {(lg === 'ar' ? set?.footer_ar : set?.footer_en) && <p className="sub letter-footer">{lg === 'ar' ? set?.footer_ar : set?.footer_en}</p>}
            </section>);
        })}
      </div>
      {url && (
        <footer className="letter-verify" dir="ltr">
          <span>{t('lt.verify_line')}: <span className="num">{url}</span></span>
          <span>{t('lt.code')}: <b className="num">{l.verify_code}</b></span>
        </footer>)}
    </article>
  );
}
