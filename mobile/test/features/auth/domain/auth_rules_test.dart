import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/domain/auth_failure.dart';
import 'package:mobile/features/auth/domain/auth_validators.dart';
import 'package:mobile/features/auth/domain/password_strength.dart';

void main() {
  group('AuthValidators.email', () {
    test('accepts a normal email, ignoring spaces around it', () {
      expect(AuthValidators.email(' ali@student.usm.my '), isNull);
    });

    for (final bad in [
      '',
      '   ',
      'ali',
      'ali@',
      '@student.usm.my',
      'a b@c.my',
    ]) {
      test('rejects "$bad"', () {
        expect(AuthValidators.email(bad), isNotNull);
      });
    }
  });

  group('AuthValidators passwords', () {
    test('sign-in only needs something typed', () {
      expect(AuthValidators.password(''), isNotNull);
      expect(AuthValidators.password('x'), isNull);
    });

    test('a new password needs at least 8 characters', () {
      expect(AuthValidators.newPassword('1234567'), isNotNull);
      expect(AuthValidators.newPassword('12345678'), isNull);
    });

    test('the confirmation must match', () {
      expect(AuthValidators.confirmPassword('abc12345', 'abc12345'), isNull);
      expect(AuthValidators.confirmPassword('abc12346', 'abc12345'), isNotNull);
    });
  });

  group('AuthValidators.name', () {
    test('matches the database limits: 1 to 60, not only spaces', () {
      expect(AuthValidators.name('Ali Bin Abu'), isNull);
      expect(AuthValidators.name('   '), isNotNull);
      expect(AuthValidators.name('a' * 60), isNull);
      expect(AuthValidators.name('a' * 61), isNotNull);
    });
  });

  group('AuthFailure.fromCode', () {
    const cases = {
      'invalid_credentials': AuthFailure.invalidCredentials,
      'email_not_confirmed': AuthFailure.emailNotConfirmed,
      'weak_password': AuthFailure.weakPassword,
      'same_password': AuthFailure.samePassword,
      'over_request_rate_limit': AuthFailure.rateLimited,
      'over_email_send_rate_limit': AuthFailure.rateLimited,
      'something_new': AuthFailure.unknown,
    };
    cases.forEach((code, failure) {
      test('$code -> ${failure.name}', () {
        expect(AuthFailure.fromCode(code), failure);
      });
    });

    test('a missing code is unknown', () {
      expect(AuthFailure.fromCode(null), AuthFailure.unknown);
    });
  });

  group('passwordStrength', () {
    const cases = {
      '': PasswordStrength.weak,
      'Ab1!': PasswordStrength.weak,
      'abcdefgh': PasswordStrength.weak,
      'abcdefg1': PasswordStrength.fair,
      'Abcdefgh': PasswordStrength.fair,
      'averylongpassphrase': PasswordStrength.fair,
      'Abcdefg1': PasswordStrength.strong,
      'campus#2026': PasswordStrength.strong,
    };
    cases.forEach((password, expected) {
      test('"$password" is ${expected.label}', () {
        expect(passwordStrength(password), expected);
      });
    });
  });
}
