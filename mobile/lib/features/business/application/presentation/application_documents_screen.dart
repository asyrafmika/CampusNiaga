import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/domain/business_enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/state_views.dart';
import '../data/document_picker.dart';
import '../domain/business_application.dart';
import 'application_providers.dart';
import 'widgets/application_widgets.dart';

/// Upload Documents, then submit (or resubmit with a reply to the reviewer).
/// Pops with `true` once the application is submitted.
class ApplicationDocumentsScreen extends ConsumerWidget {
  const ApplicationDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(myApplicationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Supporting documents')),
      body: switch (application) {
        AsyncValue(value: final app?) when app.canEdit => _Documents(
          application: app,
        ),
        AsyncValue(hasValue: true) => const EmptyView(
          icon: Icons.lock_clock_outlined,
          title: 'Nothing to submit',
          message: 'Your application is with the reviewers.',
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(myApplicationProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Documents extends ConsumerStatefulWidget {
  const _Documents({required this.application});

  final BusinessApplication application;

  @override
  ConsumerState<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends ConsumerState<_Documents> {
  static const Key addKey = Key('documents-add');
  static const Key replyKey = Key('documents-reply');
  static const Key submitKey = Key('documents-submit');

  final _reply = TextEditingController();
  bool _busy = false;
  String? _replyError;

  BusinessApplication get _app => widget.application;

  bool get _isResubmit => _app.status == ApplicationStatus.infoRequested;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => _run(() async {
    final document = await ref.read(documentPickerProvider).pick();
    if (document == null) return;
    await ref.read(applicationActionsProvider).addDocument(_app, document);
  });

  Future<void> _remove(String path) => _run(
    () => ref.read(applicationActionsProvider).removeDocument(_app, path),
  );

  Future<void> _submit() async {
    final replyProblem = ApplicationRules.responseNote(_reply.text);
    setState(() => _replyError = replyProblem);
    if (replyProblem != null) return;
    // The server checks again; this catches a draft saved half-finished.
    final problem = ApplicationRules.submitProblem(_app.content);
    if (problem != null) {
      showMessage(context, 'Go back and complete the details: $problem');
      return;
    }

    var submitted = false;
    await _run(() async {
      await ref
          .read(applicationActionsProvider)
          .submit(_app.id, responseNote: _isResubmit ? _reply.text : null);
      submitted = true;
    });
    if (!submitted || !mounted) return;
    showMessage(
      context,
      _isResubmit
          ? 'Resubmitted. The reviewer will look at it again.'
          : 'Submitted! We’ll let you know when a reviewer decides.',
    );
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paths = _app.documentPaths;
    final canAdd = paths.length < ApplicationRules.maxDocuments && !_busy;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        const ApplicationStepHeader(step: 2),
        const SizedBox(height: 12),
        Text(
          'Optional, but it helps the reviewer: a menu or price list, product '
          'photos, a food handling certificate. PDF, JPEG or PNG, up to 5 MB '
          'each, ${ApplicationRules.maxDocuments} at most.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Material(
          color: AppColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (final path in paths)
                ListTile(
                  leading: Icon(
                    path.toLowerCase().endsWith('.pdf')
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    ApplicationRules.documentName(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    onPressed: _busy ? null : () => _remove(path),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              ListTile(
                key: addKey,
                enabled: canAdd,
                onTap: canAdd ? _add : null,
                leading: const Icon(
                  Icons.upload_file_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  paths.length < ApplicationRules.maxDocuments
                      ? 'Add a document'
                      : 'Document limit reached',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ],
          ),
        ),
        if (_isResubmit) ...[
          const SizedBox(height: 20),
          Text(
            'Reply to the reviewer (optional)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: replyKey,
            controller: _reply,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'e.g. I’ve added my price list.',
              errorText: _replyError,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: submitKey,
          onPressed: _busy ? null : _submit,
          child: Text(
            _isResubmit ? 'Resubmit application' : 'Submit application',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Once submitted, you can’t edit it unless a reviewer asks for '
          'changes.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        const SimulatedReviewNotice(),
      ],
    );
  }
}
