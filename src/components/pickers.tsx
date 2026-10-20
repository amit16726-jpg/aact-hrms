import { useEffect, useId, useRef, useState } from 'react';
import { api, type Named } from '../lib/api';
import { useI18n } from '../i18n';
import { Field } from './ui';

/** Masters of one kind for a company, cached for the session. */
const cache = new Map<string, Promise<Named[]>>();
export function clearMasterCache() { cache.clear(); }

export function useMasters<T extends Named = Named>(kind: string, entityId: string | null | undefined) {
  const [rows, setRows] = useState<T[]>([]);
  useEffect(() => {
    let alive = true;
    if (!entityId && kind !== 'entity' && kind !== 'document_type') { setRows([]); return; }
    const key = `${kind}:${entityId ?? ''}`;
    if (!cache.has(key)) cache.set(key, api.listMaster<Named>(kind, entityId ?? null).catch((e) => { cache.delete(key); throw e; }));
    cache.get(key)!.then((r) => { if (alive) setRows(r as T[]); }).catch(() => { if (alive) setRows([]); });
    return () => { alive = false; };
  }, [kind, entityId]);
  return rows;
}

export function MasterSelect({ kind, entityId, label, value, onChange, required, allowEmpty = true, hint, activeOnly = true, exclude }:
  { kind: string; entityId: string | null | undefined; label: string; value: string | null | undefined; onChange: (v: string | null) => void;
    required?: boolean; allowEmpty?: boolean; hint?: string; activeOnly?: boolean; exclude?: string }) {
  const rows = useMasters(kind, entityId);
  const { L, t } = useI18n();
  const id = useId();
  const list = rows.filter((r) => (!activeOnly || r.is_active || r.id === value) && r.id !== exclude);
  return (
    <Field label={label} required={required} hint={hint} htmlFor={id}>
      <select id={id} className="select" value={value ?? ''} required={required} onChange={(e) => onChange(e.target.value || null)}>
        {(allowEmpty || !value) && <option value="">{t('c.select')}</option>}
        {list.map((r) => <option key={r.id} value={r.id}>{r.code} — {L(r.name_en, r.name_ar)}</option>)}
      </select>
    </Field>
  );
}

/** Type-ahead employee search (current employees). */
export function EmployeePicker({ label, value, valueLabel, onChange, hint, exclude }:
  { label: string; value: string | null; valueLabel?: string | null; onChange: (id: string | null, label: string | null) => void; hint?: string; exclude?: string }) {
  const { t, L } = useI18n();
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const [opts, setOpts] = useState<{ id: string; label: string }[]>([]);
  const [shown, setShown] = useState(valueLabel ?? '');
  const id = useId();
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => { setShown(valueLabel ?? ''); }, [valueLabel]);
  useEffect(() => {
    if (!open) return;
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(async () => {
      try {
        const r = await api.employeeLookup(q);
        setOpts(r.filter((x) => x.id !== exclude).map((x) => ({ id: x.id, label: `${x.employee_no} — ${L(x.full_name_en, x.full_name_ar)}` })));
      } catch { setOpts([]); }
    }, 250);
    return () => window.clearTimeout(timer.current);
  }, [q, open, exclude, L]);

  return (
    <Field label={label} hint={hint} htmlFor={id}>
      <div style={{ position: 'relative' }}>
        <input id={id} className="input" role="combobox" aria-expanded={open} aria-autocomplete="list" aria-controls={`${id}-list`}
          value={open ? q : shown} placeholder={value ? '' : t('c.search')}
          onFocus={() => { setOpen(true); setQ(''); }}
          onBlur={() => window.setTimeout(() => setOpen(false), 150)}
          onChange={(e) => setQ(e.target.value)} />
        {value && !open && (
          <button type="button" className="btn btn-ghost btn-sm" style={{ position: 'absolute', insetInlineEnd: 4, top: 4 }}
            onClick={() => { onChange(null, null); setShown(''); }} aria-label={t('c.clear')}>✕</button>
        )}
        {open && opts.length > 0 && (
          <ul id={`${id}-list`} role="listbox" className="panel" style={{ position: 'absolute', zIndex: 30, insetInline: 0, top: 40, margin: 0,
            padding: 4, listStyle: 'none', maxHeight: 240, overflowY: 'auto' }}>
            {opts.map((o) => (
              <li key={o.id} role="option" aria-selected={o.id === value}>
                <button type="button" className="btn btn-ghost" style={{ width: '100%', justifyContent: 'flex-start', color: 'var(--ink)' }}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => { onChange(o.id, o.label); setShown(o.label); setOpen(false); }}>{o.label}</button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </Field>
  );
}

export function CountrySelect({ label, value, onChange, required, nationality }:
  { label: string; value: string | null | undefined; onChange: (v: string | null) => void; required?: boolean; nationality?: boolean }) {
  const { L, t } = useI18n();
  const [rows, setRows] = useState<{ code: string; name_en: string; name_ar: string; nationality_en: string; nationality_ar: string }[]>([]);
  const id = useId();
  useEffect(() => { api.listCountries().then(setRows).catch(() => setRows([])); }, []);
  return (
    <Field label={label} required={required} htmlFor={id}>
      <select id={id} className="select" value={value ?? ''} required={required} onChange={(e) => onChange(e.target.value || null)}>
        <option value="">{t('c.select')}</option>
        {rows.map((c) => <option key={c.code} value={c.code}>
          {nationality ? L(c.nationality_en, c.nationality_ar) : L(c.name_en, c.name_ar)}</option>)}
      </select>
    </Field>
  );
}
