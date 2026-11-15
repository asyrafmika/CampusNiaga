import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/storage/preferences.dart';
import 'package:mobile/features/auth/data/auth_repository.dart';
import 'package:mobile/features/auth/domain/auth_failure.dart';
import 'package:mobile/features/auth/domain/user_access.dart';
import 'package:mobile/features/auth/presentation/sign_in_screen.dart';
import 'package:mobile/features/auth/presentation/sign_up_screen.dart';
import 'package:mobile/features/auth/presentation/splash_screen.dart';
import 'package:mobile/features/onboarding/presentation/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const student = UserAccess(
  userId: 'u1',
  email: 'ali@student.usm.my',
  emailConfirmed: true,
  accountStatus: AccountStatus.active,
  isStudent: true,
  isReviewer: false,
  isAdmin: false,
);

/// Records calls instead of talking to Supabase.
class FakeAuthRepository implements AuthRepository {
  AuthFailure? failWith;
  final List<String> calls = [];

  Future<void> _record(String call) async {
    calls.add(call);
    if (failWith case final failure?) throw failure;
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      _record('signIn $email');

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) => _record('signUp $name $email');

  @override
  Future<void> sendPasswordReset(String email) => _record('reset $email');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs the whole app with access and auth replaced, so screens and
/// navigation can be tested without Supabase.
Future<FakeAuthRepository> pumpApp(
  WidgetTester tester,
  Future<UserAccess?> Function() lookup, {
  bool onboardingSeen = true,
}) async {
  // A Pixel 9-sized screen (the default test surface is 800x600).
  tester.view.physicalSize = const Size(1080, 2424);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({'onboarding_seen': onboardingSeen});
  final preferences = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWithValue(auth),
        userAccessProvider.overrideWith((ref) => lookup()),
      ],
      child: const CampusNiagaApp(),
    ),
  );
  return auth;
}

void main() {
  testWidgets('shows the splash screen while access is looked up', (
    tester,
  ) async {
    await pumpApp(tester, () => Completer<UserAccess?>().future);
    await tester.pump();

    expect(find.text('CampusNiaga'), findsOneWidget);
    expect(find.text('BUY. SELL. START YOUR BUSINESS.'), findsOneWidget);
  });

  testWidgets('offers a retry when the lookup fails', (tester) async {
    await pumpApp(tester, () => Future.error(Exception('offline')));
    await tester.pumpAndSettle();

    expect(find.byKey(SplashScreen.retryKey), findsOneWidget);
  });

  testWidgets('first launch shows onboarding, then sign-in', (tester) async {
    await pumpApp(tester, () async => null, onboardingSeen: false);
    await tester.pumpAndSettle();

    expect(find.text('Find campus deals'), findsOneWidget);

    await tester.tap(find.byKey(OnboardingScreen.continueKey));
    await tester.pumpAndSettle();
    expect(find.text('Sell or start a business'), findsOneWidget);

    await tester.tap(find.byKey(OnboardingScreen.continueKey));
    await tester.pumpAndSettle();
    expect(find.text('Collect on campus'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.byKey(OnboardingScreen.continueKey));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back.', findRichText: true), findsOneWidget);
  });

  testWidgets('skip goes straight to sign-in', (tester) async {
    await pumpApp(tester, () async => null, onboardingSeen: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(OnboardingScreen.skipKey));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.', findRichText: true), findsOneWidget);
  });

  testWidgets('a returning visitor goes straight to sign-in', (tester) async {
    await pumpApp(tester, () async => null);
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.', findRichText: true), findsOneWidget);
    expect(find.text('Find campus deals'), findsNothing);
  });

  testWidgets('sign-in checks the form before calling the server', (
    tester,
  ) async {
    final auth = await pumpApp(tester, () async => null);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SignInScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('sign-in shows the reason it failed', (tester) async {
    final auth = await pumpApp(tester, () async => null)
      ..failWith = AuthFailure.invalidCredentials;
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(SignInScreen.emailKey),
        matching: find.byType(EditableText),
      ),
      'ali@student.usm.my',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(SignInScreen.passwordKey),
        matching: find.byType(EditableText),
      ),
      'wrong-password',
    );
    await tester.tap(find.byKey(SignInScreen.submitKey));
    await tester.pumpAndSettle();

    expect(auth.calls, ['signIn ali@student.usm.my']);
    expect(find.text(AuthFailure.invalidCredentials.message), findsOneWidget);
  });

  testWidgets('create account is its own page, reached from sign-in', (
    tester,
  ) async {
    final auth = await pumpApp(tester, () async => null);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(
      find.text('Join the campus market.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Welcome back.', findRichText: true), findsNothing);
    expect(find.text('Already have an account?'), findsOneWidget);

    Future<void> type(Key key, String text) => tester.enterText(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
      text,
    );
    await type(SignUpScreen.nameKey, 'Ali Bin Abu');
    await type(SignUpScreen.emailKey, 'ali@student.usm.my');
    await type(SignUpScreen.passwordKey, 'Campus#2026');
    await tester.ensureVisible(find.byKey(SignUpScreen.submitKey));
    await tester.tap(find.byKey(SignUpScreen.submitKey));
    await tester.pumpAndSettle();

    expect(auth.calls, ['signUp Ali Bin Abu ali@student.usm.my']);
    expect(find.text('Check your inbox.', findRichText: true), findsOneWidget);
  });

  testWidgets('create account rejects a password under 8 characters', (
    tester,
  ) async {
    final auth = await pumpApp(tester, () async => null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    Future<void> type(Key key, String text) => tester.enterText(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
      text,
    );
    await type(SignUpScreen.nameKey, 'Ali');
    await type(SignUpScreen.emailKey, 'ali@student.usm.my');
    await type(SignUpScreen.passwordKey, 'short1');
    await tester.ensureVisible(find.byKey(SignUpScreen.submitKey));
    await tester.tap(find.byKey(SignUpScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('forgot password sends a reset link', (tester) async {
    final auth = await pumpApp(tester, () async => null);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(
      find.text('Reset your password.', findRichText: true),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextFormField), 'ali@student.usm.my');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['reset ali@student.usm.my']);
    expect(find.text('Check your inbox.', findRichText: true), findsOneWidget);
  });

  testWidgets('lets a verified USM student in', (tester) async {
    await pumpApp(tester, () async => student);
    await tester.pumpAndSettle();

    expect(find.text('Welcome!'), findsOneWidget);
  });

  testWidgets('stops a non-USM account at the eligibility screen', (
    tester,
  ) async {
    await pumpApp(
      tester,
      () async => const UserAccess(
        userId: 'u2',
        email: 'outsider@gmail.com',
        emailConfirmed: true,
        accountStatus: AccountStatus.active,
        isStudent: false,
        isReviewer: false,
        isAdmin: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CampusNiaga is for USM students'), findsOneWidget);
  });

  testWidgets('stops a suspended student', (tester) async {
    await pumpApp(
      tester,
      () async => const UserAccess(
        userId: 'u1',
        email: 'ali@student.usm.my',
        emailConfirmed: true,
        accountStatus: AccountStatus.suspended,
        isStudent: false,
        isReviewer: false,
        isAdmin: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account suspended'), findsOneWidget);
  });
}
