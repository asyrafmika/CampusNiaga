import '../../../core/router/app_routes.dart';
import 'user_access.dart';

/// Where a user stands before they may use the app. Checked in this order.
enum AccessGate {
  /// Access is still being looked up (or the lookup failed and will retry).
  loading,
  signedOut,

  /// Signed in through a password-reset link: must set a new password first.
  passwordRecovery,
  emailUnconfirmed,
  suspended,

  /// Signed in and confirmed, but not a USM student (or allowlisted).
  notEligible,
  allowed,
}

/// The gate for a finished access lookup; `null` means nobody is signed in.
AccessGate gateFor(UserAccess? access) {
  if (access == null) return AccessGate.signedOut;
  if (!access.emailConfirmed) return AccessGate.emailUnconfirmed;
  if (access.isSuspended) return AccessGate.suspended;
  if (!access.isStudent) return AccessGate.notEligible;
  return AccessGate.allowed;
}

/// The route to send the user to from [location], or `null` to stay.
/// First-time visitors see the onboarding slides before signing in.
String? redirectFor(
  AccessGate gate,
  String location, {
  required bool onboardingSeen,
}) {
  final String? required = switch (gate) {
    AccessGate.loading => AppRoutes.splash,
    AccessGate.signedOut => _signedOutRoute(location, onboardingSeen),
    AccessGate.passwordRecovery => AppRoutes.resetPassword,
    AccessGate.emailUnconfirmed => AppRoutes.verifyEmail,
    AccessGate.suspended => AppRoutes.suspended,
    AccessGate.notEligible => AppRoutes.notEligible,
    AccessGate.allowed => null,
  };

  if (required == null) {
    return AppRoutes.gates.contains(location) ? AppRoutes.home : null;
  }
  return required == location ? null : required;
}

String _signedOutRoute(String location, bool onboardingSeen) {
  if (!onboardingSeen) return AppRoutes.onboarding;
  final isSignInScreen =
      AppRoutes.public.contains(location) && location != AppRoutes.onboarding;
  return isSignInScreen ? location : AppRoutes.login;
}
