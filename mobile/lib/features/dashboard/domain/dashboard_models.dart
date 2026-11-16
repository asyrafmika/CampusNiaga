import '../../../core/domain/business_enums.dart';
import '../../../core/domain/listing_enums.dart';

/// The business's own figures for a date range (`business_dashboard()`).
/// Revenue and profit are estimated / self-reported: no payment is taken or
/// verified in CampusNiaga.
class BusinessDashboard {
  const BusinessDashboard({
    required this.businessName,
    required this.ordersByStatus,
    required this.totalOrders,
    required this.completedCount,
    required this.estimatedRevenueSen,
    required this.recordedCostSen,
    required this.costedCompletedCount,
    required this.estimatedProfitSen,
    required this.topProducts,
    required this.stock,
    required this.campaigns,
  });

  final String businessName;

  /// Orders placed in the range, for every status (zeros included).
  final Map<OrderStatus, int> ordersByStatus;
  final int totalOrders;

  /// Orders completed in the range, and their figures.
  final int completedCount;
  final int estimatedRevenueSen;
  final int recordedCostSen;
  final int costedCompletedCount;
  final int estimatedProfitSen;
  final List<TopProduct> topProducts;
  final List<StockItem> stock;
  final List<CampaignLoad> campaigns;

  /// Completed orders without a recorded cost, so profit may be overstated.
  int get uncostedCompletedCount => completedCount - costedCompletedCount;
}

class TopProduct {
  const TopProduct({
    required this.listingId,
    required this.title,
    required this.units,
    required this.revenueSen,
  });

  final String listingId;
  final String title;
  final int units;
  final int revenueSen;
}

class StockItem {
  const StockItem({
    required this.listingId,
    required this.title,
    required this.status,
    required this.stock,
    required this.hidden,
  });

  final String listingId;
  final String title;
  final ListingStatus status;
  final int stock;
  final bool hidden;
}

class CampaignLoad {
  const CampaignLoad({
    required this.campaignId,
    required this.title,
    required this.status,
    required this.capacity,
    required this.allocatedQty,
    required this.closeAt,
  });

  final String campaignId;
  final String title;
  final CampaignStatus status;
  final int capacity;
  final int allocatedQty;
  final DateTime closeAt;

  /// Share of the capacity already ordered, 0 to 1.
  double get filled => capacity == 0 ? 0 : allocatedQty / capacity;
}

/// The date filter's choices.
enum DashboardPeriod {
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  thisMonth('This month'),
  allTime('All time');

  const DashboardPeriod(this.label);

  final String label;

  /// The range sent to the database: `from` inclusive, `to` exclusive;
  /// `null` means unbounded. [now] is the phone's local time.
  ({DateTime? from, DateTime? to}) rangeAt(DateTime now) => switch (this) {
    DashboardPeriod.last7Days => (
      from: DateTime(now.year, now.month, now.day - 6),
      to: null,
    ),
    DashboardPeriod.last30Days => (
      from: DateTime(now.year, now.month, now.day - 29),
      to: null,
    ),
    DashboardPeriod.thisMonth => (
      from: DateTime(now.year, now.month),
      to: DateTime(now.year, now.month + 1),
    ),
    DashboardPeriod.allTime => (from: null, to: null),
  };
}
