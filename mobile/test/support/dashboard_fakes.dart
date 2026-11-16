import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:mobile/features/dashboard/domain/dashboard_models.dart';

BusinessDashboard aDashboard({int costed = 1}) => BusinessDashboard(
  businessName: 'Ali Bakes',
  ordersByStatus: const {
    OrderStatus.pendingConfirmation: 2,
    OrderStatus.confirmed: 1,
    OrderStatus.preparing: 0,
    OrderStatus.readyForPickup: 0,
    OrderStatus.completed: 3,
    OrderStatus.cancelled: 1,
  },
  totalOrders: 7,
  completedCount: 3,
  estimatedRevenueSen: 6600,
  recordedCostSen: 2700,
  costedCompletedCount: costed,
  estimatedProfitSen: 3900,
  topProducts: const [
    TopProduct(
      listingId: 'p1',
      title: 'Brownie box',
      units: 3,
      revenueSen: 3400,
    ),
    TopProduct(
      listingId: 'p2',
      title: 'Cookie jar',
      units: 4,
      revenueSen: 3200,
    ),
  ],
  stock: const [
    StockItem(
      listingId: 'p2',
      title: 'Cookie jar',
      status: ListingStatus.sold,
      stock: 0,
      hidden: false,
    ),
    StockItem(
      listingId: 'p1',
      title: 'Brownie box',
      status: ListingStatus.available,
      stock: 4,
      hidden: false,
    ),
  ],
  campaigns: [
    CampaignLoad(
      campaignId: 'c1',
      title: 'Raya brownies',
      status: CampaignStatus.open,
      capacity: 10,
      allocatedQty: 2,
      closeAt: DateTime.utc(2026, 11, 23),
    ),
  ],
);

/// Returns [dashboard] and records each requested range.
class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository([BusinessDashboard? dashboard])
    : dashboard = dashboard ?? aDashboard();

  BusinessDashboard dashboard;
  final List<({DateTime? from, DateTime? to})> ranges = [];
  AppFailure? failWith;

  @override
  Future<BusinessDashboard> fetch({DateTime? from, DateTime? to}) async {
    ranges.add((from: from, to: to));
    if (failWith case final f?) throw f;
    return dashboard;
  }
}
