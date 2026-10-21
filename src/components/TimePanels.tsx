import { Link } from 'react-router-dom';
import { tapi } from '../lib/api_time';
import { useI18n, type Key } from '../i18n';
import { OMR, monthName } from './pay';
import { useAsync } from './ui';
import { AttBadge, EmpCell, ReqBadge } from './time';
import { fmtDate, fmtDuration } from '../lib/format';

/** Dashboard panels for Phase 2 (attendance today, my leave, away list, tasks). Hidden quietly on error. */
export function TimePanels() {
  const { t, L, lang } = useI18n();
  const { data: d } = useAsync(() => tapi.timeDashboard(), []);
  if (!d) return null;
  const tk = d.tasks;
  const taskLines = ([['leave', 'dt.tasks_leave', '/approvals'], ['corrections', 'dt.tasks_corrections', '/approvals'], ['overtime', 'dt.tasks_overtime', '/approvals'],
    ['adjustments', 'dt.tasks_adjustments', '/approvals'], ['rules', 'dt.tasks_rules', '/approvals'], ['payroll', 'pd.tasks_payroll', '/approvals'],
    ['loans', 'pd.tasks_loans', '/approvals'], ['pay_adjustments', 'pd.tasks_pay_adjustments', '/approvals'],
    ['settlements', 'pd.tasks_settlements', '/approvals'], ['changes', 'sd.tasks_changes', '/requests'],
    ['letters', 'sd.tasks_letters', '/requests?tab=letters'], ['requisitions', 'rd.tasks_requisitions', '/approvals'],
    ['offers', 'rd.tasks_offers', '/approvals'], ['interviews', 'rd.tasks_interviews', '/recruitment?tab=interviews']] as const).filter(([k]) => (tk[k] ?? 0) > 0);

  return (
    <div className="stack">
      {d.today && (
        <section className="panel">
          <div className="panel-head"><h2>{t(d.today.scope === 'ALL' ? 'dt.today' : 'dt.team_today')} · <span className="muted">{fmtDate(d.today.date)}</span></h2>
            <Link to="/attendance">{t('tnav.attendance')}</Link></div>
          <div className="figures panel-pad" role="list">
            <div className="figure" role="listitem"><b className="num ok-text">{d.today.present}</b><span>{t('att.present')}</span></div>
            <div className="figure" role="listitem"><b className="num">{d.today.late}</b><span>{t('att.late')}</span></div>
            <div className="figure" role="listitem"><b className={`num${d.today.absent ? ' bad-text' : ''}`}>{d.today.absent}</b><span>{t('att.absent')}</span></div>
            <div className="figure" role="listitem"><b className={`num${d.today.missing ? ' bad-text' : ''}`}>{d.today.missing}</b><span>{t('att.missing')}</span></div>
            <div className="figure" role="listitem"><b className="num">{d.today.leave}</b><span>{t('att.leave')}</span></div>
            <div className="figure" role="listitem"><b className="num">{d.today.off}</b><span>{t('att.off')}</span></div>
          </div>
        </section>
      )}
      <div className="grid-2" style={{ alignItems: 'start' }}>
        {d.mine && (
          <section className="panel panel-pad stack">
            <div className="row" style={{ justifyContent: 'space-between' }}><h2>{t('dt.my_leave')}</h2><Link to="/leave">{t('tnav.leave')}</Link></div>
            <div>{t('dt.mine_today')}: {d.mine.today ? <><AttBadge status={d.mine.today.status} late={d.mine.today.late_minutes} />
              {d.mine.today.first_in && <span className="num"> {d.mine.today.first_in}{d.mine.today.last_out ? `–${d.mine.today.last_out}` : ''} ({fmtDuration(d.mine.today.worked_minutes)})</span>}</>
              : <span className="muted">{t('dt.no_punch_today')}</span>}</div>
            {d.mine.annual && d.mine.annual.available !== null && <div><b className="num">{t('dt.annual_left', { n: d.mine.annual.available })}</b></div>}
            {d.mine.sick && <div className="muted">{t('dt.sick_used', { n: d.mine.sick.used })}</div>}
            {d.mine.next_leave && <div>{t('dt.next_leave')}: {L(d.mine.next_leave.name_en, d.mine.next_leave.name_ar)} · <span className="num">{fmtDate(d.mine.next_leave.start_date)} – {fmtDate(d.mine.next_leave.end_date)}</span> <ReqBadge status={d.mine.next_leave.status} /></div>}
            {d.mine.pending > 0 && <div className="muted">{t('dt.waiting_requests', { n: d.mine.pending })}</div>}
            {d.mine.last_payslip && <div><Link to={`/payslips/${d.mine.last_payslip.id}`}>{t('pd.my_last', { m: monthName(d.mine.last_payslip.month, lang) })}</Link>
              {' '}<b className="num">OMR {OMR(d.mine.last_payslip.net)}</b></div>}
            {(d.mine.requests_open ?? 0) > 0 && <div><Link to="/me?tab=requests">{t('sd.my_requests', { n: d.mine.requests_open ?? 0 })}</Link></div>}
            {(d.mine.letters_ready ?? 0) > 0 && <div><Link to="/me?tab=letters">{t('sd.letters_ready', { n: d.mine.letters_ready ?? 0 })}</Link></div>}
          </section>
        )}
        {d.payroll && (
          <section className="panel panel-pad stack">
            <div className="row" style={{ justifyContent: 'space-between' }}><h2>{t('pd.payroll')}</h2><Link to="/payroll">{t('pnav.runs')}</Link></div>
            <div><Link to={`/payroll/${d.payroll.id}`}>{t('pd.last_run', { m: monthName(d.payroll.month, lang), s: t(`prs.${d.payroll.status}` as Key) })}</Link></div>
            {d.payroll.totals.net !== undefined && <div className="tile-row">
              <div className="tile"><span>{t('pr.employees')}</span><b>{d.payroll.totals.employees ?? 0}</b></div>
              <div className="tile"><span>{t('pr.net')}</span><b>{OMR(d.payroll.totals.net)}</b></div>
              <div className="tile"><span>{t('pr.employer_cost')}</span><b>{OMR(d.payroll.totals.employer_cost)}</b></div>
            </div>}
          </section>
        )}
        {d.recruitment && (
          <section className="panel panel-pad stack">
            <div className="row" style={{ justifyContent: 'space-between' }}><h2>{t('rd.recruitment')}</h2><Link to="/recruitment">{t('rnav.recruitment')}</Link></div>
            <div className="tile-row">
              <div className="tile"><span>{t('rd.open_positions')}</span><b>{d.recruitment.open_positions}</b></div>
              <div className="tile"><span>{t('rd.in_pipeline')}</span><b>{d.recruitment.in_pipeline}</b></div>
              <div className="tile"><span>{t('rd.joining_30')}</span><b>{d.recruitment.joining_30}</b></div>
            </div>
            {d.recruitment.onboarding_overdue > 0 && <div><Link className="bad-text" to="/recruitment?tab=onboarding">{t('rd.onboarding_overdue')}: {d.recruitment.onboarding_overdue}</Link></div>}
            {d.recruitment.probation_due_30 > 0 && <div><Link to="/probation">{t('rd.probation_30')}: {d.recruitment.probation_due_30}</Link></div>}
          </section>
        )}
        {taskLines.length > 0 && (
          <section className="panel panel-pad stack">
            <h2>{t('dt.tasks')}</h2>
            <ul style={{ margin: 0, paddingInlineStart: 18 }}>{taskLines.map(([k, key, to]) => <li key={k}><Link to={to}>{t(key, { n: tk[k] ?? 0 })}</Link></li>)}</ul>
          </section>
        )}
        {d.away_next_14 && (
          <section className="panel">
            <div className="panel-head"><h2>{t('dt.away')}</h2><Link to="/leave?tab=calendar">{t('lv.tab_calendar')}</Link></div>
            {!d.away_next_14.length ? <div className="panel-pad muted">{t('dt.nobody_away')}</div> : (
              <div className="table-wrap"><table className="t">
                <tbody>{d.away_next_14.slice(0, 12).map((a, i) => (
                  <tr key={`${a.employee_id}-${i}`}><td><EmpCell r={a} tab="time" /></td><td>{L(a.name_en, a.name_ar)}</td>
                    <td className="num">{fmtDate(a.start_date)} – {fmtDate(a.end_date)}</td><td><ReqBadge status={a.status} /></td></tr>))}
                </tbody></table></div>
            )}
          </section>
        )}
      </div>
    </div>
  );
}
