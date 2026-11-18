import 'dart:convert';
import 'dart:typed_data';

import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/payment.dart';
import 'package:mobile/features/marketplace/data/listing_repository.dart';
import 'package:mobile/features/marketplace/data/photo_picker.dart';
import 'package:mobile/features/marketplace/domain/listing_input.dart';
import 'package:mobile/features/payments/data/payment_repository.dart';
import 'package:mobile/features/payments/domain/payment_models.dart';

/// A payment page, as the buyer (default) or the seller sees it.
PaymentView aPayment({
  String id = 'pay1',
  bool iAmBuyer = true,
  PaymentStatus status = PaymentStatus.awaitingProof,
  DateTime? dueAt,
  String? proofPath,
  String? rejectReason,
  PaymentDetails? payTo = const PaymentDetails(
    bankName: 'Maybank',
    accountName: 'Siti Aminah',
    accountNumber: '1234567890',
    qrPath: 'u2/qr.png',
  ),
}) => PaymentView(
  id: id,
  reservationId: 'r1',
  iAmBuyer: iAmBuyer,
  itemTitle: 'Casio FX-570 calculator',
  qty: 1,
  sellerName: 'Siti',
  amountSen: 2500,
  status: status,
  dueAt: dueAt ?? DateTime.now().add(const Duration(minutes: 25)),
  proofPath: proofPath,
  submittedAt: proofPath == null ? null : DateTime.now(),
  rejectReason: rejectReason,
  payTo: iAmBuyer && status.isOpen ? payTo : null,
);

/// In-memory payments; records every call.
class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository({
    SavedPaymentDetails? saved,
    Map<String, PaymentView>? payments,
    this.acceptsTransferResult = false,
  }) : saved = saved ?? const SavedPaymentDetails(),
       payments = payments ?? {};

  SavedPaymentDetails saved;
  Map<String, PaymentView> payments;
  bool acceptsTransferResult;
  final List<String> calls = [];
  AppFailure? failWith;

  void _check() {
    if (failWith case final f?) throw f;
  }

  @override
  Future<SavedPaymentDetails> mine() async => saved;

  @override
  Future<void> saveDetails({
    required bool forBusiness,
    required String bankName,
    required String accountName,
    required String accountNumber,
    String? keptQrPath,
    NewPhoto? newQr,
    String? previousQrPath,
  }) async {
    calls.add(
      'details ${forBusiness ? 'business' : 'personal'} '
      '${bankName.trim()}|${accountName.trim()}|$accountNumber '
      'qr:${newQr != null ? 'new' : keptQrPath ?? 'none'}',
    );
    _check();
  }

  @override
  Future<bool> acceptsTransfer(String listingId) async => acceptsTransferResult;

  @override
  Future<PaymentView> payment(String paymentId) async {
    _check();
    return payments[paymentId] ?? aPayment(id: paymentId);
  }

  @override
  Future<void> submitProof(String paymentId, NewPhoto photo) async {
    calls.add('proof $paymentId ${photo.extension}');
    _check();
  }

  @override
  Future<void> review(
    String paymentId, {
    required bool accept,
    String? reason,
  }) async {
    calls.add(
      'review $paymentId ${accept ? 'accept' : 'reject ${reason ?? ''}'}',
    );
    _check();
  }

  @override
  PhotoRequest image(String bucket, String path) =>
      PhotoRequest('https://example.invalid/$bucket/$path', const {});
}

/// Hands back one tiny PNG, or nothing when [cancel] is set.
class FakePhotoPicker implements PhotoPicker {
  bool cancel = false;
  int picks = 0;

  @override
  Future<NewPhoto?> pick(PhotoSource source) async {
    picks++;
    if (cancel) return null;
    return NewPhoto(bytes: _png, extension: 'png');
  }
}

/// A valid 1x1 PNG, so Image.memory can decode it.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);
