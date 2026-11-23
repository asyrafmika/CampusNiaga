import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/listing_enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';

/// A listing photo from the private bucket, loaded with the user's token.
/// Shows a soft placeholder while loading or if the photo is missing.
class ListingPhoto extends ConsumerWidget {
  const ListingPhoto({super.key, required this.path, this.fit = BoxFit.cover});

  final String? path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = this.path;
    if (path == null) return const _PhotoPlaceholder();
    final request = ref.watch(listingRepositoryProvider).photo(path);
    return Image.network(
      request.url,
      headers: request.headers,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _PhotoPlaceholder(),
      errorBuilder: (context, error, stackTrace) => const _PhotoPlaceholder(),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.primarySoft,
    child: Center(
      child: Icon(Icons.image_outlined, color: AppColors.primary, size: 32),
    ),
  );
}

/// A small coloured label for a listing or purchase status.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.tone});

  factory StatusPill.listing(ListingStatus status) => StatusPill(
    label: status.label,
    tone: switch (status) {
      ListingStatus.available => PillTone.good,
      ListingStatus.draft => PillTone.neutral,
      ListingStatus.sold ||
      ListingStatus.closed ||
      ListingStatus.deleted => PillTone.muted,
    },
  );

  factory StatusPill.purchase(PurchaseStatus status) => StatusPill(
    label: status.label,
    tone: switch (status) {
      PurchaseStatus.awaitingPayment => PillTone.warning,
      PurchaseStatus.awaitingHandover => PillTone.info,
      PurchaseStatus.completed => PillTone.good,
      PurchaseStatus.cancelled => PillTone.muted,
    },
  );

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      PillTone.good => (const Color(0xFFE3F5EA), const Color(0xFF1E7A43)),
      PillTone.warning => (const Color(0xFFFDF0DA), const Color(0xFF9A5B00)),
      PillTone.info => (AppColors.primarySoft, AppColors.primaryDark),
      PillTone.neutral => (AppColors.inputFill, AppColors.text),
      PillTone.muted => (AppColors.inputFill, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum PillTone { good, warning, info, neutral, muted }

/// The feed's product card: photo, price, title and pickup area.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The photo takes whatever height the text leaves, so the card
              // never overflows with larger text.
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ListingPhoto(path: listing.coverPhoto),
                    if (listing.status != ListingStatus.available)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: StatusPill.listing(listing.status),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatRm(listing.priceSen),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      listing.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            listing.pickupArea,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A two-column grid of listing cards inside a scroll view.
class ListingGrid extends StatelessWidget {
  const ListingGrid({super.key, required this.listings, required this.onOpen});

  final List<Listing> listings;
  final ValueChanged<Listing> onOpen;

  @override
  Widget build(BuildContext context) => SliverGrid.builder(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 0.64,
    ),
    itemCount: listings.length,
    itemBuilder: (context, i) =>
        ListingCard(listing: listings[i], onTap: () => onOpen(listings[i])),
  );
}

/// An icon for each default category; anything else gets a generic one.
IconData categoryIcon(String category) => switch (category) {
  'Books' => Icons.menu_book_rounded,
  'Electronics' => Icons.devices_other_rounded,
  'Fashion' => Icons.checkroom_rounded,
  'Food & Beverage' => Icons.restaurant_rounded,
  'Hostel Essentials' => Icons.bed_rounded,
  'Stationery' => Icons.edit_rounded,
  _ => Icons.category_rounded,
};
