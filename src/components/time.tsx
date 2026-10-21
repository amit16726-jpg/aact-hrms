import { useEffect, useId, useMemo, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { api, checkFile, uploadFile } from '../lib/api';
import { tapi, type AttStatus, type Balance, type LeaveReq, type ReqStatus, type TimeRule } from '../lib/api_time';
import { useI18n, type Key } from '../i18n';
import { useSession } from '../lib/session';
import { addMonths, monthDays, todayMuscat } from '../lib/format';
import { Badge, Button, Check, Field, Input, Modal, Select, Textarea, useAction } from './ui';
import { EmployeePicker } from './pickers';

// ---------------------------------------------------------------------------
// Badges
// ---------------------------------------------------------------------------
export function ReqBadge({ status }: { status: ReqStatus | string }) {
  const { tk } = useI18n();
  const tone = status === 'APPROVED' ? 'ok' : status === 'REJECTED' ? 'bad' : status.startsWith('PENDING') ? 'warn' : undefined;
  return <Badge tone={tone}>{tk(`rst.${status}`, status)}</Badge>;
}

export function AttBadge({ status, late }: { status: AttStatus; late?: number }) {
  const { tk, t } = useI18n();
  const tone = status === 'PRESENT' ? (late ? 'warn' : 'ok') : status === 'ABSENT' || status === 'MISSING_PUNCH' ? 'bad'
    : status === 'LEAVE' ? 'info' : undefined;
  return <Badge tone={tone}>{status === 'PRESENT' && late ? t('ast.LATE') : tk(`ast.${status}`, status)}</Badge>;
}

// ---------------------------------------------------------------------------
// Company and month selectors
// ---------------------------------------------------------------------------
export function useEntity(): [string, (v: string) => void, { id: string; code: string; name_en: string; name_ar: string | null }[]] {
  const { me } = useSession();
  const list = me?.entities ?? [];
  const [id, setId] = useState(list[0]?.id ?? '');
  useEffect(() => { if (!id && list[0]) setId(list[0].id); }, [id, list]);
  return [id, setId, list];
}

export function EntitySelect({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const { me } = useSession();
  const { t, L } = useI18n();
  const id = useId();
  const list = me?.entities ?? [];
  if (list.length <= 1) return null;
  return (
    <div className="field" style={{ minWidth: 200 }}>
      <label htmlFor={id}>{t('c.company')}</label>
      <select id={id} className="select" value={value} onChange={(e) => onChange(e.target.value)}>
        {list.map((x) => <option key={x.id} value={x.id}>{L(x.name_en, x.name_ar)}</option>)}
      </select>
    </div>
  );
}

export function MonthPicker({ value, onChange, label }: { value: string; onChange: (v: string) => void; label?: string }) {
  const { t } = useI18n();
  const id = useId();
  return (
    <div className="field">
      <label htmlFor={id}>{label ?? t('att.month')}</label>
      <div className="row" style={{ gap: 4, flexWrap: 'nowrap' }}>
        <Button small kind="ghost" aria-label={t('att.prev')} onClick={() => onChange(addMonths(value, -1))}>‹</Button>
        <input id={id} type="month" className="input ltr" style={{ width: 150 }} value={value}
          onChange={(e) => e.target.value && onChange(e.target.value)} />
        <Button small kind="ghost" aria-label={t('att.next')} onClick={() => onChange(addMonths(value, 1))}>›</Button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Month grid (employees × days)
// ---------------------------------------------------------------------------
export interface GridLine { key: string; label: ReactNode; sub?: ReactNode; cells: Record<number, { code: string; title?: string }>; tail?: ReactNode }

export function MonthGrid({ month, lines, holidays, legend, tailHead }:
  { month: string; lines: GridLine[]; holidays?: Set<number>; legend: string[]; tailHead?: ReactNode }) {
  const { t, tk } = useI18n();
  const days = useMemo(() => monthDays(month), [month]);
  const today = todayMuscat();
  return (
    <div className="stack" style={{ gap: 8 }}>
      <div className="table-wrap mgrid-wrap">
        <table className="mgrid">
          <thead><tr>
            <th className="mg-name" scope="col">{t('c.employee')}</th>
            {days.map((d) => (
              <th key={d.day} scope="col" className={`${d.dow >= 5 && d.dow <= 6 ? 'we' : ''} ${holidays?.has(d.day) ? 'hol' : ''} ${d.iso === today ? 'now' : ''}`}
                title={`${tk(`wd.${d.dow}`)} ${d.iso}`}>
                <span className="num">{d.day}</span><span className="mg-dow">{tk(`wd.${d.dow}`).slice(0, 2)}</span>
              </th>
            ))}
            {tailHead && <th scope="col" className="mg-tail">{tailHead}</th>}
          </tr></thead>
          <tbody>
            {lines.map((l) => (
              <tr key={l.key}>
                <th scope="row" className="mg-name">{l.label}{l.sub && <span className="sub">{l.sub}</span>}</th>
                {days.map((d) => {
                  const c = l.cells[d.day];
                  return <td key={d.day} className={c ? `g g-${c.code}` : 'g'} title={c?.title ?? (c ? tk(`grid.${c.code}`) : undefined)}>
                    {c ? c.code : ''}</td>;
                })}
                {l.tail !== undefined && <td className="mg-tail num">{l.tail}</td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="row mg-legend" aria-label={t('grid.legend')}>
        {legend.map((c) => <span key={c}><span className={`g g-${c} mg-key`}>{c}</span> {tk(`grid.${c}`)}</span>)}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Choosing the employee a request is for (HR: search; manager: own team; employee: self)
// ---------------------------------------------------------------------------
export function PersonChooser({ value, onChange, label }: { value: string | null; onChange: (id: string | null) => void; label: string }) {
  const { can, me } = useSession();
  const { L, t } = useI18n();
  const id = useId();
  const [team, setTeam] = useState<{ id: string; label: string }[]>([]);
  const hr = can('EMP_READ');
  useEffect(() => {
    if (hr) return;
    api.listEmployees({ limit: 500 }).then((r) => setTeam(r.rows.map((x) => ({ id: x.id, label: `${x.employee_no} — ${L(x.full_name_en, x.full_name_ar)}` }))))
      .catch(() => setTeam([]));
  }, [hr, L]);
  if (hr) return <EmployeePicker label={label} value={value} onChange={(v) => onChange(v)} />;
  if (!me?.is_manager) return null;
  return (
    <Field label={label} htmlFor={id} required>
      <select id={id} className="select" value={value ?? ''} onChange={(e) => onChange(e.target.value || null)} required>
        <option value="">{t('c.select')}</option>
        {team.map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
      </select>
    </Field>
  );
}

// ---------------------------------------------------------------------------
// Correction request
// ---------------------------------------------------------------------------
export function CorrectionDialog({ open, onClose, onDone, employeeId, date }:
  { open: boolean; onClose: () => void; onDone: () => void; employeeId?: string | null; date?: string | null }) {
  const { t } = useI18n();
  const { me } = useSession();
  const { busy, run } = useAction();
  const [emp, setEmp] = useState<string | null>(null);
  const [f, setF] = useState({ work_date: '', in_time: '', out_time: '', out_next_day: false, reason: '' });
  useEffect(() => {
    if (open) { setEmp(employeeId ?? (me?.employee_id ?? null)); setF({ work_date: date ?? '', in_time: '', out_time: '', out_next_day: false, reason: '' }); }
  }, [open, employeeId, date, me?.employee_id]);
  const submit = async () => {
    const r = await run(() => tapi.requestCorrection({ employee_id: emp, ...f, in_time: f.in_time || null, out_time: f.out_time || null }), t('cor.done'));
    if (r) { onDone(); onClose(); }
  };
  return (
    <Modal open={open} title={t('cor.new')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!emp || !f.work_date || (!f.in_time && !f.out_time) || f.reason.trim().length < 3}
          onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <p className="muted" style={{ margin: 0 }}>{t('cor.hint')}</p>
        {!employeeId && <PersonChooser label={t('c.employee')} value={emp} onChange={setEmp} />}
        <div className="form-grid">
          <Input label={t('att.date')} type="date" ltr required value={f.work_date} max={todayMuscat()} onChange={(e) => setF({ ...f, work_date: e.target.value })} />
          <span />
          <Input label={t('cor.in_time')} type="time" ltr value={f.in_time} onChange={(e) => setF({ ...f, in_time: e.target.value })} />
          <Input label={t('cor.out_time')} type="time" ltr value={f.out_time} onChange={(e) => setF({ ...f, out_time: e.target.value })} />
        </div>
        <Check label={t('cor.out_next_day')} checked={f.out_next_day} onChange={(v) => setF({ ...f, out_next_day: v })} />
        <Textarea label={t('c.reason')} required value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} />
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
// Overtime request
// ---------------------------------------------------------------------------
export function useRule(code: TimeRule['code']) {
  const [v, setV] = useState<Record<string, number | string> | null>(null);
  useEffect(() => {
    let alive = true;
    tapi.listTimeRules().then((rs) => {
      const today = todayMuscat();
      const r = rs.find((x) => x.code === code && x.status === 'APPROVED' && x.effective_from <= today && (!x.effective_to || x.effective_to >= today));
      if (alive) setV(r?.value ?? null);
    }).catch(() => undefined);
    return () => { alive = false; };
  }, [code]);
  return v;
}

export function OvertimeDialog({ open, onClose, onDone, employeeId, date }:
  { open: boolean; onClose: () => void; onDone: () => void; employeeId?: string | null; date?: string | null }) {
  const { t } = useI18n();
  const { me } = useSession();
  const { busy, run } = useAction();
  const ot = useRule('OVERTIME');
  const [emp, setEmp] = useState<string | null>(null);
  const [f, setF] = useState({ work_date: '', start_time: '', end_time: '', end_next_day: false, basis: 'CONSENT', employee_consent: false, comp_choice: 'PAY', reason: '' });
  useEffect(() => {
    if (open) {
      setEmp(employeeId ?? me?.employee_id ?? null);
      setF({ work_date: date ?? '', start_time: '', end_time: '', end_next_day: false, basis: 'CONSENT', employee_consent: false, comp_choice: 'PAY', reason: '' });
    }
  }, [open, employeeId, date, me?.employee_id]);
  const self = !!emp && emp === me?.employee_id;
  const pct = (x: unknown) => Math.round(Number(x ?? 0) * 100);
  const submit = async () => {
    const r = await run(() => tapi.requestOvertime({ employee_id: emp, ...f }), t('ot.done'));
    if (r) { onDone(); onClose(); }
  };
  return (
    <Modal open={open} title={t('ot.new')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy}
          disabled={!emp || !f.work_date || !f.start_time || !f.end_time || f.reason.trim().length < 3 || (f.basis === 'CONSENT' && !self && !f.employee_consent)}
          onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {ot && <p className="note" style={{ margin: 0 }}>{t('ot.rules_hint', { day: pct(ot.day_premium), night: pct(ot.night_premium), ns: String(ot.night_start),
          ne: String(ot.night_end), cap: String(ot.max_total_daily_hours), rest: pct(ot.rest_day_premium) })}</p>}
        {!employeeId && <PersonChooser label={t('c.employee')} value={emp} onChange={setEmp} />}
        <div className="form-grid">
          <Input label={t('ot.work_date')} type="date" ltr required value={f.work_date} onChange={(e) => setF({ ...f, work_date: e.target.value })} />
          <Select label={t('ot.comp')} value={f.comp_choice} onChange={(e) => setF({ ...f, comp_choice: e.target.value })}>
            <option value="PAY">{t('ot.comp_PAY')}</option><option value="TIME_OFF">{t('ot.comp_TIME_OFF')}</option>
          </Select>
          <Input label={t('ot.start')} type="time" ltr required value={f.start_time} onChange={(e) => setF({ ...f, start_time: e.target.value })} />
          <Input label={t('ot.end')} type="time" ltr required value={f.end_time} onChange={(e) => setF({ ...f, end_time: e.target.value })} />
        </div>
        <Check label={t('ot.end_next_day')} checked={f.end_next_day} onChange={(v) => setF({ ...f, end_next_day: v })} />
        <Select label={t('ot.basis')} value={f.basis} onChange={(e) => setF({ ...f, basis: e.target.value })}>
          {(['CONSENT', 'INVENTORY', 'EMERGENCY'] as const).map((b) => <option key={b} value={b}>{t(`ot.b_${b}` as Key)}</option>)}
        </Select>
        {f.basis !== 'CONSENT' && <p className="note note-warn" style={{ margin: 0 }}>{t('ot.emergency_hint')}</p>}
        {!self && <Check label={t('ot.consent')} checked={f.employee_consent} onChange={(v) => setF({ ...f, employee_consent: v })} />}
        <Textarea label={t('c.reason')} required value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} />
      </div>
    </Modal>
  );
}

// ---------------------------------------------------------------------------
// Leave request
// ---------------------------------------------------------------------------
export function balanceText(b: Balance, t: (k: Key, v?: Record<string, string | number>) => string): string {
  if (b.quota_period === 'NONE') return t('lv.unlimited');
  if (b.quota_period === 'EVENT') return t('lv.per_event', { n: Number(b.quota_days) });
  if (b.quota_period === 'ONCE') return t('lv.once', { n: Number(b.quota_days) });
  if (b.accrual === 'MONTHLY') return t('lv.accrues', { n: Number(b.quota_days) });
  return t('lv.per_year', { n: Number(b.quota_days) });
}

export function LeaveDialog({ open, onClose, onDone, employeeId }:
  { open: boolean; onClose: () => void; onDone: (r: LeaveReq) => void; employeeId?: string | null }) {
  const { t, L } = useI18n();
  const { me } = useSession();
  const { busy, run } = useAction();
  const [emp, setEmp] = useState<string | null>(null);
  const [bals, setBals] = useState<Balance[]>([]);
  const [f, setF] = useState({ leave_type: '', start_date: '', end_date: '', half_day: false, event_date: '', reason: '', ticket_requested: false });
  useEffect(() => {
    if (open) {
      setEmp(employeeId ?? me?.employee_id ?? null);
      setF({ leave_type: '', start_date: '', end_date: '', half_day: false, event_date: '', reason: '', ticket_requested: false });
    }
  }, [open, employeeId, me?.employee_id]);
  useEffect(() => {
    if (!open || !emp) { setBals([]); return; }
    tapi.leaveBalances(emp).then((b) => setBals(b.balances)).catch(() => setBals([]));
  }, [open, emp]);
  const b = bals.find((x) => x.leave_type === f.leave_type);
  const today = todayMuscat();
  const submit = async () => {
    const r = await run(() => tapi.requestLeave({ employee_id: emp, ...f, end_date: f.half_day ? f.start_date : (f.end_date || f.start_date),
      event_date: f.event_date || null }), t('lv.done'));
    if (r) { onDone(r); onClose(); }
  };
  return (
    <Modal open={open} title={employeeId || emp === me?.employee_id ? t('lv.request') : t('lv.request_for')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!emp || !f.leave_type || !f.start_date || (b?.needs_event_date && !f.event_date)}
          onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {!employeeId && <PersonChooser label={t('c.employee')} value={emp} onChange={setEmp} />}
        <Select label={t('lv.type')} required value={f.leave_type} onChange={(e) => setF({ ...f, leave_type: e.target.value, half_day: false })}>
          <option value="">{t('c.select')}</option>
          {bals.map((x) => <option key={x.leave_type} value={x.leave_type}>
            {L(x.name_en, x.name_ar)}{x.available !== null ? ` — ${t('lv.available')}: ${x.available}` : ''}</option>)}
        </Select>
        {b && (
          <div className="note" style={{ margin: 0 }}>
            <b>{balanceText(b, t)}</b>
            {b.available !== null && <> · {t('lv.available')}: <span className="num">{b.available}</span> · {t('lv.pending')}: <span className="num">{b.pending}</span></>}
            {b.eligible_from > today && <> · {t('lv.not_eligible_yet', { d: b.eligible_from })}</>}
            {b.requires_document && <> · {t('lv.needs_doc')}</>}
          </div>
        )}
        <div className="form-grid">
          <Input label={t('lv.start')} type="date" ltr required value={f.start_date} onChange={(e) => setF({ ...f, start_date: e.target.value, end_date: f.end_date && f.end_date < e.target.value ? e.target.value : f.end_date })} />
          <Input label={t('lv.end')} type="date" ltr value={f.half_day ? f.start_date : f.end_date} min={f.start_date} disabled={f.half_day}
            onChange={(e) => setF({ ...f, end_date: e.target.value })} />
          {b?.needs_event_date && <Input label={t('lv.event_date')} type="date" ltr required hint={t('lv.event_hint')} value={f.event_date}
            onChange={(e) => setF({ ...f, event_date: e.target.value })} />}
        </div>
        {b?.allow_half_day && <Check label={t('lv.half_day')} checked={f.half_day} onChange={(v) => setF({ ...f, half_day: v })} />}
        {b?.ticket_eligible && <Check label={t('lv.ticket')} checked={f.ticket_requested} onChange={(v) => setF({ ...f, ticket_requested: v })} />}
        <Textarea label={t('c.reason')} value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} />
      </div>
    </Modal>
  );
}

export function AttachDialog({ request, onClose, onDone }: { request: LeaveReq | null; onClose: () => void; onDone: (r: LeaveReq) => void }) {
  const { t, errText } = useI18n();
  const { busy, run } = useAction();
  const [kind, setKind] = useState<'MEDICAL_CERT' | 'LEAVE_SUPPORT'>('MEDICAL_CERT');
  const [file, setFile] = useState<File | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => { setFile(null); setErr(null); setKind(request?.leave_type === 'SICK' ? 'MEDICAL_CERT' : 'LEAVE_SUPPORT'); }, [request]);
  const submit = async () => {
    if (!request || !file) return;
    const bad = checkFile(file);
    if (bad) { setErr(t(bad === 'FILE_TYPE' ? 'doc.file_type' : 'doc.file_size')); return; }
    const r = await run(async () => {
      const path = await uploadFile(request.employee_id, kind, file);
      return tapi.attachLeaveDocument(request.id, { doc_type: kind, file_path: path, file_name: file.name, mime_type: file.type, file_size: String(file.size) });
    }, t('lv.attached'));
    if (r) { onDone(r); onClose(); }
  };
  return (
    <Modal open={!!request} title={t('lv.attach_title')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!file} onClick={() => void submit().catch((e) => setErr(errText(e)))}>{t('c.save')}</Button></>}>
      <div className="stack">
        <Select label={t('lv.doc_kind')} value={kind} onChange={(e) => setKind(e.target.value as typeof kind)}>
          <option value="MEDICAL_CERT">{t('lv.doc_MEDICAL_CERT')}</option><option value="LEAVE_SUPPORT">{t('lv.doc_LEAVE_SUPPORT')}</option>
        </Select>
        <Field label={t('doc.file')} error={err}>
          <input type="file" accept="application/pdf,image/jpeg,image/png,image/webp" onChange={(e) => { setFile(e.target.files?.[0] ?? null); setErr(null); }} />
        </Field>
      </div>
    </Modal>
  );
}

/** Link to an employee record for lists. */
export function EmpCell({ r, tab }: { r: { employee_id: string; employee_no: string; full_name_en: string; full_name_ar: string | null }; tab?: string }) {
  const { L } = useI18n();
  return (
    <>
      <Link to={`/employees/${r.employee_id}${tab ? `?tab=${tab}` : ''}`}>{L(r.full_name_en, r.full_name_ar)}</Link>
      <span className="sub num">{r.employee_no}</span>
    </>
  );
}
