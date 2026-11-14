/// Form checks for a quick answer on the screen. The server enforces its own
/// rules; these only save a round trip. Each returns an error message, or
/// `null` when the value is fine (the `FormField.validator` convention).
abstract final class AuthValidators {
  static const int minPasswordLength = 8;

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email.';
    if (!_email.hasMatch(email)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password.';
    return null;
  }

  static String? newPassword(String? value) {
    if (value == null || value.isEmpty) return 'Choose a password.';
    if (value.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value != password) return 'The passwords do not match.';
    return null;
  }

  /// Same limits as the database (`profiles.name`).
  static String? name(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your name.';
    if (name.length > 60) return 'Use at most 60 characters.';
    return null;
  }
}
