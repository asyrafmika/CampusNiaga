/// A rough guide shown while choosing a password. The server enforces its own
/// minimum; this only nudges people towards a better one.
enum PasswordStrength {
  weak('Weak'),
  fair('Fair'),
  strong('Strong');

  const PasswordStrength(this.label);

  final String label;
}

/// Under 8 characters is weak. From 8, each of these adds a point: mixed case,
/// a digit, a symbol, 12+ characters. One point is fair, two or more strong.
PasswordStrength passwordStrength(String password) {
  if (password.length < 8) return PasswordStrength.weak;
  var points = 0;
  if (password.contains(RegExp('[a-z]')) &&
      password.contains(RegExp('[A-Z]'))) {
    points++;
  }
  if (password.contains(RegExp(r'\d'))) points++;
  if (password.contains(RegExp('[^A-Za-z0-9]'))) points++;
  if (password.length >= 12) points++;
  if (points >= 2) return PasswordStrength.strong;
  return points == 1 ? PasswordStrength.fair : PasswordStrength.weak;
}
