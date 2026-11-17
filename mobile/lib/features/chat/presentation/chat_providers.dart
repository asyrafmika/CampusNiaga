import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marketplace/presentation/marketplace_providers.dart';
import '../data/chat_repository.dart';
import '../domain/chat_models.dart';

/// The signed-in student's chats, newest activity first.
final conversationsProvider =
    FutureProvider.autoDispose<List<ConversationCard>>(
      (ref) => ref.watch(chatRepositoryProvider).conversations(),
    );

/// Unread messages across all chats, for the Profile badge.
final unreadChatsProvider = FutureProvider.autoDispose<int>((ref) async {
  final chats = await ref.watch(conversationsProvider.future);
  return chats.fold<int>(0, (sum, c) => sum + c.unreadCount);
});

/// One chat's header: who, what, and whether it can still send.
final conversationProvider = FutureProvider.autoDispose
    .family<ConversationCard, String>(
      (ref, id) => ref.watch(chatRepositoryProvider).conversation(id),
    );

/// The chat id for a reservation or order, created when needed.
final openConversationProvider = FutureProvider.autoDispose
    .family<String, ChatDeal>(
      (ref, deal) => ref.watch(chatRepositoryProvider).open(deal),
    );

/// A chat's messages: loaded once, then kept current by the live updates
/// while the screen is open. Incoming messages are marked read straight
/// away, because the student is looking at them.
class ChatController extends AsyncNotifier<List<ChatMessage>> {
  ChatController(this.conversationId);

  final String conversationId;

  ChatRepository get _repository => ref.read(chatRepositoryProvider);

  @override
  Future<List<ChatMessage>> build() async {
    final repository = ref.watch(chatRepositoryProvider);
    final subscription = repository.incoming(conversationId).listen(_receive);
    ref.onDispose(subscription.cancel);

    final messages = await repository.messages(conversationId);
    unawaited(_markRead());
    return messages;
  }

  void _receive(ChatMessage message) {
    if (!ref.mounted) return;
    state = AsyncData(ChatRules.merge(state.value ?? const [], [message]));
    if (message.senderId != ref.read(currentUserIdProvider)) {
      unawaited(_markRead());
    }
  }

  Future<void> _markRead() async {
    try {
      await _repository.markRead(conversationId);
      if (ref.mounted) ref.invalidate(conversationsProvider);
    } on Object {
      // Only the unread badge depends on it; the next open retries.
    }
  }

  /// Sends [body]; failures are thrown as `AppFailure` for the screen.
  Future<void> send(String body) async {
    final message = await _repository.send(conversationId, body);
    if (!ref.mounted) return;
    state = AsyncData(ChatRules.merge(state.value ?? const [], [message]));
    ref.invalidate(conversationsProvider);
  }
}

final chatControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ChatController, List<ChatMessage>, String>(ChatController.new);

/// Closing and reporting a chat.
class ChatActions {
  ChatActions(this._ref);

  final Ref _ref;

  ChatRepository get _repository => _ref.read(chatRepositoryProvider);

  Future<void> close(String conversationId) async {
    await _repository.close(conversationId);
    _refresh(conversationId);
  }

  Future<void> report(
    String conversationId,
    ChatReportReason reason,
    String details,
  ) => _repository.report(conversationId, reason, details);

  /// After a send was refused because the chat became read-only.
  void refresh(String conversationId) => _refresh(conversationId);

  void _refresh(String conversationId) {
    _ref
      ..invalidate(conversationProvider(conversationId))
      ..invalidate(conversationsProvider);
  }
}

final chatActionsProvider = Provider<ChatActions>(ChatActions.new);
