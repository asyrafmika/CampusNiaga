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

/// Product detail: photos, price, details and seller; buyers chat, buy or
/// report, owners manage the listing.
class ListingDetailScreen extends ConsumerWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  static const Key buyKey = Key('detail-buy');
  static const Key chatKey = Key('detail-chat');
  static const Key buyPickupKey = Key('buy-pickup');
  static const Key confirmBuyKey = Key('buy-confirm');
  static const Key confirmOwnerActionKey = Key('owner-action-confirm');
  static Key ownerActionKey(OwnerAction action) => Key('owner-${action.name}');
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
                'buy it.',
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

/// Buyer: chat (which holds nothing) and Buy now, or why they can't buy.
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
    final canBuy =
        listing.status == ListingStatus.available && listing.stock > 0;
    final buy = FilledButton(
      key: ListingDetailScreen.buyKey,
      onPressed: canBuy
          ? () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _BuySheet(listing: listing),
            )
          : null,
      child: Text(switch (listing.status) {
        ListingStatus.available => 'Buy now',
        ListingStatus.sold => 'Sold',
        _ => 'Not available',
      }),
    );
    if (!canBuy) return buy;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: ListingDetailScreen.chatKey,
            onPressed: () => context.push(AppRoutes.chatForListing(listing.id)),
            child: const Text('Chat', semanticsLabel: 'Chat with seller'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: buy),
      ],
    );
  }
}

/// Quantity and payment, then Confirm purchase: only that buys the item.
class _BuySheet extends ConsumerStatefulWidget {
  const _BuySheet({required this.listing});

  final Listing listing;

  @override
  ConsumerState<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends ConsumerState<_BuySheet> {
  int _qty = 1;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    try {
      final paymentId = await ref
          .read(marketplaceActionsProvider)
          .buy(listingId: widget.listing.id, qty: _qty, paymentMethod: _method);
      // Only the sheet: it may have been closed while the call ran.
      if (mounted) navigator.pop();
      if (paymentId != null) {
        // Transfer: straight to where to pay.
        unawaited(router.push(AppRoutes.payment(paymentId)));
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Bought! Arrange pickup with the seller in the chat, under '
              'Purchases.',
            ),
          ),
        );
    } on Object catch (e) {
      // Closed first, so the message isn't hidden behind the sheet.
      if (mounted) navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AppFailure.messageOf(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = widget.listing;
    return SingleChildScrollView(
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
          Text('Buy this item', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            _method == PaymentMethod.transfer
                ? 'It’s yours once you confirm. Send your receipt within 30 '
                      'minutes or it goes back on sale.'
                : 'It’s yours once you confirm, first come, first served. '
                      'Pay cash when you collect.',
            style: theme.textTheme.bodyMedium,
          ),
          if (listing.stock > 1) ...[
            const SizedBox(height: 18),
            _QuantityRow(
              qty: _qty,
              max: listing.stock,
              // Steps, not values: two taps can land before a rebuild.
              onStep: (by) =>
                  setState(() => _qty = (_qty + by).clamp(1, listing.stock)),
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
          // Collection happens where the seller pinned it; a different time
          // or place is agreed in the chat.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.place_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pickup at ${listing.pickupArea}. You can chat with the '
                  'seller to agree on a time or another place.',
                  key: ListingDetailScreen.buyPickupKey,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
            key: ListingDetailScreen.confirmBuyKey,
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('Confirm purchase'),
          ),
        ],
      ),
    );
  }
}

class _QuantityRow extends StatelessWidget {
  const _QuantityRow({
    required this.qty,
    required this.max,
    required this.onStep,
  });

  final int qty;
  final int max;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text('Quantity', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      IconButton.outlined(
        tooltip: 'Remove one',
        onPressed: qty > 1 ? () => onStep(-1) : null,
        icon: const Icon(Icons.remove_rounded),
      ),
      SizedBox(
        width: 44,
        child: Text(
          '$qty',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton.outlined(
        tooltip: 'Add one',
        onPressed: qty < max ? () => onStep(1) : null,
        icon: const Icon(Icons.add_rounded),
      ),
    ],
  );
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
    // A personal draft is published from its payment step.
    if (action == OwnerAction.publish && !listing.isBusiness) {
      await context.push(AppRoutes.listingPayment(listing.id, publish: true));
      return;
    }
    final target = targetStatusOf(action)!;
    if (action == OwnerAction.markSold || action == OwnerAction.delete) {
      final delete = action == OwnerAction.delete;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(delete ? 'Delete this listing?' : 'Mark as sold?'),
          content: Text(
            delete
                ? 'It’s removed from the marketplace and your listings for '
                      'good. Purchases and orders already made carry on.'
                : 'Use this if it sold outside the app. Buyers can no longer '
                      'buy it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            TextButton(
              key: ListingDetailScreen.confirmOwnerActionKey,
              onPressed: () => Navigator.pop(context, true),
              child: Text(delete ? 'Delete' : 'Mark sold'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(marketplaceActionsProvider)
          .setListingStatus(listing.id, target);
      if (!mounted) return;
      if (action == OwnerAction.delete) {
        showMessage(context, 'Listing deleted.');
        context.pop();
        return;
      }
      showMessage(context, 'Listing is now ${target.label.toLowerCase()}.');
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
        onPressed: () => context.go(AppRoutes.purchases),
        icon: const Icon(Icons.receipt_long_rounded),
        label: Text(
          widget.listing.status == ListingStatus.deleted
              ? 'Deleted. See purchases'
              : 'Sold. See purchases',
        ),
      );
    }
    // The main button: the status change, else Edit (restocking a sold-out
    // product). Delete is never the main button, and looks destructive.
    final main = actions.where(
      (a) => a != OwnerAction.edit && a != OwnerAction.delete,
    );
    final primary = main.isNotEmpty
        ? main.first
        : actions.contains(OwnerAction.edit)
        ? OwnerAction.edit
        : null;
    final others = actions
        .where((a) => a != primary && a != OwnerAction.delete)
        .toList();
    final error = Theme.of(context).colorScheme.error;
    // Each item starts a gap, except the first.
    final items = <Widget>[
      // A bin icon, so three buttons still fit a small phone on one line.
      if (actions.contains(OwnerAction.delete))
        IconButton.outlined(
          key: ListingDetailScreen.ownerActionKey(OwnerAction.delete),
          tooltip: 'Delete listing',
          color: error,
          style: IconButton.styleFrom(
            side: BorderSide(color: error.withValues(alpha: 0.5)),
            minimumSize: const Size(52, 52),
          ),
          onPressed: _busy ? null : () => _run(OwnerAction.delete),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      if (widget.listing.status == ListingStatus.sold &&
          !widget.listing.isBusiness)
        Expanded(
          child: OutlinedButton(
            onPressed: () => context.go(AppRoutes.purchases),
            child: const Text('See purchases'),
          ),
        ),
      for (final action in others)
        Expanded(
          child: OutlinedButton(
            key: ListingDetailScreen.ownerActionKey(action),
            onPressed: _busy ? null : () => _run(action),
            child: Text(_label(action)),
          ),
        ),
      if (primary != null)
        Expanded(
          child: FilledButton(
            key: ListingDetailScreen.ownerActionKey(primary),
            onPressed: _busy ? null : () => _run(primary),
            child: Text(_label(primary)),
          ),
        ),
    ];
    return Row(
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          item,
        ],
      ],
    );
  }

  static String _label(OwnerAction action) => switch (action) {
    OwnerAction.edit => 'Edit',
    OwnerAction.publish => 'Publish',
    OwnerAction.reopen => 'Re-open',
    OwnerAction.markSold => 'Sold',
    OwnerAction.delete => 'Delete',
  };
}
