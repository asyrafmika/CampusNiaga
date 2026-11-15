import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/core/utils/money.dart';
import 'package:mobile/features/marketplace/domain/listing.dart';
import 'package:mobile/features/marketplace/domain/listing_input.dart';
import 'package:mobile/features/marketplace/domain/listing_query.dart';
import 'package:mobile/features/marketplace/domain/reservation.dart';

import '../../../support/marketplace_fakes.dart';

void main() {
  group('formatRm', () {
    test(
      'whole ringgit has no decimals',
      () => expect(formatRm(2500), 'RM 25'),
    );
    test('sen show two decimals', () => expect(formatRm(2550), 'RM 25.50'));
    test('small amounts', () => expect(formatRm(5), 'RM 0.05'));
    test('zero', () => expect(formatRm(0), 'RM 0'));
    test('thousands are grouped', () {
      expect(formatRm(125000), 'RM 1,250');
      expect(formatRm(10000000), 'RM 100,000');
    });
  });

  group('parseRmToSen', () {
    test('reads whole and decimal prices', () {
      expect(parseRmToSen('25'), 2500);
      expect(parseRmToSen('25.5'), 2550);
      expect(parseRmToSen('25.50'), 2550);
      expect(parseRmToSen(' RM 1,250.05 '), 125005);
      expect(parseRmToSen('0'), 0);
    });

    test('rejects anything else', () {
      for (final bad in ['', 'abc', '-5', '25.505', '1.2.3', 'RM']) {
        expect(parseRmToSen(bad), isNull, reason: bad);
      }
    });

    test('round-trips with senToInput', () {
      for (final sen in [0, 5, 2500, 2550, 125005]) {
        expect(parseRmToSen(senToInput(sen)), sen);
      }
    });
  });

  group('ListingRules', () {
    test('title must be 3 to 80 characters after trimming', () {
      expect(ListingRules.title('  ab  '), isNotNull);
      expect(ListingRules.title('abc'), isNull);
      expect(ListingRules.title('a' * 80), isNull);
      expect(ListingRules.title('a' * 81), isNotNull);
    });

    test('price must parse and stay under RM 100,000', () {
      expect(ListingRules.price('25'), isNull);
      expect(ListingRules.price('100000'), isNull);
      expect(ListingRules.price('100000.01'), isNotNull);
      expect(ListingRules.price('free'), isNotNull);
    });

    test('quantity must be 1 to 999', () {
      expect(ListingRules.quantity('1'), isNull);
      expect(ListingRules.quantity('999'), isNull);
      expect(ListingRules.quantity('0'), isNotNull);
      expect(ListingRules.quantity('1000'), isNotNull);
      expect(ListingRules.quantity('two'), isNotNull);
    });

    test('pickup area and description limits', () {
      expect(ListingRules.pickupArea(' '), isNotNull);
      expect(ListingRules.pickupArea('Tekun'), isNull);
      expect(ListingRules.description('a' * 1000), isNull);
      expect(ListingRules.description('a' * 1001), isNotNull);
    });

    test('publishing needs a photo', () {
      expect(ListingRules.publishProblem(0), isNotNull);
      expect(ListingRules.publishProblem(1), isNull);
    });

    test('photo types are limited to JPEG, PNG and WebP', () {
      expect(NewPhoto.extensionOf('IMG_1.JPG'), 'jpg');
      expect(NewPhoto.extensionOf('a.webp'), 'webp');
      expect(NewPhoto.extensionOf('a.gif'), isNull);
      expect(NewPhoto.extensionOf('noext'), isNull);
    });
  });

  group('ownerActionsFor', () {
    test('matches the transitions set_listing_status allows', () {
      expect(ownerActionsFor(aListing(status: ListingStatus.draft)), [
        OwnerAction.edit,
        OwnerAction.publish,
      ]);
      expect(ownerActionsFor(aListing()), [
        OwnerAction.edit,
        OwnerAction.markSold,
        OwnerAction.close,
      ]);
      expect(ownerActionsFor(aListing(status: ListingStatus.closed)), [
        OwnerAction.edit,
        OwnerAction.reopen,
      ]);
      expect(
        ownerActionsFor(aListing(status: ListingStatus.reserved)),
        isEmpty,
      );
      expect(ownerActionsFor(aListing(status: ListingStatus.sold)), isEmpty);
    });

    test('each action targets the right status', () {
      expect(targetStatusOf(OwnerAction.publish), ListingStatus.available);
      expect(targetStatusOf(OwnerAction.reopen), ListingStatus.available);
      expect(targetStatusOf(OwnerAction.close), ListingStatus.closed);
      expect(targetStatusOf(OwnerAction.markSold), ListingStatus.sold);
      expect(targetStatusOf(OwnerAction.edit), isNull);
    });
  });

  group('actionsFor (reservations)', () {
    test('the seller accepts or declines a request', () {
      expect(actionsFor(aReservation()), [
        ReservationAction.accept,
        ReservationAction.decline,
      ]);
    });

    test('the seller collects or cancels an accepted one', () {
      expect(actionsFor(aReservation(status: ReservationStatus.accepted)), [
        ReservationAction.collect,
        ReservationAction.cancel,
      ]);
    });

    test('the buyer can only cancel, and only while active', () {
      expect(actionsFor(aReservation(iAmBuyer: true)), [
        ReservationAction.cancel,
      ]);
      expect(
        actionsFor(
          aReservation(iAmBuyer: true, status: ReservationStatus.accepted),
        ),
        [ReservationAction.cancel],
      );
    });

    test('finished reservations offer nothing', () {
      for (final status in [
        ReservationStatus.declined,
        ReservationStatus.cancelled,
        ReservationStatus.collected,
        ReservationStatus.expired,
      ]) {
        expect(actionsFor(aReservation(status: status)), isEmpty);
        expect(
          actionsFor(aReservation(status: status, iAmBuyer: true)),
          isEmpty,
        );
      }
    });

    test('only requested and accepted are active', () {
      expect(ReservationStatus.values.where((s) => s.isActive), [
        ReservationStatus.requested,
        ReservationStatus.accepted,
      ]);
    });
  });

  group('ListingQuery', () {
    test('has value equality, so the same query reuses its feed', () {
      expect(
        const ListingQuery(search: 'lamp', category: 'Books'),
        const ListingQuery(search: 'lamp', category: 'Books'),
      );
      expect(
        const ListingQuery(search: 'lamp'),
        isNot(const ListingQuery(search: 'lamp', sort: ListingSort.priceAsc)),
      );
    });

    test('copyWith can clear a filter', () {
      const query = ListingQuery(category: 'Books', minPriceSen: 100);
      expect(query.activeFilterCount, 2);
      final cleared = query.copyWith(category: () => null);
      expect(cleared.category, isNull);
      expect(cleared.minPriceSen, 100);
      expect(query.clearFilters().activeFilterCount, 0);
    });
  });

  group('wire values', () {
    test('match the data dictionary exactly', () {
      expect(ListingStatus.values.map((s) => s.wireName), [
        'draft',
        'available',
        'reserved',
        'sold',
        'closed',
      ]);
      expect(ListingCondition.values.map((c) => c.wireName), [
        'new',
        'like_new',
        'good',
        'fair',
      ]);
      expect(ReservationStatus.values.map((s) => s.wireName), [
        'requested',
        'accepted',
        'declined',
        'cancelled',
        'collected',
        'expired',
      ]);
      expect(ReportReason.values.map((r) => r.wireName), [
        'prohibited_item',
        'scam',
        'offensive',
        'misleading',
        'other',
      ]);
    });

    test('unknown values are rejected rather than guessed', () {
      expect(() => ListingStatus.fromWire('gone'), throwsFormatException);
      expect(() => ReservationStatus.fromWire(null), throwsFormatException);
    });
  });

  group('AppFailure', () {
    test('uses the database message for a known reason', () {
      final failure = AppFailure.fromServer(
        details: 'ITEM_UNAVAILABLE',
        message: 'Only 2 left.',
      );
      expect(failure.reason, AppFailureReason.itemUnavailable);
      expect(failure.message, 'Only 2 left.');
    });

    test('falls back to a generic message for anything else', () {
      expect(
        AppFailure.fromServer(details: 'Failing row contains …', message: 'x'),
        same(AppFailure.unknownFailure),
      );
      expect(
        AppFailure.messageOf(Exception('boom')),
        AppFailure.unknownFailure.message,
      );
    });
  });
}
