import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/domain/listing_enums.dart';
import '../../../../core/domain/payment.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../marketplace/domain/listing.dart';
import '../../../marketplace/presentation/marketplace_providers.dart';
import '../../../marketplace/presentation/widgets/listing_widgets.dart';
import '../../../payments/presentation/payment_providers.dart';
import '../../../payments/presentation/widgets/payment_widgets.dart';
import '../domain/store_models.dart';
import 'store_providers.dart';
import 'widgets/store_widgets.dart';

/// Order a business product: ready stock, or one of its open pre-orders.
class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key, required this.listingId, this.campaignId});

  final String listingId;

  /// Pre-select this pre-order.
  final String? campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(listingDetailProvider(listingId));
    final businessId = listing.value?.businessId;
    final store = businessId == null
        ? null
        : ref.watch(storefrontProvider(businessId));

    final Widget body;
    if (listing case AsyncError(:final error)) {
      body = ErrorView(
        error: error,
        onRetry: () => ref.invalidate(listingDetailProvider(listingId)),
      );
    } else if (store case AsyncError(:final error)) {
      body = ErrorView(
        error: error,
        onRetry: () => ref.invalidate(storefrontProvider(businessId!)),
      );
    } else if (listing.value case final l? when !l.isBusiness) {
      body = const EmptyView(
        icon: Icons.handshake_outlined,
        title: 'Buy this item from its page',
        message: 'Personal items use Buy now, not orders.',
      );
    } else if (listing.value == null || store?.value == null) {
      body = const LoadingView();
    } else {
      body = _OrderForm(
        listing: listing.value!,
        campaigns: store!.value!.campaignsFor(listingId),
        initialCampaignId: campaignId,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Order')),
      body: body,
    );
  }
}

class _OrderForm extends ConsumerStatefulWidget {
  const _OrderForm({
    required this.listing,
    required this.campaigns,
    this.initialCampaignId,
  });

  final Listing listing;
  final List<Campaign> campaigns;
  final String? initialCampaignId;

  @override
  ConsumerState<_OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends ConsumerState<_OrderForm> {
  static const Key submitKey = Key('order-submit');

  final _note = TextEditingController();
  final DateTime _now = DateTime.now();
  late final List<Campaign> _open = [
    for (final c in widget.campaigns)
      if (c.takesOrdersAt(_now)) c,
  ];
  late final bool _inStock =
      widget.listing.status == ListingStatus.available &&
      widget.listing.stock > 0;

  /// The chosen pre-order; `null` means ready stock.
  late Campaign? _campaign = _initialChoice();
  int _qty = 1;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  Campaign? _initialChoice() {
    for (final c in _open) {
      if (c.id == widget.initialCampaignId) return c;
    }
    return _inStock || _open.isEmpty ? null : _open.first;
  }

  bool get _canOrder => _campaign != null || _inStock;

  int get _max => _campaign?.maxPerOrder ?? widget.listing.stock;

  int get _unitPrice => _campaign?.priceSen ?? widget.listing.priceSen;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final preOrder = _campaign != null;
    try {
      final paymentId = await ref
          .read(storeActionsProvider)
          .placeOrder(
            listingId: widget.listing.id,
            businessId: widget.listing.businessId!,
            qty: _qty,
            campaignId: _campaign?.id,
            note: _note.text,
            paymentMethod: _method,
          );
      if (!mounted) return;
      if (paymentId != null) {
        // Transfer: straight to where to pay; the order waits for the proof.
        context.pushReplacement(AppRoutes.payment(paymentId));
        return;
      }
      showMessage(
        context,
        preOrder
            ? 'Pre-ordered! The business will confirm it. See My orders.'
            : 'Ordered! The business will confirm it. See My orders.',
      );
      context.pop();
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.square(
                dimension: 72,
                child: ListingPhoto(path: listing.coverPhoto),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(listing.title, style: theme.textTheme.titleMedium),
                  if (listing.businessName case final name?)
                    Text(name, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (!_canOrder)
          const EmptyView(
            icon: Icons.inventory_2_outlined,
            title: 'Not available right now',
            message: 'It’s sold out and has no open pre-order.',
          )
        else ...[
          Text('How do you want it?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_inStock)
            _Choice(
              key: const Key('order-choice-stock'),
              selected: _campaign == null,
              title: 'Buy from stock',
              subtitle:
                  '${formatRm(listing.priceSen)} · ${listing.stock} available',
              onTap: () => setState(() {
                _campaign = null;
                _qty = 1;
              }),
            ),
          for (final c in _open)
            _Choice(
              key: Key('order-choice-${c.id}'),
              selected: _campaign?.id == c.id,
              title: 'Pre-order: ${c.title}',
              subtitle:
                  '${formatRm(c.priceSen)} · ${c.remaining} places left · '
                  'closes ${formatDay(c.closeAt)}\nCollect: ${c.pickupDetails}',
              onTap: () => setState(() {
                _campaign = c;
                _qty = 1;
              }),
            ),
          const SizedBox(height: 16),
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
                onPressed: _qty < _max ? () => setState(() => _qty++) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (_campaign?.perOrderLimit case final limit?)
            Text('Up to $limit per order.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          PaymentMethodPicker(
            value: _method,
            transferAvailable:
                ref.watch(acceptsTransferProvider(listing.id)).value ?? false,
            onChanged: (m) => setState(() => _method = m),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const Key('order-note'),
            controller: _note,
            maxLength: 200,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Note for the business (optional), e.g. after 5pm',
            ),
          ),
          Row(
            children: [
              Text('Total', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                formatRm(_unitPrice * _qty),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: submitKey,
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(_campaign == null ? 'Place order' : 'Pre-order'),
          ),
          const SizedBox(height: 16),
          const OffPlatformNotice(),
        ],
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selected ? AppColors.primarySoft : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_off_rounded,
          color: AppColors.primary,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        isThreeLine: subtitle.contains('\n'),
      ),
    ),
  );
}
