import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/router/app_routes.dart';
import 'package:mobile/features/auth/domain/access_gate.dart';
import 'package:mobile/features/auth/domain/user_access.dart';

UserAccess access({
  bool emailConfirmed = true,
  AccountStatus status = AccountStatus.active,
  bool isStudent = true,
}) => UserAccess(
  userId: 'u1',
  email: 'ali@student.usm.my',
  emailConfirmed: emailConfirmed,
  accountStatus: status,
  isStudent: isStudent,
  isReviewer: false,
  isAdmin: false,
);

void main() {
  group('gateFor', () {
    test('nobody signed in', () {
      expect(gateFor(null), AccessGate.signedOut);
    });

    test('unconfirmed email comes first', () {
      expect(
        gateFor(access(emailConfirmed: false, isStudent: false)),
        AccessGate.emailUnconfirmed,
      );
    });

    test('a suspended student is suspended, not allowed', () {
      expect(
        gateFor(access(status: AccountStatus.suspended)),
        AccessGate.suspended,
      );
    });

    test('a confirmed non-USM account is not eligible', () {
      expect(gateFor(access(isStudent: false)), AccessGate.notEligible);
    });

    test('a confirmed, active USM student is allowed', () {
      expect(gateFor(access()), AccessGate.allowed);
    });
  });

  group('redirectFor', () {
    // (gate, location, onboarding seen, expected redirect or null to stay)
    const cases = <(AccessGate, String, bool, String?)>[
      (AccessGate.loading, AppRoutes.home, true, AppRoutes.splash),
      (AccessGate.loading, AppRoutes.splash, true, null),
      // First launch: onboarding before anything else.
      (AccessGate.signedOut, AppRoutes.splash, false, AppRoutes.onboarding),
      (AccessGate.signedOut, AppRoutes.login, false, AppRoutes.onboarding),
      (AccessGate.signedOut, AppRoutes.onboarding, false, null),
      // After onboarding: sign-in screens only.
      (AccessGate.signedOut, AppRoutes.onboarding, true, AppRoutes.login),
      (AccessGate.signedOut, AppRoutes.splash, true, AppRoutes.login),
      (AccessGate.signedOut, AppRoutes.home, true, AppRoutes.login),
      (AccessGate.signedOut, AppRoutes.login, true, null),
      (AccessGate.signedOut, AppRoutes.signUp, true, null),
      (AccessGate.signedOut, AppRoutes.forgotPassword, true, null),
      (AccessGate.signedOut, AppRoutes.resetPassword, true, AppRoutes.login),
      // Password-reset link: choose a new password before anything else.
      (
        AccessGate.passwordRecovery,
        AppRoutes.home,
        true,
        AppRoutes.resetPassword,
      ),
      (AccessGate.passwordRecovery, AppRoutes.resetPassword, true, null),
      (
        AccessGate.emailUnconfirmed,
        AppRoutes.home,
        true,
        AppRoutes.verifyEmail,
      ),
      (AccessGate.emailUnconfirmed, AppRoutes.verifyEmail, true, null),
      (AccessGate.suspended, AppRoutes.home, true, AppRoutes.suspended),
      (AccessGate.notEligible, AppRoutes.home, true, AppRoutes.notEligible),
      (AccessGate.notEligible, AppRoutes.notEligible, true, null),
      // Allowed users leave the gate screens for home, and can go anywhere else.
      (AccessGate.allowed, AppRoutes.splash, true, AppRoutes.home),
      (AccessGate.allowed, AppRoutes.login, true, AppRoutes.home),
      (AccessGate.allowed, AppRoutes.signUp, true, AppRoutes.home),
      (AccessGate.allowed, AppRoutes.resetPassword, true, AppRoutes.home),
      (AccessGate.allowed, AppRoutes.home, true, null),
      (AccessGate.allowed, '/some/feature', true, null),
      (AccessGate.allowed, AppRoutes.home, false, null),
    ];

    for (final (gate, location, seen, expected) in cases) {
      test('${gate.name} at $location (onboarding seen: $seen) -> '
          '${expected ?? 'stay'}', () {
        expect(redirectFor(gate, location, onboardingSeen: seen), expected);
      });
    }
  });
}
