/**
 * What the signed-in user may do, from `get_my_access()` (docs/api-contracts.md).
 * There is one staff role, the HDC administrator (ADR 0009).
 */
export type StaffAccess = {
  userId: string;
  email: string;
  isAdmin: boolean;
};

/** Only HDC administrators use the dashboard. */
export function isStaff(access: StaffAccess): boolean {
  return access.isAdmin;
}

export function roleLabel(access: StaffAccess): string {
  return access.isAdmin ? 'HDC Administrator' : 'No staff role';
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
    typeof json['is_admin'] === 'boolean'
  ) {
    return {
      userId: json['user_id'],
      email: json['email'],
      isAdmin: json['is_admin'],
    };
  }
  throw new Error('Unexpected get_my_access response');
}
