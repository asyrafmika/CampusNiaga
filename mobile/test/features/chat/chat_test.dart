import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/core/router/app_router.dart';
import 'package:mobile/core/router/app_routes.dart';
import 'package:mobile/core/utils/dates.dart';
import 'package:mobile/features/auth/presentation/profile_screen.dart';
import 'package:mobile/features/business/store/domain/store_models.dart';
import 'package:mobile/features/chat/data/chat_repository.dart';
import 'package:mobile/features/chat/domain/chat_models.dart';
import 'package:mobile/features/marketplace/presentation/my_purchases_screen.dart';

import '../../support/app_harness.dart';
import '../../support/chat_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/store_fakes.dart';

void main() {
  group('rules', () {
    test('a message must have text and fit 1,000 characters', () {
      expect(ChatRules.validate('   '), 'Write a message first.');
      expect(ChatRules.validate('Hi'), isNull);
      expect(ChatRules.validate('a' * 1000), isNull);
      expect(ChatRules.validate('a' * 1001), isNotNull);
      expect(ChatRules.validate('  ${'a' * 1000}  '), isNull);
    });

    test('merging keeps each message once, oldest first', () {
      final merged = ChatRules.merge(
        [aMessage(3, 'c'), aMessage(1, 'a')],
        [aMessage(2, 'b'), aMessage(3, 'c again')],
      );
      expect(merged.map((m) => m.id), [1, 2, 3]);
      expect(merged.last.body, 'c again');
    });

    test('the preview and the read-only reason', () {
      expect(aConversation(last: null).preview, 'No messages yet');
      expect(aConversation(last: 'Hi', lastMine: true).preview, 'You: Hi');
      expect(aConversation(last: 'Hi').preview, 'Hi');
      expect(aConversation().readOnlyReason, isNull);
      expect(
        aConversation(canSend: false, closed: true).readOnlyReason,
        'This chat was closed.',
      );
      expect(
        aConversation(canSend: false).readOnlyReason,
        'This item is no longer available, so the chat is read-only.',
      );
      expect(
        aConversation(kind: ChatKind.order, canSend: false).readOnlyReason,
        'This order has ended, so the chat is read-only.',
      );
      expect(aConversation(iAmBuyer: true).otherPartyRole, 'Seller');
      expect(aConversation(iAmBuyer: false).otherPartyRole, 'Buyer');
    });

    test('a chat is for exactly one item, purchase or order', () {
      expect(const ChatDeal.listing('x'), const ChatDeal.listing('x'));
      expect(const ChatDeal.listing('x'), isNot(const ChatDeal.order('x')));
      expect(const ChatDeal.listing('x'), isNot(const ChatDeal.purchase('x')));
    });

    test('an order can chat from confirmation until it ends', () {
      expect(
        {for (final s in OrderStatus.values) s: OrderRules.canChat(s)},
        {
          OrderStatus.pendingConfirmation: false,
          OrderStatus.confirmed: true,
          OrderStatus.preparing: true,
          OrderStatus.readyForPickup: true,
          OrderStatus.completed: false,
          OrderStatus.cancelled: false,
        },
      );
    });

    test('chat times: today, yesterday, then the date', () {
      final now = DateTime(2026, 11, 16, 20);
      expect(formatChatTime(DateTime(2026, 11, 16, 15, 5), now), '3:05 PM');
      expect(formatChatTime(DateTime(2026, 11, 16, 0, 30), now), '12:30 AM');
      expect(formatChatTime(DateTime(2026, 11, 15, 23), now), 'Yesterday');
      expect(formatChatTime(DateTime(2026, 11, 14, 9), now), '14 Nov 2026');
    });
  });

  group('mappers', () {
    test('reads a conversation card and a message', () {
      final card = conversationFromRow({
        'conversation_id': 'c1',
        'kind': 'order',
        'order_id': 'o1',
        'listing_id': 'l1',
        'listing_title': 'Brownie box',
        'listing_photo': null,
        'other_party_name': 'Ali',
        'i_am_buyer': true,
        'last_message': null,
        'last_message_at': null,
        'last_message_mine': null,
        'unread_count': 2,
        'can_send': true,
        'closed': false,
        'created_at': '2026-11-16T08:00:00+00:00',
      });
      expect(card.kind, ChatKind.order);
      expect(card.unreadCount, 2);
      expect(card.lastMessageAt, isNull);
      expect(card.lastMessageMine, isFalse);

      final message = messageFromRow({
        'id': 7,
        'conversation_id': 'c1',
        'sender_id': 'u2',
        'body': 'Hi',
        'created_at': '2026-11-16T09:00:00+00:00',
      });
      expect(message.id, 7);
      expect(message.senderId, 'u2');
    });

    test('rejects an unknown kind instead of guessing', () {
      expect(() => ChatKind.fromWire('group'), throwsFormatException);
    });
  });

  group('screens', () {
    Future<void> go(WidgetTester tester, String location) async {
      ProviderScope.containerOf(tester.element(find.byType(CampusNiagaApp)))
          .read(appRouterProvider)
          .go(location);
      await tester.pumpAndSettle();
    }

    Future<void> send(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const Key('chat-input')), text);
      await tester.tap(find.byKey(const Key('chat-send')));
      await tester.pumpAndSettle();
    }

    testWidgets('a purchase opens its chat; the buyer sends a message', (
      tester,
    ) async {
      final chat = FakeChatRepository();
      await pumpApp(
        tester,
        () async => student,
        chat: chat,
        purchases: FakePurchaseRepository(buying: [aPurchase(iAmBuyer: true)]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchases'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(PurchaseTile.chatKey('r1')));
      await tester.tap(find.byKey(PurchaseTile.chatKey('r1')));
      await tester.pumpAndSettle();

      expect(chat.calls.first, 'open purchase r1');
      expect(find.text('Hi, is it still there?'), findsOneWidget);
      expect(find.text('Seller · Casio FX-570 calculator'), findsOneWidget);
      expect(find.textContaining('never takes payment'), findsOneWidget);

      await send(tester, '  Can I collect at 5pm?  ');
      expect(chat.calls, contains('send c1 Can I collect at 5pm?'));
      expect(find.text('Can I collect at 5pm?'), findsOneWidget);
    });

    testWidgets('an order chat says nothing about holding an item', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () async => student,
        chat: FakeChatRepository(chats: [aConversation(kind: ChatKind.order)]),
      );
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.chat('c1'));

      expect(find.textContaining('does not hold'), findsNothing);
      expect(find.textContaining('never takes payment'), findsOneWidget);
    });

    testWidgets('a message from the other person arrives live and is '
        'marked read', (tester) async {
      final chat = FakeChatRepository();
      await pumpApp(tester, () async => student, chat: chat);
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.chat('c1'));
      expect(chat.calls, contains('read c1'));
      chat.calls.clear();

      chat.live.add(aMessage(2, 'On my way!'));
      await tester.pumpAndSettle();

      expect(find.text('On my way!'), findsOneWidget);
      expect(chat.calls, ['read c1']);
    });

    testWidgets('an empty message is not sent', (tester) async {
      final chat = FakeChatRepository();
      await pumpApp(tester, () async => student, chat: chat);
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.chat('c1'));

      await send(tester, '   ');
      expect(find.text('Write a message first.'), findsOneWidget);
      expect(chat.calls.where((c) => c.startsWith('send')), isEmpty);
    });

    testWidgets('a read-only chat shows why and has no message box', (
      tester,
    ) async {
      await pumpApp(
        tester,
        () async => student,
        chat: FakeChatRepository(chats: [aConversation(canSend: false)]),
      );
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.chat('c1'));

      expect(
        find.text(
          'This item is no longer available, so the chat is read-only.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('chat-input')), findsNothing);
      expect(find.text('Hi, is it still there?'), findsOneWidget);
    });

    testWidgets('a refused send shows the reason and refreshes the chat', (
      tester,
    ) async {
      final chat = FakeChatRepository()
        ..failSendWith = const AppFailure(
          AppFailureReason.invalidTransition,
          'This chat is read-only because the item is no longer available.',
        );
      await pumpApp(tester, () async => student, chat: chat);
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.chat('c1'));

      chat.chats = [aConversation(canSend: false)];
      await send(tester, 'Hello?');

      expect(
        find.text(
          'This chat is read-only because the item is no longer available.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('chat-input')), findsNothing);
    });

    testWidgets('closing a chat asks first, then makes it read-only', (
      tester,
    ) async {
      final chat = FakeChatRepository();
      await pumpApp(tester, () async => student, chat: chat);
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.chat('c1'));

      await tester.tap(find.byKey(const Key('chat-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-close-confirm')));
      await tester.pumpAndSettle();

      expect(chat.calls, contains('close c1'));
      expect(find.text('This chat was closed.'), findsOneWidget);
      expect(find.byKey(const Key('chat-input')), findsNothing);
    });

    testWidgets('reporting needs a reason, and details for "something '
        'else"', (tester) async {
      final chat = FakeChatRepository();
      await pumpApp(tester, () async => student, chat: chat);
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.chat('c1'));

      await tester.tap(find.byKey(const Key('chat-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat-report-send')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a reason.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat-report-other')));
      await tester.tap(find.byKey(const Key('chat-report-send')));
      await tester.pumpAndSettle();
      expect(find.text('Tell us what’s wrong.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat-report-scam')));
      await tester.enterText(
        find.byKey(const Key('chat-report-details')),
        'Asked me to pay first',
      );
      await tester.tap(find.byKey(const Key('chat-report-send')));
      await tester.pumpAndSettle();

      expect(chat.calls, contains('report c1 scam Asked me to pay first'));
      expect(
        find.text('Reported. An administrator will review the chat.'),
        findsOneWidget,
      );
    });

    testWidgets('Messages lists chats with unread counts; Profile shows '
        'the total', (tester) async {
      final chat = FakeChatRepository(
        chats: [
          aConversation(unread: 2, last: 'Are you there?'),
          aConversation(
            id: 'c2',
            kind: ChatKind.order,
            title: 'Brownie box',
            other: 'Ali Bakes',
            last: 'Thanks!',
            lastMine: true,
            canSend: false,
          ),
        ],
      );
      await pumpApp(tester, () async => student, chat: chat);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      final messages = find.byKey(ProfileScreen.messagesKey);
      expect(
        find.descendant(of: messages, matching: find.text('2')),
        findsOneWidget,
      );

      await tester.tap(messages);
      await tester.pumpAndSettle();
      expect(find.text('Are you there?'), findsOneWidget);
      expect(find.text('You: Thanks!'), findsOneWidget);
      expect(find.text('Order · Brownie box · Ended'), findsOneWidget);
      expect(find.text('Item · Casio FX-570 calculator'), findsOneWidget);
    });

    testWidgets('no chats yet', (tester) async {
      await pumpApp(tester, () async => student);
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.messages);

      expect(find.text('No chats yet'), findsOneWidget);
    });

    testWidgets('a confirmed order offers a chat; one awaiting confirmation '
        'does not', (tester) async {
      final chat = FakeChatRepository(
        chats: [aConversation(kind: ChatKind.order, other: 'Ali Bakes')],
      );
      await pumpApp(
        tester,
        () async => student,
        chat: chat,
        store: FakeStoreRepository(
          buying: [
            anOrder(status: OrderStatus.confirmed),
            anOrder(id: 'o2'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await go(tester, AppRoutes.orders);

      expect(find.byKey(const Key('order-chat-o2')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('order-chat-o1')));
      await tester.tap(find.byKey(const Key('order-chat-o1')));
      await tester.pumpAndSettle();

      expect(chat.calls.first, 'open order o1');
      expect(find.text('Ali Bakes'), findsOneWidget);
    });
  });
}
