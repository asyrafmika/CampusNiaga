import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi, type Mock } from 'vitest';

import { AppError } from '../../../shared/lib/errors';
import { renderAt } from '../../../test/render';
import type { AccessState } from '../hooks/useAccess';
import { LoginPage } from './LoginPage';

type Mocks = { state: AccessState; signIn: Mock<(email: string, password: string) => Promise<void>> };
const mocks = vi.hoisted((): Mocks => ({ state: { status: 'signedOut' }, signIn: vi.fn() }));

vi.mock('../hooks/useAccess', () => ({ useAccess: () => mocks.state }));
vi.mock('../services/authService', () => ({ signIn: mocks.signIn }));

describe('LoginPage', () => {
  beforeEach(() => {
    mocks.state = { status: 'signedOut' };
    mocks.signIn.mockReset();
  });

  it('checks the form before calling the server', async () => {
    renderAt(<LoginPage />, { path: '/login' });
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(screen.getByText('Enter a valid email address.')).toBeInTheDocument();
    expect(screen.getByText('Enter your password.')).toBeInTheDocument();
    expect(mocks.signIn).not.toHaveBeenCalled();
  });

  it('signs in with the typed details', async () => {
    mocks.signIn.mockResolvedValue();
    renderAt(<LoginPage />, { path: '/login' });

    await userEvent.type(screen.getByLabelText('Email'), 'admin@campusniaga.test');
    await userEvent.type(screen.getByLabelText('Password'), 'secret-pass');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(mocks.signIn).toHaveBeenCalledWith('admin@campusniaga.test', 'secret-pass');
  });

  it('shows why sign-in failed', async () => {
    mocks.signIn.mockRejectedValue(new AppError('Email or password is incorrect.'));
    renderAt(<LoginPage />, { path: '/login' });

    await userEvent.type(screen.getByLabelText('Email'), 'admin@campusniaga.test');
    await userEvent.type(screen.getByLabelText('Password'), 'wrong');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText('Email or password is incorrect.')).toBeInTheDocument();
  });

  it('explains when a student was turned away', () => {
    renderAt(<LoginPage />, { path: '/login', at: '/login?reason=staff-only' });
    expect(screen.getByText(/The dashboard is for CampusNiaga staff only/)).toBeInTheDocument();
  });

  it('sends signed-in staff straight to the dashboard', () => {
    mocks.state = {
      status: 'ready',
      access: { userId: 'u1', email: 'a@usm.my', isReviewer: true, isAdmin: false },
    };
    renderAt(<LoginPage />, { path: '/login' });
    expect(screen.getByText('page: /')).toBeInTheDocument();
  });
});
