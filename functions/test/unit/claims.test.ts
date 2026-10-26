import { describe, expect, it } from 'vitest';
import { applyClaimsPatch, claimsFromToken } from '../../src/domain/claims';

describe('applyClaimsPatch', () => {
  it('adds a claim while keeping unrelated claims', () => {
    const result = applyClaimsPatch({ reviewer: true, custom: 'x' }, { student: true });

    expect(result).toEqual({ next: { reviewer: true, custom: 'x', student: true }, changed: true });
  });

  it('removes a flag set to false instead of storing false', () => {
    const result = applyClaimsPatch({ reviewer: true, student: true }, { reviewer: false });

    expect(result).toEqual({ next: { student: true }, changed: true });
  });

  it('removes businessId when patched with null', () => {
    expect(applyClaimsPatch({ businessId: 'b1' }, { businessId: null }).next).toEqual({});
  });

  it('reports no change when the claim already has the value', () => {
    expect(applyClaimsPatch({ student: true }, { student: true }).changed).toBe(false);
  });

  it('reports no change when removing a claim that is absent', () => {
    expect(applyClaimsPatch({}, { admin: false }).changed).toBe(false);
  });

  it('handles a user with no claims yet', () => {
    expect(applyClaimsPatch(undefined, { student: true }).next).toEqual({ student: true });
  });
});

describe('claimsFromToken', () => {
  it('reads only well-formed CampusNiaga claims', () => {
    const claims = claimsFromToken({
      student: true,
      reviewer: 'true',
      admin: 1,
      businessId: '',
      email: 'ali@student.usm.my',
    });

    expect(claims).toEqual({ student: true });
  });

  it('reads every claim when present', () => {
    expect(claimsFromToken({ student: true, reviewer: true, admin: true, businessId: 'b1' })).toEqual({
      student: true,
      reviewer: true,
      admin: true,
      businessId: 'b1',
    });
  });
});
