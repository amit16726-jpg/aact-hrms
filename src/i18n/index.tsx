import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { en, type Key } from './en';
import { ar } from './ar';
import type { Lang } from '../lib/api';
import { parseError } from '../lib/errors';

const DICTS: Record<Lang, Record<Key, string>> = { en, ar };
const STORE_KEY = 'aact-hrms-lang';

export function translate(lang: Lang, key: Key, vars?: Record<string, string | number>): string {
  let s = DICTS[lang][key] ?? en[key] ?? key;
  if (vars) for (const [k, v] of Object.entries(vars)) s = s.split(`{${k}}`).join(String(v));
  return s;
}

interface I18n {
  lang: Lang;
  dir: 'ltr' | 'rtl';
  setLang: (l: Lang) => void;
  t: (key: Key, vars?: Record<string, string | number>) => string;
  /** pick the Arabic text in Arabic mode when it exists */
  L: (enText: string | null | undefined, arText: string | null | undefined) => string;
  /** a user-facing message for any error */
  errText: (e: unknown) => string;
  /** translate a dynamic key such as `st.${status}` — falls back to the raw value */
  tk: (key: string, fallback?: string) => string;
}

const Ctx = createContext<I18n | null>(null);

function readStored(): Lang {
  try {
    const v = localStorage.getItem(STORE_KEY);
    return v === 'ar' ? 'ar' : 'en';
  } catch {
    return 'en';
  }
}

export function I18nProvider({ children, initial }: { children: ReactNode; initial?: Lang }) {
  const [lang, setLangState] = useState<Lang>(initial ?? readStored());

  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  }, [lang]);

  const setLang = useCallback((l: Lang) => {
    setLangState(l);
    try { localStorage.setItem(STORE_KEY, l); } catch { /* storage unavailable */ }
  }, []);

  const value = useMemo<I18n>(() => {
    const t = (key: Key, vars?: Record<string, string | number>) => translate(lang, key, vars);
    const tk = (key: string, fallback?: string) =>
      key in en ? translate(lang, key as Key) : (fallback ?? key.split('.').pop() ?? key);
    return {
      lang,
      dir: lang === 'ar' ? 'rtl' : 'ltr',
      setLang,
      t,
      tk,
      L: (e, a) => (lang === 'ar' && a ? a : e ?? a ?? ''),
      errText: (err) => {
        const p = parseError(err);
        const head = `err.${p.code}` in en ? t(`err.${p.code}` as Key) : '';
        if (!head) return p.detail || t('err.UNKNOWN');
        if (!p.detail || p.code === 'NETWORK' || p.code === 'NOT_SIGNED_IN') return head;
        return lang === 'ar' ? `${head} (${p.detail})` : p.detail;
      },
    };
  }, [lang, setLang]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useI18n(): I18n {
  const v = useContext(Ctx);
  if (!v) throw new Error('useI18n outside I18nProvider');
  return v;
}

export type { Key };
