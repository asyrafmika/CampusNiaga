import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/features/auth/presentation/profile_screen.dart';
import 'package:mobile/features/discovery/data/discovery_repository.dart';
import 'package:mobile/features/discovery/domain/discovery_models.dart';
import 'package:mobile/features/discovery/presentation/discover_screen.dart';

import '../../support/app_harness.dart';
import '../../support/discovery_fakes.dart';

void main() {
  group('mappers and rules', () {
    test('reads a request card without identities', () {
      final r = requestFromRow({
        'id': 'r1',
        'name': 'Chocolate brownie',
        'category': 'Food & Beverage',
        'preferred_price_sen': 500,
        'campus_area': 'Tekun',
        'notes': null,
        'status': 'active',
        'cluster_key': brownieKey,
        'created_at': '2026-11-16T00:00:00+00:00',
        'interest_count': 2,
        'i_am_interested': true,
        'is_mine': false,
      });
      expect(r.isActive, isTrue);
      expect(r.preferredPriceSen, 500);
      expect(r.studentCount, 3, reason: 'the creator plus 2 interested');
      expect(
        () => requestFromRow({
          'id': 'r1',
          'status': 'archived',
          'name': 'x',
          'category': 'x',
          'campus_area': 'x',
          'cluster_key': 'x',
          'created_at': '2026-11-16T00:00:00+00:00',
          'interest_count': 0,
          'i_am_interested': false,
          'is_mine': false,
        }),
        throwsFormatException,
      );
    });

    test('reads an opportunity with its numbers and reasons', () {
      final o = opportunityFromRow({
        'cluster_key': brownieKey,
        'category': 'Food & Beverage',
        'head_term': 'brownie',
        'keywords': ['brownie', 'chocolate'],
        'request_ids': ['a', 'b', 'c'],
        'unique_interest_count': 4,
        'active_supply_count': 1,
        'distinct_seller_count': 1,
        'median_listed_price_sen': 900,
        'median_preferred_price_sen': 500,
        'price_gap': true,
        'score': 22,
        'reasons': ['4 students interested'],
        'insufficient_data': false,
        'algo_version': 'm4-v1',
        'calculated_at': '2026-11-16T00:00:00+00:00',
      });
      expect(o.title, 'Brownie');
      expect(o.requestCount, 3);
      expect(o.score, 22);
      expect(o.priceGap, isTrue);
      expect(o.algoVersion, 'm4-v1');
    });

    test('form checks mirror create_product_request', () {
      expect(RequestRules.name('ab'), isNotNull);
      expect(RequestRules.name('Brownie'), isNull);
      expect(RequestRules.name('x' * 81), isNotNull);
      expect(RequestRules.campusArea('T'), isNotNull);
      expect(RequestRules.campusArea('Tekun'), isNull);
      expect(RequestRules.notes('x' * 301), isNotNull);
      expect(RequestRules.notes(null), isNull);
    });
  });

  group('screens', () {
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> openDiscover(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(ProfileScreen.discoverKey));
    }

    testWidgets('Home leads to Discover', (tester) async {
      await pumpApp(tester, () async => student);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Can’t find it? Request it'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.text('Can’t find it? Request it'));
      expect(find.text('Discover'), findsOneWidget);
    });

    testWidgets('opportunities are ranked, labelled and explained', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () async => student,
        discovery: FakeDiscoveryRepository(
          opportunities: [
            anOpportunity(),
            anOpportunity(
              key: 'Others|lanyard',
              head: 'lanyard',
              score: 5,
              insufficient: true,
            ),
          ],
        ),
      );
      await openDiscover(tester);

      expect(find.textContaining('Interest is not a purchase'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Brownie'), findsOneWidget);
      expect(find.text('Possible opportunity'), findsNWidgets(2));
      expect(find.text('4 students interested'), findsOneWidget);
      expect(find.text('Insufficient data'), findsOneWidget);
    });

    testWidgets(
      'an opportunity shows its numbers, the formula and its requests',
      (tester) async {
        final discovery = FakeDiscoveryRepository();
        await pumpApp(tester, () async => student, discovery: discovery);
        await openDiscover(tester);
        await tapVisible(tester, find.text('Brownie'));

        expect(find.text('students want it'), findsOneWidget);
        expect(find.text('RM 9'), findsOneWidget);
        expect(find.text('RM 5'), findsOneWidget);
        expect(
          find.text(
            'Listings (median RM 9) are above requested prices (median RM 5)',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Score = 5 × students'), findsOneWidget);
        expect(find.text('Requests (3)'), findsOneWidget);

        await tapVisible(tester, find.byKey(const Key('request-interest-r2')));
        expect(discovery.calls, ['toggle r2']);
        expect(find.text('Interested ✓'), findsOneWidget);
      },
    );

    testWidgets('a student requests a product', (tester) async {
      final discovery = FakeDiscoveryRepository();
      await pumpApp(tester, () async => student, discovery: discovery);
      await openDiscover(tester);
      await tester.tap(find.byKey(DiscoverScreen.requestKey));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.byKey(const Key('request-submit')));
      expect(discovery.calls, isEmpty, reason: 'the form is incomplete');
      expect(find.text('Choose a category.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('request-name')),
        'Chocolate brownie',
      );
      await tester.tap(find.byKey(const Key('request-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Others').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('request-price')), '4.50');
      await tester.enterText(find.byKey(const Key('request-area')), 'Tekun');
      await tapVisible(tester, find.byKey(const Key('request-submit')));

      expect(discovery.calls, ['create Chocolate brownie Others 450 Tekun']);
      expect(find.textContaining('Requested!'), findsOneWidget);
    });

    testWidgets('the creator closes their own request; others tap Interested', (
      tester,
    ) async {
      final discovery = FakeDiscoveryRepository(
        mine: [aRequest(id: 'r5', mine: true)],
      );
      await pumpApp(tester, () async => student, discovery: discovery);
      await openDiscover(tester);
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('request-interest-r1')), findsOneWidget);

      await tester.tap(find.text('Mine'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('request-interest-r5')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('request-close-r5')));
      await tester.tap(find.text('Close request'));
      await tester.pumpAndSettle();

      expect(discovery.calls, ['close r5']);
    });

    testWidgets('a refused tap shows the database’s reason', (tester) async {
      final discovery = FakeDiscoveryRepository();
      await pumpApp(tester, () async => student, discovery: discovery);
      await openDiscover(tester);
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      discovery.failWith = const AppFailure(
        AppFailureReason.rateLimited,
        'You’ve shown interest in a lot of requests. Try again in an hour.',
      );
      await tapVisible(tester, find.byKey(const Key('request-interest-r1')));

      expect(find.textContaining('Try again in an hour'), findsOneWidget);
      expect(find.text('Interested ✓'), findsNothing);
    });
  });
}
