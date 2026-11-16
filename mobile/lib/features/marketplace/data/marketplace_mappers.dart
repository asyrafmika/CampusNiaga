import '../../../core/domain/listing_enums.dart';
import '../domain/listing.dart';
import '../domain/reservation.dart';

/// Maps rows from `listing_card`, `listings` and `reservation_card` (JSON from
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
  status: ListingStatus.fromWire(row['status']),
  createdAt: _time(row['created_at']),
  hidden: row['hidden'] as bool? ?? false,
  mode: row['mode'] == null
      ? ListingMode.personal
      : ListingMode.fromWire(row['mode']),
  businessId: row['business_id'] as String?,
  businessName: row['business_name'] as String?,
);

ReservationCard reservationFromRow(Map<String, dynamic> row) => ReservationCard(
  id: row['id'] as String,
  listingId: row['listing_id'] as String,
  listingTitle: row['listing_title'] as String,
  listingPhoto: row['listing_photo'] as String?,
  pickupArea: row['pickup_area'] as String,
  priceSen: (row['price_sen'] as num).toInt(),
  qty: (row['qty'] as num).toInt(),
  pickupNote: row['pickup_note'] as String?,
  status: ReservationStatus.fromWire(row['status']),
  expiresAt: _timeOrNull(row['expires_at']),
  createdAt: _time(row['created_at']),
  iAmBuyer: row['i_am_buyer'] as bool,
  otherPartyName: row['other_party_name'] as String,
  otherPartyEmail: row['other_party_email'] as String?,
);

/// A list of rows from an RPC or a select.
List<Map<String, dynamic>> rowsOf(Object? response) =>
    (response as List<dynamic>? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
