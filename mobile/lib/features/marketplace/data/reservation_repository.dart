import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/listing_enums.dart';
import '../../../core/domain/payment.dart';
import '../../../core/supabase/supabase_guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/reservation.dart';
import 'marketplace_mappers.dart';

/// Reservations and reports, through their database functions only.
class ReservationRepository {
  ReservationRepository(this._client);

  final SupabaseClient _client;

  /// Reserves and returns the payment's id when paying by transfer.
  Future<String?> request({
    required String listingId,
    required int qty,
    String? pickupNote,
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'request_reservation',
      params: {
        'listing_id': listingId,
        'qty': qty,
        'pickup_note': (pickupNote?.trim().isEmpty ?? true)
            ? null
            : pickupNote!.trim(),
        'payment_method': paymentMethod.wireName,
      },
    );
    return (result as Map?)?['payment_id'] as String?;
  });

  Future<void> resolve(String reservationId, ReservationAction action) =>
      guardSupabase(() async {
        await _client.rpc<Object?>(
          'resolve_reservation',
          params: {'reservation_id': reservationId, 'action': action.wireName},
        );
      });

  Future<List<ReservationCard>> mine(ReservationSide side) =>
      guardSupabase(() async {
        final Object? result = await _client.rpc<Object?>(
          'my_reservations',
          params: {'side': side.wireName},
        );
        return rowsOf(result).map(reservationFromRow).toList();
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

final reservationRepositoryProvider = Provider<ReservationRepository>(
  (ref) => ReservationRepository(ref.watch(supabaseClientProvider)),
);
