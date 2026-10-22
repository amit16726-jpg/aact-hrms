import { useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import {
  Award, CalendarDays, CircleCheck, Cpu, EyeOff, FileText, HandHeart, Lightbulb, Megaphone, Paperclip, PartyPopper, Pin, Scale, ShieldCheck,
  Sparkles, Star,
  Trophy, Users, HeartHandshake, Smile, type LucideIcon,
} from 'lucide-react';
import { useI18n, type Key } from '../i18n';
import { annPdfUrl, eapi, fileSize, type AnnCategory, type Announcement, type RecogCategory, type Recognition } from '../lib/api_eng';
import { ApiError } from '../lib/errors';
import { isNative, saveFile } from '../lib/native';
import type { EmpBrief } from '../lib/api_time';
import { Badge, Button, Field } from './ui';
import { fmtDate } from '../lib/format';
import { initials } from './Layout';

export const ANN_ICONS: Record<AnnCategory, LucideIcon> = {
  GENERAL: Megaphone, HR_POLICY: Scale, EVENT: CalendarDays, SAFETY: ShieldCheck, HOLIDAY: Sparkles, CELEBRATION: PartyPopper, IT: Cpu,
};
export const RECOG_ICONS: Record<RecogCategory, LucideIcon> = {
  TEAMWORK: Users, SAFETY: ShieldCheck, QUALITY: Star, CUSTOMER: Smile, INNOVATION: Lightbulb, EXTRA_MILE: HeartHandshake, LEADERSHIP: Trophy,
};

export function EngStatus({ s }: { s: string }) {
  const { t } = useI18n();
  const tone = s === 'PUBLISHED' || s === 'OPEN' || s === 'APPROVED' ? 'ok' : s === 'PENDING' ? 'warn' : s === 'REJECTED' || s === 'HIDDEN' ? 'bad' : s === 'DRAFT' ? 'info' : undefined;
  return <Badge tone={tone}>{t(`ea.st_${s}` as Key)}</Badge>;
}

export function AnnCategoryChip({ c }: { c: AnnCategory }) {
  const { t } = useI18n();
  const Icon = ANN_ICONS[c];
  return <span className={`eg-chip eg-cat-${c.toLowerCase()}`}><Icon size={13} aria-hidden="true" />{t(`eg.cat_${c}` as Key)}</span>;
}

export function RecogCategoryChip({ c }: { c: RecogCategory }) {
  const { t } = useI18n();
  const Icon = RECOG_ICONS[c];
  return <span className="eg-chip eg-rc"><Icon size={13} aria-hidden="true" />{t(`eg.rc_${c}` as Key)}</span>;
}

/** Who sees it: company and department, or everyone. */
export function audienceText(x: { entity_code: string | null; department_en: string | null; department_ar: string | null },
  t: (k: Key) => string, L: (e: string | null | undefined, a: string | null | undefined) => string): string {
  const parts = [x.entity_code, x.department_en ? L(x.department_en, x.department_ar) : null].filter(Boolean);
  return parts.length ? parts.join(' · ') : t('ea.everyone');
}

export function AnnouncementCard({ a }: { a: Announcement }) {
  const { t, L } = useI18n();
  const body = L(a.body_en, a.body_ar);
  const unread = !a.read_at;
  const needAck = a.require_ack && !a.acknowledged_at;
  return (
    <Link to={`/engage/news/${a.id}`} className={`eg-ann${unread ? ' is-unread' : ''}${a.pinned ? ' is-pinned' : ''}`}>
      <div className="eg-ann-top">
        <AnnCategoryChip c={a.category} />
        {a.pinned && <span className="eg-flag"><Pin size={12} aria-hidden="true" />{t('eg.pinned')}</span>}
        {unread && <span className="eg-flag is-new">{t('eg.new')}</span>}
        {a.attachment_path && <span className="eg-flag" title={t('eg.has_pdf')}><Paperclip size={12} aria-hidden="true" />PDF</span>}
        <span className="eg-ann-date">{t('eg.posted', { d: fmtDate(a.publish_on) })}</span>
      </div>
      <h3>{L(a.title_en, a.title_ar)}</h3>
      <p>{body.length > 220 ? `${body.slice(0, 217)}…` : body}</p>
      {a.require_ack && (
        <div className={`eg-ack-line${needAck ? ' is-due' : ''}`}>
          <CircleCheck size={14} aria-hidden="true" />
          {needAck ? t('eg.needs_ack') : t('eg.acked', { d: fmtDate(a.acknowledged_at?.slice(0, 10)) })}
        </div>
      )}
    </Link>
  );
}

export function Avatar({ name, award }: { name: string; award?: boolean }) {
  return <span className={`eg-avatar${award ? ' is-award' : ''}`} aria-hidden="true">{award ? <Award size={18} /> : initials(name)}</span>;
}

export function RecognitionCard({ r, onChange, onHide }: { r: Recognition; onChange: (r: Recognition) => void; onHide?: (r: Recognition) => void }) {
  const { t, L } = useI18n();
  const [busy, setBusy] = useState(false);
  const who = L(r.employee.full_name_en, r.employee.full_name_ar);
  const from = L(r.giver_name, r.giver_name_ar);
  const applaud = async () => {
    if (r.applauded || busy) return;
    setBusy(true);
    try { onChange(await eapi.applaud(r.id)); } catch { /* the wall reloads on the next visit */ } finally { setBusy(false); }
  };
  return (
    <article className={`eg-recog${r.kind === 'AWARD' ? ' is-award' : ''}`}>
      <Avatar name={who} award={r.kind === 'AWARD'} />
      <div className="eg-recog-main">
        <div className="eg-recog-head">
          <b>{who}</b>
          {r.employee.department_en && <span className="muted small">{L(r.employee.department_en, r.employee.department_ar)}</span>}
        </div>
        {r.kind === 'AWARD'
          ? <div className="eg-award-title"><Trophy size={15} aria-hidden="true" />{r.award_title}</div>
          : <RecogCategoryChip c={r.category} />}
        <p className="eg-recog-msg">{r.message}</p>
        <div className="eg-recog-foot">
          <span className="muted small">{r.kind === 'PEER' ? t('eg.by', { n: from }) : t('eg.award')} · {fmtDate(r.posted_at.slice(0, 10))}</span>
          <span className="eg-recog-actions">
            <button type="button" className={`eg-applaud${r.applauded ? ' is-on' : ''}`} onClick={() => void applaud()} disabled={r.applauded || busy}
              aria-pressed={r.applauded} aria-label={`${r.applauded ? t('eg.applauded') : t('eg.applaud')} (${r.applause})`}>
              <HandHeart size={15} aria-hidden="true" /><span className="num">{r.applause}</span>
            </button>
            {r.can_hide && onHide && (
              <button type="button" className="eg-applaud" onClick={() => onHide(r)} aria-label={t('eg.hide')} title={t('eg.hide')}>
                <EyeOff size={15} aria-hidden="true" />
              </button>)}
          </span>
        </div>
      </div>
    </article>
  );
}

/** Search box for a colleague (same company), for peer recognition. */
export function ColleaguePicker({ value, onChange }: { value: EmpBrief | null; onChange: (e: EmpBrief | null) => void }) {
  const { t, L } = useI18n();
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const [opts, setOpts] = useState<EmpBrief[]>([]);
  const id = useId();
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => {
    if (!open) return;
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(async () => {
      try { setOpts(await eapi.colleagues(q)); } catch { setOpts([]); }
    }, 250);
    return () => window.clearTimeout(timer.current);
  }, [q, open]);
  const label = (e: EmpBrief) => `${L(e.full_name_en, e.full_name_ar)}${e.department_en ? ` — ${L(e.department_en, e.department_ar)}` : ''}`;
  return (
    <Field label={t('eg.colleague')} required htmlFor={id}>
      <div style={{ position: 'relative' }}>
        <input id={id} className="input" role="combobox" aria-expanded={open} aria-autocomplete="list" aria-controls={`${id}-list`}
          value={open ? q : value ? label(value) : ''} placeholder={t('eg.search_colleague')}
          onFocus={() => { setOpen(true); setQ(''); }} onBlur={() => window.setTimeout(() => setOpen(false), 150)}
          onChange={(e) => setQ(e.target.value)} />
        {open && opts.length > 0 && (
          <ul id={`${id}-list`} role="listbox" className="panel eg-pick-list">
            {opts.map((o) => (
              <li key={o.employee_id} role="option" aria-selected={o.employee_id === value?.employee_id}>
                <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => { onChange(o); setOpen(false); }}>
                  <Avatar name={o.full_name_en} />
                  <span><b>{L(o.full_name_en, o.full_name_ar)}</b><span className="muted small">{[o.employee_no, L(o.department_en, o.department_ar)].filter(Boolean).join(' · ')}</span></span>
                </button>
              </li>))}
          </ul>)}
      </div>
    </Field>
  );
}

/** Five tappable faces/numbers for a 1–5 rating. */
export function RatingScale({ name, value, onChange, disabled }: { name: string; value: number | undefined; onChange: (v: number) => void; disabled?: boolean }) {
  const { t } = useI18n();
  return (
    <div className="eg-scale" role="radiogroup">
      {[1, 2, 3, 4, 5].map((n) => (
        <label key={n} className={`eg-scale-opt${value === n ? ' is-on' : ''}`}>
          <input type="radio" name={name} value={n} checked={value === n} disabled={disabled} onChange={() => onChange(n)} />
          <span className="eg-scale-num num">{n}</span>
          <span className="eg-scale-label">{t(`eg.rate_${n}` as Key)}</span>
        </label>))}
    </div>
  );
}

export function Bar({ value, total, label, strong }: { value: number; total: number; label: string; strong?: boolean }) {
  const p = total > 0 ? Math.round((100 * value) / total) : 0;
  return (
    <div className="eg-bar-row">
      <span className="eg-bar-label">{label}</span>
      <span className="eg-bar" aria-hidden="true"><span className={strong ? 'is-strong' : undefined} style={{ width: `${p}%` }} /></span>
      <span className="eg-bar-val num">{value} <span className="muted">({p}%)</span></span>
    </div>
  );
}

/**
 * Opens an announcement PDF. In a browser: a new tab pointed at a short-lived signed link (the tab is opened inside the
 * click, before any waiting, so pop-up blockers allow it). In the phone app: downloads it and opens the share sheet
 * (open in a PDF viewer, save to Files, send …), because app web views cannot show PDFs.
 */
export async function openAnnPdf(path: string, name: string | null): Promise<void> {
  const fname = name && /\.pdf$/i.test(name) ? name : `${name || 'announcement'}.pdf`;
  if (isNative()) {
    const url = await annPdfUrl(path, 300);
    const res = await fetch(url);
    if (!res.ok) throw new ApiError('NOT_FOUND', 'The PDF could not be downloaded.');
    await saveFile(fname, await res.blob());
    return;
  }
  const w = window.open('', '_blank');
  if (w) w.opener = null;
  try {
    const url = await annPdfUrl(path, 300);
    if (w) w.location.href = url; else window.location.assign(url);
  } catch (e) {
    if (w) w.close();
    throw e;
  }
}

/** The attached signed PDF: icon, file name, size and an Open button. */
export function PdfChip({ name, bytes, onOpen, busy, children }:
  { name: string | null; bytes: number | null; onOpen: () => void; busy?: boolean; children?: ReactNode }) {
  const { t } = useI18n();
  return (
    <div className="eg-pdf">
      <span className="eg-pdf-ico" aria-hidden="true"><FileText size={20} /></span>
      <span className="eg-pdf-text">
        <span className="eg-pdf-name" dir="auto">{name || 'announcement.pdf'}</span>
        <span className="eg-pdf-size">PDF{bytes ? ` · ${fileSize(bytes)}` : ''}</span>
      </span>
      <span className="eg-pdf-actions">
        <Button small busy={busy} onClick={onOpen}>{t('ea.pdf_open')}</Button>
        {children}
      </span>
    </div>
  );
}
