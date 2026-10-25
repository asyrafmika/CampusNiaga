import { HttpsError } from 'firebase-functions/v2/https';
import { describe, expect, it } from 'vitest';
import { ERROR_REASONS, fail } from '../../src/shared/errors';

function captureError(fn: () => void): HttpsError {
  try {
    fn();
  } catch (error) {
    if (error instanceof HttpsError) return error;
    throw error;
  }
  throw new Error('expected fail() to throw');
}

describe('fail', () => {
  it('throws an HttpsError carrying the reason in details', () => {
    const error = captureError(() => fail('ITEM_UNAVAILABLE', 'Listing is reserved'));

    expect(error.code).toBe('failed-precondition');
    expect(error.message).toBe('Listing is reserved');
    expect(error.details).toEqual({ reason: 'ITEM_UNAVAILABLE' });
  });

  it.each([
    ['NOT_VERIFIED_STUDENT', 'permission-denied'],
    ['FORBIDDEN', 'permission-denied'],
    ['INVALID_INPUT', 'invalid-argument'],
    ['NOT_FOUND', 'not-found'],
    ['ALREADY_EXISTS', 'already-exists'],
    ['RATE_LIMITED', 'resource-exhausted'],
  ] as const)('maps %s to the %s status code', (reason, code) => {
    expect(captureError(() => fail(reason, 'x')).code).toBe(code);
  });

  it('defines every reason listed in the API contract', () => {
    expect(ERROR_REASONS).toEqual([
      'NOT_VERIFIED_STUDENT',
      'FORBIDDEN',
      'INVALID_INPUT',
      'NOT_FOUND',
      'INVALID_TRANSITION',
      'ITEM_UNAVAILABLE',
      'CAPACITY_FULL',
      'ALREADY_EXISTS',
      'RATE_LIMITED',
    ]);
  });
});
