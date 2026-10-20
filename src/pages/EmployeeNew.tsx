import { useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../lib/api';
import { parseError } from '../lib/errors';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, Check, ErrorNote, Input, Select, Textarea, useToast } from '../components/ui';
import { EmployeePicker, MasterSelect, useMasters } from '../components/pickers';
import { PageHead } from '../components/Layout';
import { PersonalFields, emptyPersonal, personalPayload, type PersonalForm } from './employee/PersonalFields';

interface JobForm {
  department_id: string | null; job_title_id: string | null; grade_id: string | null; category_id: string | null;
  location_id: string | null; cost_centre_id: string | null; manager_id: string | null; employment_type: string; shift_code: string;
}

export default function EmployeeNewPage() {
  const { t, errText } = useI18n();
  const { me, can } = useSession();
  const nav = useNavigate();
  const { push } = useToast();
  const [entityId, setEntityId] = useState<string>(me?.entities[0]?.id ?? '');
  const [p, setP] = useState<PersonalForm>(emptyPersonal());
  const [employeeNo, setEmployeeNo] = useState('');
  const [joinDate, setJoinDate] = useState('');
  const [probationEnd, setProbationEnd] = useState('');
  const [job, setJob] = useState<JobForm>({ department_id: null, job_title_id: null, grade_id: null, category_id: null,
    location_id: null, cost_centre_id: null, manager_id: null, employment_type: 'FULL_TIME', shift_code: '' });
  const [managerLabel, setManagerLabel] = useState<string | null>(null);
  const [dupNeeded, setDupNeeded] = useState(false);
  const [dupOk, setDupOk] = useState(false);
  const [excReason, setExcReason] = useState('');
  const [error, setError] = useState<unknown>(null);
  const [busy, setBusy] = useState(false);

  const jobs = useMasters<{ id: string; code: string; name_en: string; name_ar: string | null; is_active: boolean; omani_only: boolean; omani_only_source: string | null }>('job_title', entityId);
  const selectedJob = jobs.find((j) => j.id === job.job_title_id);
  const needsException = !!selectedJob?.omani_only && !!p.nationality && p.nationality !== 'OM';

  if (!can('EMP_WRITE')) return <ErrorNote error={new Error('NOT_ALLOWED: ')} />;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      const res = await api.saveEmployee({
        ...personalPayload(p), entity_id: entityId, employee_no: employeeNo.trim() || null, join_date: joinDate || null,
        probation_end_date: probationEnd || null, confirm_duplicate: dupOk,
        exception_reason: needsException ? excReason.trim() : null,
        assignment: { ...job, shift_code: job.shift_code.trim() || null },
      });
      push(t('ef.created', { no: res.employee.employee_no }));
      nav(`/employees/${res.employee.id}`, { replace: true });
    } catch (err) {
      const pe = parseError(err);
      if (pe.code === 'POSSIBLE_DUPLICATE') setDupNeeded(true);
      setError(err);
      window.scrollTo({ top: 0 });
    } finally {
      setBusy(false);
    }
  };

  const setJ = (k: keyof JobForm, v: string | null) => setJob((s) => ({ ...s, [k]: v }));

  return (
    <form className="stack" onSubmit={submit} noValidate>
      <PageHead title={t('ef.title_new')} />
      {error ? <div className="note note-bad" role="alert">{errText(error)}</div> : null}

      <section className="panel panel-pad form-section">
        <h3>{t('ef.personal')}</h3>
        <PersonalFields value={p} onChange={setP} />
      </section>

      <section className="panel panel-pad form-section">
        <h3>{t('ef.employment')}</h3>
        <div className="form-grid">
          {me && me.entities.length > 1 && (
            <Select label={t('c.company')} required value={entityId} onChange={(e) => { setEntityId(e.target.value);
              setJob({ ...job, department_id: null, job_title_id: null, grade_id: null, category_id: null, location_id: null, cost_centre_id: null }); }}>
              {me.entities.map((en) => <option key={en.id} value={en.id}>{en.code} — {en.name_en}</option>)}
            </Select>
          )}
          <Input label={t('ef.employee_no')} hint={t('ef.employee_no_hint')} ltr value={employeeNo}
            onChange={(e) => setEmployeeNo(e.target.value.toUpperCase())} />
          <Input label={t('ef.join_date')} type="date" required value={joinDate} onChange={(e) => setJoinDate(e.target.value)} />
          <Input label={t('ef.probation_end')} type="date" hint={t('ef.probation_hint')} value={probationEnd}
            min={joinDate || undefined} onChange={(e) => setProbationEnd(e.target.value)} />
          <MasterSelect kind="department" entityId={entityId} label={t('c.department')} required value={job.department_id} onChange={(v) => setJ('department_id', v)} />
          <MasterSelect kind="job_title" entityId={entityId} label={t('emp.job')} required value={job.job_title_id} onChange={(v) => setJ('job_title_id', v)} />
          <MasterSelect kind="category" entityId={entityId} label={t('ef.category')} required value={job.category_id} onChange={(v) => setJ('category_id', v)} />
          <MasterSelect kind="grade" entityId={entityId} label={t('ef.grade')} value={job.grade_id} onChange={(v) => setJ('grade_id', v)} />
          <MasterSelect kind="location" entityId={entityId} label={t('ef.location')} value={job.location_id} onChange={(v) => setJ('location_id', v)} />
          <MasterSelect kind="cost_centre" entityId={entityId} label={t('ef.cost_centre')} hint={t('ef.cost_centre_hint')} value={job.cost_centre_id} onChange={(v) => setJ('cost_centre_id', v)} />
          <EmployeePicker label={t('ef.manager')} value={job.manager_id} valueLabel={managerLabel}
            onChange={(id, label) => { setJ('manager_id', id); setManagerLabel(label); }} />
          <Select label={t('ef.employment_type')} value={job.employment_type} onChange={(e) => setJ('employment_type', e.target.value)}>
            {['FULL_TIME', 'PART_TIME', 'TEMPORARY', 'TRAINEE'].map((x) => <option key={x} value={x}>{t(`ef.${x}` as 'ef.FULL_TIME')}</option>)}
          </Select>
          <Input label={t('ef.shift')} value={job.shift_code} onChange={(e) => setJ('shift_code', e.target.value)} />
          {needsException && (
            <div className="span-2 stack">
              <div className="note note-warn">{t('ef.exception_hint')} {selectedJob?.omani_only_source ? `(${selectedJob.omani_only_source})` : ''}</div>
              <Textarea label={t('ef.exception_reason')} required value={excReason} onChange={(e) => setExcReason(e.target.value)} />
            </div>
          )}
          {dupNeeded && (
            <div className="span-2"><Check label={t('ef.duplicate_tick')} checked={dupOk} onChange={setDupOk} /></div>
          )}
        </div>
      </section>

      <div className="row row-end">
        <Button onClick={() => nav(-1)}>{t('c.cancel')}</Button>
        <button type="submit" className="btn btn-primary" disabled={busy}>{busy ? t('c.saving') : t('ef.create')}</button>
      </div>
    </form>
  );
}
