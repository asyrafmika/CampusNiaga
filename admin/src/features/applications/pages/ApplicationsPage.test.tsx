import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderAt } from '../../../test/render';
import type { QueueFilter } from '../rules';
import type * as applicationsService from '../services/applicationsService';
import type { ApplicationPage, ApplicationRow, StatusCount } from '../services/applicationsService';
import { ApplicationsPage } from './ApplicationsPage';

const mocks = vi.hoisted(() => ({
  listApplications: vi.fn<(args: { filter: QueueFilter; page: number }) => Promise<ApplicationPage>>(),
  fetchStatusSummary: vi.fn<() => Promise<StatusCount[]>>(),
}));

vi.mock('../services/applicationsService', async (importOriginal) => {
  const actual = await importOriginal<typeof applicationsService>();
  return { ...actual, ...mocks };
});

const row = (overrides: Partial<ApplicationRow> = {}): ApplicationRow => ({
  id: 'a1',
  businessName: 'Ali Bakes',
  category: 'Food & Beverage',
  status: 'submitted',
  submittedAt: '2026-11-16T03:00:00Z',
  applicant: { name: 'Ali', email: 'ali@student.usm.my' },
  ...overrides,
});

describe('ApplicationsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.fetchStatusSummary.mockResolvedValue([
      { status: 'submitted', total: 2 },
      { status: 'under_review', total: 1 },
      { status: 'info_requested', total: 4 },
      { status: 'approved', total: 5 },
      { status: 'rejected', total: 0 },
    ]);
    mocks.listApplications.mockImplementation(({ filter }) =>
      Promise.resolve(
        filter === 'needs_review'
          ? { total: 1, rows: [row()] }
          : { total: 1, rows: [row({ id: 'a2', businessName: 'Siti Prints', status: 'approved' })] },
      ),
    );
  });

  it('shows the queue of applications needing review, with the applicant', async () => {
    renderAt(<ApplicationsPage />);

    const tableRow = (await screen.findByText('Ali Bakes')).closest('tr');
    expect(tableRow).not.toBeNull();
    if (tableRow === null) return;
    expect(within(tableRow).getByText('ali@student.usm.my')).toBeInTheDocument();
    expect(within(tableRow).getByText('Submitted')).toBeInTheDocument();
    expect(mocks.listApplications).toHaveBeenCalledWith({ filter: 'needs_review', page: 0 });
  });

  it('shows the status summary counted by the database', async () => {
    renderAt(<ApplicationsPage />);

    // Needs review = submitted + under review.
    expect(await screen.findByText('3')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
    expect(screen.getByText('5')).toBeInTheDocument();
    expect(screen.getByText('0')).toBeInTheDocument();
  });

  it('switches status with the tabs', async () => {
    renderAt(<ApplicationsPage />);
    await screen.findByText('Ali Bakes');

    await userEvent.click(screen.getByRole('tab', { name: 'Approved' }));

    expect(await screen.findByText('Siti Prints')).toBeInTheDocument();
    expect(mocks.listApplications).toHaveBeenLastCalledWith({ filter: 'approved', page: 0 });
  });

  it('opens an application', async () => {
    renderAt(<ApplicationsPage />, { path: '/applications' });

    await userEvent.click(await screen.findByText('Ali Bakes'));

    expect(screen.getByText('page: /applications/a1')).toBeInTheDocument();
  });

  it('shows the prototype disclaimer', async () => {
    renderAt(<ApplicationsPage />);
    expect(await screen.findByText(/not an official USM\/HDC decision/)).toBeInTheDocument();
  });

  it('says so when nothing is waiting', async () => {
    mocks.listApplications.mockResolvedValue({ total: 0, rows: [] });
    renderAt(<ApplicationsPage />);
    expect(await screen.findByText('Nothing waiting for review. All caught up!')).toBeInTheDocument();
  });
});
