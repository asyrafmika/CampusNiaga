import { describe, expect, it } from 'vitest';
import { resolveEmulatorTarget } from '../../src/emulatorTarget';

describe('resolveEmulatorTarget', () => {
  it('defaults to the local emulators and the demo project', () => {
    expect(resolveEmulatorTarget({})).toEqual({
      projectId: 'demo-campusniaga',
      firestoreHost: '127.0.0.1:8080',
      authHost: '127.0.0.1:9099',
    });
  });

  it('accepts the values the Firebase CLI sets', () => {
    const target = resolveEmulatorTarget({
      GCLOUD_PROJECT: 'demo-campusniaga',
      FIRESTORE_EMULATOR_HOST: 'localhost:8080',
      FIREBASE_AUTH_EMULATOR_HOST: '[::1]:9099',
    });

    expect(target.firestoreHost).toBe('localhost:8080');
    expect(target.authHost).toBe('[::1]:9099');
  });

  it('refuses the real Firebase project', () => {
    expect(() => resolveEmulatorTarget({ GCLOUD_PROJECT: 'campusniaga-usm' })).toThrow(/only demo- projects/);
  });

  it.each([
    ['FIRESTORE_EMULATOR_HOST', 'firestore.googleapis.com:443'],
    ['FIRESTORE_EMULATOR_HOST', '10.0.0.5:8080'],
    ['FIREBASE_AUTH_EMULATOR_HOST', 'identitytoolkit.googleapis.com:443'],
    ['FIREBASE_AUTH_EMULATOR_HOST', '127.0.0.1.example.com:9099'],
  ])('refuses a non-local %s: %s', (name, value) => {
    expect(() => resolveEmulatorTarget({ [name]: value })).toThrow(/only local emulators/);
  });
});
