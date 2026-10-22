import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase, configMissing } from './supabase';
import { api, type Me } from './api';
import { parseError } from './errors';
import { useI18n } from '../i18n';

interface SessionCtx {
  ready: boolean;
  session: Session | null;
  me: Me | null;
  meError: unknown;
  recovery: boolean;
  can: (perm: string) => boolean;
  hasAnyRole: boolean;
  reload: () => Promise<void>;
  setMe: (m: Me) => void;
  signOut: () => Promise<void>;
  clearRecovery: () => void;
}

const Ctx = createContext<SessionCtx | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const { setLang } = useI18n();
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [me, setMeState] = useState<Me | null>(null);
  const [meError, setMeError] = useState<unknown>(null);
  const [recovery, setRecovery] = useState(false);

  const setMe = useCallback((m: Me) => {
    setMeState(m);
    if (m?.language) setLang(m.language);
  }, [setLang]);

  const loadMe = useCallback(async () => {
    try {
      setMeError(null);
      const m = await api.me();
      // no profile for this sign-in (its account was removed): sign out instead of showing an empty page
      if (!m) { setMeState(null); await supabase.auth.signOut(); return; }
      setMe(m);
    } catch (e) {
      setMeState(null);
      setMeError(e);
      if (parseError(e).code === 'NOT_SIGNED_IN') await supabase.auth.signOut();
    }
  }, [setMe]);

  useEffect(() => {
    if (configMissing) { setReady(true); return; }
    let alive = true;
    supabase.auth.getSession().then(async ({ data }) => {
      if (!alive) return;
      setSession(data.session);
      if (data.session) await loadMe();
      if (alive) setReady(true);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((event, s) => {
      setSession(s);
      if (event === 'PASSWORD_RECOVERY') setRecovery(true);
      if (event === 'SIGNED_IN') void loadMe();
      if (event === 'SIGNED_OUT') { setMeState(null); setMeError(null); }
    });
    return () => { alive = false; sub.subscription.unsubscribe(); };
  }, [loadMe]);

  const value = useMemo<SessionCtx>(() => {
    const perms = new Set(me?.is_active ? me.permissions : []);
    return {
      ready, session, me, meError, recovery,
      can: (p) => perms.has(p),
      hasAnyRole: !!me && me.is_active && (me.roles.length > 0),
      reload: loadMe,
      setMe,
      signOut: async () => { await supabase.auth.signOut(); setMeState(null); },
      clearRecovery: () => setRecovery(false),
    };
  }, [ready, session, me, meError, recovery, loadMe, setMe]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useSession(): SessionCtx {
  const v = useContext(Ctx);
  if (!v) throw new Error('useSession outside SessionProvider');
  return v;
}
