import '../../../core/domain/account_status.dart';
import '../../../core/domain/business_enums.dart';

/// What the signed-in user may do, as reported by `get_my_access()`.
/// The database enforces every rule itself; the app uses this for navigation.
/// `isAdmin` is the HDC administrator, the one staff role (ADR 0009).
class UserAccess {
  const UserAccess({
    required this.userId,
    required this.email,
    required this.emailConfirmed,
    required this.accountStatus,
    required this.isStudent,
    required this.isAdmin,
    this.isBusinessOwner = false,
    this.businessStatus,
  });

  final String userId;
  final String email;
  final bool emailConfirmed;
  final AccountStatus accountStatus;
  final bool isStudent;
  final bool isAdmin;

  /// A verified student with an approved (not suspended) business.
  final bool isBusinessOwner;

  /// The student's business, if they have one; `null` before approval.
  final BusinessStatus? businessStatus;

  bool get isSuspended => accountStatus == AccountStatus.suspended;
}
