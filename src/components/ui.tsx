import {
  createContext, useCallback, useContext, useEffect, useId, useRef, useState,
  type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes,
} from 'react';
import { useI18n, type Key } from '../i18n';
import { bucketOf, fmtDate } from '../lib/format';
import { ArrowDown, ArrowUp, ChevronsUpDown, X } from 'lucide-react';

// ---------------------------------------------------------------------------
// Buttons and fields
// ---------------------------------------------------------------------------
type BtnKind = 'primary' | 'danger' | 'ghost' | 'default';
export function Button({ kind = 'default', small, busy, children, className, disabled, ...rest }:
  ButtonHTMLAttributes<HTMLButtonElement> & { kind?: BtnKind; small?: boolean; busy?: boolean }) {
  const { t } = useI18n();
  const cls = ['btn', kind !== 'default' ? `btn-${kind}` : '', small ? 'btn-sm' : '', className ?? ''].filter(Boolean).join(' ');
  return (
    <button type="button" className={cls} disabled={disabled || busy} aria-busy={busy || undefined} {...rest}>
      {busy ? t('c.saving') : children}
    </button>
  );
}

export function Field({ label, hint, error, required, children, className, htmlFor }:
  { label: ReactNode; hint?: ReactNode; error?: string | null; required?: boolean; children: ReactNode; className?: string; htmlFor?: string }) {
  return (
    <div className={`field ${className ?? ''}`}>
      <label htmlFor={htmlFor}>{label}{required && <span className="req" aria-hidden="true">*</span>}</label>
      {children}
      {error ? <span className="ferr" role="alert">{error}</span> : hint ? <span className="hint">{hint}</span> : null}
    </div>
  );
}

export function Input({ label, hint, error, required, className, ltr, ...rest }:
  InputHTMLAttributes<HTMLInputElement> & { label: ReactNode; hint?: ReactNode; error?: string | null; ltr?: boolean }) {
  const id = useId();
  return (
    <Field label={label} hint={hint} error={error} required={required} className={className} htmlFor={id}>
      <input id={id} className={`input ${ltr ? 'ltr' : ''}`} required={required} aria-invalid={error ? true : undefined} {...rest} />
    </Field>
  );
}

export function Select({ label, hint, error, required, className, children, ...rest }:
  SelectHTMLAttributes<HTMLSelectElement> & { label: ReactNode; hint?: ReactNode; error?: string | null }) {
  const id = useId();
  return (
    <Field label={label} hint={hint} error={error} required={required} className={className} htmlFor={id}>
      <select id={id} className="select" required={required} aria-invalid={error ? true : undefined} {...rest}>{children}</select>
    </Field>
  );
}

export function Textarea({ label, hint, error, required, className, ...rest }:
  TextareaHTMLAttributes<HTMLTextAreaElement> & { label: ReactNode; hint?: ReactNode; error?: string | null }) {
  const id = useId();
  return (
    <Field label={label} hint={hint} error={error} required={required} className={className} htmlFor={id}>
      <textarea id={id} className="textarea" required={required} {...rest} />
    </Field>
  );
}

export function Check({ label, checked, onChange, disabled }:
  { label: ReactNode; checked: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <label className="check">
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
      <span>{label}</span>
    </label>
  );
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------
export function Badge({ tone, children }: { tone?: 'ok' | 'warn' | 'bad' | 'info'; children: ReactNode }) {
  return <span className={`badge ${tone ? `badge-${tone}` : ''}`}>{children}</span>;
}

export function StatusBadge({ status }: { status: string }) {
  const { tk } = useI18n();
  const tone = status === 'ACTIVE' ? 'ok' : status === 'PROBATION' ? 'info' : status === 'NOTICE' || status === 'SUSPENDED' ? 'warn' : undefined;
  return <Badge tone={tone}>{tk(`st.${status}`, status)}</Badge>;
}

export function DaysLeft({ days }: { days: number | null | undefined }) {
  const { t } = useI18n();
  if (days === null || days === undefined) return <span className="muted">—</span>;
  const b = bucketOf(days);
  const text = days < 0 ? t('c.days_ago', { n: Math.abs(days) }) : days === 0 ? t('c.today') : t('c.in_days', { n: days });
  return <span className={`days days-${b}`}>{text}</span>;
}

export function DateText({ v }: { v: string | null | undefined }) {
  return <span className="num nowrap">{fmtDate(v)}</span>;
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="empty">{children}</div>;
}

export function Loading() {
  const { t } = useI18n();
  return <div className="loading" role="status">{t('c.loading')}</div>;
}

export function ErrorNote({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const { errText, t } = useI18n();
  if (!error) return null;
  return (
    <div className="note note-bad row" role="alert">
      <span style={{ flex: 1 }}>{errText(error)}</span>
      {onRetry && <Button small onClick={onRetry}>{t('c.retry')}</Button>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------
export function Tabs<T extends string>({ tabs, value, onChange, label }:
  { tabs: { id: T; label: ReactNode }[]; value: T; onChange: (v: T) => void; label: string }) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const { dir } = useI18n();
  const onKey = (e: React.KeyboardEvent, i: number) => {
    const fwd = dir === 'rtl' ? 'ArrowLeft' : 'ArrowRight';
    const back = dir === 'rtl' ? 'ArrowRight' : 'ArrowLeft';
    let n = -1;
    if (e.key === fwd) n = (i + 1) % tabs.length;
    if (e.key === back) n = (i - 1 + tabs.length) % tabs.length;
    if (e.key === 'Home') n = 0;
    if (e.key === 'End') n = tabs.length - 1;
    if (n >= 0) { e.preventDefault(); onChange(tabs[n].id); refs.current[n]?.focus(); }
  };
  return (
    <div className="tabs" role="tablist" aria-label={label}>
      {tabs.map((tb, i) => (
        <button key={tb.id} ref={(el) => { refs.current[i] = el; }} role="tab" type="button"
          aria-selected={tb.id === value} tabIndex={tb.id === value ? 0 : -1}
          onClick={() => onChange(tb.id)} onKeyDown={(e) => onKey(e, i)}>
          {tb.label}
        </button>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Dialog (native <dialog>: focus trap, Esc and Android back via cancel event)
// ---------------------------------------------------------------------------
export function Modal({ open, title, onClose, children, footer, wide }:
  { open: boolean; title: ReactNode; onClose: () => void; children: ReactNode; footer?: ReactNode; wide?: boolean }) {
  const ref = useRef<HTMLDialogElement>(null);
  const opener = useRef<Element | null>(null);
  const { t } = useI18n();
  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      opener.current = document.activeElement;
      if (typeof d.showModal === 'function') d.showModal(); else d.setAttribute('open', '');
    } else if (!open && d.open) {
      if (typeof d.close === 'function') d.close(); else d.removeAttribute('open');
      (opener.current as HTMLElement | null)?.focus?.();
    }
  }, [open]);
  // The latest onClose, so the back-button handler is set up once per opening. (Re-running it whenever a parent passed a
  // new inline onClose made history.back() fire a popstate that closed the dialog while the person was still typing.)
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    if (!open) return;
    const onPop = () => closeRef.current();
    window.history.pushState({ hrDialog: true }, '');
    window.addEventListener('popstate', onPop);
    return () => {
      window.removeEventListener('popstate', onPop);
      if (window.history.state && (window.history.state as { hrDialog?: boolean }).hrDialog) window.history.back();
    };
  }, [open]);
  return (
    <dialog ref={ref} className={`dlg ${wide ? 'wide' : ''}`} aria-modal="true"
      onCancel={(e) => { e.preventDefault(); onClose(); }}
      onClick={(e) => { if (e.target === ref.current) onClose(); }}>
      {open && (
        <>
          <div className="dlg-head">
            <h2>{title}</h2>
            <button type="button" className="icon-btn" onClick={onClose} aria-label={t('c.close')}><X size={18} aria-hidden="true" /></button>
          </div>
          <div className="dlg-body">{children}</div>
          {footer && <div className="dlg-foot">{footer}</div>}
        </>
      )}
    </dialog>
  );
}

/** Ask for confirmation, optionally with a reason. Resolves to the reason (or '' when not asked) or null when cancelled. */
export function useConfirm() {
  const { t } = useI18n();
  const [state, setState] = useState<{
    title: ReactNode; body?: ReactNode; reason?: 'required' | 'optional'; reasonLabel?: string; danger?: boolean;
    okLabel?: string; resolve: (v: string | null) => void;
  } | null>(null);
  const [reason, setReason] = useState('');
  const ask = useCallback((o: { title: ReactNode; body?: ReactNode; reason?: 'required' | 'optional'; reasonLabel?: string; danger?: boolean; okLabel?: string }) =>
    new Promise<string | null>((resolve) => { setReason(''); setState({ ...o, resolve }); }), []);
  const close = (v: string | null) => { state?.resolve(v); setState(null); };
  const node = (
    <Modal open={!!state} title={state?.title ?? ''} onClose={() => close(null)}
      footer={<>
        <Button onClick={() => close(null)}>{t('c.cancel')}</Button>
        <Button kind={state?.danger ? 'danger' : 'primary'} disabled={state?.reason === 'required' && reason.trim().length < 3}
          onClick={() => close(reason.trim())}>{state?.okLabel ?? t('c.yes_sure')}</Button>
      </>}>
      <div className="stack">
        {state?.body && <div>{state.body}</div>}
        {state?.reason && (
          <Textarea label={state.reasonLabel ?? t('c.reason_required')} required={state.reason === 'required'}
            value={reason} onChange={(e) => setReason(e.target.value)} />
        )}
      </div>
    </Modal>
  );
  return { ask, node };
}

// ---------------------------------------------------------------------------
// Toasts
// ---------------------------------------------------------------------------
interface ToastItem { id: number; text: string; bad?: boolean }
const ToastCtx = createContext<{ push: (text: string, bad?: boolean) => void } | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const seq = useRef(0);
  const { t } = useI18n();
  const push = useCallback((text: string, bad?: boolean) => {
    const id = ++seq.current;
    setItems((s) => [...s.slice(-3), { id, text, bad }]);
    window.setTimeout(() => setItems((s) => s.filter((x) => x.id !== id)), bad ? 9000 : 4500);
  }, []);
  return (
    <ToastCtx.Provider value={{ push }}>
      {children}
      <div className="toasts" aria-live="polite">
        {items.map((x) => (
          <div key={x.id} className={`toast ${x.bad ? 'toast-bad' : ''}`} role={x.bad ? 'alert' : 'status'}>
            <span>{x.text}</span>
            <button type="button" aria-label={t('c.close')} onClick={() => setItems((s) => s.filter((y) => y.id !== x.id))}><X size={15} aria-hidden="true" /></button>
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}

export function useToast() {
  const v = useContext(ToastCtx);
  if (!v) throw new Error('useToast outside ToastProvider');
  return v;
}

// ---------------------------------------------------------------------------
// Data loading
// ---------------------------------------------------------------------------
export function useAsync<T>(fn: () => Promise<T>, deps: unknown[]) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);
  const seq = useRef(0);
  const run = useCallback(async () => {
    const my = ++seq.current;
    setLoading(true); setError(null);
    try {
      const v = await fn();
      if (my === seq.current) setData(v);
    } catch (e) {
      if (my === seq.current) setError(e);
    } finally {
      if (my === seq.current) setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(() => { void run(); }, [run]);
  return { data, error, loading, reload: run, setData };
}

/** Run an action with a busy flag, a toast on success and a translated toast on failure. */
export function useAction() {
  const [busy, setBusy] = useState(false);
  const { push } = useToast();
  const { errText } = useI18n();
  const run = useCallback(async <T,>(fn: () => Promise<T>, okText?: string): Promise<T | undefined> => {
    if (busy) return undefined;
    setBusy(true);
    try {
      const v = await fn();
      if (okText) push(okText);
      return v;
    } catch (e) {
      push(errText(e), true);
      return undefined;
    } finally {
      setBusy(false);
    }
  }, [busy, push, errText]);
  return { busy, run };
}

// ---------------------------------------------------------------------------
// Pager
// ---------------------------------------------------------------------------
export function Pager({ total, limit, offset, onChange }: { total: number; limit: number; offset: number; onChange: (o: number) => void }) {
  const { t } = useI18n();
  const pages = Math.max(1, Math.ceil(total / limit));
  const page = Math.floor(offset / limit) + 1;
  return (
    <div className="row pager">
      <span className="muted">{t('c.rows', { n: total })}</span>
      <span className="spacer" />
      <Button small disabled={page <= 1} onClick={() => onChange(Math.max(0, offset - limit))}>{t('c.previous')}</Button>
      <span className="muted num">{t('c.page_of', { page, pages })}</span>
      <Button small disabled={page >= pages} onClick={() => onChange(offset + limit)}>{t('c.next')}</Button>
    </div>
  );
}

export function SortHead({ id, label, sort, dir, onSort, className }:
  { id: string; label: ReactNode; sort: string; dir: 'asc' | 'desc'; onSort: (id: string) => void; className?: string }) {
  const active = sort === id;
  return (
    <th className={className} aria-sort={active ? (dir === 'asc' ? 'ascending' : 'descending') : 'none'}>
      <button type="button" onClick={() => onSort(id)}>{label}{active ? (dir === 'asc' ? <ArrowUp size={13} aria-hidden="true" /> : <ArrowDown size={13} aria-hidden="true" />) : <ChevronsUpDown size={13} aria-hidden="true" className="sort-idle" />}</button>
    </th>
  );
}

export function useT() { return useI18n().t; }
export type { Key };
