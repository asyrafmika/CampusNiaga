import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/dates.dart';
import '../../../core/widgets/state_views.dart';
import '../../marketplace/presentation/marketplace_providers.dart';
import '../domain/chat_models.dart';
import 'chat_providers.dart';
import 'widgets/chat_report_sheet.dart';

/// A chat. Opened by id from Messages, or by its item, purchase or order
/// from the listing, Purchases and My orders (created then if needed).
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, this.conversationId, this.deal})
    : assert((conversationId == null) != (deal == null));

  final String? conversationId;
  final ChatDeal? deal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (conversationId case final id?) return _Chat(conversationId: id);
    final opened = ref.watch(openConversationProvider(deal!));
    return switch (opened) {
      AsyncData(:final value) => _Chat(conversationId: value),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(openConversationProvider(deal!)),
        ),
      ),
      _ => Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const LoadingView(),
      ),
    };
  }
}

enum _MenuAction { report, close }

class _Chat extends ConsumerWidget {
  const _Chat({required this.conversationId});

  final String conversationId;

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this chat?'),
        content: const Text(
          'Neither of you will be able to send messages here again. The '
          'messages stay readable. Your purchase or order is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            key: const Key('chat-close-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close chat'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(chatActionsProvider).close(conversationId);
      if (context.mounted) showMessage(context, 'Chat closed.');
    } on Object catch (e) {
      if (context.mounted) showMessage(context, AppFailure.messageOf(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = ref.watch(conversationProvider(conversationId)).value;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: header == null
            ? const Text('Chat')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(header.otherPartyName),
                  Text(
                    '${header.otherPartyRole} · ${header.listingTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
        actions: [
          PopupMenuButton<_MenuAction>(
            key: const Key('chat-menu'),
            onSelected: (action) => switch (action) {
              _MenuAction.report => showChatReportSheet(
                context,
                conversationId,
              ),
              _MenuAction.close => _close(context, ref),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _MenuAction.report,
                child: Text('Report'),
              ),
              if (header != null && !header.closed)
                const PopupMenuItem(
                  value: _MenuAction.close,
                  child: Text('Close chat'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _SafetyNote(kind: header?.kind),
          Expanded(child: _MessageList(conversationId: conversationId)),
          if (header?.readOnlyReason case final reason?)
            _ReadOnlyBar(reason: reason)
          else if (header != null)
            _Composer(conversationId: conversationId),
        ],
      ),
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote({required this.kind});

  final ChatKind? kind;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.primarySoft,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      '${kind == ChatKind.item ? 'Chatting does not hold the item. ' : ''}'
      'Meet in a public place on campus. CampusNiaga never takes payment, so '
      'pay only in person or through the app’s payment page.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _MessageList extends ConsumerWidget {
  const _MessageList({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatControllerProvider(conversationId));
    final me = ref.watch(currentUserIdProvider);
    return switch (messages) {
      AsyncData(:final value) when value.isEmpty => const EmptyView(
        icon: Icons.waving_hand_outlined,
        title: 'Say hello',
        message: 'Ask about the item, or agree on a time and place to collect.',
      ),
      AsyncData(:final value) => ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        itemCount: value.length,
        itemBuilder: (_, i) {
          final message = value[value.length - 1 - i];
          return _Bubble(message: message, mine: message.senderId == me);
        },
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(chatControllerProvider(conversationId)),
      ),
      _ => const LoadingView(),
    };
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? AppColors.primary : AppColors.surface,
            border: mine ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(
                message.body,
                style: TextStyle(
                  color: mine ? Colors.white : AppColors.text,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatChatTime(message.createdAt, DateTime.now()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.75)
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyBar extends StatelessWidget {
  const _ReadOnlyBar({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.icon),
          const SizedBox(width: 10),
          Expanded(child: Text(reason)),
        ],
      ),
    ),
  );
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.conversationId});

  final String conversationId;

  static const fieldKey = Key('chat-input');
  static const sendKey = Key('chat-send');

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final problem = ChatRules.validate(_controller.text);
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(chatControllerProvider(widget.conversationId).notifier)
          .send(_controller.text);
      _controller.clear();
    } on AppFailure catch (e) {
      if (!mounted) return;
      showMessage(context, e.message);
      // The deal may have ended or the chat been closed meanwhile.
      if (e.reason == AppFailureReason.invalidTransition) {
        ref.read(chatActionsProvider).refresh(widget.conversationId);
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: _Composer.fieldKey,
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              maxLength: ChatRules.maxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Message',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            key: _Composer.sendKey,
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    ),
  );
}
