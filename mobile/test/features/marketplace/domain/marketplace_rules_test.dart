import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/core/domain/payment.dart';
import 'package:mobile/core/utils/money.dart';
import 'package:mobile/features/marketplace/domain/listing.dart';
import 'package:mobile/features/marketplace/domain/listing_input.dart';
import 'package:mobile/features/marketplace/domain/listing_query.dart';
import 'package:mobile/features/marketplace/domain/purchase.dart';

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
        OwnerAction.delete,
      ]);
      expect(ownerActionsFor(aListing()), [
        OwnerAction.edit,
        OwnerAction.markSold,
        OwnerAction.delete,
      ]);
      expect(ownerActionsFor(aListing(status: ListingStatus.closed)), [
        OwnerAction.edit,
        OwnerAction.reopen,
        OwnerAction.delete,
      ]);
      expect(ownerActionsFor(aListing(status: ListingStatus.sold)), [
        OwnerAction.delete,
      ]);
      expect(
        ownerActionsFor(
          aListing(status: ListingStatus.sold, businessId: 'b1', stock: 0),
        ),
        [OwnerAction.edit, OwnerAction.delete],
      );
      expect(ownerActionsFor(aListing(status: ListingStatus.deleted)), isEmpty);
      expect(
        OwnerAction.values,
        isNot(contains(predicate<OwnerAction>((a) => a.name == 'close'))),
        reason: 'listings are deleted, not closed (ADR 0008)',
      );
    });

    test('each action targets the right status', () {
      expect(targetStatusOf(OwnerAction.publish), ListingStatus.available);
      expect(targetStatusOf(OwnerAction.reopen), ListingStatus.available);
      expect(targetStatusOf(OwnerAction.delete), ListingStatus.deleted);
      expect(targetStatusOf(OwnerAction.markSold), ListingStatus.sold);
      expect(targetStatusOf(OwnerAction.edit), isNull);
    });
  });

  group('PurchaseRules', () {
    final now = DateTime.now();
    PaymentSummary pay(PaymentStatus status) =>
        PaymentSummary(id: 'pay1', status: status, dueAt: now);

    test('the seller completes or cancels; relists cash after 24 hours', () {
      expect(PurchaseRules.actionsFor(aPurchase(), now), [
        PurchaseAction.complete,
        PurchaseAction.cancel,
      ]);
      expect(PurchaseRules.actionsFor(aPurchase(relistFrom: now), now), [
        PurchaseAction.complete,
        PurchaseAction.relist,
        PurchaseAction.cancel,
      ]);
    });

    test('a transfer is completed only after its payment, never relisted', () {
      expect(
        PurchaseRules.actionsFor(
          aPurchase(payment: pay(PaymentStatus.submitted)),
          now,
        ),
        [PurchaseAction.cancel],
      );
      expect(
        PurchaseRules.actionsFor(
          aPurchase(
            status: PurchaseStatus.awaitingHandover,
            payment: pay(PaymentStatus.accepted),
          ),
          now.add(const Duration(days: 30)),
        ),
        [PurchaseAction.complete, PurchaseAction.cancel],
      );
    });

    test('the buyer can only cancel, until the receipt is sent', () {
      for (final payment in [null, pay(PaymentStatus.awaitingProof)]) {
        expect(
          PurchaseRules.actionsFor(
            aPurchase(iAmBuyer: true, payment: payment, relistFrom: now),
            now,
          ).where((a) => a != PurchaseAction.relist),
          [PurchaseAction.cancel],
        );
      }
      for (final status in [PaymentStatus.submitted, PaymentStatus.accepted]) {
        expect(
          PurchaseRules.actionsFor(
            aPurchase(iAmBuyer: true, payment: pay(status)),
            now,
          ),
          isEmpty,
        );
      }
    });

    test('a buyer is never offered Relist', () {
      expect(
        PurchaseRules.actionsFor(
          aPurchase(iAmBuyer: true, relistFrom: now),
          now,
        ),
        [PurchaseAction.cancel],
      );
    });

    test('finished purchases offer nothing', () {
      for (final status in [
        PurchaseStatus.completed,
        PurchaseStatus.cancelled,
      ]) {
        for (final buyer in [true, false]) {
          expect(
            PurchaseRules.actionsFor(
              aPurchase(status: status, iAmBuyer: buyer),
              now,
            ),
            isEmpty,
          );
        }
      }
    });

    test('only the two awaiting statuses are active', () {
      expect(PurchaseStatus.values.where((s) => s.isActive), [
        PurchaseStatus.awaitingPayment,
        PurchaseStatus.awaitingHandover,
      ]);
    });

    test('a seller cancels with a reason of up to 200 characters', () {
      expect(PurchaseRules.cancelReason('  '), isNotNull);
      expect(PurchaseRules.cancelReason('x' * 201), isNotNull);
      expect(PurchaseRules.cancelReason('It broke'), isNull);
    });

    test('chat stays with the buyer, and for refunds after cancelling', () {
      expect(aPurchase().canChat, isTrue);
      expect(aPurchase(status: PurchaseStatus.completed).canChat, isTrue);
      expect(aPurchase(status: PurchaseStatus.cancelled).canChat, isFalse);
      for (final (status, chat) in [
        (PaymentStatus.cancelled, true),
        (PaymentStatus.rejected, true),
        (PaymentStatus.accepted, true),
        (PaymentStatus.expired, false),
      ]) {
        expect(
          aPurchase(
            status: PurchaseStatus.cancelled,
            payment: pay(status),
          ).canChat,
          chat,
          reason: status.name,
        );
      }
    });

    test('a cancellation says who and why', () {
      String text(String? by, {bool buyer = true, String? reason}) =>
          PurchaseRules.explanation(
            aPurchase(
              iAmBuyer: buyer,
              status: PurchaseStatus.cancelled,
              cancelledBy: by,
              cancelReason: reason,
            ),
          );
      expect(text('buyer'), 'You cancelled this purchase.');
      expect(text('buyer', buyer: false), 'The buyer cancelled this purchase.');
      expect(
        text('seller', reason: 'It broke'),
        'The seller cancelled: It broke',
      );
      expect(text(null), 'Cancelled this purchase.');
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
        'sold',
        'closed',
        'deleted',
      ]);
      expect(ListingCondition.values.map((c) => c.wireName), [
        'new',
        'like_new',
        'good',
        'fair',
      ]);
      expect(PurchaseStatus.values.map((s) => s.wireName), [
        'awaiting_payment',
        'awaiting_handover',
        'completed',
        'cancelled',
      ]);
      expect(PaymentMethod.values.map((m) => m.wireName), ['cash', 'transfer']);
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
      expect(() => ListingStatus.fromWire('reserved'), throwsFormatException);
      expect(() => PaymentMethod.fromWire('card'), throwsFormatException);
      expect(() => PurchaseStatus.fromWire(null), throwsFormatException);
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
