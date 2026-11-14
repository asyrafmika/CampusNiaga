import '../../../core/domain/account_status.dart';

/// What the signed-in user may do, as reported by `get_my_access()`.
/// The database enforces every rule itself; the app uses this for navigation.
class UserAccess {
  const UserAccess({
    required this.userId,
    required this.email,
    required this.emailConfirmed,
    required this.accountStatus,
    required this.isStudent,
    required this.isReviewer,
    required this.isAdmin,
  });

  final String userId;
  final String email;
  final bool emailConfirmed;
  final AccountStatus accountStatus;
  final bool isStudent;
  final bool isReviewer;
  final bool isAdmin;

  bool get isSuspended => accountStatus == AccountStatus.suspended;
}
