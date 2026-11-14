/// Why a sign-in, sign-up or password action failed, in words for the user.
enum AuthFailure implements Exception {
  invalidCredentials('Email or password is incorrect.'),
  emailNotConfirmed(
    'Confirm your email first. Check your inbox (and Junk) for the link.',
  ),
  weakPassword('Choose a stronger password: at least 8 characters.'),
  samePassword('Your new password must be different from the old one.'),
  rateLimited('Too many attempts. Wait a minute and try again.'),
  network("Couldn't reach CampusNiaga. Check your internet connection."),
  unknown('Something went wrong. Please try again.');

  const AuthFailure(this.message);

  final String message;

  /// Maps a Supabase Auth error code to a failure.
  static AuthFailure fromCode(String? code) => switch (code) {
    'invalid_credentials' => invalidCredentials,
    'email_not_confirmed' => emailNotConfirmed,
    'weak_password' => weakPassword,
    'same_password' => samePassword,
    'over_request_rate_limit' || 'over_email_send_rate_limit' => rateLimited,
    _ => unknown,
  };
}
