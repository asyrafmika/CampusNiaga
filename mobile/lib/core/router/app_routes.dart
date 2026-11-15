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

  // Bottom navigation tabs (home is the first).
  static const String search = '/search';
  static const String reservations = '/reservations';
  static const String profile = '/profile';

  // Full-screen pages opened from the tabs.
  static const String sell = '/sell';
  static const String myListings = '/my-listings';
  static String listing(String id) => '/listing/$id';
  static String editListing(String id) => '/listing/$id/edit';
  static String reportListing(String id) => '/listing/$id/report';

  /// The search tab, opened on one category.
  static String searchCategory(String category) =>
      Uri(path: search, queryParameters: {'category': category}).toString();

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
