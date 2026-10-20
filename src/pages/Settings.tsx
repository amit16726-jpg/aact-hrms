import { useState } from 'react';
import { api } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, Input, Select, useAction } from '../components/ui';
import { PageHead } from '../components/Layout';

export default function SettingsPage() {
  const { t } = useI18n();
  const { me, can, setMe, reload } = useSession();
  const s = me?.settings ?? {};
  const [prefix, setPrefix] = useState(String(s.employee_no_prefix ?? 'AACT-'));
  const [digits, setDigits] = useState(String(s.employee_no_digits ?? 5));
  const [horizon, setHorizon] = useState(String(s.expiry_horizon_days ?? 90));
  const [defLang, setDefLang] = useState(String(s.default_language ?? 'en'));
  const [name, setName] = useState(me?.display_name ?? '');
  const { busy, run } = useAction();
  const example = `${prefix}${'1'.padStart(Math.min(8, Math.max(3, Number(digits) || 5)), '0')}`;

  const saveCompany = async () => {
    const ok = await run(async () => {
      await api.saveSetting('employee_no_prefix', prefix.trim().toUpperCase());
      await api.saveSetting('employee_no_digits', Number(digits));
      await api.saveSetting('expiry_horizon_days', Number(horizon));
      await api.saveSetting('default_language', defLang);
      return true;
    }, t('c.saved'));
    if (ok) void reload();
  };

  return (
    <div className="stack">
      <PageHead title={t('set.title')} />
      <section className="panel panel-pad stack" style={{ maxWidth: 640 }}>
        <h2>{t('set.my_profile')}</h2>
        <div className="form-grid">
          <Input label={t('set.display_name')} value={name} onChange={(e) => setName(e.target.value)} />
          <Input label={t('auth.email')} value={me?.email ?? ''} disabled ltr />
        </div>
        <div className="row row-end">
          <Button kind="primary" busy={busy} onClick={async () => { const m = await run(() => api.setMyProfile({ display_name: name }), t('c.saved')); if (m) setMe(m); }}>{t('c.save')}</Button>
        </div>
      </section>

      {can('USERS_ADMIN') && (
        <section className="panel panel-pad stack" style={{ maxWidth: 640 }}>
          <h2>{t('set.numbering')}</h2>
          <div className="form-grid">
            <Input label={t('set.prefix')} ltr value={prefix} maxLength={10} onChange={(e) => setPrefix(e.target.value.toUpperCase())} />
            <Input label={t('set.digits')} type="number" min={3} max={8} value={digits} onChange={(e) => setDigits(e.target.value)} />
            <div className="span-2 muted">{t('set.example', { ex: example })}</div>
            <Input label={t('set.horizon')} type="number" min={30} max={365} value={horizon} onChange={(e) => setHorizon(e.target.value)} />
            <Select label={t('set.default_lang')} value={defLang} onChange={(e) => setDefLang(e.target.value)}>
              <option value="en">English</option><option value="ar">العربية</option>
            </Select>
          </div>
          <div className="row row-end"><Button kind="primary" busy={busy} onClick={() => void saveCompany()}>{t('c.save')}</Button></div>
        </section>
      )}
    </div>
  );
}
