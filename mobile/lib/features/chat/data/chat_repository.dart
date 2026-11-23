import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../marketplace/data/marketplace_mappers.dart';
import '../domain/chat_models.dart';

ConversationCard conversationFromRow(Map<String, dynamic> row) =>
    ConversationCard(
      id: row['conversation_id'] as String,
      kind: ChatKind.fromWire(row['kind'] as String),
      listingId: row['listing_id'] as String,
      listingTitle: row['listing_title'] as String,
      listingPhoto: row['listing_photo'] as String?,
      otherPartyName: row['other_party_name'] as String,
      iAmBuyer: row['i_am_buyer'] as bool,
      lastMessage: row['last_message'] as String?,
      lastMessageAt: switch (row['last_message_at']) {
        final String at => DateTime.parse(at),
        _ => null,
      },
      lastMessageMine: row['last_message_mine'] as bool? ?? false,
      unreadCount: (row['unread_count'] as num).toInt(),
      canSend: row['can_send'] as bool,
      closed: row['closed'] as bool,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

ChatMessage messageFromRow(Map<String, dynamic> row) => ChatMessage(
  id: (row['id'] as num).toInt(),
  senderId: row['sender_id'] as String,
  body: row['body'] as String,
  createdAt: DateTime.parse(row['created_at'] as String),
);

/// Chats, through their database functions; messages are read under
/// Row Level Security and arrive live through Supabase Realtime.
class ChatRepository {
  ChatRepository(this._client);

  static const int pageSize = 30;

  /// The newest messages a chat loads; chats are short.
  static const int messageLimit = 200;

  final SupabaseClient _client;

  /// The chat for [deal], created if it may be.
  Future<String> open(ChatDeal deal) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'open_conversation',
      params: {
        'listing_id': deal.listingId,
        'order_id': deal.orderId,
        'purchase_id': deal.purchaseId,
      },
    );
    return (result! as Map)['conversation_id'] as String;
  });

  Future<List<ConversationCard>> conversations({int offset = 0}) =>
      guardSupabase(() async {
        final Object? result = await _client.rpc<Object?>(
          'my_conversations',
          params: {'page_size': pageSize, 'page_offset': offset},
        );
        return rowsOf(result).map(conversationFromRow).toList();
      });

  Future<ConversationCard> conversation(String id) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'get_conversation',
      params: {'conversation_id': id},
    );
    return conversationFromRow(Map<String, dynamic>.from(result! as Map));
  });

  /// The chat's latest messages, oldest first.
  Future<List<ChatMessage>> messages(String conversationId) =>
      guardSupabase(() async {
        final List<Map<String, dynamic>> rows = await _client
            .from('messages')
            .select('id, sender_id, body, created_at')
            .eq('conversation_id', conversationId)
            .order('id', ascending: false)
            .limit(messageLimit);
        return rows.reversed.map(messageFromRow).toList();
      });

  /// New messages in the chat as they are sent, by either person.
  Stream<ChatMessage> incoming(String conversationId) {
    late final RealtimeChannel channel;
    final controller = StreamController<ChatMessage>(
      onCancel: () => _client.removeChannel(channel),
    );
    channel = _client
        .channel('chat-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            if (!controller.isClosed) {
              controller.add(messageFromRow(payload.newRecord));
            }
          },
        )
        .subscribe();
    return controller.stream;
  }

  Future<ChatMessage> send(String conversationId, String body) =>
      guardSupabase(() async {
        final text = body.trim();
        final Object? result = await _client.rpc<Object?>(
          'send_message',
          params: {'conversation_id': conversationId, 'body': text},
        );
        final map = result! as Map;
        return ChatMessage(
          id: (map['message_id'] as num).toInt(),
          senderId: _client.auth.currentUser!.id,
          body: text,
          createdAt: DateTime.parse(map['created_at'] as String),
        );
      });

  Future<void> markRead(String conversationId) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'mark_conversation_read',
      params: {'conversation_id': conversationId},
    );
  });

  Future<void> close(String conversationId) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'close_conversation',
      params: {'conversation_id': conversationId},
    );
  });

  Future<void> report(
    String conversationId,
    ChatReportReason reason,
    String details,
  ) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'report_conversation',
      params: {
        'conversation_id': conversationId,
        'reason': reason.wireName,
        'details': details.trim(),
      },
    );
  });
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(supabaseClientProvider)),
);
