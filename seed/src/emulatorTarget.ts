export interface EmulatorTarget {
  projectId: string;
  firestoreHost: string;
  authHost: string;
}

const DEFAULT_TARGET: EmulatorTarget = {
  projectId: 'demo-campusniaga',
  firestoreHost: '127.0.0.1:8080',
  authHost: '127.0.0.1:9099',
};

const LOCAL_HOST = /^(127\.0\.0\.1|localhost|\[::1\]):\d+$/;

/**
 * Decides where the seed writes. Defaults to the local emulators and refuses
 * anything else, so seed data can never reach the real Firebase project.
 */
export function resolveEmulatorTarget(env: Readonly<Record<string, string | undefined>>): EmulatorTarget {
  const target: EmulatorTarget = {
    projectId: env['GCLOUD_PROJECT'] ?? DEFAULT_TARGET.projectId,
    firestoreHost: env['FIRESTORE_EMULATOR_HOST'] ?? DEFAULT_TARGET.firestoreHost,
    authHost: env['FIREBASE_AUTH_EMULATOR_HOST'] ?? DEFAULT_TARGET.authHost,
  };

  if (!target.projectId.startsWith('demo-')) {
    throw new Error(`Refusing to seed project "${target.projectId}": only demo- projects are allowed.`);
  }
  for (const host of [target.firestoreHost, target.authHost]) {
    if (!LOCAL_HOST.test(host)) {
      throw new Error(`Refusing to seed "${host}": only local emulators are allowed.`);
    }
  }
  return target;
}
