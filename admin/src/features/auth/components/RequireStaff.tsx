import { Alert, Box, Button, CircularProgress } from '@mui/material';
import { useEffect, type ReactNode } from 'react';
import { Navigate, useNavigate } from 'react-router';

import { isStaff } from '../access';
import { useAccess } from '../hooks/useAccess';
import { signOut } from '../services/authService';

function Centered({ children }: { children: ReactNode }) {
  return <Box sx={{ minHeight: '60vh', display: 'grid', placeItems: 'center', p: 4 }}>{children}</Box>;
}

/** Signs out an account without the administrator role, then explains why on the login page. */
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
  children: ReactNode;
};

/**
 * Shows [children] only to a signed-in HDC administrator, the one staff role
 * (ADR 0009). This is for the UI: the database refuses everyone else anyway.
 */
export function RequireStaff({ children }: RequireStaffProps) {
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
      return children;
  }
}
