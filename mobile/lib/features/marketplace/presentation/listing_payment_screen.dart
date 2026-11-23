import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/listing_enums.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/state_views.dart';
import '../../payments/presentation/payment_details_screen.dart';
import '../../payments/presentation/payment_providers.dart';
import 'marketplace_providers.dart';

/// The listing's second step (ADR 0008): how buyers pay the seller. The
/// details belong to the seller, so they are filled in from last time and
/// used for all their items. With [publish], finishing publishes the draft.
class ListingPaymentScreen extends ConsumerWidget {
  const ListingPaymentScreen({
    super.key,
    required this.listingId,
    this.publish = false,
  });

  final String listingId;
  final bool publish;

  static const Key draftKey = Key('listing-payment-draft');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(myPaymentDetailsProvider);

    // After saving: publish if asked, then show the listing.
    Future<void> finish({required bool publishNow}) async {
      if (publishNow) {
        await ref
            .read(marketplaceActionsProvider)
            .setListingStatus(listingId, ListingStatus.available);
      }
      if (!context.mounted) return;
      showMessage(
        context,
        publishNow
            ? 'Published! Your item is now in the marketplace.'
            : publish
            ? 'Saved as a draft. Publish it when you’re ready.'
            : 'Changes saved.',
      );
      if (publish) {
        context.pushReplacement(AppRoutes.listing(listingId));
      } else {
        context.pop();
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('How buyers pay you')),
      body: switch (saved) {
        AsyncData(:final value) => PaymentDetailsForm(
          forBusiness: false,
          initial: value.personal,
          intro:
              'Buyers can always pay cash when they collect. Add a bank '
              'account or a QR code so they can also pay by transfer. These '
              'details are used for all your items.',
          submitLabel: publish ? 'Publish' : 'Save',
          onDone: (_) => finish(publishNow: publish),
          secondary: publish
              ? TextButton(
                  key: draftKey,
                  onPressed: () => finish(publishNow: false),
                  child: const Text('Not yet: keep it as a draft'),
                )
              : null,
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(myPaymentDetailsProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}
