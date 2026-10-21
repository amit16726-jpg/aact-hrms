import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { ssapi, type ChangeReq, type Letter, type LetterLang, type LetterSettings } from '../../lib/api_ss';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { EmpLink } from '../../components/pay';
import { ChangeBadge, ChangeSummary, LetterBadge, LetterLine, LetterRequestDialog } from '../../components/ss';
import { fmtDate, fmtDateTime } from '../../lib/format';

type Tab = 'changes' | 'letters' | 'setup';

export default function RequestsPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const tabs: { id: Tab; label: string }[] = [
    { id: 'changes', label: t('rq.tab_changes') }, { id: 'letters', label: t('rq.tab_letters') },
    ...(can('LETTER_APPROVE') ? [{ id: 'setup' as Tab, label: t('rq.tab_setup') }] : [])];
  const tab = (tabs.some((x) => x.id === sp.get('tab')) ? sp.get('tab') : 'changes') as Tab;
  return (
    <div className="stack">
      <PageHead title={t('rq.title')} sub={t('rq.hint')} />
      <Tabs label={t('rq.title')} value={tab} onChange={(v) => setSp(v === 'changes' ? {} : { tab: v }, { replace: true })} tabs={tabs} />
      {tab === 'changes' && <Changes />}
      {tab === 'letters' && <Letters />}
      {tab === 'setup' && <Setup />}
    </div>
  );
}

function StatusFilter({ id, value, onChange, options, prefix }: { id: string; value: string; onChange: (v: string) => void; options: string[]; prefix: string }) {
  const { t } = useI18n();
  return (
    <div className="panel panel-pad row">
      <div className="field" style={{ minWidth: 220 }}><label htmlFor={id}>{t('c.status')}</label>
        <select id={id} className="select" value={value} onChange={(e) => onChange(e.target.value)}>
          <option value="OPEN">{t('rq.filter_open')}</option><option value="">{t('c.all')}</option>
          {options.map((s) => <option key={s} value={s}>{t(`${prefix}${s}` as Key)}</option>)}
        </select></div>
    </div>
  );
}

function Changes() {
  const { t } = useI18n();
  const [status, setStatus] = useState('OPEN');
  const { data, error, loading, reload } = useAsync(() => ssapi.listChanges(status === 'OPEN' ? 'PENDING' : status || null), [status]);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const decide = async (c: ChangeReq, approve: boolean) => {
    const needNote = !approve || c.kind === 'CORRECTION';
    const note = await confirm.ask({ title: `${t(approve ? 'rq.approve_title' : 'rq.reject_title')} — ${c.full_name_en}`,
      body: <div className="stack"><ChangeSummary c={c} />{approve && c.kind === 'BANK' && <div className="note">{t('rq.bank_note')}</div>}</div>,
      reason: needNote ? 'required' : 'optional', reasonLabel: approve && c.kind === 'CORRECTION' ? t('rq.correction_note') : t('ap.decision_note'),
      danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    if (await run(() => ssapi.decideChange(c.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'))) void reload();
  };
  return (
    <>
      <StatusFilter id="rq-st" value={status} onChange={setStatus} options={['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED']} prefix="rq.st_" />
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('rq.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('c.type')}</th><th>{t('rq.what')}</th><th>{t('rq.due')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((c) => (
              <tr key={c.id}>
                <td data-label={t('c.employee')}><EmpLink id={c.employee_id} no={c.employee_no} en={c.full_name_en} ar={c.full_name_ar} /></td>
                <td data-label={t('c.type')}><b>{t(`rq.k_${c.kind}` as Key)}</b><span className="sub">{fmtDateTime(c.requested_at)}</span>{c.reason && c.kind !== 'CORRECTION' && <span className="sub">{c.reason}</span>}</td>
                <td data-label={t('rq.what')}><ChangeSummary c={c} /></td>
                <td data-label={t('rq.due')} className={`num${c.overdue ? ' bad-text' : ''}`}>{fmtDate(c.due_date)}</td>
                <td data-label={t('c.status')}><ChangeBadge c={c} />{c.decided_at && <span className="sub">{t('rq.decided', { n: c.decided_by_name ?? '', d: fmtDate(c.decided_at) })}</span>}
                  {c.decision_note && <span className="sub">{c.decision_note}</span>}</td>
                <td className="r">{c.can_decide && <div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  <Button small kind="primary" busy={busy} onClick={() => void decide(c, true)}>{t('c.approve')}</Button>
                  <Button small kind="danger" busy={busy} onClick={() => void decide(c, false)}>{t('c.reject')}</Button></div>}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      {confirm.node}
    </>
  );
}

function Letters() {
  const { t } = useI18n();
  const { can } = useSession();
  const [status, setStatus] = useState('OPEN');
  const { data, error, loading, reload } = useAsync(async () => {
    const rows = await ssapi.listLetters(status === 'OPEN' ? null : status || null);
    return status === 'OPEN' ? rows.filter((l) => l.status === 'REQUESTED' || l.status === 'PREPARED') : rows;
  }, [status]);
  const [prep, setPrep] = useState<Letter | null>(null);
  const [newOpen, setNewOpen] = useState(false);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const approve = async (l: Letter) => {
    const note = await confirm.ask({ title: `${t('lt.approve_issue')} — ${t(`lt.${l.letter_type}` as Key)} — ${l.full_name_en}`,
      body: <Link to={`/letters/${l.id}`} target="_blank" rel="noreferrer">{t('lt.view')}</Link>, reason: 'optional', okLabel: t('lt.approve_issue') });
    if (note === null) return;
    if (await run(() => ssapi.decideLetter(l.id, true, note || null), t('lt.issued'))) void reload();
  };
  const reject = async (l: Letter) => {
    const note = await confirm.ask({ title: `${t('c.reject')} — ${t(`lt.${l.letter_type}` as Key)} — ${l.full_name_en}`, reason: 'required', danger: true, okLabel: t('c.reject') });
    if (note === null) return;
    if (await run(() => ssapi.decideLetter(l.id, false, note), t('ap.done_reject'))) void reload();
  };
  const revoke = async (l: Letter) => {
    const note = await confirm.ask({ title: `${t('lt.revoke_title')} — ${l.ref_no ?? ''}`, body: t('lt.revoke_hint'), reason: 'required', danger: true, okLabel: t('lt.revoke') });
    if (note === null) return;
    if (await run(() => ssapi.revokeLetter(l.id, note))) void reload();
  };
  const cancel = async (l: Letter) => {
    if ((await confirm.ask({ title: t('rq.cancel_q'), danger: true })) === null) return;
    if (await run(() => ssapi.cancelLetter(l.id))) void reload();
  };
  return (
    <>
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <StatusFilter id="lt-st" value={status} onChange={setStatus} options={['REQUESTED', 'PREPARED', 'ISSUED', 'REJECTED', 'CANCELLED']} prefix="lt.st_" />
        {can('LETTER_PREPARE') && <Button kind="primary" onClick={() => setNewOpen(true)}>{t('lt.new_hr')}</Button>}
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('lt.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('lt.type')}</th><th>{t('rq.requested')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((l) => (
              <tr key={l.id}>
                <td data-label={t('lt.type')}><LetterLine l={l} showEmployee /></td>
                <td data-label={t('rq.requested')}>{t('lt.requested_by', { n: l.requested_by_name ?? '' })}<span className="sub num">{fmtDateTime(l.requested_at)}</span>
                  {l.prepared_by_name && <span className="sub">{t('lt.prepared_by', { n: l.prepared_by_name })}</span>}
                  {l.approved_by_name && l.status === 'ISSUED' && <span className="sub">{t('lt.approved_by', { n: l.approved_by_name })}</span>}</td>
                <td data-label={t('c.status')}><LetterBadge l={l} />{l.decision_note && <span className="sub">{l.decision_note}</span>}{l.revoke_reason && <span className="sub">{l.revoke_reason}</span>}</td>
                <td className="r"><div className="row" style={{ gap: 4, justifyContent: 'flex-end', flexWrap: 'wrap' }}>
                  <Link className="btn btn-sm" to={`/letters/${l.id}`}>{t('lt.view')}</Link>
                  {l.can_prepare && <Button small kind="primary" onClick={() => setPrep(l)}>{t('lt.prepare')}</Button>}
                  {l.can_approve && <Button small kind="primary" busy={busy} onClick={() => void approve(l)}>{t('lt.approve_issue')}</Button>}
                  {(l.can_prepare || l.can_approve) && <Button small kind="danger" busy={busy} onClick={() => void reject(l)}>{t('c.reject')}</Button>}
                  {l.can_cancel && !l.can_prepare && !l.can_approve && <Button small busy={busy} onClick={() => void cancel(l)}>{t('lt.cancel')}</Button>}
                  {l.can_revoke && <Button small kind="danger" busy={busy} onClick={() => void revoke(l)}>{t('lt.revoke')}</Button>}
                </div></td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <PrepareDialog l={prep} onClose={() => setPrep(null)} onDone={() => { setPrep(null); void reload(); }} />
      <LetterRequestDialog hr open={newOpen} onClose={() => setNewOpen(false)} onDone={() => void reload()} />
      {confirm.node}
    </>
  );
}

function PrepareDialog({ l, onClose, onDone }: { l: Letter | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ language: 'BOTH' as LetterLang, addressee: '', purpose: '', include_salary: false, destination: '', activity: '', from_date: '', to_date: '' });
  useEffect(() => {
    if (l) setF({ language: l.language, addressee: l.addressee ?? '', purpose: l.purpose ?? '', include_salary: l.include_salary,
      destination: l.details?.destination ?? '', activity: l.details?.activity ?? '', from_date: l.details?.from_date ?? '', to_date: l.details?.to_date ?? '' });
  }, [l]);
  const submit = async () => {
    if (!l) return;
    const details = l.letter_type === 'NOC' ? { destination: f.destination.trim() || undefined, activity: f.activity.trim() || undefined,
      from_date: f.from_date || undefined, to_date: f.to_date || undefined } : l.details;
    if (await run(() => ssapi.prepareLetter(l.id, { language: f.language, addressee: f.addressee, purpose: f.purpose, include_salary: f.include_salary, details }), t('lt.prepared'))) onDone();
  };
  return (
    <Modal open={!!l} title={`${t('lt.prepare_title')} — ${l ? t(`lt.${l.letter_type}` as Key) : ''} — ${l?.full_name_en ?? ''}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void submit()}>{t('lt.prepare')}</Button></>}>
      <div className="form-grid">
        <Select label={t('lt.language')} value={f.language} onChange={(e) => setF({ ...f, language: e.target.value as LetterLang })}>
          {(['BOTH', 'EN', 'AR'] as const).map((x) => <option key={x} value={x}>{t(`lt.l_${x}` as Key)}</option>)}
        </Select>
        <Input label={t('lt.addressee')} value={f.addressee} maxLength={200} onChange={(e) => setF({ ...f, addressee: e.target.value })} />
        <Input className="span-2" label={t('lt.purpose')} value={f.purpose} maxLength={200} onChange={(e) => setF({ ...f, purpose: e.target.value })} />
        {l?.letter_type === 'NOC' && <>
          <Input label={t('lt.destination')} value={f.destination} onChange={(e) => setF({ ...f, destination: e.target.value })} />
          <Input label={t('lt.activity')} value={f.activity} onChange={(e) => setF({ ...f, activity: e.target.value })} />
          <Input label={t('lt.from')} type="date" ltr value={f.from_date} onChange={(e) => setF({ ...f, from_date: e.target.value })} />
          <Input label={t('lt.to')} type="date" ltr value={f.to_date} onChange={(e) => setF({ ...f, to_date: e.target.value })} />
        </>}
        {l?.letter_type === 'EMPLOYMENT' && <div className="span-2"><Check label={t('lt.include_salary_hr')} checked={f.include_salary} onChange={(v) => setF({ ...f, include_salary: v })} /></div>}
      </div>
    </Modal>
  );
}

function Setup() {
  const { t } = useI18n();
  const { data, error, loading, reload } = useAsync(() => ssapi.letterSettings(), []);
  const [f, setF] = useState<LetterSettings | null>(null);
  const { busy, run } = useAction();
  useEffect(() => { if (data) setF({ ...data }); }, [data]);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!f) return null;
  const field = (k: keyof LetterSettings, key: Key, ltr = false) => (
    <Input key={k} label={t(key)} ltr={ltr} value={f[k] ?? ''} maxLength={300} onChange={(e) => setF({ ...f, [k]: e.target.value })} />);
  return (
    <section className="panel panel-pad stack" style={{ maxWidth: 760 }}>
      <h2 style={{ margin: 0 }}>{t('ls.title')}</h2>
      <p className="muted" style={{ margin: 0 }}>{t('ls.hint')}</p>
      <div className="form-grid">
        {field('signatory_en', 'ls.signatory_en')}{field('signatory_ar', 'ls.signatory_ar')}
        {field('signatory_name_en', 'ls.name_en')}{field('signatory_name_ar', 'ls.name_ar')}
        {field('footer_en', 'ls.footer_en')}{field('footer_ar', 'ls.footer_ar')}
        <Input className="span-2" label={t('ls.verify_url')} hint={t('ls.verify_hint')} ltr value={f.verify_base_url} onChange={(e) => setF({ ...f, verify_base_url: e.target.value })} />
      </div>
      <div className="row row-end"><Button kind="primary" busy={busy} onClick={async () => { const r = await run(() => ssapi.saveLetterSettings({ ...f }), t('c.saved')); if (r) setF({ ...r }); }}>{t('c.save')}</Button></div>
    </section>
  );
}
