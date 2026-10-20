import { useState } from 'react';
import { api, type EmergencyContact, type EmployeeFile } from '../../lib/api';
import { useI18n } from '../../i18n';
import { Badge, Button, Check, DateText, Empty, Input, Modal, Select, Textarea, useAction, type useConfirm } from '../../components/ui';
import { MasterSelect } from '../../components/pickers';
import { PersonalFields, personalFrom, personalPayload, type PersonalForm } from './PersonalFields';
import { todayMuscat } from '../../lib/format';

export type ConfirmFn = ReturnType<typeof useConfirm>['ask'];

function Fact({ label, children }: { label: string; children: React.ReactNode }) {
  return <><dt>{label}</dt><dd>{children || <span className="muted">—</span>}</dd></>;
}

export function ProfileTab({ file, onChange, confirm }: { file: EmployeeFile; onChange: (f: EmployeeFile) => void; confirm: ConfirmFn }) {
  const { t, L } = useI18n();
  const e = file.employee;
  const full = file.access !== 'TEAM';
  const [editing, setEditing] = useState<PersonalForm | null>(null);
  const [contact, setContact] = useState<Partial<EmergencyContact> | null>(null);
  const { busy, run } = useAction();

  const savePersonal = async () => {
    if (!editing) return;
    const r = await run(() => api.saveEmployee({ id: e.id, ...personalPayload(editing) }), t('c.saved'));
    if (r) { onChange(r); setEditing(null); }
  };
  const saveContact = async () => {
    if (!contact) return;
    const r = await run(() => api.saveEmergencyContact(e.id, contact), t('c.saved'));
    if (r) { onChange(r); setContact(null); }
  };
  const removeContact = async (c: EmergencyContact) => {
    if ((await confirm({ title: t('c.remove'), body: c.name, danger: true })) === null) return;
    const r = await run(() => api.removeEmergencyContact(c.id), t('c.saved'));
    if (r) onChange(r);
  };

  return (
    <div className="grid-side">
      <div className="stack">
        <section className="panel">
          <div className="panel-head"><h2>{t('ef.personal')}</h2>
            {file.caps.edit && full && <Button small onClick={() => setEditing(personalFrom(e))}>{t('ed.edit_personal')}</Button>}</div>
          <div className="panel-body">
            <dl className="facts">
              <Fact label={t('emp.nationality')}>{L(e.nationality_en, e.nationality_ar)}</Fact>
              <Fact label={t('ef.gender')}>{e.gender === 'M' ? t('ef.male') : e.gender === 'F' ? t('ef.female') : ''}</Fact>
              {full && <>
                <Fact label={t('ef.dob')}>{e.date_of_birth && <DateText v={e.date_of_birth} />}</Fact>
                <Fact label={t('ef.marital')}>{e.marital_status ? t(`ef.${e.marital_status}` as 'ef.SINGLE') : ''}</Fact>
                <Fact label={t('ef.civil')}><span className="num">{e.civil_number}</span></Fact>
              </>}
              <Fact label={t('ef.mobile')}>{e.mobile && <a className="num" href={`tel:${e.mobile}`}>{e.mobile}</a>}</Fact>
              <Fact label={t('ef.work_email')}>{e.work_email && <a href={`mailto:${e.work_email}`}>{e.work_email}</a>}</Fact>
              {full && <>
                <Fact label={t('ef.personal_email')}>{e.personal_email}</Fact>
                <Fact label={t('ef.alt_phone')}><span className="num">{e.alt_phone}</span></Fact>
                <Fact label={t('ef.address')}>{[e.address_line, e.city, e.wilayat, e.governorate].filter(Boolean).join(', ')}</Fact>
              </>}
            </dl>
          </div>
        </section>

        {full && (
          <section className="panel">
            <div className="panel-head"><h2>{t('ed.emergency')}</h2>
              {file.caps.edit && <Button small onClick={() => setContact({ is_next_of_kin: false })}>{t('ed.add_contact')}</Button>}</div>
            {file.emergency_contacts.length === 0 ? <Empty>{t('ed.no_contacts')}</Empty> : (
              <div className="table-wrap"><table className="t cards">
                <thead><tr><th>{t('ed.contact_name')}</th><th>{t('ed.relationship')}</th><th>{t('ed.phone')}</th><th /></tr></thead>
                <tbody>{file.emergency_contacts.map((c) => (
                  <tr key={c.id}>
                    <td data-label={t('ed.contact_name')}>{c.name} {c.is_next_of_kin && <Badge tone="info">{t('ed.next_of_kin')}</Badge>}</td>
                    <td data-label={t('ed.relationship')}>{c.relationship}</td>
                    <td data-label={t('ed.phone')} className="num">{c.phone}{c.alt_phone && <span className="sub">{c.alt_phone}</span>}</td>
                    <td className="r">{file.caps.edit && <>
                      <Button kind="ghost" small onClick={() => setContact(c)}>{t('c.edit')}</Button>
                      <Button kind="ghost" small onClick={() => void removeContact(c)}>{t('c.remove')}</Button></>}</td>
                  </tr>))}
                </tbody></table></div>
            )}
          </section>
        )}
      </div>

      <div className="stack">
        <section className="panel">
          <div className="panel-head"><h2>{t('ef.employment')}</h2></div>
          <div className="panel-body">
            <dl className="facts">
              <Fact label={t('c.company')}>{L(e.entity_en, e.entity_ar)}</Fact>
              <Fact label={t('emp.joined')}><DateText v={e.join_date} /></Fact>
              {full && e.original_join_date && e.original_join_date !== e.join_date &&
                <Fact label={t('ed.first_joined')}><DateText v={e.original_join_date} /></Fact>}
              <Fact label={t('ef.probation_end')}>{e.probation_end_date && <DateText v={e.probation_end_date} />}</Fact>
              {e.confirmation_date && <Fact label={t('ed.confirm')}><DateText v={e.confirmation_date} /></Fact>}
              {e.last_working_date && <Fact label={t('ed.last_working')}><DateText v={e.last_working_date} /></Fact>}
              {full && e.separation_type && <Fact label={t('ed.leaving_reason')}>{t(`ed.${e.separation_type}` as 'ed.OTHER')}</Fact>}
              {file.current_assignment && <>
                <Fact label={t('emp.manager')}>{L(file.current_assignment.manager_name_en, file.current_assignment.manager_name_ar)}</Fact>
                <Fact label={t('ef.location')}>{L(file.current_assignment.location_en, file.current_assignment.location_ar)}</Fact>
              </>}
              {file.access === 'FULL' && <Fact label={t('ed.linked_login')}>{file.linked_user ? file.linked_user.email : <span className="muted">{t('ed.no_login')}</span>}</Fact>}
            </dl>
          </div>
        </section>

        {file.caps.edit && <StatusActions file={file} onChange={onChange} />}

        {file.omanisation_exceptions.length > 0 && (
          <section className="panel">
            <div className="panel-head"><h2>{t('ed.exceptions')}</h2></div>
            <ul className="panel-body stack" style={{ margin: 0, listStyle: 'none' }}>
              {file.omanisation_exceptions.map((x) => (
                <li key={x.id}>
                  <div className="row"><b>{L(x.job_title_en, x.job_title_ar)}</b>
                    <Badge tone={x.status === 'ACTIVE' ? 'warn' : undefined}>{x.status === 'ACTIVE' ? t('c.active') : t('c.inactive')}</Badge>
                    {x.status === 'ACTIVE' && file.caps.exception_approve && (
                      <Button kind="ghost" small onClick={async () => {
                        const note = await confirm({ title: t('ed.revoke'), reason: 'required', danger: true });
                        if (note === null) return;
                        const r = await run(() => api.revokeException(x.id, note), t('c.saved'));
                        if (r) onChange(r);
                      }}>{t('ed.revoke')}</Button>)}
                  </div>
                  <div className="muted" style={{ fontSize: 13.5 }}>{x.reason}</div>
                  <div className="muted" style={{ fontSize: 12.5 }}>{x.approved_by_name}</div>
                </li>
              ))}
            </ul>
          </section>
        )}
      </div>

      <Modal open={!!editing} title={t('ed.edit_personal')} onClose={() => setEditing(null)} wide
        footer={<><Button onClick={() => setEditing(null)}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void savePersonal()}>{t('c.save')}</Button></>}>
        {editing && <PersonalFields value={editing} onChange={setEditing} />}
      </Modal>

      <Modal open={!!contact} title={t(contact?.id ? 'c.edit' : 'ed.add_contact')} onClose={() => setContact(null)}
        footer={<><Button onClick={() => setContact(null)}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void saveContact()}>{t('c.save')}</Button></>}>
        {contact && (
          <div className="form-grid">
            <Input label={t('ed.contact_name')} required value={contact.name ?? ''} onChange={(ev) => setContact({ ...contact, name: ev.target.value })} />
            <Input label={t('ed.relationship')} required value={contact.relationship ?? ''} onChange={(ev) => setContact({ ...contact, relationship: ev.target.value })} />
            <Input label={t('ed.phone')} type="tel" ltr required value={contact.phone ?? ''} onChange={(ev) => setContact({ ...contact, phone: ev.target.value })} />
            <Input label={t('ef.alt_phone')} type="tel" ltr value={contact.alt_phone ?? ''} onChange={(ev) => setContact({ ...contact, alt_phone: ev.target.value })} />
            <Input label={t('ef.address')} className="span-2" value={contact.address ?? ''} onChange={(ev) => setContact({ ...contact, address: ev.target.value })} />
            <div className="span-2"><Check label={t('ed.next_of_kin')} checked={!!contact.is_next_of_kin} onChange={(v) => setContact({ ...contact, is_next_of_kin: v })} /></div>
          </div>
        )}
      </Modal>
    </div>
  );
}

type Action = 'CONFIRM' | 'NOTICE' | 'WITHDRAW_NOTICE' | 'SUSPEND' | 'REINSTATE' | 'SEPARATE' | 'REHIRE';

function StatusActions({ file, onChange }: { file: EmployeeFile; onChange: (f: EmployeeFile) => void }) {
  const { t } = useI18n();
  const e = file.employee;
  const [action, setAction] = useState<Action | null>(null);
  const [form, setForm] = useState<Record<string, string>>({});
  const { busy, run } = useAction();

  const available: Action[] = {
    PROBATION: ['CONFIRM', 'NOTICE', 'SUSPEND', 'SEPARATE'],
    ACTIVE: ['NOTICE', 'SUSPEND', 'SEPARATE'],
    NOTICE: ['WITHDRAW_NOTICE', 'SUSPEND', 'SEPARATE'],
    SUSPENDED: ['REINSTATE', 'SEPARATE'],
    SEPARATED: ['REHIRE'],
  }[e.status] as Action[];

  const label: Record<Action, string> = {
    CONFIRM: t('ed.confirm'), NOTICE: t('ed.notice'), WITHDRAW_NOTICE: t('ed.withdraw_notice'), SUSPEND: t('ed.suspend'),
    REINSTATE: t('ed.reinstate'), SEPARATE: t('ed.separate'), REHIRE: t('ed.rehire'),
  };
  const today = todayMuscat();
  const open = (a: Action) => {
    setForm({ date: today, separation_type: e.separation_type ?? '', last_working_date: e.last_working_date ?? '' });
    setAction(a);
  };
  const set = (k: string, v: string) => setForm((s) => ({ ...s, [k]: v }));
  const submit = async () => {
    if (!action) return;
    const p: Record<string, unknown> = { action, date: form.date || null, notes: form.notes?.trim() || null };
    if (action === 'NOTICE' || action === 'SEPARATE') { p.separation_type = form.separation_type || null; p.last_working_date = form.last_working_date || null; }
    if (action === 'REHIRE') {
      p.probation_end_date = form.probation_end_date || null;
      p.exception_reason = form.exception_reason?.trim() || null;
      p.assignment = { department_id: form.department_id || null, job_title_id: form.job_title_id || null, category_id: form.category_id || null,
        grade_id: form.grade_id || null, location_id: form.location_id || null };
    }
    const r = await run(() => api.changeStatus(e.id, p), t('c.saved'));
    if (r) { onChange(r); setAction(null); }
  };

  return (
    <section className="panel">
      <div className="panel-head"><h2>{t('ed.actions')}</h2></div>
      <div className="panel-body row">
        {available.map((a) => (
          <Button key={a} small kind={a === 'SEPARATE' ? 'danger' : 'default'} onClick={() => open(a)}>{label[a]}</Button>
        ))}
      </div>
      <Modal open={!!action} title={action ? label[action] : ''} onClose={() => setAction(null)} wide={action === 'REHIRE'}
        footer={<><Button onClick={() => setAction(null)}>{t('c.cancel')}</Button>
          <Button kind={action === 'SEPARATE' ? 'danger' : 'primary'} busy={busy} onClick={() => void submit()}>{t('c.confirm')}</Button></>}>
        <div className="form-grid">
          {action === 'SEPARATE' && <div className="span-2 note note-warn">{t('ed.separate_warn')}</div>}
          <Input type="date" required label={action === 'SEPARATE' ? t('ed.leaving_date') : action === 'REHIRE' ? t('ed.rehire_date') : t('c.date')}
            value={form.date ?? ''} onChange={(ev) => set('date', ev.target.value)} />
          {(action === 'NOTICE' || action === 'SEPARATE') && (
            <Select label={t('ed.leaving_reason')} required value={form.separation_type ?? ''} onChange={(ev) => set('separation_type', ev.target.value)}>
              <option value="">{t('c.select')}</option>
              {(['RESIGNATION', 'TERMINATION', 'END_OF_CONTRACT', 'RETIREMENT', ...(action === 'SEPARATE' ? ['DEATH'] : []), 'OTHER'] as const)
                .map((x) => <option key={x} value={x}>{t(`ed.${x}` as 'ed.OTHER')}</option>)}
            </Select>
          )}
          {action === 'NOTICE' && <Input type="date" required label={t('ed.last_working')} value={form.last_working_date ?? ''} onChange={(ev) => set('last_working_date', ev.target.value)} />}
          {action === 'REHIRE' && <>
            <Input type="date" label={t('ef.probation_end')} value={form.probation_end_date ?? ''} onChange={(ev) => set('probation_end_date', ev.target.value)} />
            <MasterSelect kind="department" entityId={e.entity_id} label={t('c.department')} required value={form.department_id} onChange={(v) => set('department_id', v ?? '')} />
            <MasterSelect kind="job_title" entityId={e.entity_id} label={t('emp.job')} required value={form.job_title_id} onChange={(v) => set('job_title_id', v ?? '')} />
            <MasterSelect kind="category" entityId={e.entity_id} label={t('ef.category')} required value={form.category_id} onChange={(v) => set('category_id', v ?? '')} />
            <MasterSelect kind="grade" entityId={e.entity_id} label={t('ef.grade')} value={form.grade_id} onChange={(v) => set('grade_id', v ?? '')} />
            <MasterSelect kind="location" entityId={e.entity_id} label={t('ef.location')} value={form.location_id} onChange={(v) => set('location_id', v ?? '')} />
            {!e.is_omani && <Textarea className="span-2" label={t('ef.exception_reason')} hint={t('ef.exception_hint')}
              value={form.exception_reason ?? ''} onChange={(ev) => set('exception_reason', ev.target.value)} />}
          </>}
          <Textarea className="span-2" label={t('c.notes')} required={action === 'SUSPEND'} value={form.notes ?? ''} onChange={(ev) => set('notes', ev.target.value)} />
        </div>
      </Modal>
    </section>
  );
}
