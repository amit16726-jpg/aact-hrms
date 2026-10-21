import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { COURSE_CATEGORIES, addMonthsIso, wfapi, type Course, type CourseCategory } from '../../lib/api_wf';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, DaysLeft, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { EmpCell } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { MultiEmployeePicker } from '../../components/wf';
import { OMR } from '../../components/pay';
import { fmtDate, todayMuscat } from '../../lib/format';

type Tab = 'records' | 'expiring' | 'gaps' | 'courses';

export default function TrainingPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const hr = can('TRAIN_WRITE');
  const tabs: { id: Tab; label: string }[] = [{ id: 'records', label: t('tr.tab_records') },
    ...(hr ? [{ id: 'expiring' as Tab, label: t('tr.tab_expiring') }, { id: 'gaps' as Tab, label: t('tr.tab_gaps') }, { id: 'courses' as Tab, label: t('tr.tab_courses') }] : [])];
  const tab = (tabs.some((x) => x.id === sp.get('tab')) ? sp.get('tab') : 'records') as Tab;
  return (
    <div className="stack">
      <PageHead title={t('tr.title')} sub={t('tr.hint')} />
      {tabs.length > 1 && <Tabs label={t('tr.title')} value={tab} onChange={(v) => setSp(v === 'records' ? {} : { tab: v }, { replace: true })} tabs={tabs} />}
      {(tab === 'records' || tab === 'expiring') && <Records expiring={tab === 'expiring'} />}
      {tab === 'gaps' && <Gaps />}
      {tab === 'courses' && <Courses />}
    </div>
  );
}

function Records({ expiring }: { expiring: boolean }) {
  const { t, L } = useI18n();
  const { can } = useSession();
  const hr = can('TRAIN_WRITE');
  const courses = useAsync(() => wfapi.listCourses(), []);
  const [course, setCourse] = useState('');
  const { data, error, loading, reload } = useAsync(() => wfapi.listTraining({ course_id: course || null, expiring_days: expiring ? 60 : null }), [course, expiring]);
  const [rec, setRec] = useState(false);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const cancel = async (id: string) => {
    if ((await confirm.ask({ title: t('tr.cancel_q'), danger: true })) === null) return;
    if (await run(() => wfapi.cancelTraining(id), t('c.saved'))) void reload();
  };
  const rows = expiring ? (data ?? []).filter((r) => !r.superseded) : data;
  return (
    <>
      <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}>
        <div className="panel panel-pad row">
          <div className="field" style={{ minWidth: 240 }}><label htmlFor="tr-c">{t('tr.course')}</label>
            <select id="tr-c" className="select" value={course} onChange={(e) => setCourse(e.target.value)}>
              <option value="">{t('c.all')}</option>
              {(courses.data ?? []).map((c) => <option key={c.id} value={c.id}>{c.code} — {L(c.name_en, c.name_ar)}</option>)}
            </select></div>
        </div>
        {hr && <Button kind="primary" onClick={() => setRec(true)}>{t('tr.record')}</Button>}
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !rows?.length ? <Empty>{t('tr.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr>{hr && <th>{t('c.employee')}</th>}<th>{t('tr.course')}</th><th>{t('tr.status')}</th><th>{t('tr.completed_on')}</th><th>{t('tr.expires_on')}</th><th>{t('tr.certificate')}</th>{hr && <th className="r">{t('tr.cost')}</th>}{hr && <th />}</tr></thead>
            <tbody>{rows.map((r) => (
              <tr key={r.id}>
                {hr && <td data-label={t('c.employee')}><EmpCell r={r} /></td>}
                <td data-label={t('tr.course')}>{L(r.course_en, r.course_ar)}<span className="sub">{r.course_code} · {t(`tr.c_${r.category}` as Key)}{r.mandatory ? ` · ${t('tr.mandatory')}` : ''}</span></td>
                <td data-label={t('tr.status')}><Badge tone={r.status === 'COMPLETED' ? 'ok' : 'info'}>{t(`tr.st_${r.status}` as Key)}</Badge>
                  {r.status === 'PLANNED' && r.planned_on && <span className="sub num">{fmtDate(r.planned_on)}</span>}</td>
                <td data-label={t('tr.completed_on')} className="num">{fmtDate(r.completed_on)}</td>
                <td data-label={t('tr.expires_on')}>{r.expires_on ? <><span className="num">{fmtDate(r.expires_on)}</span>
                  <span className="sub">{r.superseded ? <Badge>{t('tr.superseded')}</Badge> : <DaysLeft days={r.days_left} />}</span></> : <span className="muted">{t('tr.validity_none')}</span>}</td>
                <td data-label={t('tr.certificate')} className="num">{r.certificate_no ?? '—'}{r.score && <span className="sub">{r.score}</span>}</td>
                {hr && <td data-label={t('tr.cost')} className="r num">{r.cost != null ? OMR(r.cost) : '—'}</td>}
                {hr && <td className="r"><Button small kind="ghost" busy={busy} onClick={() => void cancel(r.id)}>{t('c.remove')}</Button></td>}
              </tr>))}
            </tbody></table></div>)}
      </div>
      <RecordDialog open={rec} courses={courses.data ?? []} onClose={() => setRec(false)} onDone={() => { setRec(false); void reload(); }} />
      {confirm.node}
    </>
  );
}

function RecordDialog({ open, courses, onClose, onDone }: { open: boolean; courses: Course[]; onClose: () => void; onDone: () => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const blank = () => ({ course_id: '', status: 'COMPLETED', planned_on: '', completed_on: todayMuscat(), expires_on: '', certificate_no: '', score: '', cost: '', notes: '' });
  const [f, setF] = useState(blank);
  const [emps, setEmps] = useState<{ id: string; label: string }[]>([]);
  useEffect(() => { if (open) { setF(blank()); setEmps([]); } }, [open]);
  const c = courses.find((x) => x.id === f.course_id);
  const autoExp = c?.validity_months && f.completed_on ? addMonthsIso(f.completed_on, c.validity_months) : '';
  const done = f.status === 'COMPLETED';
  const submit = async () => {
    const r = await run(() => wfapi.saveTraining({ course_id: f.course_id, status: f.status, employee_ids: emps.map((e) => e.id), planned_on: f.planned_on || null,
      completed_on: done ? f.completed_on : null, expires_on: done ? f.expires_on || null : null, certificate_no: f.certificate_no || null, score: f.score || null,
      cost: f.cost || null, notes: f.notes || null }));
    if (r) onDone();
  };
  return (
    <Modal open={open} title={t('tr.record')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!f.course_id || emps.length === 0 || (done && !f.completed_on)} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="grid-2">
          <Select label={t('tr.course')} required value={f.course_id} onChange={(e) => setF({ ...f, course_id: e.target.value })}>
            <option value="">{t('c.select')}</option>
            {courses.filter((x) => x.is_active).map((x) => <option key={x.id} value={x.id}>{x.code} — {L(x.name_en, x.name_ar)}</option>)}
          </Select>
          <Select label={t('tr.status')} value={f.status} onChange={(e) => setF({ ...f, status: e.target.value })}>
            <option value="COMPLETED">{t('tr.st_COMPLETED')}</option><option value="PLANNED">{t('tr.st_PLANNED')}</option>
          </Select>
        </div>
        <MultiEmployeePicker label={t('tr.add_emp')} value={emps} onChange={setEmps} />
        {done ? <div className="grid-2">
          <Input label={t('tr.completed_on')} type="date" ltr required max={todayMuscat()} value={f.completed_on} onChange={(e) => setF({ ...f, completed_on: e.target.value })} />
          <Input label={t('tr.expires_on')} type="date" ltr value={f.expires_on} placeholder={autoExp} hint={autoExp ? `${t('tr.expires_auto')} ${fmtDate(autoExp)}` : t('tr.expires_auto')}
            onChange={(e) => setF({ ...f, expires_on: e.target.value })} />
        </div> : <Input label={t('tr.planned_on')} type="date" ltr value={f.planned_on} onChange={(e) => setF({ ...f, planned_on: e.target.value })} />}
        <div className="grid-3">
          <Input label={t('tr.certificate')} ltr value={f.certificate_no} onChange={(e) => setF({ ...f, certificate_no: e.target.value })} />
          <Input label={t('tr.score')} value={f.score} onChange={(e) => setF({ ...f, score: e.target.value })} />
          <Input label={t('tr.cost')} inputMode="decimal" ltr value={f.cost} onChange={(e) => setF({ ...f, cost: e.target.value })} />
        </div>
        <Textarea label={t('c.notes')} value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} />
      </div>
    </Modal>
  );
}

function Gaps() {
  const { t, L } = useI18n();
  const { data, error, loading, reload } = useAsync(() => wfapi.trainingGaps(), []);
  return (
    <div className="panel">
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('tr.no_gaps')}</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('c.employee')}</th><th>{t('tr.course')}</th><th>{t('tr.last_expired')}</th></tr></thead>
          <tbody>{data.map((g, i) => (
            <tr key={`${g.employee_id}-${g.course_code}-${i}`}>
              <td data-label={t('c.employee')}><EmpCell r={g} /></td>
              <td data-label={t('tr.course')}>{L(g.course_en, g.course_ar)}<span className="sub">{g.course_code}</span></td>
              <td data-label={t('tr.last_expired')}>{g.last_expired ? <span className="num bad-text">{fmtDate(g.last_expired)}</span> : <span className="muted">{t('tr.never')}</span>}</td>
            </tr>))}
          </tbody></table></div>)}
    </div>
  );
}

function Courses() {
  const { t, L } = useI18n();
  const { data, error, loading, reload, setData } = useAsync(() => wfapi.listCourses(), []);
  const [edit, setEdit] = useState<Course | 'new' | null>(null);
  return (
    <>
      <div className="row" style={{ justifyContent: 'flex-end' }}><Button kind="primary" onClick={() => setEdit('new')}>{t('tr.new_course')}</Button></div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('tr.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('tr.course')}</th><th>{t('tr.category')}</th><th>{t('tr.validity')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((c) => (
              <tr key={c.id}>
                <td data-label={t('tr.course')}><b>{L(c.name_en, c.name_ar)}</b><span className="sub">{c.code}{c.provider ? ` · ${c.provider}` : ''}</span></td>
                <td data-label={t('tr.category')}>{t(`tr.c_${c.category}` as Key)}{c.mandatory && <> <Badge tone="info">{t('tr.mandatory')}</Badge></>}</td>
                <td data-label={t('tr.validity')} className="num">{c.validity_months ?? t('tr.validity_none')}</td>
                <td data-label={t('c.status')}>{t('tr.completed_n', { n: c.completed })}{c.expiring_60 > 0 && <span className="sub warn-text">{t('tr.expiring_n', { n: c.expiring_60 })}</span>}
                  {!c.is_active && <span className="sub">{t('c.inactive')}</span>}</td>
                <td className="r"><Button small onClick={() => setEdit(c)}>{t('c.edit')}</Button></td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <CourseDialog edit={edit} onClose={() => setEdit(null)} onDone={(r) => { setData(r); setEdit(null); }} />
    </>
  );
}

function CourseDialog({ edit, onClose, onDone }: { edit: Course | 'new' | null; onClose: () => void; onDone: (r: Course[]) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const blank = { code: '', name_en: '', name_ar: '', provider: '', category: 'SAFETY' as CourseCategory, validity_months: '', mandatory: false, is_active: true };
  const [f, setF] = useState(blank);
  useEffect(() => {
    if (edit === 'new') setF(blank);
    else if (edit) setF({ code: edit.code, name_en: edit.name_en, name_ar: edit.name_ar ?? '', provider: edit.provider ?? '', category: edit.category,
      validity_months: edit.validity_months != null ? String(edit.validity_months) : '', mandatory: edit.mandatory, is_active: edit.is_active });
  }, [edit]); // eslint-disable-line react-hooks/exhaustive-deps
  const save = async () => {
    const r = await run(() => wfapi.saveCourse({ ...(edit && edit !== 'new' ? { id: edit.id } : {}), ...f, name_ar: f.name_ar || null, provider: f.provider || null,
      validity_months: f.validity_months ? Number(f.validity_months) : null }), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? 'tr.new_course' : 'tr.edit_course')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.code.trim() || !f.name_en.trim()} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="grid-2">
          <Input label={t('tr.code')} required ltr value={f.code} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} />
          <Select label={t('tr.category')} value={f.category} onChange={(e) => setF({ ...f, category: e.target.value as CourseCategory })}>
            {COURSE_CATEGORIES.map((c) => <option key={c} value={c}>{t(`tr.c_${c}` as Key)}</option>)}
          </Select>
        </div>
        <Input label={t('tr.name_en')} required value={f.name_en} onChange={(e) => setF({ ...f, name_en: e.target.value })} />
        <Input label={t('tr.name_ar')} dir="rtl" value={f.name_ar} onChange={(e) => setF({ ...f, name_ar: e.target.value })} />
        <div className="grid-2">
          <Input label={t('tr.provider')} value={f.provider} onChange={(e) => setF({ ...f, provider: e.target.value })} />
          <Input label={t('tr.validity')} type="number" min={1} max={120} ltr value={f.validity_months} hint={t('tr.validity_none')} onChange={(e) => setF({ ...f, validity_months: e.target.value })} />
        </div>
        <Check label={t('tr.mandatory')} checked={f.mandatory} onChange={(v) => setF({ ...f, mandatory: v })} />
        <Check label={t('tr.active')} checked={f.is_active} onChange={(v) => setF({ ...f, is_active: v })} />
      </div>
    </Modal>
  );
}
