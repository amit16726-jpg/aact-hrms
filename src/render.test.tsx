import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import type { ReactNode } from 'react';

// --- jsdom gaps -------------------------------------------------------------
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal(this: HTMLDialogElement) { this.setAttribute('open', ''); };
  HTMLDialogElement.prototype.close = function close(this: HTMLDialogElement) { this.removeAttribute('open'); };
});
afterEach(() => cleanup());

// --- mocked server ------------------------------------------------------------
const me = {
  user_id: 'u1', email: 'mgr@aact.test', display_name: 'Manager', language: 'en', is_active: true, employee_id: 'e-mgr',
  employee_no: 'AACT-00001', employee_name: 'Salim Al Harthy', employee_name_ar: 'سالم الحارثي', roles: ['MANAGER'],
  permissions: ['ORG_READ'], is_manager: true, admin_exists: true, settings: {}, entities: [{ id: 'ent', code: 'AACT', name_en: 'AACT', name_ar: null }],
  unread_notifications: 0,
};

const teamFile = {
  employee: { id: 'e-w', entity_id: 'ent', employee_no: 'AACT-00002', full_name_en: 'Ravi Kumar', full_name_ar: null, preferred_name: null,
    gender: 'M', nationality: 'IN', nationality_en: 'Indian', nationality_ar: 'هندي', work_email: null, mobile: '+968 9000 0000',
    photo_path: null, join_date: '2026-08-21', probation_end_date: null, confirmation_date: null, status: 'ACTIVE', is_omani: false },
  access: 'TEAM', current_assignment: null, assignments: [], contracts: [], emergency_contacts: [], events: [], omanisation_exceptions: [],
  linked_user: null,
  caps: { edit: false, salary_read: false, salary_write: false, salary_approve: false, bank_read: false, bank_write: false, bank_approve: false,
    docs_read: false, docs_write: false, docs_sensitive: false, history: false, exception_approve: false },
};

vi.mock('./lib/api', async (orig) => {
  const real = await orig<typeof import('./lib/api')>();
  return {
    ...real,
    signedUrl: vi.fn(async () => 'about:blank'),
    api: {
      ...real.api,
      me: vi.fn(async () => me),
      getEmployee: vi.fn(async () => teamFile),
      listNotifications: vi.fn(async () => ({ unread: 0, rows: [] })),
      dashboard: vi.fn(async () => ({
        compliance: { expired: 1, d30: 2, d60: 0, d90: 3, missing: 4, employees_missing: 2 },
        expiring_soon: [{ employee_id: 'e-w', employee_no: 'AACT-00002', full_name_en: 'Ravi Kumar', full_name_ar: null, nationality: 'IN',
          entity_id: 'ent', department_id: null, department_en: 'Production', department_ar: null, source: 'DOCUMENT', ref_id: 'd1',
          doc_type: 'RESIDENT_CARD', name_en: 'Resident card', name_ar: 'بطاقة المقيم', doc_number: null, expiry_date: '2026-10-15',
          days_left: -5, bucket: 'EXPIRED', is_sensitive: false }],
        approvals: { salary: 0, bank: 0, targets: 0 },
      })),
    },
  };
});

vi.mock('./lib/session', () => ({
  useSession: () => ({
    ready: true, session: {}, me, meError: null, recovery: false, hasAnyRole: true,
    can: (p: string) => me.permissions.includes(p), reload: async () => undefined, setMe: () => undefined,
    signOut: async () => undefined, clearRecovery: () => undefined,
  }),
}));

import { I18nProvider } from './i18n';
import { Modal, ToastProvider } from './components/ui';
import { Runway } from './components/Runway';
import { DashboardPage } from './pages/Dashboard';
import EmployeeDetailPage from './pages/employee/EmployeeDetail';

function wrap(node: ReactNode, lang: 'en' | 'ar' = 'en', path = '/') {
  return render(
    <I18nProvider initial={lang}>
      <ToastProvider>
        <MemoryRouter initialEntries={[path]}>
          <Routes>
            <Route path="/" element={node} />
            <Route path="/employees/:id" element={node} />
          </Routes>
        </MemoryRouter>
      </ToastProvider>
    </I18nProvider>,
  );
}

describe('runway', () => {
  it('shows each bucket with its count and links to the filtered tracker', () => {
    wrap(<Runway expired={1} d30={2} d60={0} d90={3} />);
    const items = screen.getAllByRole('listitem');
    expect(items).toHaveLength(4);
    expect(items[0].textContent).toContain('1');
    expect(items[0].textContent).toContain('Expired');
    expect(items[0].getAttribute('href')).toBe('/compliance/expiries?bucket=EXPIRED');
    expect(items[2].className).toContain('seg-zero');
  });
  it('switches to Arabic and right-to-left', () => {
    wrap(<Runway expired={0} d30={0} d60={0} d90={0} />, 'ar');
    expect(screen.getByText('منتهٍ')).toBeTruthy();
    expect(document.documentElement.dir).toBe('rtl');
  });
});

describe('dashboard', () => {
  it('renders compliance figures and the expiring list from the server', async () => {
    wrap(<DashboardPage />);
    await waitFor(() => expect(screen.getByText('Ravi Kumar')).toBeTruthy());
    expect(screen.getByText(/4 mandatory documents missing for 2 employees/)).toBeTruthy();
    expect(screen.getByText('5 days ago')).toBeTruthy();
    expect(screen.queryByText('Headcount')).toBeNull(); // no workforce section for this role
  });
});

describe('employee file for a line manager', () => {
  it('shows only the profile and time tabs and the limited-view note', async () => {
    wrap(<EmployeeDetailPage />, 'en', '/employees/e-w');
    await waitFor(() => expect(screen.getAllByText('Ravi Kumar').length).toBeGreaterThan(0));
    const tabs = screen.getAllByRole('tab');
    expect(tabs.map((x) => x.textContent)).toEqual(['Profile', 'Time and leave']);
    expect(screen.getByText(/line manager needs/)).toBeTruthy();
    expect(screen.queryByText('Edit personal details')).toBeNull();
    expect(screen.queryByText('Employment actions')).toBeNull();
  });
});

describe('dialog', () => {
  it('closes on Escape (and so on the Android back button)', () => {
    const onClose = vi.fn();
    wrap(<Modal open title="Test" onClose={onClose}><p>Body</p></Modal>);
    const dlg = document.querySelector('dialog')!;
    fireEvent(dlg, new Event('cancel', { cancelable: true }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
