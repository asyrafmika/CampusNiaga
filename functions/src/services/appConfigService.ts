import { logger } from 'firebase-functions/v2';
import { z } from 'zod';
import {
  DEFAULT_STUDENT_EMAIL_DOMAINS,
  type StudentEligibilityConfig,
} from '../domain/studentEligibility';
import { COLLECTIONS } from '../domain/types';
import { db } from '../shared/firebase';

const APP_CONFIG_DOC = 'app';

const StudentEligibilityConfigSchema = z.object({
  studentEmailDomains: z.array(z.string().min(1)).min(1).default([...DEFAULT_STUDENT_EMAIL_DOMAINS]),
  testAllowlist: z.array(z.string()).default([]),
});

/**
 * Reads the student-gate settings from config/app. A missing document uses
 * the defaults; a malformed one is logged and also falls back to the defaults,
 * so a bad edit can't open the gate to other domains.
 */
export async function getStudentEligibilityConfig(): Promise<StudentEligibilityConfig> {
  const snap = await db.collection(COLLECTIONS.config).doc(APP_CONFIG_DOC).get();
  const parsed = StudentEligibilityConfigSchema.safeParse(snap.data() ?? {});
  if (parsed.success) return parsed.data;

  logger.warn('config/app is malformed; using default student-gate settings', {
    issues: parsed.error.issues.map((issue) => issue.path.map(String).join('.')),
  });
  return { studentEmailDomains: DEFAULT_STUDENT_EMAIL_DOMAINS, testAllowlist: [] };
}
