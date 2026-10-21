import { useEffect, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { recapi, type Candidate, type ChecklistStep, type NatRule, type RecSettings, type Requisition } from '../../lib/api_rec';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync, useToast } from '../../components/ui';
import { CountrySelect, EmployeePicker, MasterSelect } from '../../components/pickers';
import { EntitySelect, useEntity } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { ReqBadgeRec, StageBadge, Stars } from '../../components/rec';
import { fmtDate, fmtDateTime } from '../../lib/format';

type Tab = 'reqs' | 'candidates' | 'interviews' | 'onboarding' | 'settings';

export default function RecruitmentPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const full = can('REC_READ');
  const tabs: { id: Tab; label: string }[] = [
    { id: 'reqs', label: t('rc.tab_reqs') },
    ...(full ? [{ id: 'candidates' as Tab, label: t('rc.tab_candidates') }] : []),
    { id: 'interviews', label: t('rc.tab_interviews') },
    ...(full ? [{ id: 'onboarding' as Tab, label: t('rc.tab_onboarding') }, { id: 'settings' as Tab, label: t('rc.tab_settings') }] : [])];
  const tab = (tabs.some((x) => x.id === sp.get('tab')) ? sp.get('tab') : 'reqs') as Tab;
  return (
    <div className="stack">
      <PageHead title={t('rc.title')} sub={t('rc.hint')} />
      <Tabs label={t('rc.title')} value={tab} onChange={(v) => setSp(v === 'reqs' ? {} : { tab: v }, { replace: true })} tabs={tabs} />
      {tab === 'reqs' && <Requisitions />}
      {tab === 'candidates' && <Candidates />}
      {tab === 'interviews' && <Interviews />}
      {tab === 'onboarding' && <Onboarding />}
      {tab === 'settings' && <Settings />}
    </div>
  );
}

// ---------------------------------------------------------------------------
function Requisitions() {
  const { t, L } = useI18n();
  const [status, setStatus] = useState('OPEN');
  const [open, setOpen] = useState(false);
  const nav = useNavigate();
  const { data, error, loading, reload } = useAsync(() => recapi.listRequisitions({ status: status || null }), [status]);
  return (
    <>
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div className="panel panel-pad row">
          <div className="field" style={{ minWidth: 220 }}><label htmlFor="rq-st">{t('c.status')}</label>
            <select id="rq-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="OPEN">{t('rq2.filter_open')}</option><option value="">{t('c.all')}</option>
              {(['PENDING', 'APPROVED', 'ON_HOLD', 'FILLED', 'REJECTED', 'CANCELLED'] as const).map((s) => <option key={s} value={s}>{t(`rq2.st_${s}` as Key)}</option>)}
            </select></div>
        </div>
        <Button kind="primary" onClick={() => setOpen(true)}>{t('rq2.new')}</Button>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('rq2.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('rq2.job')}</th><th>{t('c.department')}</th><th className="r">{t('rq2.positions')}</th><th>{t('rq2.nat_rule')}</th><th>{t('c.status')}</th></tr></thead>
            <tbody>{data.map((r) => (
              <tr key={r.id}>
                <td data-label={t('rq2.job')}><Link to={`/recruitment/req/${r.id}`}>{L(r.job_en, r.job_ar)}</Link><span className="sub num">{r.ref_no} · {fmtDate(r.requested_at)}</span></td>
                <td data-label={t('c.department')}>{L(r.department_en, r.department_ar)}</td>
                <td data-label={t('rq2.positions')} className="r num">{r.positions}<span className="sub">{t('rq2.filled_of', { h: r.hired, n: r.positions })}{r.in_pipeline ? ` · ${t('rq2.pipeline', { n: r.in_pipeline })}` : ''}</span></td>
                <td data-label={t('rq2.nat_rule')}>{r.nationality_rule === 'ANY' ? <span className="muted">{t('rq2.n_ANY')}</span> : <Badge tone="info">{t(`rq2.n_${r.nationality_rule}` as Key)}</Badge>}</td>
                <td data-label={t('c.status')}><ReqBadgeRec s={r.status} /><span className="sub">{r.requested_by_name}</span></td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <RequisitionDialog open={open} onClose={() => setOpen(false)} onDone={(id) => nav(`/recruitment/req/${id}`)} />
    </>
  );
}

export function RequisitionDialog({ open, onClose, onDone, edit }: { open: boolean; onClose: () => void; onDone: (id: string) => void; edit?: Requisition | null }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const [entity, setEntity] = useEntity();
  const init = () => ({ department_id: edit?.department_id ?? null as string | null, job_title_id: edit?.job_title_id ?? null as string | null,
    grade_id: edit?.grade_id ?? null as string | null, category_id: edit?.category_id ?? null as string | null, location_id: edit?.location_id ?? null as string | null,
    positions: String(edit?.positions ?? 1), reason: edit?.reason ?? 'NEW', replaces_employee_id: edit?.replaces_employee_id ?? null as string | null,
    employment_type: edit?.employment_type ?? 'FULL_TIME', nationality_rule: (edit?.nationality_rule ?? 'ANY') as NatRule,
    salary_min: edit?.salary_min != null ? String(edit.salary_min) : '', salary_max: edit?.salary_max != null ? String(edit.salary_max) : '',
    target_date: edit?.target_date ?? '', justification: edit?.justification ?? '' });
  const [f, setF] = useState(init);
  useEffect(() => { if (open) { setF(init()); if (edit) setEntity(edit.entity_id); } }, [open]);
  const ent = edit?.entity_id ?? entity;
  const ok = f.department_id && f.job_title_id && f.justification.trim().length >= 10 && Number(f.positions) >= 1 && (f.reason !== 'REPLACEMENT' || f.replaces_employee_id);
  const submit = async () => {
    const r = await run(() => recapi.saveRequisition({ ...f, id: edit?.id ?? null, positions: Number(f.positions) }));
    if (r) { push(t('rq2.saved')); onClose(); onDone(r.id); }
  };
  return (
    <Modal open={open} title={edit ? t('rq2.edit') : t('rq2.new')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!ok} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {!edit && <EntitySelect value={entity} onChange={(v) => { setEntity(v); setF({ ...f, department_id: null, job_title_id: null, grade_id: null, category_id: null, location_id: null }); }} />}
        <div className="form-grid">
          <MasterSelect kind="department" entityId={ent} label={t('c.department')} required value={f.department_id} onChange={(v) => setF({ ...f, department_id: v })} />
          <MasterSelect kind="job_title" entityId={ent} label={t('rq2.job')} required value={f.job_title_id} onChange={(v) => setF({ ...f, job_title_id: v })} />
          <MasterSelect kind="grade" entityId={ent} label={t('ef.grade')} value={f.grade_id} onChange={(v) => setF({ ...f, grade_id: v })} />
          <MasterSelect kind="category" entityId={ent} label={t('ef.category')} value={f.category_id} onChange={(v) => setF({ ...f, category_id: v })} />
          <MasterSelect kind="location" entityId={ent} label={t('ef.location')} value={f.location_id} onChange={(v) => setF({ ...f, location_id: v })} />
          <Input label={t('rq2.positions')} type="number" min={1} max={200} value={f.positions} onChange={(e) => setF({ ...f, positions: e.target.value })} />
          <Select label={t('rq2.reason')} value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value as typeof f.reason })}>
            {(['NEW', 'REPLACEMENT', 'TEMPORARY'] as const).map((x) => <option key={x} value={x}>{t(`rq2.r_${x}` as Key)}</option>)}
          </Select>
          {f.reason === 'REPLACEMENT' ? <EmployeePicker label={t('rq2.replaces')} value={f.replaces_employee_id} onChange={(v) => setF({ ...f, replaces_employee_id: v })} />
            : <Select label={t('rq2.employment_type')} value={f.employment_type} onChange={(e) => setF({ ...f, employment_type: e.target.value })}>
                {['FULL_TIME', 'PART_TIME', 'TEMPORARY', 'TRAINEE'].map((x) => <option key={x} value={x}>{t(`ef.${x}` as Key)}</option>)}
              </Select>}
          <Select label={t('rq2.nat_rule')} value={f.nationality_rule} onChange={(e) => setF({ ...f, nationality_rule: e.target.value as NatRule })}>
            {(['ANY', 'OMANI_PREFERRED', 'OMANI_ONLY'] as const).map((x) => <option key={x} value={x}>{t(`rq2.n_${x}` as Key)}</option>)}
          </Select>
          <Input label={t('rq2.target_date')} type="date" ltr value={f.target_date} onChange={(e) => setF({ ...f, target_date: e.target.value })} />
          <Input label={`${t('rq2.salary_range')} — ${t('rq2.salary_min')}`} ltr inputMode="decimal" value={f.salary_min} onChange={(e) => setF({ ...f, salary_min: e.target.value })} />
          <Input label={`${t('rq2.salary_range')} — ${t('rq2.salary_max')}`} ltr inputMode="decimal" value={f.salary_max} onChange={(e) => setF({ ...f, salary_max: e.target.value })} />
        </div>
        <Textarea label={t('rq2.justification')} required value={f.justification} maxLength={1000} onChange={(e) => setF({ ...f, justification: e.target.value })} />
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function Candidates() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const [q, setQ] = useState('');
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const { data, error, loading, reload } = useAsync(() => recapi.listCandidates(query), [query]);
  return (
    <>
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <form className="panel panel-pad row" onSubmit={(e) => { e.preventDefault(); setQuery(q.trim()); }}>
          <Input label={t('c.search')} placeholder={t('cd.search_ph')} value={q} onChange={(e) => setQ(e.target.value)} />
          <Button type="submit">{t('c.search')}</Button>
        </form>
        {can('REC_WRITE') && <Button kind="primary" onClick={() => setOpen(true)}>{t('cd.new')}</Button>}
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('cd.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('cd.name_en')}</th><th>{t('cd.nationality')}</th><th>{t('cd.experience')}</th><th>{t('cd.source')}</th><th>{t('c.status')}</th></tr></thead>
            <tbody>{data.map((c) => (
              <tr key={c.id}>
                <td data-label={t('cd.name_en')}><b>{L(c.full_name_en, c.full_name_ar)}</b><span className="sub ltr-inline">{[c.email, c.phone].filter(Boolean).join(' · ')}</span></td>
                <td data-label={t('cd.nationality')}>{L(c.nationality_en, c.nationality_ar)}{!c.in_oman && <span className="sub">{t('cd.abroad')}</span>}</td>
                <td data-label={t('cd.experience')} className="num">{c.experience_years ?? '—'}</td>
                <td data-label={t('cd.source')}>{t(`cd.s_${c.source}` as Key)}</td>
                <td data-label={t('c.status')}>{c.employee_id ? <Link to={`/employees/${c.employee_id}`}>{t('cd.hired_as')}</Link>
                  : <span>{t('cd.applications', { n: typeof c.applications === 'number' ? c.applications : 0 })}</span>}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <CandidateDialog open={open} onClose={() => setOpen(false)} onSaved={() => void reload()} />
    </>
  );
}

export type CandidateForm = { full_name_en: string; full_name_ar: string; nationality: string; gender: string; date_of_birth: string; email: string; phone: string;
  civil_number: string; passport_no: string; in_oman: boolean; current_employer: string; experience_years: string; qualification: string; source: string; notes: string };
export const blankCandidate = (): CandidateForm => ({ full_name_en: '', full_name_ar: '', nationality: '', gender: '', date_of_birth: '', email: '', phone: '',
  civil_number: '', passport_no: '', in_oman: false, current_employer: '', experience_years: '', qualification: '', source: 'OTHER', notes: '' });

export function CandidateFields({ f, setF }: { f: CandidateForm; setF: (f: CandidateForm) => void }) {
  const { t } = useI18n();
  return (
    <div className="form-grid">
      <Input label={t('cd.name_en')} required value={f.full_name_en} onChange={(e) => setF({ ...f, full_name_en: e.target.value })} />
      <Input label={t('cd.name_ar')} value={f.full_name_ar} onChange={(e) => setF({ ...f, full_name_ar: e.target.value })} />
      <CountrySelect label={t('cd.nationality')} nationality required value={f.nationality} onChange={(v) => setF({ ...f, nationality: v ?? '', in_oman: v === 'OM' ? true : f.in_oman })} />
      <Select label={t('cd.gender')} value={f.gender} onChange={(e) => setF({ ...f, gender: e.target.value })}>
        <option value="">{t('c.select')}</option><option value="M">{t('ef.male')}</option><option value="F">{t('ef.female')}</option>
      </Select>
      <Input label={t('cd.dob')} type="date" ltr value={f.date_of_birth} onChange={(e) => setF({ ...f, date_of_birth: e.target.value })} />
      <Input label={t('cd.email')} type="email" ltr value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} />
      <Input label={t('cd.phone')} ltr inputMode="tel" value={f.phone} onChange={(e) => setF({ ...f, phone: e.target.value })} />
      <Input label={t('cd.civil')} ltr value={f.civil_number} onChange={(e) => setF({ ...f, civil_number: e.target.value })} />
      <Input label={t('cd.passport')} ltr value={f.passport_no} onChange={(e) => setF({ ...f, passport_no: e.target.value })} />
      <Input label={t('cd.employer')} value={f.current_employer} onChange={(e) => setF({ ...f, current_employer: e.target.value })} />
      <Input label={t('cd.experience')} ltr inputMode="decimal" value={f.experience_years} onChange={(e) => setF({ ...f, experience_years: e.target.value })} />
      <Input label={t('cd.qualification')} value={f.qualification} onChange={(e) => setF({ ...f, qualification: e.target.value })} />
      <Select label={t('cd.source')} value={f.source} onChange={(e) => setF({ ...f, source: e.target.value })}>
        {['REFERRAL', 'AGENCY', 'WEBSITE', 'WALK_IN', 'INTERNAL', 'MOL_PORTAL', 'OTHER'].map((s) => <option key={s} value={s}>{t(`cd.s_${s}` as Key)}</option>)}
      </Select>
      <div className="field" style={{ alignSelf: 'end' }}><Check label={t('cd.in_oman')} checked={f.in_oman} disabled={f.nationality === 'OM'} onChange={(v) => setF({ ...f, in_oman: v })} /></div>
      <Textarea className="span-2" label={t('cd.notes')} value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} />
    </div>
  );
}

export const candidateOk = (f: CandidateForm) => f.full_name_en.trim().length > 1 && !!f.nationality;

function CandidateDialog({ open, onClose, onSaved }: { open: boolean; onClose: () => void; onSaved: (c: Candidate) => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const [f, setF] = useState(blankCandidate);
  useEffect(() => { if (open) setF(blankCandidate()); }, [open]);
  const submit = async () => {
    const r = await run(() => recapi.saveCandidate({ ...f }));
    if (r) { push(t('cd.added')); onSaved(r); onClose(); }
  };
  return (
    <Modal open={open} title={t('cd.new')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!candidateOk(f)} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <CandidateFields f={f} setF={setF} />
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function Interviews() {
  const { t, L } = useI18n();
  const { data, error, loading, reload } = useAsync(() => recapi.myInterviews(), []);
  return (
    <div className="panel">
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('iv.none')}</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('iv.when')}</th><th>{t('iv.candidate')}</th><th>{t('iv.interviewer')}</th><th>{t('c.status')}</th><th /></tr></thead>
          <tbody>{data.map((i) => (
            <tr key={i.id}>
              <td data-label={t('iv.when')} className="num">{fmtDateTime(i.scheduled_at)}<span className="sub">{t(`iv.m_${i.mode}` as Key)}{i.location ? ` · ${i.location}` : ''}</span></td>
              <td data-label={t('iv.candidate')}><b>{L(i.full_name_en ?? '', i.full_name_ar)}</b><span className="sub">{L(i.job_en ?? '', i.job_ar)} · <span className="num">{i.requisition_ref}</span></span></td>
              <td data-label={t('iv.interviewer')}>{i.interviewer_name}</td>
              <td data-label={t('c.status')}>{i.status === 'DONE' ? <Stars n={i.rating} /> : <Badge tone={i.status === 'SCHEDULED' ? (new Date(i.scheduled_at) < new Date() ? 'bad' : 'warn') : undefined}>{t(`iv.st_${i.status}` as Key)}</Badge>}</td>
              <td className="r"><Link className={`btn btn-sm${i.can_record ? ' btn-primary' : ''}`} to={`/recruitment/app/${i.application_id}`}>{i.can_record ? t('iv.record') : t('ap2.open_full')}</Link></td>
            </tr>))}
          </tbody></table></div>)}
    </div>
  );
}

// ---------------------------------------------------------------------------
function Onboarding() {
  const { t, L } = useI18n();
  const [all, setAll] = useState(false);
  const { data, error, loading, reload } = useAsync(() => recapi.listOnboarding(!all), [all]);
  return (
    <>
      <div className="panel panel-pad"><Check label={t('ob.show_all')} checked={all} onChange={setAll} /></div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('ob.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('iv.candidate')}</th><th>{t('of.start')}</th><th>{t('ob.title')}</th><th>{t('ob.next')}</th></tr></thead>
            <tbody>{data.map((r) => (
              <tr key={r.application_id}>
                <td data-label={t('iv.candidate')}><Link to={`/recruitment/app/${r.application_id}`}>{L(r.full_name_en, r.full_name_ar)}</Link><span className="sub">{L(r.job_en, r.job_ar)} · <StageBadge s={r.stage} /></span></td>
                <td data-label={t('of.start')} className="num">{fmtDate(r.start_date)}</td>
                <td data-label={t('ob.title')}><progress max={r.total} value={r.done} aria-label={t('ob.progress', { d: r.done, t: r.total })} />
                  <span className="sub">{t('ob.progress', { d: r.done, t: r.total })}{r.overdue ? <> · <span className="bad-text">{t('ob.overdue', { n: r.overdue })}</span></> : null}</span></td>
                <td data-label={t('ob.next')}>{r.next ? <>{L(r.next.title_en, r.next.title_ar)}<span className="sub num">{fmtDate(r.next.due_date)}</span></> : '—'}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------
function Settings() {
  const { t } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload } = useAsync(() => recapi.settings(), []);
  const [f, setF] = useState<RecSettings | null>(null);
  const { busy, run } = useAction();
  useEffect(() => { if (data) setF(JSON.parse(JSON.stringify(data)) as RecSettings); }, [data]);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!f) return null;
  const edit = can('REC_APPROVE');
  const setStep = (k: keyof RecSettings['onboarding'], i: number, patch: Partial<ChecklistStep>) =>
    setF({ ...f, onboarding: { ...f.onboarding, [k]: f.onboarding[k].map((s, j) => (j === i ? { ...s, ...patch } : s)) } });
  const save = async () => {
    const r = await run(() => recapi.saveSettings({ probation_monthly_max_months: f.probation_monthly_max_months, probation_other_max_months: f.probation_other_max_months,
      probation_reminder_days: f.probation_reminder_days, onboarding: f.onboarding as unknown as Record<string, unknown> }), t('c.saved'));
    if (r) setF(JSON.parse(JSON.stringify(r)) as RecSettings);
  };
  return (
    <div className="stack">
      <section className="panel panel-pad stack" style={{ maxWidth: 760 }}>
        <div className="row" style={{ justifyContent: 'space-between' }}><h2 style={{ margin: 0 }}>{t('rs.probation')}</h2>
          {edit && <Button kind="primary" busy={busy} onClick={() => void save()}>{t('c.save')}</Button>}</div>
        <div className="form-grid">
          <Input label={t('rs.monthly')} type="number" min={0} max={3} disabled={!edit} value={String(f.probation_monthly_max_months)} onChange={(e) => setF({ ...f, probation_monthly_max_months: Number(e.target.value) })} />
          <Input label={t('rs.other')} type="number" min={0} max={2} disabled={!edit} value={String(f.probation_other_max_months)} onChange={(e) => setF({ ...f, probation_other_max_months: Number(e.target.value) })} />
          <Input label={t('rs.reminder')} type="number" min={1} max={60} disabled={!edit} value={String(f.probation_reminder_days)} onChange={(e) => setF({ ...f, probation_reminder_days: Number(e.target.value) })} />
        </div>
        <div className="muted">{t('rs.basis')}: {f.probation_legal_basis}</div>
      </section>
      {(['EXPAT_ABROAD', 'EXPAT_IN_OMAN', 'OMANI'] as const).map((k) => (
        <section key={k} className="panel">
          <div className="panel-head"><h2>{t('rs.checklists')} — {t(`rs.k_${k}` as Key)}</h2>
            {edit && <Button small onClick={() => setF({ ...f, onboarding: { ...f.onboarding, [k]: [...f.onboarding[k], { code: '', en: '', ar: '', days: 0 }] } })}>{t('rs.add_step')}</Button>}</div>
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('rs.step_code')}</th><th>{t('rs.step_en')}</th><th>{t('rs.step_ar')}</th><th className="r">{t('rs.step_days')}</th><th /></tr></thead>
            <tbody>{f.onboarding[k].map((s, i) => (
              <tr key={i}>
                <td data-label={t('rs.step_code')}><input className="input ltr" aria-label={t('rs.step_code')} disabled={!edit} value={s.code} style={{ maxWidth: 170 }}
                  onChange={(e) => setStep(k, i, { code: e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, '') })} /></td>
                <td data-label={t('rs.step_en')}><input className="input" aria-label={t('rs.step_en')} disabled={!edit} value={s.en} onChange={(e) => setStep(k, i, { en: e.target.value })} /></td>
                <td data-label={t('rs.step_ar')}><input className="input" dir="rtl" aria-label={t('rs.step_ar')} disabled={!edit} value={s.ar} onChange={(e) => setStep(k, i, { ar: e.target.value })} /></td>
                <td data-label={t('rs.step_days')} className="r"><input className="input ltr" type="number" aria-label={t('rs.step_days')} disabled={!edit} value={s.days} style={{ maxWidth: 90 }}
                  onChange={(e) => setStep(k, i, { days: Number(e.target.value) })} /></td>
                <td className="r">{edit && <Button small kind="danger" onClick={() => setF({ ...f, onboarding: { ...f.onboarding, [k]: f.onboarding[k].filter((_, j) => j !== i) } })}>{t('rs.remove')}</Button>}</td>
              </tr>))}
            </tbody></table></div>
        </section>))}
    </div>
  );
}
