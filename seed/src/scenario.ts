import type { AppClaims } from '../../functions/src/domain/types';

/**
 * Test data for the emulators. Later phases extend this with the handoff's
 * scenario fixture (businesses, listings, the capped pre-order, the brownie
 * requests). These credentials exist only in the emulators.
 */
export const SEED_PASSWORD = 'CampusNiaga#2026';

export interface SeedAccount {
  uid: string;
  email: string;
  name: string;
  claims: AppClaims;
  /** Profile written to users/{uid}; false for accounts the app must refuse. */
  hasProfile: boolean;
}

export const users = {
  studentAli: {
    uid: 'seed-student-ali',
    email: 'ali.test@student.usm.my',
    name: 'Ali (test student)',
    claims: { student: true },
    hasProfile: true,
  },
  studentSiti: {
    uid: 'seed-student-siti',
    email: 'siti.test@student.usm.my',
    name: 'Siti (test student)',
    claims: { student: true },
    hasProfile: true,
  },
  reviewer: {
    uid: 'seed-reviewer',
    email: 'reviewer@campusniaga.test',
    name: 'Test Reviewer',
    claims: { reviewer: true },
    hasProfile: true,
  },
  admin: {
    uid: 'seed-admin',
    email: 'admin@campusniaga.test',
    name: 'Test Admin',
    claims: { admin: true },
    hasProfile: true,
  },
  // Verified, but not a USM email: syncStudentStatus must refuse this account.
  outsider: {
    uid: 'seed-outsider',
    email: 'outsider@example.com',
    name: 'Test Outsider',
    claims: {},
    hasProfile: false,
  },
} as const satisfies Record<string, SeedAccount>;

/** config/app, as documented in docs/data-dictionary.md. */
export const appConfig = {
  studentEmailDomains: ['student.usm.my'],
  testAllowlist: ['examiner@example.com'],
  categories: ['Books', 'Electronics', 'Fashion', 'Food & Beverage', 'Hostel Essentials', 'Stationery', 'Others'],
  maxApplicationDocuments: 5,
  maxUploadBytes: 5_242_880,
};
