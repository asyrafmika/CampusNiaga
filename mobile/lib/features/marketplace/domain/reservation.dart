import '../../../core/domain/listing_enums.dart';
import '../../../core/domain/payment.dart';
import '../../payments/domain/payment_models.dart';

enum ReservationSide {
  buying('buying', 'Buying'),
  selling('selling', 'Selling');

  const ReservationSide(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// What a party may do to a reservation (`resolve_reservation` actions).
enum ReservationAction {
  accept('accept', 'Accept'),
  decline('decline', 'Decline'),
  collect('collect', 'Mark collected'),
  cancel('cancel', 'Cancel');

  const ReservationAction(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// One row of My Reservations (`my_reservations`).
class ReservationCard {
  const ReservationCard({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.listingPhoto,
    required this.pickupArea,
    required this.priceSen,
    required this.qty,
    required this.pickupNote,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    required this.iAmBuyer,
    required this.otherPartyName,
    required this.otherPartyEmail,
    this.payment,
  });

  final String id;
  final String listingId;
  final String listingTitle;
  final String? listingPhoto;
  final String pickupArea;
  final int priceSen;
  final int qty;
  final String? pickupNote;
  final ReservationStatus status;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final bool iAmBuyer;
  final String otherPartyName;

  /// Shared by the database only once the seller accepts.
  final String? otherPartyEmail;

  /// The transfer payment; `null` when paying cash on pickup.
  final PaymentSummary? payment;

  int get totalSen => priceSen * qty;

  /// The deal chat (ADR 0004) can send while the reservation is accepted
  /// and not overdue, as `open_conversation` checks.
  bool canChatAt(DateTime now) =>
      status == ReservationStatus.accepted &&
      (expiresAt?.isAfter(now) ?? false);
}

/// The actions this user may take, matching what `resolve_reservation`
/// allows: the seller accepts, declines and marks collected; either side can
/// cancel while the reservation is active. A transfer reservation is
/// accepted by checking its payment instead, and a buyer who has sent proof
/// can't cancel on their own.
List<ReservationAction> actionsFor(ReservationCard r) {
  if (r.iAmBuyer) {
    return r.status.isActive && PaymentRules.buyerMayCancel(r.payment)
        ? const [ReservationAction.cancel]
        : const [];
  }
  return switch (r.status) {
    ReservationStatus.requested when r.payment != null => const [
      ReservationAction.decline,
    ],
    ReservationStatus.requested => const [
      ReservationAction.accept,
      ReservationAction.decline,
    ],
    ReservationStatus.accepted => const [
      ReservationAction.collect,
      ReservationAction.cancel,
    ],
    _ => const [],
  };
}

/// A short line explaining where the reservation stands, for this user.
String statusExplanation(ReservationCard r) {
  final payment = r.payment?.status;
  return switch (r.status) {
    ReservationStatus.requested when payment == PaymentStatus.awaitingProof =>
      r.iAmBuyer
          ? 'Pay the seller and send your proof before the time runs out.'
          : 'Waiting for the buyer’s transfer.',
    ReservationStatus.requested when payment == PaymentStatus.submitted =>
      r.iAmBuyer
          ? 'Proof sent. Waiting for the seller to check it.'
          : 'The buyer sent payment proof. Check your bank, then accept or '
                'reject it.',
    ReservationStatus.requested =>
      r.iAmBuyer
          ? 'Waiting for the seller to respond.'
          : 'Accept or decline this request.',
    ReservationStatus.accepted when payment == PaymentStatus.accepted =>
      r.iAmBuyer
          ? 'Paid. Arrange pickup with the seller.'
          : 'Paid. Arrange pickup with the buyer, then mark it collected.',
    ReservationStatus.accepted =>
      r.iAmBuyer
          ? 'Accepted. Contact the seller to arrange pickup and payment.'
          : 'Arrange pickup with the buyer, then mark it collected.',
    ReservationStatus.declined when payment == PaymentStatus.rejected =>
      'The seller rejected the payment: ${r.payment?.rejectReason ?? ''}',
    ReservationStatus.declined => 'The seller declined this request.',
    ReservationStatus.cancelled => 'This reservation was cancelled.',
    ReservationStatus.collected => 'Collected. Thanks for trading on campus!',
    ReservationStatus.expired when payment == PaymentStatus.expired =>
      'The payment wasn’t completed in time, so it expired.',
    ReservationStatus.expired => 'This reservation expired.',
  };
}
