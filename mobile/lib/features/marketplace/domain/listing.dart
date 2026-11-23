import '../../../core/domain/geo_point.dart';
import '../../../core/domain/listing_enums.dart';

/// A listing as the app shows it. [sellerName] comes from the feed and detail
/// functions; it is `null` in My Listings (the seller is the user).
class Listing {
  const Listing({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.category,
    required this.priceSen,
    required this.condition,
    required this.photoPaths,
    required this.stock,
    required this.pickupArea,
    required this.status,
    required this.createdAt,
    this.sellerName,
    this.hidden = false,
    this.mode = ListingMode.personal,
    this.businessId,
    this.businessName,
    this.pickupPin,
  });

  final String id;
  final String ownerId;
  final String? sellerName;
  final String title;
  final String description;
  final String category;
  final int priceSen;
  final ListingCondition condition;
  final List<String> photoPaths;

  /// Units still for sale.
  final int stock;
  final String pickupArea;

  /// Where on the map the seller hands it over, if they pinned it.
  final GeoPoint? pickupPin;
  final ListingStatus status;
  final DateTime createdAt;

  /// Hidden by an administrator (only the owner and admins see it).
  final bool hidden;

  /// A business product is ordered from its storefront; a personal item is
  /// bought with Buy now.
  final ListingMode mode;
  final String? businessId;

  /// The business selling it, for storefront attribution.
  final String? businessName;

  bool get isBusiness => mode == ListingMode.business;

  String? get coverPhoto => photoPaths.isEmpty ? null : photoPaths.first;
}

/// What the owner may do with a listing right now, matching the transitions
/// `set_listing_status` and `upsert_listing` allow.
enum OwnerAction { edit, publish, reopen, markSold, delete }

List<OwnerAction> ownerActionsFor(Listing listing) => switch (listing.status) {
  ListingStatus.draft => const [
    OwnerAction.edit,
    OwnerAction.publish,
    OwnerAction.delete,
  ],
  ListingStatus.available => const [
    OwnerAction.edit,
    OwnerAction.markSold,
    OwnerAction.delete,
  ],
  // Closed before listings could be deleted instead (ADR 0008).
  ListingStatus.closed => const [
    OwnerAction.edit,
    OwnerAction.reopen,
    OwnerAction.delete,
  ],
  // A business product that sold out is restocked by editing its quantity.
  ListingStatus.sold when listing.isBusiness => const [
    OwnerAction.edit,
    OwnerAction.delete,
  ],
  ListingStatus.sold => const [OwnerAction.delete],
  ListingStatus.deleted => const [],
};

/// The status an owner action moves a listing to.
ListingStatus? targetStatusOf(OwnerAction action) => switch (action) {
  OwnerAction.publish || OwnerAction.reopen => ListingStatus.available,
  OwnerAction.delete => ListingStatus.deleted,
  OwnerAction.markSold => ListingStatus.sold,
  OwnerAction.edit => null,
};
