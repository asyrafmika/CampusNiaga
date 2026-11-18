import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/domain/listing_enums.dart';
import '../../../core/domain/payment.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/pickup_map.dart';
import '../../../core/widgets/state_views.dart';
import '../../payments/presentation/payment_providers.dart';
import '../../payments/presentation/widgets/payment_widgets.dart';
import '../domain/listing.dart';
import 'marketplace_providers.dart';
import 'widgets/listing_widgets.dart';

/// Product detail: photos, price, details and seller; buyers reserve or
/// report, owners manage the listing.
class ListingDetailScreen extends ConsumerWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  static const Key reserveKey = Key('detail-reserve');
  static const Key orderKey = Key('detail-order');
  static const Key storefrontKey = Key('detail-storefront');
  static const Key pickupMapKey = Key('detail-pickup-map');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(listingDetailProvider(listingId));
    final isOwner = switch (listing) {
      AsyncData(:final value) =>
        value.ownerId == ref.watch(currentUserIdProvider),
      _ => false,
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Item'),
        actions: [
          if (listing.hasValue && !isOwner)
            PopupMenuButton<String>(
              tooltip: 'More options',
              onSelected: (_) =>
                  context.push(AppRoutes.reportListing(listingId)),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: Icon(Icons.flag_outlined),
                    title: Text('Report listing'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: switch (listing) {
        AsyncData(:final value) => _Details(listing: value, isOwner: isOwner),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(listingDetailProvider(listingId)),
        ),
        _ => const LoadingView(),
      },
      bottomNavigationBar: switch (listing) {
        AsyncData(:final value) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: isOwner
                ? _OwnerBar(listing: value)
                : _BuyerBar(listing: value),
          ),
        ),
        _ => null,
      },
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.listing, required this.isOwner});

  final Listing listing;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _PhotoPager(paths: listing.photoPaths),
        if (isOwner && listing.hidden)
          const _Banner(
            icon: Icons.visibility_off_rounded,
            text:
                'Hidden by an administrator. Other students can’t see or '
                'reserve it.',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatRm(listing.priceSen),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StatusPill.listing(listing.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(listing.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Fact(
                    icon: categoryIcon(listing.category),
                    text: listing.category,
                  ),
                  _Fact(
                    icon: Icons.auto_awesome_rounded,
                    text: listing.condition.label,
                  ),
                  _Fact(
                    icon: Icons.inventory_2_outlined,
                    text: listing.stock == 1
                        ? '1 available'
                        : '${listing.stock} available',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoRow(
                icon: Icons.place_outlined,
                title: 'Pickup on campus',
                text: listing.pickupArea,
              ),
              if (listing.pickupPin case final pin?) ...[
                PickupMapPreview(
                  key: ListingDetailScreen.pickupMapKey,
                  point: pin,
                  onTap: () => showPickupMap(
                    context,
                    point: pin,
                    place: listing.pickupArea,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  child: Text(
                    'Tap the map to see it larger or get directions.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              if (listing.businessName case final business?)
                InkWell(
                  key: ListingDetailScreen.storefrontKey,
                  onTap: () =>
                      context.push(AppRoutes.storefront(listing.businessId!)),
                  child: _InfoRow(
                    icon: Icons.storefront_outlined,
                    title: 'Sold by (tap for the storefront)',
                    text: isOwner ? '$business (your business)' : business,
                  ),
                )
              else if (listing.sellerName case final seller?)
                _InfoRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Seller',
                  text: isOwner ? '$seller (you)' : seller,
                ),
              if (listing.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Description',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  listing.description,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
              const SizedBox(height: 20),
              const _Banner(
                icon: Icons.handshake_outlined,
                text:
                    'Payment and pickup are arranged between you and the '
                    'seller. CampusNiaga doesn’t take payments.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoPager extends StatefulWidget {
  const _PhotoPager({required this.paths});

  final List<String> paths;

  @override
  State<_PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<_PhotoPager> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final paths = widget.paths;
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          if (paths.isEmpty)
            const ListingPhoto(path: null)
          else
            PageView.builder(
              itemCount: paths.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => ListingPhoto(path: paths[i]),
            ),
          if (paths.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < paths.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Colors.white
                            : const Color(0x99FFFFFF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFDF5E7),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF9A5B00)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
      ],
    ),
  );
}

/// Buyer: reserve (when something is left) or the reason they can't.
class _BuyerBar extends StatelessWidget {
  const _BuyerBar({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    // Business products are ordered (ready stock or a pre-order), on their
    // own screen; it says when nothing is left.
    if (listing.isBusiness) {
      return FilledButton.icon(
        key: ListingDetailScreen.orderKey,
        onPressed: () => context.push(AppRoutes.orderListing(listing.id)),
        icon: const Icon(Icons.shopping_bag_outlined),
        label: Text(
          listing.status == ListingStatus.available
              ? 'Order'
              : 'Sold out · see pre-orders',
        ),
      );
    }
    final canReserve =
        listing.status == ListingStatus.available && listing.stock > 0;
    return FilledButton(
      key: ListingDetailScreen.reserveKey,
      onPressed: canReserve
          ? () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _ReserveSheet(listing: listing),
            )
          : null,
      child: Text(switch (listing.status) {
        ListingStatus.available => 'Reserve',
        ListingStatus.reserved => 'Reserved by someone else',
        ListingStatus.sold => 'Sold',
        _ => 'Not available',
      }),
    );
  }
}

class _ReserveSheet extends ConsumerStatefulWidget {
  const _ReserveSheet({required this.listing});

  final Listing listing;

  @override
  ConsumerState<_ReserveSheet> createState() => _ReserveSheetState();
}

class _ReserveSheetState extends ConsumerState<_ReserveSheet> {
  final _note = TextEditingController();
  int _qty = 1;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    try {
      final paymentId = await ref
          .read(marketplaceActionsProvider)
          .reserve(
            listingId: widget.listing.id,
            qty: _qty,
            pickupNote: _note.text,
            paymentMethod: _method,
          );
      navigator.pop();
      if (paymentId != null) {
        // Transfer: straight to where to pay; the item is held meanwhile.
        unawaited(router.push(AppRoutes.payment(paymentId)));
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Reserved! The seller has 48 hours to respond. '
              'See it under Bookings.',
            ),
          ),
        );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showMessage(context, AppFailure.messageOf(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = widget.listing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reserve this item', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            _method == PaymentMethod.transfer
                ? 'The item is held for you for 30 minutes while you pay.'
                : 'The item is held for you while the seller responds.',
            style: theme.textTheme.bodyMedium,
          ),
          if (listing.stock > 1) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Quantity',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Remove one',
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$_qty',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Add one',
                  onPressed: _qty < listing.stock
                      ? () => setState(() => _qty++)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          PaymentMethodPicker(
            value: _method,
            transferAvailable:
                ref.watch(acceptsTransferProvider(listing.id)).value ?? false,
            onChanged: (m) => setState(() => _method = m),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _note,
            maxLength: 200,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Pickup preference (optional), e.g. after 5pm at Tekun',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Total', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                formatRm(listing.priceSen * _qty),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _method == PaymentMethod.transfer
                        ? 'Reserve and pay'
                        : 'Confirm reservation',
                  ),
          ),
        ],
      ),
    );
  }
}

/// Owner: the actions their listing's status allows.
class _OwnerBar extends ConsumerStatefulWidget {
  const _OwnerBar({required this.listing});

  final Listing listing;

  @override
  ConsumerState<_OwnerBar> createState() => _OwnerBarState();
}

class _OwnerBarState extends ConsumerState<_OwnerBar> {
  bool _busy = false;

  Future<void> _run(OwnerAction action) async {
    final listing = widget.listing;
    if (action == OwnerAction.edit) {
      await context.push(AppRoutes.editListing(listing.id));
      return;
    }
    final target = targetStatusOf(action)!;
    if (action == OwnerAction.markSold || action == OwnerAction.close) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            action == OwnerAction.markSold ? 'Mark as sold?' : 'Close listing?',
          ),
          content: Text(
            action == OwnerAction.markSold
                ? 'Use this if it sold outside the app. Buyers can no longer '
                      'reserve it.'
                : 'It leaves the marketplace. You can re-open it later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                action == OwnerAction.markSold ? 'Mark sold' : 'Close',
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(marketplaceActionsProvider)
          .setListingStatus(listing.id, target);
      if (mounted) {
        showMessage(context, 'Listing is now ${target.label.toLowerCase()}.');
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = ownerActionsFor(widget.listing);
    if (actions.isEmpty && widget.listing.isBusiness) {
      return OutlinedButton.icon(
        onPressed: () => context.push(AppRoutes.ordersSelling),
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('See its orders'),
      );
    }
    if (actions.isEmpty) {
      return OutlinedButton.icon(
        onPressed: () => context.go(AppRoutes.reservations),
        icon: const Icon(Icons.receipt_long_rounded),
        label: Text(
          widget.listing.status == ListingStatus.sold
              ? 'Sold. See reservations'
              : 'Manage its reservations',
        ),
      );
    }
    final primary = actions.firstWhere(
      (a) => a != OwnerAction.edit,
      orElse: () => OwnerAction.edit,
    );
    final secondary = actions.where((a) => a != primary).toList();
    return Row(
      children: [
        for (final action in secondary) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _run(action),
              child: Text(_label(action)),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FilledButton(
            onPressed: _busy ? null : () => _run(primary),
            child: Text(_label(primary)),
          ),
        ),
      ],
    );
  }

  static String _label(OwnerAction action) => switch (action) {
    OwnerAction.edit => 'Edit',
    OwnerAction.publish => 'Publish',
    OwnerAction.close => 'Close',
    OwnerAction.reopen => 'Re-open',
    OwnerAction.markSold => 'Sold',
  };
}
