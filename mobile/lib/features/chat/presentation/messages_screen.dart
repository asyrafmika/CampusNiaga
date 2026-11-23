import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/unread_badge.dart';
import '../../marketplace/presentation/widgets/listing_widgets.dart';
import '../domain/chat_models.dart';
import 'chat_providers.dart';

/// Every chat the student is in, newest activity first.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(conversationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: switch (chats) {
        AsyncData(:final value) when value.isEmpty => const EmptyView(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'No chats yet',
          message:
              'Chat with a seller from their item, or with a business once '
              'it confirms your order.',
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(conversationsProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: value.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 84),
            itemBuilder: (_, i) => ConversationTile(chat: value[i]),
          ),
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(conversationsProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class ConversationTile extends StatelessWidget {
  const ConversationTile({super.key, required this.chat});

  final ConversationCard chat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = chat.unreadCount > 0;
    final time = chat.lastMessageAt ?? chat.createdAt;
    return ListTile(
      key: Key('chat-${chat.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      onTap: () => context.push(AppRoutes.chat(chat.id)),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.square(
          dimension: 52,
          child: ListingPhoto(path: chat.listingPhoto),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.otherPartyName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            formatChatTime(time, DateTime.now()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: unread ? AppColors.primary : null,
              fontWeight: unread ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${chat.kind.label} · ${chat.listingTitle}'
            '${chat.closed ? ' · Closed' : (chat.canSend ? '' : ' · Ended')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  chat.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unread ? AppColors.text : AppColors.textSecondary,
                    fontWeight: unread ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (unread) UnreadBadge(count: chat.unreadCount),
            ],
          ),
        ],
      ),
    );
  }
}
