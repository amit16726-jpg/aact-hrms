import { useState } from 'react';
import { api, type Assignment, type EmployeeFile } from '../../lib/api';
import { useI18n } from '../../i18n';
import { Badge, Button, DateText, Empty, Input, Modal, Select, Textarea, useAction } from '../../components/ui';
import { EmployeePicker, MasterSelect, useMasters } from '../../components/pickers';
import { todayMuscat } from '../../lib/format';

interface Form {
  reason: string; effective_from: string; department_id: string | null; job_title_id: string | null; grade_id: string | null;
  category_id: string | null; location_id: string | null; cost_centre_id: string | null; manager_id: string | null;
  employment_type: string; shift_code: string; notes: string; exception_reason: string;
}

export function JobTab({ file, onChange }: { file: EmployeeFile; onChange: (f: EmployeeFile) => void }) {
  const { t, L, tk } = useI18n();
  const e = file.employee;
  const open = file.assignments.find((a) => !a.effective_to) ?? null;
  const [form, setForm] = useState<Form | null>(null);
  const [mgrLabel, setMgrLabel] = useState<string | null>(null);
  const { busy, run } = useAction();
  const jobs = useMasters<{ id: string; code: string; name_en: string; name_ar: string | null; is_active: boolean; omani_only: boolean }>('job_title', e.entity_id);

  const start = (a: Assignment) => {
    setMgrLabel(a.manager_name_en ? `${a.manager_no} — ${L(a.manager_name_en, a.manager_name_ar)}` : null);
    setForm({ reason: 'TRANSFER', effective_from: todayMuscat(), department_id: a.department_id, job_title_id: a.job_title_id,
      grade_id: a.grade_id, category_id: a.category_id, location_id: a.location_id, cost_centre_id: a.cost_centre_id,
      manager_id: a.manager_id, employment_type: a.employment_type, shift_code: a.shift_code ?? '', notes: '', exception_reason: '' });
  };
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((s) => (s ? { ...s, [k]: v } : s));
  const needsException = !!form && !e.is_omani && !!jobs.find((j) => j.id === form.job_title_id)?.omani_only
    && form.job_title_id !== open?.job_title_id;

  const submit = async () => {
    if (!form) return;
    const p = { ...form, effective_from: form.reason === 'CORRECTION' ? null : form.effective_from,
      shift_code: form.shift_code.trim() || null, notes: form.notes.trim() || null,
      exception_reason: needsException ? form.exception_reason.trim() : null };
    const r = await run(() => api.addAssignment(e.id, p), t('c.saved'));
    if (r) { onChange(r); setForm(null); }
  };

  return (
    <section className="panel">
      <div className="panel-head">
        <h2>{t('ed.tab_job')}</h2>
        {file.caps.edit && open && e.status !== 'SEPARATED' && <Button small kind="primary" onClick={() => start(open)}>{t('ed.change_job')}</Button>}
      </div>
      <div className="panel-body">
        {file.assignments.length === 0 ? <Empty>—</Empty> : (
          <ol className="tl">
            {file.assignments.map((a) => (
              <li key={a.id} className={a.effective_to ? 'past' : ''}>
                <div className="row" style={{ gap: 8 }}>
                  <b>{L(a.job_title_en, a.job_title_ar)}</b>
                  <span className="muted-2">{L(a.department_en, a.department_ar)}</span>
                  <Badge tone={a.effective_to ? undefined : 'info'}>{tk(`as.${a.reason}`, a.reason)}</Badge>
                  {a.omanisation_exception_id && <Badge tone="warn">{t('ed.exceptions')}</Badge>}
                </div>
                <div className="muted" style={{ fontSize: 13.5 }}>
                  <DateText v={a.effective_from} /> – {a.effective_to ? <DateText v={a.effective_to} /> : t('as.open_ended')}
                </div>
                <div style={{ fontSize: 13.5 }} className="muted-2">
                  {[a.grade_code && `${t('ef.grade')} ${a.grade_code}`, L(a.category_en, a.category_ar), L(a.location_en, a.location_ar),
                    a.cost_centre_en && `${t('ef.cost_centre')}: ${L(a.cost_centre_en, a.cost_centre_ar)}`,
                    a.manager_name_en && `${t('emp.manager')}: ${L(a.manager_name_en, a.manager_name_ar)}`,
                    a.shift_code && `${t('ef.shift')}: ${a.shift_code}`].filter(Boolean).join(' | ')}
                </div>
                {a.notes && <div style={{ fontSize: 13.5 }}>{a.notes}</div>}
              </li>
            ))}
          </ol>
        )}
      </div>

      <Modal open={!!form} title={t('ed.change_job')} onClose={() => setForm(null)} wide
        footer={<><Button onClick={() => setForm(null)}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void submit()}>{t('c.save')}</Button></>}>
        {form && (
          <div className="form-grid">
            <Select label={t('as.reason')} required value={form.reason} onChange={(ev) => set('reason', ev.target.value)}>
              {['TRANSFER', 'PROMOTION', 'DEMOTION', 'REORGANISATION', 'OTHER', 'CORRECTION'].map((r) => <option key={r} value={r}>{tk(`as.${r}`, r)}</option>)}
            </Select>
            {form.reason !== 'CORRECTION'
              ? <Input type="date" label={t('as.effective_from')} required value={form.effective_from} onChange={(ev) => set('effective_from', ev.target.value)} />
              : <div className="note">{t('as.correction_hint')}</div>}
            <div className="span-2 muted" style={{ fontSize: 13 }}>{t('as.keep_hint')}</div>
            <MasterSelect kind="department" entityId={e.entity_id} label={t('c.department')} required value={form.department_id} onChange={(v) => set('department_id', v)} allowEmpty={false} />
            <MasterSelect kind="job_title" entityId={e.entity_id} label={t('emp.job')} required value={form.job_title_id} onChange={(v) => set('job_title_id', v)} allowEmpty={false} />
            <MasterSelect kind="category" entityId={e.entity_id} label={t('ef.category')} required value={form.category_id} onChange={(v) => set('category_id', v)} allowEmpty={false} />
            <MasterSelect kind="grade" entityId={e.entity_id} label={t('ef.grade')} value={form.grade_id} onChange={(v) => set('grade_id', v)} />
            <MasterSelect kind="location" entityId={e.entity_id} label={t('ef.location')} value={form.location_id} onChange={(v) => set('location_id', v)} />
            <MasterSelect kind="cost_centre" entityId={e.entity_id} label={t('ef.cost_centre')} value={form.cost_centre_id} onChange={(v) => set('cost_centre_id', v)} />
            <EmployeePicker label={t('ef.manager')} value={form.manager_id} valueLabel={mgrLabel} exclude={e.id}
              onChange={(id, lbl) => { set('manager_id', id); setMgrLabel(lbl); }} />
            <Select label={t('ef.employment_type')} value={form.employment_type} onChange={(ev) => set('employment_type', ev.target.value)}>
              {(['FULL_TIME', 'PART_TIME', 'TEMPORARY', 'TRAINEE'] as const).map((x) => <option key={x} value={x}>{t(`ef.${x}`)}</option>)}
            </Select>
            <Input label={t('ef.shift')} value={form.shift_code} onChange={(ev) => set('shift_code', ev.target.value)} />
            {needsException && <Textarea className="span-2" required label={t('ef.exception_reason')} hint={t('ef.exception_hint')}
              value={form.exception_reason} onChange={(ev) => set('exception_reason', ev.target.value)} />}
            <Textarea className="span-2" label={t('c.notes')} required={form.reason === 'CORRECTION'} value={form.notes} onChange={(ev) => set('notes', ev.target.value)} />
          </div>
        )}
      </Modal>
    </section>
  );
}
