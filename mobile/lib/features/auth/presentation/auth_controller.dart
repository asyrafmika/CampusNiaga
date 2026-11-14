import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// Actions the auth screens trigger. Navigation follows automatically from
/// [accessGateProvider], so these only change state.
class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signOut(),
    );
  }

  /// Looks up access again, e.g. after the user confirms their email.
  void recheckAccess() => ref.invalidate(userAccessProvider);
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
