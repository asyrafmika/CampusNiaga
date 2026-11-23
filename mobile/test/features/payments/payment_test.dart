import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/core/domain/payment.dart';
import 'package:mobile/core/router/app_router.dart';
import 'package:mobile/core/router/app_routes.dart';
import 'package:mobile/features/auth/domain/user_access.dart';
import 'package:mobile/features/auth/presentation/profile_screen.dart';
import 'package:mobile/features/business/store/data/store_mappers.dart';
import 'package:mobile/features/business/store/domain/store_models.dart';
import 'package:mobile/features/marketplace/data/marketplace_mappers.dart';
import 'package:mobile/features/marketplace/domain/purchase.dart';
import 'package:mobile/features/marketplace/presentation/listing_detail_screen.dart';
import 'package:mobile/features/payments/data/payment_mappers.dart';
import 'package:mobile/features/payments/domain/payment_models.dart';
import 'package:mobile/features/payments/presentation/payment_details_screen.dart';
import 'package:mobile/features/payments/presentation/payment_screen.dart';
import 'package:mobile/features/payments/presentation/widgets/payment_widgets.dart';

import '../../support/app_harness.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/payment_fakes.dart';
import '../../support/store_fakes.dart';

/// Runs Ali Bakes (approved).
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

PaymentSummary _summary(PaymentStatus status, {String? reason}) =>
    PaymentSummary(
      id: 'pay1',
      status: status,
      dueAt: DateTime.now().add(const Duration(minutes: 20)),
      rejectReason: reason,
    );

/// Transfer payments (ADR 0005): the rules, the mappers, choosing transfer,
/// the payment page for both sides, payment details and the cards.
void main() {
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('rules', () {
    test(
      'every payment status reads from the database; unknown ones throw',
      () {
        for (final s in PaymentStatus.values) {
          expect(PaymentStatus.fromWire(s.wireName), s);
        }
        expect(() => PaymentStatus.fromWire('paid'), throwsFormatException);
        expect(PaymentStatus.awaitingProof.isOpen, isTrue);
        expect(PaymentStatus.submitted.isOpen, isTrue);
        expect(PaymentStatus.accepted.isOpen, isFalse);
        expect(PaymentStatus.expired.isOpen, isFalse);
      },
    );

    test(
      'account numbers: digits only, 6 to 20, spaces and dashes allowed',
      () {
        expect(PaymentRules.accountNumber('1234-5678 90'), isNull);
        expect(PaymentRules.accountNumber(''), isNull);
        expect(PaymentRules.accountNumber('12345'), isNotNull);
        expect(PaymentRules.accountNumber('12ab5678'), isNotNull);
        expect(PaymentRules.accountNumber('1' * 21), isNotNull);
        expect(
          PaymentRules.normaliseAccountNumber('1234-5678 90'),
          '1234567890',
        );
      },
    );

    test('bank fields go together; empty means remove', () {
      expect(
        PaymentRules.together(bankName: '', accountName: '', accountNumber: ''),
        isNull,
      );
      expect(
        PaymentRules.together(
          bankName: 'Maybank',
          accountName: 'Siti',
          accountNumber: '1234567890',
        ),
        isNull,
      );
      expect(
        PaymentRules.together(
          bankName: 'Maybank',
          accountName: '',
          accountNumber: '1234567890',
        ),
        isNotNull,
      );
      expect(PaymentRules.bankName('M'), isNotNull);
      expect(PaymentRules.accountName('x' * 81), isNotNull);
    });

    test('a rejection needs a reason of up to 200 characters', () {
      expect(PaymentRules.rejectReason('  '), isNotNull);
      expect(PaymentRules.rejectReason('x' * 201), isNotNull);
      expect(PaymentRules.rejectReason('Nothing arrived'), isNull);
    });

    test('time left reads in minutes, then under a minute, then nothing', () {
      final now = DateTime(2026, 11, 18, 10);
      expect(
        PaymentRules.timeLeft(
          now.add(const Duration(minutes: 29, seconds: 30)),
          now,
        ),
        '29 min left',
      );
      expect(
        PaymentRules.timeLeft(now.add(const Duration(seconds: 40)), now),
        'Under a minute left',
      );
      expect(PaymentRules.timeLeft(now, now), isNull);
      expect(
        PaymentRules.timeLeft(now.subtract(const Duration(minutes: 1)), now),
        isNull,
      );
    });

    test('a buyer may cancel until the proof is sent', () {
      expect(PaymentRules.buyerMayCancel(null), isTrue);
      expect(
        PaymentRules.buyerMayCancel(_summary(PaymentStatus.awaitingProof)),
        isTrue,
      );
      expect(
        PaymentRules.buyerMayCancel(_summary(PaymentStatus.submitted)),
        isFalse,
      );
      expect(
        PaymentRules.buyerMayCancel(_summary(PaymentStatus.accepted)),
        isFalse,
      );
    });

    test('a transfer purchase moves on through its payment', () {
      final now = DateTime.now();
      final pending = aPurchase(payment: _summary(PaymentStatus.submitted));
      expect(PurchaseRules.actionsFor(pending, now), [PurchaseAction.cancel]);
      expect(PurchaseRules.actionsFor(aPurchase(), now), [
        PurchaseAction.complete,
        PurchaseAction.cancel,
      ]);
      expect(
        PurchaseRules.actionsFor(
          aPurchase(iAmBuyer: true, payment: _summary(PaymentStatus.submitted)),
          now,
        ),
        isEmpty,
        reason: 'a buyer who paid cannot cancel on their own',
      );
      expect(
        PurchaseRules.actionsFor(
          aPurchase(
            iAmBuyer: true,
            payment: _summary(PaymentStatus.awaitingProof),
          ),
          now,
        ),
        [PurchaseAction.cancel],
      );
      expect(
        PurchaseRules.explanation(
          aPurchase(
            iAmBuyer: true,
            payment: _summary(PaymentStatus.awaitingProof),
          ),
        ),
        contains('send your proof'),
      );
      expect(
        PurchaseRules.explanation(
          aPurchase(
            status: PurchaseStatus.cancelled,
            cancelledBy: 'seller',
            cancelReason: 'Not received',
            payment: _summary(PaymentStatus.rejected, reason: 'Not received'),
          ),
        ),
        contains('Not received'),
      );
    });

    test('a transfer order is confirmed through its payment', () {
      final selling = anOrder(
        iAmBuyer: false,
        payment: _summary(PaymentStatus.submitted),
      );
      expect(OrderRules.actionsFor(selling), [OrderAction.cancel]);
      expect(OrderRules.actionsFor(anOrder(iAmBuyer: false)), [
        OrderAction.confirm,
        OrderAction.cancel,
      ]);
      expect(
        OrderRules.actionsFor(
          anOrder(payment: _summary(PaymentStatus.submitted)),
        ),
        isEmpty,
      );
      expect(
        OrderRules.actionsFor(
          anOrder(
            iAmBuyer: false,
            status: OrderStatus.confirmed,
            payment: _summary(PaymentStatus.accepted),
          ),
        ),
        [OrderAction.prepare, OrderAction.cancel],
        reason: 'after the payment, the order moves on as usual',
      );
    });
  });

  group('mappers', () {
    final row = <String, dynamic>{
      'payment_id': 'pay1',
      'payment_status': 'rejected',
      'payment_due_at': '2026-11-18T10:30:00Z',
      'payment_reject_reason': 'Not received',
    };

    test('a cash deal has no payment; a transfer deal has one', () {
      expect(paymentSummaryFromRow(const {'payment_id': null}), isNull);
      final p = paymentSummaryFromRow(row)!;
      expect(p.status, PaymentStatus.rejected);
      expect(p.dueAt, DateTime.utc(2026, 11, 18, 10, 30));
      expect(p.rejectReason, 'Not received');
    });

    test('order and purchase cards carry the payment', () {
      final purchase = purchaseFromRow({
        'id': 'r1',
        'listing_id': 'l1',
        'listing_title': 'Calculator',
        'pickup_area': 'Tekun',
        'unit_price_sen': 2500,
        'total_sen': 2500,
        'qty': 1,
        'payment_method': 'transfer',
        'status': 'cancelled',
        'created_at': '2026-11-18T10:00:00Z',
        'i_am_buyer': true,
        'other_party_name': 'Siti',
        ...row,
      });
      expect(purchase.payment?.status, PaymentStatus.rejected);
      final order = orderFromRow({
        'id': 'o1',
        'listing_id': 'p1',
        'listing_title': 'Brownie box',
        'business_id': 'b1',
        'business_name': 'Ali Bakes',
        'qty': 1,
        'unit_price_sen': 500,
        'total_sen': 500,
        'status': 'cancelled',
        'cancelled_by': 'system',
        'created_at': '2026-11-18T10:00:00Z',
        'i_am_buyer': true,
        'other_party_name': 'Ali',
        'payment_id': 'pay2',
        'payment_status': 'expired',
        'payment_due_at': '2026-11-18T10:30:00Z',
      });
      expect(order.payment?.status, PaymentStatus.expired);
      expect(order.cancelledBy, 'system');
    });

    test('the payment page, with and without where to pay', () {
      final json = {
        'payment_id': 'pay1',
        'order_id': null,
        'purchase_id': 'r1',
        'i_am_buyer': true,
        'item_title': 'Calculator',
        'qty': 1,
        'seller_name': 'Siti',
        'amount_sen': 2500,
        'status': 'awaiting_proof',
        'due_at': '2026-11-18T10:30:00Z',
        'pay_to': {
          'bank_name': 'Maybank',
          'account_name': 'Siti',
          'account_number': '1234567890',
          'qr_path': null,
        },
      };
      final view = paymentViewFromJson(json);
      expect(view.payTo?.accountNumber, '1234567890');
      expect(view.payTo?.hasBank, isTrue);
      expect(view.purchaseId, 'r1');
      expect(paymentViewFromJson({...json, 'pay_to': null}).payTo, isNull);
      expect(
        () => paymentViewFromJson({...json, 'status': 'paid'}),
        throwsFormatException,
      );
    });

    test('saved details split into the student’s and the business’s', () {
      final saved = savedDetailsFromRows([
        {
          'business_id': null,
          'bank_name': 'CIMB',
          'account_name': 'Ali',
          'account_number': '111111',
        },
        {'business_id': 'b1', 'qr_path': 'u2/qr.png'},
      ]);
      expect(saved.personal?.bankName, 'CIMB');
      expect(saved.business?.qrPath, 'u2/qr.png');
      expect(saved.business?.hasBank, isFalse);
    });
  });

  group('choosing transfer', () {
    testWidgets('a business that takes transfers: order, then pay', (
      tester,
    ) async {
      final store = FakeStoreRepository();
      await pumpApp(
        tester,
        () async => student,
        listings: FakeListingRepository(feed: [aProduct()]),
        store: store,
        payments: FakePaymentRepository(acceptsTransferResult: true),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Brownie box').first);
      await tapVisible(tester, find.byKey(ListingDetailScreen.orderKey));

      await tapVisible(
        tester,
        find.byKey(PaymentMethodPicker.optionKey(PaymentMethod.transfer)),
      );
      await tapVisible(tester, find.byKey(const Key('order-submit')));

      expect(store.calls, ['order p1 x1 stock transfer']);
      expect(find.byType(PaymentScreen), findsOneWidget);
      expect(find.text('1234567890'), findsOneWidget);
    });

    testWidgets('a cash-only seller offers cash on pickup only', (
      tester,
    ) async {
      final store = FakeStoreRepository();
      await pumpApp(
        tester,
        () async => student,
        listings: FakeListingRepository(feed: [aProduct()]),
        store: store,
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Brownie box').first);
      await tapVisible(tester, find.byKey(ListingDetailScreen.orderKey));

      expect(
        find.byKey(PaymentMethodPicker.optionKey(PaymentMethod.transfer)),
        findsNothing,
      );
      expect(
        find.text('This seller takes cash on pickup only.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('order-submit')));
      expect(store.calls, ['order p1 x1 stock']);
      expect(find.byType(PaymentScreen), findsNothing);
    });

    testWidgets('buying a personal item by transfer opens the payment page', (
      tester,
    ) async {
      final purchases = FakePurchaseRepository();
      await pumpApp(
        tester,
        () async => student,
        purchases: purchases,
        payments: FakePaymentRepository(acceptsTransferResult: true),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Casio FX-570 calculator').first);
      await tapVisible(tester, find.byKey(ListingDetailScreen.buyKey));
      await tapVisible(
        tester,
        find.byKey(PaymentMethodPicker.optionKey(PaymentMethod.transfer)),
      );
      expect(
        find.textContaining('Send your receipt within 30 minutes'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(ListingDetailScreen.confirmBuyKey));

      expect(purchases.calls, ['buy l1 x1 transfer']);
      expect(find.byType(PaymentScreen), findsOneWidget);
    });
  });

  group('the payment page', () {
    testWidgets('the buyer sees where to pay, then sends a screenshot', (
      tester,
    ) async {
      final payments = FakePaymentRepository();
      final purchases = FakePurchaseRepository(
        buying: [
          aPurchase(
            iAmBuyer: true,
            payment: _summary(PaymentStatus.awaitingProof),
          ),
        ],
      );
      await pumpApp(
        tester,
        () async => student,
        purchases: purchases,
        payments: payments,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchases'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(PaymentStrip.payNowKey('pay1')));

      expect(find.text('Maybank'), findsOneWidget);
      expect(find.text('1234567890'), findsOneWidget);
      expect(find.text('RM 25'), findsWidgets);
      final send = tester.widget<FilledButton>(
        find.byKey(PaymentScreen.sendProofKey),
      );
      expect(
        send.onPressed,
        isNull,
        reason: 'nothing to send before choosing a screenshot',
      );

      await tapVisible(tester, find.byKey(PaymentScreen.chooseProofKey));
      await tapVisible(tester, find.byKey(PaymentScreen.sendProofKey));

      expect(payments.calls, ['proof pay1 png']);
      expect(find.text('Proof sent to the seller.'), findsOneWidget);
    });

    testWidgets('a refused proof shows the database’s reason', (tester) async {
      final payments = FakePaymentRepository()
        ..failWith = const AppFailure(
          AppFailureReason.invalidTransition,
          'The 30 minutes to pay have run out, so the item went back on sale.',
        );
      final purchases = FakePurchaseRepository(
        buying: [
          aPurchase(
            iAmBuyer: true,
            payment: _summary(PaymentStatus.awaitingProof),
          ),
        ],
      );
      // The page loads before the failure is set on sending.
      payments.payments['pay1'] = aPayment();
      final failure = payments.failWith;
      payments.failWith = null;
      await pumpApp(
        tester,
        () async => student,
        purchases: purchases,
        payments: payments,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchases'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(PaymentStrip.payNowKey('pay1')));
      await tapVisible(tester, find.byKey(PaymentScreen.chooseProofKey));
      payments.failWith = failure;
      await tapVisible(tester, find.byKey(PaymentScreen.sendProofKey));

      expect(find.textContaining('have run out'), findsOneWidget);
    });

    testWidgets('the seller checks the proof: a rejection needs a reason', (
      tester,
    ) async {
      final payments = FakePaymentRepository(
        payments: {
          'pay1': aPayment(
            iAmBuyer: false,
            status: PaymentStatus.submitted,
            proofPath: 'u1/pay1/proof.png',
          ),
        },
      );
      final purchases = FakePurchaseRepository(
        selling: [aPurchase(payment: _summary(PaymentStatus.submitted))],
      );
      await pumpApp(
        tester,
        () async => student,
        purchases: purchases,
        payments: payments,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchases'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selling'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pay-now-pay1')), findsNothing);
      await tapVisible(tester, find.byKey(PaymentStrip.checkKey('pay1')));

      expect(find.text('The buyer’s proof'), findsOneWidget);
      expect(
        find.text('1234567890'),
        findsNothing,
        reason: 'sellers don’t get the pay-to block',
      );

      await tapVisible(tester, find.byKey(PaymentScreen.rejectKey));
      await tester.tap(find.byKey(PaymentScreen.rejectConfirmKey));
      await tester.pumpAndSettle();
      expect(
        find.text('Say why, so the buyer knows what to do.'),
        findsOneWidget,
      );
      expect(payments.calls, isEmpty);
      await tester.enterText(
        find.byKey(PaymentScreen.rejectReasonKey),
        'Nothing arrived',
      );
      await tester.tap(find.byKey(PaymentScreen.rejectConfirmKey));
      await tester.pumpAndSettle();

      expect(payments.calls, ['review pay1 reject Nothing arrived']);
    });

    testWidgets('the seller accepts after confirming the money arrived', (
      tester,
    ) async {
      final payments = FakePaymentRepository(
        payments: {
          'pay1': aPayment(
            iAmBuyer: false,
            status: PaymentStatus.submitted,
            proofPath: 'u1/pay1/proof.png',
          ),
        },
      );
      final store = FakeStoreRepository(
        selling: [
          anOrder(
            id: 'o2',
            iAmBuyer: false,
            payment: _summary(PaymentStatus.submitted),
          ),
        ],
      );
      await pumpApp(
        tester,
        () async => owner,
        store: store,
        payments: payments,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(ProfileScreen.ordersKey));
      await tester.tap(find.text('My business'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('order-next-o2')),
        findsNothing,
        reason: 'a transfer order is confirmed through its payment',
      );
      await tapVisible(tester, find.byKey(PaymentStrip.checkKey('pay1')));
      await tapVisible(tester, find.byKey(PaymentScreen.acceptKey));
      await tester.tap(find.text('Not yet'));
      await tester.pumpAndSettle();
      expect(payments.calls, isEmpty);
      await tapVisible(tester, find.byKey(PaymentScreen.acceptKey));
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(payments.calls, ['review pay1 accept']);
    });

    testWidgets('a closed payment shows why, with no actions', (tester) async {
      final payments = FakePaymentRepository(
        payments: {
          'pay1': aPayment(
            status: PaymentStatus.rejected,
            rejectReason: 'Wrong amount',
            proofPath: 'u1/pay1/p.png',
          ),
        },
      );
      final purchases = FakePurchaseRepository(
        buying: [
          aPurchase(
            iAmBuyer: true,
            status: PurchaseStatus.cancelled,
            payment: _summary(PaymentStatus.rejected, reason: 'Wrong amount'),
          ),
        ],
      );
      await pumpApp(
        tester,
        () async => student,
        purchases: purchases,
        payments: payments,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchases'));
      await tester.pumpAndSettle();
      expect(find.text('Payment rejected: Wrong amount'), findsOneWidget);
      await tapVisible(tester, find.text('Payment rejected: Wrong amount'));

      expect(
        find.text('The payment was rejected: Wrong amount'),
        findsOneWidget,
      );
      expect(find.byKey(PaymentScreen.sendProofKey), findsNothing);
      expect(find.text('Proof you sent'), findsOneWidget);
    });
  });

  group('cards', () {
    testWidgets('an order cancelled because time ran out says so', (
      tester,
    ) async {
      final store = FakeStoreRepository(
        buying: [
          anOrder(
            status: OrderStatus.cancelled,
            cancelledBy: 'system',
            payment: _summary(PaymentStatus.expired),
          ),
        ],
      );
      await pumpApp(tester, () async => student, store: store);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(ProfileScreen.ordersKey));

      expect(
        find.text('Cancelled: the payment wasn’t sent in time'),
        findsOneWidget,
      );
      expect(
        find.text('The payment wasn’t completed in time.'),
        findsOneWidget,
      );
    });
  });

  group('payment details', () {
    // A published listing's payment step, as when editing it.
    Future<void> openDetails(WidgetTester tester) async {
      await tester.pumpAndSettle();
      ProviderScope.containerOf(tester.element(find.byType(CampusNiagaApp)))
          .read(appRouterProvider)
          .push(AppRoutes.listingPayment('l1'));
      await tester.pumpAndSettle();
    }

    testWidgets('Profile has no payment details: they come with a listing', (
      tester,
    ) async {
      await pumpApp(tester, () async => student);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Payment details'), findsNothing);
    });

    testWidgets('half a bank account is refused before saving', (tester) async {
      final payments = FakePaymentRepository();
      await pumpApp(tester, () async => student, payments: payments);
      await openDetails(tester);

      await tester.enterText(find.byKey(PaymentDetailsForm.bankKey), 'Maybank');
      await tester.enterText(
        find.byKey(PaymentDetailsForm.numberKey),
        '1234567890',
      );
      await tapVisible(tester, find.byKey(PaymentDetailsForm.saveKey));
      expect(find.textContaining('together'), findsOneWidget);
      // Let the message go, so it doesn't cover the button.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(PaymentDetailsForm.numberKey), '12ab');
      await tester.enterText(find.byKey(PaymentDetailsForm.nameKey), 'Ali');
      await tapVisible(tester, find.byKey(PaymentDetailsForm.saveKey));
      expect(
        find.text('An account number has 6 to 20 digits.'),
        findsOneWidget,
      );
      expect(payments.calls, isEmpty);
    });

    testWidgets('a student saves a bank account and a QR code', (tester) async {
      final payments = FakePaymentRepository();
      await pumpApp(tester, () async => student, payments: payments);
      await openDetails(tester);

      await tester.enterText(
        find.byKey(PaymentDetailsForm.bankKey),
        ' Maybank ',
      );
      await tester.enterText(find.byKey(PaymentDetailsForm.nameKey), 'Ali Abu');
      await tester.enterText(
        find.byKey(PaymentDetailsForm.numberKey),
        '1234-5678 90',
      );
      await tapVisible(tester, find.byKey(PaymentDetailsForm.qrKey));
      // The QR preview pushes Save below the part of the list that is built.
      await tester.scrollUntilVisible(
        find.byKey(PaymentDetailsForm.saveKey),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.byKey(PaymentDetailsForm.saveKey));

      expect(payments.calls, [
        'details personal Maybank|Ali Abu|1234567890 qr:new',
      ]);
      expect(find.text('Changes saved.'), findsOneWidget);
    });

    testWidgets('clearing everything removes the saved details', (
      tester,
    ) async {
      final payments = FakePaymentRepository(
        saved: const SavedPaymentDetails(
          personal: PaymentDetails(qrPath: 'u1/qr.png'),
        ),
      );
      await pumpApp(tester, () async => student, payments: payments);
      await openDetails(tester);

      await tapVisible(tester, find.byKey(PaymentDetailsForm.removeQrKey));
      await tapVisible(tester, find.byKey(PaymentDetailsForm.saveKey));

      expect(payments.calls, ['details personal || qr:none']);
      expect(find.text('Changes saved.'), findsOneWidget);
    });
  });
}
