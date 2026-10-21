import { lazy, Suspense } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { useSession } from './lib/session';
import { useI18n } from './i18n';
import { Loading } from './components/ui';
import Layout from './components/Layout';
import { AuthPage, SetPasswordPage } from './pages/Auth';
import { SetupPage } from './pages/Setup';
import { DashboardPage } from './pages/Dashboard';

const EmployeesPage = lazy(() => import('./pages/Employees'));
const EmployeeNewPage = lazy(() => import('./pages/EmployeeNew'));
const EmployeeDetailPage = lazy(() => import('./pages/employee/EmployeeDetail'));
const ExpiriesPage = lazy(() => import('./pages/Expiries'));
const MissingPage = lazy(() => import('./pages/Missing'));
const OmanisationPage = lazy(() => import('./pages/Omanisation'));
const TargetsPage = lazy(() => import('./pages/Targets'));
const ApprovalsPage = lazy(() => import('./pages/Approvals'));
const OrganisationPage = lazy(() => import('./pages/Organisation'));
const UsersPage = lazy(() => import('./pages/Users'));
const AuditPage = lazy(() => import('./pages/Audit'));
const SettingsPage = lazy(() => import('./pages/Settings'));
const NotificationsPage = lazy(() => import('./pages/Notifications'));
const AttendancePage = lazy(() => import('./pages/time/AttendancePage'));
const OvertimePage = lazy(() => import('./pages/time/OvertimePage'));
const LeavePage = lazy(() => import('./pages/time/LeavePage'));
const LeaveAdminPage = lazy(() => import('./pages/time/LeaveAdminPage'));
const ShiftsPage = lazy(() => import('./pages/time/ShiftsPage'));
const CalendarPage = lazy(() => import('./pages/time/CalendarPage'));
const ImportPage = lazy(() => import('./pages/time/ImportPage'));
const PeriodsPage = lazy(() => import('./pages/time/PeriodsPage'));
const RulesPage = lazy(() => import('./pages/time/RulesPage'));

function NotFound() {
  const { t } = useI18n();
  return <div className="empty"><h1>404</h1><p>{t('err.NOT_FOUND')}</p><a href="/">{t('nav.dashboard')}</a></div>;
}

function MyRecord() {
  const { me } = useSession();
  return me?.employee_id ? <Navigate to={`/employees/${me.employee_id}`} replace /> : <Navigate to="/" replace />;
}

export default function App() {
  const { ready, session, me, hasAnyRole, recovery } = useSession();
  if (!ready) return <Loading />;
  if (recovery && session) return <SetPasswordPage />;
  if (!session) return <AuthPage />;
  if (!me) return <SetupPage />;
  if (!hasAnyRole) return <SetupPage />;
  return (
    <BrowserRouter>
      <Suspense fallback={<Loading />}>
        <Routes>
          <Route element={<Layout />}>
            <Route index element={<DashboardPage />} />
            <Route path="my" element={<MyRecord />} />
            <Route path="employees" element={<EmployeesPage />} />
            <Route path="employees/new" element={<EmployeeNewPage />} />
            <Route path="employees/:id" element={<EmployeeDetailPage />} />
            <Route path="approvals" element={<ApprovalsPage />} />
            <Route path="compliance/expiries" element={<ExpiriesPage />} />
            <Route path="compliance/missing" element={<MissingPage />} />
            <Route path="compliance/omanisation" element={<OmanisationPage />} />
            <Route path="compliance/targets" element={<TargetsPage />} />
            <Route path="organisation" element={<OrganisationPage />} />
            <Route path="admin/users" element={<UsersPage />} />
            <Route path="admin/audit" element={<AuditPage />} />
            <Route path="settings" element={<SettingsPage />} />
            <Route path="notifications" element={<NotificationsPage />} />
            <Route path="attendance" element={<AttendancePage />} />
            <Route path="overtime" element={<OvertimePage />} />
            <Route path="leave" element={<LeavePage />} />
            <Route path="leave/admin" element={<LeaveAdminPage />} />
            <Route path="time/shifts" element={<ShiftsPage />} />
            <Route path="time/calendar" element={<CalendarPage />} />
            <Route path="time/import" element={<ImportPage />} />
            <Route path="time/periods" element={<PeriodsPage />} />
            <Route path="time/rules" element={<RulesPage />} />
            <Route path="*" element={<NotFound />} />
          </Route>
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}
