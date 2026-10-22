import { useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { buildWpsSif, downloadText, papi, type JournalData, type PayrollRun, type RunDetail } from '../../lib/api_pay';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Loading, Tabs, useAction, useAsync, useConfirm, useToast } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { OMR, PayGroupBadge, RunBadge, RunSteps, monthName } from '../../components/pay';
import { downloadCsv } from '../../lib/csv';
import { parseCsv } from '../../lib/punches';

type TabId = 'slips' | 'summary' | 'exports' | 'parallel';

export default function PayrollRunPage() {
  const { id = '' } = useParams();
  const { t, L, lang } = useI18n();
  const { data, error, loading, reload, setData } = useAsync(() => papi.getRun(id), [id]);
  const [tab, setTab] = useState<TabId>('slips');
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const { can } = useSession();
  const merge = (r: PayrollRun) => setData((d) => (d ? { ...d, ...r } : d));

  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;
  const r = data;
  const m = monthName(r.month, lang);
  const tot = r.totals;

  const act = async (fn: () => Promise<PayrollRun>, ok: Key, full = false) => {
    const res = await run(fn, t(ok));
    if (res) { if (full) void reload(); else merge(res); }
  };

  return (
    <div className="stack">
      <PageHead title={t('pr.run_title', { m, c: L(r.entity_en, r.entity_ar) })} sub={<span className="row" style={{ gap: 8 }}><RunBadge status={r.status} />{(r.pay_group === 'MG' || can('MG_PAY')) && <PayGroupBadge group={r.pay_group} />}</span>}
        actions={<>
          {r.can_calculate && <Button kind="primary" busy={busy} disabled={!r.attendance_locked}
            onClick={() => void act(() => papi.calculate(r.id), 'pr.calculated_done', true)}>{r.status === 'DRAFT' && r.calc_count === 0 ? t('pr.calculate') : t('pr.recalculate')}</Button>}
          {r.can_verify && <Button kind="primary" busy={busy} onClick={async () => {
            const note = await confirm.ask({ title: t('pr.verify_title', { m }), reason: 'optional', okLabel: t('pr.verify') });
            if (note !== null) void act(() => papi.verify(r.id, note || null), 'pr.verified_done');
          }}>{t('pr.verify')}</Button>}
          {r.can_approve && <Button kind="primary" busy={busy} onClick={async () => {
            const note = await confirm.ask({ title: t('pr.approve_title', { m }), body: t('pr.approve_body', { n: OMR(tot.net), e: tot.employees ?? 0 }),
              reason: 'optional', okLabel: t('pr.approve') });
            if (note !== null) void act(() => papi.approve(r.id, note || null), 'pr.approved_done');
          }}>{t('pr.approve')}</Button>}
          {r.can_return && <Button busy={busy} onClick={async () => {
            const note = await confirm.ask({ title: t('pr.return_title'), reason: 'required', reasonLabel: t('pr.return_label'), danger: true, okLabel: t('pr.return') });
            if (note) void act(() => papi.returnRun(r.id, note), 'pr.returned_done');
          }}>{t('pr.return')}</Button>}
          {r.can_pay && <Button busy={busy} onClick={() => void act(() => papi.markPaid(r.id), 'pr.paid_done')}>{t('pr.mark_paid')}</Button>}
          {r.can_reopen && <Button kind="danger" busy={busy} onClick={async () => {
            const note = await confirm.ask({ title: t('pr.reopen_title'), body: t('pr.reopen_body'), reason: 'required', danger: true, okLabel: t('pr.reopen') });
            if (note) void act(() => papi.reopen(r.id, note), 'pr.reopened_done', true);
          }}>{t('pr.reopen')}</Button>}
        </>} />
      <section className="panel panel-pad stack">
        <RunSteps run={r} />
        {!r.attendance_locked && r.status === 'DRAFT' && (
          <div className="note note-warn">{t('pr.attendance_open')} <Link to="/time/periods">{t('pr.lock_attendance')}</Link></div>)}
        {r.return_note && r.status === 'DRAFT' && <div className="note note-warn">{t('pr.returned_note', { n: r.return_note })}</div>}
        {r.reopen_reason && r.status === 'DRAFT' && <div className="note note-warn">{t('pr.reopened_note', { n: r.reopen_reason })}</div>}
        {(r.pending_inputs.adjustments > 0 || r.pending_inputs.loans > 0) && ['DRAFT', 'CALCULATED'].includes(r.status) && (
          <div className="note">{t('pr.pending_inputs', { a: r.pending_inputs.adjustments, l: r.pending_inputs.loans })}</div>)}
      </section>
      {r.status !== 'DRAFT' || r.calc_count > 0 ? (
        <div className="tile-row">
          <div className="tile"><span>{t('pr.employees')}</span><b>{tot.employees ?? 0}</b><span>{t('pr.omani')} {tot.omani ?? 0} · {t('pr.expat')} {tot.expat ?? 0}</span></div>
          <div className="tile"><span>{t('pr.gross')}</span><b>{OMR(tot.earnings)}</b></div>
          <div className="tile"><span>{t('pr.deductions')}</span><b>{OMR(tot.deductions)}</b></div>
          <div className="tile"><span>{t('pr.net')}</span><b>{OMR(tot.net)}</b></div>
          <div className="tile"><span>{t('pr.spf_ee')}</span><b>{OMR(tot.spf_employee)}</b></div>
          <div className="tile"><span>{t('pr.spf_er')}</span><b>{OMR(tot.spf_employer)}</b></div>
          <div className="tile"><span>{t('pr.overtime')}</span><b>{OMR(tot.overtime)}</b></div>
          <div className="tile"><span>{t('pr.eosb')}</span><b>{OMR(tot.eosb)}</b></div>
          <div className="tile"><span>{t('pr.employer_cost')}</span><b>{OMR(tot.employer_cost)}</b></div>
        </div>) : null}
      <Tabs tabs={[{ id: 'slips', label: `${t('pr.tab_slips')} (${r.payslips.length})` }, { id: 'summary', label: t('pr.tab_summary') },
        { id: 'exports', label: t('pr.tab_exports') }, { id: 'parallel', label: t('pr.tab_parallel') }]} value={tab} onChange={setTab} label={t('pr.title')} />
      {tab === 'slips' && <SlipsTab run={r} />}
      {tab === 'summary' && <SummaryTab run={r} />}
      {tab === 'exports' && <ExportsTab run={r} />}
      {tab === 'parallel' && <ParallelTab run={r} />}
      {confirm.node}
    </div>
  );
}

function SlipsTab({ run }: { run: RunDetail }) {
  const { t, L } = useI18n();
  const [q, setQ] = useState('');
  const [warn, setWarn] = useState(false);
  const rows = useMemo(() => run.payslips.filter((s) => (!warn || s.warnings.length > 0)
    && (!q || `${s.employee_no} ${s.full_name_en} ${s.full_name_ar ?? ''}`.toLowerCase().includes(q.toLowerCase()))), [run.payslips, q, warn]);
  if (!run.payslips.length) return <div className="panel"><Empty>{t('ps.none')}</Empty></div>;
  return (
    <div className="panel">
      <div className="panel-head row" style={{ gap: 12 }}>
        <input className="input" style={{ maxWidth: 280 }} placeholder={t('pr.search')} aria-label={t('pr.search')} value={q} onChange={(e) => setQ(e.target.value)} />
        <Check label={t('pr.only_warnings')} checked={warn} onChange={setWarn} />
      </div>
      <div className="table-wrap"><table className="t cards">
        <thead><tr><th>{t('c.employee')}</th><th className="r">{t('ps.paid_days')}</th><th className="r">{t('ps.basic')}</th><th className="r">{t('pr.gross')}</th>
          <th className="r">{t('pr.deductions')}</th><th className="r">{t('pr.net')}</th><th className="r">{t('pr.employer_cost')}</th><th>{t('ps.bank')}</th></tr></thead>
        <tbody>{rows.map((s) => (
          <tr key={s.id}>
            <td data-label={t('c.employee')}><Link to={`/payslips/${s.id}`}>{L(s.full_name_en, s.full_name_ar)}</Link>
              <span className="sub num">{s.employee_no} · {s.is_omani ? t('pr.omani') : t('pr.expat')}</span>
              {s.warnings.map((w, i) => <span key={i} className="sub bad-text">{w}</span>)}</td>
            <td data-label={t('ps.paid_days')} className="r num">{s.paid_days}{s.unpaid_days > 0 && <span className="sub">−{s.unpaid_days}</span>}</td>
            <td data-label={t('ps.basic')} className="r num">{OMR(s.basic)}</td>
            <td data-label={t('pr.gross')} className="r num">{OMR(s.total_earnings)}</td>
            <td data-label={t('pr.deductions')} className="r num">{OMR(s.total_deductions)}</td>
            <td data-label={t('pr.net')} className="r num"><b>{OMR(s.net)}</b></td>
            <td data-label={t('pr.employer_cost')} className="r num">{OMR(s.employer_cost)}</td>
            <td data-label={t('ps.bank')}>{s.has_bank ? <>{s.bank_name}<span className="sub num">{s.account_masked}</span></> : <Badge tone="bad">{t('pr.no_bank')}</Badge>}</td>
          </tr>))}
        </tbody></table></div>
    </div>
  );
}

function SummaryTab({ run }: { run: RunDetail }) {
  const { t, L } = useI18n();
  const groups: ('EARNING' | 'DEDUCTION' | 'EMPLOYER')[] = ['EARNING', 'DEDUCTION', 'EMPLOYER'];
  if (!run.by_code.length) return <div className="panel"><Empty>{t('ps.none')}</Empty></div>;
  return (
    <div className="grid-2" style={{ alignItems: 'start' }}>
      {groups.map((g) => {
        const rows = run.by_code.filter((c) => c.kind === g);
        if (!rows.length) return null;
        return (
          <section key={g} className="panel">
            <div className="panel-head"><h2>{t(`pr.k_${g}` as Key)}</h2><b className="num">{OMR(rows.reduce((s, c) => s + Number(c.amount), 0))}</b></div>
            <div className="table-wrap"><table className="t">
              <thead><tr><th>{t('pr.kind')}</th><th className="r">{t('pr.count')}</th><th className="r">{t('pr.amount')}</th></tr></thead>
              <tbody>{rows.map((c) => <tr key={c.code}><td>{L(c.name_en, c.name_ar)}<span className="sub num">{c.code}</span></td>
                <td className="r num">{c.employees}</td><td className="r num">{OMR(c.amount)}</td></tr>)}</tbody>
            </table></div>
          </section>);
      })}
    </div>
  );
}

export function journalRows(j: JournalData): (string | number)[][] {
  const gl = j.gl ?? {};
  const out: (string | number)[][] = [];
  for (const l of j.lines) {
    if (l.kind === 'EARNING') out.push([l.account, l.cost_centre, l.code, l.name, l.amount.toFixed(3), '']);
    else if (l.kind === 'DEDUCTION') out.push([l.account, l.cost_centre, l.code, l.name, '', l.amount.toFixed(3)]);
    else {
      out.push([l.account, l.cost_centre, l.code, l.name, l.amount.toFixed(3), '']);
      const credit = l.code.startsWith('SPF_') ? gl.spf_payable : gl.eosb_provision;
      out.push([credit ?? '—', l.cost_centre, l.code, `${l.name} (payable)`, '', l.amount.toFixed(3)]);
    }
  }
  out.push([gl.salary_payable ?? '—', '', 'NET_PAY', 'Net salaries payable', '', Number(j.net).toFixed(3)]);
  return out;
}

function ExportsTab({ run }: { run: RunDetail }) {
  const { t } = useI18n();
  const { can } = useSession();
  const { push } = useToast();
  const { busy, run: act } = useAction();
  const approved = run.status === 'APPROVED' || run.status === 'PAID';
  const wps = async () => {
    const d = await act(() => papi.exportWps(run.id));
    if (!d) return;
    if (!d.employer_cr || !d.bank_code || !d.account) { push(t('px.wps_needs'), true); return; }
    const f = buildWpsSif(d);
    downloadText(f.name, f.text, false);
    if (f.skipped.length) push(t('px.wps_skipped', { n: f.skipped.length, list: f.skipped.join(', ') }), true);
  };
  const journal = async () => {
    const j = await act(() => papi.exportJournal(run.id));
    if (j) downloadCsv(`payroll-journal-${run.month}.csv`, ['Account', 'Cost centre', 'Item', 'Description', 'Debit', 'Credit'], journalRows(j));
  };
  const register = async () => {
    const d = await act(() => papi.exportRegister(run.id));
    if (!d) return;
    const cols = d.codes.map((c) => `${c.code}:${c.kind}`);
    downloadCsv(`payroll-register-${run.month}.csv`,
      ['Employee no', 'Name', 'Department', 'Paid days', 'Unpaid days', ...d.codes.map((c) => `${c.name_en} (${c.kind === 'EARNING' ? '+' : c.kind === 'DEDUCTION' ? '−' : 'employer'})`),
        'Earnings', 'Deductions', 'Net', 'Employer cost'],
      d.rows.map((r) => [r.employee_no, r.name, r.department ?? '', r.paid_days, r.unpaid_days, ...cols.map((c) => r.amounts?.[c] ?? ''),
        r.earnings, r.deductions, r.net, r.employer_cost]));
  };
  const spf = async () => {
    const d = await act(() => papi.exportSpf(run.id));
    if (!d) return;
    const codes = ['SPF_EE_OLD_AGE', 'SPF_EE_JOB_SECURITY', 'SPF_ER_OLD_AGE', 'SPF_ER_INJURY', 'SPF_ER_JOB_SECURITY', 'SPF_ER_MATERNITY', 'SPF_ER_SICK'];
    downloadCsv(`spf-${run.month}.csv`, ['Employer no', 'Employee no', 'Name', 'Civil number', 'Omani', 'Wage', ...codes, 'Employee total', 'Employer total'],
      d.rows.map((r) => [d.employer_no ?? '', r.employee_no, r.name, r.civil_number ?? '', r.is_omani ? 'Y' : 'N', r.wage ?? '', ...codes.map((c) => r.lines?.[c] ?? ''),
        r.employee, r.employer]));
  };
  const card = (title: Key, hint: Key, onClick: () => void, enabled: boolean, note?: string) => (
    <section className="panel panel-pad stack">
      <h2 style={{ margin: 0 }}>{t(title)}</h2>
      <p className="muted" style={{ margin: 0 }}>{t(hint)}</p>
      <div><Button busy={busy} disabled={!enabled} onClick={onClick}>{t('px.download')}</Button>{note && <span className="muted small"> {note}</span>}</div>
    </section>);
  return (
    <div className="grid-2" style={{ alignItems: 'start' }}>
      {can('PAY_APPROVE') && card('px.wps', 'px.wps_hint', () => void wps(), run.can_export_bank, approved ? undefined : t('px.after_approval'))}
      {card('px.journal', 'px.journal_hint', () => void journal(), run.payslips.length > 0)}
      {card('px.register', 'px.register_hint', () => void register(), run.payslips.length > 0)}
      {card('px.spf', 'px.spf_hint', () => void spf(), run.payslips.length > 0)}
    </div>
  );
}

function ParallelTab({ run }: { run: RunDetail }) {
  const { t } = useI18n();
  const { can } = useSession();
  const { push } = useToast();
  const { busy, run: act } = useAction();
  const { data, error, loading, reload } = useAsync(() => papi.parallelReport(run.id), [run.id]);
  const upload = async (f: File) => {
    const rows = parseCsv(await f.text()).filter((r) => r.some((c) => c.trim() !== ''));
    const head = (rows[0] ?? []).map((h) => h.toLowerCase().trim());
    const ix = (k: string) => head.indexOf(k);
    if (ix('employee_no') < 0 || ix('net') < 0) { push(t('pp.hint'), true); return; }
    const payload = rows.slice(1).map((r) => ({ employee_no: r[ix('employee_no')] ?? '', net: (r[ix('net')] ?? '').replace(/,/g, ''),
      gross: ix('gross') >= 0 ? (r[ix('gross')] ?? '').replace(/,/g, '') : '', note: ix('note') >= 0 ? r[ix('note')] ?? '' : '' }));
    const res = await act(() => papi.saveParallel(run.id, payload, true));
    if (res) { push(t('pp.loaded', { n: res.loaded }), res.errors.length > 0); void reload(); }
  };
  const counts = useMemo(() => {
    const c = { MATCH: 0, DIFF: 0, OTHER: 0 };
    (data?.rows ?? []).forEach((r) => { if (r.status === 'MATCH') c.MATCH++; else if (r.status === 'DIFF') c.DIFF++; else c.OTHER++; });
    return c;
  }, [data]);
  return (
    <div className="stack">
      <section className="panel panel-pad stack">
        <h2 style={{ margin: 0 }}>{t('pp.title')}</h2>
        <p className="muted" style={{ margin: 0 }}>{t('pp.hint')}</p>
        {can('PAY_PREPARE') && <label className="btn" style={{ alignSelf: 'flex-start' }} aria-busy={busy}>{t('pp.upload')}
          <input type="file" accept=".csv,text/csv" hidden onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void upload(f); }} /></label>}
      </section>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.loaded ? <Empty>{t('pp.none')}</Empty> : (<>
          <div className="panel-head"><span>{t('pp.summary', { m: counts.MATCH, d: counts.DIFF, o: counts.OTHER })}</span>
            <Button small onClick={() => downloadCsv(`parallel-${run.month}.csv`, ['Employee no', 'Name', 'System net', 'Current net', 'Difference', 'Status', 'Note'],
              data.rows.map((r) => [r.employee_no, r.name ?? '', r.system_net ?? '', r.legacy_net ?? '', r.diff ?? '', r.status, r.note ?? '']))}>{t('c.export')}</Button></div>
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th className="r">{t('pp.system')}</th><th className="r">{t('pp.legacy')}</th><th className="r">{t('pp.diff')}</th><th>{t('c.status')}</th></tr></thead>
            <tbody>{data.rows.map((r) => (
              <tr key={r.employee_no}>
                <td data-label={t('c.employee')}>{r.name ?? '—'}<span className="sub num">{r.employee_no}</span>{r.note && <span className="sub">{r.note}</span>}</td>
                <td data-label={t('pp.system')} className="r num">{OMR(r.system_net)}</td>
                <td data-label={t('pp.legacy')} className="r num">{OMR(r.legacy_net)}</td>
                <td data-label={t('pp.diff')} className={`r num ${r.diff && r.diff > 0 ? 'diff-pos' : r.diff && r.diff < 0 ? 'diff-neg' : ''}`}>{r.diff === null ? '—' : OMR(r.diff)}</td>
                <td data-label={t('c.status')}><Badge tone={r.status === 'MATCH' ? 'ok' : r.status === 'DIFF' ? 'bad' : 'warn'}>{t(`pp.${r.status}` as Key)}</Badge></td>
              </tr>))}
            </tbody></table></div>
        </>)}
      </div>
    </div>
  );
}
