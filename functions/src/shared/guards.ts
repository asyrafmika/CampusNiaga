import type { CallableRequest } from 'firebase-functions/v2/https';
import { claimsFromToken } from '../domain/claims';
import type { AppClaims } from '../domain/types';
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

export function requireAdmin(req: CallableInput): Actor {
  const actor = requireAuth(req);
  if (actor.claims.admin !== true) fail('FORBIDDEN', 'Administrator access required.');
  return actor;
}
