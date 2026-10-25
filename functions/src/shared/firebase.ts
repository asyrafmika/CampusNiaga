import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

// Single Admin SDK instance. In the emulator the SDK connects to the local
// emulators automatically through the FIRESTORE_EMULATOR_HOST and
// FIREBASE_AUTH_EMULATOR_HOST variables set by the Firebase CLI.
const app = getApps()[0] ?? initializeApp();

export const db = getFirestore(app);
export const adminAuth = getAuth(app);
