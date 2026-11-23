import '../../../core/domain/listing_enums.dart';
import '../../../core/domain/payment.dart';
import '../../payments/domain/payment_models.dart';

enum PurchaseSide {
  buying('buying', 'Buying'),
  selling('selling', 'Selling');

  const PurchaseSide(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// What a party may do to a purchase (ADR 0006).
enum PurchaseAction {
  complete('Complete sale'),
  relist('Relist'),
  cancel('Cancel');

  const PurchaseAction(this.label);

  final String label;
}

/// One row of Purchases (`my_purchases`).
class PurchaseCard {
  const PurchaseCard({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.listingPhoto,
    required this.pickupArea,
    required this.qty,
    required this.unitPriceSen,
    required this.totalSen,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    required this.iAmBuyer,
    required this.otherPartyName,
    this.cancelledBy,
    this.cancelReason,
    this.relistFrom,
    this.payment,
  });

  final String id;
  final String listingId;
  final String listingTitle;
  final String? listingPhoto;
  final String pickupArea;
  final int qty;

  /// Snapshots from the moment of buying.
  final int unitPriceSen;
  final int totalSen;
  final PaymentMethod paymentMethod;
  final PurchaseStatus status;
  final DateTime createdAt;
  final bool iAmBuyer;
  final String otherPartyName;

  /// `buyer`, `seller` or `system`; `null` for some converted reservations.
  final String? cancelledBy;
  final String? cancelReason;

  /// From when the seller may relist an uncollected cash purchase.
  final DateTime? relistFrom;

  /// The transfer payment; `null` when paying cash on pickup.
  final PaymentSummary? payment;

  /// The item chat stays open to someone who bought it. A cancelled
  /// purchase keeps it when money may have been sent, to arrange a refund.
  bool get canChat =>
      status != PurchaseStatus.cancelled ||
      (payment != null && payment!.status != PaymentStatus.expired);
}

/// The rules of Buy now, mirroring the database functions, which check again.
abstract final class PurchaseRules {
  static const int maxReason = 200;

  /// The actions this user may take at [now]: the seller completes at
  /// handover, relists uncollected cash after 24 hours, or cancels; the
  /// buyer cancels until they've sent a receipt.
  static List<PurchaseAction> actionsFor(PurchaseCard p, DateTime now) {
    if (!p.status.isActive) return const [];
    if (p.iAmBuyer) {
      return PaymentRules.buyerMayCancel(p.payment)
          ? const [PurchaseAction.cancel]
          : const [];
    }
    return [
      if (p.status == PurchaseStatus.awaitingHandover) PurchaseAction.complete,
      if (p.relistFrom case final from? when !now.isBefore(from))
        PurchaseAction.relist,
      PurchaseAction.cancel,
    ];
  }

  static String? cancelReason(String? value) {
    final length = (value ?? '').trim().length;
    if (length == 0) return 'Say why, so the buyer knows.';
    if (length > maxReason) return 'Keep it under $maxReason characters.';
    return null;
  }

  /// A short line explaining where the purchase stands, for this user.
  static String explanation(PurchaseCard p) {
    final payment = p.payment?.status;
    return switch (p.status) {
      PurchaseStatus.awaitingPayment when payment == PaymentStatus.submitted =>
        p.iAmBuyer
            ? 'Receipt sent. Waiting for the seller to check it.'
            : 'Check your bank, then accept or reject the payment.',
      PurchaseStatus.awaitingPayment =>
        p.iAmBuyer
            ? 'Pay the seller and send your proof before the time runs out.'
            : 'Waiting for the buyer’s transfer.',
      PurchaseStatus.awaitingHandover
          when p.paymentMethod == PaymentMethod.transfer =>
        p.iAmBuyer
            ? 'Payment confirmed by the seller. Arrange pickup in the chat.'
            : 'Arrange pickup in the chat, then complete the sale.',
      PurchaseStatus.awaitingHandover =>
        p.iAmBuyer
            ? 'It’s yours. Arrange pickup in the chat and pay cash when you '
                  'collect.'
            : 'Take the cash at handover, then complete the sale.',
      PurchaseStatus.completed => 'Completed. Thanks for trading on campus!',
      PurchaseStatus.cancelled => _cancelled(p),
    };
  }

  static String _cancelled(PurchaseCard p) {
    final who = switch (p.cancelledBy) {
      'buyer' => p.iAmBuyer ? 'You cancelled' : 'The buyer cancelled',
      'seller' => p.iAmBuyer ? 'The seller cancelled' : 'You cancelled',
      _ => 'Cancelled',
    };
    return switch (p.cancelReason) {
      final reason? => '$who: $reason',
      null => '$who this purchase.',
    };
  }
}
