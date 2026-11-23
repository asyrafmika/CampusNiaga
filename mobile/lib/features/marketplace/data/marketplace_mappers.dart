import '../../../core/domain/geo_point.dart';
import '../../../core/domain/listing_enums.dart';
import '../../../core/domain/payment.dart';
import '../../payments/data/payment_mappers.dart';
import '../domain/listing.dart';
import '../domain/purchase.dart';

/// Maps rows from `listing_card`, `listings` and `purchase_card` (JSON from
/// Supabase) into domain models. Unknown status values throw
/// [FormatException], so a schema change is noticed instead of misread.

List<String> _strings(Object? value) =>
    (value as List<dynamic>? ?? const []).map((e) => e as String).toList();

DateTime _time(Object? value) => DateTime.parse(value! as String);

DateTime? _timeOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

Listing listingFromRow(Map<String, dynamic> row) => Listing(
  id: row['id'] as String,
  ownerId: row['owner_id'] as String,
  sellerName: row['seller_name'] as String?,
  title: row['title'] as String,
  description: row['description'] as String? ?? '',
  category: row['category'] as String,
  priceSen: (row['price_sen'] as num).toInt(),
  condition: ListingCondition.fromWire(row['condition']),
  photoPaths: _strings(row['photo_paths']),
  stock: (row['stock'] as num).toInt(),
  pickupArea: row['pickup_area'] as String,
  pickupPin: GeoPoint.fromWire(row['pickup_lat'], row['pickup_lng']),
  status: ListingStatus.fromWire(row['status']),
  createdAt: _time(row['created_at']),
  hidden: row['hidden'] as bool? ?? false,
  mode: row['mode'] == null
      ? ListingMode.personal
      : ListingMode.fromWire(row['mode']),
  businessId: row['business_id'] as String?,
  businessName: row['business_name'] as String?,
);

PurchaseCard purchaseFromRow(Map<String, dynamic> row) => PurchaseCard(
  id: row['id'] as String,
  listingId: row['listing_id'] as String,
  listingTitle: row['listing_title'] as String,
  listingPhoto: row['listing_photo'] as String?,
  pickupArea: row['pickup_area'] as String,
  qty: (row['qty'] as num).toInt(),
  unitPriceSen: (row['unit_price_sen'] as num).toInt(),
  totalSen: (row['total_sen'] as num).toInt(),
  paymentMethod: PaymentMethod.fromWire(row['payment_method']),
  status: PurchaseStatus.fromWire(row['status']),
  cancelledBy: row['cancelled_by'] as String?,
  cancelReason: row['cancel_reason'] as String?,
  relistFrom: _timeOrNull(row['relist_from']),
  createdAt: _time(row['created_at']),
  iAmBuyer: row['i_am_buyer'] as bool,
  otherPartyName: row['other_party_name'] as String,
  payment: paymentSummaryFromRow(row),
);

/// A list of rows from an RPC or a select.
List<Map<String, dynamic>> rowsOf(Object? response) =>
    (response as List<dynamic>? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
