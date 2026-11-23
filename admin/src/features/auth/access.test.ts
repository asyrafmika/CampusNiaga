import { describe, expect, it } from 'vitest';

import { isStaff, parseAccess, roleLabel, type StaffAccess } from './access';

const base: StaffAccess = { userId: 'u1', email: 'a@usm.my', isAdmin: false };

describe('parseAccess', () => {
  it('reads a get_my_access response', () => {
    expect(
      parseAccess({
        user_id: 'u1',
        email: 'a@usm.my',
        is_student: true,
        is_admin: true,
        email_confirmed: true,
        account_status: 'active',
      }),
    ).toEqual({ userId: 'u1', email: 'a@usm.my', isAdmin: true });
  });

  it.each([null, 'x', { user_id: 'u1' }, { user_id: 'u1', email: 'a', is_admin: 'yes' }])('rejects %j', (json) => {
    expect(() => parseAccess(json)).toThrow();
  });
});

describe('roles', () => {
  it('treats a student without the administrator role as non-staff', () => {
    expect(isStaff(base)).toBe(false);
    expect(roleLabel(base)).toBe('No staff role');
  });

  it('lets an HDC administrator in', () => {
    const admin = { ...base, isAdmin: true };
    expect(isStaff(admin)).toBe(true);
    expect(roleLabel(admin)).toBe('HDC Administrator');
  });
});
