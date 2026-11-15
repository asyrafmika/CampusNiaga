import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_failure.dart';

/// Runs a Supabase call and turns its failures into [AppFailure]s, so the
/// rest of the app never sees Supabase exception types.
Future<T> guardSupabase<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on PostgrestException catch (e) {
    // Signed out or not permitted at all (no grant): SQL state 42501.
    if (e.code == '42501') {
      throw const AppFailure(
        AppFailureReason.forbidden,
        "You don't have access to that.",
      );
    }
    throw AppFailure.fromServer(details: e.details, message: e.message);
  } on StorageException catch (e) {
    final status = e.statusCode;
    if (status == '413') {
      throw const AppFailure(
        AppFailureReason.invalidInput,
        'That photo is too large. Use one under 5 MB.',
      );
    }
    if (status == '415' || status == '422') {
      throw const AppFailure(
        AppFailureReason.invalidInput,
        'Use a JPEG, PNG or WebP photo.',
      );
    }
    throw AppFailure.unknownFailure;
  } on SocketException {
    throw AppFailure.networkFailure;
  } on TimeoutException {
    throw AppFailure.networkFailure;
  } on AuthRetryableFetchException {
    throw AppFailure.networkFailure;
  }
}
