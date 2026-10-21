import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { tapi, type Adjustment, type LeaveType } from '../../lib/api_time';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, DateText, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync, useConfirm, useToast } from '../../components/ui';
import { EmployeePicker, MasterSelect } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { EmpCell, EntitySelect, useEntity } from '../../components/time';
import { fmtDateTime, todayMuscat } from '../../lib/format';
import { downloadCsv } from '../../lib/csv';
import { parseCsv } from '../../lib/punches';

type TabId = 'balances' | 'adjust' | 'types' | 'year';

export default function LeaveAdminPage() {
  const { t } = useI18n();
  const [params, setParams] = useSearchParams();
  const tab = (params.get('tab') ?? 'balances') as TabId;
  const setTab = (v: TabId) => { const p = new URLSearchParams(params); p.set('tab', v); setParams(p, { replace: true }); };
  return (
    <div className="stack">
      <PageHead title={t('la.title')} />
      <Tabs tabs={[{ id: 'balances', label: t('la.tab_balances') }, { id: 'adjust', label: t('la.tab_adjust') },
        { id: 'types', label: t('la.tab_types') }, { id: 'year', label: t('la.tab_year') }]} value={tab} onChange={setTab} label={t('la.title')} />
      {tab === 'balances' && <BalancesTab />}
      {tab === 'adjust' && <AdjustTab />}
      {tab === 'types' && <TypesTab />}
      {tab === 'year' && <YearTab />}
    </div>
  );
}

// ---------------------------------------------------------------------------
function BalancesTab() {
  const { t, L } = useI18n();
  const [entity, setEntity] = useEntity();
  const [type, setType] = useState('ANNUAL');
  const [dep, setDep] = useState<string | null>(null);
  const [due, setDue] = useState(false);
  const types = useAsync(() => tapi.listLeaveTypes(), []);
  const { data, error, loading, reload } = useAsync(() => tapi.listLeaveBalances({ entity_id: entity || null, leave_type: type, department_id: dep }), [entity, type, dep]);
  const rows = (data ?? []).filter((r) => !due || r.two_year_rule_due);
  const exportCsv = () => downloadCsv(`leave-balances-${type}-${todayMuscat()}.csv`,
    [t('emp.no'), t('emp.name'), t('c.department'), t('lv.entitled'), t('lv.used'), t('lv.pending'), t('lv.available'), t('lv.taken_24m')],
    rows.map((r) => [r.employee_no, L(r.full_name_en, r.full_name_ar), L(r.department_en, r.department_ar), r.entitled, r.used, r.pending, r.available, r.taken_24m]));
  return (
    <div className="stack">
      <div className="panel panel-pad row" style={{ gap: 16, alignItems: 'flex-end' }}>
        <EntitySelect value={entity} onChange={setEntity} />
        <div className="field" style={{ minWidth: 220 }}><label htmlFor="lb-type">{t('lv.type')}</label>
          <select id="lb-type" className="select" value={type} onChange={(e) => setType(e.target.value)}>
            {(types.data ?? []).filter((x) => x.quota_period !== 'NONE').map((x) => <option key={x.code} value={x.code}>{L(x.name_en, x.name_ar)}</option>)}
          </select></div>
        <div style={{ minWidth: 220 }}><MasterSelect kind="department" entityId={entity} label={t('c.department')} value={dep} onChange={setDep} /></div>
        {type === 'ANNUAL' && <Check label={t('la.two_year_only')} checked={due} onChange={setDue} />}
        <span className="spacer" />
        <Button onClick={exportCsv} disabled={!rows.length}>{t('c.export')}</Button>
      </div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !rows.length ? <Empty>{t('lv.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th className="r">{t('lv.entitled')}</th><th className="r">{t('lv.used')}</th>
              <th className="r">{t('lv.pending')}</th><th className="r">{t('lv.available')}</th>{type === 'ANNUAL' && <th className="r">{t('lv.taken_24m')}</th>}</tr></thead>
            <tbody>{rows.map((r) => (
              <tr key={r.employee_id}>
                <td data-label={t('c.employee')}><EmpCell r={r} tab="time" />{r.two_year_rule_due && <span className="sub"><Badge tone="warn">{t('lv.two_year')}</Badge></span>}</td>
                <td data-label={t('lv.entitled')} className="r num">{r.entitled ?? '—'}</td>
                <td data-label={t('lv.used')} className="r num">{r.used}</td>
                <td data-label={t('lv.pending')} className="r num">{r.pending}</td>
                <td data-label={t('lv.available')} className="r num"><b>{r.available ?? '—'}</b></td>
                {type === 'ANNUAL' && <td data-label={t('lv.taken_24m')} className="r num">{r.taken_24m}</td>}
              </tr>))}
            </tbody></table></div>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
function AdjustTab() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { push } = useToast();
  const [status, setStatus] = useState('PENDING');
  const { data, error, loading, reload } = useAsync(() => tapi.listAdjustments({ status: status || null }), [status]);
  const [sel, setSel] = useState<Set<string>>(new Set());
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const [form, setForm] = useState(false);
  const [csvErrors, setCsvErrors] = useState<{ row: number; message: string }[]>([]);
  useEffect(() => setSel(new Set()), [data]);
  const decidable = (data ?? []).filter((a) => a.can_decide);
  const decide = async (approve: boolean) => {
    const note = await confirm.ask({ title: t(approve ? 'la.approve_selected' : 'la.reject_selected'), reason: approve ? 'optional' : 'required',
      reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    if (await run(() => tapi.decideAdjustments([...sel], approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'))) void reload();
  };
  const importCsv = async (file: File) => {
    const rows = parseCsv(await file.text()).filter((r) => r.some((c) => c.trim() !== ''));
    const head = (rows[0] ?? []).map((h) => h.toLowerCase().trim());
    const ix = (k: string) => head.indexOf(k);
    if (rows.length < 2 || ix('employee_no') < 0 || ix('days') < 0) { push(t('la.csv_hint'), true); return; }
    const payload = rows.slice(1).map((r) => ({ employee_no: r[ix('employee_no')] ?? '', leave_type: r[ix('leave_type')] || 'ANNUAL',
      kind: 'OPENING', days: r[ix('days')] ?? '', effective_date: r[ix('effective_date')] || null, reason: r[ix('reason')] || 'Opening balance' }));
    const res = await run(() => tapi.proposeAdjustments(payload));
    if (res) { push(t('la.proposed', { n: res.proposed })); setCsvErrors(res.errors); void reload(); }
  };
  return (
    <div className="stack">
      {can('LEAVE_WRITE') && (
        <div className="panel panel-pad row" style={{ gap: 12 }}>
          <Button kind="primary" onClick={() => setForm(true)}>{t('la.propose')}</Button>
          <label className="btn">{t('la.opening')}<input type="file" accept=".csv,text/csv" hidden onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void importCsv(f); }} /></label>
          <span className="muted" style={{ flex: 1, minWidth: 260 }}>{t('la.csv_hint')}</span>
        </div>
      )}
      {csvErrors.length > 0 && (
        <div className="note note-warn"><b>{t('la.errors', { n: csvErrors.length })}</b>
          <ul style={{ margin: '6px 0 0' }}>{csvErrors.slice(0, 20).map((e) => <li key={e.row}>{t('imp.line')} {e.row + 1}: {e.message}</li>)}</ul></div>
      )}
      <div className="panel">
        <div className="panel-head">
          <h2>{t('la.tab_adjust')}</h2>
          <div className="row" style={{ gap: 8 }}>
            {decidable.length > 0 && <>
              <Button small kind="primary" busy={busy} disabled={!sel.size} onClick={() => void decide(true)}>{t('la.approve_selected')}</Button>
              <Button small kind="danger" busy={busy} disabled={!sel.size} onClick={() => void decide(false)}>{t('la.reject_selected')}</Button></>}
            <select className="select" style={{ width: 160 }} value={status} onChange={(e) => setStatus(e.target.value)} aria-label={t('c.status')}>
              <option value="">{t('c.all')}</option>
              {['PENDING', 'APPROVED', 'REJECTED'].map((s) => <option key={s} value={s}>{t(`rst.${s}` as Key)}</option>)}
            </select>
          </div>
        </div>
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('la.none_pending')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{decidable.length > 0 && <input type="checkbox" aria-label={t('c.all')} checked={sel.size === decidable.length}
              onChange={(e) => setSel(e.target.checked ? new Set(decidable.map((a) => a.id)) : new Set())} />}</th>
              <th>{t('c.employee')}</th><th>{t('lv.type')}</th><th>{t('la.kind')}</th><th className="r">{t('lv.days')}</th><th>{t('la.effective')}</th>
              <th>{t('c.reason')}</th><th>{t('c.status')}</th></tr></thead>
            <tbody>{data.map((a: Adjustment) => (
              <tr key={a.id}>
                <td>{a.can_decide && <input type="checkbox" aria-label={a.employee_no} checked={sel.has(a.id)}
                  onChange={(e) => { const s = new Set(sel); if (e.target.checked) s.add(a.id); else s.delete(a.id); setSel(s); }} />}</td>
                <td data-label={t('c.employee')}><EmpCell r={a} tab="time" /></td>
                <td data-label={t('lv.type')}>{L(a.name_en, a.name_ar)}</td>
                <td data-label={t('la.kind')}>{t(`la.k_${a.kind}` as Key)}</td>
                <td data-label={t('lv.days')} className="r num">{a.days > 0 ? `+${a.days}` : a.days}</td>
                <td data-label={t('la.effective')}><DateText v={a.effective_date} /></td>
                <td data-label={t('c.reason')}>{a.reason}{a.decision_note && <span className="sub">{a.decision_note}</span>}</td>
                <td data-label={t('c.status')}><Badge tone={a.status === 'APPROVED' ? 'ok' : a.status === 'REJECTED' ? 'bad' : 'warn'}>{t(`rst.${a.status === 'PENDING' ? 'PENDING' : a.status}` as Key)}</Badge>
                  <span className="sub">{a.proposed_by_name} · {fmtDateTime(a.proposed_at)}</span></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
      <AdjustDialog open={form} onClose={() => setForm(false)} onDone={() => void reload()} />
      {confirm.node}
    </div>
  );
}

function AdjustDialog({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: () => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const { push } = useToast();
  const types = useAsync(() => tapi.listLeaveTypes(), []);
  const [f, setF] = useState({ employee_id: null as string | null, leave_type: 'ANNUAL', kind: 'ADJUSTMENT', days: '', effective_date: todayMuscat(), reason: '' });
  useEffect(() => { if (open) setF({ employee_id: null, leave_type: 'ANNUAL', kind: 'ADJUSTMENT', days: '', effective_date: todayMuscat(), reason: '' }); }, [open]);
  const submit = async () => {
    const r = await run(() => tapi.proposeAdjustments([f]));
    if (!r) return;
    if (r.errors.length) push(r.errors[0].message, true);
    else { push(t('la.proposed', { n: r.proposed })); onDone(); onClose(); }
  };
  return (
    <Modal open={open} title={t('la.propose')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy}
        disabled={!f.employee_id || !f.days || f.reason.trim().length < 3} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <EmployeePicker label={t('c.employee')} value={f.employee_id} onChange={(v) => setF({ ...f, employee_id: v })} />
        <div className="form-grid">
          <Select label={t('lv.type')} value={f.leave_type} onChange={(e) => setF({ ...f, leave_type: e.target.value })}>
            {(types.data ?? []).filter((x) => x.quota_period !== 'NONE').map((x) => <option key={x.code} value={x.code}>{L(x.name_en, x.name_ar)}</option>)}
          </Select>
          <Select label={t('la.kind')} value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>
            <option value="ADJUSTMENT">{t('la.k_ADJUSTMENT')}</option><option value="OPENING">{t('la.k_OPENING')}</option>
          </Select>
          <Input label={t('la.days')} ltr inputMode="decimal" value={f.days} onChange={(e) => setF({ ...f, days: e.target.value })} />
          <Input label={t('la.effective')} type="date" ltr value={f.effective_date} onChange={(e) => setF({ ...f, effective_date: e.target.value })} />
        </div>
        <Textarea label={t('c.reason')} required value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} />
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function TypesTab() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload } = useAsync(() => tapi.listLeaveTypes(), []);
  const [edit, setEdit] = useState<Partial<LeaveType> | null>(null);
  return (
    <div className="panel">
      <div className="panel-head"><h2>{t('la.tab_types')}</h2>
        {can('RULES_APPROVE') && <Button small onClick={() => setEdit({ code: '', name_en: '', name_ar: '', quota_period: 'YEAR', pay_mode: 'FULL', paid_by: 'EMPLOYER',
          accrual: 'NONE', count_mode: 'CALENDAR', gender: 'ALL', nationality: 'ALL', min_service_months: 0, is_active: true, quota_days: 1 })}>{t('la.new_type')}</Button>}</div>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('lv.type')}</th><th className="r">{t('la.quota')}</th><th>{t('la.period')}</th><th>{t('la.pay_mode')}</th>
            <th>{t('la.gender')}</th><th>{t('la.legal')}</th><th /></tr></thead>
          <tbody>{(data ?? []).map((x) => (
            <tr key={x.code} style={{ opacity: x.is_active ? 1 : 0.55 }}>
              <td data-label={t('lv.type')}>{L(x.name_en, x.name_ar)}<span className="sub num">{x.code}</span>{x.notes && <span className="sub">{x.notes}</span>}</td>
              <td data-label={t('la.quota')} className="r num">{x.quota_days ?? '—'}{x.legal_min_days !== null && <span className="sub">{t('la.legal_min', { n: Number(x.legal_min_days) })}</span>}</td>
              <td data-label={t('la.period')}>{t(`la.qp_${x.quota_period}` as Key)}{x.accrual === 'MONTHLY' && <span className="sub">{t('la.ac_MONTHLY')}</span>}</td>
              <td data-label={t('la.pay_mode')}>{t(`la.pm_${x.pay_mode}` as Key)}{x.paid_by === 'FUND' && <span className="sub">{t('lv.paid_by_FUND')}</span>}
                {x.pay_mode === 'TIERED' && <span className="sub">{x.pay_tiers.map((p) => `${p.from}–${p.to}: ${p.pct}%`).join(' · ')}</span>}</td>
              <td data-label={t('la.gender')}>{t(`la.g_${x.gender}` as Key)}{x.nationality !== 'ALL' && <span className="sub">{t(`la.n_${x.nationality}` as Key)}</span>}</td>
              <td data-label={t('la.legal')}>{x.legal_basis ?? t('rule.COMPANY_POLICY')}</td>
              <td className="r">{can('RULES_APPROVE') && <Button small onClick={() => setEdit(x)}>{t('c.edit')}</Button>}</td>
            </tr>))}
          </tbody></table></div>
      )}
      <TypeDialog row={edit} onClose={() => setEdit(null)} onDone={() => void reload()} />
    </div>
  );
}

function TypeDialog({ row, onClose, onDone }: { row: Partial<LeaveType> | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState<Partial<LeaveType>>({});
  useEffect(() => { if (row) setF(row); }, [row]);
  const isNew = !!row && !row.name_en;
  const sel = (k: keyof LeaveType, opts: string[], prefix: string, label: Key) => (
    <Select label={t(label)} value={String(f[k] ?? '')} onChange={(e) => setF({ ...f, [k]: e.target.value })}>
      {opts.map((o) => <option key={o} value={o}>{t(`${prefix}${o}` as Key)}</option>)}
    </Select>);
  const submit = async () => {
    const p = { ...f, quota_days: f.quota_period === 'NONE' ? null : (f.quota_days === null || f.quota_days === undefined ? null : String(f.quota_days)),
      carry_forward_max: f.carry_forward_max === null || f.carry_forward_max === undefined || String(f.carry_forward_max) === '' ? null : String(f.carry_forward_max),
      min_service_months: String(f.min_service_months ?? 0), event_window_days: f.event_window_days ? String(f.event_window_days) : null,
      max_before_event_days: f.max_before_event_days ? String(f.max_before_event_days) : null, sort: f.sort ? String(f.sort) : null };
    if (await run(() => tapi.saveLeaveType(p as Record<string, unknown>), t('c.saved'))) { onDone(); onClose(); }
  };
  return (
    <Modal open={!!row} title={isNew ? t('la.new_type') : t('la.edit_type')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.code || !f.name_en || !f.name_ar} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="form-grid">
        <Input label={t('c.code')} ltr required disabled={!isNew} value={f.code ?? ''} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} />
        <span />
        <Input label={t('c.name_en')} required value={f.name_en ?? ''} onChange={(e) => setF({ ...f, name_en: e.target.value })} />
        <Input label={t('c.name_ar')} required value={f.name_ar ?? ''} onChange={(e) => setF({ ...f, name_ar: e.target.value })} />
        {sel('quota_period', ['YEAR', 'EVENT', 'ONCE', 'NONE'], 'la.qp_', 'la.period')}
        <Input label={t('la.quota')} ltr inputMode="decimal" disabled={f.quota_period === 'NONE'} value={f.quota_days ?? ''}
          hint={f.legal_min_days ? t('la.legal_min', { n: Number(f.legal_min_days) }) : undefined}
          onChange={(e) => setF({ ...f, quota_days: e.target.value === '' ? null : (e.target.value as unknown as number) })} />
        {sel('pay_mode', ['FULL', 'TIERED', 'UNPAID'], 'la.pm_', 'la.pay_mode')}
        {sel('paid_by', ['EMPLOYER', 'FUND', 'NONE'], 'la.pbb_', 'la.paid_by')}
        {sel('accrual', ['NONE', 'MONTHLY'], 'la.ac_', 'la.accrual')}
        {sel('count_mode', ['CALENDAR', 'CALENDAR_EXCL_HOLIDAYS', 'WORKING'], 'la.cm_', 'la.count_mode')}
        <Input label={t('la.min_service')} ltr inputMode="numeric" value={f.min_service_months ?? 0} onChange={(e) => setF({ ...f, min_service_months: Number(e.target.value) || 0 })} />
        <Input label={t('la.carry')} ltr inputMode="decimal" value={f.carry_forward_max ?? ''} onChange={(e) => setF({ ...f, carry_forward_max: e.target.value === '' ? null : (e.target.value as unknown as number) })} />
        {sel('gender', ['ALL', 'M', 'F'], 'la.g_', 'la.gender')}
        {sel('nationality', ['ALL', 'OMANI', 'EXPAT'], 'la.n_', 'la.nat')}
        <Input label={t('la.legal')} className="span-2" value={f.legal_basis ?? ''} onChange={(e) => setF({ ...f, legal_basis: e.target.value })} />
        <Textarea label={t('c.notes')} className="span-2" value={f.notes ?? ''} onChange={(e) => setF({ ...f, notes: e.target.value })} />
        <div className="span-2 row" style={{ gap: 18 }}>
          <Check label={t('la.req_doc')} checked={!!f.requires_document} onChange={(v) => setF({ ...f, requires_document: v })} />
          <Check label={t('la.event')} checked={!!f.needs_event_date} onChange={(v) => setF({ ...f, needs_event_date: v })} />
          <Check label={t('la.half')} checked={!!f.allow_half_day} onChange={(v) => setF({ ...f, allow_half_day: v })} />
          <Check label={t('la.negative')} checked={!!f.allow_negative} onChange={(v) => setF({ ...f, allow_negative: v })} />
          <Check label={t('la.ticket')} checked={!!f.ticket_eligible} onChange={(v) => setF({ ...f, ticket_eligible: v })} />
          <Check label={t('c.active')} checked={f.is_active !== false} onChange={(v) => setF({ ...f, is_active: v })} />
        </div>
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
function YearTab() {
  const { t } = useI18n();
  const { me, can, reload: reloadMe } = useSession();
  const { push } = useToast();
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const current = (me?.settings?.leave_opening_date as string | null) ?? '';
  const [opening, setOpening] = useState(current ? current.slice(0, 7) : '');
  const lastYear = Number(todayMuscat().slice(0, 4)) - 1;
  return (
    <div className="grid-2">
      <section className="panel panel-pad stack">
        <h2>{t('la.opening_date')}</h2>
        <p className="muted" style={{ margin: 0 }}>{t('la.opening_date_hint')}</p>
        <div className="row" style={{ alignItems: 'flex-end' }}>
          <Input label={t('att.month')} type="month" ltr value={opening} disabled={!can('USERS_ADMIN')} onChange={(e) => setOpening(e.target.value)} />
          {can('USERS_ADMIN') && <Button busy={busy} disabled={!opening} onClick={async () => {
            if (await run(() => api.saveSetting('leave_opening_date', `${opening}-01`), t('la.opening_saved'))) void reloadMe();
          }}>{t('c.save')}</Button>}
        </div>
      </section>
      <section className="panel panel-pad stack">
        <h2>{t('la.run_accrual')}</h2>
        {can('LEAVE_WRITE') && <div><Button kind="primary" busy={busy} onClick={async () => {
          const r = await run(() => tapi.runAccrual(null));
          if (r) push(t('la.accrual_done', { n: r.created, d: r.through }));
        }}>{t('la.run_accrual')}</Button></div>}
        {can('LEAVE_APPROVE') && <div><Button busy={busy} onClick={async () => {
          const ok = await confirm.ask({ title: t('la.close_year', { y: lastYear }), body: t('la.close_body'), danger: true });
          if (ok === null) return;
          const r = await run(() => tapi.closeYear(lastYear));
          if (r) push(t('la.close_done', { n: r.lapsed }));
        }}>{t('la.close_year', { y: lastYear })}</Button></div>}
      </section>
      {confirm.node}
    </div>
  );
}
