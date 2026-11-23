import StorefrontRoundedIcon from '@mui/icons-material/StorefrontRounded';
import { Alert, Box, Button, CircularProgress, Paper, Stack, TextField, Typography } from '@mui/material';
import { useMutation } from '@tanstack/react-query';
import { useState, type SyntheticEvent } from 'react';
import { Navigate, useSearchParams } from 'react-router';

import { palette } from '../../../app/theme';
import { messageOf } from '../../../shared/lib/errors';
import { isStaff } from '../access';
import { useAccess } from '../hooks/useAccess';
import { signIn } from '../services/authService';

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export function LoginPage() {
  const access = useAccess();
  const [params] = useSearchParams();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [touched, setTouched] = useState(false);
  const login = useMutation({ mutationFn: () => signIn(email, password) });

  if (access.status === 'ready' && isStaff(access.access)) return <Navigate to="/" replace />;

  const emailError = touched && !EMAIL.test(email.trim()) ? 'Enter a valid email address.' : undefined;
  const passwordError = touched && password.length === 0 ? 'Enter your password.' : undefined;

  const submit = (event: SyntheticEvent) => {
    event.preventDefault();
    setTouched(true);
    if (!EMAIL.test(email.trim()) || password.length === 0) return;
    login.mutate();
  };

  return (
    <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center', bgcolor: 'background.default', p: 2 }}>
      <Paper component="form" onSubmit={submit} noValidate sx={{ width: '100%', maxWidth: 420, p: 4 }}>
        <Stack spacing={3}>
          <Stack direction="row" spacing={1.5} sx={{ alignItems: 'center' }}>
            <Box
              sx={{
                width: 44,
                height: 44,
                borderRadius: 2,
                bgcolor: palette.primary,
                color: '#fff',
                display: 'grid',
                placeItems: 'center',
              }}
            >
              <StorefrontRoundedIcon />
            </Box>
            <Typography variant="h2" component="p">
              CampusNiaga
            </Typography>
          </Stack>

          <Box>
            <Typography variant="h1">Staff sign in</Typography>
            <Typography sx={{ color: 'text.secondary', mt: 0.5 }}>
              For CampusNiaga HDC administrators.
            </Typography>
          </Box>

          {params.get('reason') === 'staff-only' && (
            <Alert severity="info">
              The dashboard is for CampusNiaga staff only. Students use the mobile app.
            </Alert>
          )}
          {login.isError && <Alert severity="error">{messageOf(login.error)}</Alert>}

          <TextField
            label="Email"
            type="email"
            autoComplete="email"
            value={email}
            onChange={(e) => {
              setEmail(e.target.value);
            }}
            error={emailError !== undefined}
            helperText={emailError}
          />
          <TextField
            label="Password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => {
              setPassword(e.target.value);
            }}
            error={passwordError !== undefined}
            helperText={passwordError}
          />
          <Button type="submit" variant="contained" size="large" disabled={login.isPending}>
            {login.isPending ? <CircularProgress size={24} color="inherit" aria-label="Signing in" /> : 'Sign in'}
          </Button>
        </Stack>
      </Paper>
    </Box>
  );
}
