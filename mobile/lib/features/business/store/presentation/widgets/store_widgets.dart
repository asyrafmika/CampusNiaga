import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/domain/business_enums.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/dates.dart';
import '../../../../../core/utils/money.dart';
import '../../../../marketplace/presentation/widgets/listing_widgets.dart';
import '../../data/store_repository.dart';
import '../../domain/store_models.dart';

/// A business logo from the private bucket, or its initial on a navy circle.
class BusinessLogo extends ConsumerWidget {
  const BusinessLogo({
    super.key,
    required this.name,
    required this.path,
    this.size = 56,
  });

  final String name;
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.primarySoft,
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
    final path = this.path;
    if (path == null) return fallback;
    final request = ref.watch(storeRepositoryProvider).logo(path);
    return ClipOval(
      child: Image.network(
        request.url,
        headers: request.headers,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

/// A pre-order: its title, price, places left and closing date.
class CampaignTile extends StatelessWidget {
  const CampaignTile({
    super.key,
    required this.campaign,
    this.onTap,
    this.trailing,
  });

  final Campaign campaign;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final String when;
    if (campaign.status == CampaignStatus.open &&
        now.isBefore(campaign.startAt)) {
      when = 'Opens ${formatDayTime(campaign.startAt)}';
    } else {
      when = 'Closes ${formatDayTime(campaign.closeAt)}';
    }
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 56,
                  child: ListingPhoto(path: campaign.listingPhoto),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      campaign.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatRm(campaign.priceSen)} · '
                      '${campaign.remaining} of ${campaign.capacity} left',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(when, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

StatusPill orderStatusPill(OrderStatus status) => StatusPill(
  label: status.label,
  tone: switch (status) {
    OrderStatus.pendingConfirmation => PillTone.warning,
    OrderStatus.confirmed ||
    OrderStatus.preparing ||
    OrderStatus.readyForPickup => PillTone.info,
    OrderStatus.completed => PillTone.good,
    OrderStatus.cancelled => PillTone.muted,
  },
);

StatusPill campaignStatusPill(CampaignStatus status) => StatusPill(
  label: status.label,
  tone: switch (status) {
    CampaignStatus.draft => PillTone.neutral,
    CampaignStatus.open => PillTone.good,
    CampaignStatus.closed => PillTone.muted,
  },
);

/// The reminder every buying screen shows.
class OffPlatformNotice extends StatelessWidget {
  const OffPlatformNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFDF5E7),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.handshake_outlined, size: 20, color: Color(0xFF9A5B00)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'You pay and collect directly with the business. CampusNiaga '
            'doesn’t take payments or deliver.',
            style: TextStyle(height: 1.35),
          ),
        ),
      ],
    ),
  );
}
