import { toAppError } from '../../../shared/lib/errors';
import { PAGE_SIZE } from '../../../shared/lib/format';
import { supabase } from '../../../shared/supabase/client';

export type AuditRow = {
  id: number;
  action: string;
  actorEmail: string | null;
  targetType: string;
  targetLabel: string;
  details: string;
  createdAt: string;
};

export type AuditPage = { rows: AuditRow[]; total: number };

/** Plain-language names for audit actions. */
export const ACTION_LABELS: Record<string, string> = {
  'role.granted': 'Role granted',
  'role.revoked': 'Role removed',
  'application.submitted': 'Application submitted',
  'application.under_review': 'Application review started',
  'application.info_requested': 'Application changes requested',
  'application.approved': 'Application approved',
  'application.rejected': 'Application rejected',
  'business.suspended': 'Business suspended',
  'business.reinstated': 'Business reinstated',
};

function describe(metadata: unknown): string {
  if (typeof metadata !== 'object' || metadata === null) return '';
  return Object.entries(metadata)
    .map(([key, value]) => `${key}: ${String(value)}`)
    .join(', ');
}

async function emailsFor(ids: string[]): Promise<Map<string, string>> {
  const unique = [...new Set(ids)];
  if (unique.length === 0) return new Map();
  const { data, error } = await supabase.from('profiles').select('id, email').in('id', unique);
  if (error) throw toAppError(error);
  return new Map(data.map((p) => [p.id, p.email]));
}

/** Newest audit entries first, with people shown by email. Admins only (RLS). */
export async function listAuditLogs({ page, limit = PAGE_SIZE }: { page: number; limit?: number }): Promise<AuditPage> {
  const { data, error, count } = await supabase
    .from('audit_logs')
    .select('id, actor_id, action, target_type, target_id, metadata, created_at', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(page * limit, page * limit + limit - 1);
  if (error) throw toAppError(error);

  const userTargets = data.filter((r) => r.target_type === 'user').map((r) => r.target_id);
  const actors = data.map((r) => r.actor_id).filter((id): id is string => id !== null);
  const emails = await emailsFor([...actors, ...userTargets]);

  return {
    total: count ?? data.length,
    rows: data.map((r) => ({
      id: r.id,
      action: r.action,
      actorEmail: r.actor_id === null ? null : (emails.get(r.actor_id) ?? null),
      targetType: r.target_type,
      targetLabel: r.target_type === 'user' ? (emails.get(r.target_id) ?? r.target_id) : r.target_id,
      details: describe(r.metadata),
      createdAt: r.created_at,
    })),
  };
}
