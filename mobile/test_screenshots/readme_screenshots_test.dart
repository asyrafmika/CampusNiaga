// Renders the README screenshots of the mobile app with demo data, so they
// can be refreshed without an emulator or a real account:
//
//   cd mobile && flutter test test_screenshots
//
// The PNGs are written to docs/images/mobile/. This folder is outside test/,
// so `flutter test` (and CI) never runs it.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/core/router/app_router.dart';
import 'package:mobile/core/router/app_routes.dart';
import 'package:mobile/core/widgets/app_logo.dart';
import 'package:mobile/features/auth/domain/user_access.dart';
import 'package:mobile/features/business/application/domain/business_application.dart';
import 'package:mobile/features/discovery/domain/discovery_models.dart';
import 'package:mobile/features/marketplace/domain/listing.dart';

import '../test/support/app_harness.dart';
import '../test/support/business_fakes.dart';
import '../test/support/dashboard_fakes.dart';
import '../test/support/discovery_fakes.dart';
import '../test/support/marketplace_fakes.dart';
import '../test/support/store_fakes.dart';

const String outDir = '../docs/images/mobile';

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

Listing demo(
  String id,
  String title,
  int priceSen,
  String category, {
  String seller = 'Siti',
  ListingCondition condition = ListingCondition.good,
  String pickup = 'Desasiswa Tekun',
  String description = 'Used for one semester, works perfectly.',
  int stock = 1,
  bool business = false,
}) => Listing(
  id: id,
  ownerId: business ? 'u2' : 'u3',
  sellerName: seller,
  title: title,
  description: description,
  category: category,
  priceSen: priceSen,
  condition: condition,
  photoPaths: const [],
  stock: stock,
  pickupArea: pickup,
  status: ListingStatus.available,
  createdAt: DateTime.utc(2026, 11, 16),
  mode: business ? ListingMode.business : ListingMode.personal,
  businessId: business ? storeId : null,
  businessName: business ? 'Ali Bakes' : null,
);

final List<Listing> feed = [
  demo(
    'l1',
    'Casio FX-570EX calculator',
    2500,
    'Stationery',
    description:
        'Scientific calculator, approved for USM exams. Used for one '
        'semester, comes with its cover.',
  ),
  demo(
    'p1',
    'Brownie box (6 pcs)',
    1200,
    'Food & Beverage',
    seller: 'Ali',
    condition: ListingCondition.brandNew,
    pickup: 'Tekun lobby',
    stock: 8,
    business: true,
  ),
  demo('l2', 'LED desk lamp', 1500, 'Electronics', seller: 'Amin'),
  demo(
    'l3',
    'Data Structures textbook',
    3000,
    'Books',
    seller: 'Mei',
    condition: ListingCondition.likeNew,
    pickup: 'Desasiswa Restu',
  ),
  demo('l4', 'Mini rice cooker', 3500, 'Electronics', seller: 'Hafiz'),
  demo('l5', 'A4 lecture pad, 5 pack', 800, 'Stationery', seller: 'Nina'),
];

final List<Opportunity> opportunities = [
  anOpportunity(),
  Opportunity(
    clusterKey: 'Electronics|stand',
    category: 'Electronics',
    headTerm: 'stand',
    keywords: const ['phone', 'stand'],
    requestCount: 2,
    uniqueInterestCount: 3,
    activeSupplyCount: 0,
    distinctSellerCount: 0,
    medianPreferredPriceSen: 1000,
    priceGap: false,
    score: 15,
    reasons: const [
      '3 students interested',
      'No active matching listings',
      'No listing prices to compare',
    ],
    insufficientData: false,
    algoVersion: 'm4-v1',
    calculatedAt: DateTime.utc(2026, 11, 16),
  ),
  Opportunity(
    clusterKey: 'Others|umbrella',
    category: 'Others',
    headTerm: 'umbrella',
    keywords: const ['umbrella'],
    requestCount: 1,
    uniqueInterestCount: 1,
    activeSupplyCount: 0,
    distinctSellerCount: 0,
    medianPreferredPriceSen: 1200,
    priceGap: false,
    score: 5,
    reasons: const [
      '1 student interested',
      'No active matching listings',
      'No listing prices to compare',
      'Insufficient data: fewer than 2 interested students',
    ],
    insufficientData: true,
    algoVersion: 'm4-v1',
    calculatedAt: DateTime.utc(2026, 11, 16),
  ),
];

Future<void> loadFonts() async {
  ByteData bytes(String path) =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final montserrat = FontLoader('Montserrat');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    montserrat.addFont(
      Future.value(bytes('assets/fonts/Montserrat-$weight.ttf')),
    );
  }
  await montserrat.load();
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}'
      '/bin/cache/artifacts/material_fonts';
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(bytes('$fonts/materialicons-regular.otf')));
  await icons.load();
  final roboto = FontLoader('Roboto')
    ..addFont(Future.value(bytes('$fonts/roboto-regular.ttf')));
  await roboto.load();
}

Future<void> shoot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final element = find.byType(CampusNiagaApp).evaluate().single;
  await save(tester, await captureImage(element), name);
}

Future<void> save(WidgetTester tester, ui.Image image, String name) async {
  await tester.runAsync(() async {
    // Half size (540 px wide) keeps the README light; still sharp at the
    // width GitHub shows it.
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(0.5)
      ..drawImage(
        image,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
    final small = await recorder.endRecording().toImage(
      image.width ~/ 2,
      image.height ~/ 2,
    );
    final png = await small.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$outDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

Future<void> go(WidgetTester tester, String location) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(CampusNiagaApp)),
  );
  container.read(appRouterProvider).go(location);
  await tester.pumpAndSettle();
}

/// A widget test with real shadows and no debug banner, restored before the
/// framework checks its debug settings.
void screenshot(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    WidgetsApp.debugAllowBannerOverride = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
      WidgetsApp.debugAllowBannerOverride = true;
    }
  });
}

void main() {
  setUpAll(loadFonts);

  screenshot('splash', (tester) async {
    await pumpApp(tester, () => Completer<UserAccess?>().future);
    final element = find.byType(CampusNiagaApp).evaluate().single;
    // The spinner never settles, so load the logo before capturing.
    await tester.runAsync(
      () => precacheImage(const AssetImage(AppLogoMark.asset), element),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await save(tester, await captureImage(element), 'splash');
  });

  screenshot('sign in', (tester) async {
    await pumpApp(tester, () async => null);
    await shoot(tester, 'sign_in');
  });

  screenshot('marketplace', (tester) async {
    await pumpApp(
      tester,
      () async => student,
      listings: FakeListingRepository(feed: feed),
      discovery: FakeDiscoveryRepository(opportunities: opportunities),
    );
    await tester.pumpAndSettle();
    await shoot(tester, 'home');
    await go(tester, AppRoutes.listing('l1'));
    await shoot(tester, 'listing');
  });

  screenshot('storefront', (tester) async {
    await pumpApp(
      tester,
      () async => student,
      listings: FakeListingRepository(feed: feed),
      store: FakeStoreRepository(
        storefront: aStorefront(
          listings: [
            feed[1],
            demo(
              'p2',
              'Chocolate chip cookie jar',
              1500,
              'Food & Beverage',
              seller: 'Ali',
              condition: ListingCondition.brandNew,
              stock: 5,
              business: true,
            ),
          ],
          campaigns: [aCampaign(capacity: 10, allocated: 6)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await go(tester, AppRoutes.storefront(storeId));
    await shoot(tester, 'storefront');
  });

  screenshot('discovery', (tester) async {
    await pumpApp(
      tester,
      () async => student,
      discovery: FakeDiscoveryRepository(opportunities: opportunities),
    );
    await tester.pumpAndSettle();
    await go(tester, AppRoutes.discover);
    await shoot(tester, 'discover');
    await go(tester, AppRoutes.opportunity(brownieKey));
    await shoot(tester, 'opportunity');
  });

  screenshot('business application', (tester) async {
    await pumpApp(
      tester,
      () async => student,
      applications: FakeBusinessApplicationRepository(
        application: anApplication(
          status: ApplicationStatus.infoRequested,
          remarks:
              'Please add your price list and a food handling '
              'certificate.',
        ),
        entries: [
          ApplicationHistoryEntry(
            from: ApplicationStatus.underReview,
            to: ApplicationStatus.infoRequested,
            actor: ApplicationActor.reviewer,
            note:
                'Please add your price list and a food handling '
                'certificate.',
            createdAt: DateTime.utc(2026, 11, 16, 14),
          ),
          ApplicationHistoryEntry(
            from: ApplicationStatus.submitted,
            to: ApplicationStatus.underReview,
            actor: ApplicationActor.reviewer,
            createdAt: DateTime.utc(2026, 11, 16, 11),
          ),
          ApplicationHistoryEntry(
            from: ApplicationStatus.draft,
            to: ApplicationStatus.submitted,
            actor: ApplicationActor.applicant,
            createdAt: DateTime.utc(2026, 11, 16, 9),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await go(tester, AppRoutes.business);
    await shoot(tester, 'application');
  });

  screenshot('dashboard', (tester) async {
    await pumpApp(
      tester,
      () async => owner,
      dashboard: FakeDashboardRepository(aDashboard(costed: 3)),
    );
    await tester.pumpAndSettle();
    await go(tester, AppRoutes.dashboard);
    await shoot(tester, 'dashboard');
  });
}
