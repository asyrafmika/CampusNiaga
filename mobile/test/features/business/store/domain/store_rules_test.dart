import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/features/business/store/data/store_mappers.dart';
import 'package:mobile/features/business/store/domain/store_models.dart';
import 'package:mobile/features/marketplace/data/marketplace_mappers.dart';
import 'package:mobile/features/marketplace/domain/listing.dart';

import '../../../../support/store_fakes.dart';

void main() {
  group('the order state machine, as the app sees it', () {
    test('the seller moves an order forward one step at a time', () {
      expect(
        {for (final s in OrderStatus.values) s: OrderRules.nextStep(s)},
        {
          OrderStatus.pendingConfirmation: OrderAction.confirm,
          OrderStatus.confirmed: OrderAction.prepare,
          OrderStatus.preparing: OrderAction.ready,
          OrderStatus.readyForPickup: OrderAction.complete,
          OrderStatus.completed: null,
          OrderStatus.cancelled: null,
        },
      );
    });

    test('either side may cancel until the order is completed', () {
      expect(OrderStatus.values.where(OrderRules.canCancel), [
        OrderStatus.pendingConfirmation,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.readyForPickup,
      ]);
    });

    test('a buyer can only cancel; a seller also moves it forward', () {
      expect(OrderRules.actionsFor(anOrder()), [OrderAction.cancel]);
      expect(OrderRules.actionsFor(anOrder(iAmBuyer: false)), [
        OrderAction.confirm,
        OrderAction.cancel,
      ]);
      expect(
        OrderRules.actionsFor(
          anOrder(iAmBuyer: false, status: OrderStatus.completed),
        ),
        isEmpty,
      );
    });

    test('status values match the data dictionary', () {
      expect(OrderStatus.values.map((s) => s.wireName), [
        'pending_confirmation',
        'confirmed',
        'preparing',
        'ready_for_pickup',
        'completed',
        'cancelled',
      ]);
      expect(OrderAction.values.map((a) => a.wireName), [
        'confirm',
        'prepare',
        'ready',
        'complete',
        'cancel',
      ]);
      expect(CampaignStatus.values.map((s) => s.wireName), [
        'draft',
        'open',
        'closed',
      ]);
      expect(() => OrderStatus.fromWire('shipped'), throwsFormatException);
    });
  });

  group('campaigns', () {
    test(
      'only open campaigns inside their dates with places left take orders',
      () {
        final now = DateTime.now();
        expect(aCampaign().takesOrdersAt(now), isTrue);
        expect(
          aCampaign(status: CampaignStatus.draft).takesOrdersAt(now),
          isFalse,
        );
        expect(
          aCampaign(status: CampaignStatus.closed).takesOrdersAt(now),
          isFalse,
        );
        expect(aCampaign(allocated: 3).takesOrdersAt(now), isFalse);
        expect(
          aCampaign().takesOrdersAt(now.add(const Duration(days: 8))),
          isFalse,
        );
        expect(
          aCampaign().takesOrdersAt(now.subtract(const Duration(days: 2))),
          isFalse,
        );
      },
    );

    test('one order may take the per-order limit or what is left, whichever is less', () {
      expect(aCampaign(perOrderLimit: 2).maxPerOrder, 2);
      expect(aCampaign(perOrderLimit: 2, allocated: 2).maxPerOrder, 1);
      expect(aCampaign(perOrderLimit: null, allocated: 1).maxPerOrder, 2);
    });

    test('status changes mirror set_campaign_status', () {
      expect(StoreRules.nextStatuses(CampaignStatus.draft), [
        CampaignStatus.open,
        CampaignStatus.closed,
      ]);
      expect(StoreRules.nextStatuses(CampaignStatus.open), [
        CampaignStatus.closed,
      ]);
      expect(StoreRules.nextStatuses(CampaignStatus.closed), isEmpty);
    });

    test('form checks mirror upsert_campaign', () {
      expect(StoreRules.title('Ra'), isNotNull);
      expect(StoreRules.title('Raya brownies'), isNull);
      expect(StoreRules.capacity('0'), isNotNull);
      expect(StoreRules.capacity('10001'), isNotNull);
      expect(StoreRules.capacity('30'), isNull);
      expect(StoreRules.perOrderLimit('', 3), isNull);
      expect(StoreRules.perOrderLimit('4', 3), isNotNull);
      expect(StoreRules.perOrderLimit('0', 3), isNotNull);
      expect(StoreRules.perOrderLimit('2', 3), isNull);
      expect(StoreRules.pickupDetails('Tek'), isNotNull);
      expect(StoreRules.pickupDetails('Tekun lobby'), isNull);
      final now = DateTime(2026, 11, 16, 12);
      expect(StoreRules.dates(now, now, now), isNotNull);
      expect(
        StoreRules.dates(
          now.subtract(const Duration(days: 2)),
          now.subtract(const Duration(days: 1)),
          now,
        ),
        isNotNull,
      );
      expect(
        StoreRules.dates(now, now.add(const Duration(days: 1)), now),
        isNull,
      );
    });
  });

  group('mappers', () {
    test('reads a storefront', () {
      final store = storefrontFromJson({
        'business': {
          'business_id': 'b1',
          'name': 'Ali Bakes',
          'description': 'Brownies',
          'logo_path': 'b1/logo.png',
          'pickup_details': 'Tekun lobby',
          'status': 'approved',
          'owner_name': 'Ali',
        },
        'is_owner': false,
        'categories': ['Food & Beverage'],
        'listings': [
          {
            'id': 'p1',
            'owner_id': 'u2',
            'seller_name': 'Ali',
            'mode': 'business',
            'title': 'Brownie box',
            'description': '',
            'category': 'Food & Beverage',
            'price_sen': 1200,
            'condition': 'new',
            'photo_paths': <String>[],
            'stock': 3,
            'pickup_area': 'Tekun',
            'status': 'available',
            'created_at': '2026-11-16T00:00:00+00:00',
            'business_id': 'b1',
            'business_name': 'Ali Bakes',
          },
        ],
        'campaigns': [
          {
            'campaign_id': 'c1',
            'listing_id': 'p1',
            'listing_title': 'Brownie box',
            'listing_photo': null,
            'title': 'Raya brownies',
            'price_sen': 1000,
            'start_at': '2026-11-16T00:00:00+00:00',
            'close_at': '2026-11-23T00:00:00+00:00',
            'capacity': 3,
            'allocated_qty': 1,
            'remaining': 2,
            'per_order_limit': 2,
            'pickup_details': 'Tekun lobby',
            'status': 'open',
          },
        ],
      });
      expect(store.business.name, 'Ali Bakes');
      expect(store.business.logoPath, 'b1/logo.png');
      expect(store.listings.single.isBusiness, isTrue);
      expect(store.listings.single.businessName, 'Ali Bakes');
      expect(store.campaigns.single.remaining, 2);
      expect(store.campaignsFor('p1'), hasLength(1));
      expect(store.campaignsFor('p2'), isEmpty);
    });

    test('reads a campaign row from the table too', () {
      final c = campaignFromRow({
        'id': 'c2',
        'listing_id': 'p1',
        'title': 'Cookie week',
        'price_sen': 700,
        'start_at': '2026-11-16T00:00:00+00:00',
        'close_at': '2026-11-23T00:00:00+00:00',
        'capacity': 10,
        'allocated_qty': 0,
        'per_order_limit': null,
        'pickup_details': 'Tekun lobby',
        'status': 'draft',
      });
      expect(c.id, 'c2');
      expect(c.perOrderLimit, isNull);
      expect(c.status, CampaignStatus.draft);
    });

    test('reads an order card, and rejects an unknown status', () {
      Map<String, dynamic> row(String status) => {
        'id': 'o1',
        'listing_id': 'p1',
        'listing_title': 'Brownie box',
        'listing_photo': null,
        'business_id': 'b1',
        'business_name': 'Ali Bakes',
        'campaign_id': null,
        'campaign_title': null,
        'qty': 2,
        'unit_price_sen': 1200,
        'total_sen': 2400,
        'status': status,
        'buyer_note': null,
        'collection_details': 'Tekun lobby',
        'cancelled_by': null,
        'created_at': '2026-11-16T00:00:00+00:00',
        'updated_at': '2026-11-16T00:00:00+00:00',
        'completed_at': null,
        'i_am_buyer': true,
        'other_party_name': 'Ali',
        'other_party_email': null,
      };
      final order = orderFromRow(row('ready_for_pickup'));
      expect(order.totalSen, 2400);
      expect(order.status, OrderStatus.readyForPickup);
      expect(order.isPreOrder, isFalse);
      expect(() => orderFromRow(row('shipped')), throwsFormatException);
    });

    test('a listing row without a mode is personal (older databases)', () {
      final Listing listing = listingFromRow({
        'id': 'l1',
        'owner_id': 'u1',
        'title': 'Calculator',
        'description': '',
        'category': 'Stationery',
        'price_sen': 2500,
        'condition': 'good',
        'photo_paths': <String>[],
        'stock': 1,
        'pickup_area': 'Tekun',
        'status': 'available',
        'created_at': '2026-11-16T00:00:00+00:00',
      });
      expect(listing.isBusiness, isFalse);
      expect(listing.businessName, isNull);
    });
  });
}
