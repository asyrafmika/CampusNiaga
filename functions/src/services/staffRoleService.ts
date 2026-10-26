import { FieldValue } from 'firebase-admin/firestore';
import { z } from 'zod';
import type { ClaimsPatch } from '../domain/claims';
import { COLLECTIONS } from '../domain/types';
import { writeAudit } from '../shared/audit';
import { findAuthUser, updateUserClaims } from '../shared/authClaims';
import { fail } from '../shared/errors';
import { adminAuth, db } from '../shared/firebase';
import type { Actor } from '../shared/guards';
import { displayNameFor, roleFlagsFor } from './userProfile';

export const STAFF_ROLES = ['reviewer', 'admin'] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

export const SetStaffRoleInput = z.object({
  uid: z.string().min(1).max(128),
  role: z.enum(STAFF_ROLES),
  enabled: z.boolean(),
});
export type SetStaffRoleInput = z.infer<typeof SetStaffRoleInput>;

export interface SetStaffRoleResult {
  uid: string;
  role: StaffRole;
  enabled: boolean;
  /** False when the user already had (or already lacked) the role. */
  changed: boolean;
}

/**
 * Grants or removes a staff role. Removing a role also revokes the user's
 * refresh tokens, so the change takes effect at their next request instead
 * of when their current ID token expires.
 */
export async function setStaffRole(actor: Actor, input: SetStaffRoleInput): Promise<SetStaffRoleResult> {
  if (input.uid === actor.uid && input.role === 'admin' && !input.enabled) {
    fail('FORBIDDEN', "You can't remove your own administrator role.");
  }

  const target = await findAuthUser(input.uid);
  if (!target) fail('NOT_FOUND', 'User not found.');

  const patch: ClaimsPatch = input.role === 'admin' ? { admin: input.enabled } : { reviewer: input.enabled };
  const changed = await updateUserClaims(target, patch);
  const result: SetStaffRoleResult = { uid: target.uid, role: input.role, enabled: input.enabled, changed };
  if (!changed) return result;

  if (!input.enabled) await adminAuth.revokeRefreshTokens(target.uid);

  const userRef = db.collection(COLLECTIONS.users).doc(target.uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (snap.exists) {
      tx.update(userRef, {
        [`roleFlags.${input.role}`]: input.enabled,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      tx.create(userRef, {
        name: displayNameFor(target),
        email: target.email ?? '',
        verified: false,
        roleFlags: roleFlagsFor(target, { [input.role]: input.enabled }),
        accountStatus: 'active',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    writeAudit(tx, {
      actorUid: actor.uid,
      action: input.enabled ? 'role.granted' : 'role.revoked',
      targetType: 'user',
      targetId: target.uid,
      metadata: { role: input.role },
    });
  });

  return result;
}
