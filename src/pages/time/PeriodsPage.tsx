import { useMemo, useState } from 'react';
import { tapi, type Period } from '../../lib/api_time';
import { useI18n } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Empty, ErrorNote, Loading, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { EmpCell, EntitySelect, useEntity } from '../../components/time';
import { fmtDateTime, todayMuscat } from '../../lib/format';
import { downloadCsv } from '../../lib/csv';

export default function PeriodsPage() {
  const { t, lang } = useI18n();
  const { can } = useSession();
  const [entity, setEntity] = useEntity();
  const [year, setYear] = useState(Number(todayMuscat().slice(0, 4)));
  const { data, error, loading, reload, setData } = useAsync(() => (entity ? tapi.listPeriods(entity, year) : Promise.resolve([] as Period[])), [entity, year]);
  const [month, setMonth] = useState(todayMuscat().slice(0, 7));
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const mName = (m: string) => new Date(`${m}-01T00:00:00`).toLocaleDateString(lang === 'ar' ? 'ar-OM' : 'en-GB', { month: 'long', year: 'numeric' });

  const lock = async (p: Period) => {
    const ok = await confirm.ask({ title: t('per.lock_title', { m: mName(p.month) }), body: t('per.lock_body'), okLabel: t('per.lock') });
    if (ok === null) return;
    const r = await run(() => tapi.lockPeriod(entity, p.month), t('per.locked_done'));
    if (r) setData(r);
  };
  const unlock = async (p: Period) => {
    const reason = await confirm.ask({ title: t('per.unlock_title', { m: mName(p.month) }), reason: 'required', danger: true, okLabel: t('per.unlock') });
    if (reason === null) return;
    const r = await run(() => tapi.unlockPeriod(entity, p.month, reason), t('per.unlocked_done'));
    if (r) setData(r);
  };

  return (
    <div className="stack">
      <PageHead title={t('per.title')} />
      <div className="panel panel-pad row" style={{ alignItems: 'flex-end', gap: 8 }}>
        <EntitySelect value={entity} onChange={setEntity} />
        <Button onClick={() => setYear(year - 1)} aria-label={t('c.previous')}>‹</Button>
        <b className="num" style={{ padding: '8px 6px' }}>{year}</b>
        <Button onClick={() => setYear(year + 1)} aria-label={t('c.next')}>›</Button>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('att.month')}</th><th>{t('c.status')}</th><th>{t('per.locked_by')}</th><th /></tr></thead>
            <tbody>{(data ?? []).map((p) => (
              <tr key={p.month} className={p.month === month ? 'row-sel' : undefined}>
                <td data-label={t('att.month')}><button type="button" className="linklike" onClick={() => setMonth(p.month)}>{mName(p.month)}</button></td>
                <td data-label={t('c.status')}><Badge tone={p.status === 'LOCKED' ? 'ok' : undefined}>{t(p.status === 'LOCKED' ? 'per.LOCKED' : 'per.OPEN')}</Badge>
                  {p.pending > 0 && <span className="sub"><Badge tone="warn">{t('per.pending', { n: p.pending })}</Badge></span>}</td>
                <td data-label={t('per.locked_by')}>{p.locked_by_name ? <>{p.locked_by_name}<span className="sub">{fmtDateTime(p.locked_at)}</span></> : '—'}
                  {p.unlock_reason && <span className="sub">{t('per.unlock')}: {p.unlocked_by_name} — {p.unlock_reason}</span>}</td>
                <td className="r">{can('ATT_LOCK') && (p.status === 'OPEN'
                  ? p.can_lock && <Button small kind="primary" busy={busy} disabled={p.pending > 0} onClick={() => void lock(p)}>{t('per.lock')}</Button>
                  : <Button small kind="danger" busy={busy} onClick={() => void unlock(p)}>{t('per.unlock')}</Button>)}</td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
      {entity && <Summary entity={entity} month={month} title={t('per.summary', { m: mName(month) })} />}
      {confirm.node}
    </div>
  );
}

function Summary({ entity, month, title }: { entity: string; month: string; title: string }) {
  const { t, L } = useI18n();
  const { data, error, loading, reload } = useAsync(() => tapi.attendanceSummary({ entity_id: entity, month }), [entity, month]);
  const types = useAsync(() => tapi.listLeaveTypes(), []);
  const leaveCodes = useMemo(() => {
    const set = new Set<string>();
    (data?.rows ?? []).forEach((r) => Object.keys(r.leave ?? {}).forEach((k) => set.add(k)));
    return [...set].sort();
  }, [data]);
  const lname = (c: string) => { const x = types.data?.find((y) => y.code === c); return x ? L(x.name_en, x.name_ar) : c; };
  const exportCsv = () => data && downloadCsv(`payroll-inputs-${month}.csv`,
    [t('emp.no'), t('emp.name'), t('per.scheduled'), t('per.present'), t('per.absent'), t('per.missing'), t('per.late_min'), t('per.holidays'),
      ...leaveCodes.map(lname), t('per.unpaid'), t('per.ot_hours'), t('per.ot_days')],
    data.rows.map((r) => [r.employee_no, L(r.full_name_en, r.full_name_ar), r.scheduled_days, r.present_days, r.absent_days, r.missing_punch_days,
      r.late_minutes, r.holidays, ...leaveCodes.map((c) => r.leave?.[c] ?? 0), r.unpaid_leave_days, r.ot_pay_hours, r.ot_pay_days]));
  return (
    <section className="panel">
      <div className="panel-head"><h2>{title} {data?.locked && <Badge tone="ok">{t('per.LOCKED')}</Badge>}</h2>
        <Button small onClick={exportCsv} disabled={!data?.rows.length}>{t('per.export')}</Button></div>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.rows.length ? <Empty>{t('att.no_rows')}</Empty> : (
        <div className="table-wrap"><table className="t">
          <thead><tr><th>{t('c.employee')}</th><th className="r">{t('per.scheduled')}</th><th className="r">{t('per.present')}</th><th className="r">{t('per.absent')}</th>
            <th className="r">{t('per.missing')}</th><th className="r">{t('per.late_min')}</th><th className="r">{t('per.holidays')}</th>
            {leaveCodes.map((c) => <th key={c} className="r">{lname(c)}</th>)}
            <th className="r">{t('per.unpaid')}</th><th className="r">{t('per.ot_hours')}</th><th className="r">{t('per.ot_days')}</th></tr></thead>
          <tbody>{data.rows.map((r) => (
            <tr key={r.employee_id}>
              <td><EmpCell r={r} tab="time" /></td>
              <td className="r num">{r.scheduled_days}</td><td className="r num">{r.present_days}</td>
              <td className={`r num${r.absent_days ? ' bad-text' : ''}`}>{r.absent_days}</td>
              <td className={`r num${r.missing_punch_days ? ' bad-text' : ''}`}>{r.missing_punch_days}</td>
              <td className="r num">{r.late_minutes}</td><td className="r num">{r.holidays}</td>
              {leaveCodes.map((c) => <td key={c} className="r num">{r.leave?.[c] ?? ''}</td>)}
              <td className="r num">{r.unpaid_leave_days || ''}</td><td className="r num">{r.ot_pay_hours || ''}</td><td className="r num">{r.ot_pay_days || ''}</td>
            </tr>))}
          </tbody></table></div>
      )}
    </section>
  );
}
