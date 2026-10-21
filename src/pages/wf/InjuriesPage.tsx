import { useEffect, useState } from 'react';
import { SEVERITIES, wfapi, type Injury, type Severity } from '../../lib/api_wf';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { EmpCell } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { SeverityBadge } from '../../components/wf';
import { fmtDate, fmtDateTime, todayMuscat } from '../../lib/format';

/** datetime-local value in Muscat time (UTC+4, no daylight saving). */
function toLocalInput(iso: string): string {
  const d = new Date(new Date(iso).getTime() + 4 * 3600000);
  return d.toISOString().slice(0, 16);
}
function fromLocalInput(v: string): string { return `${v}:00+04:00`; }

export default function InjuriesPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const hr = can('HSE_WRITE');
  const [status, setStatus] = useState('OPEN');
  const { data, error, loading, reload } = useAsync(() => wfapi.listInjuries({ status: status || null }), [status]);
  const [edit, setEdit] = useState<Injury | 'new' | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const close = async (w: Injury) => {
    if ((await confirm.ask({ title: `${t('in.close')} — ${w.ref_no}`, body: t('in.close_q') })) === null) return;
    if (await run(() => wfapi.closeInjury(w.id), t('c.saved'))) void reload();
  };
  return (
    <div className="stack">
      <PageHead title={t('in.title')} sub={t('in.hint')} actions={hr ? <Button kind="primary" onClick={() => setEdit('new')}>{t('in.new')}</Button> : undefined} />
      <div className="panel panel-pad row">
        <div className="field" style={{ minWidth: 200 }}><label htmlFor="in-st">{t('c.status')}</label>
          <select id="in-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="OPEN">{t('in.st_OPEN')}</option><option value="CLOSED">{t('in.st_CLOSED')}</option><option value="">{t('c.all')}</option>
          </select></div>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('in.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('in.ref')}</th><th>{t('c.employee')}</th><th>{t('in.severity')}</th><th>{t('in.location')}</th><th>{t('in.spf_reported')}</th><th /></tr></thead>
            <tbody>{data.map((w) => (
              <tr key={w.id}>
                <td data-label={t('in.ref')}><span className="num">{w.ref_no}</span><span className="sub num">{fmtDateTime(w.occurred_at)}</span></td>
                <td data-label={t('c.employee')}><EmpCell r={w} /></td>
                <td data-label={t('in.severity')}><SeverityBadge s={w.severity} />{w.lost_days > 0 && <span className="sub">{t('in.lost_days')}: <span className="num">{w.lost_days}</span></span>}</td>
                <td data-label={t('in.location')}><span className="wrap-text">{w.location}</span><span className="sub wrap-text">{w.description}</span></td>
                <td data-label={t('in.spf_reported')}>{w.spf_reported_on ? <span className="num">{t('in.reported', { d: fmtDate(w.spf_reported_on) })}</span>
                  : w.severity === 'FIRST_AID' ? '—' : w.report_overdue ? <Badge tone="bad">{t('in.overdue')}</Badge> : <span className="warn-text num">{t('in.report_due', { d: fmtDate(w.report_due) })}</span>}</td>
                <td className="r">{w.can_edit && <div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  <Button small onClick={() => setEdit(w)}>{t('c.edit')}</Button>
                  <Button small busy={busy} onClick={() => void close(w)}>{t('in.close')}</Button></div>}
                  {w.status === 'CLOSED' && <Badge tone="ok">{t('in.st_CLOSED')}</Badge>}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <InjuryDialog edit={edit} onClose={() => setEdit(null)} onDone={() => { setEdit(null); void reload(); }} />
      {confirm.node}
    </div>
  );
}

function InjuryDialog({ edit, onClose, onDone }: { edit: Injury | 'new' | null; onClose: () => void; onDone: () => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const pol = useAsync(() => (edit ? wfapi.policies() : Promise.resolve(null)), [edit]);
  const blank = () => ({ employee_id: null as string | null, label: '', occurred_at: `${todayMuscat()}T08:00`, location: '', description: '', injury_type: '', body_part: '',
    severity: '' as Severity | '', lost_days: '0', witnesses: '', root_cause: '', corrective_action: '', spf_reported_on: '', spf_reference: '' });
  const [f, setF] = useState(blank);
  useEffect(() => {
    if (edit === 'new') setF(blank());
    else if (edit) setF({ employee_id: edit.employee_id, label: `${edit.employee_no} — ${L(edit.full_name_en, edit.full_name_ar)}`, occurred_at: toLocalInput(edit.occurred_at),
      location: edit.location, description: edit.description, injury_type: edit.injury_type ?? '', body_part: edit.body_part ?? '', severity: edit.severity,
      lost_days: String(edit.lost_days), witnesses: edit.witnesses ?? '', root_cause: edit.root_cause ?? '', corrective_action: edit.corrective_action ?? '',
      spf_reported_on: edit.spf_reported_on ?? '', spf_reference: edit.spf_reference ?? '' });
  }, [edit, L]);
  const set = (k: keyof ReturnType<typeof blank>) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const save = async () => {
    const r = await run(() => wfapi.saveInjury({ ...(edit && edit !== 'new' ? { id: edit.id } : {}), employee_id: f.employee_id, occurred_at: fromLocalInput(f.occurred_at),
      location: f.location, description: f.description, injury_type: f.injury_type || null, body_part: f.body_part || null, severity: f.severity,
      lost_days: Number(f.lost_days) || 0, witnesses: f.witnesses || null, root_cause: f.root_cause || null, corrective_action: f.corrective_action || null,
      spf_reported_on: f.spf_reported_on || null, spf_reference: f.spf_reference || null }), t('in.saved'));
    if (r) onDone();
  };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? 'in.new' : 'in.edit')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!f.employee_id || !f.severity || !f.location.trim() || f.description.trim().length < 15 || !f.occurred_at} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {edit === 'new' ? <EmployeePicker label={t('c.employee')} value={f.employee_id} valueLabel={f.label} onChange={(id, l) => setF({ ...f, employee_id: id, label: l ?? '' })} />
          : <div><b>{f.label}</b></div>}
        <div className="grid-3">
          <Input label={t('in.when')} type="datetime-local" ltr required value={f.occurred_at} onChange={set('occurred_at')} />
          <Select label={t('in.severity')} required value={f.severity} onChange={set('severity')}>
            <option value="">{t('c.select')}</option>
            {SEVERITIES.map((s) => <option key={s} value={s}>{t(`in.sev_${s}` as Key)}</option>)}
          </Select>
          <Input label={t('in.lost_days')} type="number" min={0} ltr value={f.lost_days} onChange={set('lost_days')} />
        </div>
        <Input label={t('in.location')} required value={f.location} onChange={set('location')} />
        <Textarea label={t('in.description')} required value={f.description} onChange={set('description')} />
        <div className="grid-3">
          <Input label={t('in.type')} value={f.injury_type} onChange={set('injury_type')} />
          <Input label={t('in.body_part')} value={f.body_part} onChange={set('body_part')} />
          <Input label={t('in.witnesses')} value={f.witnesses} onChange={set('witnesses')} />
        </div>
        <Textarea label={t('in.root_cause')} value={f.root_cause} onChange={set('root_cause')} />
        <Textarea label={t('in.corrective')} value={f.corrective_action} onChange={set('corrective_action')} />
        <div className="grid-2">
          <Input label={t('in.spf_reported')} type="date" ltr value={f.spf_reported_on} max={todayMuscat()} hint={pol.data ? t('in.basis', { n: pol.data.injury_report_days }) : undefined} onChange={set('spf_reported_on')} />
          <Input label={t('in.spf_ref')} ltr value={f.spf_reference} onChange={set('spf_reference')} />
        </div>
      </div>
    </Modal>
  );
}
