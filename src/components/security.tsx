import { useEffect, useState, useCallback } from 'react';
import { ShieldCheck, Timer } from 'lucide-react';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { api, type RoleDef } from '../lib/api';
import { Badge, Button, Check, ErrorNote, Input, Modal, useAction, useAsync } from './ui';
import { codeOk, removeFactor, startEnrolment, verifiedFactor, verifyCode, type Enrolment } from '../lib/mfa';
import { useIdleSignOut } from '../lib/idle';
import { fmtDate } from '../lib/format';

/** Settings → my two-step sign-in. */
export function MyMfaPanel() {
  const { t } = useI18n();
  const { reload } = useSession();
  const { data: factor, error, reload: again } = useAsync(() => verifiedFactor(), []);
  const [enrol, setEnrol] = useState<Enrolment | null>(null);
  const [code, setCode] = useState('');
  const { busy, run } = useAction();
  const start = async () => { const e = await run(() => startEnrolment()); if (e) { setEnrol(e); setCode(''); } };
  const finish = async () => {
    if (!enrol) return;
    const ok = await run(async () => { await verifyCode(enrol.factorId, code); return true; }, t('mfa.done'));
    if (ok) { setEnrol(null); void again(); void reload(); }
  };
  const remove = async () => {
    if (!factor) return;
    const ok = await run(async () => { await removeFactor(factor.id); return true; }, t('mfa.removed'));
    if (ok) { void again(); void reload(); }
  };
  return (
    <section className="panel panel-pad stack" style={{ maxWidth: 640 }}>
      <div className="row" style={{ gap: 10 }}><ShieldCheck size={20} aria-hidden="true" /><h2 style={{ margin: 0 }}>{t('mfa.title')}</h2>
        {factor ? <Badge tone="ok">{t('mfa.on')}</Badge> : <Badge>{t('mfa.off')}</Badge>}</div>
      <p className="muted" style={{ margin: 0 }}>{t('mfa.panel_hint')}</p>
      <ErrorNote error={error} />
      {factor ? (
        <div className="row"><span className="muted">{t('mfa.since', { d: fmtDate(factor.created_at.slice(0, 10)) })}</span>
          <span className="spacer" /><Button busy={busy} onClick={() => void remove()}>{t('mfa.remove')}</Button></div>
      ) : <div className="row"><Button kind="primary" busy={busy} onClick={() => void start()}>{t('mfa.set_up')}</Button></div>}
      <Modal open={!!enrol} title={t('mfa.setup_title')} onClose={() => setEnrol(null)}
        footer={<><Button onClick={() => setEnrol(null)}>{t('c.cancel')}</Button>
          <Button kind="primary" busy={busy} disabled={!codeOk(code)} onClick={() => void finish()}>{t('mfa.verify')}</Button></>}>
        {enrol && <div className="stack">
          <p className="muted" style={{ margin: 0 }}>{t('mfa.setup_hint')}</p>
          <div className="mfa-qr"><img src={enrol.qr} alt={t('mfa.qr_alt')} width={180} height={180} />
            <div className="muted" style={{ fontSize: 13 }}>{t('mfa.secret')} <code className="ltr-inline">{enrol.secret}</code></div></div>
          <Input label={t('mfa.code')} ltr inputMode="numeric" autoComplete="one-time-code" maxLength={7} value={code}
            onChange={(e) => setCode(e.target.value.replace(/[^\d ]/g, ''))} />
        </div>}
      </Modal>
    </section>
  );
}

/** Settings → security policy (administrators): automatic sign-out and two-step sign-in for chosen roles. */
export function SecurityPolicyPanel() {
  const { t, L } = useI18n();
  const { me, reload } = useSession();
  const s = me?.settings ?? {};
  const mfa = (s.mfa ?? { required: false, roles: [] }) as { required: boolean; roles: string[] };
  const [idle, setIdle] = useState(String(s.session_idle_minutes ?? 30));
  const [required, setRequired] = useState(!!mfa.required);
  const [roles, setRoles] = useState<string[]>(mfa.roles ?? []);
  const roleDefs = useAsync(() => api.listRoles(), []);
  const { busy, run } = useAction();
  const save = async () => {
    const ok = await run(async () => {
      await api.saveSetting('session_idle_minutes', Number(idle));
      await api.saveSetting('mfa', { required, roles });
      return true;
    }, t('c.saved'));
    if (ok) void reload();
  };
  return (
    <section className="panel panel-pad stack" style={{ maxWidth: 640 }}>
      <div className="row" style={{ gap: 10 }}><Timer size={20} aria-hidden="true" /><h2 style={{ margin: 0 }}>{t('sec.title')}</h2></div>
      <Input label={t('sec.idle')} hint={t('sec.idle_hint')} type="number" ltr min={5} max={480} value={idle} onChange={(e) => setIdle(e.target.value)} />
      <Check label={t('sec.require')} checked={required} onChange={setRequired} />
      <fieldset className="rp-recipients" disabled={!required}>
        <legend>{t('sec.roles')}</legend>
        {(roleDefs.data?.roles ?? []).map((r: RoleDef) => (
          <Check key={r.code} label={L(r.name_en, r.name_ar)} checked={roles.includes(r.code)}
            onChange={(v) => setRoles(v ? [...roles, r.code] : roles.filter((x) => x !== r.code))} />))}
      </fieldset>
      <p className="muted" style={{ margin: 0, fontSize: 13 }}>{t('sec.require_hint')}</p>
      <div className="row row-end"><Button kind="primary" busy={busy} onClick={() => void save()}>{t('c.save')}</Button></div>
    </section>
  );
}

/** Signs out after the configured time without activity; warns in the last minute. */
export function IdleGuard() {
  const { t } = useI18n();
  const { me, signOut } = useSession();
  const minutes = Number(me?.settings?.session_idle_minutes ?? 30) || 30;
  const expire = useCallback(() => { void signOut(); }, [signOut]);
  const { warnIn, stay } = useIdleSignOut(minutes, expire);
  const [shown, setShown] = useState(false);
  useEffect(() => { setShown(warnIn !== null); }, [warnIn]);
  return (
    <Modal open={shown} title={t('idle.title')} onClose={stay}
      footer={<><Button onClick={() => void signOut()}>{t('c.signout')}</Button><Button kind="primary" onClick={stay}>{t('idle.stay')}</Button></>}>
      <p style={{ margin: 0 }}>{t('idle.body', { s: warnIn ?? 0 })}</p>
    </Modal>
  );
}
