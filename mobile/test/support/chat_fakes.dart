import 'dart:async';

import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/features/chat/data/chat_repository.dart';
import 'package:mobile/features/chat/domain/chat_models.dart';

ConversationCard aConversation({
  String id = 'c1',
  ChatKind kind = ChatKind.item,
  String title = 'Casio FX-570 calculator',
  String other = 'Siti',
  bool iAmBuyer = true,
  String? last = 'See you at 5pm',
  bool lastMine = false,
  int unread = 0,
  bool canSend = true,
  bool closed = false,
}) => ConversationCard(
  id: id,
  kind: kind,
  listingId: 'l1',
  listingTitle: title,
  otherPartyName: other,
  iAmBuyer: iAmBuyer,
  lastMessage: last,
  lastMessageAt: last == null ? null : DateTime.utc(2026, 11, 16, 9),
  lastMessageMine: lastMine,
  unreadCount: unread,
  canSend: canSend,
  closed: closed,
  createdAt: DateTime.utc(2026, 11, 16, 8),
);

ChatMessage aMessage(int id, String body, {String sender = 'u2'}) =>
    ChatMessage(
      id: id,
      senderId: sender,
      body: body,
      createdAt: DateTime.utc(2026, 11, 16, 9, id),
    );

/// In-memory chats; records every call. [live] stands in for Supabase
/// Realtime: add a message to it to "receive" one.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({
    List<ConversationCard>? chats,
    Map<String, List<ChatMessage>>? messages,
  }) : chats = chats ?? [aConversation()],
       history =
           messages ??
           {
             'c1': [aMessage(1, 'Hi, is it still there?')],
           };

  List<ConversationCard> chats;
  Map<String, List<ChatMessage>> history;
  final StreamController<ChatMessage> live =
      StreamController<ChatMessage>.broadcast();
  final List<String> calls = [];
  AppFailure? failSendWith;
  int _nextId = 100;

  @override
  Future<String> open(ChatDeal deal) async {
    calls.add(switch (deal) {
      ChatDeal(:final listingId?) => 'open item $listingId',
      ChatDeal(:final purchaseId?) => 'open purchase $purchaseId',
      _ => 'open order ${deal.orderId}',
    });
    return chats.first.id;
  }

  @override
  Future<List<ConversationCard>> conversations({int offset = 0}) async => chats;

  @override
  Future<ConversationCard> conversation(String id) async =>
      chats.firstWhere((c) => c.id == id);

  @override
  Future<List<ChatMessage>> messages(String conversationId) async =>
      history[conversationId] ?? const [];

  @override
  Stream<ChatMessage> incoming(String conversationId) => live.stream;

  @override
  Future<ChatMessage> send(String conversationId, String body) async {
    calls.add('send $conversationId ${body.trim()}');
    if (failSendWith case final f?) throw f;
    return aMessage(_nextId++, body.trim(), sender: 'u1');
  }

  @override
  Future<void> markRead(String conversationId) async =>
      calls.add('read $conversationId');

  @override
  Future<void> close(String conversationId) async {
    calls.add('close $conversationId');
    chats = [
      for (final c in chats)
        c.id == conversationId
            ? aConversation(id: c.id, canSend: false, closed: true)
            : c,
    ];
  }

  @override
  Future<void> report(
    String conversationId,
    ChatReportReason reason,
    String details,
  ) async => calls.add(
    'report $conversationId ${reason.wireName}'
    '${details.trim().isEmpty ? '' : ' ${details.trim()}'}',
  );
}
