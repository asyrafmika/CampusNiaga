import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AppError } from '../../../shared/lib/errors';
import { renderAt } from '../../../test/render';
import type * as moderationService from '../services/moderationService';
import type { ReportFilter, ReportPage, ReportRow } from '../services/moderationService';
import { ModerationPage } from './ModerationPage';

const mocks = vi.hoisted(() => ({
  listReports: vi.fn<(args: { filter: ReportFilter; page: number }) => Promise<ReportPage>>(),
  moderateListing: vi.fn<(listingId: string, hide: boolean, note: string) => Promise<void>>(),
  dismissReport: vi.fn<(reportId: string, note: string) => Promise<void>>(),
  setAccountStatus: vi.fn<(userId: string, status: string, note: string) => Promise<void>>(),
}));

vi.mock('../services/moderationService', async (importOriginal) => {
  const actual = await importOriginal<typeof moderationService>();
  return { ...actual, ...mocks };
});

const report = (overrides: Partial<ReportRow> = {}): ReportRow => ({
  id: 'rep1',
  reason: 'scam',
  details: 'Price too good to be true',
  status: 'open',
  action: null,
  reviewNote: null,
  createdAt: '2026-11-16T03:00:00Z',
  listing: { id: 'l1', title: 'Brand new iPhone RM50', hidden: false, status: 'available' },
  reporter: { name: 'Siti', email: 'siti@student.usm.my' },
  seller: { id: 'ali', name: 'Ali', email: 'ali@student.usm.my', accountStatus: 'active' },
  ...overrides,
});

describe('ModerationPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.listReports.mockImplementation(({ filter }) =>
      Promise.resolve(
        filter === 'open'
          ? { total: 1, rows: [report()] }
          : {
              total: 1,
              rows: [report({ id: 'rep2', status: 'reviewed', action: 'dismissed', reviewNote: 'Not a problem' })],
            },
      ),
    );
  });

  it('lists open reports with the reason, reporter and seller', async () => {
    renderAt(<ModerationPage />);

    const row = (await screen.findByText('Brand new iPhone RM50')).closest('tr');
    expect(row).not.toBeNull();
    if (row === null) return;
    expect(within(row).getByText('Scam or fraud')).toBeInTheDocument();
    expect(within(row).getByText('Price too good to be true')).toBeInTheDocument();
    expect(within(row).getByText('siti@student.usm.my')).toBeInTheDocument();
    expect(within(row).getByText('ali@student.usm.my')).toBeInTheDocument();
    expect(mocks.listReports).toHaveBeenCalledWith({ filter: 'open', page: 0 });
  });

  it('hides a listing after confirmation, with a note', async () => {
    mocks.moderateListing.mockResolvedValue();
    renderAt(<ModerationPage />);

    await userEvent.click(await screen.findByRole('button', { name: 'Hide listing' }));
    expect(screen.getByText('Hide listing?')).toBeInTheDocument();
    await userEvent.type(screen.getByLabelText('Note (optional)'), 'Likely scam');
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Hide listing' }));

    expect(mocks.moderateListing).toHaveBeenCalledWith('l1', true, 'Likely scam');
    expect(await screen.findByText('Listing hidden. Its open reports are closed.')).toBeInTheDocument();
  });

  it('cancelling the dialog does nothing', async () => {
    renderAt(<ModerationPage />);

    await userEvent.click(await screen.findByRole('button', { name: 'Suspend seller' }));
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(mocks.setAccountStatus).not.toHaveBeenCalled();
  });

  it('suspends the seller', async () => {
    mocks.setAccountStatus.mockResolvedValue();
    renderAt(<ModerationPage />);

    await userEvent.click(await screen.findByRole('button', { name: 'Suspend seller' }));
    await userEvent.click(screen.getByRole('button', { name: 'Suspend' }));

    expect(mocks.setAccountStatus).toHaveBeenCalledWith('ali', 'suspended', '');
    expect(await screen.findByText('ali@student.usm.my is suspended.')).toBeInTheDocument();
  });

  it('dismisses a report and shows why one was refused', async () => {
    mocks.dismissReport.mockRejectedValue(new AppError('This report is already closed.', 'INVALID_TRANSITION'));
    renderAt(<ModerationPage />);

    await userEvent.click(await screen.findByRole('button', { name: 'Dismiss' }));
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Dismiss' }));

    expect(mocks.dismissReport).toHaveBeenCalledWith('rep1', '');
    expect(await screen.findByText('This report is already closed.')).toBeInTheDocument();
  });

  it('shows closed reports with their outcome', async () => {
    renderAt(<ModerationPage />);

    await userEvent.click(await screen.findByRole('tab', { name: 'Closed' }));

    expect(await screen.findByText('Dismissed')).toBeInTheDocument();
    expect(screen.getByText('Not a problem')).toBeInTheDocument();
    expect(mocks.listReports).toHaveBeenLastCalledWith({ filter: 'closed', page: 0 });
  });

  it('says when there is nothing to review', async () => {
    mocks.listReports.mockResolvedValue({ total: 0, rows: [] });
    renderAt(<ModerationPage />);

    expect(await screen.findByText('No open reports. All clear!')).toBeInTheDocument();
  });
});
