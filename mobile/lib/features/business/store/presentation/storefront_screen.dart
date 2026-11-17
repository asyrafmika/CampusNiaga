import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/business_enums.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/pickup_map.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../marketplace/presentation/widgets/listing_widgets.dart';
import '../domain/store_models.dart';
import 'store_providers.dart';
import 'widgets/store_widgets.dart';

/// Storefront: a business's name, logo, description, categories, pickup
/// details and map pin, open pre-orders and products.
class StorefrontScreen extends ConsumerWidget {
  const StorefrontScreen({super.key, required this.businessId});

  final String businessId;

  static const Key manageKey = Key('storefront-manage');
  static const Key pickupMapKey = Key('storefront-pickup-map');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storefrontProvider(businessId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(store.value?.business.name ?? 'Storefront'),
        backgroundColor: AppColors.background,
        actions: [
          if (store.value?.isOwner ?? false)
            TextButton.icon(
              key: manageKey,
              onPressed: () => context.push(AppRoutes.manageStore),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Manage'),
            ),
        ],
      ),
      body: switch (store) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(storefrontProvider(businessId).future),
          child: _StorefrontBody(store: value),
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(storefrontProvider(businessId)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _StorefrontBody extends StatelessWidget {
  const _StorefrontBody({required this.store});

  final Storefront store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final business = store.business;
    final now = DateTime.now();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverList.list(
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
                    Row(
                      children: [
                        BusinessLogo(
                          name: business.name,
                          path: business.logoPath,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                business.name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              if (business.ownerName case final owner?)
                                Text(
                                  'Run by $owner',
                                  style: const TextStyle(
                                    color: Color(0xD9FFFFFF),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (business.description.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        business.description,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            business.pickupDetails,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (business.pickupPin case final pin?) ...[
                const SizedBox(height: 12),
                PickupMapPreview(
                  key: StorefrontScreen.pickupMapKey,
                  point: pin,
                  height: 140,
                  onTap: () => showPickupMap(
                    context,
                    point: pin,
                    place: business.pickupDetails,
                  ),
                ),
              ],
              if (business.status == BusinessStatus.suspended) ...[
                const SizedBox(height: 12),
                const _Note(
                  'This business is suspended by an administrator. Other '
                  'students can’t see or order from it.',
                ),
              ],
              if (store.categories.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in store.categories)
                      Chip(
                        avatar: Icon(categoryIcon(c), size: 16),
                        label: Text(c),
                      ),
                  ],
                ),
              ],
              if (store.campaigns.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Pre-orders', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final campaign in store.campaigns) ...[
                  CampaignTile(
                    campaign: campaign,
                    onTap: store.isOwner
                        ? null
                        : () => context.push(
                            AppRoutes.orderListing(
                              campaign.listingId,
                              campaignId: campaign.id,
                            ),
                          ),
                    trailing: store.isOwner
                        ? null
                        : Text(
                            campaign.takesOrdersAt(now)
                                ? 'Pre-order'
                                : campaign.remaining == 0
                                ? 'Full'
                                : 'Soon',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 20),
              Text('Products', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
            ],
          ),
        ),
        if (store.listings.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Nothing in stock right now.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: ListingGrid(
              listings: store.listings,
              onOpen: (l) => context.push(AppRoutes.listing(l.id)),
            ),
          ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverToBoxAdapter(child: OffPlatformNotice()),
        ),
      ],
    );
  }
}

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
