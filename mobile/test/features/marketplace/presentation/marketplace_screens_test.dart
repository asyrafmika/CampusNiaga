import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/features/marketplace/domain/listing_query.dart';
import 'package:mobile/features/marketplace/presentation/listing_detail_screen.dart';
import 'package:mobile/features/marketplace/presentation/search_screen.dart';

import '../../../support/app_harness.dart';
import '../../../support/marketplace_fakes.dart';

/// The marketplace screens, driven through the real router with in-memory
/// repositories.
void main() {
  Future<void> openListing(WidgetTester tester, String title) async {
    // The first card can sit under the bottom bar; scroll it into view.
    await tester.ensureVisible(find.text(title).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
  }

  testWidgets('home shows the feed, and a listing opens its detail page', (
    tester,
  ) async {
    await pumpApp(tester, () async => student);
    await tester.pumpAndSettle();

    expect(find.text('Just listed'), findsOneWidget);
    expect(find.text('RM 25'), findsOneWidget);

    await openListing(tester, 'Casio FX-570 calculator');
    expect(find.text('Pickup on campus'), findsOneWidget);
    expect(find.text('Siti'), findsOneWidget);
    expect(find.text('1 available'), findsOneWidget);
  });

  testWidgets('a buyer reserves an item with a pickup note', (tester) async {
    final reservations = FakeReservationRepository();
    await pumpApp(tester, () async => student, reservations: reservations);
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    await tester.tap(find.byKey(ListingDetailScreen.reserveKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'After 5pm');
    await tester.tap(find.text('Confirm reservation'));
    await tester.pumpAndSettle();

    expect(reservations.calls, ['request l1 x1 After 5pm']);
    expect(find.textContaining('Reserved!'), findsOneWidget);
  });

  testWidgets('a buyer chooses how many units of a multi-unit listing', (
    tester,
  ) async {
    final reservations = FakeReservationRepository();
    await pumpApp(
      tester,
      () async => student,
      listings: FakeListingRepository(feed: [aListing(stock: 3)]),
      reservations: reservations,
    );
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');
    expect(find.text('3 available'), findsOneWidget);

    await tester.tap(find.byKey(ListingDetailScreen.reserveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add one'));
    await tester.tap(find.byTooltip('Add one'));
    await tester.pump();
    expect(find.text('RM 75'), findsOneWidget);
    await tester.tap(find.text('Confirm reservation'));
    await tester.pumpAndSettle();

    expect(reservations.calls, ['request l1 x3']);
  });

  testWidgets('a refused reservation shows the database’s reason', (
    tester,
  ) async {
    final reservations = FakeReservationRepository()
      ..failWith = const AppFailure(
        AppFailureReason.itemUnavailable,
        'This item is no longer available.',
      );
    await pumpApp(tester, () async => student, reservations: reservations);
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    await tester.tap(find.byKey(ListingDetailScreen.reserveKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm reservation'));
    await tester.pumpAndSettle();

    expect(find.text('This item is no longer available.'), findsOneWidget);
  });

  testWidgets('a reserved item cannot be reserved again', (tester) async {
    await pumpApp(
      tester,
      () async => student,
      listings: FakeListingRepository(
        feed: [aListing(status: ListingStatus.reserved, stock: 0)],
      ),
    );
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    final button = tester.widget<FilledButton>(
      find.byKey(ListingDetailScreen.reserveKey),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Reserved by someone else'), findsOneWidget);
  });

  testWidgets('the owner publishes their draft from the detail page', (
    tester,
  ) async {
    final listings = FakeListingRepository(
      feed: [
        aListing(
          id: 'l9',
          ownerId: meId,
          title: 'My old textbook',
          status: ListingStatus.draft,
        ),
      ],
    );
    await pumpApp(tester, () async => student, listings: listings);
    await tester.pumpAndSettle();
    await openListing(tester, 'My old textbook');

    expect(find.byKey(ListingDetailScreen.reserveKey), findsNothing);
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(listings.calls, ['status l9 available']);
  });

  testWidgets('the listing form checks fields and needs a photo to publish', (
    tester,
  ) async {
    final listings = FakeListingRepository();
    await pumpApp(tester, () async => student, listings: listings);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();
    expect(find.text('Sell an item'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('form-publish')));
    await tester.tap(find.byKey(const Key('form-publish')));
    await tester.pumpAndSettle();

    expect(find.text('Add at least one photo to publish.'), findsOneWidget);
    expect(find.text('Use at least 3 characters.'), findsOneWidget);
    expect(listings.calls, isEmpty);
  });

  testWidgets('a new listing is saved as a draft and opened', (tester) async {
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
    await tester.enterText(find.byKey(const Key('form-price')), '15.50');
    await tester.enterText(find.byKey(const Key('form-quantity')), '2');
    await tester.enterText(find.byKey(const Key('form-pickup')), 'Aman');
    await tester.ensureVisible(find.byKey(const Key('form-draft')));
    await tester.tap(find.byKey(const Key('form-draft')));
    await tester.pumpAndSettle();

    expect(listings.calls, ['save new Desk lamp 1550 x2 photos:0']);
    expect(find.text('Item'), findsOneWidget, reason: 'the detail page opens');
    expect(find.text('Publish'), findsOneWidget);
  });

  testWidgets('search sends the words and switches to best match', (
    tester,
  ) async {
    final listings = FakeListingRepository();
    await pumpApp(tester, () async => student, listings: listings);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SearchScreen.searchFieldKey), 'lamp');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(listings.queries.last.search, 'lamp');
    expect(listings.queries.last.sort, ListingSort.relevance);
  });

  testWidgets('a category on home opens search filtered to it', (tester) async {
    final listings = FakeListingRepository();
    await pumpApp(tester, () async => student, listings: listings);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Books'));
    await tester.pumpAndSettle();

    expect(listings.queries.last.category, 'Books');
    expect(find.text('Search'), findsWidgets);
  });

  testWidgets('a seller accepts a reservation request', (tester) async {
    final reservations = FakeReservationRepository(selling: [aReservation()]);
    await pumpApp(tester, () async => student, reservations: reservations);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selling'));
    await tester.pumpAndSettle();

    expect(find.text('Accept or decline this request.'), findsOneWidget);
    expect(find.text('Buyer: Siti'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(reservations.calls, ['resolve r1 accept']);
  });

  testWidgets('an accepted buyer sees the seller’s email; a requested one '
      'does not', (tester) async {
    final reservations = FakeReservationRepository(
      buying: [
        aReservation(
          iAmBuyer: true,
          status: ReservationStatus.accepted,
          email: 'ali@student.usm.my',
        ),
        aReservation(id: 'r2', iAmBuyer: true),
      ],
    );
    await pumpApp(tester, () async => student, reservations: reservations);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookings'));
    await tester.pumpAndSettle();

    expect(find.text('ali@student.usm.my'), findsOneWidget);
    expect(find.text('Waiting for the seller to respond.'), findsOneWidget);
    expect(find.text('Cancel'), findsNWidgets(2));
  });

  testWidgets('a student reports a listing', (tester) async {
    final reservations = FakeReservationRepository();
    await pumpApp(tester, () async => student, reservations: reservations);
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report listing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a reason.'), findsOneWidget);

    await tester.tap(find.text('Scam or fraud'));
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(reservations.calls, ['report l1 scam']);
    expect(
      find.textContaining('An administrator will review it'),
      findsOneWidget,
    );
  });

  testWidgets('profile shows the student and opens My Listings', (
    tester,
  ) async {
    await pumpApp(
      tester,
      () async => student,
      listings: FakeListingRepository(
        mine: [aListing(id: 'm1', ownerId: meId, title: 'My lamp')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Ali Bin Abu'), findsOneWidget);
    expect(find.text('Verified USM student'), findsOneWidget);

    await tester.tap(find.text('My listings'));
    await tester.pumpAndSettle();
    expect(find.text('My lamp'), findsOneWidget);
  });
}
