import type { DecodedIdToken } from 'firebase-admin/auth';
import { HttpsError } from 'firebase-functions/v2/https';
import { expect } from 'vitest';
import type { AppClaims } from '../../src/domain/types';
import type { ErrorReason } from '../../src/shared/errors';
import { adminAuth, db } from '../../src/shared/firebase';
import type { CallableInput } from '../../src/shared/guards';

function env(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

/** Deletes all Firestore documents and Auth users in the emulators. */
export async function resetEmulators(): Promise<void> {
  const projectId = env('GCLOUD_PROJECT');
  const targets = [
    `http://${env('FIRESTORE_EMULATOR_HOST')}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    `http://${env('FIREBASE_AUTH_EMULATOR_HOST')}/emulator/v1/projects/${projectId}/accounts`,
  ];
  for (const url of targets) {
    const response = await fetch(url, { method: 'DELETE' });
    if (!response.ok) throw new Error(`Emulator reset failed (${response.status}): ${url}`);
  }
}

export interface TestUserOptions {
  uid: string;
  email: string;
  emailVerified?: boolean;
  claims?: AppClaims;
}

export async function createTestUser(options: TestUserOptions): Promise<void> {
  await adminAuth.createUser({
    uid: options.uid,
    email: options.email,
    emailVerified: options.emailVerified ?? true,
  });
  if (options.claims) await adminAuth.setCustomUserClaims(options.uid, { ...options.claims });
}

export async function claimsOf(uid: string): Promise<Record<string, unknown>> {
  return (await adminAuth.getUser(uid)).customClaims ?? {};
}

/** A callable request from a signed-in user whose ID token carries `claims`. */
export function requestAs(uid: string, claims: AppClaims = {}, data: unknown = {}): CallableInput {
  const token = {
    uid,
    sub: uid,
    aud: env('GCLOUD_PROJECT'),
    iss: 'https://securetoken.google.com/test',
    iat: 0,
    exp: 0,
    auth_time: 0,
    firebase: { identities: {}, sign_in_provider: 'password' },
    ...claims,
  } as DecodedIdToken;
  return { auth: { uid, token, rawToken: 'test-token' }, data };
}

/** A callable request with no signed-in user. */
export function anonymousRequest(data: unknown = {}): CallableInput {
  return { data };
}

/** Asserts that calling `fn` fails with the given `details.reason`. */
export async function expectReason(fn: () => unknown, reason: ErrorReason): Promise<void> {
  const error = await Promise.resolve()
    .then(fn)
    .then(
      () => undefined,
      (e: unknown) => e,
    );
  expect(error).toBeInstanceOf(HttpsError);
  expect((error as HttpsError).details).toEqual({ reason });
}

export async function auditActionsFor(targetId: string): Promise<string[]> {
  const snap = await db.collection('auditLogs').where('targetId', '==', targetId).get();
  return snap.docs.map((doc) => String(doc.get('action')));
}
