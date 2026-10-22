import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { CalendarClock, FileChartColumn, FileDown, FileSpreadsheet, Lock, Play, Presentation, Search } from 'lucide-react';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, useAction, useAsync, useToast } from '../../components/ui';
import { MasterSelect } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { EntitySelect, useEntity } from '../../components/time';
import { tapi } from '../../lib/api_time';
import { todayMuscat } from '../../lib/format';
import {
  GROUPS, cellText, repapi, reportTotals, resolvePeriod,
  type ReportCatalog, type ReportDef, type ReportParam, type ReportParams, type ReportResult, type ReportSchedule,
} from '../../lib/api_rep';

type Tab = 'reports' | 'board' | 'schedules';
const PREVIEW_ROWS = 300;
const exporter = () => import('../../lib/report_export');

function monthStart(today: string): string { return today.slice(0, 8) + '01'; }

/** Default filter values for a report (today, this month …). */
function defaults(today: string): ReportParams {
  return { as_of: today, from: monthStart(today), to: today, month: today.slice(0, 7), days: 90, leave_type: 'ANNUAL' };
}

/** Only the filters the report uses are sent. */
function paramsFor(def: ReportDef, all: ReportParams, entity: string): ReportParams {
  const out: ReportParams = {};
  const pick = (k: string) => { if (all[k] !== undefined && all[k] !== '' && all[k] !== null) out[k] = all[k]; };
  if (def.params.includes('entity')) out.entity_id = entity;
  for (const p of def.params) {
    if (p === 'from_to') { pick('from'); pick('to'); }
    else if (p === 'run') pick('run_id');
    else if (p === 'department') pick('department_id');
    else if (p === 'cycle') pick('cycle_id');
    else if (p !== 'entity') pick(p);
  }
  return out;
}

export default function ReportsPage() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const { data: cat, error, loading, reload } = useAsync(() => repapi.catalog(), []);
  const tabParam = sp.get('tab');
  const [tab, setTabState] = useState<Tab>(tabParam === 'board' || tabParam === 'schedules' ? tabParam : 'reports');
  const setTab = (v: Tab) => { setTabState(v); setSp(v === 'reports' ? {} : { tab: v }, { replace: true }); };
  const tabs = useMemo(() => {
    const list: { id: Tab; label: string }[] = [{ id: 'reports', label: t('rp.tab_reports') }];
    if (cat?.board_pack) list.push({ id: 'board', label: t('rp.tab_board') });
    if (cat?.can_schedule) list.push({ id: 'schedules', label: t('rp.tab_schedules') });
    return list;
  }, [cat, t]);
  if (loading && !cat) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!cat) return null;
  return (
    <div className="stack">
      <PageHead title={t('rp.title')} sub={t('rp.sub', { n: cat.reports.length })} />
      {tabs.length > 1 && <Tabs label={t('rp.title')} value={tab} onChange={setTab} tabs={tabs} />}
      {tab === 'reports' && <ReportRunner cat={cat} scheduleId={sp.get('schedule')} initialCode={sp.get('code')} autoRun={sp.get('run') === '1'}
        onScheduleUsed={() => setSp({}, { replace: true })} />}
      {tab === 'board' && <BoardPackPanel />}
      {tab === 'schedules' && <SchedulesPanel cat={cat} canMg={can('MG_PAY')} L={L} />}
    </div>
  );
}

// ============================================================================ runner
function ReportRunner({ cat, scheduleId, initialCode, autoRun, onScheduleUsed }:
  { cat: ReportCatalog; scheduleId: string | null; initialCode: string | null; autoRun: boolean; onScheduleUsed: () => void }) {
  const { t, L, lang } = useI18n();
  const { can } = useSession();
  const today = todayMuscat();
  const [entity, setEntity] = useEntity();
  const [search, setSearch] = useState('');
  const [code, setCode] = useState<string>(cat.reports.find((r) => r.code === initialCode?.toUpperCase())?.code ?? cat.reports[0]?.code ?? '');
  const [vals, setVals] = useState<ReportParams>(() => defaults(today));
  const [result, setResult] = useState<{ r: ReportResult; params: ReportParams } | null>(null);
  const [making, setMaking] = useState<'' | 'xlsx' | 'pdf'>('');
  const { busy, run } = useAction();
  const { push } = useToast();
  const { errText } = useI18n();
  const def = cat.reports.find((r) => r.code === code) ?? null;

  const execute = async (d: ReportDef, v: ReportParams) => {
    const params = paramsFor(d, v, entity);
    const r = await run(() => repapi.run(d.code, params));
    if (r) setResult({ r, params });
  };

  // a link such as /reports?code=P01&run=1 opens the report and runs it with the default filters
  useEffect(() => {
    if (autoRun && def && entity && !scheduleId) void execute(def, vals);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entity]);

  // opened from a scheduled reminder: load its filters and run it
  useEffect(() => {
    if (!scheduleId) return;
    void (async () => {
      const s = await run(() => repapi.schedule(scheduleId));
      onScheduleUsed();
      if (!s) return;
      const d = cat.reports.find((r) => r.code === s.code);
      if (!d) return;
      const v = { ...defaults(today), ...resolvePeriod(s.params) };
      if (s.params.entity_id) setEntity(String(s.params.entity_id));
      setCode(d.code); setVals(v);
      const params = paramsFor(d, v, String(s.params.entity_id ?? entity));
      const r = await run(() => repapi.run(d.code, params));
      if (r) setResult({ r, params });
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scheduleId]);

  const q = search.trim().toLowerCase();
  const list = cat.reports.filter((r) => !q || r.code.toLowerCase().includes(q) || r.name_en.toLowerCase().includes(q) || r.name_ar.includes(search.trim())
    || r.desc_en.toLowerCase().includes(q));
  const set = (k: string, v: string | number | null) => setVals((o) => ({ ...o, [k]: v }));
  const choose = (c: string) => { setCode(c); setResult(null); };

  const make = async (kind: 'xlsx' | 'pdf') => {
    if (!result) return;
    setMaking(kind);
    try {
      const m = await exporter();
      const lbl = (k: string) => t(k as Key);
      if (kind === 'xlsx') await m.exportExcel(result.r, result.params, lang, lbl);
      else await m.exportPdf(result.r, result.params, lang, lbl);
    } catch (e) {
      push(errText(e), true);
    } finally {
      setMaking('');
    }
  };

  const runs = (cat.runs ?? []).filter((r) => r.entity_id === entity);
  const cycles = (cat.cycles ?? []).filter((c) => c.entity_id === entity);
  const leaveTypes = useAsync(() => (def?.params.includes('leave_type') ? tapi.listLeaveTypes() : Promise.resolve([])), [def?.code]);

  const field = (p: ReportParam) => {
    switch (p) {
      case 'entity': return <EntitySelect key={p} value={entity} onChange={(v) => { setEntity(v); set('run_id', null); set('department_id', null); set('cycle_id', null); }} />;
      case 'as_of': return <Input key={p} type="date" ltr label={t('rp.as_of')} value={String(vals.as_of ?? '')} onChange={(e) => set('as_of', e.target.value)} />;
      case 'from_to': return [
        <Input key="from" type="date" ltr label={t('rp.from')} value={String(vals.from ?? '')} onChange={(e) => set('from', e.target.value)} />,
        <Input key="to" type="date" ltr label={t('rp.to')} value={String(vals.to ?? '')} onChange={(e) => set('to', e.target.value)} />];
      case 'month': return <Input key={p} type="month" ltr label={t('rp.month')} value={String(vals.month ?? '')} onChange={(e) => set('month', e.target.value)} />;
      case 'run': return (
        <Select key={p} label={t('rp.run')} value={String(vals.run_id ?? '')} onChange={(e) => set('run_id', e.target.value || null)}>
          <option value="">{t('rp.latest_run')}</option>
          {runs.map((r) => <option key={r.id} value={r.id}>{r.month} · {r.pay_group} · {t(`rp.st_${r.status}` as Key)}</option>)}
        </Select>);
      case 'department': return <MasterSelect key={p} kind="department" entityId={entity} label={t('rp.department')} value={(vals.department_id as string) ?? null} onChange={(v) => set('department_id', v)} />;
      case 'pay_group': return (
        <Select key={p} label={t('rp.pay_group')} value={String(vals.pay_group ?? '')} onChange={(e) => set('pay_group', e.target.value || null)}>
          <option value="">{t('rp.all')}</option><option value="NMG">{t('pg.NMG')}</option>{can('MG_PAY') && <option value="MG">{t('pg.MG')}</option>}
        </Select>);
      case 'nationality_group': return (
        <Select key={p} label={t('rp.nationality')} value={String(vals.nationality_group ?? '')} onChange={(e) => set('nationality_group', e.target.value || null)}>
          <option value="">{t('rp.all')}</option><option value="OMANI">{t('rp.omani')}</option><option value="EXPAT">{t('rp.expat')}</option>
        </Select>);
      case 'days': return <Input key={p} type="number" ltr inputMode="numeric" label={t('rp.days')} value={String(vals.days ?? '')} onChange={(e) => set('days', e.target.value ? Number(e.target.value) : null)} />;
      case 'leave_type': return (
        <Select key={p} label={t('rp.leave_type')} value={String(vals.leave_type ?? 'ANNUAL')} onChange={(e) => set('leave_type', e.target.value)}>
          {(leaveTypes.data ?? []).map((lt) => <option key={lt.code} value={lt.code}>{L(lt.name_en, lt.name_ar)}</option>)}
        </Select>);
      case 'cycle': return (
        <Select key={p} label={t('rp.cycle')} value={String(vals.cycle_id ?? '')} onChange={(e) => set('cycle_id', e.target.value || null)}>
          <option value="">{t('rp.latest_cycle')}</option>{cycles.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </Select>);
      case 'table': return (
        <Select key={p} label={t('rp.table')} value={String(vals.table ?? '')} onChange={(e) => set('table', e.target.value || null)}>
          <option value="">{t('rp.all')}</option>{(cat.audit_tables ?? []).map((x) => <option key={x} value={x}>{x}</option>)}
        </Select>);
      default: return null;
    }
  };

  const r = result?.r;
  const totals = r ? reportTotals(r.columns, r.rows) : null;
  return (
    <div className="rp-layout">
      <aside className="panel rp-list" aria-label={t('rp.catalogue')}>
        <div className="rp-search"><Search size={16} aria-hidden="true" />
          <input className="input" type="search" placeholder={t('rp.search')} aria-label={t('rp.search')} value={search} onChange={(e) => setSearch(e.target.value)} /></div>
        {GROUPS.map((g) => {
          const items = list.filter((x) => x.grp === g);
          if (!items.length) return null;
          return (
            <div key={g} className="rp-group">
              <h3>{t(`rp.g_${g}` as Key)}</h3>
              <ul>{items.map((x) => (
                <li key={x.code}><button type="button" className={x.code === code ? 'on' : ''} aria-current={x.code === code ? 'true' : undefined} onClick={() => choose(x.code)}>
                  <span className="rp-code num">{x.code}</span><span className="rp-name">{L(x.name_en, x.name_ar)}</span>
                  {(x.money || x.sensitive) && <Lock size={13} aria-label={t('rp.restricted')} />}
                </button></li>))}
              </ul>
            </div>);
        })}
        {!list.length && <Empty>{t('rp.none_found')}</Empty>}
      </aside>
      <section className="stack rp-main">
        {!def ? <Empty>{t('rp.none')}</Empty> : (
          <div className="panel panel-pad stack">
            <div className="row" style={{ alignItems: 'flex-start', gap: 12 }}>
              <span className="rp-icon"><FileChartColumn size={20} aria-hidden="true" /></span>
              <div style={{ flex: 1 }}>
                <h2 style={{ margin: 0 }}>{L(def.name_en, def.name_ar)} <span className="muted num" style={{ fontWeight: 400 }}>{def.code}</span></h2>
                <p className="muted" style={{ margin: '4px 0 0' }}>{L(def.desc_en, def.desc_ar)}</p>
              </div>
              {def.money && <Badge tone="warn">{t('rp.money')}</Badge>}
              {def.sensitive && <Badge tone="bad">{t('rp.sensitive')}</Badge>}
            </div>
            {def.params.length > 0 && <div className="form-grid rp-filters">{def.params.flatMap((p) => { const f = field(p); return Array.isArray(f) ? f : [f]; })}</div>}
            <div className="row">
              <Button kind="primary" busy={busy} onClick={() => void execute(def, vals)}><Play size={16} aria-hidden="true" />{t('rp.run_btn')}</Button>
              {r && r.code === def.code && <>
                <Button busy={making === 'xlsx'} disabled={!!making} onClick={() => void make('xlsx')}><FileSpreadsheet size={16} aria-hidden="true" />{t('rp.excel')}</Button>
                <Button busy={making === 'pdf'} disabled={!!making} onClick={() => void make('pdf')}><FileDown size={16} aria-hidden="true" />{t('rp.pdf')}</Button>
              </>}
              {(def.money || def.sensitive) && <span className="muted" style={{ fontSize: 13 }}>{t('rp.logged')}</span>}
            </div>
          </div>)}
        {r && def && r.code === def.code && (
          <div className="panel">
            <div className="panel-head"><h2>{t('rp.preview')}</h2>
              <span className="muted">{t('rp.rows', { n: r.rows.length })}{r.meta?.month ? ` · ${r.meta.month} · ${r.meta.pay_group} · ${t(`rp.st_${r.meta.status}` as Key)}` : ''}</span></div>
            {r.rows.length === 0 ? <Empty>{t('rp.no_rows')}</Empty> : (
              <div className="table-wrap rp-table"><table className="t">
                <thead><tr>{r.columns.map((c) => <th key={c.k} className={c.t === 'text' ? undefined : 'n'}>{lang === 'ar' ? c.ar : c.en}</th>)}</tr></thead>
                <tbody>{r.rows.slice(0, PREVIEW_ROWS).map((row, i) => (
                  <tr key={i}>{r.columns.map((c) => <td key={c.k} className={c.t === 'text' ? undefined : 'n num'}>{cellText(row[c.k], c.t, lang)}</td>)}</tr>))}
                </tbody>
                {totals && <tfoot><tr>{r.columns.map((c, i) => <td key={c.k} className={c.t === 'text' ? undefined : 'n num'}>
                  {i === 0 ? t('rp.total') : c.k in totals ? cellText(totals[c.k], c.t, lang) : ''}</td>)}</tr></tfoot>}
              </table></div>)}
            {r.rows.length > PREVIEW_ROWS && <p className="muted panel-pad" style={{ margin: 0 }}>{t('rp.preview_cut', { n: PREVIEW_ROWS })}</p>}
          </div>)}
      </section>
    </div>
  );
}

// ============================================================================ board pack
function BoardPackPanel() {
  const { t, lang } = useI18n();
  const [entity, setEntity] = useEntity();
  const { busy, run } = useAction();
  const make = async () => {
    await run(async () => {
      const b = await repapi.boardPack(entity);
      const m = await exporter();
      await m.exportBoardPack(b, lang, (k) => t(k as Key));
      return true;
    }, t('bp.done'));
  };
  return (
    <div className="panel panel-pad stack" style={{ maxWidth: 820 }}>
      <div className="row" style={{ gap: 12, alignItems: 'flex-start' }}>
        <span className="rp-icon"><Presentation size={20} aria-hidden="true" /></span>
        <div style={{ flex: 1 }}>
          <h2 style={{ margin: 0 }}>{t('bp.title')}</h2>
          <p className="muted" style={{ margin: '4px 0 0' }}>{t('bp.hint')}</p>
        </div>
      </div>
      <ul className="rp-bullets">{(['bp.c1', 'bp.c2', 'bp.c3', 'bp.c4', 'bp.c5'] as Key[]).map((k) => <li key={k}>{t(k)}</li>)}</ul>
      <div className="row"><EntitySelect value={entity} onChange={setEntity} />
        <Button kind="primary" busy={busy} disabled={!entity} onClick={() => void make()}><Presentation size={16} aria-hidden="true" />{t('bp.download')}</Button></div>
    </div>
  );
}

// ============================================================================ schedules
function SchedulesPanel({ cat, canMg, L }: { cat: ReportCatalog; canMg: boolean; L: (a: string | null | undefined, b: string | null | undefined) => string }) {
  const { t } = useI18n();
  const { data, error, loading, reload } = useAsync(() => repapi.schedules(), []);
  const people = useAsync(() => repapi.recipients(), []);
  const [entity] = useEntity();
  const [edit, setEdit] = useState<{ id?: string; code: string; name: string; day: number; period: string; pay_group: string; recipients: string[] } | null>(null);
  const { busy, run } = useAction();
  const def = edit ? cat.reports.find((r) => r.code === edit.code) : null;
  const periodic = !!def && (def.params.includes('from_to') || def.params.includes('month') || def.params.includes('as_of'));
  const eligible = (people.data ?? []).filter((p) => def && p.perms.includes(def.perm) && (!(def.money && edit?.pay_group === 'MG') || p.perms.includes('MG_PAY')));
  const save = async () => {
    if (!edit || !def) return;
    const params: ReportParams = { entity_id: entity };
    if (periodic) params.period = edit.period;
    if (def.params.includes('pay_group') && edit.pay_group) params.pay_group = edit.pay_group;
    if (def.params.includes('run') && edit.pay_group) params.pay_group = edit.pay_group;
    const r = await run(() => repapi.saveSchedule({ id: edit.id, code: edit.code, name: edit.name.trim() || null, params, recipients: edit.recipients, day_of_month: edit.day }), t('c.saved'));
    if (r) { setEdit(null); void reload(); }
  };
  const toggle = async (s: ReportSchedule) => { const r = await run(() => repapi.setScheduleActive(s.id, !s.is_active), t('c.saved')); if (r) void reload(); };
  const open = (s?: ReportSchedule) => setEdit(s
    ? { id: s.id, code: s.code, name: s.name ?? '', day: s.day_of_month, period: String(s.params.period ?? 'PREV_MONTH'), pay_group: String(s.params.pay_group ?? ''), recipients: s.recipients }
    : { code: cat.reports[0]?.code ?? '', name: '', day: 3, period: 'PREV_MONTH', pay_group: '', recipients: [] });
  return (
    <div className="stack">
      <div className="note">{t('sc.hint')}</div>
      <div className="row"><Button kind="primary" onClick={() => open()}><CalendarClock size={16} aria-hidden="true" />{t('sc.new')}</Button></div>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('sc.none')}</Empty> : (
        <div className="panel"><div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('sc.report')}</th><th>{t('sc.day')}</th><th>{t('sc.recipients')}</th><th>{t('sc.last')}</th><th>{t('c.status')}</th><th /></tr></thead>
          <tbody>{data.map((s) => (
            <tr key={s.id}>
              <td data-label={t('sc.report')}><b>{s.name || L(s.report_en, s.report_ar)}</b><span className="sub num">{s.code} · {t(`sc.p_${String(s.params.period ?? 'NONE')}` as Key)}</span></td>
              <td data-label={t('sc.day')} className="num">{s.day_of_month}</td>
              <td data-label={t('sc.recipients')}>{s.recipient_names.map((x) => x.name).join(', ')}</td>
              <td data-label={t('sc.last')} className="num">{s.last_sent_on ?? '—'}</td>
              <td data-label={t('c.status')}>{s.is_active ? <Badge tone="ok">{t('sc.on')}</Badge> : <Badge>{t('sc.off')}</Badge>}</td>
              <td className="row" style={{ gap: 6 }}><Button small onClick={() => open(s)}>{t('c.edit')}</Button>
                <Button small busy={busy} onClick={() => void toggle(s)}>{s.is_active ? t('sc.pause') : t('sc.resume')}</Button></td>
            </tr>))}
          </tbody></table></div></div>)}
      <Modal open={!!edit} title={edit?.id ? t('sc.edit') : t('sc.new')} onClose={() => setEdit(null)} wide
        footer={<><Button onClick={() => setEdit(null)}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!edit?.recipients.length} onClick={() => void save()}>{t('c.save')}</Button></>}>
        {edit && <div className="form-grid">
          <Select label={t('sc.report')} required value={edit.code} onChange={(e) => setEdit({ ...edit, code: e.target.value, recipients: [] })}>
            {cat.reports.map((r) => <option key={r.code} value={r.code}>{r.code} — {L(r.name_en, r.name_ar)}</option>)}
          </Select>
          <Input label={t('sc.name')} value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} />
          <Input label={t('sc.day')} type="number" ltr min={1} max={28} required value={String(edit.day)} hint={t('sc.day_hint')}
            onChange={(e) => setEdit({ ...edit, day: Math.min(28, Math.max(1, Number(e.target.value) || 1)) })} />
          {periodic && <Select label={t('sc.period')} value={edit.period} onChange={(e) => setEdit({ ...edit, period: e.target.value })}>
            <option value="PREV_MONTH">{t('sc.p_PREV_MONTH')}</option><option value="THIS_MONTH">{t('sc.p_THIS_MONTH')}</option><option value="YTD">{t('sc.p_YTD')}</option>
          </Select>}
          {def && (def.params.includes('pay_group') || def.params.includes('run')) && (
            <Select label={t('rp.pay_group')} value={edit.pay_group} onChange={(e) => setEdit({ ...edit, pay_group: e.target.value, recipients: [] })}>
              <option value="">{def.params.includes('run') ? t('pg.NMG') : t('rp.all')}</option>{canMg && <option value="MG">{t('pg.MG')}</option>}
            </Select>)}
          <fieldset className="span-2 rp-recipients">
            <legend>{t('sc.recipients')}</legend>
            {!eligible.length ? <p className="muted">{t('sc.no_people')}</p> : eligible.map((p) => (
              <Check key={p.user_id} label={`${p.name} (${p.email})`} checked={edit.recipients.includes(p.user_id)}
                onChange={(v) => setEdit({ ...edit, recipients: v ? [...edit.recipients, p.user_id] : edit.recipients.filter((x) => x !== p.user_id) })} />))}
            <p className="muted" style={{ fontSize: 13, margin: 0 }}>{t('sc.only_allowed')}</p>
          </fieldset>
        </div>}
      </Modal>
    </div>
  );
}
