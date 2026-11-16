import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/discovery_models.dart';
import 'discover_screen.dart';
import 'discovery_providers.dart';
import 'widgets/request_tile.dart';

/// One possible opportunity: its numbers, the explanation, how the score is
/// worked out, and the requests behind it.
class OpportunityDetailScreen extends ConsumerWidget {
  const OpportunityDetailScreen({super.key, required this.clusterKey});

  final String clusterKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opportunity = ref.watch(opportunityProvider(clusterKey));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Possible opportunity'),
        backgroundColor: AppColors.background,
      ),
      body: switch (opportunity) {
        AsyncData(value: final o?) => _Detail(opportunity: o),
        AsyncData() => const EmptyView(
          icon: Icons.search_off_rounded,
          title: 'No longer an opportunity',
          message: 'Its requests were closed.',
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(opportunityProvider(clusterKey)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.opportunity});

  final Opportunity opportunity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final o = opportunity;
    final requests = ref.watch(
      requestsProvider((clusterKey: o.clusterKey, mine: false)),
    );
    String rm(int? sen) => sen == null ? '—' : formatRm(sen);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(o.title, style: theme.textTheme.headlineSmall),
        Text(
          '${o.category} · score ${o.score}',
          style: theme.textTheme.bodyMedium,
        ),
        if (o.insufficientData) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF0DA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Insufficient data: fewer than 2 students want this so far.',
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Rows that grow with their text, so large system fonts never clip.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Number('${o.uniqueInterestCount}', 'students want it'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Number('${o.activeSupplyCount}', 'listings for sale'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Number(
                  rm(o.medianPreferredPriceSen),
                  'median price wanted',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Number(
                  rm(o.medianListedPriceSen),
                  'median price listed',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('Why it ranks here', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final reason in o.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(reason)),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text(
          'Score = 5 × students (up to 20) − 8 × listings (up to 10) + 10 '
          'when listings cost more than students want; never below 0. '
          'Rules ${o.algoVersion}.',
          style: theme.textTheme.bodySmall,
        ),
        if (o.keywords.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in o.keywords)
                Chip(label: Text(k), visualDensity: VisualDensity.compact),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Text('Requests (${o.requestCount})', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        switch (requests) {
          AsyncData(:final value) => Column(
            children: [
              for (final r in value) ...[
                RequestTile(key: ValueKey(r.id), request: r),
                const SizedBox(height: 10),
              ],
            ],
          ),
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(
              requestsProvider((clusterKey: o.clusterKey, mine: false)),
            ),
          ),
          _ => const LoadingView(),
        },
        const SizedBox(height: 8),
        const PossibleOpportunityNotice(),
      ],
    );
  }
}

class _Number extends StatelessWidget {
  const _Number(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
