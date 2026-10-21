import { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { tapi, type Balance, type LeaveReq } from '../../lib/api_time';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, DateText, Empty, ErrorNote, Loading, Modal, Select, Tabs, useAction, useAsync, useConfirm } from '../../components/ui';
import { MasterSelect } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { AttachDialog, balanceText, EmpCell, EntitySelect, LeaveDialog, MonthGrid, MonthPicker, ReqBadge, useEntity } from '../../components/time';
import { fmtDate, fmtDateTime, monthOf, todayMuscat } from '../../lib/format';
import { downloadCsv } from '../../lib/csv';

type TabId = 'mine' | 'requests' | 'calendar';

export default function LeavePage() {
  const { t } = useI18n();
  const { me, can } = useSession();
  const [params, setParams] = useSearchParams();
  const wide = can('LEAVE_READ') || !!me?.is_manager;
  const tabs: { id: TabId; label: string }[] = [
    ...(me?.employee_id ? [{ id: 'mine' as TabId, label: t('lv.tab_mine') }] : []),
    ...(wide ? [{ id: 'requests' as TabId, label: t('lv.tab_requests') }, { id: 'calendar' as TabId, label: t('lv.tab_calendar') }] : []),
  ];
  const tab = (params.get('tab') as TabId) ?? tabs[0]?.id ?? 'mine';
  const setTab = (v: TabId) => { const p = new URLSearchParams(params); p.set('tab', v); setParams(p, { replace: true }); };
  const [open, setOpen] = useState<{ emp: string | null } | null>(null);
  const [bump, setBump] = useState(0);
  const current = tabs.some((x) => x.id === tab) ? tab : tabs[0]?.id;
  return (
    <div className="stack">
      <PageHead title={t('lv.title')} actions={<>
        {me?.employee_id && <Button kind="primary" onClick={() => setOpen({ emp: me.employee_id })}>{t('lv.request')}</Button>}
        {(can('LEAVE_WRITE') || me?.is_manager) && <Button onClick={() => setOpen({ emp: null })}>{t('lv.request_for')}</Button>}
      </>} />
      {tabs.length > 1 && <Tabs tabs={tabs} value={current ?? 'mine'} onChange={setTab} label={t('lv.title')} />}
      {!tabs.length && <Empty>{t('lv.mine_none')}</Empty>}
      {current === 'mine' && me?.employee_id && <MyLeave key={bump} employeeId={me.employee_id} />}
      {current === 'requests' && <RequestsTab key={bump} />}
      {current === 'calendar' && <CalendarTab key={bump} />}
      <LeaveDialog open={!!open} employeeId={open?.emp ?? undefined} onClose={() => setOpen(null)} onDone={() => setBump((x) => x + 1)} />
    </div>
  );
}

// ---------------------------------------------------------------------------
export function BalanceCards({ balances, today }: { balances: Balance[]; today: string }) {
  const { t, L } = useI18n();
  return (
    <div className="bal-grid">
      {balances.map((b) => (
        <div key={b.leave_type} className="bal">
          <div className="bal-name">{L(b.name_en, b.name_ar)}</div>
          {b.available !== null
            ? <div className="bal-num"><b className="num">{b.available}</b> <span className="muted">/ {b.entitled}</span></div>
            : <div className="bal-num muted">{balanceText(b, t)}</div>}
          <div className="bal-sub">
            {b.available !== null && <>{balanceText(b, t)} · </>}
            {t('lv.used')}: <span className="num">{b.used}</span>
            {b.pending > 0 && <> · {t('lv.pending')}: <span className="num">{b.pending}</span></>}
            {b.eligible_from > today && <><br />{t('lv.not_eligible_yet', { d: fmtDate(b.eligible_from) })}</>}
          </div>
        </div>
      ))}
    </div>
  );
}

function MyLeave({ employeeId }: { employeeId: string }) {
  const { t } = useI18n();
  const today = todayMuscat();
  const bal = useAsync(() => tapi.leaveBalances(employeeId), [employeeId]);
  const main = (bal.data?.balances ?? []).filter((b) => ['ANNUAL', 'SICK'].includes(b.leave_type) || b.used > 0 || b.pending > 0);
  return (
    <div className="stack">
      <section className="panel">
        <div className="panel-head"><h2>{t('lv.my_balances')}</h2></div>
        <div className="panel-body">
          <ErrorNote error={bal.error} onRetry={bal.reload} />
          {bal.loading && !bal.data ? <Loading /> : <BalanceCards balances={main} today={today} />}
        </div>
      </section>
      <LeaveList scope="mine" employeeId={employeeId} onChange={() => void bal.reload()} />
    </div>
  );
}

// ---------------------------------------------------------------------------
export function LeaveList({ scope, employeeId, onChange, title }: { scope: 'mine' | 'team' | 'all'; employeeId?: string; onChange?: () => void; title?: string }) {
  const { t, L } = useI18n();
  const { can } = useSession();
  const [status, setStatus] = useState(scope === 'mine' ? '' : 'PENDING');
  const [type, setType] = useState('');
  const [offset, setOffset] = useState(0);
  const types = useAsync(() => tapi.listLeaveTypes(), []);
  const { data, error, loading, reload } = useAsync(() => tapi.listLeaveRequests({ scope: scope === 'all' ? null : scope, employee_id: employeeId ?? null,
    status: status || null, leave_type: type || null, limit: 50, offset }), [scope, employeeId, status, type, offset]);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const [attach, setAttach] = useState<LeaveReq | null>(null);
  const [ticket, setTicket] = useState<LeaveReq | null>(null);
  const done = () => { void reload(); onChange?.(); };

  const decide = async (r: LeaveReq, approve: boolean) => {
    const note = await confirm.ask({ title: `${L(r.full_name_en, r.full_name_ar)} — ${L(r.name_en, r.name_ar)}`,
      body: <>{fmtDate(r.start_date)} – {fmtDate(r.end_date)} · {t('lv.days_count', { n: r.days })}
        {r.balance?.available !== null && r.balance ? <> · {t('lv.available')}: {r.balance.available}</> : null}</>,
      reason: approve ? 'optional' : 'required', reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    if (await run(() => tapi.decideLeave(r.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'))) done();
  };
  const cancel = async (r: LeaveReq) => {
    const approved = r.status === 'APPROVED';
    const note = await confirm.ask({ title: t('lv.cancel_title'), body: `${L(r.name_en, r.name_ar)} · ${fmtDate(r.start_date)} – ${fmtDate(r.end_date)}`,
      reason: approved ? 'required' : 'optional', reasonLabel: t('lv.cancel_reason'), danger: true });
    if (note === null) return;
    if (await run(() => tapi.cancelLeave(r.id, note || null))) done();
  };
  const exportCsv = () => data && downloadCsv(`leave-${todayMuscat()}.csv`,
    [t('emp.no'), t('emp.name'), t('lv.type'), t('lv.start'), t('lv.end'), t('lv.days'), t('c.status'), t('c.reason')],
    data.rows.map((r) => [r.employee_no, L(r.full_name_en, r.full_name_ar), L(r.name_en, r.name_ar), r.start_date, r.end_date, r.days, t(`rst.${r.status}` as Key), r.reason]));

  return (
    <section className="panel">
      <div className="panel-head">
        <h2>{title ?? t('lv.tab_requests')}</h2>
        <div className="row" style={{ gap: 8 }}>
          <select className="select" style={{ width: 170 }} value={type} onChange={(e) => { setType(e.target.value); setOffset(0); }} aria-label={t('lv.type')}>
            <option value="">{t('lv.all_types')}</option>
            {(types.data ?? []).map((x) => <option key={x.code} value={x.code}>{L(x.name_en, x.name_ar)}</option>)}
          </select>
          <select className="select" style={{ width: 170 }} value={status} onChange={(e) => { setStatus(e.target.value); setOffset(0); }} aria-label={t('c.status')}>
            <option value="">{t('c.all')}</option>
            {['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'].map((s) => <option key={s} value={s}>{t(`rst.${s}` as Key)}</option>)}
          </select>
          {scope !== 'mine' && <Button small onClick={exportCsv} disabled={!data?.rows.length}>{t('c.export')}</Button>}
        </div>
      </div>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.rows.length ? <Empty>{t('lv.none')}</Empty> : (
        <>
          <div className="table-wrap"><table className="t cards">
            <thead><tr>{scope !== 'mine' && <th>{t('c.employee')}</th>}<th>{t('lv.type')}</th><th>{t('lv.start')}</th><th>{t('lv.end')}</th>
              <th className="r">{t('lv.days')}</th><th>{t('c.status')}</th><th>{t('lv.pay')}</th><th /></tr></thead>
            <tbody>{data.rows.map((r) => (
              <tr key={r.id}>
                {scope !== 'mine' && <td data-label={t('c.employee')}><EmpCell r={r} tab="time" /></td>}
                <td data-label={t('lv.type')}>{L(r.name_en, r.name_ar)}
                  {r.reason && <span className="sub">{r.reason}</span>}
                  {r.requires_document && <span className="sub">{r.document_id ? <Badge tone="ok">{r.document_name ?? t('lv.attached')}</Badge> : <Badge tone="warn">{t('lv.no_doc')}</Badge>}</span>}
                  {r.ticket_requested && <span className="sub">{t('lv.ticket_status')}: {t(`lv.tk_${r.ticket_status}` as Key)}</span>}</td>
                <td data-label={t('lv.start')}><DateText v={r.start_date} />{r.half_day && <span className="sub">{t('lv.half')}</span>}</td>
                <td data-label={t('lv.end')}><DateText v={r.end_date} /></td>
                <td data-label={t('lv.days')} className="r num">{r.days}</td>
                <td data-label={t('c.status')}><ReqBadge status={r.status} />
                  <span className="sub">{r.requested_by_name} · {fmtDateTime(r.requested_at)}</span>
                  {r.decided_by_name && <span className="sub">{t('lv.decided_by')}: {r.decided_by_name}{r.decision_note ? ` — ${r.decision_note}` : ''}</span>}
                  {r.cancel_reason && <span className="sub">{r.cancel_reason}</span>}</td>
                <td data-label={t('lv.pay')}>{r.pay_breakdown ? r.pay_breakdown.map((p) => `${p.days}d @ ${p.pct}%`).join(', ') : t(`la.pm_${r.pay_mode}` as Key)}</td>
                <td className="r"><div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  {r.can_decide && <><Button small kind="primary" busy={busy} onClick={() => void decide(r, true)}>{t('c.approve')}</Button>
                    <Button small kind="danger" busy={busy} onClick={() => void decide(r, false)}>{t('c.reject')}</Button></>}
                  {r.can_attach && r.requires_document && !r.document_id && <Button small onClick={() => setAttach(r)}>{t('lv.attach')}</Button>}
                  {r.ticket_requested && r.status === 'APPROVED' && can('LEAVE_WRITE') && <Button small onClick={() => setTicket(r)}>{t('lv.set_ticket')}</Button>}
                  {r.can_cancel && <Button small busy={busy} onClick={() => void cancel(r)}>{r.status === 'APPROVED' ? t('c.cancel') : t('lv.withdraw')}</Button>}
                </div></td>
              </tr>))}
            </tbody></table></div>
          {data.total > 50 && <div className="row" style={{ padding: '10px 12px' }}>
            <span className="muted">{t('c.rows', { n: data.total })}</span><span className="spacer" />
            <Button small disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - 50))}>{t('c.previous')}</Button>
            <Button small disabled={offset + 50 >= data.total} onClick={() => setOffset(offset + 50)}>{t('c.next')}</Button></div>}
        </>
      )}
      <AttachDialog request={attach} onClose={() => setAttach(null)} onDone={done} />
      <TicketDialog request={ticket} onClose={() => setTicket(null)} onDone={done} />
      {confirm.node}
    </section>
  );
}

function TicketDialog({ request, onClose, onDone }: { request: LeaveReq | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [v, setV] = useState('ISSUED');
  return (
    <Modal open={!!request} title={t('lv.set_ticket')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={async () => {
        if (request && await run(() => tapi.setTicketStatus(request.id, v), t('c.saved'))) { onDone(); onClose(); }
      }}>{t('c.save')}</Button></>}>
      <Select label={t('lv.ticket_status')} value={v} onChange={(e) => setV(e.target.value)}>
        {['REQUESTED', 'ISSUED', 'CASH', 'DECLINED'].map((s) => <option key={s} value={s}>{t(`lv.tk_${s}` as Key)}</option>)}
      </Select>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function RequestsTab() {
  const { can } = useSession();
  return <LeaveList scope={can('LEAVE_READ') ? 'all' : 'team'} />;
}

function CalendarTab() {
  const { t, L } = useI18n();
  const [entity, setEntity] = useEntity();
  const [month, setMonth] = useState(monthOf(todayMuscat()));
  const [dep, setDep] = useState<string | null>(null);
  const [all, setAll] = useState(false);
  const { data, error, loading, reload } = useAsync(() => tapi.leaveCalendar({ month, entity_id: entity || null, department_id: dep, all_employees: all }), [month, entity, dep, all]);
  const lines = useMemo(() => (data?.rows ?? []).map((r) => {
    const cells: Record<number, { code: string; title: string }> = {};
    for (const l of r.leave ?? []) for (let d = l.from_day; d <= l.to_day; d++) {
      cells[d] = { code: l.status === 'APPROVED' ? 'V' : 'W', title: `${L(l.name_en, l.name_ar)}${l.half_day ? ` (${t('lv.half')})` : ''} — ${t(`rst.${l.status}` as Key)}` };
    }
    return { key: r.employee_id, label: <EmpCell r={r} tab="time" />, cells };
  }), [data, L, t]);
  const holidays = useMemo(() => new Set((data?.holidays ?? []).map((h) => h.day)), [data]);
  return (
    <div className="stack">
      <div className="panel panel-pad row" style={{ gap: 16, alignItems: 'flex-end' }}>
        <EntitySelect value={entity} onChange={setEntity} />
        <MonthPicker value={month} onChange={setMonth} />
        <div style={{ minWidth: 220 }}><MasterSelect kind="department" entityId={entity} label={t('c.department')} value={dep} onChange={setDep} /></div>
        <label className="check"><input type="checkbox" checked={all} onChange={(e) => setAll(e.target.checked)} /> <span>{t('lv.show_all')}</span></label>
      </div>
      <div className="panel panel-pad">
        <p className="muted" style={{ marginTop: 0 }}>{t('lv.calendar_hint')}</p>
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !lines.length ? <Empty>{t('lv.none')}</Empty> : <MonthGrid month={month} lines={lines} holidays={holidays} legend={['V', 'W']} />}
        {(data?.holidays ?? []).length > 0 && <p className="muted" style={{ marginBottom: 0 }}>{data!.holidays.map((h) => `${h.day}: ${L(h.name_en, h.name_ar)}`).join(' · ')}</p>}
      </div>
    </div>
  );
}
