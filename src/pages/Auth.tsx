import { useState, type FormEvent, type ReactNode } from 'react';
import { supabase, configMissing } from '../lib/supabase';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, Input } from '../components/ui';
import { Brand, LangSwitch } from '../components/Layout';
import { CircleCheck, Lock } from 'lucide-react';
import { passwordOk } from '../lib/format';

type Mode = 'signin' | 'signup' | 'reset';

export function AuthPage() {
  const { t, errText } = useI18n();
  const [mode, setMode] = useState<Mode>('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true); setMsg(null);
    try {
      if (mode === 'signin') {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (error) throw error;
      } else if (mode === 'signup') {
        if (!passwordOk(password)) { setMsg({ text: t('auth.password_rule'), bad: true }); return; }
        const { data, error } = await supabase.auth.signUp({
          email: email.trim(), password, options: { data: { full_name: name.trim() }, emailRedirectTo: window.location.origin },
        });
        if (error) throw error;
        if (!data.session) { setMsg({ text: t('auth.signup_done') }); setMode('signin'); }
      } else {
        const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: window.location.origin });
        if (error) throw error;
        setMsg({ text: t('auth.reset_sent') });
      }
    } catch (err) {
      setMsg({ text: errText(err), bad: true });
    } finally {
      setBusy(false);
    }
  };

  const title = t(mode === 'signup' ? 'auth.signup' : mode === 'reset' ? 'auth.forgot' : 'auth.signin');
  return (
    <AuthFrame>
      <form className="stack" onSubmit={submit} noValidate>
        <div>
          <h2>{title}</h2>
          <p className="lead">{t('app.tagline')}</p>
        </div>
        {configMissing && <div className="note note-bad">{t('auth.config_missing')}</div>}
        {msg && <div className={`note ${msg.bad ? 'note-bad' : 'note-ok'}`} role={msg.bad ? 'alert' : 'status'}>{msg.text}</div>}
        {mode === 'signup' && <Input label={t('auth.full_name')} value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" required />}
        <Input label={t('auth.email')} type="email" ltr value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" required />
        {mode !== 'reset' && (
          <Input label={t('auth.password')} type="password" ltr value={password} onChange={(e) => setPassword(e.target.value)}
            autoComplete={mode === 'signup' ? 'new-password' : 'current-password'} required
            hint={mode === 'signup' ? t('auth.password_rule') : undefined} />
        )}
        <button type="submit" className="btn btn-primary" disabled={busy || configMissing || !email.trim() || (mode !== 'reset' && !password)}>
          {busy ? t('c.loading') : t(mode === 'signup' ? 'auth.signup' : mode === 'reset' ? 'auth.reset_send' : 'auth.signin')}
        </button>
        <div className="row" style={{ justifyContent: 'space-between' }}>
          {mode === 'signin'
            ? <><Button kind="ghost" small onClick={() => { setMode('signup'); setMsg(null); }}>{t('auth.no_account')}</Button>
                <Button kind="ghost" small onClick={() => { setMode('reset'); setMsg(null); }}>{t('auth.forgot')}</Button></>
            : <Button kind="ghost" small onClick={() => { setMode('signin'); setMsg(null); }}>{t('auth.have_account')}</Button>}
        </div>
        <div className="auth-secure"><Lock size={14} aria-hidden="true" />{t('auth.secure')}</div>
      </form>
    </AuthFrame>
  );
}

/** Split sign-in frame: brand panel (hidden on phones) and the form side. */
export function AuthFrame({ children }: { children: ReactNode }) {
  const { t } = useI18n();
  return (
    <div className="auth-split">
      <section className="auth-hero">
        <Brand dark />
        <div className="auth-hero-body">
          <h1>{t('auth.hero_title')}</h1>
          <p>{t('auth.hero_sub')}</p>
          <ul className="auth-points">
            {(['auth.hero_1', 'auth.hero_2', 'auth.hero_3'] as const).map((k) => (
              <li key={k}><CircleCheck size={18} aria-hidden="true" /><span>{t(k)}</span></li>
            ))}
          </ul>
        </div>
        <div className="auth-hero-foot">© {new Date().getFullYear()} AACT</div>
      </section>
      <section className="auth-side">
        <div className="auth-side-top">
          <div className="auth-mobile-brand"><Brand /></div>
          <LangSwitch />
        </div>
        <div className="auth-form-wrap">{children}</div>
      </section>
    </div>
  );
}

export function SetPasswordPage() {
  const { t, errText } = useI18n();
  const { clearRecovery } = useSession();
  const [pw, setPw] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; bad?: boolean } | null>(null);
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!passwordOk(pw)) { setMsg({ text: t('auth.password_rule'), bad: true }); return; }
    setBusy(true);
    const { error } = await supabase.auth.updateUser({ password: pw });
    setBusy(false);
    if (error) setMsg({ text: errText(error), bad: true });
    else { setMsg({ text: t('auth.password_set') }); window.setTimeout(clearRecovery, 1200); }
  };
  return (
    <AuthFrame>
      <form className="stack" onSubmit={submit}>
        <h2>{t('auth.set_password')}</h2>
        {msg && <div className={`note ${msg.bad ? 'note-bad' : 'note-ok'}`}>{msg.text}</div>}
        <Input label={t('auth.new_password')} type="password" ltr value={pw} onChange={(e) => setPw(e.target.value)}
          autoComplete="new-password" hint={t('auth.password_rule')} required />
        <button type="submit" className="btn btn-primary" disabled={busy}>{t('auth.set_password')}</button>
      </form>
    </AuthFrame>
  );
}
