import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { CONSENT_PURPOSES, DSR_KINDS, LEGAL_BASES, govapi, hoursText, type Activity, type Breach, type Dsr, type DsrKind, type LegalBasis, type PrivacyNotice, type RetentionRule, type Risk } from '../../lib/api_gov';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { DsrBadge, RiskBadge } from '../../components/gov';
import { fmtDate, fmtDateTime, todayMuscat } from '../../lib/format';

type Tab = 'overview' | 'notice' | 'consents' | 'requests' | 'breaches' | 'register' | 'retention' | 'settings';
const TABS: Tab[] = ['overview', 'notice', 'consents', 'requests', 'breaches', 'register', 'retention', 'settings'];

export default function PrivacyPage() {
  const { t } = useI18n();
  const [sp, setSp] = useSearchParams();
  const tab = (TABS.includes(sp.get('tab') as Tab) ? sp.get('tab') : 'overview') as Tab;
  return (
    <div className="stack">
      <PageHead title={t('pd.title')} sub={t('pd.hint')} />
      <Tabs label={t('pd.title')} value={tab} onChange={(v) => setSp(v === 'overview' ? {} : { tab: v }, { replace: true })}
        tabs={TABS.map((x) => ({ id: x, label: t(`pd.tab_${x}` as Key) }))} />
      {tab === 'overview' && <Overview />}
      {tab === 'notice' && <Notices />}
      {tab === 'consents' && <Consents />}
      {tab === 'requests' && <Requests />}
      {tab === 'breaches' && <Breaches />}
      {tab === 'register' && <Register />}
      {tab === 'retention' && <Retention />}
      {tab === 'settings' && <Settings />}
    </div>
  );
}

/** datetime-local in Muscat time (UTC+4). */
const toLocal = (iso: string | null) => (iso ? new Date(new Date(iso).getTime() + 4 * 3600000).toISOString().slice(0, 16) : '');
const fromLocal = (v: string) => (v ? `${v}:00+04:00` : null);

function Overview() {
  const { t } = useI18n();
  const { data: o, error, loading, reload } = useAsync(() => govapi.overview(), []);
  if (loading && !o) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!o) return null;
  const tile = (label: Key, v: number, bad: boolean, to: string) => (
    <Link className="tile kpi" to={to} style={{ textDecoration: 'none', color: 'inherit' }}><span>{t(label)}</span><b className={`num${bad && v > 0 ? ' bad-text' : ''}`}>{v}</b></Link>);
  return (
    <div className="stack">
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{o.notice_version ? t('pd.notice_v', { v: o.notice_version }) : t('pd.no_notice')}</h2>
        {o.notice_version != null && <><div className="num">{t('pd.acks', { n: o.acknowledged, u: o.users })}</div>
          <progress max={Math.max(o.users, 1)} value={o.acknowledged} aria-label={t('pd.acks', { n: o.acknowledged, u: o.users })} /></>}
        <div className="muted">{o.settings.dsr_legal_basis}<br />{o.settings.breach_legal_basis}</div>
      </section>
      <div className="tile-row">
        {tile('pd.dsr_open', o.dsr_open, false, '/privacy?tab=requests')}
        {tile('pd.dsr_overdue', o.dsr_overdue, true, '/privacy?tab=requests')}
        {tile('pd.br_open', o.breaches_open, false, '/privacy?tab=breaches')}
        {tile('pd.br_overdue', o.breaches_overdue, true, '/privacy?tab=breaches')}
        {tile('pd.act', o.activities, false, '/privacy?tab=register')}
        {tile('pd.act_unrev', o.activities_unreviewed, true, '/privacy?tab=register')}
        {tile('pd.cand_due', o.candidates_due, true, '/privacy?tab=retention')}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
function Notices() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload } = useAsync(() => govapi.listNotices(), []);
  const [edit, setEdit] = useState<PrivacyNotice | 'new' | null>(null);
  const [view, setView] = useState<string | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const publish = async (n: PrivacyNotice) => {
    if ((await confirm.ask({ title: `${t('pd.publish')} — v${n.version}`, body: t('pd.publish_q') })) === null) return;
    if (await run(() => govapi.publishNotice(n.id), t('c.saved'))) void reload();
  };
  return (
    <>
      {can('PDPL_MANAGE') && <div className="row" style={{ justifyContent: 'flex-end' }}><Button kind="primary" onClick={() => setEdit('new')}>{t('pd.new_version')}</Button></div>}
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('pd.no_notice')}</Empty> : data.map((n) => (
        <section key={n.id} className="panel panel-pad stack">
          <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 6 }}>
            <h2 style={{ margin: 0 }}>{L(n.title_en, n.title_ar)} <span className="muted num">v{n.version}</span> <Badge tone={n.status === 'PUBLISHED' ? 'ok' : n.status === 'DRAFT' ? 'warn' : undefined}>{t(`pd.n_st_${n.status}` as Key)}</Badge></h2>
            <div className="row" style={{ gap: 6 }}>
              <Button small onClick={() => setView(view === n.id ? null : n.id)}>{t('sap.open')}</Button>
              {n.status === 'DRAFT' && can('PDPL_MANAGE') && <><Button small onClick={() => setEdit(n)}>{t('pd.edit_notice')}</Button>
                <Button small kind="primary" busy={busy} onClick={() => void publish(n)}>{t('pd.publish')}</Button></>}
            </div>
          </div>
          <div className="muted">{n.prepared_by_name ? t('pd.prepared', { n: n.prepared_by_name }) : ''}
            {n.published_at ? ` · ${t('pd.published', { n: n.published_by_name ?? '', d: fmtDate(n.published_at) })} · ${t('pd.ack_count', { n: n.acknowledged })}` : ''}</div>
          {view === n.id && <div className="grid-2"><div className="notice-text" lang="en" dir="ltr">{n.body_en}</div><div className="notice-text" lang="ar" dir="rtl">{n.body_ar}</div></div>}
        </section>))}
      <NoticeDialog edit={edit} last={data?.[0] ?? null} onClose={() => setEdit(null)} onDone={() => { setEdit(null); void reload(); }} />
      {confirm.node}
    </>
  );
}

function NoticeDialog({ edit, last, onClose, onDone }: { edit: PrivacyNotice | 'new' | null; last: PrivacyNotice | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ title_en: '', title_ar: '', body_en: '', body_ar: '' });
  useEffect(() => {
    const src = edit === 'new' ? last : edit;
    if (edit) setF({ title_en: src?.title_en ?? '', title_ar: src?.title_ar ?? '', body_en: src?.body_en ?? '', body_ar: src?.body_ar ?? '' });
  }, [edit, last]);
  const save = async () => { if (await run(() => govapi.saveNotice({ ...(edit && edit !== 'new' ? { id: edit.id } : {}), ...f }), t('c.saved'))) onDone(); };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? 'pd.new_version' : 'pd.edit_notice')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={f.body_en.trim().length < 100 || f.body_ar.trim().length < 100 || !f.title_en || !f.title_ar} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="grid-2">
          <Input label={t('pd.title_en')} required value={f.title_en} onChange={(e) => setF({ ...f, title_en: e.target.value })} />
          <Input label={t('pd.title_ar')} required dir="rtl" value={f.title_ar} onChange={(e) => setF({ ...f, title_ar: e.target.value })} />
        </div>
        <Textarea label={t('pd.body_en')} required rows={12} value={f.body_en} onChange={(e) => setF({ ...f, body_en: e.target.value })} />
        <Textarea label={t('pd.body_ar')} required rows={12} dir="rtl" value={f.body_ar} onChange={(e) => setF({ ...f, body_ar: e.target.value })} />
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function Consents() {
  const { t, L } = useI18n();
  const { data, error, loading, reload } = useAsync(() => govapi.listConsents(), []);
  return (
    <div className="panel">
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>—</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('c.employee')}</th><th>{t('pd.ack_col')}</th>{CONSENT_PURPOSES.map((p) => <th key={p}>{t(`pc.${p}` as Key)}</th>)}</tr></thead>
          <tbody>{data.map((c) => (
            <tr key={c.user_id}>
              <td data-label={t('c.employee')}>{L(c.name, c.name_ar)}{c.employee_no && <span className="sub num">{c.employee_no}</span>}</td>
              <td data-label={t('pd.ack_col')}>{c.acknowledged_at ? <span className="num">{fmtDate(c.acknowledged_at)}</span> : <Badge tone="warn">{t('pd.not_ack')}</Badge>}</td>
              {CONSENT_PURPOSES.map((p) => <td key={p} data-label={t(`pc.${p}` as Key)}>{c.consents[p] === undefined ? '—' : c.consents[p] ? t('mp.yes') : t('mp.no')}</td>)}
            </tr>))}
          </tbody></table></div>)}
    </div>
  );
}

// ---------------------------------------------------------------------------
function Requests() {
  const { t } = useI18n();
  const { can } = useSession();
  const [status, setStatus] = useState('OPEN');
  const { data, error, loading, reload } = useAsync(() => govapi.listDsr({ status: status || null }), [status]);
  const [edit, setEdit] = useState<Dsr | 'new' | null>(null);
  const [closing, setClosing] = useState<Dsr | null>(null);
  const mng = can('PDPL_MANAGE');
  return (
    <>
      <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}>
        <div className="panel panel-pad row"><div className="field" style={{ minWidth: 200 }}><label htmlFor="dsr-st">{t('c.status')}</label>
          <select id="dsr-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="OPEN">{t('ds.OPEN')} / {t('ds.IN_PROGRESS')}</option><option value="">{t('c.all')}</option>
            <option value="COMPLETED">{t('ds.COMPLETED')}</option><option value="REJECTED">{t('ds.REJECTED')}</option>
          </select></div></div>
        {mng && <Button kind="primary" onClick={() => setEdit('new')}>{t('dr.new')}</Button>}
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('dr.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('dr.ref')}</th><th>{t('dr.requester')}</th><th>{t('dr.kind')}</th><th>{t('dr.due')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((d) => (
              <tr key={d.id}>
                <td data-label={t('dr.ref')}><span className="num">{d.ref_no}</span><span className="sub num">{fmtDate(d.received_on)}</span></td>
                <td data-label={t('dr.requester')}>{d.employee_id ? <Link to={`/employees/${d.employee_id}`}>{d.requester_name}</Link> : d.requester_name}
                  <span className="sub">{d.employee_no ?? d.contact ?? ''}</span></td>
                <td data-label={t('dr.kind')}>{t(`dk.${d.kind}` as Key)}<span className="sub wrap-text">{d.details}</span></td>
                <td data-label={t('dr.due')}><span className="num">{fmtDate(d.due_on)}</span>
                  {(d.status === 'OPEN' || d.status === 'IN_PROGRESS') && <span className={`sub${d.overdue ? ' bad-text' : ''}`}>{d.overdue ? t('dr.overdue', { n: -d.days_left }) : t('dr.left', { n: d.days_left })}</span>}</td>
                <td data-label={t('c.status')}><DsrBadge s={d.status} />{d.outcome && <span className="sub wrap-text">{d.outcome}</span>}</td>
                <td className="r">{mng && (d.status === 'OPEN' || d.status === 'IN_PROGRESS') && <div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  <Button small onClick={() => setEdit(d)}>{t('c.edit')}</Button><Button small kind="primary" onClick={() => setClosing(d)}>{t('dr.close')}</Button></div>}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <DsrDialog edit={edit} onClose={() => setEdit(null)} onDone={() => { setEdit(null); void reload(); }} />
      <CloseDsrDialog d={closing} onClose={() => setClosing(null)} onDone={() => { setClosing(null); void reload(); }} />
    </>
  );
}

function DsrDialog({ edit, onClose, onDone }: { edit: Dsr | 'new' | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ employee_id: null as string | null, label: '', requester_name: '', contact: '', kind: '' as DsrKind | '', details: '', received_on: '', identity_checked: false });
  useEffect(() => {
    if (edit === 'new') setF({ employee_id: null, label: '', requester_name: '', contact: '', kind: '', details: '', received_on: todayMuscat(), identity_checked: false });
    else if (edit) setF({ employee_id: edit.employee_id, label: edit.requester_name, requester_name: edit.requester_name, contact: edit.contact ?? '', kind: edit.kind,
      details: edit.details, received_on: edit.received_on, identity_checked: edit.identity_checked });
  }, [edit]);
  const save = async () => {
    if (await run(() => govapi.saveDsr({ ...(edit && edit !== 'new' ? { id: edit.id } : {}), employee_id: f.employee_id, requester_name: f.requester_name || null,
      contact: f.contact || null, kind: f.kind, details: f.details, received_on: f.received_on, identity_checked: f.identity_checked }), t('c.saved'))) onDone();
  };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? 'dr.new' : 'c.edit')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!f.kind || f.details.trim().length < 10 || (!f.employee_id && !f.requester_name.trim())} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {edit === 'new' && <EmployeePicker label={t('dr.employee')} value={f.employee_id} valueLabel={f.label} onChange={(id, l) => setF({ ...f, employee_id: id, label: l ?? '' })} />}
        <div className="grid-2">
          {edit === 'new' && <Input label={t('dr.requester')} value={f.requester_name} onChange={(e) => setF({ ...f, requester_name: e.target.value })} />}
          <Input label={t('dr.contact')} value={f.contact} onChange={(e) => setF({ ...f, contact: e.target.value })} />
          <Select label={t('dr.kind')} required value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value as DsrKind })}>
            <option value="">{t('c.select')}</option>{DSR_KINDS.map((k) => <option key={k} value={k}>{t(`dk.${k}` as Key)}</option>)}
          </Select>
          {edit === 'new' && <Input label={t('dr.received')} type="date" ltr max={todayMuscat()} value={f.received_on} onChange={(e) => setF({ ...f, received_on: e.target.value })} />}
        </div>
        <Textarea label={t('dr.details')} required value={f.details} onChange={(e) => setF({ ...f, details: e.target.value })} />
        <Check label={t('dr.identity')} checked={f.identity_checked} onChange={(v) => setF({ ...f, identity_checked: v })} />
      </div>
    </Modal>
  );
}

function CloseDsrDialog({ d, onClose, onDone }: { d: Dsr | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ status: 'COMPLETED' as 'COMPLETED' | 'REJECTED', outcome: '' });
  useEffect(() => { if (d) setF({ status: d.identity_checked ? 'COMPLETED' : 'REJECTED', outcome: '' }); }, [d]);
  const submit = async () => { if (d && (await run(() => govapi.closeDsr(d.id, f.status, f.outcome), t('c.saved')))) onDone(); };
  return (
    <Modal open={!!d} title={`${t('dr.close')} — ${d?.ref_no ?? ''}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={f.outcome.trim().length < 15} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <Select label={t('c.status')} value={f.status} onChange={(e) => setF({ ...f, status: e.target.value as 'COMPLETED' | 'REJECTED' })}>
          <option value="COMPLETED" disabled={!d?.identity_checked}>{t('dr.complete')}</option><option value="REJECTED">{t('dr.reject')}</option>
        </Select>
        <Textarea label={t('dr.outcome')} required value={f.outcome} onChange={(e) => setF({ ...f, outcome: e.target.value })} />
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function Breaches() {
  const { t, lang } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload } = useAsync(() => govapi.listBreaches(), []);
  const set = useAsync(() => govapi.settings(), []);
  const [edit, setEdit] = useState<Breach | 'new' | null>(null);
  const { busy, run } = useAction();
  const close = async (b: Breach) => { if (await run(() => govapi.closeBreach(b.id), t('c.saved'))) void reload(); };
  const mng = can('PDPL_MANAGE');
  return (
    <>
      <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
        <div className="note" style={{ flex: '1 1 300px' }}>{t('br.hint', { h: set.data?.breach_hours ?? 72 })}</div>
        {mng && <Button kind="primary" onClick={() => setEdit('new')}>{t('br.new')}</Button>}
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('br.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('br.ref')}</th><th>{t('br.description')}</th><th>{t('br.risk')}</th><th>{t('br.notified')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((b) => (
              <tr key={b.id}>
                <td data-label={t('br.ref')}><span className="num">{b.ref_no}</span><span className="sub num">{fmtDateTime(b.discovered_at)}</span></td>
                <td data-label={t('br.description')}><span className="wrap-text">{b.description}</span>{b.people_affected != null && <span className="sub">{t('br.people')}: <span className="num">{b.people_affected}</span></span>}</td>
                <td data-label={t('br.risk')}><RiskBadge r={b.risk} /></td>
                <td data-label={t('br.notified')}>{b.authority_notified_at ? <><span className="num">{fmtDateTime(b.authority_notified_at)}</span>{b.notified_late && <span className="sub"><Badge tone="warn">{t('br.late')}</Badge></span>}</>
                  : b.not_notified_reason ? <span className="muted wrap-text">{b.not_notified_reason}</span>
                  : b.overdue ? <Badge tone="bad">{t('br.overdue')}</Badge>
                  : <span className="warn-text">{t('br.deadline', { d: fmtDateTime(b.deadline) })}<span className="sub">{t('br.left', { h: hoursText(b.hours_left, lang) })}</span></span>}</td>
                <td data-label={t('c.status')}><Badge tone={b.status === 'OPEN' ? 'warn' : 'ok'}>{t(`br.st_${b.status}` as Key)}</Badge></td>
                <td className="r">{mng && b.status === 'OPEN' && <div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  <Button small onClick={() => setEdit(b)}>{t('c.edit')}</Button><Button small busy={busy} onClick={() => void close(b)}>{t('br.close')}</Button></div>}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <BreachDialog edit={edit} onClose={() => setEdit(null)} onDone={() => { setEdit(null); void reload(); }} />
    </>
  );
}

function BreachDialog({ edit, onClose, onDone }: { edit: Breach | 'new' | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const blank = () => ({ discovered_at: toLocal(new Date().toISOString()), occurred_at: '', description: '', data_kinds: '', people_affected: '', risk: '' as Risk | '',
    containment: '', contained_at: '', authority_notified_at: '', authority_reference: '', not_notified_reason: '', subjects_notified_at: '' });
  const [f, setF] = useState(blank);
  useEffect(() => {
    if (edit === 'new') setF(blank());
    else if (edit) setF({ discovered_at: toLocal(edit.discovered_at), occurred_at: toLocal(edit.occurred_at), description: edit.description, data_kinds: edit.data_kinds ?? '',
      people_affected: edit.people_affected != null ? String(edit.people_affected) : '', risk: edit.risk, containment: edit.containment ?? '', contained_at: toLocal(edit.contained_at),
      authority_notified_at: toLocal(edit.authority_notified_at), authority_reference: edit.authority_reference ?? '', not_notified_reason: edit.not_notified_reason ?? '',
      subjects_notified_at: toLocal(edit.subjects_notified_at) });
  }, [edit]);
  const set = (k: keyof ReturnType<typeof blank>) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const save = async () => {
    if (await run(() => govapi.saveBreach({ ...(edit && edit !== 'new' ? { id: edit.id } : {}), discovered_at: fromLocal(f.discovered_at), occurred_at: fromLocal(f.occurred_at),
      description: f.description, data_kinds: f.data_kinds || null, people_affected: f.people_affected ? Number(f.people_affected) : null, risk: f.risk,
      containment: f.containment || null, contained_at: fromLocal(f.contained_at), authority_notified_at: fromLocal(f.authority_notified_at),
      authority_reference: f.authority_reference || null, not_notified_reason: f.not_notified_reason || null, subjects_notified_at: fromLocal(f.subjects_notified_at) }), t('c.saved'))) onDone();
  };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? 'br.new' : 'c.edit')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.discovered_at || !f.risk || f.description.trim().length < 20} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="grid-3">
          <Input label={t('br.discovered')} type="datetime-local" ltr required value={f.discovered_at} onChange={set('discovered_at')} />
          <Input label={t('br.occurred')} type="datetime-local" ltr value={f.occurred_at} onChange={set('occurred_at')} />
          <Select label={t('br.risk')} required value={f.risk} onChange={set('risk')}>
            <option value="">{t('c.select')}</option>{(['LOW', 'MEDIUM', 'HIGH'] as const).map((r) => <option key={r} value={r}>{t(`br.r_${r}`)}</option>)}
          </Select>
        </div>
        <Textarea label={t('br.description')} required value={f.description} onChange={set('description')} />
        <div className="grid-2">
          <Input label={t('br.data_kinds')} value={f.data_kinds} onChange={set('data_kinds')} />
          <Input label={t('br.people')} type="number" min={0} ltr value={f.people_affected} onChange={set('people_affected')} />
        </div>
        <Textarea label={t('br.containment')} value={f.containment} onChange={set('containment')} />
        <div className="grid-3">
          <Input label={t('br.contained')} type="datetime-local" ltr value={f.contained_at} onChange={set('contained_at')} />
          <Input label={t('br.notified')} type="datetime-local" ltr value={f.authority_notified_at} onChange={set('authority_notified_at')} />
          <Input label={t('br.reference')} ltr value={f.authority_reference} onChange={set('authority_reference')} />
        </div>
        <div className="grid-2">
          <Input label={t('br.subjects')} type="datetime-local" ltr value={f.subjects_notified_at} onChange={set('subjects_notified_at')} />
          <Input label={t('br.not_notified')} value={f.not_notified_reason} onChange={set('not_notified_reason')} />
        </div>
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function Register() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload, setData } = useAsync(() => govapi.listActivities(), []);
  const [edit, setEdit] = useState<Activity | 'new' | null>(null);
  return (
    <>
      {can('PDPL_MANAGE') && <div className="row" style={{ justifyContent: 'flex-end' }}><Button kind="primary" onClick={() => setEdit('new')}>{t('ra.new')}</Button></div>}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>—</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('ra.name_en')}</th><th>{t('ra.basis')}</th><th>{t('ra.categories')}</th><th>{t('ra.recipients')}</th><th>{t('ra.retention')}</th><th /></tr></thead>
            <tbody>{data.map((a) => (
              <tr key={a.id}>
                <td data-label={t('ra.name_en')}><b>{L(a.name_en, a.name_ar)}</b>{a.sensitive && <> <Badge tone="warn">{t('ra.sensitive')}</Badge></>}
                  <span className="sub">{a.purpose}</span><span className="sub muted">{a.code}{a.reviewed_at ? ` · ${t('ra.reviewed', { d: fmtDate(a.reviewed_at) })}` : ''}{!a.is_active ? ` · ${t('c.inactive')}` : ''}</span></td>
                <td data-label={t('ra.basis')}>{t(`lb.${a.legal_basis}` as Key)}</td>
                <td data-label={t('ra.categories')}>{a.data_categories}<span className="sub">{a.data_subjects}</span></td>
                <td data-label={t('ra.recipients')}>{a.recipients ?? '—'}{a.transfer_outside_oman && <span className="sub">{t('ra.transfer')}: {a.transfer_outside_oman}</span>}</td>
                <td data-label={t('ra.retention')}>{a.retention ?? '—'}</td>
                <td className="r">{can('PDPL_MANAGE') && <Button small onClick={() => setEdit(a)}>{t('c.edit')}</Button>}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <ActivityDialog edit={edit} onClose={() => setEdit(null)} onDone={(r) => { setData(r); setEdit(null); }} />
    </>
  );
}

function ActivityDialog({ edit, onClose, onDone }: { edit: Activity | 'new' | null; onClose: () => void; onDone: (r: Activity[]) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const blank = { code: '', name_en: '', name_ar: '', purpose: '', legal_basis: '' as LegalBasis | '', data_subjects: '', data_categories: '', sensitive: false, recipients: '',
    transfer_outside_oman: '', retention: '', security: '', system_owner: '', is_active: true };
  const [f, setF] = useState(blank);
  useEffect(() => {
    if (edit === 'new') setF(blank);
    else if (edit) setF({ code: edit.code, name_en: edit.name_en, name_ar: edit.name_ar ?? '', purpose: edit.purpose, legal_basis: edit.legal_basis, data_subjects: edit.data_subjects,
      data_categories: edit.data_categories, sensitive: edit.sensitive, recipients: edit.recipients ?? '', transfer_outside_oman: edit.transfer_outside_oman ?? '',
      retention: edit.retention ?? '', security: edit.security ?? '', system_owner: edit.system_owner ?? '', is_active: edit.is_active });
  }, [edit]); // eslint-disable-line react-hooks/exhaustive-deps
  const set = (k: keyof typeof blank) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const save = async () => {
    const r = await run(() => govapi.saveActivity({ ...(edit && edit !== 'new' ? { id: edit.id } : {}), ...f, name_ar: f.name_ar || null, recipients: f.recipients || null,
      transfer_outside_oman: f.transfer_outside_oman || null, retention: f.retention || null, security: f.security || null, system_owner: f.system_owner || null }), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? 'ra.new' : 'c.edit')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!f.code || !f.name_en || !f.purpose || !f.legal_basis || !f.data_subjects || !f.data_categories} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="grid-3">
          <Input label={t('ra.code')} required ltr value={f.code} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} />
          <Input label={t('ra.name_en')} required value={f.name_en} onChange={set('name_en')} />
          <Input label={t('ra.name_ar')} dir="rtl" value={f.name_ar} onChange={set('name_ar')} />
        </div>
        <Input label={t('ra.purpose')} required value={f.purpose} onChange={set('purpose')} />
        <div className="grid-3">
          <Select label={t('ra.basis')} required value={f.legal_basis} onChange={set('legal_basis')}>
            <option value="">{t('c.select')}</option>{LEGAL_BASES.map((b) => <option key={b} value={b}>{t(`lb.${b}` as Key)}</option>)}
          </Select>
          <Input label={t('ra.subjects')} required value={f.data_subjects} onChange={set('data_subjects')} />
          <Input label={t('ra.categories')} required value={f.data_categories} onChange={set('data_categories')} />
        </div>
        <div className="grid-2">
          <Input label={t('ra.recipients')} value={f.recipients} onChange={set('recipients')} />
          <Input label={t('ra.transfer')} value={f.transfer_outside_oman} onChange={set('transfer_outside_oman')} />
          <Input label={t('ra.retention')} value={f.retention} onChange={set('retention')} />
          <Input label={t('ra.owner')} value={f.system_owner} onChange={set('system_owner')} />
        </div>
        <Textarea label={t('ra.security')} value={f.security} onChange={set('security')} />
        <Check label={t('ra.sensitive')} checked={f.sensitive} onChange={(v) => setF({ ...f, sensitive: v })} />
        <Check label={t('ra.active')} checked={f.is_active} onChange={(v) => setF({ ...f, is_active: v })} />
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function Retention() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload } = useAsync(() => govapi.retention(), []);
  const [pick, setPick] = useState<string[]>([]);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const anon = async () => {
    if ((await confirm.ask({ title: t('rt.anonymise'), body: t('rt.anonymise_q', { n: pick.length }), danger: true })) === null) return;
    const r = await run(() => govapi.anonymise(pick));
    if (r) { setPick([]); void reload(); }
  };
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  return (
    <div className="stack">
      <section className="panel">
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('rt.rule')}</th><th className="r">{t('rt.months')}</th><th>{t('rt.basis')}</th><th className="r">{t('rt.due')}</th></tr></thead>
          <tbody>{data.rules.map((r) => (
            <tr key={r.code}><td data-label={t('rt.rule')}>{L(r.en, r.ar)}</td><td data-label={t('rt.months')} className="r num">{r.months}</td>
              <td data-label={t('rt.basis')} className="muted">{r.basis}</td>
              <td data-label={t('rt.due')} className="r">{r.due != null ? <span className={`num${r.due ? ' warn-text' : ''}`}>{r.due}</span> : '—'}
                {r.due ? <span className="sub">{r.action === 'ANONYMISE' ? t('rt.anonymise') : t('rt.review')}</span> : null}</td></tr>))}
          </tbody></table></div>
      </section>
      <section className="panel">
        <div className="panel-head"><h2>{t('rt.candidates')}</h2>
          {can('PDPL_MANAGE') && <Button small kind="danger" busy={busy} disabled={!pick.length} onClick={() => void anon()}>{t('rt.anonymise')}</Button>}</div>
        {!data.candidates.length ? <Empty>{t('rt.none')}</Empty> : (
          <ul className="plain panel-pad stack" style={{ gap: 4 }}>{data.candidates.map((c) => (
            <li key={c.id}><Check label={<>{c.full_name_en} <span className="muted num">· {c.nationality} · {fmtDate(c.updated_at)}</span></>} checked={pick.includes(c.id)}
              onChange={(v) => setPick(v ? [...pick, c.id] : pick.filter((x) => x !== c.id))} disabled={!can('PDPL_MANAGE')} /></li>))}
          </ul>)}
      </section>
      {confirm.node}
    </div>
  );
}

function Settings() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload } = useAsync(() => govapi.settings(), []);
  const [f, setF] = useState({ dpo_name: '', dpo_email: '', retention: [] as RetentionRule[] });
  const { busy, run } = useAction();
  useEffect(() => { if (data) setF({ dpo_name: data.dpo_name ?? '', dpo_email: data.dpo_email ?? '', retention: data.retention }); }, [data]);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  const save = async () => { if (await run(() => govapi.saveSettings({ dpo_name: f.dpo_name || null, dpo_email: f.dpo_email || null, retention: f.retention }), t('ps.saved'))) void reload(); };
  const ro = !can('PDPL_MANAGE');
  return (
    <section className="panel panel-pad stack" style={{ maxWidth: 820 }}>
      <div className="grid-2">
        <Input label={t('ps.dpo_name')} value={f.dpo_name} disabled={ro} onChange={(e) => setF({ ...f, dpo_name: e.target.value })} />
        <Input label={t('ps.dpo_email')} type="email" ltr value={f.dpo_email} disabled={ro} onChange={(e) => setF({ ...f, dpo_email: e.target.value })} />
      </div>
      <b>{t('pd.tab_retention')}</b>
      {f.retention.map((r, i) => (
        <div key={r.code} style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) 110px', gap: 8, alignItems: 'end' }}>
          <Input label={L(r.en, r.ar)} value={r.basis} disabled={ro} onChange={(e) => setF({ ...f, retention: f.retention.map((x, j) => (j === i ? { ...x, basis: e.target.value } : x)) })} />
          <Input label={t('rt.months')} type="number" min={1} max={600} ltr value={String(r.months)} disabled={ro}
            onChange={(e) => setF({ ...f, retention: f.retention.map((x, j) => (j === i ? { ...x, months: Number(e.target.value) || 0 } : x)) })} />
        </div>))}
      <b>{t('ps.legal')}</b>
      <div className="muted">{data.dsr_legal_basis}<br />{data.breach_legal_basis}</div>
      {!ro && <div><Button kind="primary" busy={busy} onClick={() => void save()}>{t('c.save')}</Button></div>}
    </section>
  );
}
