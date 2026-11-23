import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AppError } from '../../../shared/lib/errors';
import { renderAt } from '../../../test/render';
import type { DateRange } from '../rules';
import type * as performanceService from '../services/performanceService';
import type { BusinessPerformance } from '../services/performanceService';
import { BusinessPerformanceDetailPage } from './BusinessPerformanceDetailPage';

const mocks = vi.hoisted(() => ({
  getBusinessPerformance: vi.fn<(args: { id: string; range: DateRange }) => Promise<BusinessPerformance>>(),
}));

vi.mock('../services/performanceService', async (importOriginal) => {
  const actual = await importOriginal<typeof performanceService>();
  return { ...actual, ...mocks };
});

const business: BusinessPerformance = {
  id: 'b1',
  name: 'Ali Bakes',
  ownerName: 'Ali',
  category: 'Food & Beverage',
  status: 'approved',
  approvedAt: '2026-11-01T00:00:00Z',
  totalOrders: 9,
  completedCount: 7,
  revenueSen: 5000,
  ordersByStatus: {
    pending_confirmation: 0,
    confirmed: 0,
    preparing: 0,
    ready_for_pickup: 0,
    completed: 7,
    cancelled: 2,
  },
  topProducts: [{ id: 'l1', title: 'Brownie box', units: 5, revenueSen: 5000 }],
  stock: [{ id: 'l1', title: 'Brownie box', status: 'available', stock: 4, hidden: false }],
  campaigns: [{ id: 'c1', title: 'Raya', status: 'open', capacity: 10, remaining: 6, closeAt: '2026-12-01T00:00:00Z' }],
};

const open = (at = '/performance/b1') =>
  renderAt(<BusinessPerformanceDetailPage />, { path: '/performance/:businessId', at });

describe('BusinessPerformanceDetailPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.getBusinessPerformance.mockResolvedValue(business);
  });

  it('shows every section of the business', async () => {
    open();

    expect(await screen.findByRole('heading', { name: 'Ali Bakes' })).toBeInTheDocument();
    expect(within(screen.getByRole('table', { name: 'Orders by status' })).getByText('Cancelled')).toBeInTheDocument();
    expect(within(screen.getByRole('table', { name: 'Best-selling products' })).getByText('RM 50')).toBeInTheDocument();
    expect(within(screen.getByRole('table', { name: 'Stock now' })).getByText('4')).toBeInTheDocument();
    expect(within(screen.getByRole('table', { name: 'Pre-orders now' })).getByText('6 of 10')).toBeInTheDocument();
  });

  it('has no cost or profit figure', async () => {
    open();
    await screen.findByRole('heading', { name: 'Ali Bakes' });
    expect(screen.queryByText(/^(Recorded cost|Estimated profit)$/)).not.toBeInTheDocument();
    expect(screen.queryByRole('columnheader', { name: /cost|profit/i })).not.toBeInTheDocument();
  });

  it('keeps the period from the list, and switches it', async () => {
    open('/performance/b1?period=all_time');
    await screen.findByRole('heading', { name: 'Ali Bakes' });
    expect(mocks.getBusinessPerformance).toHaveBeenCalledWith({ id: 'b1', range: {} });

    await userEvent.click(screen.getByRole('tab', { name: 'This month' }));

    expect(mocks.getBusinessPerformance.mock.lastCall?.[0].range.to).toBeDefined();
  });

  it('says when nothing sold in the period', async () => {
    mocks.getBusinessPerformance.mockResolvedValue({ ...business, topProducts: [] });
    open();
    expect(await screen.findByText('No completed sales in this period.')).toBeInTheDocument();
  });

  it('shows a missing business with a retry', async () => {
    mocks.getBusinessPerformance.mockRejectedValue(new AppError('Business not found.', 'NOT_FOUND'));
    open();
    expect(await screen.findByText('Business not found.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Retry' })).toBeInTheDocument();
  });
});
