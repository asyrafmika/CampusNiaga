import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/discovery_models.dart';
import 'discovery_providers.dart';
import 'widgets/request_tile.dart';

/// Discover (M4): possible business opportunities ranked from what students
/// ask for, the requests themselves, and the student's own requests.
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  static const Key requestKey = Key('discover-request');

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Discover'),
        backgroundColor: AppColors.background,
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Opportunities'),
            Tab(text: 'Requests'),
            Tab(text: 'Mine'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: requestKey,
        onPressed: () => context.push(AppRoutes.discoverRequest),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Request a product'),
      ),
      body: const TabBarView(
        children: [
          _OpportunityList(),
          _RequestList(filter: allRequests),
          _RequestList(filter: myRequests),
        ],
      ),
    ),
  );
}

class _OpportunityList extends ConsumerWidget {
  const _OpportunityList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opportunities = ref.watch(opportunitiesProvider);
    return switch (opportunities) {
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(opportunitiesProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            const PossibleOpportunityNotice(),
            const SizedBox(height: 12),
            if (value.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: EmptyView(
                  icon: Icons.lightbulb_outline_rounded,
                  title: 'No opportunities yet',
                  message:
                      'They appear when students request products. Request '
                      'something you can’t find.',
                ),
              )
            else
              for (final (i, o) in value.indexed) ...[
                OpportunityCard(rank: i + 1, opportunity: o),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(opportunitiesProvider),
      ),
      _ => const LoadingView(),
    };
  }
}

class _RequestList extends ConsumerWidget {
  const _RequestList({required this.filter});

  final RequestFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(requestsProvider(filter));
    return switch (requests) {
      AsyncData(:final value) when value.isEmpty => EmptyView(
        icon: Icons.forum_outlined,
        title: filter.mine
            ? 'You haven’t requested anything'
            : 'No requests yet',
        message:
            'Can’t find something on campus? Request it, and sellers '
            'see that students want it.',
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(requestsProvider(filter).future),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) =>
              RequestTile(key: ValueKey(value[i].id), request: value[i]),
        ),
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(requestsProvider(filter)),
      ),
      _ => const LoadingView(),
    };
  }
}

/// The truthfulness label the handoff requires on every result.
class PossibleOpportunityNotice extends StatelessWidget {
  const PossibleOpportunityNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: AppColors.icon),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Possible opportunities, ranked by fixed rules from student '
            'requests and what is already for sale. Interest is not a '
            'purchase: check demand before you invest.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// One ranked opportunity with its first reasons.
class OpportunityCard extends StatelessWidget {
  const OpportunityCard({
    super.key,
    required this.rank,
    required this.opportunity,
  });

  final int rank;
  final Opportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = opportunity;
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: () => context.push(AppRoutes.opportunity(o.clusterKey)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primarySoft,
                    child: Text(
                      '#$rank',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.title, style: theme.textTheme.titleMedium),
                        Text(o.category, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${o.score}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      Text('score', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Possible opportunity',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(height: 4),
              for (final reason in o.reasons.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                        child: Text(reason, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              if (o.insufficientData) ...[
                const SizedBox(height: 8),
                const _Badge('Insufficient data'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFFDF0DA),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF9A5B00),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
