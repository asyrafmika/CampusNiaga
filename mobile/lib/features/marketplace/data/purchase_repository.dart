import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/listing_enums.dart';
import '../../../core/domain/payment.dart';
import '../../../core/supabase/supabase_guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/purchase.dart';
import 'marketplace_mappers.dart';

/// Buy now (ADR 0006) and listing reports, through their database functions
/// only.
class PurchaseRepository {
  PurchaseRepository(this._client);

  /// The most `my_purchases` returns at once; unfinished ones come first.
  static const int pageSize = 100;

  final SupabaseClient _client;

  /// Buys and returns the payment's id when paying by transfer.
  Future<String?> buy({
    required String listingId,
    required int qty,
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'buy_item',
      params: {
        'listing_id': listingId,
        'qty': qty,
        'payment_method': paymentMethod.wireName,
      },
    );
    return (result as Map?)?['payment_id'] as String?;
  });

  Future<void> complete(String purchaseId) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'complete_purchase',
      params: {'purchase_id': purchaseId},
    );
  });

  /// A seller gives a [reason], and [relist]s the item or deletes its listing.
  Future<void> cancel(
    String purchaseId, {
    String? reason,
    bool relist = true,
  }) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'cancel_purchase',
      params: {'purchase_id': purchaseId, 'reason': reason, 'relist': relist},
    );
  });

  Future<void> relist(String purchaseId) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'relist_purchase',
      params: {'purchase_id': purchaseId},
    );
  });

  Future<List<PurchaseCard>> mine(PurchaseSide side) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'my_purchases',
      params: {'side': side.wireName, 'page_size': pageSize},
    );
    return rowsOf(result).map(purchaseFromRow).toList();
  });

  Future<void> reportListing({
    required String listingId,
    required ReportReason reason,
    required String details,
  }) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'report_listing',
      params: {
        'listing_id': listingId,
        'reason': reason.wireName,
        'details': details.trim(),
      },
    );
  });
}

final purchaseRepositoryProvider = Provider<PurchaseRepository>(
  (ref) => PurchaseRepository(ref.watch(supabaseClientProvider)),
);
