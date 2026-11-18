import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/domain/payment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../marketplace/data/photo_picker.dart';
import '../../marketplace/domain/listing_input.dart';
import '../data/payment_repository.dart';
import '../domain/payment_models.dart';
import 'payment_providers.dart';
import 'widgets/payment_widgets.dart';

/// One transfer payment. The buyer sees where to pay and sends proof; the
/// seller sees the proof and accepts or rejects it.
class PaymentScreen extends ConsumerWidget {
  const PaymentScreen({super.key, required this.paymentId});

  final String paymentId;

  static const Key chooseProofKey = Key('payment-choose-proof');
  static const Key sendProofKey = Key('payment-send-proof');
  static const Key acceptKey = Key('payment-accept');
  static const Key rejectKey = Key('payment-reject');
  static const Key rejectReasonKey = Key('payment-reject-reason');
  static const Key rejectConfirmKey = Key('payment-reject-confirm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = ref.watch(paymentProvider(paymentId));
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: switch (payment) {
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(paymentProvider(paymentId).future),
          child: _PaymentBody(payment: value),
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(paymentProvider(paymentId)),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _PaymentBody extends StatelessWidget {
  const _PaymentBody({required this.payment});

  final PaymentView payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${payment.qty} × ${payment.itemTitle}',
                style: const TextStyle(color: Color(0xD9FFFFFF)),
              ),
              const SizedBox(height: 4),
              Text(
                formatRm(payment.amountSen),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                payment.iAmBuyer
                    ? 'To ${payment.sellerName}'
                    : 'From your buyer',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _StatusBanner(payment: payment),
        const SizedBox(height: 16),
        if (payment.iAmBuyer)
          _BuyerPart(payment: payment)
        else
          _SellerPart(payment: payment),
        const SizedBox(height: 20),
        Text(
          'CampusNiaga doesn’t handle money or check receipts: the seller '
          'confirms the payment from their own bank. Pay only to the details '
          'shown here and keep your receipt.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.payment});

  final PaymentView payment;

  @override
  Widget build(BuildContext context) {
    final buyer = payment.iAmBuyer;
    final left = PaymentRules.timeLeft(payment.dueAt, DateTime.now());
    final String text = switch (payment.status) {
      PaymentStatus.awaitingProof when left == null =>
        'The 30 minutes to pay have run out.',
      PaymentStatus.awaitingProof =>
        buyer
            ? 'Pay and send your proof by ${formatDayTime(payment.dueAt)} '
                  '($left). The item is held for you until then.'
            : 'Waiting for the buyer’s transfer, until '
                  '${formatDayTime(payment.dueAt)}.',
      PaymentStatus.submitted =>
        buyer
            ? 'Proof sent. The seller will check their bank and confirm.'
            : 'Check your bank app for ${formatRm(payment.amountSen)} before '
                  'accepting.',
      PaymentStatus.accepted =>
        buyer
            ? 'The seller confirmed your payment.'
            : 'You confirmed this payment.',
      PaymentStatus.rejected =>
        'The payment was rejected: ${payment.rejectReason ?? ''}',
      PaymentStatus.expired =>
        'The payment wasn’t completed in time, so the item went back on sale.',
      PaymentStatus.cancelled => 'This payment was cancelled.',
    };
    final good = payment.status == PaymentStatus.accepted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: good ? const Color(0xFFE6F4EA) : const Color(0xFFFDF5E7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            good ? Icons.verified_outlined : Icons.info_outline_rounded,
            size: 20,
            color: good ? const Color(0xFF1E7B34) : const Color(0xFF9A5B00),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ],
      ),
    );
  }
}

/// Where to pay, then the proof.
class _BuyerPart extends ConsumerStatefulWidget {
  const _BuyerPart({required this.payment});

  final PaymentView payment;

  @override
  ConsumerState<_BuyerPart> createState() => _BuyerPartState();
}

class _BuyerPartState extends ConsumerState<_BuyerPart> {
  NewPhoto? _proof;
  bool _busy = false;

  Future<void> _choose() async {
    try {
      final photo = await ref
          .read(photoPickerProvider)
          .pick(PhotoSource.gallery);
      if (photo != null && mounted) setState(() => _proof = photo);
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    }
  }

  Future<void> _send() async {
    final proof = _proof;
    if (proof == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(paymentActionsProvider)
          .submitProof(widget.payment.id, proof);
      if (mounted) showMessage(context, 'Proof sent to the seller.');
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payment = widget.payment;
    final payTo = payment.payTo;
    final open =
        payment.status == PaymentStatus.awaitingProof &&
        PaymentRules.timeLeft(payment.dueAt, DateTime.now()) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (payTo != null && payment.status.isOpen) ...[
          Text('Pay to', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (payTo.qrPath case final qr?)
            Container(
              height: 260,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: PaymentImage(bucket: PaymentRepository.qrBucket, path: qr),
            ),
          if (payTo.hasBank) ...[
            const SizedBox(height: 10),
            _CopyRow(label: 'Bank', value: payTo.bankName ?? ''),
            _CopyRow(label: 'Account name', value: payTo.accountName ?? ''),
            _CopyRow(
              label: 'Account number',
              value: payTo.accountNumber ?? '',
              copyable: true,
            ),
          ],
          _CopyRow(
            label: 'Amount',
            value: senToInput(payment.amountSen),
            display: formatRm(payment.amountSen),
            copyable: true,
          ),
        ],
        if (open) ...[
          const SizedBox(height: 20),
          Text('Your proof of payment', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A screenshot of the successful transfer, showing the amount and '
            'the time.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (_proof case final proof?)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(proof.bytes, height: 220, fit: BoxFit.cover),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: PaymentScreen.chooseProofKey,
            onPressed: _busy ? null : _choose,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _proof == null ? 'Choose screenshot' : 'Choose another',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: PaymentScreen.sendProofKey,
            onPressed: _busy || _proof == null ? null : _send,
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('Send proof'),
          ),
        ],
        if (payment.proofPath case final proof? when !open) ...[
          const SizedBox(height: 20),
          Text('Proof you sent', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _ProofImage(path: proof),
        ],
      ],
    );
  }
}

/// The proof, then accept or reject.
class _SellerPart extends ConsumerStatefulWidget {
  const _SellerPart({required this.payment});

  final PaymentView payment;

  @override
  ConsumerState<_SellerPart> createState() => _SellerPartState();
}

class _SellerPartState extends ConsumerState<_SellerPart> {
  bool _busy = false;

  Future<void> _accept() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept this payment?'),
        content: Text(
          'Only accept once ${formatRm(widget.payment.amountSen)} is in your '
          'account. The buyer’s ${widget.payment.orderId != null ? 'order is confirmed' : 'booking is accepted'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _review(accept: true);
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectDialog(),
    );
    if (reason == null) return;
    await _review(accept: false, reason: reason);
  }

  Future<void> _review({required bool accept, String? reason}) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(paymentActionsProvider)
          .review(widget.payment.id, accept: accept, reason: reason);
      if (mounted) {
        showMessage(
          context,
          accept
              ? 'Payment accepted.'
              : 'Payment rejected. The item is back on sale.',
        );
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payment = widget.payment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (payment.proofPath case final proof?) ...[
          Text('The buyer’s proof', style: theme.textTheme.titleMedium),
          if (payment.submittedAt case final at?)
            Text('Sent ${formatDayTime(at)}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          _ProofImage(path: proof),
        ],
        if (payment.status == PaymentStatus.submitted) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: PaymentScreen.rejectKey,
                  onPressed: _busy ? null : _reject,
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: PaymentScreen.acceptKey,
                  onPressed: _busy ? null : _accept,
                  child: const Text('Accept payment'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProofImage extends StatelessWidget {
  const _ProofImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Container(
    height: 360,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InteractiveViewer(
      child: PaymentImage(bucket: PaymentRepository.proofBucket, path: path),
    ),
  );
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    this.display,
    this.copyable = false,
  });

  final String label;
  final String value;
  final String? display;
  final bool copyable;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: SelectableText(
            display ?? value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (copyable)
          IconButton(
            tooltip: 'Copy ${label.toLowerCase()}',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) showMessage(context, '$label copied.');
            },
          ),
      ],
    ),
  );
}

/// Asks why the payment is rejected. Owns its controller, so it lives as
/// long as the dialog.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reject this payment?'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The buyer is told why, and the item goes back on sale. If money '
            'did arrive, refund it yourself.',
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: PaymentScreen.rejectReasonKey,
            controller: _reason,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(
              hintText: 'e.g. Nothing arrived in my account',
            ),
            validator: PaymentRules.rejectReason,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: PaymentScreen.rejectConfirmKey,
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: const Text('Reject'),
      ),
    ],
  );
}
