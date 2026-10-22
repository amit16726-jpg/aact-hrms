import { useEffect, useState } from 'react';
import { ShieldCheck } from 'lucide-react';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, ErrorNote, Input, Loading } from '../components/ui';
import { AuthFrame } from './Auth';
import { codeOk, startEnrolment, verifiedFactor, verifyCode, type Enrolment } from '../lib/mfa';

/** Second step of signing in (CHALLENGE) or the required first set-up of an authenticator app (SETUP). */
export function MfaPage({ mode }: { mode: 'CHALLENGE' | 'SETUP' }) {
  const { t } = useI18n();
  const { reload, signOut } = useSession();
  const [factorId, setFactorId] = useState<string | null>(null);
  const [enrol, setEnrol] = useState<Enrolment | null>(null);
  const [code, setCode] = useState('');
  const [error, setError] = useState<unknown>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    void (async () => {
      try {
        if (mode === 'CHALLENGE') { const f = await verifiedFactor(); setFactorId(f?.id ?? null); }
        else { const e = await startEnrolment(); setEnrol(e); setFactorId(e.factorId); }
      } catch (e) { setError(e); } finally { setLoading(false); }
    })();
  }, [mode]);

  const submit = async (ev: React.FormEvent) => {
    ev.preventDefault();
    if (!factorId || !codeOk(code)) return;
    setBusy(true); setError(null);
    try { await verifyCode(factorId, code); await reload(); }
    catch (e) { setError(e); setCode(''); }
    finally { setBusy(false); }
  };

  return (
    <AuthFrame>
      <form className="auth-form stack" onSubmit={submit} noValidate>
        <div className="row" style={{ gap: 10 }}><ShieldCheck size={22} aria-hidden="true" />
          <h1 style={{ margin: 0, fontSize: '1.35rem' }}>{mode === 'CHALLENGE' ? t('mfa.challenge_title') : t('mfa.setup_title')}</h1></div>
        <p className="muted" style={{ margin: 0 }}>{mode === 'CHALLENGE' ? t('mfa.challenge_hint') : t('mfa.setup_hint')}</p>
        {loading ? <Loading /> : <>
          {enrol && (
            <div className="mfa-qr">
              <img src={enrol.qr} alt={t('mfa.qr_alt')} width={180} height={180} />
              <div className="muted" style={{ fontSize: 13 }}>{t('mfa.secret')} <code className="ltr-inline">{enrol.secret}</code></div>
            </div>)}
          <Input label={t('mfa.code')} ltr inputMode="numeric" autoComplete="one-time-code" maxLength={7} required autoFocus
            value={code} onChange={(e) => setCode(e.target.value.replace(/[^\d ]/g, ''))} />
          <ErrorNote error={error} />
          <Button kind="primary" type="submit" busy={busy} disabled={!factorId || !codeOk(code)}>{t('mfa.verify')}</Button>
        </>}
        <Button kind="ghost" type="button" onClick={() => void signOut()}>{t('c.signout')}</Button>
      </form>
    </AuthFrame>
  );
}
