import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/domain/business_enums.dart';
import '../../../../core/supabase/supabase_guard.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../marketplace/data/listing_repository.dart';
import '../../../marketplace/data/marketplace_mappers.dart';
import '../../../marketplace/domain/listing_input.dart';
import '../domain/store_models.dart';
import 'store_mappers.dart';

/// Storefronts, pre-order campaigns and orders (M3). Every change goes
/// through a database function; the owner reads their campaigns from the
/// table (Row Level Security limits it to their business).
class StoreRepository {
  StoreRepository(this._client);

  static const int pageSize = 50;
  static const String _logoBucket = 'business-logos';

  final SupabaseClient _client;

  Future<Storefront> storefront(String businessId) => guardSupabase(() async {
    final Object? json = await _client.rpc<Object?>(
      'get_storefront',
      params: {'business_id': businessId},
    );
    return storefrontFromJson(json);
  });

  /// Saves the storefront; uploads [newLogo] first when given.
  Future<void> updateStorefront({
    required String businessId,
    required String description,
    required String pickupDetails,
    String? logoPath,
    NewPhoto? newLogo,
  }) => guardSupabase(() async {
    var path = logoPath;
    if (newLogo != null) {
      path =
          '$businessId/logo_${DateTime.now().millisecondsSinceEpoch}'
          '.${newLogo.extension}';
      await _client.storage
          .from(_logoBucket)
          .uploadBinary(
            path,
            newLogo.bytes,
            fileOptions: FileOptions(contentType: newLogo.contentType),
          );
    }
    await _client.rpc<Object?>(
      'update_storefront',
      params: {
        'description': description.trim(),
        'pickup_details': pickupDetails.trim(),
        'logo_path': path,
      },
    );
    // Best effort: the old logo is no longer used.
    if (newLogo != null && logoPath != null && logoPath != path) {
      try {
        await _client.storage.from(_logoBucket).remove([logoPath]);
      } on Object catch (_) {}
    }
  });

  /// The URL and headers to load a logo with the user's own access.
  PhotoRequest logo(String path) => PhotoRequest(
    '${SupabaseConfig.url}/storage/v1/object/authenticated/$_logoBucket/$path',
    {
      'apikey': SupabaseConfig.publishableKey,
      'Authorization':
          'Bearer ${_client.auth.currentSession?.accessToken ?? ''}',
    },
  );

  /// The owner's campaigns, newest first.
  Future<List<Campaign>> myCampaigns(String businessId) =>
      guardSupabase(() async {
        final List<Map<String, dynamic>> rows = await _client
            .from('campaigns')
            .select(
              'id, listing_id, title, price_sen, start_at, close_at, capacity, '
              'allocated_qty, per_order_limit, pickup_details, status, '
              'listing:listings(title, photo_paths)',
            )
            .eq('business_id', businessId)
            .order('created_at', ascending: false);
        return rows.map((row) {
          final listing = row['listing'] as Map<String, dynamic>?;
          final photos = listing?['photo_paths'] as List<dynamic>?;
          return campaignFromRow({
            ...row,
            'listing_title': listing?['title'],
            'listing_photo': photos == null || photos.isEmpty
                ? null
                : photos.first,
          });
        }).toList();
      });

  /// Creates ([campaignId] null) or edits a campaign; returns its id.
  Future<String> saveCampaign(CampaignInput input, {String? campaignId}) =>
      guardSupabase(() async {
        final Object? result = await _client.rpc<Object?>(
          'upsert_campaign',
          params: {
            'campaign_id': campaignId,
            'listing_id': input.listingId,
            'title': input.title.trim(),
            'price_sen': input.priceSen,
            'start_at': input.startAt.toUtc().toIso8601String(),
            'close_at': input.closeAt.toUtc().toIso8601String(),
            'capacity': input.capacity,
            'per_order_limit': input.perOrderLimit,
            'pickup_details': input.pickupDetails.trim(),
          },
        );
        return (result! as Map)['campaign_id'] as String;
      });

  Future<void> setCampaignStatus(String campaignId, CampaignStatus status) =>
      guardSupabase(() async {
        await _client.rpc<Object?>(
          'set_campaign_status',
          params: {'campaign_id': campaignId, 'new_status': status.wireName},
        );
      });

  /// Orders ready stock, or pre-orders through [campaignId].
  Future<void> placeOrder({
    required String listingId,
    required int qty,
    String? campaignId,
    String? note,
  }) => guardSupabase(() async {
    final trimmed = note?.trim() ?? '';
    await _client.rpc<Object?>(
      'place_order',
      params: {
        'listing_id': listingId,
        'qty': qty,
        'campaign_id': campaignId,
        'buyer_note': trimmed.isEmpty ? null : trimmed,
      },
    );
  });

  Future<void> transitionOrder(String orderId, OrderAction action) =>
      guardSupabase(() async {
        await _client.rpc<Object?>(
          'transition_order',
          params: {'order_id': orderId, 'action': action.wireName},
        );
      });

  /// Records (or, with `null`, clears) the business's cost for an order.
  Future<void> setOrderCost(String orderId, int? costSen) =>
      guardSupabase(() async {
        await _client.rpc<Object?>(
          'set_order_cost',
          params: {'order_id': orderId, 'cost_sen': costSen},
        );
      });

  Future<List<OrderCard>> myOrders(OrderSide side) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'my_orders',
      params: {'side': side.wireName, 'page_size': pageSize},
    );
    return rowsOf(result).map(orderFromRow).toList();
  });
}

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(ref.watch(supabaseClientProvider)),
);
