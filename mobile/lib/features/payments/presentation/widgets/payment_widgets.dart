import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/payment.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/dates.dart';
import '../../data/payment_repository.dart';
import '../../domain/payment_models.dart';

/// A QR code or a proof screenshot from its private bucket.
class PaymentImage extends ConsumerWidget {
  const PaymentImage({
    super.key,
    required this.bucket,
    required this.path,
    this.fit = BoxFit.contain,
  });

  final String bucket;
  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(paymentRepositoryProvider).image(bucket, path);
    return Image.network(
      request.url,
      headers: request.headers,
      fit: fit,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator()),
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image_outlined, color: AppColors.icon),
      ),
    );
  }
}

/// Cash on pickup, or a transfer when the seller takes them.
class PaymentMethodPicker extends StatelessWidget {
  const PaymentMethodPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.transferAvailable,
  });

  final PaymentMethod value;
  final ValueChanged<PaymentMethod> onChanged;
  final bool transferAvailable;

  static Key optionKey(PaymentMethod method) =>
      Key('pay-method-${method.wireName}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('How will you pay?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final method in PaymentMethod.values)
          if (method == PaymentMethod.cash || transferAvailable)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: value == method
                    ? AppColors.primarySoft
                    : AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: value == method
                        ? AppColors.primary
                        : AppColors.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  key: optionKey(method),
                  onTap: () => onChanged(method),
                  leading: Icon(
                    value == method
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    method.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(switch (method) {
                    PaymentMethod.cash => 'Pay the seller when you collect.',
                    PaymentMethod.transfer =>
                      'Pay now and upload your receipt within 30 minutes. '
                          'The item is held for you meanwhile.',
                  }),
                ),
              ),
            ),
        if (!transferAvailable)
          Text(
            'This seller takes cash on pickup only.',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// The payment part of an order or purchase card: where it stands and, when
/// it's this student's turn, the button to act.
class PaymentStrip extends StatelessWidget {
  const PaymentStrip({
    super.key,
    required this.payment,
    required this.iAmBuyer,
    required this.onOpen,
  });

  final PaymentSummary payment;
  final bool iAmBuyer;
  final VoidCallback onOpen;

  static Key payNowKey(String paymentId) => Key('pay-now-$paymentId');
  static Key checkKey(String paymentId) => Key('check-payment-$paymentId');

  @override
  Widget build(BuildContext context) {
    final left = PaymentRules.timeLeft(payment.dueAt, DateTime.now());
    final Widget? button = switch (payment.status) {
      PaymentStatus.awaitingProof when iAmBuyer && left != null =>
        FilledButton.icon(
          key: payNowKey(payment.id),
          onPressed: onOpen,
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: Text('Pay now · $left'),
        ),
      PaymentStatus.submitted when !iAmBuyer => FilledButton.icon(
        key: checkKey(payment.id),
        onPressed: onOpen,
        icon: const Icon(Icons.fact_check_outlined, size: 18),
        label: const Text('Check payment'),
      ),
      _ => null,
    };
    final (IconData icon, String text) = switch (payment.status) {
      PaymentStatus.awaitingProof when iAmBuyer => (
        Icons.timer_outlined,
        left == null
            ? 'The time to pay has run out.'
            : 'Paying by transfer: send proof by '
                  '${formatDayTime(payment.dueAt)}.',
      ),
      PaymentStatus.awaitingProof => (
        Icons.timer_outlined,
        'Waiting for the buyer’s transfer (until '
            '${formatDayTime(payment.dueAt)}).',
      ),
      PaymentStatus.submitted => (
        Icons.receipt_long_outlined,
        iAmBuyer
            ? 'Proof sent. Waiting for the seller to check it.'
            : 'The buyer sent payment proof.',
      ),
      PaymentStatus.accepted => (
        Icons.verified_outlined,
        iAmBuyer
            ? 'The seller confirmed your payment.'
            : 'You confirmed the payment.',
      ),
      PaymentStatus.rejected => (
        Icons.block_rounded,
        'Payment rejected: ${payment.rejectReason ?? ''}',
      ),
      PaymentStatus.expired => (
        Icons.timer_off_outlined,
        'The payment wasn’t completed in time.',
      ),
      PaymentStatus.cancelled => (
        Icons.money_off_rounded,
        'Transfer payment cancelled.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (button != null) ...[const SizedBox(height: 8), button],
        ],
      ),
    );
  }
}
