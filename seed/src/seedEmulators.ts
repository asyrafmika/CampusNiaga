import type { Auth } from 'firebase-admin/auth';
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { COLLECTIONS, type RoleFlags } from '../../functions/src/domain/types';
import { appConfig, SEED_PASSWORD, users, type SeedAccount } from './scenario';

function isUserNotFound(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === 'auth/user-not-found';
}

async function upsertAccount(auth: Auth, account: SeedAccount): Promise<void> {
  const properties = {
    email: account.email,
    emailVerified: true,
    password: SEED_PASSWORD,
    displayName: account.name,
  };
  try {
    await auth.updateUser(account.uid, properties);
  } catch (error) {
    if (!isUserNotFound(error)) throw error;
    await auth.createUser({ uid: account.uid, ...properties });
  }
  await auth.setCustomUserClaims(account.uid, { ...account.claims });
}

function profileFor(account: SeedAccount): Record<string, unknown> {
  const { claims } = account;
  const roleFlags: RoleFlags = {
    student: claims.student === true,
    business: claims.businessId !== undefined,
    reviewer: claims.reviewer === true,
    admin: claims.admin === true,
  };
  return {
    name: account.name,
    email: account.email,
    verified: claims.student === true,
    roleFlags,
    accountStatus: 'active',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Creates the test accounts, profiles and app settings, or restores them if
 * they already exist. Other data in the emulators is left alone, so running it
 * again is safe.
 */
export async function seedEmulators(auth: Auth, db: Firestore): Promise<void> {
  const accounts: SeedAccount[] = Object.values(users);
  for (const account of accounts) {
    await upsertAccount(auth, account);
  }

  const batch = db.batch();
  for (const account of accounts) {
    if (account.hasProfile) {
      batch.set(db.collection(COLLECTIONS.users).doc(account.uid), profileFor(account));
    }
  }
  batch.set(db.collection(COLLECTIONS.config).doc('app'), {
    ...appConfig,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
}
