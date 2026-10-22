import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { papi, type PayrollRun } from '../../lib/api_pay';
import { useI18n } from '../../i18n';
import { useSession } from '../../lib/session';
import { Button, Empty, ErrorNote, Input, Loading, Modal, Select, useAction, useAsync } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { EntitySelect, useEntity } from '../../components/time';
import { OMR, PayGroupBadge, RunBadge, monthName } from '../../components/pay';
import { addMonths, todayMuscat } from '../../lib/format';

export default function PayrollPage() {
  const { t, lang } = useI18n();
  const { can } = useSession();
  const [entity, setEntity] = useEntity();
  const [year, setYear] = useState(Number(todayMuscat().slice(0, 4)));
  const { data, error, loading, reload } = useAsync(() => papi.listRuns(entity || null, year), [entity, year]);
  const [open, setOpen] = useState(false);
  const showGroup = can('MG_PAY') || (data ?? []).some((r) => r.pay_group === 'MG');
  return (
    <div className="stack">
      <PageHead title={t('pr.title')} sub={t('pr.chain')}
        actions={can('PAY_PREPARE') && <Button kind="primary" onClick={() => setOpen(true)}>{t('pr.new')}</Button>} />
      <div className="panel panel-pad row" style={{ alignItems: 'flex-end', gap: 8 }}>
        <EntitySelect value={entity} onChange={setEntity} />
        <Button onClick={() => setYear(year - 1)} aria-label={t('c.previous')}>‹</Button>
        <b className="num" style={{ padding: '8px 6px' }}>{year}</b>
        <Button onClick={() => setYear(year + 1)} aria-label={t('c.next')}>›</Button>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('pr.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('pr.month')}</th><th>{t('c.status')}</th><th className="r">{t('pr.employees')}</th><th className="r">{t('pr.gross')}</th>
              <th className="r">{t('pr.deductions')}</th><th className="r">{t('pr.net')}</th><th className="r">{t('pr.employer_cost')}</th><th>{t('pr.pay_date')}</th></tr></thead>
            <tbody>{data.map((r: PayrollRun) => (
              <tr key={r.id}>
                <td data-label={t('pr.month')}><Link to={`/payroll/${r.id}`}>{monthName(r.month, lang)}</Link>
                  <span className="sub">{r.entity_code}{showGroup && <> <PayGroupBadge group={r.pay_group} short /></>}</span></td>
                <td data-label={t('c.status')}><RunBadge status={r.status} />
                  {r.warning_count > 0 && r.status !== 'DRAFT' && <span className="sub">{t('pr.warnings')}: {r.warning_count}</span>}
                  {!r.attendance_locked && r.status === 'DRAFT' && <span className="sub bad-text">{t('pr.attendance_open')}</span>}</td>
                <td data-label={t('pr.employees')} className="r num">{r.totals.employees ?? '—'}</td>
                <td data-label={t('pr.gross')} className="r num">{OMR(r.totals.earnings)}</td>
                <td data-label={t('pr.deductions')} className="r num">{OMR(r.totals.deductions)}</td>
                <td data-label={t('pr.net')} className="r num"><b>{OMR(r.totals.net)}</b></td>
                <td data-label={t('pr.employer_cost')} className="r num">{OMR(r.totals.employer_cost)}</td>
                <td data-label={t('pr.pay_date')} className="num">{r.pay_date ?? '—'}</td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
      <NewRunDialog open={open} entity={entity} onClose={() => setOpen(false)} />
    </div>
  );
}

function NewRunDialog({ open, entity, onClose }: { open: boolean; entity: string; onClose: () => void }) {
  const { t } = useI18n();
  const nav = useNavigate();
  const { busy, run } = useAction();
  const [month, setMonth] = useState(addMonths(todayMuscat().slice(0, 7), -1));
  const [payDate, setPayDate] = useState('');
  const { can } = useSession();
  const [group, setGroup] = useState<'NMG' | 'MG'>('NMG');
  const submit = async () => {
    const r = await run(() => papi.createRun(entity, month, payDate || null, group));
    if (r) { onClose(); nav(`/payroll/${r.id}`); }
  };
  return (
    <Modal open={open} title={t('pr.new')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!month || !entity} onClick={() => void submit()}>{t('pr.create')}</Button></>}>
      <div className="form-grid">
        <Input label={t('pr.month')} type="month" ltr required value={month} max={todayMuscat().slice(0, 7)} onChange={(e) => setMonth(e.target.value)} />
        <Input label={t('pr.pay_date')} type="date" ltr value={payDate} onChange={(e) => setPayDate(e.target.value)} />
        {can('MG_PAY') && <>
          <Select label={t('pg.run_group')} value={group} onChange={(e) => setGroup(e.target.value as 'NMG' | 'MG')}>
            <option value="NMG">{t('pg.NMG')}</option><option value="MG">{t('pg.MG')}</option>
          </Select>
          <div className="muted" style={{ alignSelf: 'end' }}>{t('pg.run_hint')}</div>
        </>}
        <div className="span-2 muted">{t('pr.chain')}</div>
      </div>
    </Modal>
  );
}
