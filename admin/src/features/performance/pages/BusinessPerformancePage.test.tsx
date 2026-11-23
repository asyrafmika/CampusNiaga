import { focusManager } from '@tanstack/react-query';
import { act, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { AppError } from '../../../shared/lib/errors';
import { renderAt } from '../../../test/render';
import type { DateRange } from '../rules';
import type * as performanceService from '../services/performanceService';
import type { BusinessRow, PerformanceList } from '../services/performanceService';
import { BusinessPerformancePage } from './BusinessPerformancePage';

const mocks = vi.hoisted(() => ({
  listBusinessPerformance: vi.fn<(args: { range: DateRange; page: number }) => Promise<PerformanceList>>(),
}));

vi.mock('../services/performanceService', async (importOriginal) => {
  const actual = await importOriginal<typeof performanceService>();
  return { ...actual, ...mocks };
});

const row = (overrides: Partial<BusinessRow> = {}): BusinessRow => ({
  id: 'b1',
  name: 'Ali Bakes',
  ownerName: 'Ali',
  category: 'Food & Beverage',
  status: 'approved',
  totalOrders: 3,
  completedCount: 2,
  revenueSen: 125050,
  ...overrides,
});

const list = (rows: BusinessRow[], businesses = rows.length): PerformanceList => ({
  totals: { businesses, approvedBusinesses: 1, totalOrders: 17, completedCount: 11, revenueSen: 987650 },
  rows,
});

describe('BusinessPerformancePage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.listBusinessPerformance.mockResolvedValue(
      list([row(), row({ id: 'b2', name: 'Zed Prints', status: 'suspended', revenueSen: 0 })]),
    );
  });

  it('shows the totals and each business, suspended ones included', async () => {
    renderAt(<BusinessPerformancePage />);

    const tableRow = (await screen.findByText('Ali Bakes')).closest('tr');
    expect(tableRow).not.toBeNull();
    if (tableRow === null) return;
    expect(within(tableRow).getByText('RM 1,250.50')).toBeInTheDocument();
    expect(screen.getByText('RM 9,876.50')).toBeInTheDocument();
    expect(screen.getByText('17')).toBeInTheDocument();
    expect(screen.getByText('Suspended')).toBeInTheDocument();
  });

  it('labels the figures estimated and says what is private', async () => {
    renderAt(<BusinessPerformancePage />);
    expect(await screen.findByText(/Estimated \(self-reported\)/)).toBeInTheDocument();
    expect(screen.getByText(/Costs\s+and profit are private to the seller/)).toBeInTheDocument();
  });

  it('starts on the last 30 days and switches period', async () => {
    renderAt(<BusinessPerformancePage />);
    await screen.findByText('Ali Bakes');
    expect(mocks.listBusinessPerformance.mock.calls[0]?.[0].range.from).toBeDefined();

    await userEvent.click(screen.getByRole('tab', { name: 'All time' }));

    expect(mocks.listBusinessPerformance).toHaveBeenLastCalledWith({ range: {}, page: 0 });
  });

  it('opens a business on the same period', async () => {
    renderAt(<BusinessPerformancePage />, { path: '/performance', at: '/performance?period=all_time' });

    await userEvent.click(await screen.findByRole('link', { name: 'Open Ali Bakes' }));

    expect(screen.getByText('page: /performance/b1?period=all_time')).toBeInTheDocument();
  });

  it('pages through businesses', async () => {
    mocks.listBusinessPerformance.mockResolvedValue(list([row()], 25));
    renderAt(<BusinessPerformancePage />);
    await screen.findByText('Ali Bakes');

    await userEvent.click(screen.getByRole('button', { name: /next page/i }));

    expect(mocks.listBusinessPerformance.mock.lastCall?.[0].page).toBe(1);
  });

  it('asks once, since each view is audited', async () => {
    renderAt(<BusinessPerformancePage />);
    await screen.findByText('Ali Bakes');
    await act(async () => {
      focusManager.setFocused(false);
      focusManager.setFocused(true);
      await Promise.resolve();
    });
    focusManager.setFocused(undefined);
    expect(mocks.listBusinessPerformance).toHaveBeenCalledTimes(1);
  });

  it('says so when there are no businesses', async () => {
    mocks.listBusinessPerformance.mockResolvedValue(list([]));
    renderAt(<BusinessPerformancePage />);
    expect(await screen.findByText(/No student businesses yet/)).toBeInTheDocument();
  });

  it('shows a refusal with a retry', async () => {
    mocks.listBusinessPerformance.mockRejectedValue(new AppError('Administrator access required.', 'FORBIDDEN'));
    renderAt(<BusinessPerformancePage />);
    expect(await screen.findByText('Administrator access required.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Retry' })).toBeInTheDocument();
  });
});
