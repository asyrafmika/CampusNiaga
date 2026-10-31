import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { resolveEmulatorTarget } from './emulatorTarget';
import { SEED_PASSWORD, users } from './scenario';
import { seedEmulators } from './seedEmulators';

async function main(): Promise<void> {
  const target = resolveEmulatorTarget(process.env);

  // The Admin SDK reads these when it connects, so they must be set first.
  process.env['GCLOUD_PROJECT'] = target.projectId;
  process.env['FIRESTORE_EMULATOR_HOST'] = target.firestoreHost;
  process.env['FIREBASE_AUTH_EMULATOR_HOST'] = target.authHost;
  process.env['METADATA_SERVER_DETECTION'] = 'none';

  try {
    await fetch(`http://${target.authHost}/`);
  } catch {
    throw new Error('The emulators are not running. Start them with: firebase emulators:start --project demo-campusniaga');
  }

  const app = initializeApp({ projectId: target.projectId });
  await seedEmulators(getAuth(app), getFirestore(app));

  console.log(`Seeded project ${target.projectId}. Every account uses the password: ${SEED_PASSWORD}`);
  console.table(Object.values(users).map(({ email, claims }) => ({ email, roles: Object.keys(claims).join(', ') || '(none)' })));
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
