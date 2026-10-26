import { beforeEach, describe, expect, it } from 'vitest';
import { setStaffRoleHandler } from '../../src/callable/admin/setStaffRole';
import { adminAuth, db } from '../../src/shared/firebase';
import {
  anonymousRequest,
  auditActionsFor,
  claimsOf,
  createTestUser,
  expectReason,
  requestAs,
  resetEmulators,
} from './helpers';

const asAdmin = (data: unknown) => setStaffRoleHandler(requestAs('admin1', { admin: true }, data));

describe('setStaffRole', () => {
  beforeEach(async () => {
    await resetEmulators();
    await createTestUser({ uid: 'admin1', email: 'admin@campusniaga.test', claims: { admin: true } });
    await createTestUser({ uid: 'ali', email: 'ali@student.usm.my', claims: { student: true } });
  });

  it('lets an admin grant the reviewer role, keeping other claims', async () => {
    const result = await asAdmin({ uid: 'ali', role: 'reviewer', enabled: true });

    expect(result).toEqual({ uid: 'ali', role: 'reviewer', enabled: true, changed: true });
    expect(await claimsOf('ali')).toEqual({ student: true, reviewer: true });
    expect((await db.doc('users/ali').get()).get('roleFlags.reviewer')).toBe(true);
    expect(await auditActionsFor('ali')).toEqual(['role.granted']);
  });

  it('removes a role, revokes the user sessions and records it', async () => {
    await asAdmin({ uid: 'ali', role: 'reviewer', enabled: true });
    const before = (await adminAuth.getUser('ali')).tokensValidAfterTime;

    await asAdmin({ uid: 'ali', role: 'reviewer', enabled: false });

    expect(await claimsOf('ali')).toEqual({ student: true });
    expect((await db.doc('users/ali').get()).get('roleFlags.reviewer')).toBe(false);
    expect((await adminAuth.getUser('ali')).tokensValidAfterTime).not.toBe(before);
    expect((await auditActionsFor('ali')).sort()).toEqual(['role.granted', 'role.revoked']);
  });

  it('reports no change and writes no audit entry when the role is already set', async () => {
    await asAdmin({ uid: 'ali', role: 'reviewer', enabled: true });

    const result = await asAdmin({ uid: 'ali', role: 'reviewer', enabled: true });

    expect(result.changed).toBe(false);
    expect(await auditActionsFor('ali')).toEqual(['role.granted']);
  });

  it('refuses a caller who is not an admin', async () => {
    const request = requestAs('ali', { student: true, reviewer: true }, { uid: 'ali', role: 'admin', enabled: true });

    await expectReason(() => setStaffRoleHandler(request), 'FORBIDDEN');
    expect(await claimsOf('ali')).toEqual({ student: true });
  });

  it('refuses an unauthenticated caller', async () => {
    await expectReason(
      () => setStaffRoleHandler(anonymousRequest({ uid: 'ali', role: 'admin', enabled: true })),
      'FORBIDDEN',
    );
  });

  it('stops an admin from removing their own admin role', async () => {
    await expectReason(() => asAdmin({ uid: 'admin1', role: 'admin', enabled: false }), 'FORBIDDEN');
    expect(await claimsOf('admin1')).toEqual({ admin: true });
  });

  it.each([
    { uid: 'ali', role: 'superuser', enabled: true },
    { uid: '', role: 'reviewer', enabled: true },
    { uid: 'ali', role: 'reviewer', enabled: 'yes' },
    null,
  ])('rejects invalid input %j', async (data) => {
    await expectReason(() => asAdmin(data), 'INVALID_INPUT');
  });

  it('returns NOT_FOUND for an unknown user', async () => {
    await expectReason(() => asAdmin({ uid: 'nobody', role: 'reviewer', enabled: true }), 'NOT_FOUND');
  });

  it('creates a profile for a staff account that never signed in to the app', async () => {
    await createTestUser({ uid: 'staff', email: 'staff@usm.my' });

    await asAdmin({ uid: 'staff', role: 'reviewer', enabled: true });

    expect((await db.doc('users/staff').get()).data()).toMatchObject({
      email: 'staff@usm.my',
      verified: false,
      accountStatus: 'active',
      roleFlags: { student: false, business: false, reviewer: true, admin: false },
    });
  });
});
