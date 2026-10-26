import { describe, expect, it } from 'vitest';
import { isEligibleStudentEmail, type StudentEligibilityConfig } from '../../src/domain/studentEligibility';

const config: StudentEligibilityConfig = {
  studentEmailDomains: ['student.usm.my'],
  testAllowlist: ['examiner@gmail.com'],
};

describe('isEligibleStudentEmail', () => {
  it.each([
    'ali@student.usm.my',
    'ALI@Student.USM.my',
    '  ali@student.usm.my  ',
  ])('accepts a student-domain email: %j', (email) => {
    expect(isEligibleStudentEmail(email, config)).toBe(true);
  });

  it.each([
    'ali@gmail.com',
    'staff@usm.my',
    'ali@evilstudent.usm.my',
    'ali@sub.student.usm.my',
    'ali@student.usm.my.example.com',
    'student.usm.my',
    '@student.usm.my',
    'ali@',
    '',
  ])('rejects a non-student email: %j', (email) => {
    expect(isEligibleStudentEmail(email, config)).toBe(false);
  });

  it('accepts an allowlisted test email of any domain, case-insensitively', () => {
    expect(isEligibleStudentEmail('Examiner@Gmail.com', config)).toBe(true);
  });

  it('uses the configured domains instead of a hard-coded one', () => {
    const other: StudentEligibilityConfig = { studentEmailDomains: ['usm.edu.test'], testAllowlist: [] };

    expect(isEligibleStudentEmail('ali@usm.edu.test', other)).toBe(true);
    expect(isEligibleStudentEmail('ali@student.usm.my', other)).toBe(false);
  });
});
