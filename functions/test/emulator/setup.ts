// Runs before any emulator test file is imported (and so before the Admin SDK
// initializes). Refuses to run unless the emulators are active and the
// project is a demo- project, so these tests can never touch real data.
const required = ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST', 'GCLOUD_PROJECT'] as const;

for (const name of required) {
  if (!process.env[name]) {
    throw new Error(`${name} is not set. Run emulator tests with "npm run test:emulator".`);
  }
}

if (!process.env['GCLOUD_PROJECT']?.startsWith('demo-')) {
  throw new Error('Emulator tests must run against a demo- project ID.');
}

// The emulators need no credentials; skip the Google Cloud metadata-server
// lookup the Admin SDK otherwise attempts (slow, and noisy off Google Cloud).
process.env['METADATA_SERVER_DETECTION'] ??= 'none';
