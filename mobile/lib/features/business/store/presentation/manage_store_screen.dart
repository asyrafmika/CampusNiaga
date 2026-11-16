import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/domain/business_enums.dart';
import '../../../../core/domain/listing_enums.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../marketplace/domain/listing.dart';
import '../../../marketplace/presentation/marketplace_providers.dart';
import '../../../marketplace/presentation/widgets/listing_widgets.dart';
import '../../application/domain/business_application.dart';
import '../../application/presentation/application_providers.dart';
import '../domain/store_models.dart';
import 'store_providers.dart';
import 'widgets/store_widgets.dart';

/// The owner's store: storefront, products, pre-orders and orders.
class ManageStoreScreen extends ConsumerWidget {
  const ManageStoreScreen({super.key});

  static const Key addProductKey = Key('store-add-product');
  static const Key newCampaignKey = Key('store-new-campaign');
  static const Key dashboardKey = Key('store-dashboard');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(myBusinessProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My store'),
        backgroundColor: AppColors.background,
      ),
      body: switch (business) {
        AsyncData(value: final b?) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(myBusinessProvider)
              ..invalidate(myListingsProvider)
              ..invalidate(myCampaignsProvider);
            await ref.read(myBusinessProvider.future);
          },
          child: _Store(business: b),
        ),
        AsyncData() => const EmptyView(
          icon: Icons.storefront_outlined,
          title: 'No business yet',
          message:
              'Apply from Profile → My business. Once a reviewer '
              'approves it, your store opens here.',
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(myBusinessProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Store extends ConsumerWidget {
  const _Store({required this.business});

  final MyBusiness business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final suspended = business.status == BusinessStatus.suspended;
    final products = ref.watch(myListingsProvider);
    final campaigns = ref.watch(myCampaignsProvider);
    final businessProducts = [
      for (final l in products.value ?? const <Listing>[])
        if (l.isBusiness) l,
    ];
    final hasPublished = businessProducts.any(
      (l) => l.status != ListingStatus.draft && !l.hidden,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  BusinessLogo(name: business.name, path: business.logoPath),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(business.name, style: theme.textTheme.titleLarge),
                        Text(
                          'Pickup: ${business.pickupDetails}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!suspended)
                    OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.editStorefront),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit storefront'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        context.push(AppRoutes.storefront(business.id)),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('View as buyer'),
                  ),
                  FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.ordersSelling),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Orders'),
                  ),
                  if (!suspended)
                    FilledButton.icon(
                      key: ManageStoreScreen.dashboardKey,
                      onPressed: () => context.push(AppRoutes.dashboard),
                      icon: const Icon(Icons.insights_rounded),
                      label: const Text('Dashboard'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (suspended) ...[
          const SizedBox(height: 12),
          const _Note(
            'Your business is suspended by an administrator. Its products and '
            'pre-orders are hidden and it can’t take or progress orders. You '
            'can still read your order history.',
          ),
        ],
        const SizedBox(height: 24),
        _Header(
          title: 'Products',
          action: suspended
              ? null
              : TextButton.icon(
                  key: ManageStoreScreen.addProductKey,
                  onPressed: () => context.push(AppRoutes.sellBusiness),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add product'),
                ),
        ),
        switch (products) {
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(myListingsProvider),
          ),
          AsyncData() when businessProducts.isEmpty => const _Empty(
            'No products yet. Add one: it appears in the marketplace and on '
            'your storefront.',
          ),
          AsyncData() => Column(
            children: [
              for (final l in businessProducts) _ProductTile(listing: l),
            ],
          ),
          _ => const LoadingView(),
        },
        const SizedBox(height: 24),
        _Header(
          title: 'Pre-orders',
          action: suspended
              ? null
              : TextButton.icon(
                  key: ManageStoreScreen.newCampaignKey,
                  onPressed: hasPublished
                      ? () => context.push(AppRoutes.newCampaign)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New pre-order'),
                ),
        ),
        switch (campaigns) {
          AsyncError(:final error) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(myCampaignsProvider),
          ),
          AsyncData(:final value) when value.isEmpty => _Empty(
            hasPublished
                ? 'No pre-orders yet. Take orders ahead with a capacity '
                      'you can fulfil.'
                : 'Publish a product first, then take pre-orders for it.',
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final c in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CampaignRow(campaign: c, locked: suspended),
                ),
            ],
          ),
          _ => const LoadingView(),
        },
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: () => context.push(AppRoutes.listing(listing.id)),
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 48,
        child: ListingPhoto(path: listing.coverPhoto),
      ),
    ),
    title: Text(listing.title),
    subtitle: Text('${formatRm(listing.priceSen)} · ${listing.stock} in stock'),
    trailing: StatusPill.listing(listing.status),
  );
}

class _CampaignRow extends ConsumerStatefulWidget {
  const _CampaignRow({required this.campaign, required this.locked});

  final Campaign campaign;
  final bool locked;

  @override
  ConsumerState<_CampaignRow> createState() => _CampaignRowState();
}

class _CampaignRowState extends ConsumerState<_CampaignRow> {
  bool _busy = false;

  Future<void> _set(CampaignStatus status) async {
    if (status == CampaignStatus.closed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Close this pre-order?'),
          content: const Text(
            'It stops taking orders and can’t reopen. Orders already placed '
            'carry on.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(storeActionsProvider)
          .setCampaignStatus(widget.campaign.id, status);
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.campaign;
    final next = widget.locked
        ? const <CampaignStatus>[]
        : StoreRules.nextStatuses(c.status);
    return CampaignTile(
      campaign: c,
      onTap: widget.locked || c.status == CampaignStatus.closed
          ? null
          : () => context.push(AppRoutes.editCampaign(c.id)),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          campaignStatusPill(c.status),
          if (next.contains(CampaignStatus.open))
            TextButton(
              key: Key('campaign-open-${c.id}'),
              onPressed: _busy ? null : () => _set(CampaignStatus.open),
              child: const Text('Open'),
            )
          else if (next.contains(CampaignStatus.closed))
            TextButton(
              key: Key('campaign-close-${c.id}'),
              onPressed: _busy ? null : () => _set(CampaignStatus.closed),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      ?action,
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: const TextStyle(color: AppColors.textSecondary)),
  );
}

/// A grey note box.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(text),
  );
}
