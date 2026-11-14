import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// One controller per form, so an error on one screen never shows on another.
/// Each exposes the request's progress as an [AsyncValue]; a failure's error
/// is an `AuthFailure`.

class SignInController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> submit({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password),
    );
  }
}

final signInControllerProvider =
    AsyncNotifierProvider.autoDispose<SignInController, void>(
      SignInController.new,
    );

/// Holds the email the confirmation link was sent to, once sign-up succeeds.
class SignUpController extends AsyncNotifier<String?> {
  @override
  FutureOr<String?> build() => null;

  Future<void> submit({
    required String name,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(authRepositoryProvider)
          .signUp(name: name, email: email, password: password);
      return email.trim();
    });
  }
}

final signUpControllerProvider =
    AsyncNotifierProvider.autoDispose<SignUpController, String?>(
      SignUpController.new,
    );

/// Holds the email the reset link was sent to, once sending succeeds.
class ForgotPasswordController extends AsyncNotifier<String?> {
  @override
  FutureOr<String?> build() => null;

  Future<void> submit(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      return email.trim();
    });
  }
}

final forgotPasswordControllerProvider =
    AsyncNotifierProvider.autoDispose<ForgotPasswordController, String?>(
      ForgotPasswordController.new,
    );

class ResetPasswordController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> submit(String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).updatePassword(password),
    );
    if (!state.hasError) ref.read(passwordRecoveryProvider.notifier).finish();
  }
}

final resetPasswordControllerProvider =
    AsyncNotifierProvider.autoDispose<ResetPasswordController, void>(
      ResetPasswordController.new,
    );
