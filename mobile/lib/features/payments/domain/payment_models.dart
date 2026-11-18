import '../../../core/domain/payment.dart';

/// Where a buyer pays: a bank account, a QR code, or both.
class PaymentDetails {
  const PaymentDetails({
    this.bankName,
    this.accountName,
    this.accountNumber,
    this.qrPath,
  });

  final String? bankName;
  final String? accountName;
  final String? accountNumber;

  /// In the private `payment-qr` bucket.
  final String? qrPath;

  bool get hasBank => accountNumber != null;
}

/// The signed-in student's saved details: their own and, for an approved
/// business, the business's (used for its orders instead).
class SavedPaymentDetails {
  const SavedPaymentDetails({this.personal, this.business});

  final PaymentDetails? personal;
  final PaymentDetails? business;
}

/// The payment page (`get_payment`).
class PaymentView {
  const PaymentView({
    required this.id,
    required this.iAmBuyer,
    required this.itemTitle,
    required this.qty,
    required this.sellerName,
    required this.amountSen,
    required this.status,
    required this.dueAt,
    this.orderId,
    this.reservationId,
    this.proofPath,
    this.submittedAt,
    this.decidedAt,
    this.rejectReason,
    this.payTo,
  });

  final String id;
  final String? orderId;
  final String? reservationId;
  final bool iAmBuyer;
  final String itemTitle;
  final int qty;

  /// The business's name for an order, the seller's for a reservation.
  final String sellerName;
  final int amountSen;
  final PaymentStatus status;
  final DateTime dueAt;

  /// In the private `payment-proofs` bucket.
  final String? proofPath;
  final DateTime? submittedAt;
  final DateTime? decidedAt;
  final String? rejectReason;

  /// Only the buyer gets it, and only while the payment is open.
  final PaymentDetails? payTo;
}

/// Form checks for payment details and decisions, mirroring
/// `set_payment_details` and `review_payment`. The database checks again.
abstract final class PaymentRules {
  static const Duration proofWindow = Duration(minutes: 30);

  /// Spaces and dashes are how people write account numbers; the database
  /// stores digits.
  static String normaliseAccountNumber(String value) =>
      value.replaceAll(RegExp(r'[\s-]'), '');

  static String? bankName(String? value) {
    final length = (value ?? '').trim().length;
    if (length == 0) return null;
    if (length < 2 || length > 60) return 'Use 2 to 60 characters.';
    return null;
  }

  static String? accountName(String? value) {
    final length = (value ?? '').trim().length;
    if (length == 0) return null;
    if (length < 2 || length > 80) return 'Use 2 to 80 characters.';
    return null;
  }

  static String? accountNumber(String? value) {
    final digits = normaliseAccountNumber((value ?? '').trim());
    if (digits.isEmpty) return null;
    if (!RegExp(r'^\d{6,20}$').hasMatch(digits)) {
      return 'An account number has 6 to 20 digits.';
    }
    return null;
  }

  /// Why the details as a whole can't be saved, or `null`. Saving with
  /// nothing at all is allowed: it removes them.
  static String? together({
    required String bankName,
    required String accountName,
    required String accountNumber,
  }) {
    final filled = [
      bankName,
      accountName,
      accountNumber,
    ].where((v) => v.trim().isNotEmpty).length;
    if (filled != 0 && filled != 3) {
      return 'Give the bank, the account holder’s name and the account '
          'number together.';
    }
    return null;
  }

  static String? rejectReason(String? value) {
    final length = (value ?? '').trim().length;
    if (length == 0) return 'Say why, so the buyer knows what to do.';
    if (length > 200) return 'Keep it under 200 characters.';
    return null;
  }

  /// "29 min left", "Under a minute left", or `null` once it has passed.
  static String? timeLeft(DateTime dueAt, DateTime now) {
    final left = dueAt.difference(now);
    if (left <= Duration.zero) return null;
    if (left < const Duration(minutes: 1)) return 'Under a minute left';
    return '${left.inMinutes} min left';
  }

  /// A buyer may back out until they have sent proof; after that the seller
  /// cancels (and refunds). Mirrors `resolve_reservation` / `transition_order`.
  static bool buyerMayCancel(PaymentSummary? payment) =>
      payment == null ||
      (payment.status != PaymentStatus.submitted &&
          payment.status != PaymentStatus.accepted);
}
