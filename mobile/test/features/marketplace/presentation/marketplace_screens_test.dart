import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/features/marketplace/domain/listing.dart';
import 'package:mobile/features/marketplace/domain/listing_query.dart';
import 'package:mobile/features/marketplace/domain/purchase.dart';
import 'package:mobile/features/marketplace/presentation/listing_detail_screen.dart';
import 'package:mobile/features/marketplace/presentation/listing_payment_screen.dart';
import 'package:mobile/features/marketplace/presentation/my_purchases_screen.dart';
import 'package:mobile/features/marketplace/presentation/search_screen.dart';
import 'package:mobile/features/payments/domain/payment_models.dart';
import 'package:mobile/features/payments/presentation/payment_details_screen.dart';

import '../../../support/app_harness.dart';
import '../../../support/chat_fakes.dart';
import '../../../support/marketplace_fakes.dart';
import '../../../support/payment_fakes.dart';

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

  testWidgets('a buyer buys an item for pickup at the seller\'s spot', (
    tester,
  ) async {
    final purchases = FakePurchaseRepository();
    await pumpApp(tester, () async => student, purchases: purchases);
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    await tester.tap(find.byKey(ListingDetailScreen.buyKey));
    await tester.pumpAndSettle();
    // Nothing to type: the seller's spot is shown, and other arrangements go
    // through the chat.
    expect(find.byType(TextField), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(ListingDetailScreen.buyPickupKey)).data,
      contains('Pickup at Desasiswa Tekun'),
    );
    expect(purchases.calls, isEmpty, reason: 'only Confirm purchase buys');
    await tester.tap(find.byKey(ListingDetailScreen.confirmBuyKey));
    await tester.pumpAndSettle();

    expect(purchases.calls, ['buy l1 x1']);
    expect(find.textContaining('Bought!'), findsOneWidget);
  });

  testWidgets('choosing how to pay and leaving buys nothing', (tester) async {
    final purchases = FakePurchaseRepository();
    await pumpApp(tester, () async => student, purchases: purchases);
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    await tester.tap(find.byKey(ListingDetailScreen.buyKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash on pickup'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 60)); // outside the sheet
    await tester.pumpAndSettle();

    expect(find.byKey(ListingDetailScreen.confirmBuyKey), findsNothing);
    expect(purchases.calls, isEmpty);
  });

  testWidgets('closing the sheet mid-purchase keeps the listing open', (
    tester,
  ) async {
    final gate = Completer<void>();
    final purchases = FakePurchaseRepository()..buyGate = gate.future;
    await pumpApp(tester, () async => student, purchases: purchases);
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');
    await tester.tap(find.byKey(ListingDetailScreen.buyKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ListingDetailScreen.confirmBuyKey));
    await tester.pump();

    await tester.tapAt(const Offset(20, 60)); // outside the sheet
    // Not pumpAndSettle: the sheet's spinner animates until it has gone.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ListingDetailScreen), findsOneWidget);
    expect(find.textContaining('Bought!'), findsOneWidget);
  });

  testWidgets('a buyer chooses how many units of a multi-unit listing', (
    tester,
  ) async {
    final purchases = FakePurchaseRepository();
    await pumpApp(
      tester,
      () async => student,
      listings: FakeListingRepository(feed: [aListing(stock: 3)]),
      purchases: purchases,
    );
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');
    expect(find.text('3 available'), findsOneWidget);

    await tester.tap(find.byKey(ListingDetailScreen.buyKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add one'));
    await tester.tap(find.byTooltip('Add one'));
    await tester.pump();
    expect(find.text('RM 75'), findsOneWidget);
    await tester.tap(find.byKey(ListingDetailScreen.confirmBuyKey));
    await tester.pumpAndSettle();

    expect(purchases.calls, ['buy l1 x3']);
  });

  testWidgets('losing the race shows the reason and that it is sold', (
    tester,
  ) async {
    final listings = FakeListingRepository();
    final purchases = FakePurchaseRepository()
      ..failWith = const AppFailure(
        AppFailureReason.itemUnavailable,
        'Sorry, this item has just been sold.',
      );
    await pumpApp(
      tester,
      () async => student,
      listings: listings,
      purchases: purchases,
    );
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    await tester.tap(find.byKey(ListingDetailScreen.buyKey));
    await tester.pumpAndSettle();
    listings.feed = [aListing(status: ListingStatus.sold, stock: 0)];
    await tester.tap(find.byKey(ListingDetailScreen.confirmBuyKey));
    await tester.pumpAndSettle();

    expect(find.text('Sorry, this item has just been sold.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(ListingDetailScreen.buyKey),
    );
    expect(button.onPressed, isNull, reason: 'the page refreshed');
  });

  testWidgets('a sold item cannot be bought or chatted about', (tester) async {
    await pumpApp(
      tester,
      () async => student,
      listings: FakeListingRepository(
        feed: [aListing(status: ListingStatus.sold, stock: 0)],
      ),
    );
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    final button = tester.widget<FilledButton>(
      find.byKey(ListingDetailScreen.buyKey),
    );
    expect(button.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byKey(ListingDetailScreen.buyKey),
        matching: find.text('Sold'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(ListingDetailScreen.chatKey), findsNothing);
  });

  testWidgets('a student asks the seller first, which buys nothing', (
    tester,
  ) async {
    final chat = FakeChatRepository();
    final purchases = FakePurchaseRepository();
    await pumpApp(
      tester,
      () async => student,
      chat: chat,
      purchases: purchases,
    );
    await tester.pumpAndSettle();
    await openListing(tester, 'Casio FX-570 calculator');

    await tester.tap(find.byKey(ListingDetailScreen.chatKey));
    await tester.pumpAndSettle();

    expect(chat.calls.first, 'open item l1');
    expect(
      find.textContaining('Chatting does not hold the item.'),
      findsOneWidget,
    );
    expect(purchases.calls, isEmpty);
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

    expect(find.byKey(ListingDetailScreen.buyKey), findsNothing);
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(
      find.byType(ListingPaymentScreen),
      findsOneWidget,
      reason: 'a draft is published from its payment step',
    );
    expect(listings.calls, isEmpty);
    await tester.tap(find.byKey(PaymentDetailsForm.saveKey));
    await tester.pumpAndSettle();

    expect(listings.calls, ['status l9 available']);
  });

  Future<void> fillNewListing(WidgetTester tester) async {
    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('form-title')), 'Desk lamp');
    await tester.tap(find.byKey(const Key('form-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Others').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('form-price')), '15.50');
    await tester.enterText(find.byKey(const Key('form-pickup')), 'Aman');
    await tester.ensureVisible(find.byKey(const Key('form-publish')));
    await tester.pumpAndSettle();
    expect(find.text('Next: payment'), findsOneWidget);
    await tester.tap(find.byKey(const Key('form-publish')));
    await tester.pumpAndSettle();
  }

  testWidgets('after the details, the seller adds how buyers pay, then '
      'publishes', (tester) async {
    final listings = FakeListingRepository();
    final payments = FakePaymentRepository();
    await pumpApp(
      tester,
      () async => student,
      listings: listings,
      payments: payments,
    );
    await tester.pumpAndSettle();
    await fillNewListing(tester);

    expect(find.text('How buyers pay you'), findsOneWidget);
    expect(listings.calls, ['save new Desk lamp 1550 x1 photos:1']);
    await tester.enterText(find.byKey(PaymentDetailsForm.bankKey), 'Maybank');
    await tester.enterText(find.byKey(PaymentDetailsForm.nameKey), 'Ali Abu');
    await tester.enterText(
      find.byKey(PaymentDetailsForm.numberKey),
      '1234567890',
    );
    await tester.ensureVisible(find.byKey(PaymentDetailsForm.saveKey));
    await tester.tap(find.byKey(PaymentDetailsForm.saveKey));
    await tester.pumpAndSettle();

    expect(payments.calls, [
      'details personal Maybank|Ali Abu|1234567890 qr:none',
    ]);
    expect(listings.calls.last, 'status new1 available');
    expect(find.byType(ListingDetailScreen), findsOneWidget);
    expect(find.textContaining('Published!'), findsOneWidget);
  });

  testWidgets('saved details are filled in, and cash only needs nothing', (
    tester,
  ) async {
    final listings = FakeListingRepository();
    final payments = FakePaymentRepository(
      saved: const SavedPaymentDetails(
        personal: PaymentDetails(
          bankName: 'CIMB',
          accountName: 'Ali',
          accountNumber: '111111',
        ),
      ),
    );
    await pumpApp(
      tester,
      () async => student,
      listings: listings,
      payments: payments,
    );
    await tester.pumpAndSettle();
    await fillNewListing(tester);

    expect(find.text('CIMB'), findsOneWidget, reason: 'used for all items');
    await tester.ensureVisible(find.byKey(PaymentDetailsForm.saveKey));
    await tester.tap(find.byKey(PaymentDetailsForm.saveKey));
    await tester.pumpAndSettle();

    expect(payments.calls, isEmpty, reason: 'nothing changed, nothing saved');
    expect(listings.calls.last, 'status new1 available');
  });

  testWidgets('the seller can stop at the payment step with a draft', (
    tester,
  ) async {
    final listings = FakeListingRepository();
    await pumpApp(tester, () async => student, listings: listings);
    await tester.pumpAndSettle();
    await fillNewListing(tester);

    await tester.ensureVisible(find.byKey(ListingPaymentScreen.draftKey));
    await tester.tap(find.byKey(ListingPaymentScreen.draftKey));
    await tester.pumpAndSettle();

    expect(listings.calls, ['save new Desk lamp 1550 x1 photos:1']);
    expect(find.byType(ListingDetailScreen), findsOneWidget);
  });

  testWidgets('the owner deletes a listing, after confirming', (tester) async {
    final listings = FakeListingRepository(
      feed: [aListing(id: 'l9', ownerId: meId, title: 'My old textbook')],
    );
    await pumpApp(tester, () async => student, listings: listings);
    await tester.pumpAndSettle();
    await openListing(tester, 'My old textbook');

    expect(find.text('Close'), findsNothing, reason: 'deleted, not closed');
    await tester.tap(
      find.byKey(ListingDetailScreen.ownerActionKey(OwnerAction.delete)),
    );
    await tester.pumpAndSettle();
    expect(listings.calls, isEmpty, reason: 'it asks first');
    await tester.tap(find.byKey(ListingDetailScreen.confirmOwnerActionKey));
    await tester.pumpAndSettle();

    expect(listings.calls, ['status l9 deleted']);
    expect(find.byType(ListingDetailScreen), findsNothing);
    expect(find.text('Listing deleted.'), findsOneWidget);
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

  Future<void> openSales(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selling'));
    await tester.pumpAndSettle();
  }

  testWidgets('a seller completes a sale, with nothing to accept', (
    tester,
  ) async {
    final purchases = FakePurchaseRepository(selling: [aPurchase()]);
    await pumpApp(tester, () async => student, purchases: purchases);
    await openSales(tester);

    expect(find.text('Buyer: Siti'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
    expect(
      find.byKey(PurchaseTile.actionKey('r1', PurchaseAction.relist)),
      findsNothing,
      reason: 'not before 24 hours',
    );
    expect(find.textContaining('You can relist from'), findsOneWidget);
    await tester.tap(
      find.byKey(PurchaseTile.actionKey('r1', PurchaseAction.complete)),
    );
    await tester.pumpAndSettle();
    expect(purchases.calls, isEmpty, reason: 'it asks first');
    await tester.tap(find.byKey(PurchaseTile.confirmKey));
    await tester.pumpAndSettle();

    expect(purchases.calls, ['complete r1']);
  });

  testWidgets('after 24 hours a seller relists uncollected cash', (
    tester,
  ) async {
    final purchases = FakePurchaseRepository(
      selling: [
        aPurchase(
          relistFrom: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ],
    );
    await pumpApp(tester, () async => student, purchases: purchases);
    await openSales(tester);

    await tester.tap(
      find.byKey(PurchaseTile.actionKey('r1', PurchaseAction.relist)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PurchaseTile.confirmKey));
    await tester.pumpAndSettle();

    expect(purchases.calls, ['relist r1']);
  });

  testWidgets('a seller cancels with a reason, and may close the item', (
    tester,
  ) async {
    final purchases = FakePurchaseRepository(selling: [aPurchase()]);
    await pumpApp(tester, () async => student, purchases: purchases);
    await openSales(tester);

    await tester.tap(
      find.byKey(PurchaseTile.actionKey('r1', PurchaseAction.cancel)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PurchaseTile.confirmKey));
    await tester.pumpAndSettle();
    expect(find.text('Say why, so the buyer knows.'), findsOneWidget);
    expect(purchases.calls, isEmpty);

    await tester.enterText(
      find.byKey(PurchaseTile.cancelReasonKey),
      ' It broke ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PurchaseTile.cancelDeleteKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PurchaseTile.confirmKey));
    await tester.pumpAndSettle();

    expect(purchases.calls, ['cancel r1 "It broke" delete']);
  });

  testWidgets('a buyer sees the purchase and can cancel it', (tester) async {
    final purchases = FakePurchaseRepository(
      buying: [aPurchase(iAmBuyer: true)],
    );
    await pumpApp(tester, () async => student, purchases: purchases);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();

    expect(find.text('Seller: Ali'), findsOneWidget);
    expect(find.text('Awaiting handover'), findsOneWidget);
    expect(find.byKey(PurchaseTile.chatKey('r1')), findsOneWidget);
    expect(
      find.byKey(PurchaseTile.actionKey('r1', PurchaseAction.complete)),
      findsNothing,
    );
    await tester.tap(
      find.byKey(PurchaseTile.actionKey('r1', PurchaseAction.cancel)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PurchaseTile.confirmKey));
    await tester.pumpAndSettle();

    expect(purchases.calls, ['cancel r1']);
  });

  testWidgets('a student reports a listing', (tester) async {
    final purchases = FakePurchaseRepository();
    await pumpApp(tester, () async => student, purchases: purchases);
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

    expect(purchases.calls, ['report l1 scam']);
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
