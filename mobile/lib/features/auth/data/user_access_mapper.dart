import '../../../core/domain/account_status.dart';
import '../../../core/domain/business_enums.dart';
import '../domain/user_access.dart';

/// Parses the JSON returned by `get_my_access()` (docs/api-contracts.md).
/// Throws [FormatException] if the shape is not what the contract promises.
/// The business fields (Phase 3) are optional, so an older database still
/// parses.
UserAccess userAccessFromJson(Object? json) {
  if (json case {
    'user_id': final String userId,
    'email': final String email,
    'email_confirmed': final bool emailConfirmed,
    'account_status': final String accountStatus,
    'is_student': final bool isStudent,
    'is_admin': final bool isAdmin,
  }) {
    return UserAccess(
      userId: userId,
      email: email,
      emailConfirmed: emailConfirmed,
      accountStatus: AccountStatus.fromWire(accountStatus),
      isStudent: isStudent,
      isAdmin: isAdmin,
      isBusinessOwner: switch (json['is_business_owner']) {
        final bool owner => owner,
        null => false,
        final other => throw FormatException('Bad is_business_owner: $other'),
      },
      businessStatus: switch (json['business_status']) {
        null => null,
        final status => BusinessStatus.fromWire(status),
      },
    );
  }
  throw FormatException('Unexpected get_my_access response: $json');
}
