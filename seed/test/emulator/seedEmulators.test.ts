import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { beforeEach, describe, expect, it } from 'vitest';
import { resolveEmulatorTarget } from '../../src/emulatorTarget';
import { appConfig, SEED_PASSWORD, users } from '../../src/scenario';
import { seedEmulators } from '../../src/seedEmulators';

// Throws unless these tests are pointed at local emulators and a demo- project.
const target = resolveEmulatorTarget(process.env);
if (!process.env['FIRESTORE_EMULATOR_HOST'] || !process.env['FIREBASE_AUTH_EMULATOR_HOST']) {
  throw new Error('Run these tests with "npm run test:emulator".');
}
process.env['METADATA_SERVER_DETECTION'] ??= 'none';

const app = initializeApp({ projectId: target.projectId });
const auth = getAuth(app);
const db = getFirestore(app);

async function resetEmulators(): Promise<void> {
  const urls = [
    `http://${target.firestoreHost}/emulator/v1/projects/${target.projectId}/databases/(default)/documents`,
    `http://${target.authHost}/emulator/v1/projects/${target.projectId}/accounts`,
  ];
  for (const url of urls) {
    const response = await fetch(url, { method: 'DELETE' });
    if (!response.ok) throw new Error(`Emulator reset failed (${response.status}): ${url}`);
  }
}

/** Signs in through the Auth emulator's REST API and returns the ID token's claims. */
async function signIn(email: string, password: string): Promise<{ status: number; claims: Record<string, unknown> }> {
  const url = `http://${target.authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=test`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = (await response.json()) as { idToken?: string };
  const payload = body.idToken?.split('.')[1];
  const claims = payload ? (JSON.parse(Buffer.from(payload, 'base64url').toString()) as Record<string, unknown>) : {};
  return { status: response.status, claims };
}

describe('seedEmulators', () => {
  beforeEach(resetEmulators);

  it('creates accounts that can sign in and carry the right roles', async () => {
    await seedEmulators(auth, db);

    const admin = await signIn(users.admin.email, SEED_PASSWORD);
    expect(admin.status).toBe(200);
    expect(admin.claims).toMatchObject({ admin: true, email_verified: true });

    const student = await signIn(users.studentAli.email, SEED_PASSWORD);
    expect(student.claims).toMatchObject({ student: true, email_verified: true });
    expect(student.claims).not.toHaveProperty('admin');

    const reviewer = await signIn(users.reviewer.email, SEED_PASSWORD);
    expect(reviewer.claims).toMatchObject({ reviewer: true });
    expect(reviewer.claims).not.toHaveProperty('admin');
  });

  it('rejects a wrong password', async () => {
    await seedEmulators(auth, db);

    expect((await signIn(users.admin.email, 'wrong-password')).status).toBe(400);
  });

  it('writes profiles in the documented shape', async () => {
    await seedEmulators(auth, db);

    const student = await db.doc(`users/${users.studentAli.uid}`).get();
    expect(student.data()).toMatchObject({
      name: users.studentAli.name,
      email: users.studentAli.email,
      verified: true,
      accountStatus: 'active',
      roleFlags: { student: true, business: false, reviewer: false, admin: false },
    });
    expect(student.get('createdAt')).toBeDefined();

    const admin = await db.doc(`users/${users.admin.uid}`).get();
    expect(admin.data()).toMatchObject({
      verified: false,
      roleFlags: { student: false, business: false, reviewer: false, admin: true },
    });
  });

  it('gives the outsider no roles and no profile, so the app must refuse them', async () => {
    await seedEmulators(auth, db);

    const outsider = await signIn(users.outsider.email, SEED_PASSWORD);
    expect(outsider.status).toBe(200);
    expect(outsider.claims).not.toHaveProperty('student');
    expect((await db.doc(`users/${users.outsider.uid}`).get()).exists).toBe(false);
  });

  it('writes the app settings', async () => {
    await seedEmulators(auth, db);

    expect((await db.doc('config/app').get()).data()).toMatchObject(appConfig);
  });

  it('restores changed accounts when run again', async () => {
    await seedEmulators(auth, db);
    await auth.setCustomUserClaims(users.studentAli.uid, { admin: true });
    await auth.updateUser(users.studentAli.uid, { password: 'changed-password' });
    await db.doc(`users/${users.studentAli.uid}`).update({ name: 'Changed' });

    await seedEmulators(auth, db);

    const student = await signIn(users.studentAli.email, SEED_PASSWORD);
    expect(student.status).toBe(200);
    expect(student.claims).toMatchObject({ student: true });
    expect(student.claims).not.toHaveProperty('admin');
    expect((await db.doc(`users/${users.studentAli.uid}`).get()).get('name')).toBe(users.studentAli.name);
  });

  it('leaves other data alone when run again', async () => {
    await seedEmulators(auth, db);
    await db.doc('users/someone-else').set({ name: 'Keep me' });
    await auth.createUser({ uid: 'someone-else', email: 'keep@example.com' });

    await seedEmulators(auth, db);

    expect((await db.doc('users/someone-else').get()).get('name')).toBe('Keep me');
    expect((await auth.getUser('someone-else')).email).toBe('keep@example.com');
  });
});
