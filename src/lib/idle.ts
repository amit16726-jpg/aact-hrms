import { useEffect, useRef, useState } from 'react';

const KEY = 'aact-hrms-last-active';
const EVENTS = ['pointerdown', 'keydown', 'wheel', 'touchstart', 'scroll'] as const;

function readLast(): number {
  try { return Number(localStorage.getItem(KEY)) || Date.now(); } catch { return Date.now(); }
}
function writeLast(t: number) {
  try { localStorage.setItem(KEY, String(t)); } catch { /* storage unavailable: this tab still counts */ }
}

/** Seconds left before an automatic sign-out after `minutes` without activity (shared across tabs). */
export function secondsLeft(last: number, now: number, minutes: number): number {
  return Math.max(0, Math.round((last + minutes * 60_000 - now) / 1000));
}

/**
 * Signs out after `minutes` without keyboard, mouse or touch activity in any tab of the app.
 * Returns the seconds left when the final minute starts (to show a warning), otherwise null, and a function to stay signed in.
 */
export function useIdleSignOut(minutes: number, onExpire: () => void): { warnIn: number | null; stay: () => void } {
  const [warnIn, setWarnIn] = useState<number | null>(null);
  const last = useRef(Date.now());
  const expired = useRef(false);
  useEffect(() => {
    if (!minutes || minutes <= 0) return;
    last.current = Date.now(); writeLast(last.current);
    let throttle = 0;
    const touch = () => {
      const now = Date.now();
      if (now - throttle < 5000) return;
      throttle = now; last.current = now; writeLast(now);
    };
    EVENTS.forEach((e) => window.addEventListener(e, touch, { passive: true }));
    const timer = window.setInterval(() => {
      const shared = Math.max(last.current, readLast());
      const left = secondsLeft(shared, Date.now(), minutes);
      if (left <= 0 && !expired.current) { expired.current = true; setWarnIn(null); onExpire(); return; }
      setWarnIn(left <= 60 ? left : null);
    }, 1000);
    return () => { EVENTS.forEach((e) => window.removeEventListener(e, touch)); window.clearInterval(timer); };
  }, [minutes, onExpire]);
  const stay = () => { last.current = Date.now(); writeLast(last.current); setWarnIn(null); };
  return { warnIn, stay };
}
