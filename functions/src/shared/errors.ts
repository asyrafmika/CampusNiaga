import { HttpsError, type FunctionsErrorCode } from 'firebase-functions/v2/https';

/** Machine-readable failure reasons. See docs/api-contracts.md. */
export const ERROR_REASONS = [
  'NOT_VERIFIED_STUDENT',
  'FORBIDDEN',
  'INVALID_INPUT',
  'NOT_FOUND',
  'INVALID_TRANSITION',
  'ITEM_UNAVAILABLE',
  'CAPACITY_FULL',
  'ALREADY_EXISTS',
  'RATE_LIMITED',
] as const;

export type ErrorReason = (typeof ERROR_REASONS)[number];

const CODE_BY_REASON: Record<ErrorReason, FunctionsErrorCode> = {
  NOT_VERIFIED_STUDENT: 'permission-denied',
  FORBIDDEN: 'permission-denied',
  INVALID_INPUT: 'invalid-argument',
  NOT_FOUND: 'not-found',
  INVALID_TRANSITION: 'failed-precondition',
  ITEM_UNAVAILABLE: 'failed-precondition',
  CAPACITY_FULL: 'failed-precondition',
  ALREADY_EXISTS: 'already-exists',
  RATE_LIMITED: 'resource-exhausted',
};

/** Shape of `HttpsError.details` for every CampusNiaga error. */
export interface ErrorDetails {
  reason: ErrorReason;
}

/** Throws the HttpsError that clients receive, with `details.reason` set. */
export function fail(reason: ErrorReason, message: string): never {
  const details: ErrorDetails = { reason };
  throw new HttpsError(CODE_BY_REASON[reason], message, details);
}
