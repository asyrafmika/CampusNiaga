import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/listing_enums.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/listing.dart';
import 'marketplace_providers.dart';
import 'widgets/listing_widgets.dart';

/// The user's own listings, filtered by status.
class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  ListingStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final listings = ref.watch(myListingsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My listings'),
        backgroundColor: AppColors.background,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.sell),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New listing'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final status in <ListingStatus?>[
                  null,
                  ...ListingStatus.values.where(
                    (s) => s != ListingStatus.deleted,
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(status?.label ?? 'All'),
                      selected: _filter == status,
                      onSelected: (_) => setState(() => _filter = status),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (listings) {
              AsyncData(:final value) => _List(
                listings: [
                  for (final l in value)
                    if (_filter == null || l.status == _filter) l,
                ],
                anyAtAll: value.isNotEmpty,
                onRefresh: () => ref.refresh(myListingsProvider.future),
              ),
              AsyncError(:final error) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(myListingsProvider),
              ),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.listings,
    required this.anyAtAll,
    required this.onRefresh,
  });

  final List<Listing> listings;
  final bool anyAtAll;
  final Future<Object?> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) {
      return EmptyView(
        icon: Icons.inventory_2_outlined,
        title: anyAtAll ? 'Nothing here' : 'You haven’t listed anything yet',
        message: anyAtAll
            ? 'No listings with this status.'
            : 'Tap New listing to sell your first item.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        itemCount: listings.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _Tile(listing: listings[i]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(AppRoutes.listing(listing.id)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 76,
                  child: ListingPhoto(path: listing.coverPhoto),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatRm(listing.priceSen)} · ${listing.stock} left',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        StatusPill.listing(listing.status),
                        if (listing.hidden)
                          const StatusPill(
                            label: 'Hidden',
                            tone: PillTone.warning,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.icon),
            ],
          ),
        ),
      ),
    );
  }
}
