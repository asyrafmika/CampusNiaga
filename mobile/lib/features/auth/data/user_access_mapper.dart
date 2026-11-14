import '../../../core/domain/account_status.dart';
import '../domain/user_access.dart';

/// Parses the JSON returned by `get_my_access()` (docs/api-contracts.md).
/// Throws [FormatException] if the shape is not what the contract promises.
UserAccess userAccessFromJson(Object? json) {
  if (json case {
    'user_id': final String userId,
    'email': final String email,
    'email_confirmed': final bool emailConfirmed,
    'account_status': final String accountStatus,
    'is_student': final bool isStudent,
    'is_reviewer': final bool isReviewer,
    'is_admin': final bool isAdmin,
  }) {
    return UserAccess(
      userId: userId,
      email: email,
      emailConfirmed: emailConfirmed,
      accountStatus: AccountStatus.fromWire(accountStatus),
      isStudent: isStudent,
      isReviewer: isReviewer,
      isAdmin: isAdmin,
    );
  }
  throw FormatException('Unexpected get_my_access response: $json');
}
