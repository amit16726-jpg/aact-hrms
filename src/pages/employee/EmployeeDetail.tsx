import { useEffect, useRef, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { api, checkFile, signedUrl, uploadFile, type EmployeeFile } from '../../lib/api';
import { useI18n } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, DateText, ErrorNote, Loading, StatusBadge, Tabs, useAction, useAsync, useConfirm, useToast } from '../../components/ui';
import { initials } from '../../lib/format';
import { ProfileTab } from './ProfileTab';
import { JobTab } from './JobTab';
import { ContractTab } from './ContractTab';
import { PayTab } from './PayTab';
import { BankTab } from './BankTab';
import { DocumentsTab } from './DocumentsTab';
import { HistoryTab } from './HistoryTab';
import { TimeTab } from './TimeTab';

type TabId = 'profile' | 'job' | 'contract' | 'time' | 'pay' | 'bank' | 'documents' | 'history';

export function Avatar({ path, name, small }: { path: string | null; name: string; small?: boolean }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    setUrl(null);
    if (path) signedUrl(path, 3600).then((u) => alive && setUrl(u)).catch(() => undefined);
    return () => { alive = false; };
  }, [path]);
  return (
    <div className={`avatar ${small ? 'avatar-sm' : ''}`} aria-hidden="true">
      {url ? <img src={url} alt="" /> : initials(name)}
    </div>
  );
}

function serviceText(from: string | undefined, to: string | null | undefined, lang: string): string {
  if (!from) return '—';
  const a = new Date(from + 'T00:00:00Z');
  const b = to ? new Date(to + 'T00:00:00Z') : new Date();
  let months = (b.getUTCFullYear() - a.getUTCFullYear()) * 12 + (b.getUTCMonth() - a.getUTCMonth());
  if (b.getUTCDate() < a.getUTCDate()) months -= 1;
  if (months < 0) return '—';
  const y = Math.floor(months / 12), m = months % 12;
  return lang === 'ar' ? `${y} سنة و${m} شهر` : `${y} yr ${m} mo`;
}

export default function EmployeeDetailPage() {
  const { id = '' } = useParams();
  const [params, setParams] = useSearchParams();
  const { t, L, lang } = useI18n();
  const { can, me } = useSession();
  const { data, error, loading, reload, setData } = useAsync(() => api.getEmployee(id), [id]);
  const tab = (params.get('tab') ?? 'profile') as TabId;
  const setTab = (v: TabId) => { const p = new URLSearchParams(params); p.set('tab', v); setParams(p, { replace: true }); };
  const fileRef = useRef<HTMLInputElement>(null);
  const { busy, run } = useAction();
  const { push } = useToast();
  const confirm = useConfirm();

  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  const f: EmployeeFile = data;
  const e = f.employee;
  const a = f.current_assignment;
  const team = f.access === 'TEAM';

  const tabs: { id: TabId; label: string }[] = [
    { id: 'profile', label: t('ed.tab_profile') },
    ...(!team ? [{ id: 'job' as TabId, label: t('ed.tab_job') }, { id: 'contract' as TabId, label: t('ed.tab_contract') }] : []),
    ...(can('ATT_READ') || can('LEAVE_READ') || team || me?.employee_id === e.id ? [{ id: 'time' as TabId, label: t('et.tab') }] : []),
    ...(f.caps.salary_read ? [{ id: 'pay' as TabId, label: t('ed.tab_pay') }] : []),
    ...(f.caps.bank_read ? [{ id: 'bank' as TabId, label: t('ed.tab_bank') }] : []),
    ...(f.caps.docs_read ? [{ id: 'documents' as TabId, label: t('ed.tab_documents') }] : []),
    ...(f.caps.history ? [{ id: 'history' as TabId, label: t('ed.tab_history') }] : []),
  ];
  const active = tabs.some((x) => x.id === tab) ? tab : 'profile';

  const onPhoto = async (file: File | undefined) => {
    if (!file) return;
    const bad = checkFile(file);
    if (bad || !file.type.startsWith('image/')) { push(t(bad === 'FILE_SIZE' ? 'doc.file_size' : 'doc.file_type'), true); return; }
    await run(async () => {
      const path = await uploadFile(e.id, 'PHOTO', file);
      setData(await api.setPhoto(e.id, path));
    }, t('c.saved'));
  };

  return (
    <div className="stack">
      <div className="panel panel-pad">
        <div className="person">
          <Avatar path={e.photo_path} name={e.full_name_en} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="row" style={{ gap: 10 }}>
              <h1>{L(e.full_name_en, e.full_name_ar)}</h1>
              <StatusBadge status={e.status} />
              {e.is_omani ? <Badge tone="info">{t('dash.omani')}</Badge> : <Badge>{t('dash.expat')}</Badge>}
              {e.pay_group === 'MG' && <Badge tone="warn">{t('pg.MG')}</Badge>}
            </div>
            {lang === 'en' && e.full_name_ar && <div className="ar-name" lang="ar" dir="rtl">{e.full_name_ar}</div>}
            {lang === 'ar' && <div className="muted" lang="en" dir="ltr">{e.full_name_en}</div>}
            <div className="muted-2" style={{ marginTop: 4 }}>
              <span className="num">{e.employee_no}</span>
              {a && <span>{lang === 'ar' ? '، ' : ', '}{L(a.job_title_en, a.job_title_ar)}{lang === 'ar' ? '، ' : ', '}{L(a.department_en, a.department_ar)}</span>}
            </div>
            <div className="muted row" style={{ fontSize: 13.5, gap: 16 }}>
              <span>{t('emp.joined')} <DateText v={e.join_date} /></span>
              <span>{t('ed.service')}: {serviceText(e.join_date, e.separation_date, lang)}</span>
            </div>
          </div>
          {f.caps.edit && (
            <div className="no-print">
              <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(ev) => { void onPhoto(ev.target.files?.[0]); ev.target.value = ''; }} />
              <Button small busy={busy} onClick={() => fileRef.current?.click()}>{t('ed.change_photo')}</Button>
            </div>
          )}
        </div>
        {team && <div className="note" style={{ marginTop: 14 }}>{t('ed.team_view')}</div>}
      </div>

      <div>
        <Tabs tabs={tabs} value={active} onChange={setTab} label={t('c.details')} />
        {active === 'profile' && <ProfileTab file={f} onChange={setData} confirm={confirm.ask} />}
        {active === 'job' && <JobTab file={f} onChange={setData} />}
        {active === 'contract' && <ContractTab file={f} onChange={setData} />}
        {active === 'time' && <TimeTab employeeId={e.id} />}
        {active === 'pay' && <PayTab file={f} confirm={confirm.ask} />}
        {active === 'bank' && <BankTab file={f} confirm={confirm.ask} />}
        {active === 'documents' && <DocumentsTab file={f} confirm={confirm.ask} />}
        {active === 'history' && <HistoryTab file={f} canAudit={can('AUDIT_READ')} />}
      </div>
      {confirm.node}
      <div className="no-print"><Link to="/employees">{t('c.back')}</Link></div>
    </div>
  );
}
