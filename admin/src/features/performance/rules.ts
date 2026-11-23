/**
 * Business performance (ADR 0007): the periods, the same as the mobile
 * dashboard's, and the labels. The database computes every figure.
 */

export const PERIODS = ['last_7_days', 'last_30_days', 'this_month', 'all_time'] as const;

export type Period = (typeof PERIODS)[number];

export const PERIOD_LABELS: Record<Period, string> = {
  last_7_days: 'Last 7 days',
  last_30_days: 'Last 30 days',
  this_month: 'This month',
  all_time: 'All time',
};

export const DEFAULT_PERIOD: Period = 'last_30_days';

export function isPeriod(value: string | null): value is Period {
  return value !== null && (PERIODS as readonly string[]).includes(value);
}

/** `from` inclusive, `to` exclusive, in the admin's own time zone; absent means unbounded. */
export type DateRange = { from?: string; to?: string };

export function rangeFor(period: Period, now: Date): DateRange {
  const year = now.getFullYear();
  const month = now.getMonth();
  const day = now.getDate();
  switch (period) {
    case 'last_7_days':
      return { from: new Date(year, month, day - 6).toISOString() };
    case 'last_30_days':
      return { from: new Date(year, month, day - 29).toISOString() };
    case 'this_month':
      return { from: new Date(year, month, 1).toISOString(), to: new Date(year, month + 1, 1).toISOString() };
    case 'all_time':
      return {};
  }
}

export const BUSINESS_STATUSES = ['approved', 'suspended'] as const;

export type PerformanceBusinessStatus = (typeof BUSINESS_STATUSES)[number];

export const BUSINESS_STATUS_LABELS: Record<PerformanceBusinessStatus, string> = {
  approved: 'Approved',
  suspended: 'Suspended',
};

export const ORDER_STATUSES = [
  'pending_confirmation',
  'confirmed',
  'preparing',
  'ready_for_pickup',
  'completed',
  'cancelled',
] as const;

export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const ORDER_STATUS_LABELS: Record<OrderStatus, string> = {
  pending_confirmation: 'Pending confirmation',
  confirmed: 'Confirmed',
  preparing: 'Preparing',
  ready_for_pickup: 'Ready for pickup',
  completed: 'Completed',
  cancelled: 'Cancelled',
};
