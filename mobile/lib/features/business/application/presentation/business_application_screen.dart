import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/business_enums.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/widgets/state_views.dart';
import '../domain/business_application.dart';
import 'application_providers.dart';
import 'widgets/application_widgets.dart';

/// Track Status: the student's business application and what happens next.
/// Also where a saved draft is continued and a request for changes is
/// answered.
class BusinessApplicationScreen extends ConsumerWidget {
  const BusinessApplicationScreen({super.key});

  static const Key startKey = Key('application-start');
  static const Key continueKey = Key('application-continue');
  static const Key storeKey = Key('application-open-store');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(myApplicationProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Business application'),
        backgroundColor: AppColors.background,
      ),
      body: switch (application) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () async {
            ref.read(applicationActionsProvider).refresh(value?.id);
            await ref.read(myApplicationProvider.future);
          },
          child: value == null
              ? const _NoApplication()
              : _ApplicationStatusView(application: value),
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

class _NoApplication extends StatelessWidget {
  const _NoApplication();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storefront_rounded, color: AppColors.accent),
              const SizedBox(height: 12),
              Text(
                'Run your student business on CampusNiaga',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Apply once. After a reviewer approves your business, you '
                'can sell as a business on campus.',
                style: TextStyle(color: Color(0xD9FFFFFF)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _Step(
          number: 1,
          title: 'Tell us about your business',
          text: 'Name, what you sell, how buyers reach you and collect.',
        ),
        const _Step(
          number: 2,
          title: 'Add supporting documents',
          text:
              'Optional: a menu, product photos, a food handling '
              'certificate. PDF, JPEG or PNG.',
        ),
        const _Step(
          number: 3,
          title: 'A reviewer checks it',
          text: 'They approve it, or tell you what to change.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: BusinessApplicationScreen.startKey,
          onPressed: () => context.push(AppRoutes.businessApply),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Start application'),
        ),
        const SizedBox(height: 16),
        const SimulatedReviewNotice(),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.text});

  final int number;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.primarySoft,
          child: Text(
            '$number',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                text,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ApplicationStatusView extends ConsumerWidget {
  const _ApplicationStatusView({required this.application});

  final BusinessApplication application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = application.status;
    final content = application.content;
    final remarks = application.remarks;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _StatusCard(application: application),
        const SizedBox(height: 16),
        if (remarks != null &&
            (status == ApplicationStatus.infoRequested ||
                status == ApplicationStatus.rejected)) ...[
          ReviewerNoteCard(
            note: remarks,
            title: status == ApplicationStatus.rejected
                ? 'Why it wasn’t approved'
                : 'What the reviewer asked for',
          ),
          const SizedBox(height: 16),
        ],
        if (application.canEdit)
          FilledButton.icon(
            key: BusinessApplicationScreen.continueKey,
            onPressed: () => context.push(AppRoutes.businessApply),
            icon: const Icon(Icons.edit_rounded),
            label: Text(
              status == ApplicationStatus.draft
                  ? 'Continue application'
                  : 'Make changes and resubmit',
            ),
          ),
        if (status == ApplicationStatus.rejected)
          FilledButton.icon(
            key: BusinessApplicationScreen.startKey,
            onPressed: () => context.push(AppRoutes.businessApply),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Start a new application'),
          ),
        if (status == ApplicationStatus.approved) const _MyBusinessCard(),
        const SizedBox(height: 20),
        _Details(
          content: content,
          documentCount: application.documentPaths.length,
        ),
        if (status != ApplicationStatus.draft) ...[
          const SizedBox(height: 20),
          _Timeline(applicationId: application.id),
        ],
        const SizedBox(height: 20),
        const SimulatedReviewNotice(),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.application});

  final BusinessApplication application;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = application.status;
    final (IconData icon, String headline, String text) = switch (status) {
      ApplicationStatus.draft => (
        Icons.edit_note_rounded,
        'Draft saved',
        'Only you can see it. Finish it and submit when you’re ready.',
      ),
      ApplicationStatus.submitted => (
        Icons.schedule_rounded,
        'Waiting for a reviewer',
        'Your application is in the queue. You can’t edit it while it’s '
            'with the reviewers.',
      ),
      ApplicationStatus.underReview => (
        Icons.manage_search_rounded,
        'Being reviewed',
        'A reviewer is looking at your application now.',
      ),
      ApplicationStatus.infoRequested => (
        Icons.rate_review_rounded,
        'Changes requested',
        'The reviewer needs something more before deciding.',
      ),
      ApplicationStatus.approved => (
        Icons.verified_rounded,
        'Approved',
        'Your business is approved on CampusNiaga.',
      ),
      ApplicationStatus.rejected => (
        Icons.block_rounded,
        'Not approved',
        'You can start a new application.',
      ),
    };
    final when = application.decidedAt ?? application.submittedAt;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        headline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    applicationStatusPill(status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(text, style: theme.textTheme.bodyMedium),
                if (when != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${application.decidedAt != null ? 'Decided' : 'Submitted'} '
                    '${formatDay(when)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyBusinessCard extends ConsumerWidget {
  const _MyBusinessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(myBusinessProvider);
    return switch (business) {
      AsyncData(value: final b?) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_rounded, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    b.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              b.status == BusinessStatus.suspended
                  ? 'Suspended by an administrator. Business features are '
                        'unavailable until it is reinstated.'
                  : 'Pickup: ${b.pickupDetails}',
              style: const TextStyle(color: Color(0xD9FFFFFF)),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: BusinessApplicationScreen.storeKey,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primaryDark,
              ),
              onPressed: () => context.push(AppRoutes.manageStore),
              icon: const Icon(Icons.storefront_rounded),
              label: const Text('Open my store'),
            ),
          ],
        ),
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(myBusinessProvider),
      ),
      AsyncData() => const SizedBox.shrink(),
      _ => const LoadingView(),
    };
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.content, required this.documentCount});

  final ApplicationContent content;
  final int documentCount;

  @override
  Widget build(BuildContext context) {
    String show(String value) => value.trim().isEmpty ? '—' : value;
    return _Section(
      title: 'Your application',
      children: [
        _Field('Business name', show(content.businessName)),
        _Field('Category', show(content.category)),
        _Field('What you sell', show(content.description)),
        _Field('Contact', show(content.contactDetails)),
        _Field('Collection', show(content.collectionDetails)),
        _Field(
          'Documents',
          documentCount == 0 ? 'None attached' : '$documentCount attached',
        ),
      ],
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(applicationHistoryProvider(applicationId));
    return _Section(
      title: 'Timeline',
      children: [
        switch (history) {
          AsyncData(:final value) => Column(
            children: [
              for (final (i, entry) in value.reversed.indexed)
                _TimelineEntry(entry: entry, latest: i == 0),
            ],
          ),
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () =>
                ref.invalidate(applicationHistoryProvider(applicationId)),
          ),
          _ => const Padding(padding: EdgeInsets.all(16), child: LoadingView()),
        },
      ],
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.entry, required this.latest});

  final ApplicationHistoryEntry entry;
  final bool latest;

  @override
  Widget build(BuildContext context) {
    final title = switch (entry.to) {
      ApplicationStatus.submitted =>
        entry.from == ApplicationStatus.infoRequested
            ? 'Resubmitted'
            : 'Submitted',
      ApplicationStatus.underReview => 'Review started',
      ApplicationStatus.infoRequested => 'Changes requested',
      ApplicationStatus.approved => 'Approved',
      ApplicationStatus.rejected => 'Not approved',
      ApplicationStatus.draft => 'Draft',
    };
    final note = entry.note;
    return ListTile(
      leading: Icon(
        latest ? Icons.radio_button_checked_rounded : Icons.circle_outlined,
        color: latest ? AppColors.primary : AppColors.icon,
        size: 20,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${entry.actor.label} · ${formatDayTime(entry.createdAt)}'
        '${note == null ? '' : '\n“$note”'}',
      ),
      isThreeLine: note != null,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Column(children: children),
      ),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(
      label,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    ),
    subtitle: Text(
      value,
      style: const TextStyle(fontSize: 14, color: AppColors.text),
    ),
  );
}
