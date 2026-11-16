import '../../../../core/domain/business_enums.dart';
import '../../../marketplace/domain/listing.dart';

/// A business's public page (`get_storefront()`).
class Storefront {
  const Storefront({
    required this.business,
    required this.isOwner,
    required this.categories,
    required this.listings,
    required this.campaigns,
  });

  final StoreBusiness business;

  /// The signed-in student owns this business.
  final bool isOwner;
  final List<String> categories;

  /// Its available products.
  final List<Listing> listings;

  /// Its open pre-orders that haven't closed.
  final List<Campaign> campaigns;

  /// The open pre-orders for one product.
  List<Campaign> campaignsFor(String listingId) =>
      campaigns.where((c) => c.listingId == listingId).toList();
}

class StoreBusiness {
  const StoreBusiness({
    required this.id,
    required this.name,
    required this.description,
    required this.pickupDetails,
    required this.status,
    this.logoPath,
    this.ownerName,
  });

  final String id;
  final String name;
  final String description;
  final String pickupDetails;
  final BusinessStatus status;
  final String? logoPath;
  final String? ownerName;
}

/// A pre-order campaign: from the storefront (buyers) or the campaigns
/// table (the owner).
class Campaign {
  const Campaign({
    required this.id,
    required this.listingId,
    required this.title,
    required this.priceSen,
    required this.startAt,
    required this.closeAt,
    required this.capacity,
    required this.allocatedQty,
    required this.pickupDetails,
    required this.status,
    this.perOrderLimit,
    this.listingTitle,
    this.listingPhoto,
  });

  final String id;
  final String listingId;
  final String? listingTitle;
  final String? listingPhoto;
  final String title;
  final int priceSen;
  final DateTime startAt;
  final DateTime closeAt;
  final int capacity;
  final int allocatedQty;
  final int? perOrderLimit;
  final String pickupDetails;
  final CampaignStatus status;

  int get remaining => capacity - allocatedQty;

  /// Open, started, not closed and with places left: what `place_order`
  /// accepts (it checks again).
  bool takesOrdersAt(DateTime now) =>
      status == CampaignStatus.open &&
      !now.isBefore(startAt) &&
      now.isBefore(closeAt) &&
      remaining > 0;

  /// The most one order may take right now.
  int get maxPerOrder {
    final limit = perOrderLimit;
    return limit == null || limit > remaining ? remaining : limit;
  }
}

/// The campaign form's fields.
class CampaignInput {
  const CampaignInput({
    required this.listingId,
    required this.title,
    required this.priceSen,
    required this.startAt,
    required this.closeAt,
    required this.capacity,
    required this.pickupDetails,
    this.perOrderLimit,
  });

  final String listingId;
  final String title;
  final int priceSen;
  final DateTime startAt;
  final DateTime closeAt;
  final int capacity;
  final int? perOrderLimit;
  final String pickupDetails;
}

/// One order as My Orders shows it (`my_orders()`).
class OrderCard {
  const OrderCard({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.businessId,
    required this.businessName,
    required this.qty,
    required this.unitPriceSen,
    required this.totalSen,
    required this.status,
    required this.collectionDetails,
    required this.createdAt,
    required this.iAmBuyer,
    required this.otherPartyName,
    this.listingPhoto,
    this.campaignId,
    this.campaignTitle,
    this.buyerNote,
    this.cancelledBy,
    this.completedAt,
    this.otherPartyEmail,
  });

  final String id;
  final String listingId;
  final String listingTitle;
  final String? listingPhoto;
  final String businessId;
  final String businessName;
  final String? campaignId;
  final String? campaignTitle;
  final int qty;
  final int unitPriceSen;
  final int totalSen;
  final OrderStatus status;
  final String? buyerNote;
  final String collectionDetails;

  /// `buyer` or `seller`, once cancelled.
  final String? cancelledBy;
  final DateTime createdAt;
  final DateTime? completedAt;
  final bool iAmBuyer;
  final String otherPartyName;

  /// Shared only from confirmation until completion.
  final String? otherPartyEmail;

  bool get isPreOrder => campaignId != null;
}

enum OrderSide {
  buying('buying'),
  selling('selling');

  const OrderSide(this.wireName);

  final String wireName;
}

/// What `transition_order` accepts.
enum OrderAction {
  confirm('confirm', 'Confirm'),
  prepare('prepare', 'Start preparing'),
  ready('ready', 'Ready for pickup'),
  complete('complete', 'Mark collected'),
  cancel('cancel', 'Cancel order');

  const OrderAction(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// The order state machine, mirroring `transition_order`.
abstract final class OrderRules {
  /// The seller's next step from [status], or `null` when there is none.
  static OrderAction? nextStep(OrderStatus status) => switch (status) {
    OrderStatus.pendingConfirmation => OrderAction.confirm,
    OrderStatus.confirmed => OrderAction.prepare,
    OrderStatus.preparing => OrderAction.ready,
    OrderStatus.readyForPickup => OrderAction.complete,
    OrderStatus.completed || OrderStatus.cancelled => null,
  };

  /// Either side may cancel until the order is completed.
  static bool canCancel(OrderStatus status) => status.isActive;

  /// The actions [order] offers to the signed-in student.
  static List<OrderAction> actionsFor(OrderCard order) => [
    if (!order.iAmBuyer) ?nextStep(order.status),
    if (canCancel(order.status)) OrderAction.cancel,
  ];
}

/// Campaign and storefront form checks, mirroring `upsert_campaign` and
/// `update_storefront`. The database checks everything again.
abstract final class StoreRules {
  static const int maxCapacity = 10000;

  static String? title(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 3) return 'Use at least 3 characters.';
    if (length > 80) return 'Keep it under 80 characters.';
    return null;
  }

  static String? capacity(String? value) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n < 1 || n > maxCapacity) {
      return 'Enter 1 to $maxCapacity.';
    }
    return null;
  }

  /// Empty means no limit; otherwise 1 to the capacity.
  static String? perOrderLimit(String? value, int? capacity) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final n = int.tryParse(text);
    if (n == null || n < 1) return 'Enter a number, or leave it empty.';
    if (capacity != null && n > capacity) return 'Can’t be above the capacity.';
    return null;
  }

  static String? pickupDetails(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 5) return 'Where and when do buyers collect?';
    if (length > 200) return 'Keep it under 200 characters.';
    return null;
  }

  static String? description(String? value) =>
      (value ?? '').trim().length > 1000
      ? 'Keep it under 1,000 characters.'
      : null;

  /// Why the dates don't work, or `null`.
  static String? dates(DateTime startAt, DateTime closeAt, DateTime now) {
    if (!closeAt.isAfter(startAt)) return 'It must close after it opens.';
    if (!closeAt.isAfter(now)) return 'The closing time must be in the future.';
    return null;
  }

  /// The campaign actions allowed from [status], mirroring
  /// `set_campaign_status`.
  static List<CampaignStatus> nextStatuses(CampaignStatus status) =>
      switch (status) {
        CampaignStatus.draft => const [
          CampaignStatus.open,
          CampaignStatus.closed,
        ],
        CampaignStatus.open => const [CampaignStatus.closed],
        CampaignStatus.closed => const [],
      };
}
