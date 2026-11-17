import '../../../../core/domain/business_enums.dart';
import '../../../../core/domain/geo_point.dart';
import '../../../marketplace/data/marketplace_mappers.dart';
import '../domain/store_models.dart';

/// Maps `get_storefront()`, `campaigns` rows and `order_card` rows into
/// domain models. Unknown status values throw [FormatException].

DateTime _time(Object? value) => DateTime.parse(value! as String);

DateTime? _timeOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

int _int(Object? value) => (value! as num).toInt();

int? _intOrNull(Object? value) => value == null ? null : (value as num).toInt();

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

Storefront storefrontFromJson(Object? json) {
  final root = _map(json);
  final business = _map(root['business']);
  return Storefront(
    business: StoreBusiness(
      id: business['business_id'] as String,
      name: business['name'] as String,
      description: business['description'] as String? ?? '',
      pickupDetails: business['pickup_details'] as String? ?? '',
      status: BusinessStatus.fromWire(business['status']),
      logoPath: business['logo_path'] as String?,
      ownerName: business['owner_name'] as String?,
      pickupPin: GeoPoint.fromWire(
        business['pickup_lat'],
        business['pickup_lng'],
      ),
    ),
    isOwner: root['is_owner'] as bool? ?? false,
    categories: (root['categories'] as List<dynamic>? ?? const [])
        .map((c) => c as String)
        .toList(),
    listings: rowsOf(root['listings']).map(listingFromRow).toList(),
    campaigns: rowsOf(root['campaigns']).map(campaignFromRow).toList(),
  );
}

/// A campaign from the storefront (`campaign_id`) or the table (`id`).
Campaign campaignFromRow(Map<String, dynamic> row) => Campaign(
  id: (row['campaign_id'] ?? row['id'])! as String,
  listingId: row['listing_id'] as String,
  listingTitle: row['listing_title'] as String?,
  listingPhoto: row['listing_photo'] as String?,
  title: row['title'] as String,
  priceSen: _int(row['price_sen']),
  startAt: _time(row['start_at']),
  closeAt: _time(row['close_at']),
  capacity: _int(row['capacity']),
  allocatedQty: _int(row['allocated_qty']),
  perOrderLimit: _intOrNull(row['per_order_limit']),
  pickupDetails: row['pickup_details'] as String,
  status: CampaignStatus.fromWire(row['status']),
);

OrderCard orderFromRow(Map<String, dynamic> row) => OrderCard(
  id: row['id'] as String,
  listingId: row['listing_id'] as String,
  listingTitle: row['listing_title'] as String,
  listingPhoto: row['listing_photo'] as String?,
  businessId: row['business_id'] as String,
  businessName: row['business_name'] as String,
  campaignId: row['campaign_id'] as String?,
  campaignTitle: row['campaign_title'] as String?,
  qty: _int(row['qty']),
  unitPriceSen: _int(row['unit_price_sen']),
  totalSen: _int(row['total_sen']),
  status: OrderStatus.fromWire(row['status']),
  buyerNote: row['buyer_note'] as String?,
  collectionDetails: row['collection_details'] as String? ?? '',
  cancelledBy: row['cancelled_by'] as String?,
  createdAt: _time(row['created_at']),
  completedAt: _timeOrNull(row['completed_at']),
  iAmBuyer: row['i_am_buyer'] as bool,
  otherPartyName: row['other_party_name'] as String,
  otherPartyEmail: row['other_party_email'] as String?,
  costSen: _intOrNull(row['cost_sen']),
);
