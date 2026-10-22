/** Installing the web app on a phone or computer (Android/Chrome/Edge prompt, iPhone/iPad "Add to Home Screen"). */
export interface InstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

let deferred: InstallPromptEvent | null = null;
const listeners = new Set<() => void>();
const changed = () => listeners.forEach((f) => f());

/** Call once at start-up: keeps the browser's install offer so a menu item can show it later. */
export function initInstall(): void {
  if (typeof window === 'undefined') return;
  window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); deferred = e as InstallPromptEvent; changed(); });
  window.addEventListener('appinstalled', () => { deferred = null; changed(); });
}

/** Registers the service worker in production builds only (never on the dev server). */
export function registerServiceWorker(prod: boolean): void {
  if (!prod || typeof navigator === 'undefined' || !('serviceWorker' in navigator)) return;
  window.addEventListener('load', () => { navigator.serviceWorker.register('/sw.js').catch(() => undefined); });
}

/** iPhone, iPod or iPad (iPadOS reports itself as a Mac with a touch screen). */
export function isIos(ua: string, maxTouchPoints: number): boolean {
  return /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && maxTouchPoints > 1);
}

/** Already running as an installed app. */
export function isStandalone(): boolean {
  if (typeof window === 'undefined') return false;
  return window.matchMedia?.('(display-mode: standalone)').matches === true
    || (window.navigator as Navigator & { standalone?: boolean }).standalone === true;
}

/** 'prompt' = the browser can install it now; 'ios' = show the Share → Add to Home Screen steps; null = nothing to offer. */
export function installMode(): 'prompt' | 'ios' | null {
  if (typeof window === 'undefined' || isStandalone()) return null;
  if (deferred) return 'prompt';
  if (isIos(navigator.userAgent, navigator.maxTouchPoints ?? 0)) return 'ios';
  return null;
}

export async function promptInstall(): Promise<boolean> {
  const e = deferred;
  if (!e) return false;
  await e.prompt();
  const choice = await e.userChoice;
  deferred = null;
  changed();
  return choice.outcome === 'accepted';
}

export function onInstallChange(f: () => void): () => void {
  listeners.add(f);
  return () => { listeners.delete(f); };
}
