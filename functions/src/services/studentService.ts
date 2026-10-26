import { FieldValue } from 'firebase-admin/firestore';
import { isEligibleStudentEmail } from '../domain/studentEligibility';
import { COLLECTIONS } from '../domain/types';
import { writeAudit } from '../shared/audit';
import { findAuthUser, updateUserClaims } from '../shared/authClaims';
import { fail } from '../shared/errors';
import { db } from '../shared/firebase';
import type { Actor } from '../shared/guards';
import { getStudentEligibilityConfig } from './appConfigService';
import { displayNameFor, readStoredUser, roleFlagsFor } from './userProfile';

export interface SyncStudentResult {
  student: true;
  /** True when the claim was just granted: the client must refresh its ID token. */
  claimsChanged: boolean;
}

/**
 * Grants the `student` claim to a verified USM student (or allowlisted test
 * account) and creates or updates their profile. Email and verification are
 * read from Firebase Auth on the server, never from client input. Idempotent.
 */
export async function syncStudent(actor: Actor): Promise<SyncStudentResult> {
  const user = await findAuthUser(actor.uid);
  if (!user) fail('NOT_FOUND', 'Account not found.');
  const { email } = user;
  if (!email || !user.emailVerified) {
    fail('NOT_VERIFIED_STUDENT', 'Verify your email address first.');
  }

  const config = await getStudentEligibilityConfig();
  if (!isEligibleStudentEmail(email, config)) {
    const domain = config.studentEmailDomains[0] ?? 'student.usm.my';
    fail('NOT_VERIFIED_STUDENT', `CampusNiaga is for USM students. Sign up with your @${domain} email.`);
  }

  const userRef = db.collection(COLLECTIONS.users).doc(user.uid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const stored = readStoredUser(snap.data());
    if (stored.accountStatus === 'suspended') fail('FORBIDDEN', 'This account is suspended.');

    if (!snap.exists) {
      tx.create(userRef, {
        name: displayNameFor(user),
        email,
        verified: true,
        roleFlags: roleFlagsFor(user, { student: true }),
        accountStatus: 'active',
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else if (stored.verified !== true || stored.email !== email) {
      tx.update(userRef, {
        email,
        verified: true,
        'roleFlags.student': true,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    if (stored.verified !== true) {
      writeAudit(tx, {
        actorUid: user.uid,
        action: 'student.verified',
        targetType: 'user',
        targetId: user.uid,
      });
    }
  });

  // Claims are set after the profile commits; a failure here is repaired by
  // calling again, since every step above is idempotent.
  const claimsChanged = await updateUserClaims(user, { student: true });
  return { student: true, claimsChanged };
}
