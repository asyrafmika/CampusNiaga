import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AppError } from '../../../shared/lib/errors';
import { renderAt } from '../../../test/render';
import type { UserPage } from '../services/usersService';
import { UsersPage } from './UsersPage';

const mocks = vi.hoisted(() => ({
  listUsers: vi.fn<() => Promise<UserPage>>(),
  setStaffRole: vi.fn<(userId: string, role: string, enabled: boolean) => Promise<void>>(),
  setAccountStatus: vi.fn<(userId: string, status: string, note: string) => Promise<void>>(),
}));

vi.mock('../services/usersService', () => ({
  listUsers: mocks.listUsers,
  setStaffRole: mocks.setStaffRole,
}));
vi.mock('../../moderation/services/moderationService', () => ({
  setAccountStatus: mocks.setAccountStatus,
}));
vi.mock('../../auth', () => ({
  useAccess: () => ({
    status: 'ready',
    access: { userId: 'me', email: 'me@student.usm.my', isReviewer: false, isAdmin: true },
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
      isReviewer: false,
      isAdmin: true,
    },
    {
      id: 'ali',
      name: 'Ali',
      email: 'ali@student.usm.my',
      accountStatus: 'active',
      createdAt: '2026-11-15T02:00:00Z',
      isReviewer: false,
      isAdmin: false,
    },
  ],
};

describe('UsersPage', () => {
  beforeEach(() => {
    mocks.listUsers.mockResolvedValue(page);
    mocks.setStaffRole.mockReset();
  });

  it('lists accounts with their roles', async () => {
    renderAt(<UsersPage />);

    const ali = (await screen.findByText('ali@student.usm.my')).closest('tr');
    expect(ali).not.toBeNull();
    if (ali === null) return;
    expect(within(ali).getByRole('switch', { name: 'Reviewer role for ali@student.usm.my' })).not.toBeChecked();
  });

  it('grants a role through set_staff_role and confirms it', async () => {
    mocks.setStaffRole.mockResolvedValue();
    renderAt(<UsersPage />);

    await userEvent.click(await screen.findByRole('switch', { name: 'Reviewer role for ali@student.usm.my' }));

    expect(mocks.setStaffRole).toHaveBeenCalledWith('ali', 'reviewer', true);
    expect(await screen.findByText('ali@student.usm.my is now a reviewer.')).toBeInTheDocument();
  });

  it('does not let an admin remove their own admin role', async () => {
    renderAt(<UsersPage />);
    expect(await screen.findByRole('switch', { name: 'Admin role for me@student.usm.my' })).toBeDisabled();
  });

  it('shows the reason a change was refused', async () => {
    mocks.setStaffRole.mockRejectedValue(new AppError('Administrator access required.', 'FORBIDDEN'));
    renderAt(<UsersPage />);

    await userEvent.click(await screen.findByRole('switch', { name: 'Admin role for ali@student.usm.my' }));

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
