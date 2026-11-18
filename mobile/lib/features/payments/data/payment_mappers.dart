import '../../../core/domain/payment.dart';
import '../domain/payment_models.dart';

/// Maps payment rows and `get_payment` JSON into domain models. Unknown
/// status values throw [FormatException].

DateTime? _timeOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// The payment columns of `order_card` / `reservation_card`; `null` for a
/// cash deal.
PaymentSummary? paymentSummaryFromRow(Map<String, dynamic> row) {
  final id = row['payment_id'] as String?;
  if (id == null) return null;
  return PaymentSummary(
    id: id,
    status: PaymentStatus.fromWire(row['payment_status']),
    dueAt: DateTime.parse(row['payment_due_at'] as String),
    rejectReason: row['payment_reject_reason'] as String?,
  );
}

PaymentDetails paymentDetailsFromRow(Map<String, dynamic> row) =>
    PaymentDetails(
      bankName: row['bank_name'] as String?,
      accountName: row['account_name'] as String?,
      accountNumber: row['account_number'] as String?,
      qrPath: row['qr_path'] as String?,
    );

/// Rows of `payment_details` the owner may read: their own and their
/// business's.
SavedPaymentDetails savedDetailsFromRows(List<Map<String, dynamic>> rows) {
  PaymentDetails? personal;
  PaymentDetails? business;
  for (final row in rows) {
    if (row['business_id'] != null) {
      business = paymentDetailsFromRow(row);
    } else {
      personal = paymentDetailsFromRow(row);
    }
  }
  return SavedPaymentDetails(personal: personal, business: business);
}

PaymentView paymentViewFromJson(Object? json) {
  final row = Map<String, dynamic>.from(json! as Map);
  final payTo = row['pay_to'];
  return PaymentView(
    id: row['payment_id'] as String,
    orderId: row['order_id'] as String?,
    reservationId: row['reservation_id'] as String?,
    iAmBuyer: row['i_am_buyer'] as bool,
    itemTitle: row['item_title'] as String,
    qty: (row['qty'] as num).toInt(),
    sellerName: row['seller_name'] as String? ?? '',
    amountSen: (row['amount_sen'] as num).toInt(),
    status: PaymentStatus.fromWire(row['status']),
    dueAt: DateTime.parse(row['due_at'] as String),
    proofPath: row['proof_path'] as String?,
    submittedAt: _timeOrNull(row['submitted_at']),
    decidedAt: _timeOrNull(row['decided_at']),
    rejectReason: row['reject_reason'] as String?,
    payTo: payTo == null
        ? null
        : paymentDetailsFromRow(Map<String, dynamic>.from(payTo as Map)),
  );
}
