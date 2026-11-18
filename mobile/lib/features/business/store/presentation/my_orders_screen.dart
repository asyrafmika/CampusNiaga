import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/domain/business_enums.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../marketplace/presentation/widgets/listing_widgets.dart';
import '../../../payments/presentation/widgets/payment_widgets.dart';
import '../domain/store_models.dart';
import 'store_providers.dart';
import 'widgets/store_widgets.dart';

/// My Orders: what the student ordered and, for a business owner, what
/// their business was ordered.
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key, this.initialSide = OrderSide.buying});

  final OrderSide initialSide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An owner keeps the selling tab while suspended, to read the history.
    final hasBusiness =
        ref.watch(userAccessProvider).value?.businessStatus != null;
    if (!hasBusiness) {
      return Scaffold(
        appBar: AppBar(title: const Text('My orders')),
        body: const _OrderList(side: OrderSide.buying),
      );
    }
    return DefaultTabController(
      length: 2,
      initialIndex: initialSide == OrderSide.selling ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My orders'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Buying'),
              Tab(text: 'My business'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OrderList(side: OrderSide.buying),
            _OrderList(side: OrderSide.selling),
          ],
        ),
      ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  const _OrderList({required this.side});

  final OrderSide side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider(side));
    return switch (orders) {
      AsyncData(:final value) when value.isEmpty => EmptyView(
        icon: Icons.shopping_bag_outlined,
        title: 'No orders yet',
        message: side == OrderSide.buying
            ? 'Orders and pre-orders from student businesses appear here.'
            : 'When students order from your business, they appear here.',
      ),
      AsyncData(:final value) => RefreshIndicator(
        onRefresh: () => ref.refresh(myOrdersProvider(side).future),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => OrderTile(order: value[i]),
        ),
      ),
      AsyncError(:final error) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(myOrdersProvider(side)),
      ),
      _ => const LoadingView(),
    };
  }
}

/// One order with what the student may do next.
class OrderTile extends ConsumerStatefulWidget {
  const OrderTile({super.key, required this.order});

  final OrderCard order;

  @override
  ConsumerState<OrderTile> createState() => _OrderTileState();
}

class _OrderTileState extends ConsumerState<OrderTile> {
  bool _busy = false;

  /// Records the seller's own cost, for the estimated profit on the
  /// dashboard. Empty clears it.
  Future<void> _recordCost() async {
    final order = widget.order;
    final String? entered = await showDialog<String>(
      context: context,
      builder: (context) => _CostDialog(initialSen: order.costSen),
    );
    if (entered == null || !mounted) return;
    final text = entered.trim();
    final sen = text.isEmpty ? null : parseRmToSen(text);
    if (text.isNotEmpty && sen == null) {
      showMessage(context, 'Enter an amount, e.g. 9 or 8.50.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(storeActionsProvider).setOrderCost(order, sen);
      if (mounted) {
        showMessage(context, sen == null ? 'Cost cleared.' : 'Cost saved.');
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(OrderAction action) async {
    final order = widget.order;
    if (action == OrderAction.cancel || action == OrderAction.complete) {
      final rejecting =
          !order.iAmBuyer && order.status == OrderStatus.pendingConfirmation;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(switch (action) {
            OrderAction.complete => 'Mark as collected?',
            _ when rejecting => 'Reject this order?',
            _ => 'Cancel this order?',
          }),
          content: Text(
            action == OrderAction.complete
                ? 'Do this once the buyer has collected it. It can’t be undone.'
                : 'The other side is told, and the quantity is freed for '
                      'others.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                action == OrderAction.complete
                    ? 'Mark collected'
                    : rejecting
                    ? 'Reject'
                    : 'Cancel order',
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(storeActionsProvider).transitionOrder(order, action);
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final actions = OrderRules.actionsFor(order);
    final next = actions.where((a) => a != OrderAction.cancel).firstOrNull;
    final canCancel = actions.contains(OrderAction.cancel);
    final rejecting =
        !order.iAmBuyer && order.status == OrderStatus.pendingConfirmation;

    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => context.push(AppRoutes.listing(order.listingId)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox.square(
                      dimension: 60,
                      child: ListingPhoto(path: order.listingPhoto),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.campaignTitle ?? order.listingTitle,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${order.qty} × ${formatRm(order.unitPriceSen)} = '
                          '${formatRm(order.totalSen)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          '${order.isPreOrder ? 'Pre-order' : 'Order'} · '
                          '${order.iAmBuyer ? order.businessName : order.otherPartyName}'
                          ' · ${formatDay(order.createdAt)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  orderStatusPill(order.status),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _Line(Icons.place_outlined, 'Collect: ${order.collectionDetails}'),
            if (order.buyerNote case final note?)
              _Line(Icons.notes_rounded, 'Note: $note'),
            if (order.payment case final payment?)
              PaymentStrip(
                payment: payment,
                iAmBuyer: order.iAmBuyer,
                onOpen: () => context.push(AppRoutes.payment(payment.id)),
              ),
            if (order.otherPartyEmail case final email?)
              _Line(
                Icons.mail_outline_rounded,
                '${order.iAmBuyer ? 'Seller' : 'Buyer'}: '
                '${order.otherPartyName} · $email',
              ),
            if (!order.iAmBuyer && order.costSen != null)
              _Line(
                Icons.calculate_outlined,
                'Your cost: ${formatRm(order.costSen!)}',
              ),
            if (order.canRecordCost)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('order-cost-${order.id}'),
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all(const Size(0, 36)),
                  ),
                  onPressed: _busy ? null : _recordCost,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: Text(
                    order.costSen == null ? 'Record cost' : 'Change cost',
                  ),
                ),
              ),
            if (OrderRules.canChat(order.status))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('order-chat-${order.id}'),
                  style: ButtonStyle(
                    minimumSize: WidgetStateProperty.all(const Size(0, 36)),
                  ),
                  onPressed: () =>
                      context.push(AppRoutes.chatForOrder(order.id)),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text(
                    order.iAmBuyer
                        ? 'Chat with the business'
                        : 'Chat with the buyer',
                  ),
                ),
              ),
            if (order.status == OrderStatus.cancelled)
              _Line(Icons.block_rounded, switch (order.cancelledBy) {
                'seller' => 'Cancelled by the business',
                'system' => 'Cancelled: the payment wasn’t sent in time',
                _ => 'Cancelled by the buyer',
              }),
            if (next != null || canCancel) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (canCancel)
                    Expanded(
                      child: OutlinedButton(
                        key: Key('order-cancel-${order.id}'),
                        onPressed: _busy
                            ? null
                            : () => _run(OrderAction.cancel),
                        child: Text(rejecting ? 'Reject' : 'Cancel'),
                      ),
                    ),
                  if (next != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: Key('order-next-${order.id}'),
                        onPressed: _busy ? null : () => _run(next),
                        child: Text(next.label),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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

/// Asks for the seller's cost. It owns its text controller, so the
/// controller lives exactly as long as the dialog (including its closing
/// animation).
class _CostDialog extends StatefulWidget {
  const _CostDialog({this.initialSen});

  final int? initialSen;

  @override
  State<_CostDialog> createState() => _CostDialogState();
}

class _CostDialogState extends State<_CostDialog> {
  late final _controller = TextEditingController(
    text: widget.initialSen == null ? '' : senToInput(widget.initialSen!),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your cost for this order'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingredients, packaging and so on. Only you see it; it is used for '
          'the estimated profit on your dashboard.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('order-cost-field'),
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: 'RM ',
            hintText: 'Leave empty to clear',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('order-cost-save'),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
