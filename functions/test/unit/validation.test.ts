import { HttpsError } from 'firebase-functions/v2/https';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { parse } from '../../src/shared/validation';

const ListingInput = z.object({
  title: z.string().min(3).max(80),
  priceSen: z.number().int().min(0),
});

describe('parse', () => {
  it('returns the parsed value and strips unknown keys', () => {
    const result = parse(ListingInput, { title: 'Desk lamp', priceSen: 1500, ownerUid: 'attacker' });

    expect(result).toEqual({ title: 'Desk lamp', priceSen: 1500 });
  });

  it('throws INVALID_INPUT naming each failing field', () => {
    let caught: unknown;
    try {
      parse(ListingInput, { title: 'ab', priceSen: 12.5 });
    } catch (error) {
      caught = error;
    }

    expect(caught).toBeInstanceOf(HttpsError);
    const error = caught as HttpsError;
    expect(error.code).toBe('invalid-argument');
    expect(error.details).toEqual({ reason: 'INVALID_INPUT' });
    expect(error.message).toContain('title:');
    expect(error.message).toContain('priceSen:');
  });

  it('rejects input that is not an object', () => {
    expect(() => parse(ListingInput, null)).toThrow(HttpsError);
  });
});
