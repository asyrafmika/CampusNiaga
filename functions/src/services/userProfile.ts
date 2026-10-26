import type { UserRecord } from 'firebase-admin/auth';
import { z } from 'zod';
import { claimsFromToken } from '../domain/claims';
import { ACCOUNT_STATUSES, type RoleFlags } from '../domain/types';

/** The fields of users/{uid} that services read back. Unknown fields are ignored. */
export const StoredUserSchema = z.object({
  email: z.string().optional(),
  verified: z.boolean().optional(),
  accountStatus: z.enum(ACCOUNT_STATUSES).optional(),
});
export type StoredUser = z.infer<typeof StoredUserSchema>;

export function readStoredUser(data: unknown): StoredUser {
  return StoredUserSchema.parse(data ?? {});
}

/** Display-only role flags derived from the user's current claims. */
export function roleFlagsFor(user: UserRecord, overrides: Partial<RoleFlags> = {}): RoleFlags {
  const claims = claimsFromToken(user.customClaims ?? {});
  return {
    student: claims.student === true,
    business: claims.businessId !== undefined,
    reviewer: claims.reviewer === true,
    admin: claims.admin === true,
    ...overrides,
  };
}

/** Display name for a new profile: the Auth display name, else the email's local part. */
export function displayNameFor(user: UserRecord): string {
  const name = user.displayName?.trim();
  if (name) return name;
  return user.email?.split('@')[0] ?? 'CampusNiaga user';
}
