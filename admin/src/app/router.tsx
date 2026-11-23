import { createBrowserRouter, Navigate } from 'react-router';

import { ApplicationDetailPage, ApplicationsPage } from '../features/applications';
import { AuditLogPage } from '../features/audit/pages/AuditLogPage';
import { LoginPage, RequireStaff } from '../features/auth';
import { ModerationPage } from '../features/moderation';
import { OverviewPage } from '../features/overview/pages/OverviewPage';
import { BusinessPerformanceDetailPage, BusinessPerformancePage } from '../features/performance';
import { UsersPage } from '../features/users/pages/UsersPage';
import { AppShell } from './layout/AppShell';

/** Every route except /login is for HDC administrators, the one staff role (ADR 0009). */
export const routes = [
  { path: '/login', element: <LoginPage /> },
  {
    path: '/',
    element: (
      <RequireStaff>
        <AppShell />
      </RequireStaff>
    ),
    children: [
      { index: true, element: <OverviewPage /> },
      { path: 'applications', element: <ApplicationsPage /> },
      { path: 'applications/:applicationId', element: <ApplicationDetailPage /> },
      { path: 'performance', element: <BusinessPerformancePage /> },
      { path: 'performance/:businessId', element: <BusinessPerformanceDetailPage /> },
      { path: 'moderation', element: <ModerationPage /> },
      { path: 'users', element: <UsersPage /> },
      { path: 'audit', element: <AuditLogPage /> },
    ],
  },
  { path: '*', element: <Navigate to="/" replace /> },
];

/**
 * Vite's base path (`/` locally, `/CampusNiaga/` on GitHub Pages), without
 * the trailing slash React Router doesn't want.
 */
export function routerBasename(base: string): string {
  return base.replace(/\/+$/, '') || '/';
}

export function createAppRouter() {
  return createBrowserRouter(routes, { basename: routerBasename(import.meta.env.BASE_URL) });
}
