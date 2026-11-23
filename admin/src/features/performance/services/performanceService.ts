import { toAppError } from '../../../shared/lib/errors';
import { PAGE_SIZE } from '../../../shared/lib/format';
import { supabase } from '../../../shared/supabase/client';
import {
  BUSINESS_STATUSES,
  ORDER_STATUSES,
  type DateRange,
  type OrderStatus,
  type PerformanceBusinessStatus,
} from '../rules';

export type BusinessRow = {
  id: string;
  name: string;
  ownerName: string;
  category: string;
  status: PerformanceBusinessStatus;
  totalOrders: number;
  completedCount: number;
  revenueSen: number;
};

export type PerformanceTotals = {
  businesses: number;
  approvedBusinesses: number;
  totalOrders: number;
  completedCount: number;
  revenueSen: number;
};

export type PerformanceList = { totals: PerformanceTotals; rows: BusinessRow[] };

export type BusinessPerformance = BusinessRow & {
  approvedAt: string;
  ordersByStatus: Record<OrderStatus, number>;
  topProducts: { id: string; title: string; units: number; revenueSen: number }[];
  stock: { id: string; title: string; status: string; stock: number; hidden: boolean }[];
  campaigns: { id: string; title: string; status: string; capacity: number; remaining: number; closeAt: string }[];
};

type Json = Record<string, unknown>;

function objectOf(value: unknown): Json {
  if (typeof value === 'object' && value !== null && !Array.isArray(value)) return value as Json;
  throw new Error('Unexpected performance data');
}

function listOf(value: unknown): Json[] {
  if (Array.isArray(value)) return value.map(objectOf);
  throw new Error('Unexpected performance list');
}

function text(json: Json, key: string): string {
  const value = json[key];
  if (typeof value === 'string') return value;
  throw new Error(`Expected text in ${key}`);
}

function whole(json: Json, key: string): number {
  const value = json[key];
  if (typeof value === 'number' && Number.isSafeInteger(value)) return value;
  throw new Error(`Expected a whole number in ${key}`);
}

function flag(json: Json, key: string): boolean {
  const value = json[key];
  if (typeof value === 'boolean') return value;
  throw new Error(`Expected true or false in ${key}`);
}

function statusOf(value: string): PerformanceBusinessStatus {
  const status = BUSINESS_STATUSES.find((s) => s === value);
  if (status !== undefined) return status;
  throw new Error(`Unknown business status: ${value}`);
}

function businessOf(json: Json): BusinessRow {
  return {
    id: text(json, 'business_id'),
    name: text(json, 'business_name'),
    ownerName: text(json, 'owner_name'),
    category: text(json, 'category'),
    status: statusOf(text(json, 'status')),
    totalOrders: whole(json, 'total_orders'),
    completedCount: whole(json, 'completed_count'),
    revenueSen: whole(json, 'estimated_revenue_sen'),
  };
}

/** Parses `admin_business_performance_list()`; throws if it isn't the promised shape. */
export function parsePerformanceList(value: unknown): PerformanceList {
  const json = objectOf(value);
  const totals = objectOf(json['totals']);
  return {
    totals: {
      businesses: whole(totals, 'businesses'),
      approvedBusinesses: whole(totals, 'approved_businesses'),
      totalOrders: whole(totals, 'total_orders'),
      completedCount: whole(totals, 'completed_count'),
      revenueSen: whole(totals, 'estimated_revenue_sen'),
    },
    rows: listOf(json['rows']).map(businessOf),
  };
}

/** Parses `admin_business_performance()`. Cost and profit are not part of it. */
export function parseBusinessPerformance(value: unknown): BusinessPerformance {
  const json = objectOf(value);
  const byStatus = objectOf(json['orders_by_status']);
  return {
    ...businessOf(json),
    approvedAt: text(json, 'approved_at'),
    ordersByStatus: Object.fromEntries(ORDER_STATUSES.map((s) => [s, whole(byStatus, s)])) as Record<
      OrderStatus,
      number
    >,
    topProducts: listOf(json['top_products']).map((p) => ({
      id: text(p, 'listing_id'),
      title: text(p, 'title'),
      units: whole(p, 'units'),
      revenueSen: whole(p, 'revenue_sen'),
    })),
    stock: listOf(json['stock']).map((s) => ({
      id: text(s, 'listing_id'),
      title: text(s, 'title'),
      status: text(s, 'status'),
      stock: whole(s, 'stock'),
      hidden: flag(s, 'hidden'),
    })),
    campaigns: listOf(json['campaigns']).map((c) => ({
      id: text(c, 'campaign_id'),
      title: text(c, 'title'),
      status: text(c, 'status'),
      capacity: whole(c, 'capacity'),
      remaining: whole(c, 'remaining'),
      closeAt: text(c, 'close_at'),
    })),
  };
}

const rangeArgs = ({ from, to }: DateRange) => ({
  ...(from === undefined ? {} : { from_at: from }),
  ...(to === undefined ? {} : { to_at: to }),
});

/** Every business with headline figures (`admin_business_performance_list`, audited). Admins only. */
export async function listBusinessPerformance({
  range,
  page,
}: {
  range: DateRange;
  page: number;
}): Promise<PerformanceList> {
  const { data, error } = await supabase.rpc('admin_business_performance_list', {
    ...rangeArgs(range),
    page_size: PAGE_SIZE,
    page_offset: page * PAGE_SIZE,
  });
  if (error) throw toAppError(error);
  return parsePerformanceList(data);
}

/** One business (`admin_business_performance`, audited). Admins only. */
export async function getBusinessPerformance({
  id,
  range,
}: {
  id: string;
  range: DateRange;
}): Promise<BusinessPerformance> {
  const { data, error } = await supabase.rpc('admin_business_performance', { business_id: id, ...rangeArgs(range) });
  if (error) throw toAppError(error);
  return parseBusinessPerformance(data);
}
