import type { StaffRole } from '../../auth';
import { toAppError } from '../../../shared/lib/errors';
import { escapeLike, PAGE_SIZE } from '../../../shared/lib/format';
import { supabase } from '../../../shared/supabase/client';

export type UserRow = {
  id: string;
  name: string;
  email: string;
  accountStatus: string;
  createdAt: string;
  isReviewer: boolean;
  isAdmin: boolean;
};

export type UserPage = { rows: UserRow[]; total: number };

/** One page of accounts with their staff roles, newest first. Admins only (RLS). */
export async function listUsers({ page, search }: { page: number; search: string }): Promise<UserPage> {
  let query = supabase
    .from('profiles')
    .select('id, name, email, account_status, created_at', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE - 1);
  const term = search.trim();
  if (term.length > 0) query = query.ilike('email', `%${escapeLike(term)}%`);

  const { data: profiles, error, count } = await query;
  if (error) throw toAppError(error);

  const ids = profiles.map((p) => p.id);
  const roles = new Map<string, Set<string>>();
  if (ids.length > 0) {
    const { data, error: rolesError } = await supabase.from('staff_roles').select('user_id, role').in('user_id', ids);
    if (rolesError) throw toAppError(rolesError);
    for (const { user_id, role } of data) {
      const set = roles.get(user_id) ?? new Set<string>();
      set.add(role);
      roles.set(user_id, set);
    }
  }

  return {
    total: count ?? profiles.length,
    rows: profiles.map((p) => ({
      id: p.id,
      name: p.name,
      email: p.email,
      accountStatus: p.account_status,
      createdAt: p.created_at,
      isReviewer: roles.get(p.id)?.has('reviewer') ?? false,
      isAdmin: roles.get(p.id)?.has('admin') ?? false,
    })),
  };
}

/** Grants or removes a role through the audited `set_staff_role` function. */
export async function setStaffRole(userId: string, role: StaffRole, enabled: boolean): Promise<void> {
  const { error } = await supabase.rpc('set_staff_role', { target_user_id: userId, role, enabled });
  if (error) throw toAppError(error);
}
