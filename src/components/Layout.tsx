import { Suspense, useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom';
import {
  Award, Banknote, Briefcase, Building2, CalendarClock, CalendarCog, CalendarDays, CalendarRange, ChartColumn,
  ChevronDown, CircleCheckBig, ClipboardList, Clock, DoorOpen, FileSpreadsheet, FileUp, FileWarning, Fingerprint,
  Flag, GraduationCap, HandCoins, HardHat, History, Hourglass, IdCard, Inbox, Landmark, LayoutDashboard, ListPlus, LogOut,
  Menu, Network, Package, PiggyBank, Receipt, Scale, Search, Settings, Settings2, ShieldAlert, ShieldCheck, Target, Timer,
  Upload, UserCog, UserRound, Users, UsersRound, X, Bell, Smartphone, Share, SquarePlus, type LucideIcon,
} from 'lucide-react';
import { useI18n, type Key } from '../i18n';
import { useSession } from '../lib/session';
import { api } from '../lib/api';
import { tapi } from '../lib/api_time';
import { Loading, Modal, Button } from './ui';
import { installMode, onInstallChange, promptInstall } from '../lib/install';

interface Item { to: string; key: Key; show: boolean; icon: LucideIcon; count?: number }
interface Group { id: string; title?: Key; items: Item[] }

const GROUPS_KEY = 'aact-hrms-nav-closed';

function readClosed(): string[] {
  try { const v = JSON.parse(window.localStorage.getItem(GROUPS_KEY) ?? '[]'); return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []; }
  catch { return []; }
}
function writeClosed(v: string[]) {
  try { window.localStorage.setItem(GROUPS_KEY, JSON.stringify(v)); } catch { /* private window: keep in memory only */ }
}

export function initials(name: string | null | undefined): string {
  const parts = String(name ?? '').replace(/@.*/, '').split(/[\s._-]+/).filter(Boolean);
  if (!parts.length) return '?';
  return ((parts[0][0] ?? '') + (parts.length > 1 ? parts[parts.length - 1][0] ?? '' : '')).toUpperCase();
}

export function LangSwitch({ dark }: { dark?: boolean }) {
  const { lang, setLang, t } = useI18n();
  const { me, setMe } = useSession();
  const change = async (l: 'en' | 'ar') => {
    setLang(l);
    if (me) { try { setMe(await api.setMyProfile({ language: l })); } catch { /* keep local choice */ } }
  };
  return (
    <div className={`lang-switch${dark ? ' lang-dark' : ''}`} role="group" aria-label={t('c.language')}>
      <button type="button" aria-pressed={lang === 'en'} onClick={() => change('en')} lang="en">EN</button>
      <button type="button" aria-pressed={lang === 'ar'} onClick={() => change('ar')} lang="ar">عربي</button>
    </div>
  );
}

export function BrandMark({ size = 36 }: { size?: number }) {
  return (
    <svg className="brand-mark" width={size} height={size} viewBox="0 0 40 40" aria-hidden="true">
      <rect width="40" height="40" rx="10" fill="var(--petrol)" />
      <path d="M11 29 19.2 10.5h1.6L29 29h-4.1l-1.8-4.3h-6.3L15 29Zm7.2-7.7h3.5L20 17.1Z" fill="#fff" />
      <rect x="11" y="31.2" width="18" height="2.2" rx="1.1" fill="var(--brass)" />
    </svg>
  );
}

export function Brand({ dark }: { dark?: boolean }) {
  const { t } = useI18n();
  return (
    <div className={`brand${dark ? ' brand-dark' : ''}`}>
      <BrandMark />
      <div className="brand-text">
        <div className="brand-name">{t('app.name')}</div>
        <div className="brand-sub">{t('app.tagline')}</div>
        <EnvBadge />
      </div>
    </div>
  );
}

/** Shows which environment this is (LOCAL / TEST). Production leaves VITE_ENV_LABEL unset → nothing shown. */
export function EnvBadge() {
  const { t } = useI18n();
  const env = String(import.meta.env.VITE_ENV_LABEL ?? '').trim().toUpperCase();
  if (!env || env === 'PRODUCTION') return null;
  return <div className={`env-badge env-${env === 'LOCAL' ? 'local' : 'test'}`}>{env === 'LOCAL' ? t('env.local') : `${env} – ${t('env.test')}`}</div>;
}

function isActive(path: string, to: string): boolean {
  if (to === '/') return path === '/';
  if (to === '/payroll' || to === '/leave') return path === to || (to === '/payroll' && /^\/payroll\/(?!items|loans|settlements|gratuity|rules|setup)[^/]+$/.test(path));
  return path === to || path.startsWith(to + '/');
}

function AccountMenu() {
  const { t } = useI18n();
  const { me, signOut } = useSession();
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => { if (box.current && !box.current.contains(e.target as Node)) setOpen(false); };
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', onDoc);
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('mousedown', onDoc); document.removeEventListener('keydown', onKey); };
  }, [open]);
  const name = me?.display_name || me?.email || '';
  const [mode, setMode] = useState(installMode);
  const [iosHelp, setIosHelp] = useState(false);
  useEffect(() => onInstallChange(() => setMode(installMode())), []);
  const install = async () => {
    setOpen(false);
    if (mode === 'ios') setIosHelp(true); else await promptInstall();
  };
  return (
    <div className="acct" ref={box}>
      <button type="button" className="acct-btn" aria-haspopup="menu" aria-expanded={open} aria-label={t('shell.account')}
        onClick={() => setOpen((v) => !v)}>
        <span className="avatar avatar-sm" aria-hidden="true">{initials(name)}</span>
        <span className="acct-name">{name}</span>
        <ChevronDown size={16} aria-hidden="true" />
      </button>
      {open && (
        <div className="acct-menu" role="menu">
          <div className="acct-head">
            <span className="avatar" aria-hidden="true">{initials(name)}</span>
            <div className="acct-id">
              <b>{name}</b>
              <span className="ltr-inline">{me?.email}</span>
            </div>
          </div>
          {me?.employee_id && (
            <NavLink role="menuitem" to="/me" onClick={() => setOpen(false)}><UserRound size={16} aria-hidden="true" />{t('snav.my_hr')}</NavLink>
          )}
          <NavLink role="menuitem" to="/settings" onClick={() => setOpen(false)}><Settings size={16} aria-hidden="true" />{t('nav.settings')}</NavLink>
          {mode && (
            <button type="button" role="menuitem" onClick={() => void install()}><Smartphone size={16} aria-hidden="true" />{t('shell.install')}</button>
          )}
          <button type="button" role="menuitem" className="acct-out" onClick={() => void signOut()}>
            <LogOut size={16} aria-hidden="true" />{t('c.signout')}
          </button>
        </div>
      )}
      <Modal open={iosHelp} title={t('shell.install_title')} onClose={() => setIosHelp(false)}
        footer={<Button kind="primary" onClick={() => setIosHelp(false)}>{t('c.close')}</Button>}>
        <ol className="install-steps">
          <li><Share size={18} aria-hidden="true" />{t('shell.install_ios_1')}</li>
          <li><SquarePlus size={18} aria-hidden="true" />{t('shell.install_ios_2')}</li>
          <li><Smartphone size={18} aria-hidden="true" />{t('shell.install_ios_3')}</li>
        </ol>
      </Modal>
    </div>
  );
}

function TopSearch() {
  const { t } = useI18n();
  const nav = useNavigate();
  const [q, setQ] = useState('');
  const submit = (e: FormEvent) => {
    e.preventDefault();
    const v = q.trim();
    nav(v ? `/employees?search=${encodeURIComponent(v)}` : '/employees');
    setQ('');
  };
  return (
    <form className="top-search" role="search" onSubmit={submit}>
      <Search size={16} aria-hidden="true" />
      <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder={t('shell.search_ph')} aria-label={t('shell.search')} />
    </form>
  );
}

export default function Layout() {
  const { t } = useI18n();
  const { me, can, signOut } = useSession();
  const loc = useLocation();
  const [navOpen, setNavOpen] = useState(false);
  const [unread, setUnread] = useState(me?.unread_notifications ?? 0);
  const [approvals, setApprovals] = useState(0);
  const [closed, setClosed] = useState<string[]>(readClosed);

  useEffect(() => { setNavOpen(false); }, [loc.pathname]);
  useEffect(() => {
    let alive = true;
    const load = () => {
      api.listNotifications(true).then((r) => alive && setUnread(r.unread)).catch(() => undefined);
      const hr = can('SALARY_APPROVE') || can('BANK_APPROVE') || can('RULES_APPROVE');
      Promise.all([
        hr ? api.dashboard().then((d) => d.approvals.salary + d.approvals.bank + d.approvals.targets).catch(() => 0) : Promise.resolve(0),
        tapi.myTasks().then((x) => x.count).catch(() => 0),
      ]).then(([a, b]) => { if (alive) setApprovals(a + b); }).catch(() => undefined);
    };
    load();
    const id = window.setInterval(load, 120000);
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);
    return () => { alive = false; window.clearInterval(id); window.removeEventListener('focus', onFocus); };
  }, [can, loc.pathname]);

  const groups: Group[] = [
    { id: 'main', items: [
      { to: '/', key: 'nav.dashboard', icon: LayoutDashboard, show: true },
      { to: '/me', key: 'snav.my_hr', icon: UserRound, show: !!me?.employee_id },
      { to: '/my', key: 'nav.my_record', icon: IdCard, show: !!me?.employee_id },
      { to: '/team', key: 'snav.team', icon: UsersRound, show: !!me?.is_manager },
      { to: '/employees', key: 'nav.employees', icon: Users, show: can('EMP_READ') || !!me?.is_manager },
      { to: '/approvals', key: 'nav.approvals', icon: CircleCheckBig, show: can('SALARY_APPROVE') || can('BANK_APPROVE') || can('RULES_APPROVE') || can('LEAVE_APPROVE') || can('ATT_APPROVE') || can('PAY_VERIFY') || can('PAY_APPROVE') || can('REC_APPROVE') || can('DISC_APPROVE') || can('PERF_MANAGE') || !!me?.is_manager || approvals > 0, count: approvals },
      { to: '/requests', key: 'snav.requests', icon: Inbox, show: can('SS_APPROVE') || can('LETTER_PREPARE') || can('LETTER_APPROVE') },
    ] },
    { id: 'time', title: 'tnav.group', items: [
      { to: '/attendance', key: 'tnav.attendance', icon: Fingerprint, show: can('ATT_READ') || !!me?.is_manager || !!me?.employee_id },
      { to: '/overtime', key: 'tnav.overtime', icon: Timer, show: can('ATT_READ') || !!me?.is_manager || !!me?.employee_id },
      { to: '/leave', key: 'tnav.leave', icon: CalendarDays, show: can('LEAVE_READ') || !!me?.is_manager || !!me?.employee_id },
      { to: '/leave/admin', key: 'tnav.leave_admin', icon: CalendarCog, show: can('LEAVE_READ') },
      { to: '/time/shifts', key: 'tnav.shifts', icon: Clock, show: can('ATT_READ') },
      { to: '/time/calendar', key: 'tnav.calendar', icon: CalendarRange, show: can('ATT_READ') },
      { to: '/time/import', key: 'tnav.import', icon: FileUp, show: can('ATT_WRITE') },
      { to: '/time/periods', key: 'tnav.periods', icon: CalendarClock, show: can('ATT_READ') },
      { to: '/time/rules', key: 'tnav.rules', icon: Scale, show: can('ATT_READ') || can('RULES_PROPOSE') },
    ] },
    { id: 'pay', title: 'pnav.group', items: [
      { to: '/payslips', key: 'pnav.my_payslips', icon: Receipt, show: !!me?.employee_id },
      { to: '/payroll', key: 'pnav.runs', icon: Banknote, show: can('PAY_READ') },
      { to: '/payroll/items', key: 'pnav.adjustments', icon: ListPlus, show: can('PAY_READ') },
      { to: '/payroll/loans', key: 'pnav.loans', icon: HandCoins, show: can('PAY_READ') },
      { to: '/payroll/settlements', key: 'pnav.settlements', icon: DoorOpen, show: can('PAY_READ') },
      { to: '/payroll/gratuity', key: 'pnav.gratuity', icon: PiggyBank, show: can('PAY_READ') },
      { to: '/payroll/rules', key: 'pnav.rules', icon: Scale, show: can('PAY_READ') || can('RULES_PROPOSE') },
      { to: '/payroll/setup', key: 'pnav.setup', icon: Settings2, show: can('PAY_READ') },
    ] },
    { id: 'rec', title: 'rnav.group', items: [
      { to: '/recruitment', key: 'rnav.recruitment', icon: Briefcase, show: can('REC_READ') || can('REC_WRITE') || !!me?.is_manager },
      { to: '/probation', key: 'rnav.probation', icon: Hourglass, show: can('REC_READ') || can('EMP_READ') || !!me?.is_manager },
    ] },
    { id: 'ops', title: 'wnav.group', items: [
      { to: '/performance', key: 'wnav.performance', icon: Award, show: can('PERF_MANAGE') || !!me?.is_manager || !!me?.employee_id },
      { to: '/training', key: 'wnav.training', icon: GraduationCap, show: can('TRAIN_WRITE') || !!me?.employee_id },
      { to: '/discipline', key: 'wnav.discipline', icon: ShieldAlert, show: can('DISC_READ') || !!me?.employee_id },
      { to: '/assets', key: 'wnav.assets', icon: Package, show: can('ASSET_WRITE') || can('EMP_READ') || !!me?.employee_id },
      { to: '/facilities', key: 'wnav.facilities', icon: Building2, show: can('ASSET_WRITE') || can('EMP_READ') },
      { to: '/injuries', key: 'wnav.injuries', icon: HardHat, show: can('HSE_WRITE') || can('EMP_READ') },
      { to: '/exits', key: 'wnav.exits', icon: LogOut, show: can('EXIT_MANAGE') },
    ] },
    { id: 'gov', title: 'gnav.group', items: [
      { to: '/executive', key: 'gnav.exec', icon: ChartColumn, show: can('EXEC_VIEW') },
      { to: '/reports/mol', key: 'gnav.mol', icon: Landmark, show: can('COMPLIANCE_READ') },
      { to: '/reports/spf', key: 'gnav.spf', icon: FileSpreadsheet, show: can('PAY_READ') },
      { to: '/privacy', key: 'gnav.privacy', icon: ShieldCheck, show: can('PDPL_READ') },
      { to: '/admin/import', key: 'gnav.import', icon: Upload, show: can('DATA_IMPORT') },
    ] },
    { id: 'comp', title: 'nav.compliance', items: [
      { to: '/compliance/expiries', key: 'nav.expiries', icon: FileWarning, show: can('COMPLIANCE_READ') || !!me?.is_manager },
      { to: '/compliance/missing', key: 'nav.missing', icon: ClipboardList, show: can('COMPLIANCE_READ') },
      { to: '/compliance/omanisation', key: 'nav.omanisation', icon: Flag, show: can('COMPLIANCE_READ') },
      { to: '/compliance/targets', key: 'nav.targets', icon: Target, show: can('COMPLIANCE_READ') },
    ] },
    { id: 'admin', title: 'nav.admin', items: [
      { to: '/organisation', key: 'nav.organisation', icon: Network, show: can('ORG_WRITE') || can('EMP_READ') },
      { to: '/admin/users', key: 'nav.users', icon: UserCog, show: can('USERS_ADMIN') },
      { to: '/admin/audit', key: 'nav.audit', icon: History, show: can('AUDIT_READ') },
      { to: '/settings', key: 'nav.settings', icon: Settings, show: true },
    ] },
  ];

  const visible = groups.map((g) => ({ ...g, items: g.items.filter((i) => i.show) })).filter((g) => g.items.length);

  // the item (and its group) for the current address: used for the page path in the header
  const current = useMemo(() => {
    let best: { g: Group; i: Item } | null = null;
    for (const g of visible) for (const i of g.items) {
      if (isActive(loc.pathname, i.to) && (!best || i.to.length > best.i.to.length)) best = { g, i };
    }
    return best;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loc.pathname, JSON.stringify(visible.map((g) => g.items.map((i) => i.to)))]);

  const toggle = (id: string) => {
    setClosed((c) => { const n = c.includes(id) ? c.filter((x) => x !== id) : [...c, id]; writeClosed(n); return n; });
  };

  const CurIcon = current?.i.icon;

  return (
    <div className={`shell ${navOpen ? 'nav-open' : ''}`}>
      <a className="skip" href="#main">{t('c.skip_to_content')}</a>
      <aside className="side" aria-label={t('nav.menu')}>
        <div className="side-top">
          <Brand dark />
          <button type="button" className="side-close" aria-label={t('c.close')} onClick={() => setNavOpen(false)}><X size={18} /></button>
        </div>
        <nav className="nav">
          {visible.map((g) => {
            const hasActive = g.items.some((i) => isActive(loc.pathname, i.to));
            const isOpen = !g.title || hasActive || !closed.includes(g.id);
            const listId = `nav-${g.id}`;
            return (
              <div className={`nav-group${isOpen ? '' : ' is-closed'}`} key={g.id}>
                {g.title && (
                  <button type="button" className="nav-group-title" aria-expanded={isOpen} aria-controls={listId}
                    disabled={hasActive} onClick={() => toggle(g.id)}>
                    <span>{t(g.title)}</span>
                    <ChevronDown size={14} aria-hidden="true" className="nav-chev" />
                  </button>
                )}
                {isOpen && (
                  <div id={listId} className="nav-items">
                    {g.items.map((i) => {
                      const Icon = i.icon;
                      return (
                        <NavLink key={i.to} to={i.to} end={i.to === '/' || i.to === '/payroll' || i.to === '/leave'}
                          className={({ isActive: a }) => (a || (current?.i.to === i.to) ? 'active' : undefined)}>
                          <Icon size={18} strokeWidth={1.75} aria-hidden="true" className="nav-ico" />
                          <span className="nav-label">{t(i.key)}</span>
                          {i.count ? <span className="count num">{i.count > 99 ? '99+' : i.count}</span> : null}
                        </NavLink>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </nav>
        <div className="side-foot">
          <span className="avatar avatar-sm" aria-hidden="true">{initials(me?.display_name || me?.email)}</span>
          <div className="side-user">
            <b>{me?.display_name || me?.email}</b>
            <span className="ltr-inline">{me?.email}</span>
          </div>
          <button type="button" className="side-out" aria-label={t('c.signout')} title={t('c.signout')} onClick={() => void signOut()}>
            <LogOut size={17} aria-hidden="true" />
          </button>
        </div>
      </aside>
      <div className="scrim" onClick={() => setNavOpen(false)} aria-hidden="true" />
      <div className="main">
        <header className="top">
          <button type="button" className="icon-btn menu-btn" aria-label={t('nav.menu')} aria-expanded={navOpen}
            onClick={() => setNavOpen((v) => !v)}><Menu size={20} /></button>
          <div className="crumbs" aria-label={t('shell.home')}>
            {CurIcon && <span className="crumb-ico" aria-hidden="true"><CurIcon size={16} strokeWidth={1.75} /></span>}
            {current?.g.title && <><span className="crumb-group">{t(current.g.title)}</span><span className="crumb-sep" aria-hidden="true">/</span></>}
            <span className="crumb-page">{current ? t(current.i.key) : t('app.name')}</span>
          </div>
          <span className="spacer" />
          {(can('EMP_READ') || me?.is_manager) && <TopSearch />}
          <LangSwitch />
          <NavLink to="/notifications" className="icon-btn bell" aria-label={`${t('nav.notifications')} (${unread})`}>
            <Bell size={19} strokeWidth={1.75} aria-hidden="true" />
            {unread > 0 && <span className="dot num">{unread > 99 ? '99+' : unread}</span>}
          </NavLink>
          <AccountMenu />
        </header>
        <main className="content" id="main" tabIndex={-1}>
          <Suspense fallback={<Loading />}>
            <Outlet />
          </Suspense>
        </main>
      </div>
    </div>
  );
}

export function PageHead({ title, sub, actions }: { title: ReactNode; sub?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="page-head">
      <div className="page-head-text">
        <h1>{title}</h1>
        {sub && <p>{sub}</p>}
      </div>
      {actions && <div className="page-actions row no-print">{actions}</div>}
    </div>
  );
}

