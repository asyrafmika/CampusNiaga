/// Route paths, defined once.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/welcome';
  static const String login = '/login';
  static const String signUp = '/sign-up';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String verifyEmail = '/verify-email';
  static const String notEligible = '/not-eligible';
  static const String suspended = '/suspended';
  static const String home = '/';

  /// Screens a signed-out visitor may open.
  static const Set<String> public = {onboarding, login, signUp, forgotPassword};

  /// Screens that only make sense before a user is allowed in. An allowed user
  /// who lands on one is sent home.
  static const Set<String> gates = {
    splash,
    ...public,
    resetPassword,
    verifyEmail,
    notEligible,
    suspended,
  };
}
