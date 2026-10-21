import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { SS_FIELDS, changedFields, ssapi, type Contact, type Portal, type SsField } from '../../lib/api_ss';
import { useI18n, type Key } from '../../i18n';
import { Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync, useConfirm, useToast } from '../../components/ui';
import { CountrySelect } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { OMR, monthName } from '../../components/pay';
import { ReqBadge } from '../../components/time';
import { ChangeBadge, ChangeSummary, LetterBadge, LetterLine, LetterRequestDialog, downloadJson, fieldLabel } from '../../components/ss';
import { fmtDate, fmtDateTime, todayMuscat } from '../../lib/format';
import type { ReqStatus } from '../../lib/api_time';
import { CONSENT_PURPOSES, DSR_KINDS, govapi, type ConsentPurpose, type DsrKind } from '../../lib/api_gov';
import { DsrBadge } from '../../components/gov';

type Tab = 'overview' | 'details' | 'letters' | 'requests' | 'privacy';
type Dialog = null | 'profile' | 'contacts' | 'bank' | 'correction' | 'letter';

export default function MyHrPage() {
  const { t } = useI18n();
  const [sp, setSp] = useSearchParams();
  const tab = (['overview', 'details', 'letters', 'requests', 'privacy'].includes(sp.get('tab') ?? '') ? sp.get('tab') : 'overview') as Tab;
  const setTab = (v: Tab) => setSp(v === 'overview' ? {} : { tab: v }, { replace: true });
  const { data, error, loading, reload } = useAsync(() => ssapi.portal(), []);
  const [dlg, setDlg] = useState<Dialog>(null);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  if (!data.linked || !data.employee) return <div className="stack"><PageHead title={t('me.title')} /><div className="note note-warn">{t('me.not_linked')}</div></div>;
  const open = (d: Dialog) => setDlg(d);
  const done = () => { setDlg(null); void reload(); };
  const openReq = (data.changes ?? []).filter((c) => c.status === 'PENDING').length + (data.letters ?? []).filter((l) => l.status === 'REQUESTED' || l.status === 'PREPARED').length;
  return (
    <div className="stack">
      <PageHead title={t('me.title')} sub={t('me.hint')} />
      <Tabs label={t('me.title')} value={tab} onChange={setTab} tabs={[
        { id: 'overview', label: t('me.tab_overview') }, { id: 'details', label: t('me.tab_details') },
        { id: 'letters', label: t('me.tab_letters') }, { id: 'requests', label: <>{t('me.tab_requests')}{openReq ? <span className="count-pill">{openReq}</span> : null}</> },
        { id: 'privacy', label: t('me.tab_privacy') }]} />
      {tab === 'overview' && <Overview p={data} open={open} />}
      {tab === 'details' && <Details p={data} open={open} />}
      {tab === 'letters' && <Letters p={data} open={open} reload={reload} />}
      {tab === 'requests' && <Requests p={data} reload={reload} />}
      {tab === 'privacy' && <Privacy open={open} />}
      <ProfileDialog open={dlg === 'profile'} p={data} onClose={() => setDlg(null)} onDone={done} />
      <ContactsDialog open={dlg === 'contacts'} p={data} onClose={() => setDlg(null)} onDone={done} />
      <BankDialog open={dlg === 'bank'} p={data} onClose={() => setDlg(null)} onDone={done} />
      <CorrectionDialog open={dlg === 'correction'} onClose={() => setDlg(null)} onDone={done} />
      <LetterRequestDialog open={dlg === 'letter'} employeeStatus={data.employee.status} onClose={() => setDlg(null)} onDone={() => { done(); setTab('letters'); }} />
    </div>
  );
}

function Overview({ p, open }: { p: Portal; open: (d: Dialog) => void }) {
  const { t, L, lang } = useI18n();
  const e = p.employee!;
  const ready = (p.letters ?? []).filter((l) => l.status === 'ISSUED' && !l.revoked).slice(0, 3);
  const openReq = (p.changes ?? []).filter((c) => c.status === 'PENDING').length + (p.letters ?? []).filter((l) => l.status === 'REQUESTED' || l.status === 'PREPARED').length;
  return (
    <div className="grid-2" style={{ alignItems: 'start' }}>
      <section className="panel panel-pad stack">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h2 style={{ margin: 0 }}>{L(e.full_name_en, e.full_name_ar)}</h2><Link to="/my">{t('me.open_record')}</Link>
        </div>
        <dl className="kv">
          <div><dt>{t('ef.employee_no')}</dt><dd className="num">{e.employee_no}</dd></div>
          <div><dt>{t('me.job')}</dt><dd>{L(e.job_en, e.job_ar) || '—'}<span className="sub">{L(e.department_en, e.department_ar)}</span></dd></div>
          <div><dt>{t('me.manager')}</dt><dd>{L(e.manager_en, e.manager_ar) || '—'}</dd></div>
          <div><dt>{t('me.joined')}</dt><dd className="num">{fmtDate(e.join_date)}</dd></div>
        </dl>
        {e.status === 'PROBATION' && e.probation_end_date && <div className="note">{t('me.probation_until', { d: fmtDate(e.probation_end_date) })}</div>}
      </section>
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('me.quick')}</h2>
        <div className="quick-grid">
          <Link className="btn" to="/leave">{t('me.q_leave')}</Link>
          <Button onClick={() => open('letter')}>{t('me.q_letter')}</Button>
          <Button onClick={() => open('profile')}>{t('me.q_update')}</Button>
          <Button onClick={() => open('correction')}>{t('me.q_correction')}</Button>
        </div>
        {openReq > 0 && <div className="muted">{t('me.open_requests', { n: openReq })}</div>}
      </section>
      <section className="panel panel-pad stack">
        <div className="row" style={{ justifyContent: 'space-between' }}><h2 style={{ margin: 0 }}>{t('tnav.leave')}</h2><Link to="/leave">{t('me.open_leave')}</Link></div>
        <div className="tile-row">
          <div className="tile"><span>{t('me.annual_left')}</span><b>{p.annual?.available ?? '—'}</b></div>
          <div className="tile"><span>{t('me.sick_used')}</span><b>{p.sick?.used ?? 0}</b></div>
        </div>
        {p.next_leave && <div>{t('me.next_leave')}: {L(p.next_leave.name_en, p.next_leave.name_ar)} · <span className="num">{fmtDate(p.next_leave.start_date)} – {fmtDate(p.next_leave.end_date)}</span> <ReqBadge status={p.next_leave.status as ReqStatus} /></div>}
        {(p.leave_pending ?? 0) > 0 && <div className="muted">{t('me.leave_pending', { n: p.leave_pending ?? 0 })}</div>}
      </section>
      <section className="panel panel-pad stack">
        <div className="row" style={{ justifyContent: 'space-between' }}><h2 style={{ margin: 0 }}>{t('me.last_payslip')}</h2><Link to="/payslips">{t('me.open_payslips')}</Link></div>
        {p.last_payslip ? <div><Link to={`/payslips/${p.last_payslip.id}`}>{monthName(p.last_payslip.month, lang)}</Link> · <b className="num">OMR {OMR(p.last_payslip.net)}</b></div>
          : <div className="muted">{t('me.no_payslip')}</div>}
      </section>
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('me.expiring')}</h2>
        {!(p.expiring ?? []).length ? <div className="muted">{t('me.no_expiring')}</div> : (
          <ul className="plain">{(p.expiring ?? []).map((x, i) => (
            <li key={i} className={x.days_left < 0 ? 'bad-text' : x.days_left <= 30 ? 'warn-text' : ''}><b>{L(x.name_en, x.name_ar)}</b> — {x.days_left < 0
              ? t('me.expired', { d: fmtDate(x.expiry_date) }) : t('me.expires_in', { d: fmtDate(x.expiry_date), n: x.days_left })}</li>))}</ul>)}
      </section>
      {ready.length > 0 && (
        <section className="panel panel-pad stack">
          <h2 style={{ margin: 0 }}>{t('me.letters_ready')}</h2>
          <ul className="plain">{ready.map((l) => <li key={l.id}><Link to={`/letters/${l.id}`}>{t(`lt.${l.letter_type}` as Key)}</Link> <span className="muted num">{l.ref_no}</span></li>)}</ul>
        </section>
      )}
    </div>
  );
}

function Details({ p, open }: { p: Portal; open: (d: Dialog) => void }) {
  const { t } = useI18n();
  const e = p.employee!;
  const pending = (k: string) => (p.changes ?? []).some((c) => c.kind === k && c.status === 'PENDING');
  const val = (f: SsField) => {
    const v = e[f];
    if (!v) return '—';
    if (f === 'marital_status') return t(`ef.${v}` as Key);
    return v;
  };
  return (
    <div className="stack">
      <section className="panel panel-pad stack">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h2 style={{ margin: 0 }}>{t('me.personal')}</h2>
          <Button kind="primary" disabled={pending('PROFILE')} onClick={() => open('profile')}>{t('me.edit_request')}</Button>
        </div>
        {pending('PROFILE') && <div className="note">{t('rq.st_PENDING')}</div>}
        <dl className="kv">
          <div><dt>{t('ef.full_name_en')}</dt><dd>{e.full_name_en}</dd></div>
          <div><dt>{t('ef.full_name_ar')}</dt><dd>{e.full_name_ar || '—'}</dd></div>
          <div><dt>{t('ef.dob')}</dt><dd className="num">{fmtDate(e.date_of_birth)}</dd></div>
          <div><dt>{t('ef.civil')}</dt><dd className="num">{e.civil_number || '—'}</dd></div>
          <div><dt>{t('ef.work_email')}</dt><dd className="ltr-inline">{e.work_email || '—'}</dd></div>
          {SS_FIELDS.map((f) => <div key={f}><dt>{fieldLabel(t, f)}</dt><dd className={f === 'mobile' || f === 'alt_phone' || f === 'personal_email' ? 'ltr-inline num' : ''}>{val(f)}</dd></div>)}
        </dl>
        <p className="muted" style={{ margin: 0 }}>{t('me.locked_fields')} <button type="button" className="link-btn" onClick={() => open('correction')}>{t('me.correction')}</button></p>
      </section>
      <section className="panel panel-pad stack">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h2 style={{ margin: 0 }}>{t('me.contacts')}</h2>
          <Button disabled={pending('EMERGENCY')} onClick={() => open('contacts')}>{t('me.contacts_request')}</Button>
        </div>
        {!(p.emergency_contacts ?? []).length ? <Empty>{t('ed.no_contacts')}</Empty> : (
          <ul className="plain">{(p.emergency_contacts ?? []).map((c, i) => <li key={i}><b>{c.name}</b> · {c.relationship} · <span className="num ltr-inline">{c.phone}</span>{c.is_next_of_kin ? ` · ${t('ed.next_of_kin')}` : ''}</li>)}</ul>)}
      </section>
      <section className="panel panel-pad stack">
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <h2 style={{ margin: 0 }}>{t('me.bank')}</h2>
          <Button disabled={pending('BANK') || p.bank_pending} onClick={() => open('bank')}>{t('me.bank_request')}</Button>
        </div>
        {p.bank ? <div>{p.bank.bank_name} · <span className="num ltr-inline">{p.bank.account}</span></div> : <div className="muted">{t('me.bank_none')}</div>}
        {(p.bank_pending || pending('BANK')) && <div className="note">{t('me.bank_pending')}</div>}
      </section>
    </div>
  );
}

function Letters({ p, open, reload }: { p: Portal; open: (d: Dialog) => void; reload: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const cancel = async (id: string) => {
    if ((await confirm.ask({ title: t('rq.cancel_q'), danger: true })) === null) return;
    if (await run(() => ssapi.cancelLetter(id))) reload();
  };
  return (
    <section className="panel">
      <div className="panel-head"><h2>{t('me.tab_letters')}</h2><Button kind="primary" onClick={() => open('letter')}>{t('lt.new')}</Button></div>
      {!(p.letters ?? []).length ? <Empty>{t('lt.none')}</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('lt.type')}</th><th>{t('rq.requested')}</th><th>{t('c.status')}</th><th /></tr></thead>
          <tbody>{(p.letters ?? []).map((l) => (
            <tr key={l.id}>
              <td data-label={t('lt.type')}><LetterLine l={l} /></td>
              <td data-label={t('rq.requested')} className="num">{fmtDateTime(l.requested_at)}</td>
              <td data-label={t('c.status')}><LetterBadge l={l} />{l.decision_note && l.status === 'REJECTED' && <span className="sub">{l.decision_note}</span>}</td>
              <td className="r"><div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                {l.status === 'ISSUED' && <Link className="btn btn-sm btn-primary" to={`/letters/${l.id}`}>{t('lt.view')}</Link>}
                {l.can_cancel && <Button small busy={busy} onClick={() => void cancel(l.id)}>{t('lt.cancel')}</Button>}
              </div></td>
            </tr>))}
          </tbody></table></div>)}
      {confirm.node}
    </section>
  );
}

function Requests({ p, reload }: { p: Portal; reload: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const cancel = async (id: string) => {
    if ((await confirm.ask({ title: t('rq.cancel_q'), danger: true })) === null) return;
    if (await run(() => ssapi.cancelChange(id))) reload();
  };
  return (
    <section className="panel">
      <div className="panel-head"><h2>{t('me.tab_requests')}</h2></div>
      {!(p.changes ?? []).length ? <Empty>{t('rq.none')}</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('c.type')}</th><th>{t('rq.what')}</th><th>{t('rq.requested')}</th><th>{t('c.status')}</th><th /></tr></thead>
          <tbody>{(p.changes ?? []).map((c) => (
            <tr key={c.id}>
              <td data-label={t('c.type')}><b>{t(`rq.k_${c.kind}` as Key)}</b></td>
              <td data-label={t('rq.what')}><ChangeSummary c={c} /></td>
              <td data-label={t('rq.requested')} className="num">{fmtDate(c.requested_at)}{c.status === 'PENDING' && <span className="sub">{t('rq.due')}: {fmtDate(c.due_date)}</span>}</td>
              <td data-label={t('c.status')}><ChangeBadge c={c} />{c.decided_at && <span className="sub">{t('rq.decided', { n: c.decided_by_name ?? '', d: fmtDate(c.decided_at) })}</span>}
                {c.decision_note && <span className="sub">{c.decision_note}</span>}</td>
              <td className="r">{c.can_cancel && <Button small busy={busy} onClick={() => void cancel(c.id)}>{t('rq.cancel')}</Button>}</td>
            </tr>))}
          </tbody></table></div>)}
      {confirm.node}
    </section>
  );
}

function Privacy({ open }: { open: (d: Dialog) => void }) {
  const { t, L, lang } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const { data: mp, error, reload, setData } = useAsync(() => govapi.myPrivacy(), []);
  const [req, setReq] = useState({ kind: '' as DsrKind | '', details: '' });
  const download = async () => {
    const d = await run(() => ssapi.dataExport());
    if (d) { downloadJson(`my-hr-data-${todayMuscat()}.json`, d); push(t('pv.downloaded')); }
  };
  const ack = async () => { const r = await run(() => govapi.ackNotice(), t('mp.saved')); if (r) setData(r); };
  const consent = async (p: ConsentPurpose, given: boolean) => { const r = await run(() => govapi.setConsent(p, given), t('mp.saved')); if (r) setData(r); };
  const submit = async () => {
    if (!req.kind) return;
    const r = await run(() => govapi.submitDsr(req.kind as DsrKind, req.details), t('mp.sent'));
    if (r) { setData(r); setReq({ kind: '', details: '' }); }
  };
  return (
    <div className="stack" style={{ maxWidth: 820 }}>
      <ErrorNote error={error} onRetry={reload} />
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('mp.notice')}</h2>
        {!mp ? null : !mp.notice ? <div className="muted">{t('mp.none')}</div> : <>
          <b>{L(mp.notice.title_en, mp.notice.title_ar)} <span className="muted num">v{mp.notice.version}</span></b>
          <div className="notice-text" dir={lang === 'ar' ? 'rtl' : 'ltr'}>{lang === 'ar' ? mp.notice.body_ar : mp.notice.body_en}</div>
          {mp.acknowledged_at ? <div className="note">{t('mp.acked', { v: mp.notice.version, d: fmtDate(mp.acknowledged_at) })}</div>
            : <div><Button kind="primary" busy={busy} onClick={() => void ack()}>{t('mp.ack')}</Button></div>}
        </>}
      </section>
      {mp?.notice && <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('mp.consents')}</h2>
        <p className="muted" style={{ margin: 0 }}>{t('mp.consent_hint')}</p>
        {CONSENT_PURPOSES.map((p) => {
          const c = mp.consents.find((x) => x.purpose === p);
          return (
            <div key={p} className="row" style={{ justifyContent: 'space-between', gap: 8, flexWrap: 'wrap' }}>
              <span>{t(`pc.${p}` as Key)}{c && <span className="sub num">{fmtDate(c.given_at)}</span>}</span>
              <div className="lang-switch" role="group" aria-label={t(`pc.${p}` as Key)}>
                <button type="button" aria-pressed={c?.given === true} disabled={busy} onClick={() => void consent(p, true)}>{t('mp.yes')}</button>
                <button type="button" aria-pressed={c?.given === false} disabled={busy} onClick={() => void consent(p, false)}>{t('mp.no')}</button>
              </div>
            </div>);
        })}
      </section>}
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('pv.title')}</h2>
        <p style={{ margin: 0 }}>{t('pv.hint')}</p>
        <p className="muted" style={{ margin: 0 }}>{t('pv.what')}</p>
        <div className="row"><Button kind="primary" busy={busy} onClick={() => void download()}>{t('pv.download')}</Button>
          <Button onClick={() => open('correction')}>{t('pv.correct')}</Button></div>
      </section>
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('mp.request')}</h2>
        <p className="muted" style={{ margin: 0 }}>{t('mp.request_hint', { n: mp?.dsr_days ?? 45 })}</p>
        <Select label={t('dr.kind')} value={req.kind} onChange={(e) => setReq({ ...req, kind: e.target.value as DsrKind })}>
          <option value="">{t('c.select')}</option>{DSR_KINDS.map((k) => <option key={k} value={k}>{t(`dk.${k}` as Key)}</option>)}
        </Select>
        <Textarea label={t('dr.details')} value={req.details} onChange={(e) => setReq({ ...req, details: e.target.value })} />
        <div><Button kind="primary" busy={busy} disabled={!req.kind || req.details.trim().length < 10} onClick={() => void submit()}>{t('c.save')}</Button></div>
        {mp && mp.requests.length > 0 && <>
          <b>{t('mp.my_requests')}</b>
          <ul className="plain">{mp.requests.map((r) => (
            <li key={r.id}><span className="num">{r.ref_no}</span> · {t(`dk.${r.kind}` as Key)} · <DsrBadge s={r.status} />
              <span className="sub">{t('dr.received')} {fmtDate(r.received_on)} · {t('dr.due')} {fmtDate(r.due_on)}{r.outcome ? ` · ${r.outcome}` : ''}</span></li>))}
          </ul></>}
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Request dialogs
// ---------------------------------------------------------------------------
function ProfileDialog({ open, p, onClose, onDone }: { open: boolean; p: Portal; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const e = p.employee!;
  const init = () => Object.fromEntries(SS_FIELDS.map((f) => [f, e[f] ?? ''])) as Record<SsField, string>;
  const [f, setF] = useState(init);
  const [reason, setReason] = useState('');
  useEffect(() => { if (open) { setF(init()); setReason(''); } }, [open]);
  const diff = changedFields(e, f);
  const submit = async () => {
    const r = await run(() => ssapi.requestChange({ kind: 'PROFILE', changes: diff, reason }));
    if (r) { push(t('me.change_sent')); onDone(); }
  };
  const inp = (k: SsField, extra: Record<string, unknown> = {}) => (
    <Input key={k} label={fieldLabel(t, k)} value={f[k]} onChange={(ev) => setF({ ...f, [k]: ev.target.value })} {...extra} />);
  return (
    <Modal open={open} title={t('me.edit_request')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!Object.keys(diff).length} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="form-grid">
          {inp('preferred_name')}
          {inp('mobile', { ltr: true, inputMode: 'tel', required: true })}
          {inp('alt_phone', { ltr: true, inputMode: 'tel' })}
          {inp('personal_email', { ltr: true, type: 'email' })}
          <Select label={fieldLabel(t, 'marital_status')} value={f.marital_status} onChange={(ev) => setF({ ...f, marital_status: ev.target.value })}>
            <option value="">{t('c.select')}</option>
            {['SINGLE', 'MARRIED', 'DIVORCED', 'WIDOWED'].map((m) => <option key={m} value={m}>{t(`ef.${m}` as Key)}</option>)}
          </Select>
          {inp('address_line')}
          {inp('city')}
          {inp('wilayat')}
          {inp('governorate')}
          <CountrySelect label={fieldLabel(t, 'address_country')} value={f.address_country} onChange={(v) => setF({ ...f, address_country: v ?? '' })} />
        </div>
        <Input label={t('me.change_why')} value={reason} maxLength={300} onChange={(ev) => setReason(ev.target.value)} />
        {!Object.keys(diff).length && <div className="muted">{t('me.no_change')}</div>}
      </div>
    </Modal>
  );
}

function ContactsDialog({ open, p, onClose, onDone }: { open: boolean; p: Portal; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const blank: Contact = { name: '', relationship: '', phone: '', alt_phone: '', address: '', is_next_of_kin: false };
  const [rows, setRows] = useState<Contact[]>([]);
  useEffect(() => { if (open) setRows((p.emergency_contacts ?? []).length ? (p.emergency_contacts ?? []).map((c) => ({ ...c })) : [{ ...blank }]); }, [open]);
  const ok = rows.length > 0 && rows.every((r) => r.name.trim() && r.relationship.trim() && r.phone.trim());
  const set = (i: number, patch: Partial<Contact>) => setRows(rows.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  const submit = async () => {
    const r = await run(() => ssapi.requestChange({ kind: 'EMERGENCY', contacts: rows as unknown as Record<string, unknown>[] }));
    if (r) { push(t('me.change_sent')); onDone(); }
  };
  return (
    <Modal open={open} title={t('me.contacts_request')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!ok} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <p className="muted" style={{ margin: 0 }}>{t('me.contacts_hint')}</p>
        {rows.map((r, i) => (
          <fieldset key={i} className="contact-box">
            <div className="form-grid">
              <Input label={t('c.name_en')} required value={r.name} onChange={(e) => set(i, { name: e.target.value })} />
              <Input label={t('ed.relationship')} required value={r.relationship} onChange={(e) => set(i, { relationship: e.target.value })} />
              <Input label={t('ed.phone')} required ltr inputMode="tel" value={r.phone} onChange={(e) => set(i, { phone: e.target.value })} />
              <Input label={t('ef.alt_phone')} ltr inputMode="tel" value={r.alt_phone ?? ''} onChange={(e) => set(i, { alt_phone: e.target.value })} />
            </div>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <Check label={t('ed.next_of_kin')} checked={!!r.is_next_of_kin} onChange={(v) => set(i, { is_next_of_kin: v })} />
              {rows.length > 1 && <Button small kind="danger" onClick={() => setRows(rows.filter((_, j) => j !== i))}>{t('me.remove_contact')}</Button>}
            </div>
          </fieldset>))}
        {rows.length < 5 && <div><Button small onClick={() => setRows([...rows, { ...blank }])}>{t('me.add_contact')}</Button></div>}
      </div>
    </Modal>
  );
}

function BankDialog({ open, p, onClose, onDone }: { open: boolean; p: Portal; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const init = () => ({ bank_name: '', branch: '', account_name: p.employee?.full_name_en ?? '', account_number: '', iban: '', swift_code: '' });
  const [f, setF] = useState(init);
  useEffect(() => { if (open) setF(init()); }, [open]);
  const ok = f.bank_name.trim() && f.account_name.trim() && f.account_number.replace(/\s/g, '').length >= 5;
  const submit = async () => {
    const r = await run(() => ssapi.requestChange({ kind: 'BANK', ...f }));
    if (r) { push(t('me.change_sent')); onDone(); }
  };
  return (
    <Modal open={open} title={t('me.bank_request')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!ok} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <p className="muted" style={{ margin: 0 }}>{t('me.bank_hint')}</p>
        <div className="form-grid">
          <Input label={t('bk.bank')} required value={f.bank_name} onChange={(e) => setF({ ...f, bank_name: e.target.value })} />
          <Input label={t('bk.branch')} value={f.branch} onChange={(e) => setF({ ...f, branch: e.target.value })} />
          <Input label={t('bk.holder')} required value={f.account_name} onChange={(e) => setF({ ...f, account_name: e.target.value })} />
          <Input label={t('bk.account')} required ltr value={f.account_number} onChange={(e) => setF({ ...f, account_number: e.target.value })} />
          <Input label={t('bk.iban')} ltr value={f.iban} onChange={(e) => setF({ ...f, iban: e.target.value.toUpperCase() })} />
          <Input label={t('bk.swift')} ltr value={f.swift_code} onChange={(e) => setF({ ...f, swift_code: e.target.value.toUpperCase() })} />
        </div>
      </div>
    </Modal>
  );
}

function CorrectionDialog({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const [field, setField] = useState('');
  const [reason, setReason] = useState('');
  useEffect(() => { if (open) { setField(''); setReason(''); } }, [open]);
  const fields: [string, Key][] = [['full_name_en', 'ef.full_name_en'], ['full_name_ar', 'ef.full_name_ar'], ['date_of_birth', 'ef.dob'], ['gender', 'ef.gender'],
    ['nationality', 'emp.nationality'], ['civil_number', 'ef.civil'], ['join_date', 'ef.join_date'], ['job', 'me.job'], ['other', 'c.details']];
  const submit = async () => {
    const r = await run(() => ssapi.requestChange({ kind: 'CORRECTION', field: field || null, reason }));
    if (r) { push(t('me.change_sent')); onDone(); }
  };
  return (
    <Modal open={open} title={t('me.correction')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={reason.trim().length < 10} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <p className="muted" style={{ margin: 0 }}>{t('me.correction_hint')}</p>
        <Select label={t('me.correction_field')} value={field} onChange={(e) => setField(e.target.value)}>
          <option value="">{t('c.select')}</option>
          {fields.map(([k, key]) => <option key={k} value={k}>{t(key)}</option>)}
        </Select>
        <Textarea label={t('me.correction_reason')} required value={reason} maxLength={1000} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Modal>
  );
}
