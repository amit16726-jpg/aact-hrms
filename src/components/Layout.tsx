import { useEffect, useState, type ReactNode } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { useI18n, type Key } from '../i18n';
import { useSession } from '../lib/session';
import { api } from '../lib/api';

interface Item { to: string; key: Key; show: boolean; count?: number }

export function LangSwitch() {
  const { lang, setLang, t } = useI18n();
  const { me, setMe } = useSession();
  const change = async (l: 'en' | 'ar') => {
    setLang(l);
    if (me) { try { setMe(await api.setMyProfile({ language: l })); } catch { /* keep local choice */ } }
  };
  return (
    <div className="lang-switch" role="group" aria-label={t('c.language')}>
      <button type="button" aria-pressed={lang === 'en'} onClick={() => change('en')} lang="en">EN</button>
      <button type="button" aria-pressed={lang === 'ar'} onClick={() => change('ar')} lang="ar">ع</button>
    </div>
  );
}

export function Brand() {
  const { t } = useI18n();
  return (
    <div className="brand">
      <div className="brand-mark" aria-hidden="true">A</div>
      <div>
        <div className="brand-name">{t('app.name')}</div>
        <div className="brand-sub">{t('app.tagline')}</div>
      </div>
    </div>
  );
}

export default function Layout() {
  const { t } = useI18n();
  const { me, can, signOut } = useSession();
  const loc = useLocation();
  const [navOpen, setNavOpen] = useState(false);
  const [unread, setUnread] = useState(me?.unread_notifications ?? 0);
  const [approvals, setApprovals] = useState(0);

  useEffect(() => { setNavOpen(false); }, [loc.pathname]);
  useEffect(() => {
    let alive = true;
    const load = () => {
      api.listNotifications(true).then((r) => alive && setUnread(r.unread)).catch(() => undefined);
      if (can('SALARY_APPROVE') || can('BANK_APPROVE') || can('RULES_APPROVE')) {
        api.dashboard().then((d) => alive && setApprovals(d.approvals.salary + d.approvals.bank + d.approvals.targets)).catch(() => undefined);
      }
    };
    load();
    const id = window.setInterval(load, 120000);
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);
    return () => { alive = false; window.clearInterval(id); window.removeEventListener('focus', onFocus); };
  }, [can, loc.pathname]);

  const groups: { title?: Key; items: Item[] }[] = [
    { items: [
      { to: '/', key: 'nav.dashboard', show: true },
      { to: '/my', key: 'nav.my_record', show: !!me?.employee_id },
      { to: '/employees', key: 'nav.employees', show: can('EMP_READ') || !!me?.is_manager },
      { to: '/approvals', key: 'nav.approvals', show: can('SALARY_APPROVE') || can('BANK_APPROVE') || can('RULES_APPROVE'), count: approvals },
    ] },
    { title: 'nav.compliance', items: [
      { to: '/compliance/expiries', key: 'nav.expiries', show: can('COMPLIANCE_READ') || !!me?.is_manager },
      { to: '/compliance/missing', key: 'nav.missing', show: can('COMPLIANCE_READ') },
      { to: '/compliance/omanisation', key: 'nav.omanisation', show: can('COMPLIANCE_READ') },
      { to: '/compliance/targets', key: 'nav.targets', show: can('COMPLIANCE_READ') },
    ] },
    { title: 'nav.admin', items: [
      { to: '/organisation', key: 'nav.organisation', show: can('ORG_WRITE') || can('EMP_READ') },
      { to: '/admin/users', key: 'nav.users', show: can('USERS_ADMIN') },
      { to: '/admin/audit', key: 'nav.audit', show: can('AUDIT_READ') },
      { to: '/settings', key: 'nav.settings', show: true },
    ] },
  ];

  return (
    <div className={`shell ${navOpen ? 'nav-open' : ''}`}>
      <aside className="side" aria-label={t('nav.menu')}>
        <Brand />
        <nav className="nav">
          {groups.map((g, gi) => {
            const items = g.items.filter((i) => i.show);
            if (!items.length) return null;
            return (
              <div className="nav-group" key={gi}>
                {g.title && <div className="nav-group-title">{t(g.title)}</div>}
                {items.map((i) => (
                  <NavLink key={i.to} to={i.to} end={i.to === '/'}>
                    <span>{t(i.key)}</span>
                    {i.count ? <span className="count num">{i.count}</span> : null}
                  </NavLink>
                ))}
              </div>
            );
          })}
        </nav>
      </aside>
      <div className="scrim" onClick={() => setNavOpen(false)} aria-hidden="true" />
      <div className="main">
        <header className="top">
          <button type="button" className="btn btn-ghost btn-icon menu-btn" aria-label={t('nav.menu')} aria-expanded={navOpen}
            onClick={() => setNavOpen((v) => !v)}>☰</button>
          <div className="top-title">{me?.display_name || me?.email}</div>
          <LangSwitch />
          <NavLink to="/notifications" className="btn btn-ghost btn-icon bell" aria-label={`${t('nav.notifications')} (${unread})`}>
            <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M6 8a6 6 0 1 1 12 0c0 7 3 8 3 8H3s3-1 3-8" /><path d="M10.3 20a2 2 0 0 0 3.4 0" /></svg>
            {unread > 0 && <span className="dot num">{unread > 99 ? '99+' : unread}</span>}
          </NavLink>
          <button type="button" className="btn btn-sm" onClick={() => void signOut()}>{t('c.signout')}</button>
        </header>
        <main className="content" id="main">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

export function PageHead({ title, sub, actions }: { title: ReactNode; sub?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="page-head">
      <div>
        <h1>{title}</h1>
        {sub && <p>{sub}</p>}
      </div>
      {actions && <div className="row no-print">{actions}</div>}
    </div>
  );
}
