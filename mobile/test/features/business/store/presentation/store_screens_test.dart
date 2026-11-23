import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/features/auth/domain/user_access.dart';
import 'package:mobile/features/auth/presentation/profile_screen.dart';
import 'package:mobile/features/business/application/domain/business_application.dart';
import 'package:mobile/features/business/application/presentation/business_application_screen.dart';
import 'package:mobile/features/business/store/presentation/manage_store_screen.dart';
import 'package:mobile/features/marketplace/presentation/listing_detail_screen.dart';

import '../../../../support/app_harness.dart';
import '../../../../support/business_fakes.dart';
import '../../../../support/marketplace_fakes.dart';
import '../../../../support/store_fakes.dart';

const owner = UserAccess(
  userId: 'u2',
  email: 'ali@student.usm.my',
  emailConfirmed: true,
  accountStatus: AccountStatus.active,
  isStudent: true,
  isAdmin: false,
  isBusinessOwner: true,
  businessStatus: BusinessStatus.approved,
);

const aliBakes = MyBusiness(
  id: storeId,
  name: 'Ali Bakes',
  description: 'Fudgy brownies every Friday.',
  pickupDetails: 'Tekun lobby, Fri 6-8pm',
  status: BusinessStatus.approved,
);

/// The M3 screens, driven through the real router with in-memory data.
void main() {
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openProduct(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Brownie box').first);
  }

  Future<void> openProfileItem(WidgetTester tester, Key key) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(key));
  }

  /// Profile → My business (approved) → Open my store.
  Future<void> openStore(WidgetTester tester) async {
    await openProfileItem(tester, ProfileScreen.businessKey);
    await tapVisible(tester, find.byKey(BusinessApplicationScreen.storeKey));
  }

  FakeBusinessApplicationRepository approvedApplication() =>
      FakeBusinessApplicationRepository(
        application: anApplication(status: ApplicationStatus.approved),
        business: aliBakes,
      );

  group('buying', () {
    testWidgets(
      'a business product names its business and is ordered, not bought',
      (tester) async {
        final store = FakeStoreRepository();
        await pumpApp(
          tester,
          () async => student,
          listings: FakeListingRepository(feed: [aProduct()]),
          store: store,
        );
        await openProduct(tester);

        expect(find.text('Ali Bakes'), findsOneWidget);
        expect(find.byKey(ListingDetailScreen.buyKey), findsNothing);
        await tapVisible(tester, find.byKey(ListingDetailScreen.orderKey));

        expect(find.text('Buy from stock'), findsOneWidget);
        expect(find.text('Pre-order: Raya brownies'), findsOneWidget);
        await tester.tap(find.byTooltip('Add one'));
        await tester.pump();
        expect(find.text('RM 24'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('order-note')),
          'After 6pm',
        );
        await tapVisible(tester, find.byKey(const Key('order-submit')));

        expect(store.calls, ['order p1 x2 stock After 6pm']);
        expect(find.textContaining('Ordered!'), findsOneWidget);
      },
    );

    testWidgets(
      'the storefront lists its pre-orders; one opens pre-selected and capped',
      (tester) async {
        final store = FakeStoreRepository();
        await pumpApp(
          tester,
          () async => student,
          listings: FakeListingRepository(feed: [aProduct()]),
          store: store,
        );
        await openProduct(tester);
        await tapVisible(tester, find.byKey(ListingDetailScreen.storefrontKey));

        expect(find.text('Fudgy brownies every Friday.'), findsOneWidget);
        expect(find.text('Pre-orders'), findsOneWidget);
        await tapVisible(tester, find.text('Raya brownies'));

        expect(find.text('Up to 2 per order.'), findsOneWidget);
        await tester.tap(find.byTooltip('Add one'));
        await tester.pump();
        final addOne = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.add_rounded),
        );
        expect(addOne.onPressed, isNull, reason: 'the per-order limit caps it');
        await tapVisible(tester, find.byKey(const Key('order-submit')));

        expect(store.calls, ['order p1 x2 c1']);
      },
    );

    testWidgets('a sold-out product with no open pre-order cannot be ordered', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () async => student,
        listings: FakeListingRepository(feed: [aProduct(stock: 0)]),
        store: FakeStoreRepository(storefront: aStorefront(campaigns: [])),
      );
      await openProduct(tester);
      await tapVisible(tester, find.byKey(ListingDetailScreen.orderKey));

      expect(find.text('Not available right now'), findsOneWidget);
      expect(find.byKey(const Key('order-submit')), findsNothing);
    });

    testWidgets('a refused order shows the database’s reason', (tester) async {
      final store = FakeStoreRepository();
      await pumpApp(
        tester,
        () async => student,
        listings: FakeListingRepository(feed: [aProduct()]),
        store: store,
      );
      await openProduct(tester);
      await tapVisible(tester, find.byKey(ListingDetailScreen.orderKey));
      store.failWith = const AppFailure(
        AppFailureReason.itemUnavailable,
        'Only 1 left.',
      );
      await tapVisible(tester, find.byKey(const Key('order-submit')));

      expect(find.text('Only 1 left.'), findsOneWidget);
      expect(find.text('Buy from stock'), findsOneWidget);
    });

    testWidgets('a buyer cancels an order from My orders', (tester) async {
      final store = FakeStoreRepository(buying: [anOrder()]);
      await pumpApp(tester, () async => student, store: store);
      await openProfileItem(tester, ProfileScreen.ordersKey);

      expect(find.text('Awaiting confirmation'), findsOneWidget);
      expect(find.text('Collect: Tekun lobby, Fri 6-8pm'), findsOneWidget);
      expect(find.byKey(const Key('order-next-o1')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('order-cancel-o1')));
      await tester.tap(find.text('Cancel order'));
      await tester.pumpAndSettle();

      expect(store.calls, ['transition o1 cancel']);
    });
  });

  group('selling', () {
    testWidgets('the business sees its orders and moves them forward', (
      tester,
    ) async {
      final store = FakeStoreRepository(
        selling: [anOrder(id: 'o2', iAmBuyer: false)],
      );
      await pumpApp(tester, () async => owner, store: store);
      await openProfileItem(tester, ProfileScreen.ordersKey);
      await tester.tap(find.text('My business'));
      await tester.pumpAndSettle();

      expect(find.text('Reject'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('order-next-o2')));

      expect(store.calls, ['transition o2 confirm']);
    });

    testWidgets('the owner opens a draft pre-order from My store', (
      tester,
    ) async {
      final store = FakeStoreRepository(
        campaigns: [aCampaign(id: 'c2', status: CampaignStatus.draft)],
      );
      await pumpApp(
        tester,
        () async => owner,
        applications: approvedApplication(),
        listings: FakeListingRepository(mine: [aProduct()]),
        store: store,
      );
      await openStore(tester);

      expect(find.text('Brownie box'), findsWidgets);
      expect(find.text('Raya brownies'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('campaign-open-c2')));

      expect(store.calls, ['campaign c2 open']);
    });

    testWidgets('the owner creates and opens a pre-order', (tester) async {
      final store = FakeStoreRepository();
      await pumpApp(
        tester,
        () async => owner,
        applications: approvedApplication(),
        listings: FakeListingRepository(mine: [aProduct()]),
        store: store,
      );
      await openStore(tester);
      await tapVisible(tester, find.byKey(ManageStoreScreen.newCampaignKey));

      // Nothing is sent while the form is incomplete.
      await tapVisible(tester, find.byKey(const Key('campaign-save-open')));
      expect(store.calls, isEmpty);

      await tester.enterText(
        find.byKey(const Key('campaign-title')),
        'Raya brownies',
      );
      await tester.enterText(find.byKey(const Key('campaign-price')), '10');
      await tester.enterText(find.byKey(const Key('campaign-capacity')), '30');
      await tester.enterText(find.byKey(const Key('campaign-limit')), '2');
      await tapVisible(tester, find.byKey(const Key('campaign-save-open')));

      expect(store.calls, [
        'campaign new p1 Raya brownies 1000 cap30 limit2',
        'campaign c9 open',
      ]);
      expect(find.textContaining('Pre-order is open'), findsOneWidget);
    });

    testWidgets('the owner edits the storefront', (tester) async {
      final store = FakeStoreRepository();
      await pumpApp(
        tester,
        () async => owner,
        applications: approvedApplication(),
        listings: FakeListingRepository(mine: [aProduct()]),
        store: store,
      );
      await openStore(tester);
      await tapVisible(tester, find.text('Edit storefront'));

      await tester.enterText(find.byKey(const Key('storefront-pickup')), 'Tek');
      await tapVisible(tester, find.byKey(const Key('storefront-save')));
      expect(store.calls, isEmpty, reason: 'pickup details are too short');

      await tester.enterText(
        find.byKey(const Key('storefront-pickup')),
        'Tekun lobby, Sat 10am',
      );
      await tapVisible(tester, find.byKey(const Key('storefront-save')));
      expect(store.calls, ['storefront b1 Tekun lobby, Sat 10am']);
    });

    testWidgets(
      'a product added from My store is saved as a business product',
      (tester) async {
        final listings = FakeListingRepository(mine: [aProduct()]);
        await pumpApp(
          tester,
          () async => owner,
          applications: approvedApplication(),
          listings: listings,
        );
        await openStore(tester);
        await tapVisible(tester, find.byKey(ManageStoreScreen.addProductKey));

        expect(find.text('Add a product'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('form-title')),
          'Cookie jar',
        );
        await tester.tap(find.byKey(const Key('form-category')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Others').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('form-price')), '8');
        await tester.enterText(find.byKey(const Key('form-quantity')), '10');
        await tester.enterText(find.byKey(const Key('form-pickup')), 'Tekun');
        await tapVisible(tester, find.byKey(const Key('form-draft')));

        expect(listings.calls, [
          'save new Cookie jar 800 x10 photos:0 business',
        ]);
      },
    );

    testWidgets('the owner of a sold-out product can restock it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () async => owner,
        listings: FakeListingRepository(feed: [aProduct(stock: 0)]),
      );
      await openProduct(tester);

      expect(
        find.widgetWithText(FilledButton, 'Edit'),
        findsOneWidget,
        reason: 'a sold-out business product is restocked by editing it',
      );
      expect(aProduct(stock: 0).status, ListingStatus.sold);
    });
  });
}
