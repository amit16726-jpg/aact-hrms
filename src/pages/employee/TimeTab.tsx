import { Link } from 'react-router-dom';
import { tapi } from '../../lib/api_time';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Empty, ErrorNote, Loading, useAsync } from '../../components/ui';
import { BalanceCards, LeaveList } from '../time/LeavePage';
import { fmtDate, fmtDuration, todayMuscat } from '../../lib/format';

/** Employee file → "Time and leave": current shift, this month's attendance, balances and leave requests. */
export function TimeTab({ employeeId }: { employeeId: string }) {
  const { t, L } = useI18n();
  const { can } = useSession();
  const today = todayMuscat();
  const month = today.slice(0, 7);
  const bal = useAsync(() => tapi.leaveBalances(employeeId), [employeeId]);
  const att = useAsync(() => tapi.attendanceMonth(employeeId, month), [employeeId, month]);
  const shifts = useAsync(() => tapi.listShiftAssignments({ employee_id: employeeId }), [employeeId]);
  const shown = (bal.data?.balances ?? []).filter((b) => ['ANNUAL', 'SICK'].includes(b.leave_type) || b.used > 0 || b.pending > 0);
  const cur = (shifts.data ?? []).find((s) => s.effective_from <= today && (!s.effective_to || s.effective_to >= today));
  const tot = att.data?.totals;
  return (
    <div className="stack" style={{ marginTop: 16 }}>
      <div className="grid-2" style={{ alignItems: 'start' }}>
        <section className="panel panel-pad stack">
          <h2>{t('et.shift')}</h2>
          <ErrorNote error={shifts.error} />
          {shifts.loading && !shifts.data ? <Loading /> : cur ? (
            <div><b className="num">{cur.shift_code}</b> — {L(cur.shift_name_en, cur.shift_name_ar)}
              <div className="muted">{t('c.from')} {fmtDate(cur.effective_from)}{cur.effective_to ? ` ${t('c.to')} ${fmtDate(cur.effective_to)}` : ''}</div></div>
          ) : <span className="muted">{t('et.no_shift')}</span>}
          {(shifts.data?.length ?? 0) > 1 && (
            <details><summary>{t('sh.history')}</summary>
              <ul style={{ margin: '6px 0 0', paddingInlineStart: 18 }}>{shifts.data!.map((s) => <li key={s.id} className="num">{s.shift_code}: {fmtDate(s.effective_from)} – {s.effective_to ? fmtDate(s.effective_to) : '…'}</li>)}</ul>
            </details>)}
          {can('ATT_WRITE') && <Link to="/time/shifts">{t('et.assign_shift')}</Link>}
        </section>
        <section className="panel panel-pad stack">
          <div className="row" style={{ justifyContent: 'space-between' }}><h2>{t('et.this_month')}</h2>
            <Link to={`/attendance?tab=employee&emp=${employeeId}&month=${month}`}>{t('tnav.attendance')}</Link></div>
          <ErrorNote error={att.error} />
          {att.loading && !att.data ? <Loading /> : tot ? (
            <dl className="kv">
              {([['att.scheduled_days', tot.scheduled_days], ['att.present', tot.present], ['att.absent', tot.absent], ['att.missing', tot.missing],
                ['att.leave_days', tot.leave_days], ['att.late_count', tot.late_count]] as [Key, number][]).map(([k, v]) => <div key={k}><dt>{t(k)}</dt><dd className="num">{v}</dd></div>)}
              <div><dt>{t('att.worked_hours')}</dt><dd className="num">{fmtDuration(tot.worked_minutes)}</dd></div>
            </dl>
          ) : <Empty>{t('att.no_rows')}</Empty>}
        </section>
      </div>
      <section className="panel">
        <div className="panel-head"><h2>{t('lv.my_balances')}</h2>
          {bal.data && <span className="muted">{t('lv.taken_24m')}: <b className="num">{bal.data.annual_taken_24m}</b></span>}</div>
        <div className="panel-body">
          <ErrorNote error={bal.error} onRetry={bal.reload} />
          {bal.loading && !bal.data ? <Loading /> : <BalanceCards balances={shown} today={today} />}
        </div>
      </section>
      <LeaveList scope="all" employeeId={employeeId} title={t('et.recent_leave')} onChange={() => void bal.reload()} />
    </div>
  );
}
