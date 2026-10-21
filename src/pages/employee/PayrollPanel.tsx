import { Link } from 'react-router-dom';
import { papi } from '../../lib/api_pay';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Empty, useAsync } from '../../components/ui';
import { OMR, RunBadge, monthName } from '../../components/pay';
import { GratuityLines } from '../pay/SettlementsPage';

/** Employee file → Pay tab: payslip history, loans and accrued gratuity. */
export function PayrollPanel({ employeeId }: { employeeId: string }) {
  const { t, lang } = useI18n();
  const { can, me } = useSession();
  const allowed = can('PAY_READ') || me?.employee_id === employeeId;
  const { data } = useAsync(() => (allowed ? papi.employeePayroll(employeeId) : Promise.resolve(null)), [employeeId, allowed]);
  if (!allowed || !data) return null;
  return (
    <div className="grid-2" style={{ alignItems: 'start', marginTop: 16 }}>
      <section className="panel">
        <div className="panel-head"><h2>{t('ps.history')}</h2></div>
        {!data.payslips.length ? <Empty>{t('ps.none')}</Empty> : (
          <div className="table-wrap"><table className="t">
            <thead><tr><th>{t('ps.month')}</th><th className="r">{t('ps.total_earnings')}</th><th className="r">{t('ps.net')}</th></tr></thead>
            <tbody>{data.payslips.slice(0, 12).map((p) => (
              <tr key={p.id}><td><Link to={`/payslips/${p.id}`}>{monthName(p.month, lang)}</Link> <RunBadge status={p.status} /></td>
                <td className="r num">{OMR(p.total_earnings)}</td><td className="r num"><b>{OMR(p.net)}</b></td></tr>))}
            </tbody></table></div>
        )}
      </section>
      <div className="stack">
        {data.gratuity && (
          <section className="panel panel-pad stack">
            <div className="row" style={{ justifyContent: 'space-between' }}><h2 style={{ margin: 0 }}>{t('pd.gratuity')}</h2>
              {data.gratuity.applies && !data.gratuity.below_minimum && <b className="num">OMR {OMR(data.gratuity.total)}</b>}</div>
            <GratuityLines g={data.gratuity} />
          </section>
        )}
        {data.loans.length > 0 && (
          <section className="panel">
            <div className="panel-head"><h2>{t('pd.loans_open')}</h2>{can('PAY_READ') && <Link to="/payroll/loans">{t('pnav.loans')}</Link>}</div>
            <div className="table-wrap"><table className="t">
              <thead><tr><th>{t('ln.kind')}</th><th className="r">{t('ln.amount')}</th><th className="r">{t('ln.outstanding')}</th><th>{t('c.status')}</th></tr></thead>
              <tbody>{data.loans.map((l) => (
                <tr key={l.id}><td>{t(`ln.k_${l.kind}` as Key)}<span className="sub num">{l.first_month.slice(0, 7)}</span></td>
                  <td className="r num">{OMR(l.amount)}</td><td className="r num">{OMR(l.outstanding)}</td>
                  <td><Badge tone={l.status === 'APPROVED' ? 'info' : l.status === 'CLOSED' ? 'ok' : undefined}>{t(`ln.st_${l.status}` as Key)}</Badge></td></tr>))}
              </tbody></table></div>
          </section>
        )}
      </div>
    </div>
  );
}
