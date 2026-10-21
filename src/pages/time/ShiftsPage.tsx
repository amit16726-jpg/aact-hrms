import { useEffect, useState } from 'react';
import { tapi, type Shift } from '../../lib/api_time';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, DateText, Empty, ErrorNote, Input, Loading, Modal, Textarea, useAction, useAsync, useToast } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { EmpCell, EntitySelect, useEntity, useRule } from '../../components/time';
import { fmtDuration, todayMuscat } from '../../lib/format';

const DAYS = [1, 2, 3, 4, 5, 6, 7];

export default function ShiftsPage() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const [entity, setEntity] = useEntity();
  const { data, error, loading, reload } = useAsync(() => (entity ? tapi.listShifts(entity) : Promise.resolve([] as Shift[])), [entity]);
  const [edit, setEdit] = useState<Partial<Shift> | null>(null);
  const [assign, setAssign] = useState<Shift | null>(null);
  const [view, setView] = useState<Shift | null>(null);
  const wh = useRule('WORK_HOURS');
  const rh = useRule('RAMADAN_HOURS');
  const wr = useRule('WEEKLY_REST');
  const write = can('ATT_WRITE');
  return (
    <div className="stack">
      <PageHead title={t('sh.title')} actions={write && <Button kind="primary" onClick={() => setEdit({ entity_id: entity, code: '', name_en: '', name_ar: '',
        start_time: '07:00', end_time: '16:00', break_minutes: 60, grace_minutes: null, rest_days: [5, 6], is_ramadan: false, is_active: true, notes: '' })}>{t('sh.new')}</Button>} />
      {wh && (
        <div className="note">{t('sh.law_hint', { daily: wh.daily_max_hours, weekly: wh.weekly_max_hours, rd: rh?.daily_max_hours ?? '—', rw: rh?.weekly_max_hours ?? '—',
          rest: wr?.min_consecutive_days ?? '—', brk: wh.break_minutes, cont: wh.max_continuous_hours })}<br /><span className="muted">{t('sh.temp_hint')}</span></div>
      )}
      <div className="panel panel-pad row"><EntitySelect value={entity} onChange={setEntity} /></div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('sh.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.code')}</th><th>{t('sh.start')}–{t('sh.end')}</th><th className="r">{t('sh.break')}</th><th className="r">{t('sh.net')}</th>
              <th className="r">{t('sh.weekly')}</th><th>{t('sh.rest_days')}</th><th className="r">{t('sh.assigned')}</th><th /></tr></thead>
            <tbody>{data.map((s) => (
              <tr key={s.id} style={{ opacity: s.is_active ? 1 : 0.55 }}>
                <td data-label={t('c.code')}><b className="num">{s.code}</b><span className="sub">{L(s.name_en, s.name_ar)}</span>
                  {s.is_ramadan && <span className="sub"><Badge tone="info">{t('cal.ramadan')}</Badge></span>}
                  {!s.is_active && <span className="sub"><Badge>{t('c.inactive')}</Badge></span>}</td>
                <td data-label={`${t('sh.start')}–${t('sh.end')}`} className="num">{s.start_time}–{s.end_time}{s.crosses_midnight && <span className="sub">{t('sh.crosses')}</span>}</td>
                <td data-label={t('sh.break')} className="r num">{s.break_minutes}</td>
                <td data-label={t('sh.net')} className="r num">{fmtDuration(s.net_minutes)}</td>
                <td data-label={t('sh.weekly')} className="r num">{fmtDuration(s.weekly_minutes)}</td>
                <td data-label={t('sh.rest_days')}>{s.rest_days.map((d) => t(`wd.${d}` as Key)).join(', ')}</td>
                <td data-label={t('sh.assigned')} className="r num"><button type="button" className="linklike" onClick={() => setView(s)}>{s.assigned}</button></td>
                <td className="r"><div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  {write && <Button small onClick={() => setEdit(s)}>{t('c.edit')}</Button>}
                  {write && s.is_active && <Button small kind="primary" onClick={() => setAssign(s)}>{t('sh.assign')}</Button>}
                </div></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
      <ShiftDialog row={edit} onClose={() => setEdit(null)} onDone={() => void reload()} />
      <AssignDialog shift={assign} onClose={() => setAssign(null)} onDone={() => void reload()} />
      <OnShiftDialog shift={view} onClose={() => setView(null)} />
    </div>
  );
}

function ShiftDialog({ row, onClose, onDone }: { row: Partial<Shift> | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState<Partial<Shift>>({});
  useEffect(() => { if (row) setF(row); }, [row]);
  const toggle = (d: number, on: boolean) => {
    const set = new Set(f.rest_days ?? []);
    if (on) set.add(d); else set.delete(d);
    setF({ ...f, rest_days: [...set].sort() });
  };
  const submit = async () => {
    const p = { ...f, grace_minutes: f.grace_minutes === null || f.grace_minutes === undefined || String(f.grace_minutes) === '' ? null : Number(f.grace_minutes),
      break_minutes: Number(f.break_minutes ?? 0) };
    if (await run(() => tapi.saveShift(p as Record<string, unknown>), t('c.saved'))) { onDone(); onClose(); }
  };
  return (
    <Modal open={!!row} title={row?.id ? t('sh.edit') : t('sh.new')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy}
        disabled={!f.code || !f.name_en || !f.start_time || !f.end_time} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="form-grid">
        <Input label={t('c.code')} ltr required value={f.code ?? ''} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} />
        <span />
        <Input label={t('c.name_en')} required value={f.name_en ?? ''} onChange={(e) => setF({ ...f, name_en: e.target.value })} />
        <Input label={t('c.name_ar')} value={f.name_ar ?? ''} onChange={(e) => setF({ ...f, name_ar: e.target.value })} />
        <Input label={t('sh.start')} type="time" ltr required value={f.start_time ?? ''} onChange={(e) => setF({ ...f, start_time: e.target.value })} />
        <Input label={t('sh.end')} type="time" ltr required value={f.end_time ?? ''} onChange={(e) => setF({ ...f, end_time: e.target.value })} />
        <Input label={t('sh.break')} ltr inputMode="numeric" value={f.break_minutes ?? 0} onChange={(e) => setF({ ...f, break_minutes: Number(e.target.value) || 0 })} />
        <Input label={t('sh.grace')} ltr inputMode="numeric" hint={t('sh.grace_hint')} value={f.grace_minutes ?? ''}
          onChange={(e) => setF({ ...f, grace_minutes: e.target.value === '' ? null : Number(e.target.value) || 0 })} />
        <fieldset className="span-2" style={{ border: 0, padding: 0, margin: 0 }}>
          <legend style={{ fontWeight: 600, marginBottom: 6 }}>{t('sh.rest_days')}</legend>
          <div className="row" style={{ gap: 14 }}>{DAYS.map((d) => <Check key={d} label={t(`wd.${d}` as Key)} checked={(f.rest_days ?? []).includes(d)} onChange={(v) => toggle(d, v)} />)}</div>
        </fieldset>
        <div className="span-2 row" style={{ gap: 18 }}>
          <Check label={t('sh.ramadan')} checked={!!f.is_ramadan} onChange={(v) => setF({ ...f, is_ramadan: v })} />
          <Check label={t('c.active')} checked={f.is_active !== false} onChange={(v) => setF({ ...f, is_active: v })} />
        </div>
        <Textarea label={t('c.notes')} className="span-2" value={f.notes ?? ''} onChange={(e) => setF({ ...f, notes: e.target.value })} />
      </div>
    </Modal>
  );
}

function AssignDialog({ shift, onClose, onDone }: { shift: Shift | null; onClose: () => void; onDone: () => void }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const [ids, setIds] = useState<{ id: string; label: string }[]>([]);
  const [pick, setPick] = useState<string | null>(null);
  const [from, setFrom] = useState(todayMuscat());
  const [to, setTo] = useState('');
  const [notes, setNotes] = useState('');
  useEffect(() => { if (shift) { setIds([]); setPick(null); setFrom(todayMuscat()); setTo(''); setNotes(''); } }, [shift]);
  const submit = async () => {
    const r = await run(() => tapi.assignShift({ shift_id: shift!.id, employee_ids: ids.map((x) => x.id), effective_from: from, effective_to: to || null, notes: notes || null }));
    if (r) { push(t('sh.assigned_done', { n: r.assigned })); onDone(); onClose(); }
  };
  return (
    <Modal open={!!shift} title={t('sh.assign_title', { code: shift?.code ?? '' })} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!ids.length || !from} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="form-grid">
          <Input label={t('sh.from')} type="date" ltr required value={from} onChange={(e) => setFrom(e.target.value)} />
          <Input label={t('sh.to')} type="date" ltr value={to} onChange={(e) => setTo(e.target.value)} />
        </div>
        {shift?.is_ramadan && <div className="note">{t('sh.temp_hint')}</div>}
        <div className="row" style={{ alignItems: 'flex-end' }}>
          <div style={{ flex: 1, minWidth: 240 }}><EmployeePicker key={ids.length} label={t('sh.add_employee')} value={pick}
            onChange={(v, lbl) => { if (v && !ids.some((x) => x.id === v)) setIds([...ids, { id: v, label: lbl ?? v }]); setPick(null); }} /></div>
        </div>
        {ids.length > 0 && (
          <div><b>{t('sh.employees')} ({ids.length})</b>
            <ul className="chips">{ids.map((x) => <li key={x.id}>{x.label} <button type="button" className="linklike" aria-label={t('c.remove')}
              onClick={() => setIds(ids.filter((y) => y.id !== x.id))}>×</button></li>)}</ul></div>
        )}
        <Textarea label={t('c.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
      </div>
    </Modal>
  );
}

function OnShiftDialog({ shift, onClose }: { shift: Shift | null; onClose: () => void }) {
  const { t } = useI18n();
  const { data, error, loading } = useAsync(() => (shift ? tapi.listShiftAssignments({ shift_id: shift.id, on: todayMuscat() }) : Promise.resolve([])), [shift?.id]);
  return (
    <Modal open={!!shift} title={`${t('sh.on_shift')} — ${shift?.code ?? ''}`} onClose={onClose} footer={<Button onClick={onClose}>{t('c.close')}</Button>}>
      <ErrorNote error={error} />
      {loading ? <Loading /> : !data?.length ? <Empty>{t('c.none')}</Empty> : (
        <div className="table-wrap"><table className="t">
          <thead><tr><th>{t('c.employee')}</th><th>{t('sh.from')}</th><th>{t('c.to')}</th></tr></thead>
          <tbody>{data.map((a) => <tr key={a.id}><td><EmpCell r={a} tab="time" /></td><td><DateText v={a.effective_from} /></td><td><DateText v={a.effective_to} /></td></tr>)}</tbody>
        </table></div>
      )}
    </Modal>
  );
}
