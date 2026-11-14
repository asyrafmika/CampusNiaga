import { describe, expect, it } from 'vitest';

import { hasRole, isStaff, parseAccess, roleLabel, type StaffAccess } from './access';

const base: StaffAccess = { userId: 'u1', email: 'a@usm.my', isReviewer: false, isAdmin: false };

describe('parseAccess', () => {
  it('reads a get_my_access response', () => {
    expect(
      parseAccess({
        user_id: 'u1',
        email: 'a@usm.my',
        is_student: true,
        is_reviewer: true,
        is_admin: false,
        email_confirmed: true,
        account_status: 'active',
      }),
    ).toEqual({ userId: 'u1', email: 'a@usm.my', isReviewer: true, isAdmin: false });
  });

  it.each([null, 'x', { user_id: 'u1' }, { user_id: 'u1', email: 'a', is_reviewer: 'yes', is_admin: false }])(
    'rejects %j',
    (json) => {
      expect(() => parseAccess(json)).toThrow();
    },
  );
});

describe('roles', () => {
  it('treats a student without staff roles as non-staff', () => {
    expect(isStaff(base)).toBe(false);
    expect(hasRole(base, 'reviewer')).toBe(false);
    expect(roleLabel(base)).toBe('No staff role');
  });

  it('lets a reviewer into reviewer pages only', () => {
    const reviewer = { ...base, isReviewer: true };
    expect(hasRole(reviewer, 'reviewer')).toBe(true);
    expect(hasRole(reviewer, 'admin')).toBe(false);
    expect(roleLabel(reviewer)).toBe('Reviewer');
  });

  it('lets an admin into everything', () => {
    const admin = { ...base, isAdmin: true };
    expect(hasRole(admin, 'reviewer')).toBe(true);
    expect(hasRole(admin, 'admin')).toBe(true);
    expect(roleLabel(admin)).toBe('Admin');
  });
});
