import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/features/marketplace/data/marketplace_mappers.dart';

void main() {
  test('maps a listing_card row', () {
    final listing = listingFromRow({
      'id': 'l1',
      'owner_id': 'u2',
      'seller_name': 'Siti',
      'mode': 'personal',
      'title': 'Desk lamp',
      'description': 'Bright',
      'category': 'Hostel Essentials',
      'price_sen': 1500,
      'condition': 'like_new',
      'photo_paths': ['u2/l1/1.jpg', 'u2/l1/2.jpg'],
      'stock': 3,
      'pickup_area': 'Aman',
      'status': 'available',
      'created_at': '2026-11-16T08:00:00+00:00',
    });
    expect(listing.sellerName, 'Siti');
    expect(listing.priceSen, 1500);
    expect(listing.condition, ListingCondition.likeNew);
    expect(listing.coverPhoto, 'u2/l1/1.jpg');
    expect(listing.stock, 3);
    expect(listing.hidden, isFalse);
  });

  test('maps an own listing row with hidden and no seller name', () {
    final listing = listingFromRow({
      'id': 'l1',
      'owner_id': 'u1',
      'title': 'Lamp',
      'description': null,
      'category': 'Others',
      'price_sen': 0,
      'condition': 'fair',
      'photo_paths': <String>[],
      'stock': 1,
      'pickup_area': 'Aman',
      'status': 'draft',
      'hidden': true,
      'created_at': '2026-11-16T08:00:00Z',
    });
    expect(listing.sellerName, isNull);
    expect(listing.description, '');
    expect(listing.coverPhoto, isNull);
    expect(listing.hidden, isTrue);
  });

  test('maps a reservation_card row', () {
    final r = reservationFromRow({
      'id': 'r1',
      'listing_id': 'l1',
      'listing_title': 'Lamp',
      'listing_photo': null,
      'pickup_area': 'Aman',
      'price_sen': 1500,
      'qty': 2,
      'pickup_note': null,
      'status': 'accepted',
      'expires_at': '2026-11-23T08:00:00Z',
      'created_at': '2026-11-16T08:00:00Z',
      'updated_at': '2026-11-16T09:00:00Z',
      'i_am_buyer': true,
      'other_party_name': 'Ali',
      'other_party_email': 'ali@student.usm.my',
    });
    expect(r.status, ReservationStatus.accepted);
    expect(r.totalSen, 3000);
    expect(r.otherPartyEmail, 'ali@student.usm.my');
    expect(r.expiresAt, DateTime.utc(2026, 11, 23, 8));
  });

  test('an unknown status is an error, not a guess', () {
    expect(
      () => reservationFromRow({
        'id': 'r1',
        'listing_id': 'l1',
        'listing_title': 'Lamp',
        'pickup_area': 'Aman',
        'price_sen': 1,
        'qty': 1,
        'status': 'refunded',
        'created_at': '2026-11-16T08:00:00Z',
        'i_am_buyer': true,
        'other_party_name': 'Ali',
      }),
      throwsFormatException,
    );
  });
}
