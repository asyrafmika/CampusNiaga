import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/business_enums.dart';
import '../../../core/domain/listing_enums.dart';
import '../../../core/supabase/supabase_guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../marketplace/data/marketplace_mappers.dart';
import '../domain/dashboard_models.dart';

int _int(Object? value) => (value! as num).toInt();

/// Parses `business_dashboard()`. Unknown status values throw
/// [FormatException].
BusinessDashboard dashboardFromJson(Object? json) {
  final root = Map<String, dynamic>.from(json! as Map);
  final byStatus = Map<String, dynamic>.from(root['orders_by_status']! as Map);
  return BusinessDashboard(
    businessName: root['business_name'] as String,
    ordersByStatus: {
      for (final status in OrderStatus.values)
        status: _int(byStatus[status.wireName] ?? 0),
    },
    totalOrders: _int(root['total_orders']),
    completedCount: _int(root['completed_count']),
    estimatedRevenueSen: _int(root['estimated_revenue_sen']),
    recordedCostSen: _int(root['recorded_cost_sen']),
    costedCompletedCount: _int(root['costed_completed_count']),
    estimatedProfitSen: _int(root['estimated_profit_sen']),
    topProducts: rowsOf(root['top_products'])
        .map(
          (r) => TopProduct(
            listingId: r['listing_id'] as String,
            title: r['title'] as String,
            units: _int(r['units']),
            revenueSen: _int(r['revenue_sen']),
          ),
        )
        .toList(),
    stock: rowsOf(root['stock'])
        .map(
          (r) => StockItem(
            listingId: r['listing_id'] as String,
            title: r['title'] as String,
            status: ListingStatus.fromWire(r['status']),
            stock: _int(r['stock']),
            hidden: r['hidden'] as bool? ?? false,
          ),
        )
        .toList(),
    campaigns: rowsOf(root['campaigns'])
        .map(
          (r) => CampaignLoad(
            campaignId: r['campaign_id'] as String,
            title: r['title'] as String,
            status: CampaignStatus.fromWire(r['status']),
            capacity: _int(r['capacity']),
            allocatedQty: _int(r['allocated_qty']),
            closeAt: DateTime.parse(r['close_at'] as String),
          ),
        )
        .toList(),
  );
}

/// The business dashboard (M5). The database works out which business:
/// the caller's own, so no id is ever sent.
class DashboardRepository {
  DashboardRepository(this._client);

  final SupabaseClient _client;

  Future<BusinessDashboard> fetch({DateTime? from, DateTime? to}) =>
      guardSupabase(() async {
        final Object? json = await _client.rpc<Object?>(
          'business_dashboard',
          params: {
            'from_at': from?.toUtc().toIso8601String(),
            'to_at': to?.toUtc().toIso8601String(),
          },
        );
        return dashboardFromJson(json);
      });
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(supabaseClientProvider)),
);
