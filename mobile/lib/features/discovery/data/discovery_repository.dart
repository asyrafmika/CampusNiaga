import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../marketplace/data/marketplace_mappers.dart';
import '../domain/discovery_models.dart';

/// Unknown status values throw [FormatException], so a schema change is
/// noticed instead of misread.
ProductRequest requestFromRow(Map<String, dynamic> row) {
  final status = row['status'];
  if (status != 'active' && status != 'closed') {
    throw FormatException('Unknown request status: $status');
  }
  return ProductRequest(
    id: row['id'] as String,
    name: row['name'] as String,
    category: row['category'] as String,
    preferredPriceSen: (row['preferred_price_sen'] as num?)?.toInt(),
    campusArea: row['campus_area'] as String,
    notes: row['notes'] as String?,
    isActive: status == 'active',
    clusterKey: row['cluster_key'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    interestCount: (row['interest_count'] as num).toInt(),
    iAmInterested: row['i_am_interested'] as bool,
    isMine: row['is_mine'] as bool,
  );
}

Opportunity opportunityFromRow(Map<String, dynamic> row) => Opportunity(
  clusterKey: row['cluster_key'] as String,
  category: row['category'] as String,
  headTerm: row['head_term'] as String,
  keywords: (row['keywords'] as List<dynamic>).cast<String>(),
  requestCount: (row['request_ids'] as List<dynamic>).length,
  uniqueInterestCount: (row['unique_interest_count'] as num).toInt(),
  activeSupplyCount: (row['active_supply_count'] as num).toInt(),
  distinctSellerCount: (row['distinct_seller_count'] as num).toInt(),
  medianListedPriceSen: (row['median_listed_price_sen'] as num?)?.toInt(),
  medianPreferredPriceSen: (row['median_preferred_price_sen'] as num?)?.toInt(),
  priceGap: row['price_gap'] as bool,
  score: (row['score'] as num).toInt(),
  reasons: (row['reasons'] as List<dynamic>).cast<String>(),
  insufficientData: row['insufficient_data'] as bool,
  algoVersion: row['algo_version'] as String,
  calculatedAt: DateTime.parse(row['calculated_at'] as String),
);

/// Product requests, interest and opportunities (M4). Requests change only
/// through database functions; opportunities are read-only derived data.
class DiscoveryRepository {
  DiscoveryRepository(this._client);

  static const int pageSize = 20;

  final SupabaseClient _client;

  Future<List<ProductRequest>> requests({
    String? category,
    String? clusterKey,
    bool mine = false,
    int offset = 0,
  }) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'list_product_requests',
      params: {
        'category': category,
        'cluster_key': clusterKey,
        'mine': mine,
        'page_size': pageSize,
        'page_offset': offset,
      },
    );
    return rowsOf(result).map(requestFromRow).toList();
  });

  Future<String> createRequest(RequestInput input) => guardSupabase(() async {
    final notes = input.notes?.trim() ?? '';
    final Object? result = await _client.rpc<Object?>(
      'create_product_request',
      params: {
        'name': input.name.trim(),
        'category': input.category,
        'campus_area': input.campusArea.trim(),
        'preferred_price_sen': input.preferredPriceSen,
        'notes': notes.isEmpty ? null : notes,
      },
    );
    return (result! as Map)['request_id'] as String;
  });

  Future<void> closeRequest(String requestId) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'close_product_request',
      params: {'request_id': requestId},
    );
  });

  /// Returns whether the caller is now interested, and the new count.
  Future<({bool interested, int count})> toggleInterest(String requestId) =>
      guardSupabase(() async {
        final Object? result = await _client.rpc<Object?>(
          'toggle_request_interest',
          params: {'request_id': requestId},
        );
        final map = result! as Map;
        return (
          interested: map['interested'] as bool,
          count: (map['interest_count'] as num).toInt(),
        );
      });

  /// Ranked: score, then the most recent interest, then the cluster.
  Future<List<Opportunity>> opportunities({int offset = 0}) =>
      guardSupabase(() async {
        final List<Map<String, dynamic>> rows = await _client
            .from('opportunities')
            .select(
              'cluster_key, category, head_term, keywords, request_ids, '
              'unique_interest_count, active_supply_count, '
              'distinct_seller_count, median_listed_price_sen, '
              'median_preferred_price_sen, price_gap, score, reasons, '
              'insufficient_data, algo_version, calculated_at',
            )
            .order('score', ascending: false)
            .order('last_interest_at', ascending: false)
            .order('cluster_key')
            .range(offset, offset + pageSize - 1);
        return rows.map(opportunityFromRow).toList();
      });

  Future<Opportunity?> opportunity(String clusterKey) =>
      guardSupabase(() async {
        final Map<String, dynamic>? row = await _client
            .from('opportunities')
            .select(
              'cluster_key, category, head_term, keywords, request_ids, '
              'unique_interest_count, active_supply_count, '
              'distinct_seller_count, median_listed_price_sen, '
              'median_preferred_price_sen, price_gap, score, reasons, '
              'insufficient_data, algo_version, calculated_at',
            )
            .eq('cluster_key', clusterKey)
            .maybeSingle();
        return row == null ? null : opportunityFromRow(row);
      });
}

final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => DiscoveryRepository(ref.watch(supabaseClientProvider)),
);
