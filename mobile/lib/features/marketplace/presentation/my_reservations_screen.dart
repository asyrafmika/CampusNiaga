import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/domain/listing_enums.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/reservation.dart';
import 'marketplace_providers.dart';
import 'widgets/listing_widgets.dart';

/// Bookings (my reservations): what I'm buying and what others reserved from
/// me.
class MyReservationsScreen extends StatelessWidget {
  const MyReservationsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: ReservationSide.values.length,
    child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bookings'),
        backgroundColor: AppColors.background,
        bottom: TabBar(
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: [
            for (final side in ReservationSide.values) Tab(text: side.label),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          _ReservationList(side: ReservationSide.buying),
          _ReservationList(side: ReservationSide.selling),
        ],
      ),
    ),
  );
}

class _ReservationList extends ConsumerWidget {
  const _ReservationList({required this.side});

  final ReservationSide side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(myReservationsProvider(side));
    return switch (reservations) {
      AsyncData(:final value) when value.isEmpty => EmptyView(
        icon: side == ReservationSide.buying
            ? Icons.shopping_bag_outlined
            : Icons.storefront_outlined,
        title: side == ReservationSide.buying
            ? 'No reservations yet'
            : 'No requests yet',
        message: side == ReservationSide.buying
            ? 'Reserve an item and it shows up here.'
            : 'When someone reserves your item, you’ll see it here.',
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(myReservationsProvider(side).future),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => ReservationTile(reservation: value[i]),
        ),
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(myReservationsProvider(side)),
      ),
      _ => const LoadingView(),
    };
  }
}

class ReservationTile extends ConsumerStatefulWidget {
  const ReservationTile({super.key, required this.reservation});

  final ReservationCard reservation;

  @override
  ConsumerState<ReservationTile> createState() => _ReservationTileState();
}

class _ReservationTileState extends ConsumerState<ReservationTile> {
  bool _busy = false;

  Future<void> _run(ReservationAction action) async {
    final r = widget.reservation;
    if (action != ReservationAction.accept) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${action.label}?'),
          content: Text(switch (action) {
            ReservationAction.decline =>
              'The ${r.qty == 1 ? 'item goes' : 'units go'} back on sale.',
            ReservationAction.cancel =>
              'The reservation ends and the item goes back on sale.',
            ReservationAction.collect =>
              'Confirm the buyer picked it up. This can’t be undone.',
            ReservationAction.accept => '',
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action.label),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(marketplaceActionsProvider).resolveReservation(r, action);
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.reservation;
    final actions = actionsFor(r);
    final email = r.otherPartyEmail;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(AppRoutes.listing(r.listingId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.square(
                      dimension: 64,
                      child: ListingPhoto(path: r.listingPhoto),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.listingTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${r.qty} × ${formatRm(r.priceSen)} = '
                          '${formatRm(r.totalSen)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${r.iAmBuyer ? 'Seller' : 'Buyer'}: '
                          '${r.otherPartyName}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  StatusPill.reservation(r.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(statusExplanation(r), style: theme.textTheme.bodyMedium),
              if (r.pickupNote case final note?) ...[
                const SizedBox(height: 6),
                _Line(icon: Icons.schedule_rounded, text: 'Pickup: $note'),
              ],
              _Line(icon: Icons.place_outlined, text: r.pickupArea),
              if (r.status.isActive && r.expiresAt != null)
                _Line(
                  icon: Icons.timer_outlined,
                  text: 'Until ${_when(r.expiresAt!)}',
                ),
              if (email != null && r.status == ReservationStatus.accepted)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.mail_outline_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          email,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy email',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: email));
                          if (context.mounted) {
                            showMessage(context, 'Email copied.');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final (i, action) in actions.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: i == 0 && action != ReservationAction.cancel
                            ? FilledButton(
                                onPressed: _busy ? null : () => _run(action),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                ),
                                child: Text(action.label),
                              )
                            : OutlinedButton(
                                onPressed: _busy ? null : () => _run(action),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                ),
                                child: Text(action.label),
                              ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime t) {
    final local = t.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'am' : 'pm';
    return '${local.day} ${months[local.month - 1]}, $hour:$minute$ampm';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}
