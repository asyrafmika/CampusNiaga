import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
  type Firestore,
} from 'firebase/firestore';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';

const RULES_PATH = resolve(__dirname, '../../../../firebase/firestore.rules');

let env: RulesTestEnvironment;

const student = { email_verified: true, student: true };

const db = {
  anonymous: () => env.unauthenticatedContext().firestore() as unknown as Firestore,
  ali: () => env.authenticatedContext('ali', student).firestore() as unknown as Firestore,
  siti: () => env.authenticatedContext('siti', student).firestore() as unknown as Firestore,
  reviewer: () => env.authenticatedContext('rev', { reviewer: true }).firestore() as unknown as Firestore,
  admin: () => env.authenticatedContext('admin1', { admin: true }).firestore() as unknown as Firestore,
};

const aliProfile = {
  name: 'Ali',
  email: 'ali@student.usm.my',
  verified: true,
  accountStatus: 'active',
  roleFlags: { student: true, business: false, reviewer: false, admin: false },
};

async function seed(path: string, data: Record<string, unknown>): Promise<void> {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore() as unknown as Firestore, path), data);
  });
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: process.env['GCLOUD_PROJECT'] ?? 'demo-campusniaga',
    firestore: { rules: readFileSync(RULES_PATH, 'utf8') },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await seed('users/ali', aliProfile);
  await seed('auditLogs/log1', { actorUid: 'admin1', action: 'role.granted', targetId: 'ali' });
  await seed('config/app', { studentEmailDomains: ['student.usm.my'], testAllowlist: ['examiner@gmail.com'] });
});

describe('users: reading', () => {
  it('lets a user read their own profile', async () => {
    await assertSucceeds(getDoc(doc(db.ali(), 'users/ali')));
  });

  it('lets an admin read any profile', async () => {
    await assertSucceeds(getDoc(doc(db.admin(), 'users/ali')));
  });

  it('lets an admin list profiles', async () => {
    await assertSucceeds(getDocs(collection(db.admin(), 'users')));
  });

  it.each([
    ['another student', () => db.siti()],
    ['a reviewer', () => db.reviewer()],
    ['someone not signed in', () => db.anonymous()],
  ])('denies %s reading a profile', async (_who, firestore) => {
    await assertFails(getDoc(doc(firestore(), 'users/ali')));
  });

  it('stops a student listing every profile', async () => {
    await assertFails(getDocs(collection(db.ali(), 'users')));
  });
});

describe('users: writing', () => {
  it('lets an active owner change their name', async () => {
    await assertSucceeds(updateDoc(doc(db.ali(), 'users/ali'), { name: 'Ali Bin Abu', updatedAt: serverTimestamp() }));
  });

  it.each([
    ['roleFlags', { 'roleFlags.admin': true }],
    ['verified', { verified: false }],
    ['accountStatus', { accountStatus: 'suspended' }],
    ['email', { email: 'other@student.usm.my' }],
    ['a new field', { admin: true }],
  ])('denies an owner changing %s', async (_field, change) => {
    await assertFails(updateDoc(doc(db.ali(), 'users/ali'), { ...change, updatedAt: serverTimestamp() }));
  });

  it.each([
    ['empty', ''],
    ['only spaces', '   '],
    ['over 60 characters', 'a'.repeat(61)],
    ['not text', 123],
  ])('denies a name that is %s', async (_problem, name) => {
    await assertFails(updateDoc(doc(db.ali(), 'users/ali'), { name, updatedAt: serverTimestamp() }));
  });

  it('requires updatedAt to be the server time', async () => {
    await assertFails(updateDoc(doc(db.ali(), 'users/ali'), { name: 'Ali' }));
    await assertFails(updateDoc(doc(db.ali(), 'users/ali'), { name: 'Ali', updatedAt: new Date(0) }));
  });

  it('denies a suspended owner changing their name', async () => {
    await seed('users/ali', { ...aliProfile, accountStatus: 'suspended' });

    await assertFails(updateDoc(doc(db.ali(), 'users/ali'), { name: 'Ali', updatedAt: serverTimestamp() }));
  });

  it('denies changing someone else\'s profile', async () => {
    await assertFails(updateDoc(doc(db.siti(), 'users/ali'), { name: 'Hacked', updatedAt: serverTimestamp() }));
  });

  it('denies an admin editing a profile directly (role changes use setStaffRole)', async () => {
    await assertFails(updateDoc(doc(db.admin(), 'users/ali'), { 'roleFlags.admin': true, updatedAt: serverTimestamp() }));
  });

  it('denies a client creating a profile, even their own', async () => {
    await assertFails(setDoc(doc(db.siti(), 'users/siti'), { ...aliProfile, verified: true }));
  });

  it('denies deleting a profile, even for its owner or an admin', async () => {
    await assertFails(deleteDoc(doc(db.ali(), 'users/ali')));
    await assertFails(deleteDoc(doc(db.admin(), 'users/ali')));
  });
});

describe('privilege comes from claims, not documents', () => {
  it('gives no admin access to a user whose profile says admin', async () => {
    await seed('users/ali', { ...aliProfile, roleFlags: { ...aliProfile.roleFlags, admin: true } });

    await assertFails(getDoc(doc(db.ali(), 'auditLogs/log1')));
    await assertFails(getDoc(doc(db.ali(), 'config/app')));
    await assertFails(getDocs(collection(db.ali(), 'users')));
  });
});

describe('auditLogs', () => {
  it('lets an admin read the audit log', async () => {
    await assertSucceeds(getDocs(collection(db.admin(), 'auditLogs')));
  });

  it.each([
    ['a student', () => db.ali()],
    ['a reviewer', () => db.reviewer()],
    ['someone not signed in', () => db.anonymous()],
  ])('denies %s reading the audit log', async (_who, firestore) => {
    await assertFails(getDoc(doc(firestore(), 'auditLogs/log1')));
  });

  it('is append-only from the server: even an admin client cannot write', async () => {
    await assertFails(addDoc(collection(db.admin(), 'auditLogs'), { action: 'forged' }));
    await assertFails(updateDoc(doc(db.admin(), 'auditLogs/log1'), { action: 'edited' }));
    await assertFails(deleteDoc(doc(db.admin(), 'auditLogs/log1')));
  });
});

describe('config', () => {
  it('lets an admin read app settings', async () => {
    await assertSucceeds(getDoc(doc(db.admin(), 'config/app')));
  });

  it.each([
    ['a student', () => db.ali()],
    ['a reviewer', () => db.reviewer()],
    ['someone not signed in', () => db.anonymous()],
  ])('hides the allowlist from %s', async (_who, firestore) => {
    await assertFails(getDoc(doc(firestore(), 'config/app')));
  });

  it('denies an admin client changing settings', async () => {
    await assertFails(setDoc(doc(db.admin(), 'config/app'), { testAllowlist: ['attacker@gmail.com'] }));
  });
});

describe('default deny', () => {
  it.each(['listings', 'orders', 'businessApplications', 'somethingNew'])(
    'keeps %s closed to students and admins until its phase opens it',
    async (name) => {
      await assertFails(getDocs(collection(db.ali(), name)));
      await assertFails(addDoc(collection(db.ali(), name), { title: 'x' }));
      await assertFails(getDocs(collection(db.admin(), name)));
      await assertFails(addDoc(collection(db.admin(), name), { title: 'x' }));
    },
  );
});
