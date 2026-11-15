/// Why a database function refused a request. Mirrors the `details` reasons
/// in docs/api-contracts.md, plus [network] and [unknown] for the app.
enum AppFailureReason {
  notVerifiedStudent('NOT_VERIFIED_STUDENT'),
  forbidden('FORBIDDEN'),
  invalidInput('INVALID_INPUT'),
  notFound('NOT_FOUND'),
  invalidTransition('INVALID_TRANSITION'),
  itemUnavailable('ITEM_UNAVAILABLE'),
  capacityFull('CAPACITY_FULL'),
  alreadyExists('ALREADY_EXISTS'),
  rateLimited('RATE_LIMITED'),
  network('NETWORK'),
  unknown('UNKNOWN');

  const AppFailureReason(this.wireName);

  final String wireName;

  static AppFailureReason fromWire(Object? value) => values.firstWhere(
    (reason) => reason.wireName == value,
    orElse: () => unknown,
  );
}

/// A failed request, with a message that can be shown to the user as is.
class AppFailure implements Exception {
  const AppFailure(this.reason, this.message);

  /// The database writes user-facing messages for the reasons it raises; any
  /// other failure gets a generic message.
  factory AppFailure.fromServer({Object? details, String? message}) {
    final reason = AppFailureReason.fromWire(details);
    if (reason == AppFailureReason.unknown ||
        message == null ||
        message.trim().isEmpty) {
      return unknownFailure;
    }
    return AppFailure(reason, message);
  }

  static const AppFailure networkFailure = AppFailure(
    AppFailureReason.network,
    "Couldn't reach CampusNiaga. Check your internet connection.",
  );

  static const AppFailure unknownFailure = AppFailure(
    AppFailureReason.unknown,
    'Something went wrong. Please try again.',
  );

  final AppFailureReason reason;
  final String message;

  /// The message for any error caught by a controller.
  static String messageOf(Object error) =>
      error is AppFailure ? error.message : unknownFailure.message;

  @override
  String toString() => 'AppFailure(${reason.wireName}: $message)';
}
