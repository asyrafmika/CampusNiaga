import { createBrowserRouter, Navigate } from 'react-router';

import { AuditLogPage } from '../features/audit/pages/AuditLogPage';
import { LoginPage, RequireStaff } from '../features/auth';
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
