import { beforeEach, describe, expect, it } from 'vitest';
import { syncStudentStatusHandler } from '../../src/callable/auth/syncStudentStatus';
import { db } from '../../src/shared/firebase';
import {
  anonymousRequest,
  auditActionsFor,
  claimsOf,
  createTestUser,
  expectReason,
  requestAs,
  resetEmulators,
} from './helpers';

const sync = (uid: string) => syncStudentStatusHandler(requestAs(uid));

describe('syncStudentStatus', () => {
  beforeEach(resetEmulators);

  it('grants the student claim and creates the profile for a verified USM email', async () => {
    await createTestUser({ uid: 'ali', email: 'ali@student.usm.my' });

    const result = await sync('ali');

    expect(result).toEqual({ student: true, claimsChanged: true });
    expect(await claimsOf('ali')).toEqual({ student: true });
    const profile = (await db.doc('users/ali').get()).data();
    expect(profile).toMatchObject({
      name: 'ali',
      email: 'ali@student.usm.my',
      verified: true,
      accountStatus: 'active',
      roleFlags: { student: true, business: false, reviewer: false, admin: false },
    });
    expect(await auditActionsFor('ali')).toEqual(['student.verified']);
  });

  it('is idempotent: a second call changes nothing and writes no second audit entry', async () => {
    await createTestUser({ uid: 'ali', email: 'ali@student.usm.my' });
    await sync('ali');

    const result = await sync('ali');

    expect(result).toEqual({ student: true, claimsChanged: false });
    expect(await auditActionsFor('ali')).toEqual(['student.verified']);
  });

  it('rejects a USM email that is not verified yet', async () => {
    await createTestUser({ uid: 'ali', email: 'ali@student.usm.my', emailVerified: false });

    await expectReason(() => sync('ali'), 'NOT_VERIFIED_STUDENT');
    expect(await claimsOf('ali')).toEqual({});
    expect((await db.doc('users/ali').get()).exists).toBe(false);
  });

  it.each(['ali@gmail.com', 'ali@evilstudent.usm.my', 'ali@student.usm.my.example.com'])(
    'rejects a verified non-USM email: %s',
    async (email) => {
      await createTestUser({ uid: 'outsider', email });

      await expectReason(() => sync('outsider'), 'NOT_VERIFIED_STUDENT');
      expect(await claimsOf('outsider')).toEqual({});
    },
  );

  it('accepts an allowlisted test account from config/app', async () => {
    await db.doc('config/app').set({ studentEmailDomains: ['student.usm.my'], testAllowlist: ['examiner@gmail.com'] });
    await createTestUser({ uid: 'examiner', email: 'examiner@gmail.com' });

    await expect(sync('examiner')).resolves.toMatchObject({ student: true });
  });

  it('uses the configured domain instead of the default', async () => {
    await db.doc('config/app').set({ studentEmailDomains: ['usm.edu.test'], testAllowlist: [] });
    await createTestUser({ uid: 'ali', email: 'ali@student.usm.my' });

    await expectReason(() => sync('ali'), 'NOT_VERIFIED_STUDENT');
  });

  it('falls back to the default domain when config/app is malformed', async () => {
    await db.doc('config/app').set({ studentEmailDomains: 'gmail.com' });
    await createTestUser({ uid: 'outsider', email: 'outsider@gmail.com' });

    await expectReason(() => sync('outsider'), 'NOT_VERIFIED_STUDENT');
  });

  it('keeps existing claims such as reviewer when adding student', async () => {
    await createTestUser({ uid: 'rev', email: 'rev@student.usm.my', claims: { reviewer: true } });

    await sync('rev');

    expect(await claimsOf('rev')).toEqual({ reviewer: true, student: true });
  });

  it('refuses a suspended account', async () => {
    await createTestUser({ uid: 'ali', email: 'ali@student.usm.my' });
    await db.doc('users/ali').set({ email: 'ali@student.usm.my', verified: false, accountStatus: 'suspended' });

    await expectReason(() => sync('ali'), 'FORBIDDEN');
    expect(await claimsOf('ali')).toEqual({});
  });

  it('refuses an unauthenticated caller', async () => {
    await expectReason(() => syncStudentStatusHandler(anonymousRequest()), 'FORBIDDEN');
  });

  it('ignores any email or flags the client sends', async () => {
    await createTestUser({ uid: 'outsider', email: 'outsider@gmail.com' });

    const forged = requestAs('outsider', {}, { email: 'fake@student.usm.my', emailVerified: true });
    await expectReason(() => syncStudentStatusHandler(forged), 'NOT_VERIFIED_STUDENT');
  });
});
