import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { EXIT_TYPES, addMonthsIso, noticeCheck, wfapi, type ExitPreview, type ExitType } from '../../lib/api_wf';
import { useI18n, type Key } from '../../i18n';
import { Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { EmpCell } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { ExitBadge } from '../../components/wf';
import { addDays, fmtDate, todayMuscat } from '../../lib/format';

export default function ExitsPage() {
  const { t } = useI18n();
  const [status, setStatus] = useState('OPEN');
  const [open, setOpen] = useState(false);
  const { data, error, loading, reload } = useAsync(() => wfapi.listExits({ status: status || null }), [status]);
  return (
    <div className="stack">
      <PageHead title={t('ex.title')} sub={t('ex.hint')} actions={<Button kind="primary" onClick={() => setOpen(true)}>{t('ex.start')}</Button>} />
      <div className="panel panel-pad row">
        <div className="field" style={{ minWidth: 200 }}><label htmlFor="ex-st">{t('c.status')}</label>
          <select id="ex-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="OPEN">{t('ex.filter_open')}</option><option value="COMPLETED">{t('ex.st_COMPLETED')}</option>
            <option value="CANCELLED">{t('ex.st_CANCELLED')}</option><option value="">{t('c.all')}</option>
          </select></div>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('ex.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('ex.type')}</th><th>{t('ex.last_day')}</th><th>{t('ex.clearance')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((x) => (
              <tr key={x.id}>
                <td data-label={t('c.employee')}><EmpCell r={x} /></td>
                <td data-label={t('ex.type')}>{t(`ex.t_${x.exit_type}` as Key)}<span className="sub">{t('ex.notice_days', { n: x.notice_days })}{x.pay_in_lieu ? ` · ${t('ex.pay_in_lieu')}` : ''}</span></td>
                <td data-label={t('ex.last_day')} className="num">{fmtDate(x.last_working_date)}</td>
                <td data-label={t('ex.clearance')}><span className="num">{t('ex.steps', { d: x.done ?? 0, n: x.total ?? 0 })}</span>
                  <progress max={Math.max(x.total ?? 0, 1)} value={x.done ?? 0} aria-label={t('ex.steps', { d: x.done ?? 0, n: x.total ?? 0 })} /></td>
                <td data-label={t('c.status')}><ExitBadge s={x.status} /></td>
                <td className="r"><Link className="btn btn-sm" to={`/exits/${x.id}`}>{t('sap.open')}</Link></td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <StartExitDialog open={open} onClose={() => setOpen(false)} />
    </div>
  );
}

function StartExitDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t, tk } = useI18n();
  const nav = useNavigate();
  const { busy, run } = useAction();
  const pol = useAsync(() => (open ? wfapi.policies() : Promise.resolve(null)), [open]);
  const [f, setF] = useState({ employee_id: null as string | null, label: '', exit_type: '' as ExitType | '', notice_given_on: '', last_working_date: '', pay_in_lieu: false, reason: '', non_compete_months: '0' });
  const [emp, setEmp] = useState<ExitPreview | null>(null);
  useEffect(() => { if (open) { setF({ employee_id: null, label: '', exit_type: '', notice_given_on: todayMuscat(), last_working_date: '', pay_in_lieu: false, reason: '', non_compete_months: '0' }); setEmp(null); } }, [open]);
  useEffect(() => {
    if (!f.employee_id) { setEmp(null); return; }
    let alive = true;
    wfapi.exitPreview(f.employee_id).then((x) => { if (alive) setEmp(x); }).catch(() => { if (alive) setEmp(null); });
    return () => { alive = false; };
  }, [f.employee_id]);
  const minDays = emp?.min_notice_days ?? pol.data?.notice_monthly_days ?? 30;
  const nc = f.exit_type ? noticeCheck({ type: f.exit_type, given: f.notice_given_on, last: f.last_working_date, minDays, payInLieu: f.pay_in_lieu, onProbation: emp?.status === 'PROBATION' }) : null;
  const ncMax = pol.data?.non_compete_max_months ?? 24;
  const submit = async () => {
    const r = await run(() => wfapi.startExit({ employee_id: f.employee_id, exit_type: f.exit_type, notice_given_on: f.notice_given_on, last_working_date: f.last_working_date,
      pay_in_lieu: f.pay_in_lieu, reason: f.reason || null, non_compete_months: Number(f.non_compete_months) || 0 }), t('ex.started'));
    if (r) { onClose(); nav(`/exits/${r.id}`); }
  };
  return (
    <Modal open={open} title={t('ex.start')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!f.employee_id || !!emp?.open_exit || !f.exit_type || !f.last_working_date || !!nc?.short || Number(f.non_compete_months) > ncMax
          || (f.exit_type === 'TERMINATION' && f.reason.trim().length < 15)} onClick={() => void submit()}>{t('ex.start')}</Button></>}>
      <div className="stack">
        <EmployeePicker label={t('c.employee')} value={f.employee_id} valueLabel={f.label} onChange={(id, l) => setF({ ...f, employee_id: id, label: l ?? '' })} />
        {emp && <div className="muted">{tk(`st.${emp.status}`, emp.status)}{emp.contract_end ? ` · ${t('co.end')} ${fmtDate(emp.contract_end)}` : ''}
          {emp.open_assets > 0 ? ` · ${t('ex.assets_out', { n: emp.open_assets })}` : ''}</div>}
        {emp?.open_exit && <div className="note note-warn"><Link to={`/exits/${emp.open_exit}`}>{t('ex.st_OPEN')}</Link></div>}
        <div className="grid-3">
          <Select label={t('ex.type')} required value={f.exit_type} onChange={(e) => {
            const ty = e.target.value as ExitType;
            setF({ ...f, exit_type: ty, last_working_date: f.last_working_date || (f.notice_given_on && (ty === 'RESIGNATION' || ty === 'TERMINATION') ? addDays(f.notice_given_on, minDays) : f.last_working_date) });
          }}>
            <option value="">{t('c.select')}</option>
            {EXIT_TYPES.map((x) => <option key={x} value={x}>{t(`ex.t_${x}` as Key)}</option>)}
          </Select>
          <Input label={t('ex.notice_given')} type="date" ltr value={f.notice_given_on} onChange={(e) => setF({ ...f, notice_given_on: e.target.value })} />
          <Input label={t('ex.last_day')} type="date" ltr required min={f.notice_given_on} value={f.last_working_date} onChange={(e) => setF({ ...f, last_working_date: e.target.value })} />
        </div>
        {f.exit_type && (f.exit_type === 'RESIGNATION' || f.exit_type === 'TERMINATION') && <div className={`note${nc?.short ? ' note-bad' : ''}`}>
          {t('ex.min_notice', { n: minDays })}{nc && f.last_working_date ? ` ${t('ex.notice_days', { n: nc.days })}.` : ''}
          {nc?.short && <> {t('ex.short', { d: nc.days, n: minDays })}</>}
          {pol.data && <div className="muted">{pol.data.notice_legal_basis}</div>}
        </div>}
        {(f.exit_type === 'RESIGNATION' || f.exit_type === 'TERMINATION') && <Check label={t('ex.pay_in_lieu')} checked={f.pay_in_lieu} onChange={(v) => setF({ ...f, pay_in_lieu: v })} />}
        <Textarea label={t('ex.reason')} required={f.exit_type === 'TERMINATION'} value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} />
        <Input label={t('ex.non_compete', { n: ncMax })} type="number" min={0} max={ncMax} ltr value={f.non_compete_months}
          hint={f.non_compete_months !== '0' && f.last_working_date ? `${fmtDate(f.last_working_date)} – ${fmtDate(addMonthsIso(f.last_working_date, Number(f.non_compete_months) || 0))}` : pol.data?.non_compete_legal_basis}
          error={Number(f.non_compete_months) > ncMax ? t('ex.non_compete', { n: ncMax }) : null}
          onChange={(e) => setF({ ...f, non_compete_months: e.target.value })} />
      </div>
    </Modal>
  );
}
