import type { CallableRequest } from 'firebase-functions/v2/https';
import { claimsFromToken } from '../domain/claims';
import type { AppClaims } from '../domain/types';
import { findAuthUser } from './authClaims';
import { fail } from './errors';

/** The parts of a callable request that handlers use; keeps handlers easy to test. */
export type CallableInput = Pick<CallableRequest<unknown>, 'auth' | 'data'>;

/** The verified caller, passed from handlers to services. */
export interface Actor {
  uid: string;
  claims: AppClaims;
}

export function requireAuth(req: CallableInput): Actor {
  if (!req.auth) fail('FORBIDDEN', 'Sign in to continue.');
  return { uid: req.auth.uid, claims: claimsFromToken(req.auth.token) };
}

/**
 * Checks the caller's current claims in Firebase Auth, not the ones in their
 * token: an ID token stays valid for up to an hour after a role is removed.
 */
export async function requireAdmin(req: CallableInput): Promise<Actor> {
  const { uid } = requireAuth(req);
  const user = await findAuthUser(uid);
  const claims = claimsFromToken(user?.customClaims ?? {});
  if (claims.admin !== true) fail('FORBIDDEN', 'Administrator access required.');
  return { uid, claims };
}
