/** Default student email domain; overridable through config/app. */
export const DEFAULT_STUDENT_EMAIL_DOMAINS: readonly string[] = ['student.usm.my'];

export interface StudentEligibilityConfig {
  studentEmailDomains: readonly string[];
  /** Exact emails allowed for FYP evaluation, regardless of domain. */
  testAllowlist: readonly string[];
}

/**
 * True if the email belongs to a configured student domain (exact match, so
 * look-alikes such as `evilstudent.usm.my` or `student.usm.my.example.com`
 * fail) or is on the test allowlist. Comparison is case-insensitive.
 */
export function isEligibleStudentEmail(email: string, config: StudentEligibilityConfig): boolean {
  const normalized = email.trim().toLowerCase();
  const at = normalized.lastIndexOf('@');
  if (at <= 0 || at === normalized.length - 1) return false;

  const domain = normalized.slice(at + 1);
  const domainMatches = config.studentEmailDomains.some((d) => d.trim().toLowerCase() === domain);
  const allowlisted = config.testAllowlist.some((e) => e.trim().toLowerCase() === normalized);
  return domainMatches || allowlisted;
}
