import { Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, DateText, Empty, ErrorNote, Loading, useAction, useAsync, useConfirm } from '../components/ui';
import { PageHead } from '../components/Layout';
import { fmtDate, fmtDateTime, fmtDuration, fmtMoney, fmtPct } from '../lib/format';
import { tapi, type ReqStatus } from '../lib/api_time';
import { EmpCell } from '../components/time';
import { RuleValues } from './time/RulesPage';
import type { Key } from '../i18n';

type TimeKind = 'leave' | 'correction' | 'overtime' | 'adjustment' | 'rule';

export default function ApprovalsPage() {
  const { t, L, tk } = useI18n();
  const { can } = useSession();
  const hrApprover = can('SALARY_APPROVE') || can('BANK_APPROVE') || can('RULES_APPROVE');
  const { data, error, loading, reload } = useAsync(() => (hrApprover ? api.pendingApprovals() : Promise.resolve({ salary: [], bank: [], targets: [] } as unknown as Awaited<ReturnType<typeof api.pendingApprovals>>)), [hrApprover]);
  const tasks = useAsync(() => tapi.myTasks(), []);
  const { busy, run } = useAction();
  const confirm = useConfirm();

  const decide = async (kind: 'salary' | 'bank' | 'target', id: string, approve: boolean, title: string) => {
    const note = await confirm.ask({ title, body: kind === 'bank' ? t('bk.check_hint') : undefined, reason: approve ? 'optional' : 'required',
      reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    const ok = await run(async () => {
      if (kind === 'salary') await api.decideCompensation(id, approve, note || null);
      else if (kind === 'bank') await api.decideBank(id, approve, note || null);
      else await api.decideTarget(id, approve, note || null);
      return true;
    }, t(approve ? 'ap.done_approve' : 'ap.done_reject'));
    if (ok) void reload();
  };

  const decideTime = async (kind: TimeKind, id: string, approve: boolean, title: string) => {
    const note = await confirm.ask({ title, reason: approve ? 'optional' : 'required', reasonLabel: t('ap.decision_note'), danger: !approve,
      okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    const n = note || null;
    const ok = await run(async () => {
      if (kind === 'leave') await tapi.decideLeave(id, approve, n);
      else if (kind === 'correction') await tapi.decideCorrection(id, approve, n);
      else if (kind === 'overtime') await tapi.decideOvertime(id, approve, n);
      else if (kind === 'adjustment') await tapi.decideAdjustments([id], approve, n);
      else await tapi.decideTimeRule(id, approve, n);
      return true;
    }, t(approve ? 'ap.done_approve' : 'ap.done_reject'));
    if (ok) void tasks.reload();
  };
  const tAct = (kind: TimeKind, id: string, title: string) => (
    <div className="row" style={{ justifyContent: 'flex-end', gap: 4 }}>
      <Button small kind="primary" busy={busy} onClick={() => void decideTime(kind, id, true, title)}>{t('c.approve')}</Button>
      <Button small kind="danger" busy={busy} onClick={() => void decideTime(kind, id, false, title)}>{t('c.reject')}</Button>
    </div>);
  const stage = (s: ReqStatus) => <span className="sub">{t(s === 'PENDING_MANAGER' ? 'apt.stage_manager' : 'apt.stage_hr')}</span>;
  const td = tasks.data;

  if ((loading && !data) || (tasks.loading && !td)) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;

  const actions = (kind: 'salary' | 'bank' | 'target', id: string, canDecide: boolean, title: string) => canDecide ? (
    <div className="row" style={{ justifyContent: 'flex-end', gap: 4 }}>
      <Button small kind="primary" busy={busy} onClick={() => void decide(kind, id, true, title)}>{t('c.approve')}</Button>
      <Button small kind="danger" busy={busy} onClick={() => void decide(kind, id, false, title)}>{t('c.reject')}</Button>
    </div>
  ) : <span className="muted" style={{ fontSize: 12.5 }}>{t('ap.yours')}</span>;

  return (
    <div className="stack">
      <PageHead title={t('ap.title')} />
      <ErrorNote error={tasks.error} onRetry={tasks.reload} />
      {td && td.count === 0 && !hrApprover && <Empty>{t('apt.none')}</Empty>}
      {td && td.leave.length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('apt.leave')}</h2><Link to="/leave?tab=requests">{t('tnav.leave')}</Link></div>
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('lv.type')}</th><th>{t('c.from')}–{t('c.to')}</th><th className="r">{t('lv.days')}</th><th>{t('c.reason')}</th><th>{t('c.by')}</th><th /></tr></thead>
            <tbody>{td.leave.map((r) => (
              <tr key={r.id}>
                <td data-label={t('c.employee')}><EmpCell r={r} tab="time" />{stage(r.status)}</td>
                <td data-label={t('lv.type')}>{L(r.name_en, r.name_ar)}{r.requires_document && !r.document_id && <span className="sub bad-text">{t('lv.no_doc')}</span>}</td>
                <td data-label={`${t('c.from')}–${t('c.to')}`} className="num">{fmtDate(r.start_date)} – {fmtDate(r.end_date)}</td>
                <td data-label={t('lv.days')} className="r num">{r.days}{r.balance && r.balance.available !== null && <span className="sub">{t('lv.available')}: {r.balance.available}</span>}</td>
                <td data-label={t('c.reason')}>{r.reason ?? '—'}</td>
                <td data-label={t('c.by')}>{r.requested_by_name}<span className="sub">{fmtDateTime(r.requested_at)}</span></td>
                <td className="r">{tAct('leave', r.id, `${L(r.full_name_en, r.full_name_ar)} — ${L(r.name_en, r.name_ar)} (${r.days})`)}</td>
              </tr>))}
            </tbody></table></div>
        </section>
      )}
      {td && td.corrections.length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('apt.corrections')}</h2><Link to="/attendance?tab=corrections">{t('tnav.attendance')}</Link></div>
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('c.date')}</th><th>{t('cor.in_time')}–{t('cor.out_time')}</th><th>{t('c.reason')}</th><th>{t('c.by')}</th><th /></tr></thead>
            <tbody>{td.corrections.map((r) => (
              <tr key={r.id}>
                <td data-label={t('c.employee')}><EmpCell r={r} tab="time" />{stage(r.status)}</td>
                <td data-label={t('c.date')}><DateText v={r.work_date} /></td>
                <td data-label={`${t('cor.in_time')}–${t('cor.out_time')}`} className="num">{r.punch_in ?? '—'}–{r.punch_out ?? '—'}{r.out_next_day ? ' +1' : ''}</td>
                <td data-label={t('c.reason')}>{r.reason}</td>
                <td data-label={t('c.by')}>{r.requested_by_name}<span className="sub">{fmtDateTime(r.requested_at)}</span></td>
                <td className="r">{tAct('correction', r.id, `${L(r.full_name_en, r.full_name_ar)} — ${r.work_date}`)}</td>
              </tr>))}
            </tbody></table></div>
        </section>
      )}
      {td && td.overtime.length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('apt.overtime')}</h2><Link to="/overtime">{t('tnav.overtime')}</Link></div>
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('ot.work_date')}</th><th>{t('ot.start')}–{t('ot.end')}</th><th>{t('ot.kind')}</th><th className="r">{t('ot.minutes')}</th><th>{t('c.reason')}</th><th /></tr></thead>
            <tbody>{td.overtime.map((r) => (
              <tr key={r.id}>
                <td data-label={t('c.employee')}><EmpCell r={r} tab="time" />{stage(r.status)}</td>
                <td data-label={t('ot.work_date')}><DateText v={r.work_date} /></td>
                <td data-label={`${t('ot.start')}–${t('ot.end')}`} className="num">{r.start_time}–{r.end_time}{r.end_next_day ? ' +1' : ''}</td>
                <td data-label={t('ot.kind')}>{t(`ot.k_${r.day_kind}` as Key)}<span className="sub">{t(`ot.b_${r.basis}` as Key)}</span></td>
                <td data-label={t('ot.minutes')} className="r num">{fmtDuration(r.minutes)}</td>
                <td data-label={t('c.reason')}>{r.reason}</td>
                <td className="r">{tAct('overtime', r.id, `${L(r.full_name_en, r.full_name_ar)} — ${r.work_date} ${r.start_time}–${r.end_time}`)}</td>
              </tr>))}
            </tbody></table></div>
        </section>
      )}
      {td && td.adjustments.length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('apt.adjustments')}</h2><Link to="/leave/admin?tab=adjust">{t('tnav.leave_admin')}</Link></div>
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('lv.type')}</th><th>{t('la.kind')}</th><th className="r">{t('lv.days')}</th><th>{t('c.reason')}</th><th>{t('c.by')}</th><th /></tr></thead>
            <tbody>{td.adjustments.map((r) => (
              <tr key={r.id}>
                <td data-label={t('c.employee')}><EmpCell r={r} tab="time" /></td>
                <td data-label={t('lv.type')}>{L(r.name_en, r.name_ar)}</td>
                <td data-label={t('la.kind')}>{t(`la.k_${r.kind}` as Key)}</td>
                <td data-label={t('lv.days')} className="r num">{r.days > 0 ? `+${r.days}` : r.days}</td>
                <td data-label={t('c.reason')}>{r.reason}</td>
                <td data-label={t('c.by')}>{r.proposed_by_name}<span className="sub">{fmtDateTime(r.proposed_at)}</span></td>
                <td className="r">{tAct('adjustment', r.id, `${L(r.full_name_en, r.full_name_ar)} — ${r.days}`)}</td>
              </tr>))}
            </tbody></table></div>
        </section>
      )}
      {td && td.rules.length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('apt.rules')}</h2><Link to="/time/rules">{t('tnav.rules')}</Link></div>
          <div className="panel-pad stack">{td.rules.map((r) => (
            <div key={r.id} className="rule-card">
              <div className="row" style={{ justifyContent: 'space-between', gap: 8 }}>
                <b>{t(`rule.${r.code}` as Key)} — <DateText v={r.effective_from} /></b>
                {tAct('rule', r.id, `${t(`rule.${r.code}` as Key)} — ${r.effective_from}`)}
              </div>
              <RuleValues code={r.code} value={r.value} />
              <div className="muted small">{r.legal_basis} · {r.proposed_by_name}</div>
            </div>))}
          </div>
        </section>
      )}
      {can('SALARY_APPROVE') && (
        <section className="panel">
          <div className="panel-head"><h2>{t('ap.salary')}</h2></div>
          {data.salary.length === 0 ? <Empty>{t('ap.none')}</Empty> : (
            <div className="table-wrap"><table className="t cards">
              <thead><tr><th>{t('c.employee')}</th><th>{t('as.effective_from')}</th><th>{t('c.reason')}</th><th className="r">{t('pay.gross')}</th><th>{t('c.by')}</th><th /></tr></thead>
              <tbody>{data.salary.map((r) => (
                <tr key={r.id}>
                  <td data-label={t('c.employee')}><Link to={`/employees/${r.employee_id}?tab=pay`}>{L(r.full_name_en, r.full_name_ar)}</Link><span className="sub num">{r.employee_no}</span></td>
                  <td data-label={t('as.effective_from')}><DateText v={r.effective_from} /></td>
                  <td data-label={t('c.reason')}>{tk(`pay.${r.reason}`, r.reason)}</td>
                  <td data-label={t('pay.gross')} className="r num">{fmtMoney(r.total_monthly)}</td>
                  <td data-label={t('c.by')}>{r.proposed_by_name}<span className="sub">{fmtDateTime(r.proposed_at)}</span></td>
                  <td className="r">{actions('salary', r.id, r.can_decide, t('pay.approve_title'))}</td>
                </tr>))}
              </tbody></table></div>
          )}
        </section>
      )}
      {can('BANK_APPROVE') && (
        <section className="panel">
          <div className="panel-head"><h2>{t('ap.bank')}</h2></div>
          {data.bank.length === 0 ? <Empty>{t('ap.none')}</Empty> : (
            <div className="table-wrap"><table className="t cards">
              <thead><tr><th>{t('c.employee')}</th><th>{t('bk.bank')}</th><th>{t('bk.account')}</th><th>{t('c.by')}</th><th /></tr></thead>
              <tbody>{data.bank.map((r) => (
                <tr key={r.id}>
                  <td data-label={t('c.employee')}><Link to={`/employees/${r.employee_id}?tab=bank`}>{L(r.full_name_en, r.full_name_ar)}</Link><span className="sub num">{r.employee_no}</span></td>
                  <td data-label={t('bk.bank')}>{r.bank_name}</td>
                  <td data-label={t('bk.account')} className="num">{r.account_number}</td>
                  <td data-label={t('c.by')}>{r.requested_by_name}<span className="sub">{fmtDateTime(r.requested_at)}</span></td>
                  <td className="r">{actions('bank', r.id, r.can_decide, t('bk.approve_title'))}</td>
                </tr>))}
              </tbody></table></div>
          )}
        </section>
      )}
      {can('RULES_APPROVE') && (
        <section className="panel">
          <div className="panel-head"><h2>{t('ap.targets')}</h2><Link to="/compliance/targets">{t('nav.targets')}</Link></div>
          {data.targets.length === 0 ? <Empty>{t('ap.none')}</Empty> : (
            <div className="table-wrap"><table className="t cards">
              <thead><tr><th>{t('tg.scope')}</th><th className="r">{t('tg.pct')}</th><th>{t('c.from')}</th><th>{t('tg.source')}</th><th>{t('c.by')}</th><th /></tr></thead>
              <tbody>{data.targets.map((r) => (
                <tr key={r.id}>
                  <td data-label={t('tg.scope')}>{tk(`tg.${r.scope_type}`, r.scope_type)}</td>
                  <td data-label={t('tg.pct')} className="r num">{fmtPct(r.target_pct)}</td>
                  <td data-label={t('c.from')}><DateText v={r.effective_from} /></td>
                  <td data-label={t('tg.source')}>{r.source_reference}</td>
                  <td data-label={t('c.by')}>{r.proposed_by_name}</td>
                  <td className="r">{actions('target', r.id, r.can_decide, `${fmtPct(r.target_pct)} — ${r.source_reference}`)}</td>
                </tr>))}
              </tbody></table></div>
          )}
        </section>
      )}
      {confirm.node}
    </div>
  );
}
