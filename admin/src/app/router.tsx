import { createBrowserRouter, Navigate } from 'react-router';

import { ApplicationDetailPage, ApplicationsPage } from '../features/applications';
import { AuditLogPage } from '../features/audit/pages/AuditLogPage';
import { LoginPage, RequireStaff } from '../features/auth';
import { ModerationPage } from '../features/moderation';
import { OverviewPage } from '../features/overview/pages/OverviewPage';
import { UsersPage } from '../features/users/pages/UsersPage';
import { AppShell } from './layout/AppShell';

/** Every route except /login needs a staff role; admin pages need admin. */
export const routes = [
  { path: '/login', element: <LoginPage /> },
  {
    path: '/',
    element: (
      <RequireStaff role="reviewer">
        <AppShell />
      </RequireStaff>
    ),
    children: [
      { index: true, element: <OverviewPage /> },
      { path: 'applications', element: <ApplicationsPage /> },
      { path: 'applications/:applicationId', element: <ApplicationDetailPage /> },
      {
        path: 'moderation',
        element: (
          <RequireStaff role="admin">
            <ModerationPage />
          </RequireStaff>
        ),
      },
      {
        path: 'users',
        element: (
          <RequireStaff role="admin">
            <UsersPage />
          </RequireStaff>
        ),
      },
      {
        path: 'audit',
        element: (
          <RequireStaff role="admin">
            <AuditLogPage />
          </RequireStaff>
        ),
      },
    ],
  },
  { path: '*', element: <Navigate to="/" replace /> },
];

export function createAppRouter() {
  return createBrowserRouter(routes);
}
