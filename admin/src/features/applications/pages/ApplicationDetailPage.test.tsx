import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AppError } from '../../../shared/lib/errors';
import { renderAt } from '../../../test/render';
import type { BusinessStatus, ReviewAction } from '../rules';
import type * as applicationsService from '../services/applicationsService';
import type { ApplicationDetail } from '../services/applicationsService';
import { ApplicationDetailPage } from './ApplicationDetailPage';

const mocks = vi.hoisted(() => ({
  getApplication: vi.fn<(id: string) => Promise<ApplicationDetail>>(),
  reviewApplication: vi.fn<(id: string, action: ReviewAction, note: string) => Promise<void>>(),
  setBusinessStatus: vi.fn<(id: string, status: BusinessStatus, note: string) => Promise<void>>(),
  documentUrl: vi.fn<(path: string) => Promise<string>>(),
  access: { userId: 'rina', email: 'rina@campusniaga.test', isReviewer: true, isAdmin: false },
}));

vi.mock('../services/applicationsService', async (importOriginal) => {
  const actual = await importOriginal<typeof applicationsService>();
  return {
    ...actual,
    getApplication: mocks.getApplication,
    reviewApplication: mocks.reviewApplication,
    setBusinessStatus: mocks.setBusinessStatus,
    documentUrl: mocks.documentUrl,
  };
});

vi.mock('../../auth', () => ({
  useAccess: () => ({ status: 'ready', access: mocks.access }),
}));

const detail = (overrides: Partial<ApplicationDetail> = {}): ApplicationDetail => ({
  id: 'a1',
  applicantId: 'ali',
  businessName: 'Ali Bakes',
  category: 'Food & Beverage',
  status: 'under_review',
  submittedAt: '2026-11-16T03:00:00Z',
  applicant: { name: 'Ali', email: 'ali@student.usm.my' },
  description: 'Homemade brownies and cookies.',
  contactDetails: '012-3456789',
  collectionDetails: 'Desasiswa Tekun lobby',
  documentPaths: ['ali/a1/1731744000000_menu.pdf'],
  remarks: null,
  decidedAt: null,
  history: [
    { id: 1, from: 'draft', to: 'submitted', actorRole: 'applicant', note: null, createdAt: '2026-11-16T03:00:00Z' },
    { id: 2, from: 'submitted', to: 'under_review', actorRole: 'reviewer', note: null, createdAt: '2026-11-16T04:00:00Z' },
  ],
  business: null,
  ...overrides,
});

const renderDetail = () => renderAt(<ApplicationDetailPage />, { path: '/applications/:applicationId', at: '/applications/a1' });

describe('ApplicationDetailPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.access = { userId: 'rina', email: 'rina@campusniaga.test', isReviewer: true, isAdmin: false };
    mocks.getApplication.mockResolvedValue(detail());
    mocks.reviewApplication.mockResolvedValue();
    mocks.setBusinessStatus.mockResolvedValue();
  });

  it('shows the details, documents, history and the disclaimer', async () => {
    renderDetail();

    expect(await screen.findByRole('heading', { name: 'Ali Bakes' })).toBeInTheDocument();
    expect(mocks.getApplication).toHaveBeenCalledWith('a1');
    expect(screen.getByText('Homemade brownies and cookies.')).toBeInTheDocument();
    expect(screen.getByText('menu.pdf')).toBeInTheDocument();
    expect(screen.getByText('Submitted → Under review')).toBeInTheDocument();
    expect(screen.getByText(/not an official USM\/HDC decision/)).toBeInTheDocument();
  });

  it('offers only the decisions allowed while under review', async () => {
    renderDetail();
    await screen.findByRole('heading', { name: 'Ali Bakes' });

    expect(screen.getByRole('button', { name: 'Approve' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Request changes' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Reject' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Start review' })).not.toBeInTheDocument();
  });

  it('a submitted application can only be picked up', async () => {
    mocks.getApplication.mockResolvedValue(detail({ status: 'submitted' }));
    renderDetail();
    await userEvent.click(await screen.findByRole('button', { name: 'Start review' }));
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Start review' }));

    expect(mocks.reviewApplication).toHaveBeenCalledWith('a1', 'start_review', '');
    expect(screen.queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument();
  });

  it('requesting changes needs a note, which is sent to the database', async () => {
    renderDetail();
    await userEvent.click(await screen.findByRole('button', { name: 'Request changes' }));

    const dialog = screen.getByRole('dialog');
    const send = within(dialog).getByRole('button', { name: 'Request changes' });
    expect(send).toBeDisabled();
    await userEvent.type(within(dialog).getByLabelText(/Note/), 'Add your price list.');
    expect(send).toBeEnabled();
    await userEvent.click(send);

    expect(mocks.reviewApplication).toHaveBeenCalledWith('a1', 'request_info', 'Add your price list.');
    expect(await screen.findByText('Application changes requested.')).toBeInTheDocument();
  });

  it('rejecting needs a note too', async () => {
    renderDetail();
    await userEvent.click(await screen.findByRole('button', { name: 'Reject' }));
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByRole('button', { name: 'Reject' })).toBeDisabled();
  });

  it('approving is confirmed, shows the disclaimer, and calls the database', async () => {
    renderDetail();
    await userEvent.click(await screen.findByRole('button', { name: 'Approve' }));

    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText(/Approval is final/)).toBeInTheDocument();
    expect(within(dialog).getByText(/not an official USM\/HDC decision/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Approve' }));

    expect(mocks.reviewApplication).toHaveBeenCalledWith('a1', 'approve', '');
  });

  it('shows the database’s reason when a decision is refused', async () => {
    mocks.reviewApplication.mockRejectedValue(
      new AppError('This application is approved, so it can’t be moved to rejected.', 'INVALID_TRANSITION'),
    );
    renderDetail();
    await userEvent.click(await screen.findByRole('button', { name: 'Approve' }));
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Approve' }));

    expect(await screen.findByText('This application is approved, so it can’t be moved to rejected.')).toBeInTheDocument();
  });

  it('a reviewer cannot decide their own application', async () => {
    mocks.access = { ...mocks.access, userId: 'ali' };
    renderDetail();

    expect(await screen.findByText(/This is your own application/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument();
  });

  it('a decided application shows no decisions and the reviewer’s note', async () => {
    mocks.getApplication.mockResolvedValue(
      detail({ status: 'rejected', remarks: 'Needs a supplier agreement.', decidedAt: '2026-11-17T03:00:00Z' }),
    );
    renderDetail();

    expect(await screen.findByText(/Needs a supplier agreement\./)).toBeInTheDocument();
    expect(screen.getByText(/^Rejected /)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument();
  });

  it('opens a document through a short-lived link fetched on click', async () => {
    mocks.documentUrl.mockResolvedValue('https://signed.example/menu.pdf');
    const open = vi.spyOn(window, 'open').mockReturnValue(null);
    renderDetail();
    await userEvent.click(await screen.findByRole('button', { name: 'Open' }));

    expect(mocks.documentUrl).toHaveBeenCalledWith('ali/a1/1731744000000_menu.pdf');
    expect(open).toHaveBeenCalledWith('https://signed.example/menu.pdf', '_blank', 'noopener');
    open.mockRestore();
  });

  it('admins can suspend an approved business; reviewers cannot', async () => {
    const approved = detail({
      status: 'approved',
      decidedAt: '2026-11-17T03:00:00Z',
      business: { id: 'b1', name: 'Ali Bakes', status: 'approved' },
    });
    mocks.getApplication.mockResolvedValue(approved);
    const { unmount } = renderDetail();
    expect(await screen.findByText('Active')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Suspend business' })).not.toBeInTheDocument();
    unmount();

    mocks.access = { ...mocks.access, isAdmin: true };
    renderDetail();
    await userEvent.click(await screen.findByRole('button', { name: 'Suspend business' }));
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Suspend' }));

    expect(mocks.setBusinessStatus).toHaveBeenCalledWith('b1', 'suspended', '');
  });
});
