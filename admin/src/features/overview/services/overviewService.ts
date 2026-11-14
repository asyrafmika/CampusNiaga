import { toAppError } from '../../../shared/lib/errors';
import { supabase } from '../../../shared/supabase/client';

export type OverviewStats = {
  accounts: number;
  reviewers: number;
  admins: number;
  auditEventsThisWeek: number;
};

async function count(
  query: PromiseLike<{ count: number | null; error: { message: string; details?: string | null; code?: string } | null }>,
): Promise<number> {
  const { count: total, error } = await query;
  if (error) throw toAppError(error);
  return total ?? 0;
}

/** Counts for the admin overview tiles, without downloading rows (`head: true`). */
export async function fetchOverviewStats(now: Date = new Date()): Promise<OverviewStats> {
  const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const [accounts, reviewers, admins, auditEventsThisWeek] = await Promise.all([
    count(supabase.from('profiles').select('id', { count: 'exact', head: true })),
    count(supabase.from('staff_roles').select('user_id', { count: 'exact', head: true }).eq('role', 'reviewer')),
    count(supabase.from('staff_roles').select('user_id', { count: 'exact', head: true }).eq('role', 'admin')),
    count(supabase.from('audit_logs').select('id', { count: 'exact', head: true }).gte('created_at', weekAgo)),
  ]);
  return { accounts, reviewers, admins, auditEventsThisWeek };
}
