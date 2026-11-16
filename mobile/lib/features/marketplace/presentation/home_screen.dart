import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/listing_query.dart';
import 'marketplace_providers.dart';
import 'widgets/feed_footer.dart';
import 'widgets/listing_widgets.dart';

/// Home (Nestora layout): greeting, search bar, a "sell something" card,
/// categories, then the newest listings, loaded page by page.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const ListingQuery _newest = ListingQuery();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider(_newest));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(feedProvider(_newest).future),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 600) {
                ref.read(feedProvider(_newest).notifier).loadMore();
              }
              return false;
            },
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _Header()),
                const SliverToBoxAdapter(child: _SearchBar()),
                const SliverToBoxAdapter(child: _SellCard()),
                const SliverToBoxAdapter(child: _Categories()),
                const SliverToBoxAdapter(child: _DiscoverCard()),
                SliverToBoxAdapter(
                  child: _SectionTitle(
                    title: 'Just listed',
                    action: 'See all',
                    onAction: () => context.go(AppRoutes.search),
                  ),
                ),
                ...switch (feed) {
                  AsyncData(:final value) when value.items.isEmpty => [
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: EmptyView(
                          icon: Icons.storefront_rounded,
                          title: 'Nothing for sale yet',
                          message: 'Be the first: tap Sell to list something.',
                        ),
                      ),
                    ),
                  ],
                  AsyncData(:final value) => [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: ListingGrid(
                        listings: value.items,
                        onOpen: (l) => context.push(AppRoutes.listing(l.id)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: FeedFooter(
                        state: value,
                        onRetry: () =>
                            ref.read(feedProvider(_newest).notifier).loadMore(),
                      ),
                    ),
                  ],
                  AsyncError(:final error) => [
                    SliverToBoxAdapter(
                      child: ErrorView(
                        error: error,
                        onRetry: () => ref.invalidate(feedProvider(_newest)),
                      ),
                    ),
                  ],
                  _ => [
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: LoadingView(),
                      ),
                    ),
                  ],
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(myNameProvider).value ?? '';
    final firstName = name.trim().split(RegExp(r'\s+')).first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Universiti Sains Malaysia',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  firstName.isEmpty ? 'Hi there' : 'Hi, $firstName',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => context.go(AppRoutes.profile),
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primarySoft,
              child: Text(
                firstName.isEmpty ? '?' : firstName[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(AppRoutes.search),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: AppColors.icon),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Search books, gadgets, hostel stuff…',
                  style: TextStyle(color: AppColors.hint, fontSize: 15),
                ),
              ),
              Icon(Icons.tune_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SellCard extends StatelessWidget {
  const _SellCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Got something to sell?',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'List it in a minute. Buyers on campus collect it '
                    'in person.',
                    style: TextStyle(color: Color(0xD9FFFFFF), height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => context.push(AppRoutes.sell),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryDark,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: const Text('Start selling'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0x26FFFFFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sell_rounded,
                color: AppColors.accent,
                size: 40,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Leads to M4: request what you can't find, see what students want.
class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard();

  static const Key cardKey = Key('home-discover');

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        key: cardKey,
        onTap: () => context.push(AppRoutes.discover),
        leading: const Icon(
          Icons.lightbulb_outline_rounded,
          color: AppColors.accent,
        ),
        title: const Text(
          'Can’t find it? Request it',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('And see what other students want to buy'),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.icon,
        ),
      ),
    ),
  );
}

class _Categories extends ConsumerWidget {
  const _Categories();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    if (categories.isEmpty) return const SizedBox(height: 8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(title: 'Categories'),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _CategoryChip(
              category: categories[i],
              onTap: () => context.go(AppRoutes.searchCategory(categories[i])),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.onTap});

  final String category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      width: 72,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(categoryIcon(category), color: AppColors.primary),
          ),
          const SizedBox(height: 6),
          Text(
            category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 12, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (action case final action?)
          TextButton(onPressed: onAction, child: Text(action)),
      ],
    ),
  );
}
