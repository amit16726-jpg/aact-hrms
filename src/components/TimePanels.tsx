import { Link } from 'react-router-dom';
import { tapi } from '../lib/api_time';
import { useI18n } from '../i18n';
import { useAsync } from './ui';
import { AttBadge, EmpCell, ReqBadge } from './time';
import { fmtDate, fmtDuration } from '../lib/format';

/** Dashboard panels for Phase 2 (attendance today, my leave, away list, tasks). Hidden quietly on error. */
export function TimePanels() {
  const { t, L } = useI18n();
  const { data: d } = useAsync(() => tapi.timeDashboard(), []);
  if (!d) return null;
  const tk = d.tasks;
  const taskLines = ([['leave', 'dt.tasks_leave', '/approvals'], ['corrections', 'dt.tasks_corrections', '/approvals'], ['overtime', 'dt.tasks_overtime', '/approvals'],
    ['adjustments', 'dt.tasks_adjustments', '/approvals'], ['rules', 'dt.tasks_rules', '/approvals']] as const).filter(([k]) => tk[k] > 0);

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
          </section>
        )}
        {taskLines.length > 0 && (
          <section className="panel panel-pad stack">
            <h2>{t('dt.tasks')}</h2>
            <ul style={{ margin: 0, paddingInlineStart: 18 }}>{taskLines.map(([k, key, to]) => <li key={k}><Link to={to}>{t(key, { n: tk[k] })}</Link></li>)}</ul>
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
