import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../domain/access_gate.dart';
import '../domain/auth_failure.dart';
import '../domain/user_access.dart';
import 'user_access_mapper.dart';

/// Supabase Auth and the access check, behind one class so screens and tests
/// never touch the Supabase client directly. Failures are thrown as
/// [AuthFailure].
class AuthRepository {
  AuthRepository(this._client);

  /// Where links in confirmation and password-reset emails send the user.
  /// Registered in the Android manifest and in Supabase's redirect URLs.
  static const String redirectUrl = 'campusniaga://auth-callback';

  final SupabaseClient _client;

  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  bool get isSignedIn => _client.auth.currentSession != null;

  Future<UserAccess> fetchAccess() async {
    final Object? json = await _client.rpc<Object?>('get_my_access');
    return userAccessFromJson(json);
  }

  /// The signed-in user's display name, from their own profile row.
  Future<String> fetchMyName() async {
    final id = _client.auth.currentUser?.id;
    if (id == null) return '';
    final Map<String, dynamic> row = await _client
        .from('profiles')
        .select('name')
        .eq('id', id)
        .single();
    return row['name'] as String? ?? '';
  }

  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        ),
      );

  /// Creates the account; Supabase emails a confirmation link. The name is
  /// copied into the profile by the database.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) => _guard(
    () => _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'name': name.trim()},
      emailRedirectTo: redirectUrl,
    ),
  );

  Future<void> sendPasswordReset(String email) => _guard(
    () => _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: redirectUrl,
    ),
  );

  Future<void> updatePassword(String password) =>
      _guard(() => _client.auth.updateUser(UserAttributes(password: password)));

  Future<void> signOut() => _guard(() => _client.auth.signOut());

  Future<void> _guard(Future<Object?> Function() action) async {
    try {
      await action();
    } on AuthRetryableFetchException {
      throw AuthFailure.network;
    } on AuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

/// Every sign-in, sign-out and token refresh.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// The signed-in user's access, looked up again on every auth change;
/// `null` when nobody is signed in.
final userAccessProvider = FutureProvider<UserAccess?>((ref) async {
  ref.watch(authStateProvider);
  final repository = ref.watch(authRepositoryProvider);
  if (!repository.isSignedIn) return null;
  return repository.fetchAccess();
});

/// The signed-in user's name, for greetings and the profile page.
final myNameProvider = FutureProvider<String>((ref) async {
  final access = await ref.watch(userAccessProvider.future);
  if (access == null) return '';
  return ref.watch(authRepositoryProvider).fetchMyName();
});

/// True after the user opens a password-reset link, until they set a new
/// password or sign out.
class PasswordRecovery extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(authStateProvider, (_, next) {
      switch (next.value?.event) {
        case AuthChangeEvent.passwordRecovery:
          state = true;
        case AuthChangeEvent.signedOut:
          state = false;
        default:
          break;
      }
    });
    return false;
  }

  void finish() => state = false;
}

final passwordRecoveryProvider = NotifierProvider<PasswordRecovery, bool>(
  PasswordRecovery.new,
);

/// Which gate the user is at. A failed lookup counts as still loading: the
/// splash screen shows the error and a retry button.
final accessGateProvider = Provider<AccessGate>((ref) {
  if (ref.watch(passwordRecoveryProvider)) return AccessGate.passwordRecovery;
  return switch (ref.watch(userAccessProvider)) {
    AsyncData(:final value) => gateFor(value),
    _ => AccessGate.loading,
  };
});
