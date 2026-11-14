import { screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi, type Mock } from 'vitest';

import { renderAt } from '../../../test/render';
import type { AccessState } from '../hooks/useAccess';
import { RequireStaff } from './RequireStaff';

type Mocks = { state: AccessState; signOut: Mock<() => Promise<void>> };
const mocks = vi.hoisted(
  (): Mocks => ({ state: { status: 'loading' }, signOut: vi.fn(() => Promise.resolve()) }),
);

vi.mock('../hooks/useAccess', () => ({ useAccess: () => mocks.state }));
vi.mock('../services/authService', () => ({ signOut: mocks.signOut }));

const person = { userId: 'u1', email: 'a@usm.my', isReviewer: false, isAdmin: false };

function renderGuard(role: 'reviewer' | 'admin') {
  return renderAt(
    <RequireStaff role={role}>
      <p>secret page</p>
    </RequireStaff>,
  );
}

describe('RequireStaff', () => {
  beforeEach(() => {
    mocks.signOut.mockClear();
  });

  it('shows a spinner while access is checked', () => {
    mocks.state = { status: 'loading' };
    renderGuard('reviewer');
    expect(screen.getByLabelText('Checking access')).toBeInTheDocument();
    expect(screen.queryByText('secret page')).not.toBeInTheDocument();
  });

  it('sends signed-out visitors to the login page', () => {
    mocks.state = { status: 'signedOut' };
    renderGuard('reviewer');
    expect(screen.getByText('page: /login')).toBeInTheDocument();
  });

  it('signs out a student and explains the dashboard is staff-only', async () => {
    mocks.state = { status: 'ready', access: person };
    renderGuard('reviewer');
    await waitFor(() => {
      expect(screen.getByText('page: /login?reason=staff-only')).toBeInTheDocument();
    });
    expect(mocks.signOut).toHaveBeenCalledOnce();
    expect(screen.queryByText('secret page')).not.toBeInTheDocument();
  });

  it('lets a reviewer into reviewer pages', () => {
    mocks.state = { status: 'ready', access: { ...person, isReviewer: true } };
    renderGuard('reviewer');
    expect(screen.getByText('secret page')).toBeInTheDocument();
  });

  it('keeps a reviewer out of admin pages without signing them out', () => {
    mocks.state = { status: 'ready', access: { ...person, isReviewer: true } };
    renderGuard('admin');
    expect(screen.getByText('This page is for administrators only.')).toBeInTheDocument();
    expect(screen.queryByText('secret page')).not.toBeInTheDocument();
    expect(mocks.signOut).not.toHaveBeenCalled();
  });

  it('lets an admin into admin pages', () => {
    mocks.state = { status: 'ready', access: { ...person, isAdmin: true } };
    renderGuard('admin');
    expect(screen.getByText('secret page')).toBeInTheDocument();
  });

  it('offers a retry when the access check fails', () => {
    mocks.state = { status: 'error', error: new Error('offline'), retry: vi.fn() };
    renderGuard('reviewer');
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument();
  });
});
