import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/business_enums.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../marketplace/presentation/widgets/listing_widgets.dart';
import '../domain/dashboard_models.dart';
import 'dashboard_providers.dart';

/// Business Dashboard (M5): the business's own orders, estimated sales and
/// profit, top products, stock and pre-orders, for a chosen period.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardPeriod _period = DashboardPeriod.last30Days;

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider(_period));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: AppColors.background,
      ),
      body: Column(
        children: [
          // The filter sits in one row above everything it filters.
          // Four chips, all built (not lazily), so every period is
          // reachable by screen readers and tests alike.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                for (final p in DashboardPeriod.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('period-${p.name}'),
                      label: Text(p.label),
                      selected: _period == p,
                      onSelected: (_) => setState(() => _period = p),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (dashboard) {
              AsyncData(:final value) => RefreshIndicator(
                onRefresh: () => ref.refresh(dashboardProvider(_period).future),
                child: _Body(dashboard: value),
              ),
              AsyncError(:final error) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(dashboardProvider(_period)),
              ),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.dashboard});

  final BusinessDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const EstimatedNotice(),
        const SizedBox(height: 12),
        _TileRow(
          left: _StatTile(
            key: const Key('stat-completed'),
            value: '${d.completedCount}',
            label: 'Completed sales',
          ),
          right: _StatTile(
            key: const Key('stat-revenue'),
            value: formatRm(d.estimatedRevenueSen),
            label: 'Estimated revenue',
            caption: 'Estimated (self-reported)',
          ),
        ),
        const SizedBox(height: 10),
        _TileRow(
          left: _StatTile(
            key: const Key('stat-cost'),
            value: formatRm(d.recordedCostSen),
            label: 'Recorded costs',
            caption: 'Entered by you',
          ),
          right: _StatTile(
            key: const Key('stat-profit'),
            value: formatRm(d.estimatedProfitSen),
            label: 'Estimated profit',
            caption: 'Estimated (self-reported)',
          ),
        ),
        if (d.uncostedCompletedCount > 0) ...[
          const SizedBox(height: 10),
          _Hint(
            key: const Key('uncosted-hint'),
            text:
                '${d.uncostedCompletedCount} completed '
                '${d.uncostedCompletedCount == 1 ? 'order has' : 'orders have'} '
                'no cost recorded, so profit may look higher than it is.',
            action: 'Record costs',
            onAction: () => context.push(AppRoutes.ordersSelling),
          ),
        ],
        _Section(
          title: 'Orders placed',
          trailing: '${d.totalOrders} in total',
          child: _Bars(
            rows: [
              for (final s in OrderStatus.values)
                (
                  label: s.label,
                  value: d.ordersByStatus[s] ?? 0,
                  text: '${d.ordersByStatus[s] ?? 0}',
                ),
            ],
          ),
        ),
        _Section(
          title: 'Top products',
          trailing: 'by estimated revenue',
          child: d.topProducts.isEmpty
              ? const _Empty('No completed sales in this period.')
              : _Bars(
                  rows: [
                    for (final p in d.topProducts)
                      (
                        label: p.title,
                        value: p.revenueSen,
                        text:
                            '${formatRm(p.revenueSen)} · ${p.units} '
                            '${p.units == 1 ? 'unit' : 'units'}',
                      ),
                  ],
                ),
        ),
        _Section(
          title: 'Stock',
          trailing: 'lowest first',
          child: d.stock.isEmpty
              ? const _Empty('No published products yet.')
              : Column(
                  children: [
                    for (final item in d.stock)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.title),
                        subtitle: Text(
                          item.hidden
                              ? 'Hidden by an administrator'
                              : '${item.stock} in stock',
                        ),
                        trailing: StatusPill.listing(item.status),
                      ),
                  ],
                ),
        ),
        _Section(
          title: 'Pre-orders',
          trailing: 'draft and open',
          child: d.campaigns.isEmpty
              ? const _Empty('No draft or open pre-orders.')
              : Column(
                  children: [
                    for (final c in d.campaigns)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _Meter(campaign: c),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Revenue and profit are not verified: the handoff requires the label.
class EstimatedNotice extends StatelessWidget {
  const EstimatedNotice({super.key});

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
            'Estimated / self-reported. Revenue adds up the orders you marked '
            'completed and costs are what you entered. CampusNiaga doesn’t '
            'take or verify payments.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    ),
  );
}

/// A headline number: the value in ink, the label and caption below.
class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.value,
    required this.label,
    this.caption,
  });

  final String value;
  final String label;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (caption case final caption?)
            Text(caption, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

typedef _BarRow = ({String label, int value, String text});

/// Single-hue horizontal bars; each value is written beside its bar, so
/// nothing depends on reading the bar length or the colour.
class _Bars extends StatelessWidget {
  const _Bars({required this.rows});

  final List<_BarRow> rows;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(0, (m, r) => r.value > m ? r.value : m);
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.text,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _Bar(fraction: max == 0 ? 0 : r.value / max),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: 8,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: AppColors.inputFill)),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0, 1),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A pre-order's capacity: how much is taken, in words and as a meter.
class _Meter extends StatelessWidget {
  const _Meter({required this.campaign});

  final CampaignLoad campaign;

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text('${c.allocatedQty} of ${c.capacity} taken'),
          ],
        ),
        const SizedBox(height: 4),
        _Bar(fraction: c.filled),
        const SizedBox(height: 2),
        Text(
          '${c.status.label} · closes ${formatDay(c.closeAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (trailing case final t?)
                  Text(t, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: AppColors.textSecondary));
}

class _Hint extends StatelessWidget {
  const _Hint({
    super.key,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFDF0DA),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        TextButton(
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(const Size(0, 36)),
          ),
          onPressed: onAction,
          child: Text(action),
        ),
      ],
    ),
  );
}
