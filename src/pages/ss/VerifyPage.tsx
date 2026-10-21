import { useEffect, useState } from 'react';
import { ssapi, type LetterCheck } from '../../lib/api_ss';
import { useI18n, type Key } from '../../i18n';
import { Button, Input } from '../../components/ui';

const dmy = (iso: string | null | undefined) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : '');

/** Public page (no login): anyone holding a letter can check it with its reference and code. */
export default function VerifyPage() {
  const { t, L, lang, setLang } = useI18n();
  const q = new URLSearchParams(window.location.search);
  const [ref, setRef] = useState(q.get('ref') ?? '');
  const [code, setCode] = useState(q.get('code') ?? '');
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<LetterCheck | null>(null);
  const [err, setErr] = useState(false);
  const check = async (r = ref, c = code) => {
    setBusy(true); setErr(false);
    try { setRes(await ssapi.verifyLetter(r.trim(), c.trim().toUpperCase())); } catch { setErr(true); setRes(null); } finally { setBusy(false); }
  };
  useEffect(() => { if (q.get('ref') && q.get('code')) void check(q.get('ref') ?? '', q.get('code') ?? ''); }, []);
  return (
    <main className="verify-wrap">
      <div className="panel panel-pad stack verify-card">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h1 style={{ margin: 0, fontSize: '1.3rem' }}>{t('vf.title')}</h1>
          <Button small onClick={() => setLang(lang === 'ar' ? 'en' : 'ar')}>{lang === 'ar' ? 'English' : 'العربية'}</Button>
        </div>
        <p className="muted" style={{ margin: 0 }}>{t('vf.hint')}</p>
        <form className="stack" onSubmit={(e) => { e.preventDefault(); void check(); }}>
          <Input label={t('vf.ref')} ltr required value={ref} onChange={(e) => setRef(e.target.value)} placeholder="AACT/HR/2026/0001" />
          <Input label={t('vf.code')} ltr required value={code} maxLength={12} onChange={(e) => setCode(e.target.value.toUpperCase())} />
          <div><Button kind="primary" type="submit" busy={busy} disabled={!ref.trim() || code.trim().length !== 12}>{t('vf.check')}</Button></div>
        </form>
        {err && <div className="note note-bad" role="alert">{t('err.NETWORK')}</div>}
        {res && (res.valid ? (
          <div className="note note-ok" role="status">
            <b>{t('vf.valid')}</b>
            <dl className="kv" style={{ marginTop: 8 }}>
              <div><dt>{t('lt.type')}</dt><dd>{t(`lt.${res.letter_type}` as Key)}</dd></div>
              <div><dt>{t('vf.ref')}</dt><dd className="num">{res.ref_no}</dd></div>
              <div><dt>{t('vf.for')}</dt><dd>{L(res.full_name_en, res.full_name_ar)}</dd></div>
              <div><dt>{t('vf.by')}</dt><dd>{L(res.entity_en, res.entity_ar)}</dd></div>
              <div><dt>{t('lt.date')}</dt><dd className="num">{dmy(res.issue_date)}</dd></div>
            </dl>
          </div>
        ) : res.revoked ? <div className="note note-bad" role="status"><b>{t('vf.revoked')}</b> <span className="num">{res.ref_no}</span></div>
          : <div className="note note-bad" role="status">{t('vf.invalid')}</div>)}
        <a href="/">{t('vf.signin')}</a>
      </div>
    </main>
  );
}
