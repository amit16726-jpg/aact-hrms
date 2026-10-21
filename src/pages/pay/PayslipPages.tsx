import { Link, useNavigate, useParams } from 'react-router-dom';
import { papi } from '../../lib/api_pay';
import { useI18n } from '../../i18n';
import { useSession } from '../../lib/session';
import { Button, Empty, ErrorNote, Loading, useAsync } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { OMR, PayslipView, RunBadge, monthName } from '../../components/pay';
import { fmtDate } from '../../lib/format';

export function PayslipPage() {
  const { id = '' } = useParams();
  const { t } = useI18n();
  const { can } = useSession();
  const nav = useNavigate();
  const { data, error, loading, reload } = useAsync(() => papi.getPayslip(id), [id]);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  return (
    <div className="stack">
      <div className="row no-print" style={{ justifyContent: 'space-between' }}>
        <Button onClick={() => nav(-1)}>{t('c.back')}</Button>
        <Button kind="primary" onClick={() => window.print()}>{t('ps.print')}</Button>
      </div>
      <PayslipView slip={data} back={can('PAY_READ') ? <Link to={`/payroll/${data.run_id}`}>{t('pr.title')}</Link> : <Link to="/payslips">{t('ps.my_title')}</Link>} />
    </div>
  );
}

export function MyPayslipsPage() {
  const { t, lang } = useI18n();
  const { data, error, loading, reload } = useAsync(() => papi.myPayslips(), []);
  return (
    <div className="stack">
      <PageHead title={t('ps.my_title')} />
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('ps.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('ps.month')}</th><th>{t('ps.pay_date')}</th><th className="r">{t('ps.total_earnings')}</th>
              <th className="r">{t('ps.total_deductions')}</th><th className="r">{t('ps.net')}</th><th /></tr></thead>
            <tbody>{data.map((p) => (
              <tr key={p.id}>
                <td data-label={t('ps.month')}><Link to={`/payslips/${p.id}`}>{monthName(p.month, lang)}</Link><span className="sub"><RunBadge status={p.status} /></span></td>
                <td data-label={t('ps.pay_date')} className="num">{fmtDate(p.pay_date)}</td>
                <td data-label={t('ps.total_earnings')} className="r num">{OMR(p.total_earnings)}</td>
                <td data-label={t('ps.total_deductions')} className="r num">{OMR(p.total_deductions)}</td>
                <td data-label={t('ps.net')} className="r num"><b>{OMR(p.net)}</b></td>
                <td className="r"><Link to={`/payslips/${p.id}`}>{t('ps.open')}</Link></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
    </div>
  );
}
