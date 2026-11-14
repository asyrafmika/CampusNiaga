import { Alert, Box, Button, CircularProgress } from '@mui/material';
import { useEffect, type ReactNode } from 'react';
import { Navigate, useNavigate } from 'react-router';

import { hasRole, isStaff, type StaffRole } from '../access';
import { useAccess } from '../hooks/useAccess';
import { signOut } from '../services/authService';

function Centered({ children }: { children: ReactNode }) {
  return <Box sx={{ minHeight: '60vh', display: 'grid', placeItems: 'center', p: 4 }}>{children}</Box>;
}

/** Signs out an account without a staff role, then explains why on the login page. */
function SignOutNonStaff() {
  const navigate = useNavigate();
  useEffect(() => {
    void signOut().then(() => navigate('/login?reason=staff-only', { replace: true }));
  }, [navigate]);
  return (
    <Centered>
      <CircularProgress />
    </Centered>
  );
}

type RequireStaffProps = {
  role: StaffRole;
  children: ReactNode;
};

/**
 * Shows [children] only to signed-in staff with [role]. This is for the UI:
 * the database refuses every request from anyone else anyway.
 */
export function RequireStaff({ role, children }: RequireStaffProps) {
  const state = useAccess();

  switch (state.status) {
    case 'loading':
      return (
        <Centered>
          <CircularProgress aria-label="Checking access" />
        </Centered>
      );
    case 'signedOut':
      return <Navigate to="/login" replace />;
    case 'error':
      return (
        <Centered>
          <Alert
            severity="error"
            action={
              <Button color="inherit" onClick={state.retry}>
                Try again
              </Button>
            }
          >
            Could not check your access. {state.error.message}
          </Alert>
        </Centered>
      );
    case 'ready':
      if (!isStaff(state.access)) return <SignOutNonStaff />;
      if (!hasRole(state.access, role)) {
        return (
          <Centered>
            <Alert severity="warning">This page is for administrators only.</Alert>
          </Centered>
        );
      }
      return children;
  }
}
