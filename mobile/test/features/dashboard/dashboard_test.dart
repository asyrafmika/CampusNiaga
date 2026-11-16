import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/features/auth/domain/user_access.dart';
import 'package:mobile/features/auth/presentation/profile_screen.dart';
import 'package:mobile/features/business/application/domain/business_application.dart';
import 'package:mobile/features/business/application/presentation/business_application_screen.dart';
import 'package:mobile/features/business/store/presentation/manage_store_screen.dart';
import 'package:mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:mobile/features/dashboard/domain/dashboard_models.dart';

import '../../support/app_harness.dart';
import '../../support/business_fakes.dart';
import '../../support/dashboard_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/store_fakes.dart';

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

void main() {
  group('periods', () {
    final now = DateTime(2026, 11, 16, 15, 30);

    test('last 7 and 30 days start at midnight, today included', () {
      expect(DashboardPeriod.last7Days.rangeAt(now), (
        from: DateTime(2026, 11, 10),
        to: null,
      ));
      expect(DashboardPeriod.last30Days.rangeAt(now), (
        from: DateTime(2026, 10, 18),
        to: null,
      ));
    });

    test('this month runs from the 1st to the 1st of the next month', () {
      expect(DashboardPeriod.thisMonth.rangeAt(now), (
        from: DateTime(2026, 11),
        to: DateTime(2026, 12),
      ));
      expect(DashboardPeriod.thisMonth.rangeAt(DateTime(2026, 12, 31)), (
        from: DateTime(2026, 12),
        to: DateTime(2027),
      ));
    });

    test('all time is unbounded', () {
      expect(DashboardPeriod.allTime.rangeAt(now), (from: null, to: null));
    });
  });

  group('mapper', () {
    Map<String, Object?> json() => {
      'business_id': 'b1',
      'business_name': 'Ali Bakes',
      'from_at': null,
      'to_at': null,
      'orders_by_status': {'completed': 3, 'cancelled': 1},
      'total_orders': 4,
      'completed_count': 3,
      'estimated_revenue_sen': 6600,
      'recorded_cost_sen': 2700,
      'costed_completed_count': 2,
      'estimated_profit_sen': 3900,
      'top_products': [
        {
          'listing_id': 'p1',
          'title': 'Brownie box',
          'units': 3,
          'revenue_sen': 3400,
        },
      ],
      'stock': [
        {
          'listing_id': 'p1',
          'title': 'Brownie box',
          'status': 'available',
          'stock': 4,
          'hidden': false,
        },
      ],
      'campaigns': [
        {
          'campaign_id': 'c1',
          'title': 'Raya brownies',
          'status': 'open',
          'capacity': 10,
          'allocated_qty': 2,
          'remaining': 8,
          'close_at': '2026-11-23T00:00:00+00:00',
        },
      ],
    };

    test('reads every figure, with missing statuses as zero', () {
      final d = dashboardFromJson(json());
      expect(d.ordersByStatus[OrderStatus.completed], 3);
      expect(d.ordersByStatus[OrderStatus.preparing], 0);
      expect(d.estimatedProfitSen, 3900);
      expect(d.uncostedCompletedCount, 1);
      expect(d.topProducts.single.revenueSen, 3400);
      expect(d.campaigns.single.filled, 0.2);
    });

    test('rejects an unknown status instead of guessing', () {
      final bad = json()
        ..['stock'] = [
          {
            'listing_id': 'p1',
            'title': 'x',
            'status': 'gone',
            'stock': 0,
            'hidden': false,
          },
        ];
      expect(() => dashboardFromJson(bad), throwsFormatException);
    });
  });

  group('screens', () {
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openStore(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(ProfileScreen.businessKey));
      await tapVisible(tester, find.byKey(BusinessApplicationScreen.storeKey));
    }

    FakeBusinessApplicationRepository approved() =>
        FakeBusinessApplicationRepository(
          application: anApplication(status: ApplicationStatus.approved),
          business: const MyBusiness(
            id: storeId,
            name: 'Ali Bakes',
            description: '',
            pickupDetails: 'Tekun lobby',
            status: BusinessStatus.approved,
          ),
        );

    testWidgets('the dashboard shows estimated figures, labelled as such', (
      tester,
    ) async {
      final dashboard = FakeDashboardRepository(aDashboard());
      await pumpApp(
        tester,
        () async => owner,
        applications: approved(),
        listings: FakeListingRepository(mine: [aProduct()]),
        dashboard: dashboard,
      );
      await openStore(tester);
      await tapVisible(tester, find.byKey(ManageStoreScreen.dashboardKey));

      expect(find.textContaining('Estimated / self-reported'), findsOneWidget);
      expect(find.text('RM 66'), findsOneWidget);
      expect(find.text('RM 27'), findsOneWidget);
      expect(find.text('RM 39'), findsOneWidget);
      expect(find.text('Estimated (self-reported)'), findsNWidgets(2));
      expect(
        find.textContaining('2 completed orders have no cost'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('RM 34 · 3 units'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('RM 32 · 4 units'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('2 of 10 taken'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Sold'), findsOneWidget);

      expect(
        dashboard.ranges.single.from,
        isNotNull,
        reason: 'last 30 days by default',
      );
      // The period chips sit above the scrolling body, always in view.
      await tester.ensureVisible(find.byKey(const Key('period-allTime')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('period-allTime')));
      await tester.pumpAndSettle();
      expect(dashboard.ranges.last, (from: null, to: null));
    });

    testWidgets('a refused dashboard shows the database’s reason', (
      tester,
    ) async {
      final dashboard = FakeDashboardRepository()
        ..failWith = const AppFailure(
          AppFailureReason.forbidden,
          'The dashboard is for approved businesses.',
        );
      await pumpApp(
        tester,
        () async => owner,
        applications: approved(),
        dashboard: dashboard,
      );
      await openStore(tester);
      await tapVisible(tester, find.byKey(ManageStoreScreen.dashboardKey));

      expect(
        find.text('The dashboard is for approved businesses.'),
        findsOneWidget,
      );
    });

    testWidgets('the seller records a cost on an order; buyers never can', (
      tester,
    ) async {
      final store = FakeStoreRepository(
        selling: [
          anOrder(id: 'o2', iAmBuyer: false, status: OrderStatus.completed),
          anOrder(id: 'o3', iAmBuyer: false, status: OrderStatus.cancelled),
        ],
        buying: [anOrder()],
      );
      await pumpApp(tester, () async => owner, store: store);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(ProfileScreen.ordersKey));

      expect(
        find.byKey(const Key('order-cost-o1')),
        findsNothing,
        reason: 'buying side',
      );
      await tester.tap(find.text('My business'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('order-cost-o3')),
        findsNothing,
        reason: 'cancelled',
      );

      await tapVisible(tester, find.byKey(const Key('order-cost-o2')));
      await tester.enterText(find.byKey(const Key('order-cost-field')), 'abc');
      await tester.tap(find.byKey(const Key('order-cost-save')));
      await tester.pumpAndSettle();
      expect(store.calls, isEmpty);
      expect(find.textContaining('Enter an amount'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('order-cost-o2')));
      await tester.enterText(find.byKey(const Key('order-cost-field')), '8.50');
      await tester.tap(find.byKey(const Key('order-cost-save')));
      await tester.pumpAndSettle();
      expect(store.calls, ['cost o2 850']);
    });
  });
}
