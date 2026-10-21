import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ssapi, type ChangeReq, type Letter, type LetterLang, type LetterType } from '../lib/api_ss';
import { useI18n, type Key } from '../i18n';
import { Badge, Button, Check, Input, Modal, Select, useAction, useToast } from './ui';
import { EmployeePicker } from './pickers';
import { fmtDate } from '../lib/format';

const FIELD_KEY: Record<string, Key> = {
  preferred_name: 'ef.preferred_name', mobile: 'ef.mobile', alt_phone: 'ef.alt_phone', personal_email: 'ef.personal_email',
  marital_status: 'ef.marital', address_line: 'ef.address', city: 'ef.city', wilayat: 'ef.wilayat', governorate: 'ef.governorate',
  address_country: 'ef.address_country',
  // correction requests may name any field
  full_name_en: 'ef.full_name_en', full_name_ar: 'ef.full_name_ar', date_of_birth: 'ef.dob', gender: 'ef.gender', nationality: 'emp.nationality',
  civil_number: 'ef.civil', join_date: 'ef.join_date', job: 'me.job', other: 'c.details',
};
export const fieldLabel = (t: (k: Key) => string, f: string) => (FIELD_KEY[f] ? t(FIELD_KEY[f]) : f);

export function ChangeBadge({ c }: { c: Pick<ChangeReq, 'status' | 'overdue'> }) {
  const { t } = useI18n();
  const tone = c.status === 'APPROVED' ? 'ok' : c.status === 'REJECTED' ? 'bad' : c.status === 'PENDING' ? (c.overdue ? 'bad' : 'warn') : undefined;
  return <Badge tone={tone}>{t(`rq.st_${c.status}` as Key)}{c.overdue ? ` · ${t('rq.overdue')}` : ''}</Badge>;
}

export function LetterBadge({ l }: { l: Pick<Letter, 'status' | 'revoked'> }) {
  const { t } = useI18n();
  if (l.revoked) return <Badge tone="bad">{t('lt.revoked')}</Badge>;
  const tone = l.status === 'ISSUED' ? 'ok' : l.status === 'REJECTED' ? 'bad' : l.status === 'PREPARED' ? 'info' : l.status === 'REQUESTED' ? 'warn' : undefined;
  return <Badge tone={tone}>{t(`lt.st_${l.status}` as Key)}</Badge>;
}

/** What a change request asks for, readable by HR and the employee. */
export function ChangeSummary({ c }: { c: ChangeReq }) {
  const { t } = useI18n();
  const ch = c.changes;
  if (c.kind === 'PROFILE') {
    const rows = Object.entries(ch).filter(([, v]) => v && typeof v === 'object' && 'new' in (v as object)) as [string, { old: string | null; new: string | null }][];
    return (
      <table className="t kv-table"><thead><tr><th>{t('rq.what')}</th><th>{t('rq.old')}</th><th>{t('rq.new')}</th></tr></thead>
        <tbody>{rows.map(([k, v]) => <tr key={k}><td>{fieldLabel(t, k)}</td><td className="muted">{v.old ?? '—'}</td><td><b>{v.new ?? '—'}</b></td></tr>)}</tbody></table>
    );
  }
  if (c.kind === 'EMERGENCY') {
    return (
      <ul className="plain">{(ch.contacts ?? []).map((x, i) => (
        <li key={i}><b>{x.name}</b> · {x.relationship} · <span className="num ltr-inline">{x.phone}</span>{x.is_next_of_kin ? ` · ${t('ed.next_of_kin')}` : ''}</li>))}
      </ul>
    );
  }
  if (c.kind === 'BANK') {
    return <div>{ch.bank_name}{ch.branch ? `, ${ch.branch}` : ''} · <span className="num ltr-inline">{ch.iban ?? ch.account_number}</span>{ch.account_name ? <span className="sub">{ch.account_name}</span> : null}</div>;
  }
  return <div>{ch.field ? <b>{fieldLabel(t, String(ch.field))}: </b> : null}{c.reason}</div>;
}

/** Ask for a letter — by the employee for themselves, or by HR for anyone (optionally preparing it at once). */
export function LetterRequestDialog({ open, onClose, onDone, hr, employeeStatus }:
  { open: boolean; onClose: () => void; onDone: (l: Letter) => void; hr?: boolean; employeeStatus?: string }) {
  const { t } = useI18n();
  const { push } = useToast();
  const { busy, run } = useAction();
  const init = () => ({ employee_id: null as string | null, letter_type: 'SALARY_CERT' as LetterType, language: 'BOTH' as LetterLang, addressee: '', purpose: '',
    include_salary: false, destination: '', activity: '', from_date: '', to_date: '', prepare: true });
  const [f, setF] = useState(init);
  useEffect(() => { if (open) setF(init()); }, [open]);
  const types: LetterType[] = hr || employeeStatus === 'NOTICE' || employeeStatus === 'SEPARATED'
    ? ['SALARY_CERT', 'EMPLOYMENT', 'NOC', 'EXPERIENCE'] : ['SALARY_CERT', 'EMPLOYMENT', 'NOC'];
  const nocOk = f.letter_type !== 'NOC' || f.destination.trim() !== '' || f.activity.trim() !== '';
  const datesOk = !f.from_date || !f.to_date || f.to_date >= f.from_date;
  const submit = async () => {
    const details = f.letter_type === 'NOC' ? { destination: f.destination.trim() || undefined, activity: f.activity.trim() || undefined,
      from_date: f.from_date || undefined, to_date: f.to_date || undefined } : {};
    const r = await run(() => ssapi.requestLetter({ employee_id: hr ? f.employee_id : null, letter_type: f.letter_type, language: f.language,
      addressee: f.addressee, purpose: f.purpose, include_salary: f.include_salary, details, prepare: hr ? f.prepare : false }));
    if (r) { push(hr && f.prepare ? t('lt.prepared') : t('lt.sent')); onDone(r); onClose(); }
  };
  return (
    <Modal open={open} title={hr ? t('lt.new_hr') : t('lt.new')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={(hr && !f.employee_id) || !nocOk || !datesOk} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {hr && <EmployeePicker label={t('c.employee')} value={f.employee_id} onChange={(v) => setF({ ...f, employee_id: v })} />}
        <fieldset className="choice-list">
          <legend>{t('lt.type')}</legend>
          {types.map((ty) => (
            <label key={ty} className={`choice${f.letter_type === ty ? ' on' : ''}`}>
              <input type="radio" name="lt-type" checked={f.letter_type === ty} onChange={() => setF({ ...f, letter_type: ty })} />
              <span><b>{t(`lt.${ty}` as Key)}</b><span className="sub">{t(`lt.h_${ty}` as Key)}</span></span>
            </label>))}
        </fieldset>
        <div className="form-grid">
          <Select label={t('lt.language')} value={f.language} onChange={(e) => setF({ ...f, language: e.target.value as LetterLang })}>
            {(['BOTH', 'EN', 'AR'] as const).map((l) => <option key={l} value={l}>{t(`lt.l_${l}` as Key)}</option>)}
          </Select>
          <Input label={t('lt.addressee')} placeholder={t('lt.addressee_ph')} value={f.addressee} maxLength={200} onChange={(e) => setF({ ...f, addressee: e.target.value })} />
          <Input className="span-2" label={t('lt.purpose')} placeholder={t('lt.purpose_ph')} value={f.purpose} maxLength={200} onChange={(e) => setF({ ...f, purpose: e.target.value })} />
          {f.letter_type === 'NOC' && <>
            <Input label={t('lt.destination')} value={f.destination} maxLength={120} onChange={(e) => setF({ ...f, destination: e.target.value })} />
            <Input label={t('lt.activity')} placeholder={t('lt.activity_ph')} value={f.activity} maxLength={200} onChange={(e) => setF({ ...f, activity: e.target.value })} />
            <Input label={t('lt.from')} type="date" ltr value={f.from_date} onChange={(e) => setF({ ...f, from_date: e.target.value })} />
            <Input label={t('lt.to')} type="date" ltr value={f.to_date} min={f.from_date || undefined} onChange={(e) => setF({ ...f, to_date: e.target.value })} />
          </>}
        </div>
        {f.letter_type === 'EMPLOYMENT' && <Check label={hr ? t('lt.include_salary_hr') : t('lt.include_salary')} checked={f.include_salary} onChange={(v) => setF({ ...f, include_salary: v })} />}
        {hr && <Check label={t('lt.prepare_now')} checked={f.prepare} onChange={(v) => setF({ ...f, prepare: v })} />}
      </div>
    </Modal>
  );
}

/** One row of letter facts, used in lists. */
export function LetterLine({ l, showEmployee }: { l: Letter; showEmployee?: boolean }) {
  const { t, L } = useI18n();
  return (
    <div>
      <b>{t(`lt.${l.letter_type}` as Key)}</b>{showEmployee && <> · <Link to={`/employees/${l.employee_id}`}>{L(l.full_name_en, l.full_name_ar)}</Link> <span className="muted num">{l.employee_no}</span></>}
      <span className="sub">{[l.addressee, l.purpose, l.letter_type === 'NOC' ? [l.details?.destination, l.details?.activity].filter(Boolean).join(' / ') : null,
        l.ref_no ? `${t('lt.ref')} ${l.ref_no}` : null, l.issue_date ? t('lt.issued_on', { d: fmtDate(l.issue_date) }) : null].filter(Boolean).join(' · ')}</span>
    </div>
  );
}

export function downloadJson(name: string, data: unknown) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
