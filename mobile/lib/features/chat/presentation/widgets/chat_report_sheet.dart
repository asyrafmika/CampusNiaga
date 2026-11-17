import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/widgets/state_views.dart';
import '../../domain/chat_models.dart';
import '../chat_providers.dart';

/// Asks why the chat is being reported and sends it to the administrators.
Future<void> showChatReportSheet(BuildContext context, String conversationId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ReportSheet(conversationId: conversationId),
    );

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _details = TextEditingController();
  ChatReportReason? _reason;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Choose a reason.');
      return;
    }
    if (reason == ChatReportReason.other && _details.text.trim().isEmpty) {
      setState(() => _error = 'Tell us what’s wrong.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(chatActionsProvider)
          .report(widget.conversationId, reason, _details.text);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'Reported. An administrator will review the chat.');
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppFailure.messageOf(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Report this chat', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'An administrator will read this chat to review your report. '
              'To stop all messages, you can also close the chat.',
              style: theme.textTheme.bodyMedium,
            ),
            RadioGroup<ChatReportReason>(
              groupValue: _reason,
              onChanged: (r) => setState(() {
                _reason = r;
                _error = null;
              }),
              child: Column(
                children: [
                  for (final reason in ChatReportReason.values)
                    RadioListTile<ChatReportReason>(
                      key: Key('chat-report-${reason.wireName}'),
                      value: reason,
                      title: Text(reason.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              key: const Key('chat-report-details'),
              controller: _details,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: _reason == ChatReportReason.other
                    ? 'Tell us what’s wrong'
                    : 'More details (optional)',
              ),
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton(
              key: const Key('chat-report-send'),
              onPressed: _busy ? null : _submit,
              child: const Text('Send report'),
            ),
          ],
        ),
      ),
    );
  }
}
