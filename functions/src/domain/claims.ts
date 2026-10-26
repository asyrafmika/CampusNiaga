import type { AppClaims } from './types';

type ClaimKey = keyof AppClaims;

/** A change to custom claims. `null` (or `false` for flags) removes the claim. */
export type ClaimsPatch = { [K in ClaimKey]?: Required<AppClaims>[K] | null };

export interface ClaimsPatchResult {
  next: Record<string, unknown>;
  changed: boolean;
}

/**
 * Applies a patch on top of a user's existing custom claims without dropping
 * unrelated claims (Firebase replaces the whole claims object on write).
 * False flags are removed rather than stored, keeping ID tokens small.
 */
export function applyClaimsPatch(
  current: Readonly<Record<string, unknown>> | undefined,
  patch: ClaimsPatch,
): ClaimsPatchResult {
  const next: Record<string, unknown> = { ...current };
  let changed = false;

  for (const [key, value] of Object.entries(patch)) {
    const remove = value === null || value === false;
    if (remove) {
      if (key in next) {
        Reflect.deleteProperty(next, key);
        changed = true;
      }
    } else if (next[key] !== value) {
      next[key] = value;
      changed = true;
    }
  }

  return { next, changed };
}

/** Reads CampusNiaga claims from a decoded ID token, ignoring anything malformed. */
export function claimsFromToken(token: Readonly<Record<string, unknown>>): AppClaims {
  const claims: AppClaims = {};
  if (token['student'] === true) claims.student = true;
  if (token['reviewer'] === true) claims.reviewer = true;
  if (token['admin'] === true) claims.admin = true;
  const businessId = token['businessId'];
  if (typeof businessId === 'string' && businessId.length > 0) claims.businessId = businessId;
  return claims;
}
