import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../business/store/presentation/store_providers.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../marketplace/domain/listing_input.dart';
import '../../marketplace/presentation/marketplace_providers.dart';
import '../data/payment_repository.dart';
import '../domain/payment_models.dart';

final myPaymentDetailsProvider =
    FutureProvider.autoDispose<SavedPaymentDetails>(
      (ref) => ref.watch(paymentRepositoryProvider).mine(),
    );

/// Whether the seller of a listing takes transfers.
final acceptsTransferProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, listingId) =>
      ref.watch(paymentRepositoryProvider).acceptsTransfer(listingId),
);

final paymentProvider = FutureProvider.autoDispose.family<PaymentView, String>(
  (ref, paymentId) => ref.watch(paymentRepositoryProvider).payment(paymentId),
);

/// Every payment change. Each method calls the database, then refreshes what
/// shows the payment or the stock it holds. Failures are thrown as
/// `AppFailure`.
class PaymentActions {
  PaymentActions(this._ref);

  final Ref _ref;

  PaymentRepository get _payments => _ref.read(paymentRepositoryProvider);

  Future<void> saveDetails({
    required bool forBusiness,
    required String bankName,
    required String accountName,
    required String accountNumber,
    String? keptQrPath,
    NewPhoto? newQr,
    String? previousQrPath,
  }) async {
    await _payments.saveDetails(
      forBusiness: forBusiness,
      bankName: bankName,
      accountName: accountName,
      accountNumber: accountNumber,
      keptQrPath: keptQrPath,
      newQr: newQr,
      previousQrPath: previousQrPath,
    );
    _ref
      ..invalidate(myPaymentDetailsProvider)
      ..invalidate(acceptsTransferProvider);
  }

  Future<void> submitProof(String paymentId, NewPhoto photo) async {
    await _payments.submitProof(paymentId, photo);
    _refresh(paymentId);
  }

  Future<void> review(
    String paymentId, {
    required bool accept,
    String? reason,
  }) async {
    await _payments.review(paymentId, accept: accept, reason: reason);
    _refresh(paymentId);
  }

  void _refresh(String paymentId) {
    _ref
      ..invalidate(paymentProvider(paymentId))
      ..invalidate(myOrdersProvider)
      ..invalidate(myReservationsProvider)
      ..invalidate(listingDetailProvider)
      ..invalidate(myListingsProvider)
      ..invalidate(storefrontProvider)
      ..invalidate(myCampaignsProvider)
      ..invalidate(dashboardProvider)
      ..invalidate(feedProvider);
  }
}

final paymentActionsProvider = Provider<PaymentActions>(PaymentActions.new);
