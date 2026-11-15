import { toAppError } from '../../../shared/lib/errors';
import { PAGE_SIZE } from '../../../shared/lib/format';
import { supabase } from '../../../shared/supabase/client';

export const REPORT_REASONS = {
  prohibited_item: 'Prohibited item',
  scam: 'Scam or fraud',
  offensive: 'Offensive content',
  misleading: 'Misleading or wrong details',
  other: 'Something else',
} as const;

export type ReportReason = keyof typeof REPORT_REASONS;
export type ReportStatus = 'open' | 'reviewed' | 'actioned';
export type ReportFilter = 'open' | 'closed';

export type ReportRow = {
  id: string;
  reason: ReportReason;
  details: string;
  status: ReportStatus;
  action: string | null;
  reviewNote: string | null;
  createdAt: string;
  listing: { id: string; title: string; hidden: boolean; status: string } | null;
  reporter: { name: string; email: string } | null;
  seller: { id: string; name: string; email: string; accountStatus: string } | null;
};

export type ReportPage = { rows: ReportRow[]; total: number };

function reasonOf(value: string): ReportReason {
  if (value in REPORT_REASONS) return value as ReportReason;
  throw new Error(`Unknown report reason: ${value}`);
}

function statusOf(value: string): ReportStatus {
  if (value === 'open' || value === 'reviewed' || value === 'actioned') return value;
  throw new Error(`Unknown report status: ${value}`);
}

/**
 * One page of reports with the listing, the reporter and the seller. Open
 * reports oldest first (a queue); closed ones newest first. Admins only (RLS).
 */
export async function listReports({ filter, page }: { filter: ReportFilter; page: number }): Promise<ReportPage> {
  let query = supabase
    .from('reports')
    .select(
      'id, reason, details, status, action, review_note, created_at, ' +
        'listing:listings!reports_listing_id_fkey(id, title, hidden, status), ' +
        'reporter:profiles!reports_reporter_id_fkey(name, email), ' +
        'seller:profiles!reports_reported_user_id_fkey(id, name, email, account_status)',
      { count: 'exact' },
    )
    .range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1);
  query =
    filter === 'open'
      ? query.eq('status', 'open').order('created_at', { ascending: true })
      : query.neq('status', 'open').order('created_at', { ascending: false });

  const { data, error, count } = await query.overrideTypes<
    {
      id: string;
      reason: string;
      details: string;
      status: string;
      action: string | null;
      review_note: string | null;
      created_at: string;
      listing: { id: string; title: string; hidden: boolean; status: string } | null;
      reporter: { name: string; email: string } | null;
      seller: { id: string; name: string; email: string; account_status: string } | null;
    }[],
    { merge: false }
  >();
  if (error) throw toAppError(error);

  return {
    total: count ?? data.length,
    rows: data.map((r) => ({
      id: r.id,
      reason: reasonOf(r.reason),
      details: r.details,
      status: statusOf(r.status),
      action: r.action,
      reviewNote: r.review_note,
      createdAt: r.created_at,
      listing: r.listing,
      reporter: r.reporter,
      seller:
        r.seller === null
          ? null
          : { id: r.seller.id, name: r.seller.name, email: r.seller.email, accountStatus: r.seller.account_status },
    })),
  };
}

const noteArg = (note: string) => (note.trim().length > 0 ? { note: note.trim() } : {});

/** Hides or restores a listing (`moderate_listing`, audited). */
export async function moderateListing(listingId: string, hide: boolean, note: string): Promise<void> {
  const { error } = await supabase.rpc('moderate_listing', { listing_id: listingId, hide, ...noteArg(note) });
  if (error) throw toAppError(error);
}

/** Closes a report without action (`dismiss_report`, audited). */
export async function dismissReport(reportId: string, note: string): Promise<void> {
  const { error } = await supabase.rpc('dismiss_report', { report_id: reportId, ...noteArg(note) });
  if (error) throw toAppError(error);
}

/** Suspends or reactivates an account (`set_account_status`, audited). */
export async function setAccountStatus(
  userId: string,
  accountStatus: 'active' | 'suspended',
  note: string,
): Promise<void> {
  const { error } = await supabase.rpc('set_account_status', {
    user_id: userId,
    account_status: accountStatus,
    ...noteArg(note),
  });
  if (error) throw toAppError(error);
}
