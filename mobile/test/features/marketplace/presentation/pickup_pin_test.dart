import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/core/domain/geo_point.dart';
import 'package:mobile/core/widgets/pickup_map.dart';
import 'package:mobile/features/auth/domain/user_access.dart';
import 'package:mobile/features/auth/presentation/profile_screen.dart';
import 'package:mobile/features/business/application/data/application_mappers.dart';
import 'package:mobile/features/business/application/domain/business_application.dart';
import 'package:mobile/features/business/application/presentation/business_application_screen.dart';
import 'package:mobile/features/business/store/data/store_mappers.dart';
import 'package:mobile/features/business/store/presentation/storefront_screen.dart';
import 'package:mobile/features/marketplace/data/marketplace_mappers.dart';
import 'package:mobile/features/marketplace/presentation/listing_detail_screen.dart';

import '../../../support/app_harness.dart';
import '../../../support/business_fakes.dart';
import '../../../support/marketplace_fakes.dart';
import '../../../support/store_fakes.dart';

const tekun = GeoPoint(5.3563, 100.3031);

/// Map pins for pickup spots: the rules, the mapping from the database, and
/// the screens where sellers set them and buyers see them.
void main() {
  group('PickupPinRules', () {
    test('accept Malaysia, edges included, and refuse anywhere else', () {
      expect(PickupPinRules.isValid(tekun), isTrue);
      expect(PickupPinRules.isValid(const GeoPoint(0.8, 99.5)), isTrue);
      expect(PickupPinRules.isValid(const GeoPoint(7.5, 119.5)), isTrue);
      expect(PickupPinRules.isValid(const GeoPoint(0.79, 100.3)), isFalse);
      expect(PickupPinRules.isValid(const GeoPoint(5.3, 99.49)), isFalse);
      expect(PickupPinRules.isValid(const GeoPoint(51.5, -0.12)), isFalse);
      expect(PickupPinRules.isValid(const GeoPoint(0, 0)), isFalse);
    });

    test('every USM campus is a valid pin', () {
      for (final campus in UsmCampus.values) {
        expect(
          PickupPinRules.isValid(campus.centre),
          isTrue,
          reason: '$campus',
        );
      }
    });

    test('round to six decimals', () {
      expect(
        PickupPinRules.rounded(const GeoPoint(5.35630000004, 100.30309999996)),
        tekun,
      );
      expect(
        PickupPinRules.rounded(const GeoPoint(5.1234567, 100.9876543)),
        const GeoPoint(5.123457, 100.987654),
      );
    });

    test('read a pin from the wire only when both numbers are there', () {
      expect(GeoPoint.fromWire(5.3563, 100.3031), tekun);
      expect(GeoPoint.fromWire(5, 100), const GeoPoint(5, 100));
      expect(GeoPoint.fromWire(null, null), isNull);
      expect(GeoPoint.fromWire(5.3563, null), isNull);
      expect(GeoPoint.fromWire('5.3', '100.3'), isNull);
    });
  });

  group('mapping', () {
    Map<String, dynamic> listingRow([Map<String, dynamic> extra = const {}]) =>
        {
          'id': 'l1',
          'owner_id': 'u2',
          'title': 'Casio calculator',
          'description': '',
          'category': 'Electronics',
          'price_sen': 3000,
          'condition': 'good',
          'photo_paths': <String>[],
          'stock': 1,
          'pickup_area': 'Tekun lobby',
          'status': 'available',
          'created_at': '2026-11-18T09:00:00Z',
          ...extra,
        };

    test('a listing carries its pin, or none', () {
      expect(
        listingFromRow(
          listingRow({'pickup_lat': 5.3563, 'pickup_lng': 100.3031}),
        ).pickupPin,
        tekun,
      );
      expect(listingFromRow(listingRow()).pickupPin, isNull);
    });

    test('a storefront and the owner’s business carry their pin', () {
      final store = storefrontFromJson({
        'business': {
          'business_id': 'b1',
          'name': 'Ali Bakes',
          'description': '',
          'pickup_details': 'Tekun lobby',
          'pickup_lat': 5.3563,
          'pickup_lng': 100.3031,
          'status': 'approved',
        },
        'is_owner': false,
        'categories': <String>[],
        'listings': [
          listingRow({'pickup_lat': 5.3563, 'pickup_lng': 100.3031}),
        ],
        'campaigns': <Object>[],
      });
      expect(store.business.pickupPin, tekun);
      expect(store.listings.single.pickupPin, tekun);

      final mine = businessFromJson({
        'business_id': 'b1',
        'name': 'Ali Bakes',
        'description': '',
        'pickup_details': 'Tekun lobby',
        'status': 'approved',
        'pickup_lat': null,
        'pickup_lng': null,
      });
      expect(mine.pickupPin, isNull);
    });
  });

  group('screens', () {
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('a buyer sees the pin and gets directions to it', (
      tester,
    ) async {
      final opened = <GeoPoint>[];
      await pumpApp(
        tester,
        () async => student,
        listings: FakeListingRepository(feed: [aListing(pickupPin: tekun)]),
        openDirections: (point) async {
          opened.add(point);
          return true;
        },
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Casio FX-570 calculator').first);

      expect(find.byKey(ListingDetailScreen.pickupMapKey), findsOneWidget);
      await tapVisible(tester, find.byKey(ListingDetailScreen.pickupMapKey));
      expect(find.text('Pickup spot'), findsOneWidget);
      expect(find.text('Desasiswa Tekun'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

      await tester.tap(find.byKey(PickupMapScreen.directionsKey));
      await tester.pumpAndSettle();
      expect(opened, [tekun]);
    });

    testWidgets('it says so when no maps app opens the directions', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () async => student,
        listings: FakeListingRepository(feed: [aListing(pickupPin: tekun)]),
        openDirections: (_) async => false,
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Casio FX-570 calculator').first);
      await tapVisible(tester, find.byKey(ListingDetailScreen.pickupMapKey));
      await tester.tap(find.byKey(PickupMapScreen.directionsKey));
      await tester.pumpAndSettle();

      expect(find.text('No maps app could open this spot.'), findsOneWidget);
    });

    testWidgets('a listing without a pin shows no map', (tester) async {
      await pumpApp(tester, () async => student);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Casio FX-570 calculator').first);

      expect(find.text('Pickup on campus'), findsOneWidget);
      expect(find.byKey(ListingDetailScreen.pickupMapKey), findsNothing);
    });

    testWidgets('a seller pins a new listing at a campus, and buyers will see '
        'it', (tester) async {
      final listings = FakeListingRepository();
      await pumpApp(tester, () async => student, listings: listings);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sell'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('form-title')), 'Desk lamp');
      await tester.tap(find.byKey(const Key('form-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Others').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('form-price')), '15');
      await tester.enterText(
        find.byKey(const Key('form-pickup')),
        'Engineering cafe',
      );

      await tapVisible(tester, find.byKey(PickupPinField.addKey));
      expect(find.text('Pin the pickup spot'), findsOneWidget);
      expect(find.textContaining('never your room'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pin-campus-engineering')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PickupPinPickerScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(find.byKey(PickupPinField.moveKey), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('form-draft')));

      expect(listings.savedPin, UsmCampus.engineering.centre);
      expect(find.byKey(ListingDetailScreen.pickupMapKey), findsOneWidget);
    });

    testWidgets('going back from the picker adds no pin', (tester) async {
      await pumpApp(tester, () async => student);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sell'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.byKey(PickupPinField.addKey));
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      expect(find.byKey(PickupPinField.addKey), findsOneWidget);
      expect(find.byKey(PickupPinField.moveKey), findsNothing);
    });

    testWidgets('a seller removes the pin when editing', (tester) async {
      final listings = FakeListingRepository(
        mine: [
          aListing(id: 'l9', ownerId: meId, title: 'My lamp', pickupPin: tekun),
        ],
      );
      await pumpApp(tester, () async => student, listings: listings);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('My listings'));
      await tapVisible(tester, find.text('My lamp').first);
      await tapVisible(tester, find.text('Edit'));

      expect(find.byKey(PickupPinField.moveKey), findsOneWidget);
      // Closing the picker without choosing keeps the pin.
      await tapVisible(tester, find.byKey(PickupPinField.moveKey));
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byKey(PickupPinField.moveKey), findsOneWidget);

      await tapVisible(tester, find.byKey(PickupPinField.removeKey));
      expect(find.byKey(PickupPinField.addKey), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('form-save')));

      expect(listings.calls.last, startsWith('save l9'));
      expect(listings.savedPin, isNull);
    });

    testWidgets('a business owner pins the storefront pickup spot', (
      tester,
    ) async {
      const owner = UserAccess(
        userId: 'u2',
        email: 'ali@student.usm.my',
        emailConfirmed: true,
        accountStatus: AccountStatus.active,
        isStudent: true,
        isReviewer: false,
        isAdmin: false,
        isBusinessOwner: true,
        businessStatus: BusinessStatus.approved,
      );
      final store = FakeStoreRepository();
      await pumpApp(
        tester,
        () async => owner,
        applications: FakeBusinessApplicationRepository(
          application: anApplication(status: ApplicationStatus.approved),
          business: const MyBusiness(
            id: storeId,
            name: 'Ali Bakes',
            description: 'Fudgy brownies every Friday.',
            pickupDetails: 'Tekun lobby, Fri 6-8pm',
            status: BusinessStatus.approved,
          ),
        ),
        listings: FakeListingRepository(mine: [aProduct()]),
        store: store,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(ProfileScreen.businessKey));
      await tapVisible(tester, find.byKey(BusinessApplicationScreen.storeKey));
      await tapVisible(tester, find.text('Edit storefront'));

      await tapVisible(tester, find.byKey(PickupPinField.addKey));
      await tester.tap(find.byKey(PickupPinPickerScreen.confirmKey));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('storefront-save')));

      expect(store.calls, ['storefront b1 Tekun lobby, Fri 6-8pm']);
      expect(store.savedPin, UsmCampus.main.centre);
    });

    testWidgets('a buyer sees the storefront’s pin', (tester) async {
      await pumpApp(
        tester,
        () async => student,
        listings: FakeListingRepository(feed: [aProduct()]),
        store: FakeStoreRepository(storefront: aStorefront(pickupPin: tekun)),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Brownie box').first);
      await tapVisible(tester, find.byKey(ListingDetailScreen.storefrontKey));

      expect(find.byKey(StorefrontScreen.pickupMapKey), findsOneWidget);
      await tapVisible(tester, find.byKey(StorefrontScreen.pickupMapKey));
      expect(find.text('Tekun lobby, Fri 6-8pm'), findsOneWidget);
      expect(find.byKey(PickupMapScreen.directionsKey), findsOneWidget);
    });
  });
}
