import type { UserRecord } from 'firebase-admin/auth';
import { applyClaimsPatch, type ClaimsPatch } from '../domain/claims';
import { adminAuth } from './firebase';

/**
 * Merges a patch into the user's custom claims. Returns true if anything
 * changed; the client must then refresh its ID token to see the new claims.
 */
export async function updateUserClaims(user: UserRecord, patch: ClaimsPatch): Promise<boolean> {
  const { next, changed } = applyClaimsPatch(user.customClaims, patch);
  if (changed) await adminAuth.setCustomUserClaims(user.uid, next);
  return changed;
}

/** Loads an Auth user, or returns null if the UID doesn't exist. */
export async function findAuthUser(uid: string): Promise<UserRecord | null> {
  try {
    return await adminAuth.getUser(uid);
  } catch (error) {
    if (isAuthError(error, 'auth/user-not-found')) return null;
    throw error;
  }
}

function isAuthError(error: unknown, code: string): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === code;
}
