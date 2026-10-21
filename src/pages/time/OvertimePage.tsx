import { useState } from 'react';
import { tapi, type Overtime } from '../../lib/api_time';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, DateText, Empty, ErrorNote, Loading, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { EmpCell, OvertimeDialog, ReqBadge } from '../../components/time';
import { addDays, fmtDateTime, fmtDuration, todayMuscat } from '../../lib/format';
import { downloadCsv } from '../../lib/csv';

export default function OvertimePage() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const [status, setStatus] = useState('');
  const [from, setFrom] = useState(addDays(todayMuscat(), -60));
  const [to, setTo] = useState(addDays(todayMuscat(), 31));
  const [open, setOpen] = useState(false);
  const { data, error, loading, reload } = useAsync(() => tapi.listOvertime({ status: status || null, from, to }), [status, from, to]);
  const { busy, run } = useAction();
  const confirm = useConfirm();

  const decide = async (o: Overtime, approve: boolean) => {
    const note = await confirm.ask({ title: `${L(o.full_name_en, o.full_name_ar)} — ${o.work_date} ${o.start_time}–${o.end_time}`,
      reason: approve ? 'optional' : 'required', reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    if (await run(() => tapi.decideOvertime(o.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'))) void reload();
  };

  const exportCsv = () => data && downloadCsv(`overtime-${from}-${to}.csv`,
    [t('emp.no'), t('emp.name'), t('ot.work_date'), t('ot.start'), t('ot.end'), t('ot.kind'), t('ot.basis'), t('ot.minutes'), t('ot.night'),
      t('ot.pay_hours'), t('ot.pay_days'), t('ot.comp'), t('c.status')],
    data.map((o) => [o.employee_no, L(o.full_name_en, o.full_name_ar), o.work_date, o.start_time, o.end_time, t(`ot.k_${o.day_kind}` as Key),
      o.basis, fmtDuration(o.minutes), fmtDuration(o.night_minutes), o.pay_hours, o.pay_days, t(`ot.comp_${o.comp_choice}` as Key), t(`rst.${o.status}` as Key)]));

  return (
    <div className="stack">
      <PageHead title={t('ot.title')} actions={<>
        <Button kind="primary" onClick={() => setOpen(true)}>{t('ot.new')}</Button>
        <Button onClick={exportCsv} disabled={!data?.length}>{t('c.export')}</Button>
      </>} />
      <div className="panel panel-pad row" style={{ gap: 16, alignItems: 'flex-end' }}>
        <div className="field"><label htmlFor="ot-from">{t('c.from')}</label><input id="ot-from" type="date" className="input ltr" value={from} onChange={(e) => e.target.value && setFrom(e.target.value)} /></div>
        <div className="field"><label htmlFor="ot-to">{t('c.to')}</label><input id="ot-to" type="date" className="input ltr" value={to} onChange={(e) => e.target.value && setTo(e.target.value)} /></div>
        <div className="field" style={{ minWidth: 200 }}><label htmlFor="ot-st">{t('c.status')}</label>
          <select id="ot-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">{t('c.all')}</option>
            {['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'].map((s) => <option key={s} value={s}>{t(`rst.${s}` as Key)}</option>)}
          </select></div>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('ot.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('ot.work_date')}</th><th>{t('ot.start')}–{t('ot.end')}</th><th>{t('ot.kind')}</th>
              <th className="r">{t('ot.minutes')}</th><th className="r">{t('ot.pay_hours')}</th><th>{t('c.reason')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((o) => (
              <tr key={o.id}>
                <td data-label={t('c.employee')}><EmpCell r={o} tab="time" /></td>
                <td data-label={t('ot.work_date')}><DateText v={o.work_date} /></td>
                <td data-label={`${t('ot.start')}–${t('ot.end')}`} className="num">{o.start_time}–{o.end_time}{o.end_next_day ? ' +1' : ''}
                  {o.night_minutes > 0 && <span className="sub">{t('ot.night')}: {fmtDuration(o.night_minutes)}</span>}</td>
                <td data-label={t('ot.kind')}>{t(`ot.k_${o.day_kind}` as Key)}
                  <span className="sub">{o.basis === 'CONSENT' ? t('ot.b_CONSENT') : <Badge tone={o.authority_notified ? 'ok' : 'warn'}>{o.authority_notified ? t('ot.notified') : t('ot.not_notified')}</Badge>}</span></td>
                <td data-label={t('ot.minutes')} className="r num">{fmtDuration(o.minutes)}</td>
                <td data-label={t('ot.pay_hours')} className="r num">{o.comp_choice === 'TIME_OFF' ? t('ot.comp_TIME_OFF') : o.day_kind === 'WORKDAY' ? o.pay_hours : `${o.pay_days} ${t('ot.pay_days')}`}</td>
                <td data-label={t('c.reason')}>{o.reason}{o.decision_note && <span className="sub">{o.decision_note}</span>}</td>
                <td data-label={t('c.status')}><ReqBadge status={o.status} /><span className="sub">{o.requested_by_name} · {fmtDateTime(o.requested_at)}</span></td>
                <td className="r"><div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  {o.can_decide && <><Button small kind="primary" busy={busy} onClick={() => void decide(o, true)}>{t('c.approve')}</Button>
                    <Button small kind="danger" busy={busy} onClick={() => void decide(o, false)}>{t('c.reject')}</Button></>}
                  {o.can_cancel && <Button small busy={busy} onClick={async () => { if (await run(() => tapi.cancelOvertime(o.id))) void reload(); }}>{t('ot.withdraw')}</Button>}
                  {o.basis !== 'CONSENT' && !o.authority_notified && can('ATT_WRITE') && o.status !== 'CANCELLED' && o.status !== 'REJECTED' &&
                    <Button small busy={busy} onClick={async () => { if (await run(() => tapi.setOvertimeNotified(o.id))) void reload(); }}>{t('ot.mark_notified')}</Button>}
                </div></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
      <OvertimeDialog open={open} onClose={() => setOpen(false)} onDone={() => void reload()} />
      {confirm.node}
    </div>
  );
}
