import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { api } from '../lib/api';
import { Button, ErrorNote, useAction } from '../components/ui';
import { Brand, LangSwitch } from '../components/Layout';

/** Shown to a signed-in user who has no role yet (or is deactivated). */
export function SetupPage() {
  const { t } = useI18n();
  const { me, meError, setMe, reload, signOut } = useSession();
  const { busy, run } = useAction();
  const first = me && !me.admin_exists;
  return (
    <div className="auth-wrap">
      <div className="auth-card">
        <div className="row" style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <Brand />
          <LangSwitch />
        </div>
        <div className="panel panel-pad stack">
          <ErrorNote error={meError} onRetry={() => void reload()} />
          {me && !me.is_active ? (
            <p>{t('setup.inactive')}</p>
          ) : first ? (
            <>
              <h1 style={{ fontSize: '1.3rem' }}>{t('setup.first_title')}</h1>
              <p>{t('setup.first_body')}</p>
              <Button kind="primary" busy={busy} onClick={async () => {
                const m = await run(() => api.claimFirstAdmin());
                if (m) setMe(m);
              }}>{t('setup.claim')}</Button>
            </>
          ) : me ? (
            <>
              <h1 style={{ fontSize: '1.3rem' }}>{t('setup.title')}</h1>
              <p>{t('setup.body', { email: me.email })}</p>
            </>
          ) : null}
          <div className="row">
            <Button onClick={() => void reload()}>{t('setup.refresh')}</Button>
            <span className="spacer" />
            <Button kind="ghost" onClick={() => void signOut()}>{t('c.signout')}</Button>
          </div>
        </div>
      </div>
    </div>
  );
}
