import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { ssapi, type EmailAdmin } from '../lib/api_ss';
import { Badge, Check, Empty, useAsync } from '../components/ui';
import { fmtDateTime } from '../lib/format';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, Input, Select, useAction } from '../components/ui';
import { PageHead } from '../components/Layout';
import { HrPoliciesPanel } from '../components/wf';

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

      <EmailPrefPanel />
      {can('EMAIL_ADMIN') && <EmailAdminPanel />}
      {can('PERF_MANAGE') && can('DISC_APPROVE') && <HrPoliciesPanel />}

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

function EmailPrefPanel() {
  const { t } = useI18n();
  const { data, reload } = useAsync(() => ssapi.myEmailPref(), []);
  const { busy, run } = useAction();
  if (!data) return null;
  return (
    <section className="panel panel-pad stack" style={{ maxWidth: 640 }}>
      <h2>{t('em.my_pref')}</h2>
      <Check label={t('em.my_pref_hint', { e: data.email ?? '—' })} checked={data.email_opt_in} disabled={busy}
        onChange={async (v) => { if (await run(() => ssapi.setMyEmailPref(v), t('c.saved'))) void reload(); }} />
      {!data.sending_enabled && <div className="muted">{t('em.off_globally')}</div>}
    </section>
  );
}

function EmailAdminPanel() {
  const { t } = useI18n();
  const { data, reload } = useAsync(() => ssapi.emailSettings(), []);
  const [f, setF] = useState<EmailAdmin['settings'] | null>(null);
  const { busy, run } = useAction();
  useEffect(() => { if (data) setF({ ...data.settings }); }, [data]);
  if (!data || !f) return null;
  const save = async () => { if (await run(() => ssapi.saveEmailSettings({ ...f }), t('c.saved'))) void reload(); };
  const test = async () => { if (await run(() => ssapi.emailTest(), t('em.test_sent'))) void reload(); };
  return (
    <section className="panel panel-pad stack" style={{ maxWidth: 820 }}>
      <h2>{t('em.title')}</h2>
      <p className="muted" style={{ margin: 0 }}>{t('em.hint')}</p>
      <Check label={t('em.enabled')} checked={f.enabled} onChange={(v) => setF({ ...f, enabled: v })} />
      <div className="form-grid">
        <Input label={t('em.app_url')} ltr value={f.app_url} placeholder="https://hr.aact.om" onChange={(e) => setF({ ...f, app_url: e.target.value })} />
        <Input label={t('em.sender_name')} value={f.sender_name} maxLength={80} onChange={(e) => setF({ ...f, sender_name: e.target.value })} />
      </div>
      <div className="row row-end"><Button busy={busy} onClick={() => void test()}>{t('em.test')}</Button><Button kind="primary" busy={busy} onClick={() => void save()}>{t('c.save')}</Button></div>
      <div className="tile-row">
        <div className="tile"><span>{t('em.queued')}</span><b>{data.queue.queued}</b></div>
        <div className="tile"><span>{t('em.sent')}</span><b>{data.queue.sent}</b></div>
        <div className="tile"><span>{t('em.failed')}</span><b className={data.queue.failed ? 'bad-text' : ''}>{data.queue.failed}</b></div>
      </div>
      <h3 style={{ margin: 0 }}>{t('em.recent')}</h3>
      {!data.recent.length ? <Empty>{t('em.none')}</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('em.to')}</th><th>{t('em.subject')}</th><th>{t('c.status')}</th></tr></thead>
          <tbody>{data.recent.map((r) => (
            <tr key={r.id}>
              <td data-label={t('em.to')} className="ltr-inline">{r.to_email}<span className="sub num">{fmtDateTime(r.created_at)}</span></td>
              <td data-label={t('em.subject')}>{r.subject}</td>
              <td data-label={t('c.status')}><Badge tone={r.status === 'SENT' ? 'ok' : r.status === 'FAILED' ? 'bad' : 'warn'}>{r.status}</Badge>
                {r.last_error && <span className="sub">{r.last_error}</span>}</td>
            </tr>))}
          </tbody></table></div>)}
    </section>
  );
}
