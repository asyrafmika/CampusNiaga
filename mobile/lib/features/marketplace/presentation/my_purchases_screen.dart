import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../payments/presentation/widgets/payment_widgets.dart';
import '../domain/purchase.dart';
import 'marketplace_providers.dart';
import 'widgets/listing_widgets.dart';

/// Purchases: what I bought, and what others bought from me.
class MyPurchasesScreen extends StatelessWidget {
  const MyPurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: PurchaseSide.values.length,
    child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My purchases'),
        backgroundColor: AppColors.background,
        bottom: TabBar(
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: [for (final side in PurchaseSide.values) Tab(text: side.label)],
        ),
      ),
      body: const TabBarView(
        children: [
          _PurchaseList(side: PurchaseSide.buying),
          _PurchaseList(side: PurchaseSide.selling),
        ],
      ),
    ),
  );
}

class _PurchaseList extends ConsumerWidget {
  const _PurchaseList({required this.side});

  final PurchaseSide side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(myPurchasesProvider(side));
    final buying = side == PurchaseSide.buying;
    return switch (purchases) {
      AsyncData(:final value) when value.isEmpty => EmptyView(
        icon: buying ? Icons.shopping_bag_outlined : Icons.storefront_outlined,
        title: buying ? 'No purchases yet' : 'No sales yet',
        message: buying
            ? 'Buy an item and it shows up here.'
            : 'When someone buys your item, you’ll see it here.',
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(myPurchasesProvider(side).future),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => PurchaseTile(purchase: value[i]),
        ),
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(myPurchasesProvider(side)),
      ),
      _ => const LoadingView(),
    };
  }
}

class PurchaseTile extends ConsumerStatefulWidget {
  const PurchaseTile({super.key, required this.purchase});

  final PurchaseCard purchase;

  static Key chatKey(String id) => Key('purchase-chat-$id');
  static Key actionKey(String id, PurchaseAction action) =>
      Key('purchase-${action.name}-$id');
  static const Key confirmKey = Key('purchase-action-confirm');
  static const Key cancelReasonKey = Key('purchase-cancel-reason');
  static const Key cancelDeleteKey = Key('purchase-cancel-delete');

  @override
  ConsumerState<PurchaseTile> createState() => _PurchaseTileState();
}

class _PurchaseTileState extends ConsumerState<PurchaseTile> {
  bool _busy = false;

  Future<void> _run(PurchaseAction action) async {
    final p = widget.purchase;
    String? reason;
    var relist = true;
    if (action == PurchaseAction.cancel && !p.iAmBuyer) {
      // A seller says why, and what happens to the item.
      final choice = await showDialog<({String reason, bool relist})>(
        context: context,
        builder: (context) => const _SellerCancelDialog(),
      );
      if (choice == null) return;
      (:reason, :relist) = choice;
    } else {
      final (title, body, confirm) = switch (action) {
        PurchaseAction.complete => (
          'Complete the sale?',
          'Confirm you handed the item over and were paid. This can’t be '
              'undone.',
          'Complete',
        ),
        PurchaseAction.relist => (
          'Relist this item?',
          'Only if the buyer didn’t collect it. The purchase is cancelled and '
              'the item goes back on sale.',
          'Relist',
        ),
        PurchaseAction.cancel => (
          'Cancel this purchase?',
          'The item goes back on sale, so someone else can buy it.',
          'Cancel purchase',
        ),
      };
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            TextButton(
              key: PurchaseTile.confirmKey,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirm),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final actions = ref.read(marketplaceActionsProvider);
      await switch (action) {
        PurchaseAction.complete => actions.completePurchase(p),
        PurchaseAction.relist => actions.relistPurchase(p),
        PurchaseAction.cancel => actions.cancelPurchase(
          p,
          reason: reason,
          relist: relist,
        ),
      };
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.purchase;
    final now = DateTime.now();
    final actions = PurchaseRules.actionsFor(p, now);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(AppRoutes.listing(p.listingId)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(purchase: p),
              const SizedBox(height: 10),
              Text(
                PurchaseRules.explanation(p),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (p.payment case final payment?)
                PaymentStrip(
                  payment: payment,
                  iAmBuyer: p.iAmBuyer,
                  onOpen: () => context.push(AppRoutes.payment(payment.id)),
                ),
              _Line(icon: Icons.place_outlined, text: p.pickupArea),
              if (p.relistFrom case final from?
                  when !p.iAmBuyer && now.isBefore(from))
                _Line(
                  icon: Icons.timer_outlined,
                  text:
                      'Not collected? You can relist from '
                      '${formatDayTime(from)}.',
                ),
              if (p.canChat) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: PurchaseTile.chatKey(p.id),
                  onPressed: () =>
                      context.push(AppRoutes.chatForPurchase(p.id)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text(
                    'Chat with the ${p.iAmBuyer ? 'seller' : 'buyer'}',
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ActionRow(
                  purchaseId: p.id,
                  actions: actions,
                  onRun: _busy ? null : _run,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.purchase});

  final PurchaseCard purchase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = purchase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.square(
                dimension: 64,
                child: ListingPhoto(path: p.listingPhoto),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.listingTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.qty} × ${formatRm(p.unitPriceSen)} = '
                    '${formatRm(p.totalSen)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.iAmBuyer ? 'Seller' : 'Buyer'}: ${p.otherPartyName}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Under the header: "Awaiting handover" is too wide to sit beside
        // the title on a phone.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill.purchase(p.status),
            Text(p.paymentMethod.label, style: theme.textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

/// The first action filled (unless it's Cancel), the others outlined.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.purchaseId,
    required this.actions,
    required this.onRun,
  });

  final String purchaseId;
  final List<PurchaseAction> actions;
  final ValueChanged<PurchaseAction>? onRun;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, action) in actions.indexed) ...[
        if (i > 0) const SizedBox(height: 8),
        if (i == 0 && action != PurchaseAction.cancel)
          FilledButton(
            key: PurchaseTile.actionKey(purchaseId, action),
            onPressed: onRun == null ? null : () => onRun!(action),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            child: Text(action.label),
          )
        else
          OutlinedButton(
            key: PurchaseTile.actionKey(purchaseId, action),
            onPressed: onRun == null ? null : () => onRun!(action),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            child: Text(action.label),
          ),
      ],
    ],
  );
}

/// Why the seller cancels, and whether the item is relisted or closed. Owns
/// its controller, so it lives as long as the dialog.
class _SellerCancelDialog extends StatefulWidget {
  const _SellerCancelDialog();

  @override
  State<_SellerCancelDialog> createState() => _SellerCancelDialogState();
}

class _SellerCancelDialogState extends State<_SellerCancelDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  bool _relist = true;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cancel this sale?'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The buyer is told why. If they already paid, refund them '
            'yourself.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: PurchaseTile.cancelReasonKey,
            controller: _reason,
            maxLength: PurchaseRules.maxReason,
            decoration: const InputDecoration(hintText: 'e.g. It got damaged'),
            validator: PurchaseRules.cancelReason,
          ),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Relist it'),
                selected: _relist,
                onSelected: (_) => setState(() => _relist = true),
              ),
              ChoiceChip(
                key: PurchaseTile.cancelDeleteKey,
                label: const Text('Delete the listing'),
                selected: !_relist,
                onSelected: (_) => setState(() => _relist = false),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Not now'),
      ),
      TextButton(
        key: PurchaseTile.confirmKey,
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, (
              reason: _reason.text.trim(),
              relist: _relist,
            ));
          }
        },
        child: const Text('Cancel sale'),
      ),
    ],
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}
