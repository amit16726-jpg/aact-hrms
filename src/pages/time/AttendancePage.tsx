import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { tapi, type AttDay, type Correction } from '../../lib/api_time';
import { useI18n } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, DateText, Empty, ErrorNote, Loading, Tabs, useAction, useAsync, useConfirm } from '../../components/ui';
import { MasterSelect } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { AttBadge, CorrectionDialog, EmpCell, EntitySelect, MonthGrid, MonthPicker, OvertimeDialog, PersonChooser, ReqBadge, useEntity } from '../../components/time';
import { addDays, fmtDateTime, fmtDuration, monthOf, todayMuscat } from '../../lib/format';
import { downloadCsv } from '../../lib/csv';

type TabId = 'day' | 'month' | 'employee' | 'corrections';

export default function AttendancePage() {
  const { t } = useI18n();
  const { can, me } = useSession();
  const [params, setParams] = useSearchParams();
  const wide = can('ATT_READ') || !!me?.is_manager;
  const tab = (params.get('tab') ?? (wide ? 'day' : 'employee')) as TabId;
  const setTab = (v: TabId) => { const p = new URLSearchParams(params); p.set('tab', v); setParams(p, { replace: true }); };
  const [corr, setCorr] = useState<{ emp?: string | null; date?: string | null } | null>(null);
  const [ot, setOt] = useState<{ emp?: string | null; date?: string | null } | null>(null);
  const [bump, setBump] = useState(0);
  const refresh = () => setBump((x) => x + 1);

  const tabs: { id: TabId; label: string }[] = wide
    ? [{ id: 'day', label: t('att.tab_day') }, { id: 'month', label: t('att.tab_month') }, { id: 'employee', label: t('att.tab_employee') },
      { id: 'corrections', label: t('att.tab_corrections') }]
    : [{ id: 'employee', label: t('att.my_title') }, { id: 'corrections', label: t('att.tab_corrections') }];

  return (
    <div className="stack">
      <PageHead title={t('att.title')} actions={<>
        <Button onClick={() => setCorr({})}>{t('att.request_correction')}</Button>
        <Button onClick={() => setOt({})}>{t('att.request_overtime')}</Button>
      </>} />
      <Tabs tabs={tabs} value={tabs.some((x) => x.id === tab) ? tab : tabs[0].id} onChange={setTab} label={t('att.title')} />
      {tab === 'day' && wide && <DayTab key={bump} onCorrect={(emp, date) => setCorr({ emp, date })} />}
      {tab === 'month' && wide && <MonthTab key={bump} onOpen={(emp, month) => { const p = new URLSearchParams(params); p.set('tab', 'employee'); p.set('emp', emp); p.set('month', month); setParams(p, { replace: true }); }} />}
      {(tab === 'employee' || !tabs.some((x) => x.id === tab)) && <EmployeeTab key={bump} onCorrect={(emp, date) => setCorr({ emp, date })} onOvertime={(emp, date) => setOt({ emp, date })} />}
      {tab === 'corrections' && <CorrectionsTab key={bump} />}
      <CorrectionDialog open={!!corr} employeeId={corr?.emp} date={corr?.date} onClose={() => setCorr(null)} onDone={refresh} />
      <OvertimeDialog open={!!ot} employeeId={ot?.emp} date={ot?.date} onClose={() => setOt(null)} onDone={refresh} />
    </div>
  );
}

// ---------------------------------------------------------------------------
function DayTab({ onCorrect }: { onCorrect: (emp: string, date: string) => void }) {
  const { t, L, tk } = useI18n();
  const { can } = useSession();
  const [entity, setEntity] = useEntity();
  const [date, setDate] = useState(addDays(todayMuscat(), 0));
  const [status, setStatus] = useState('');
  const [dep, setDep] = useState<string | null>(null);
  const { busy, run } = useAction();
  const { data, error, loading, reload } = useAsync(() => tapi.attendanceDay({ date, entity_id: entity || null, department_id: dep, status: status || null }), [date, entity, dep, status]);
  const exportCsv = () => data && downloadCsv(`attendance-${date}.csv`,
    [t('emp.no'), t('emp.name'), t('c.department'), t('att.shift'), t('att.scheduled'), t('att.in'), t('att.out'), t('att.worked'), t('att.late'), t('c.status')],
    data.rows.map((r) => [r.employee_no, L(r.full_name_en, r.full_name_ar), L(r.department_en, r.department_ar), r.shift_code,
      r.sched_start ? `${r.sched_start}–${r.sched_end}` : '', r.first_in, r.last_out, fmtDuration(r.worked_minutes), r.late_minutes || '', tk(`ast.${r.status}`)]));
  const c = data?.counts;
  return (
    <div className="stack">
      <div className="panel panel-pad row" style={{ gap: 16, alignItems: 'flex-end' }}>
        <EntitySelect value={entity} onChange={setEntity} />
        <div className="field"><label htmlFor="ad-date">{t('att.date')}</label>
          <input id="ad-date" type="date" className="input ltr" value={date} max={todayMuscat()} onChange={(e) => e.target.value && setDate(e.target.value)} /></div>
        <div style={{ minWidth: 220 }}><MasterSelect kind="department" entityId={entity} label={t('c.department')} value={dep} onChange={setDep} /></div>
        <div className="field" style={{ minWidth: 180 }}><label htmlFor="ad-st">{t('c.status')}</label>
          <select id="ad-st" className="select" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">{t('att.all_statuses')}</option>
            {['EXCEPTION', 'PRESENT', 'LATE', 'ABSENT', 'MISSING_PUNCH', 'LEAVE', 'HOLIDAY', 'REST', 'NO_SHIFT'].map((s) => <option key={s} value={s}>{tk(`ast.${s}`)}</option>)}
          </select></div>
        <span className="spacer" />
        {can('ATT_WRITE') && <Button busy={busy} onClick={async () => {
          const r = await run(() => tapi.recompute({ from: addDays(date, -6), to: date, entity_id: entity || null }));
          if (r) { void reload(); }
        }}>{t('att.recompute')}</Button>}
        <Button onClick={exportCsv} disabled={!data?.rows.length}>{t('c.export')}</Button>
      </div>
      {c && (
        <div className="figures" role="list">
          <div className="figure" role="listitem"><b className="num">{c.present}</b><span>{t('att.present')}</span></div>
          <div className="figure" role="listitem"><b className="num" style={{ color: c.absent ? 'var(--expired)' : undefined }}>{c.absent}</b><span>{t('att.absent')}</span></div>
          <div className="figure" role="listitem"><b className="num" style={{ color: c.missing ? 'var(--expired)' : undefined }}>{c.missing}</b><span>{t('att.missing')}</span></div>
          <div className="figure" role="listitem"><b className="num" style={{ color: c.late ? 'var(--soon)' : undefined }}>{c.late}</b><span>{t('att.late')}</span></div>
          <div className="figure" role="listitem"><b className="num">{c.leave}</b><span>{t('att.leave')}</span></div>
          <div className="figure" role="listitem"><b className="num">{c.off}</b><span>{t('att.off')}</span></div>
        </div>
      )}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.rows.length ? <Empty>{t('att.no_rows')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('att.shift')}</th><th>{t('att.in')}</th><th>{t('att.out')}</th>
              <th className="r">{t('att.worked')}</th><th className="r">{t('att.late')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.rows.map((r) => (
              <tr key={r.employee_id}>
                <td data-label={t('c.employee')}><EmpCell r={r} tab="time" />{r.department_en && <span className="sub">{L(r.department_en, r.department_ar)}</span>}</td>
                <td data-label={t('att.shift')}>{r.shift_code ?? '—'}{r.sched_start && <span className="sub num">{r.sched_start}–{r.sched_end}</span>}</td>
                <td data-label={t('att.in')} className="num">{r.first_in ?? '—'}</td>
                <td data-label={t('att.out')} className="num">{r.last_out ?? '—'}</td>
                <td data-label={t('att.worked')} className="r num">{fmtDuration(r.worked_minutes)}</td>
                <td data-label={t('att.late')} className="r num">{r.late_minutes ? fmtDuration(r.late_minutes) : '—'}</td>
                <td data-label={t('c.status')}><AttBadge status={r.status} late={r.late_minutes} />
                  {r.status === 'LEAVE' && <span className="sub">{L(r.leave_name_en, r.leave_name_ar)}</span>}
                  {r.holiday_en && <span className="sub">{L(r.holiday_en, r.holiday_ar)}</span>}
                  {r.pending_correction && <span className="sub">{t('att.pending_correction')}</span>}</td>
                <td className="r">{!r.locked && (r.status === 'ABSENT' || r.status === 'MISSING_PUNCH' || r.late_minutes > 0) &&
                  <Button small onClick={() => onCorrect(r.employee_id, r.work_date)}>{t('att.request_correction')}</Button>}</td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
function MonthTab({ onOpen }: { onOpen: (emp: string, month: string) => void }) {
  const { t, L } = useI18n();
  const [entity, setEntity] = useEntity();
  const [month, setMonth] = useState(monthOf(todayMuscat()));
  const [dep, setDep] = useState<string | null>(null);
  const { data, error, loading, reload } = useAsync(() => tapi.attendanceGrid({ month, entity_id: entity || null, department_id: dep }), [month, entity, dep]);
  const lines = useMemo(() => (data?.rows ?? []).map((r) => ({
    key: r.employee_id,
    label: <button type="button" className="linklike" onClick={() => onOpen(r.employee_id, month)}>{L(r.full_name_en, r.full_name_ar)}</button>,
    sub: r.employee_no,
    cells: Object.fromEntries(Object.entries(r.days ?? {}).map(([d, code]) => [Number(d), { code }])),
    tail: `${r.absent}/${r.late}`,
  })), [data, L, onOpen, month]);
  return (
    <div className="stack">
      <div className="panel panel-pad row" style={{ gap: 16, alignItems: 'flex-end' }}>
        <EntitySelect value={entity} onChange={setEntity} />
        <MonthPicker value={month} onChange={setMonth} />
        <div style={{ minWidth: 220 }}><MasterSelect kind="department" entityId={entity} label={t('c.department')} value={dep} onChange={setDep} /></div>
        {data?.locked && <Badge tone="info">{t('att.locked')}</Badge>}
      </div>
      <div className="panel panel-pad">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !lines.length ? <Empty>{t('att.no_rows')}</Empty> :
          <MonthGrid month={month} lines={lines} legend={['P', 'L', 'A', 'M', 'V', 'H', 'R', 'N']} tailHead={`${t('att.absent')}/${t('att.late')}`} />}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
function EmployeeTab({ onCorrect, onOvertime }: { onCorrect: (emp: string, date: string) => void; onOvertime: (emp: string, date: string) => void }) {
  const { t, L, tk } = useI18n();
  const { me, can } = useSession();
  const [params, setParams] = useSearchParams();
  const wide = can('ATT_READ') || !!me?.is_manager;
  const emp = params.get('emp') ?? (wide ? null : me?.employee_id ?? null);
  const month = params.get('month') ?? monthOf(todayMuscat());
  const set = (k: string, v: string | null) => { const p = new URLSearchParams(params); if (v) p.set(k, v); else p.delete(k); setParams(p, { replace: true }); };
  const { data, error, loading, reload } = useAsync(() => (emp ? tapi.attendanceMonth(emp, month) : Promise.resolve(null)), [emp, month]);
  useEffect(() => { if (!wide && me?.employee_id && !params.get('emp')) set('emp', me.employee_id); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [wide, me?.employee_id]);
  if (!wide && !me?.employee_id) return <Empty>{t('lv.mine_none')}</Empty>;
  const tot = data?.totals;
  return (
    <div className="stack">
      <div className="panel panel-pad row" style={{ gap: 16, alignItems: 'flex-end' }}>
        {wide && <div style={{ minWidth: 280 }}><PersonChooser label={t('c.employee')} value={emp} onChange={(v) => set('emp', v)} /></div>}
        <MonthPicker value={month} onChange={(v) => set('month', v)} />
        {data && <div className="muted">{data.employee_no} — {L(data.full_name_en, data.full_name_ar)}{data.shift && <> · {t('att.shift')}: {data.shift.code} <span className="num">{data.shift.start_time}–{data.shift.end_time}</span></>}</div>}
        {data?.locked && <Badge tone="info">{t('att.locked')}</Badge>}
      </div>
      {!emp ? <Empty>{t('att.choose_employee')}</Empty> : (
        <>
          <ErrorNote error={error} onRetry={reload} />
          {tot && (
            <div className="figures" role="list">
              <div className="figure" role="listitem"><b className="num">{tot.scheduled_days}</b><span>{t('att.scheduled_days')}</span></div>
              <div className="figure" role="listitem"><b className="num">{tot.present}</b><span>{t('att.present')}</span></div>
              <div className="figure" role="listitem"><b className="num">{tot.absent}</b><span>{t('att.absent')}</span></div>
              <div className="figure" role="listitem"><b className="num">{tot.missing}</b><span>{t('att.missing')}</span></div>
              <div className="figure" role="listitem"><b className="num">{tot.late_count}</b><span>{t('att.late_count')}</span></div>
              <div className="figure" role="listitem"><b className="num">{tot.leave_days}</b><span>{t('att.leave_days')}</span></div>
              <div className="figure" role="listitem"><b className="num">{fmtDuration(tot.worked_minutes)}</b><span>{t('att.worked_hours')}</span></div>
            </div>
          )}
          <div className="panel">
            {loading && !data ? <Loading /> : !data?.days.length ? <Empty>{t('att.no_rows')}</Empty> : (
              <div className="table-wrap"><table className="t cards">
                <thead><tr><th>{t('att.date')}</th><th>{t('att.shift')}</th><th>{t('att.in')}</th><th>{t('att.out')}</th>
                  <th className="r">{t('att.worked')}</th><th className="r">{t('att.late')}</th><th className="r">{t('att.early')}</th>
                  <th className="r">{t('att.overtime')}</th><th>{t('c.status')}</th><th /></tr></thead>
                <tbody>{data.days.map((d: AttDay) => (
                  <tr key={d.work_date}>
                    <td data-label={t('att.date')}><DateText v={d.work_date} /><span className="sub">{tk(`wd.${new Date(d.work_date + 'T00:00:00Z').getUTCDay() || 7}`)}{d.is_ramadan ? ` · ${t('att.ramadan')}` : ''}</span></td>
                    <td data-label={t('att.shift')}>{d.shift_code ?? '—'}{d.sched_start && <span className="sub num">{d.sched_start}–{d.sched_end}</span>}</td>
                    <td data-label={t('att.in')} className="num">{d.first_in ?? '—'}</td>
                    <td data-label={t('att.out')} className="num">{d.last_out ?? '—'}</td>
                    <td data-label={t('att.worked')} className="r num">{fmtDuration(d.worked_minutes)}</td>
                    <td data-label={t('att.late')} className="r num">{d.late_minutes ? fmtDuration(d.late_minutes) : '—'}</td>
                    <td data-label={t('att.early')} className="r num">{d.early_minutes ? fmtDuration(d.early_minutes) : '—'}</td>
                    <td data-label={t('att.overtime')} className="r num">{d.overtime_minutes ? fmtDuration(d.overtime_minutes) : '—'}</td>
                    <td data-label={t('c.status')}><AttBadge status={d.status} late={d.late_minutes} />
                      {d.status === 'LEAVE' && <span className="sub">{L(d.leave_name_en, d.leave_name_ar)}</span>}
                      {d.holiday_en && <span className="sub">{L(d.holiday_en, d.holiday_ar)}</span>}
                      {d.worked_off_day && <span className="sub">{t('att.worked_off')}</span>}
                      {d.pending_correction && <span className="sub">{t('att.pending_correction')}</span>}</td>
                    <td className="r">{!d.locked && (
                      <div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                        {(d.status === 'ABSENT' || d.status === 'MISSING_PUNCH' || d.late_minutes > 0) && !d.pending_correction &&
                          <Button small onClick={() => onCorrect(data.employee_id, d.work_date)}>{t('att.request_correction')}</Button>}
                        {(d.status === 'PRESENT' || d.worked_off_day) && <Button small kind="ghost" onClick={() => onOvertime(data.employee_id, d.work_date)}>{t('att.request_overtime')}</Button>}
                      </div>)}</td>
                  </tr>))}
                </tbody></table></div>
            )}
          </div>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
export function CorrectionsTab({ employeeId }: { employeeId?: string }) {
  const { t, L } = useI18n();
  const [status, setStatus] = useState('PENDING');
  const { data, error, loading, reload } = useAsync(() => tapi.listCorrections({ status: status || null, employee_id: employeeId ?? null }), [status, employeeId]);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const decide = async (c: Correction, approve: boolean) => {
    const note = await confirm.ask({ title: `${L(c.full_name_en, c.full_name_ar)} — ${c.work_date}`, reason: approve ? 'optional' : 'required',
      reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    if (await run(() => tapi.decideCorrection(c.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'))) void reload();
  };
  return (
    <div className="panel">
      <div className="panel-head">
        <h2>{t('cor.title')}</h2>
        <select className="select" style={{ width: 200 }} value={status} onChange={(e) => setStatus(e.target.value)} aria-label={t('c.status')}>
          <option value="">{t('c.all')}</option>
          {['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'].map((s) => <option key={s} value={s}>{t(`rst.${s}` as 'rst.PENDING')}</option>)}
        </select>
      </div>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('cor.none')}</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('c.employee')}</th><th>{t('att.date')}</th><th>{t('cor.in_time')}</th><th>{t('cor.out_time')}</th>
            <th>{t('c.reason')}</th><th>{t('c.status')}</th><th>{t('c.by')}</th><th /></tr></thead>
          <tbody>{data.map((c) => (
            <tr key={c.id}>
              <td data-label={t('c.employee')}><EmpCell r={c} tab="time" /></td>
              <td data-label={t('att.date')}><DateText v={c.work_date} /></td>
              <td data-label={t('cor.in_time')} className="num">{c.punch_in ?? '—'}</td>
              <td data-label={t('cor.out_time')} className="num">{c.punch_out ?? '—'}{c.out_next_day ? ' +1' : ''}</td>
              <td data-label={t('c.reason')}>{c.reason}{c.decision_note && <span className="sub">{c.decision_note}</span>}</td>
              <td data-label={t('c.status')}><ReqBadge status={c.status} /></td>
              <td data-label={t('c.by')}>{c.requested_by_name}<span className="sub">{fmtDateTime(c.requested_at)}</span></td>
              <td className="r"><div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                {c.can_decide && <><Button small kind="primary" busy={busy} onClick={() => void decide(c, true)}>{t('c.approve')}</Button>
                  <Button small kind="danger" busy={busy} onClick={() => void decide(c, false)}>{t('c.reject')}</Button></>}
                {c.can_cancel && <Button small busy={busy} onClick={async () => { if (await run(() => tapi.cancelCorrection(c.id))) void reload(); }}>{t('cor.withdraw')}</Button>}
              </div></td>
            </tr>))}
          </tbody></table></div>
      )}
      {confirm.node}
    </div>
  );
}
