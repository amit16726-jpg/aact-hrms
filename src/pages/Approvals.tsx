import { Link } from 'react-router-dom';
import { api } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Button, DateText, Empty, ErrorNote, Loading, useAction, useAsync, useConfirm } from '../components/ui';
import { PageHead } from '../components/Layout';
import { fmtDateTime, fmtMoney, fmtPct } from '../lib/format';

export default function ApprovalsPage() {
  const { t, L, tk } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload } = useAsync(() => api.pendingApprovals(), []);
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

  if (loading && !data) return <Loading />;
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
