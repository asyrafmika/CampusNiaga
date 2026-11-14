/** What the signed-in user may do, from `get_my_access()` (docs/api-contracts.md). */
export type StaffAccess = {
  userId: string;
  email: string;
  isReviewer: boolean;
  isAdmin: boolean;
};

export type StaffRole = 'reviewer' | 'admin';

export function isStaff(access: StaffAccess): boolean {
  return access.isReviewer || access.isAdmin;
}

/** True if [access] satisfies [required]. Admins can do everything reviewers can. */
export function hasRole(access: StaffAccess, required: StaffRole): boolean {
  return required === 'admin' ? access.isAdmin : isStaff(access);
}

export function roleLabel(access: StaffAccess): string {
  if (access.isAdmin) return 'Admin';
  if (access.isReviewer) return 'Reviewer';
  return 'No staff role';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/** Parses the `get_my_access()` result; throws if it isn't the promised shape. */
export function parseAccess(json: unknown): StaffAccess {
  if (
    isRecord(json) &&
    typeof json['user_id'] === 'string' &&
    typeof json['email'] === 'string' &&
    typeof json['is_reviewer'] === 'boolean' &&
    typeof json['is_admin'] === 'boolean'
  ) {
    return {
      userId: json['user_id'],
      email: json['email'],
      isReviewer: json['is_reviewer'],
      isAdmin: json['is_admin'],
    };
  }
  throw new Error('Unexpected get_my_access response');
}
