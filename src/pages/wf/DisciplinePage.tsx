import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { CASE_CATEGORIES, wfapi, type CaseCategory } from '../../lib/api_wf';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Button, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { EmpCell } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { CaseBadge } from '../../components/wf';
import { fmtDate, todayMuscat } from '../../lib/format';

export default function DisciplinePage() {
  const { t } = useI18n();
  const { can } = useSession();
  const full = can('DISC_READ');
  const [status, setStatus] = useState(full ? 'OPEN' : '');
  const [open, setOpen] = useState(false);
  const { data, error, loading, reload } = useAsync(() => wfapi.listCases({ status: status || null }), [status]);
  return (
    <div className="stack">
      <PageHead title={t('dc.title')} sub={full ? t('dc.hint') : t('dc.my_hint')} />
      {full && <div className="row" style={{ justifyContent: 'space-between', flexWrap: 'wrap' }}>
        <div className="panel panel-pad row">
          <div className="field" style={{ minWidth: 220 }}><label htmlFor="dc-st">{t('c.status')}</label>
            <select id="dc-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="OPEN">{t('dc.filter_open')}</option><option value="">{t('c.all')}</option>
              {(['DRAFT', 'INVESTIGATION', 'PROPOSED', 'DECIDED', 'DISMISSED'] as const).map((s) => <option key={s} value={s}>{t(`dc.st_${s}` as Key)}</option>)}
            </select></div>
        </div>
        {can('DISC_WRITE') && <Button kind="primary" onClick={() => setOpen(true)}>{t('dc.new')}</Button>}
      </div>}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('dc.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('dc.ref')}</th>{full && <th>{t('c.employee')}</th>}<th>{t('dc.category')}</th><th>{t('c.status')}</th><th>{t('dc.penalty')}</th><th /></tr></thead>
            <tbody>{data.map((d) => (
              <tr key={d.id}>
                <td data-label={t('dc.ref')}><span className="num">{d.ref_no}</span><span className="sub num">{fmtDate(d.incident_date)}</span></td>
                {full && <td data-label={t('c.employee')}><EmpCell r={d} /></td>}
                <td data-label={t('dc.category')}>{t(`dc.cat_${d.category}` as Key)}</td>
                <td data-label={t('c.status')}><CaseBadge s={d.status} /></td>
                <td data-label={t('dc.penalty')}>{d.penalty ? <>{t(`dc.pen_${d.penalty}` as Key)}{d.penalty_days ? ` · ${t('dc.days_n', { n: d.penalty_days })}` : ''}</>
                  : d.proposed_penalty ? <span className="muted">{t('dc.proposed', { p: t(`dc.pen_${d.proposed_penalty}` as Key) })}</span> : '—'}</td>
                <td className="r"><Link className={`btn btn-sm${d.can_decide || d.can_respond ? ' btn-primary' : ''}`} to={`/discipline/${d.id}`}>{t('sap.open')}</Link></td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <CaseDialog open={open} onClose={() => setOpen(false)} />
    </div>
  );
}

export function CaseDialog({ open, onClose, edit, onDone }: {
  open: boolean; onClose: () => void; onDone?: () => void;
  edit?: { id: string; incident_date: string; category: CaseCategory; description: string; investigation_notes: string | null } | null;
}) {
  const { t } = useI18n();
  const nav = useNavigate();
  const { busy, run } = useAction();
  const [f, setF] = useState({ employee_id: null as string | null, label: '', incident_date: '', category: '' as CaseCategory | '', description: '', investigation_notes: '' });
  useEffect(() => {
    if (!open) return;
    setF(edit ? { employee_id: null, label: '', incident_date: edit.incident_date, category: edit.category, description: edit.description, investigation_notes: edit.investigation_notes ?? '' }
      : { employee_id: null, label: '', incident_date: todayMuscat(), category: '', description: '', investigation_notes: '' });
  }, [open, edit]);
  const submit = async () => {
    const r = await run(() => wfapi.saveCase({ ...(edit ? { id: edit.id } : { employee_id: f.employee_id }), incident_date: f.incident_date, category: f.category,
      description: f.description, investigation_notes: f.investigation_notes || null }), t('c.saved'));
    if (!r) return;
    onClose();
    if (onDone) onDone(); else nav(`/discipline/${r.id}`);
  };
  return (
    <Modal open={open} title={t(edit ? 'c.edit' : 'dc.new')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={(!edit && !f.employee_id) || !f.category || !f.incident_date || f.description.trim().length < 15} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {!edit && <EmployeePicker label={t('c.employee')} value={f.employee_id} valueLabel={f.label} onChange={(id, l) => setF({ ...f, employee_id: id, label: l ?? '' })} />}
        <div className="grid-2">
          <Input label={t('dc.incident')} type="date" ltr required max={todayMuscat()} value={f.incident_date} onChange={(e) => setF({ ...f, incident_date: e.target.value })} />
          <Select label={t('dc.category')} required value={f.category} onChange={(e) => setF({ ...f, category: e.target.value as CaseCategory })}>
            <option value="">{t('c.select')}</option>
            {CASE_CATEGORIES.map((c) => <option key={c} value={c}>{t(`dc.cat_${c}` as Key)}</option>)}
          </Select>
        </div>
        <Textarea label={t('dc.description')} required value={f.description} onChange={(e) => setF({ ...f, description: e.target.value })} />
        <Textarea label={t('dc.notes')} value={f.investigation_notes} onChange={(e) => setF({ ...f, investigation_notes: e.target.value })} />
      </div>
    </Modal>
  );
}
