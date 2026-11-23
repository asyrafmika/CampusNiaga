/// How a buyer pays (ADR 0005). Cash deals have no payment record; a
/// transfer deal has one, with a deadline for the proof.
enum PaymentMethod {
  cash('cash', 'Cash on pickup'),
  transfer('transfer', 'Bank transfer or QR');

  const PaymentMethod(this.wireName, this.label);

  final String wireName;
  final String label;

  static PaymentMethod fromWire(Object? value) {
    for (final m in values) {
      if (m.wireName == value) return m;
    }
    throw FormatException('Unknown payment method: $value');
  }
}

/// `deal_payments.status`.
enum PaymentStatus {
  awaitingProof('awaiting_proof', 'Awaiting payment'),
  submitted('submitted', 'Proof sent'),
  accepted('accepted', 'Payment accepted'),
  rejected('rejected', 'Payment rejected'),
  expired('expired', 'Payment time ran out'),
  cancelled('cancelled', 'Payment cancelled');

  const PaymentStatus(this.wireName, this.label);

  final String wireName;
  final String label;

  /// Still waiting for the buyer's proof or the seller's decision.
  bool get isOpen => this == awaitingProof || this == submitted;

  static PaymentStatus fromWire(Object? value) {
    for (final s in values) {
      if (s.wireName == value) return s;
    }
    throw FormatException('Unknown payment status: $value');
  }
}

/// The payment of an order or purchase, as My Orders and Purchases show it.
class PaymentSummary {
  const PaymentSummary({
    required this.id,
    required this.status,
    required this.dueAt,
    this.rejectReason,
  });

  final String id;
  final PaymentStatus status;

  /// When the proof is due; after it, an unsent payment expires.
  final DateTime dueAt;

  /// Why the seller rejected it.
  final String? rejectReason;
}
