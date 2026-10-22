import { lazy, Suspense } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { useSession } from './lib/session';
import { useI18n } from './i18n';
import { Loading } from './components/ui';
import Layout from './components/Layout';
import { AuthPage, SetPasswordPage } from './pages/Auth';
import { SetupPage } from './pages/Setup';
import { MfaPage } from './pages/Mfa';
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
const EngagePage = lazy(() => import('./pages/eng/EngagePage'));
const EngageAdminPage = lazy(() => import('./pages/eng/EngageAdminPage'));
const AnnouncementPage = lazy(() => import('./pages/eng/AnnouncementPage'));
const SurveyPage = lazy(() => import('./pages/eng/SurveyPage'));
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
const PayrollPage = lazy(() => import('./pages/pay/PayrollPage'));
const PayrollRunPage = lazy(() => import('./pages/pay/PayrollRunPage'));
const LoansPage = lazy(() => import('./pages/pay/LoansPage'));
const PayItemsPage = lazy(() => import('./pages/pay/PayItemsPage'));
const SettlementsPage = lazy(() => import('./pages/pay/SettlementsPage'));
const SettlementPage = lazy(() => import('./pages/pay/SettlementsPage').then((m) => ({ default: m.SettlementPage })));
const GratuityPage = lazy(() => import('./pages/pay/GratuityPage'));
const PayRulesPage = lazy(() => import('./pages/pay/PayRulesPage'));
const PayrollSetupPage = lazy(() => import('./pages/pay/PayrollSetupPage'));
const PayslipPage = lazy(() => import('./pages/pay/PayslipPages').then((m) => ({ default: m.PayslipPage })));
const MyPayslipsPage = lazy(() => import('./pages/pay/PayslipPages').then((m) => ({ default: m.MyPayslipsPage })));
const MyHrPage = lazy(() => import('./pages/ss/MyHrPage'));
const RequestsPage = lazy(() => import('./pages/ss/RequestsPage'));
const LetterPage = lazy(() => import('./pages/ss/LetterPage'));
const TeamPage = lazy(() => import('./pages/ss/TeamPage'));
const VerifyPage = lazy(() => import('./pages/ss/VerifyPage'));
const RecruitmentPage = lazy(() => import('./pages/rec/RecruitmentPage'));
const RequisitionPage = lazy(() => import('./pages/rec/RequisitionPage'));
const ApplicationPage = lazy(() => import('./pages/rec/ApplicationPage'));
const OfferPage = lazy(() => import('./pages/rec/OfferPage'));
const ProbationPage = lazy(() => import('./pages/rec/ProbationPage'));
const PerformancePage = lazy(() => import('./pages/wf/PerformancePage'));
const ReviewPage = lazy(() => import('./pages/wf/ReviewPage'));
const TrainingPage = lazy(() => import('./pages/wf/TrainingPage'));
const DisciplinePage = lazy(() => import('./pages/wf/DisciplinePage'));
const CasePage = lazy(() => import('./pages/wf/CasePage'));
const AssetsPage = lazy(() => import('./pages/wf/AssetsPage'));
const FacilitiesPage = lazy(() => import('./pages/wf/FacilitiesPage'));
const InjuriesPage = lazy(() => import('./pages/wf/InjuriesPage'));
const ExitsPage = lazy(() => import('./pages/wf/ExitsPage'));
const ExitPage = lazy(() => import('./pages/wf/ExitPage'));
const ExecutivePage = lazy(() => import('./pages/gov/ExecutivePage'));
const ReportsPage = lazy(() => import('./pages/rep/ReportsPage'));
const MolReportPage = lazy(() => import('./pages/gov/MolReportPage'));
const SpfReportPage = lazy(() => import('./pages/gov/SpfReportPage'));
const PrivacyPage = lazy(() => import('./pages/gov/PrivacyPage'));
const ImportDataPage = lazy(() => import('./pages/gov/ImportPage'));

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
  // public letter check: works with or without signing in
  if (window.location.pathname === '/verify') return <Suspense fallback={<Loading />}><VerifyPage /></Suspense>;
  if (!ready) return <Loading />;
  if (recovery && session) return <SetPasswordPage />;
  if (!session) return <AuthPage />;
  if (!me) return <SetupPage />;
  if (me.mfa_state === 'CHALLENGE' || me.mfa_state === 'SETUP') return <MfaPage mode={me.mfa_state} />;
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
            <Route path="payroll" element={<PayrollPage />} />
            <Route path="payroll/loans" element={<LoansPage />} />
            <Route path="payroll/items" element={<PayItemsPage />} />
            <Route path="payroll/settlements" element={<SettlementsPage />} />
            <Route path="payroll/settlements/:id" element={<SettlementPage />} />
            <Route path="payroll/gratuity" element={<GratuityPage />} />
            <Route path="payroll/rules" element={<PayRulesPage />} />
            <Route path="payroll/setup" element={<PayrollSetupPage />} />
            <Route path="payroll/:id" element={<PayrollRunPage />} />
            <Route path="payslips" element={<MyPayslipsPage />} />
            <Route path="payslips/:id" element={<PayslipPage />} />
            <Route path="me" element={<MyHrPage />} />
            <Route path="engage" element={<EngagePage />} />
            <Route path="engage/admin" element={<EngageAdminPage />} />
            <Route path="engage/news/:id" element={<AnnouncementPage />} />
            <Route path="engage/survey/:id" element={<SurveyPage />} />
            <Route path="team" element={<TeamPage />} />
            <Route path="requests" element={<RequestsPage />} />
            <Route path="letters/:id" element={<LetterPage />} />
            <Route path="recruitment" element={<RecruitmentPage />} />
            <Route path="recruitment/req/:id" element={<RequisitionPage />} />
            <Route path="recruitment/app/:id" element={<ApplicationPage />} />
            <Route path="recruitment/offer/:id" element={<OfferPage />} />
            <Route path="probation" element={<ProbationPage />} />
            <Route path="performance" element={<PerformancePage />} />
            <Route path="performance/review/:id" element={<ReviewPage />} />
            <Route path="training" element={<TrainingPage />} />
            <Route path="discipline" element={<DisciplinePage />} />
            <Route path="discipline/:id" element={<CasePage />} />
            <Route path="assets" element={<AssetsPage />} />
            <Route path="facilities" element={<FacilitiesPage />} />
            <Route path="injuries" element={<InjuriesPage />} />
            <Route path="exits" element={<ExitsPage />} />
            <Route path="exits/:id" element={<ExitPage />} />
            <Route path="executive" element={<ExecutivePage />} />
            <Route path="reports" element={<ReportsPage />} />
            <Route path="reports/mol" element={<MolReportPage />} />
            <Route path="reports/spf" element={<SpfReportPage />} />
            <Route path="privacy" element={<PrivacyPage />} />
            <Route path="admin/import" element={<ImportDataPage />} />
            <Route path="*" element={<NotFound />} />
          </Route>
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}
