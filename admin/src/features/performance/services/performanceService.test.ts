import { describe, expect, it, vi } from 'vitest';

import { parseBusinessPerformance, parsePerformanceList } from './performanceService';

// Only the parsers are under test; nothing here talks to Supabase.
vi.mock('../../../shared/supabase/client', () => ({ supabase: {} }));

const row = {
  business_id: 'b1',
  business_name: 'Ali Bakes',
  owner_name: 'Ali',
  category: 'Food & Beverage',
  status: 'approved',
  total_orders: 3,
  completed_count: 2,
  estimated_revenue_sen: 5000,
};

const detail = {
  ...row,
  approved_at: '2026-11-01T00:00:00Z',
  orders_by_status: {
    pending_confirmation: 0,
    confirmed: 0,
    preparing: 0,
    ready_for_pickup: 0,
    completed: 2,
    cancelled: 1,
  },
  top_products: [{ listing_id: 'l1', title: 'Brownie box', units: 5, revenue_sen: 5000 }],
  stock: [{ listing_id: 'l1', title: 'Brownie box', status: 'available', stock: 4, hidden: false }],
  campaigns: [
    {
      campaign_id: 'c1',
      title: 'Raya',
      status: 'open',
      capacity: 10,
      allocated_qty: 4,
      remaining: 6,
      close_at: '2026-12-01T00:00:00Z',
    },
  ],
};

describe('parsePerformanceList', () => {
  const totals = {
    businesses: 1,
    approved_businesses: 1,
    total_orders: 3,
    completed_count: 2,
    estimated_revenue_sen: 5000,
  };

  it('reads the totals and the businesses', () => {
    const list = parsePerformanceList({ totals, rows: [row] });
    expect(list.totals.revenueSen).toBe(5000);
    expect(list.rows[0]?.name).toBe('Ali Bakes');
  });

  it('rejects an unknown status instead of guessing', () => {
    expect(() => parsePerformanceList({ totals, rows: [{ ...row, status: 'paused' }] })).toThrow(/paused/);
  });

  it('rejects money that is not whole sen', () => {
    expect(() => parsePerformanceList({ totals: { ...totals, estimated_revenue_sen: 50.5 }, rows: [] })).toThrow();
  });
});

describe('parseBusinessPerformance', () => {
  it('reads every section', () => {
    const business = parseBusinessPerformance(detail);
    expect(business.ordersByStatus.cancelled).toBe(1);
    expect(business.topProducts[0]?.units).toBe(5);
    expect(business.stock[0]?.stock).toBe(4);
    expect(business.campaigns[0]?.remaining).toBe(6);
  });

  it('never carries cost or profit through, even if sent', () => {
    const business = parseBusinessPerformance({ ...detail, recorded_cost_sen: 1700, estimated_profit_sen: 3300 });
    expect(JSON.stringify(business)).not.toMatch(/cost|profit/i);
  });

  it('rejects a missing status count', () => {
    expect(() => parseBusinessPerformance({ ...detail, orders_by_status: {} })).toThrow();
  });
});
