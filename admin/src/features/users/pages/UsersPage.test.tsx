import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AppError } from '../../../shared/lib/errors';
import { renderAt } from '../../../test/render';
import type { UserPage } from '../services/usersService';
import { UsersPage } from './UsersPage';

const mocks = vi.hoisted(() => ({
  listUsers: vi.fn<() => Promise<UserPage>>(),
  setAdminRole: vi.fn<(userId: string, enabled: boolean) => Promise<void>>(),
  setAccountStatus: vi.fn<(userId: string, status: string, note: string) => Promise<void>>(),
}));

vi.mock('../services/usersService', () => ({
  listUsers: mocks.listUsers,
  setAdminRole: mocks.setAdminRole,
}));
vi.mock('../../moderation/services/moderationService', () => ({
  setAccountStatus: mocks.setAccountStatus,
}));
vi.mock('../../auth', () => ({
  useAccess: () => ({
    status: 'ready',
    access: { userId: 'me', email: 'me@student.usm.my', isAdmin: true },
  }),
}));

const page: UserPage = {
  total: 2,
  rows: [
    {
      id: 'me',
      name: 'Asyraf',
      email: 'me@student.usm.my',
      accountStatus: 'active',
      createdAt: '2026-11-15T01:00:00Z',
      isAdmin: true,
    },
    {
      id: 'ali',
      name: 'Ali',
      email: 'ali@student.usm.my',
      accountStatus: 'active',
      createdAt: '2026-11-15T02:00:00Z',
      isAdmin: false,
    },
  ],
};

describe('UsersPage', () => {
  beforeEach(() => {
    mocks.listUsers.mockResolvedValue(page);
    mocks.setAdminRole.mockReset();
  });

  it('lists accounts with the one staff role, HDC administrator', async () => {
    renderAt(<UsersPage />);

    const ali = (await screen.findByText('ali@student.usm.my')).closest('tr');
    expect(ali).not.toBeNull();
    if (ali === null) return;
    expect(within(ali).getByRole('switch', { name: 'Administrator role for ali@student.usm.my' })).not.toBeChecked();
    expect(within(ali).getAllByRole('switch')).toHaveLength(1);
    expect(screen.queryByText('Reviewer')).toBeNull();
  });

  it('grants the administrator role through set_staff_role and confirms it', async () => {
    mocks.setAdminRole.mockResolvedValue();
    renderAt(<UsersPage />);

    await userEvent.click(await screen.findByRole('switch', { name: 'Administrator role for ali@student.usm.my' }));

    expect(mocks.setAdminRole).toHaveBeenCalledWith('ali', true);
    expect(await screen.findByText('ali@student.usm.my is now an HDC administrator.')).toBeInTheDocument();
  });

  it('does not let an admin remove their own admin role', async () => {
    renderAt(<UsersPage />);
    expect(await screen.findByRole('switch', { name: 'Administrator role for me@student.usm.my' })).toBeDisabled();
  });

  it('shows the reason a change was refused', async () => {
    mocks.setAdminRole.mockRejectedValue(new AppError('Administrator access required.', 'FORBIDDEN'));
    renderAt(<UsersPage />);

    await userEvent.click(await screen.findByRole('switch', { name: 'Administrator role for ali@student.usm.my' }));

    expect(await screen.findByText('Administrator access required.')).toBeInTheDocument();
  });

  it('suspends an account after confirmation, with a note', async () => {
    mocks.setAccountStatus.mockResolvedValue();
    renderAt(<UsersPage />);

    await userEvent.click(await screen.findByRole('button', { name: 'Suspend ali@student.usm.my' }));
    await userEvent.type(screen.getByLabelText('Note (optional)'), 'Repeated scams');
    await userEvent.click(screen.getByRole('button', { name: 'Suspend' }));

    expect(mocks.setAccountStatus).toHaveBeenCalledWith('ali', 'suspended', 'Repeated scams');
    expect(await screen.findByText('ali@student.usm.my is suspended.')).toBeInTheDocument();
  });

  it('offers no suspend button on the admin’s own account', async () => {
    renderAt(<UsersPage />);
    await screen.findByText('ali@student.usm.my');
    expect(screen.queryByRole('button', { name: 'Suspend me@student.usm.my' })).toBeNull();
  });
});
