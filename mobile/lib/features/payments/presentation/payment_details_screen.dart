import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../../marketplace/data/photo_picker.dart';
import '../../marketplace/domain/listing_input.dart';
import '../data/payment_repository.dart';
import '../domain/payment_models.dart';
import 'payment_providers.dart';
import 'widgets/payment_widgets.dart';

/// A business's own payment details, from My store (ADR 0008). A student's
/// personal details are entered on the listing's payment step instead.
class PaymentDetailsScreen extends ConsumerWidget {
  const PaymentDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(myPaymentDetailsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Business payment details')),
      body: switch (saved) {
        AsyncData(:final value) => PaymentDetailsForm(
          forBusiness: true,
          initial: value.business,
          intro:
              'Used for your business’s orders. Without them, buyers pay '
              'to your personal details.',
          submitLabel: 'Save',
          onDone: (outcome) async {
            showMessage(
              context,
              outcome == DetailsOutcome.removed
                  ? 'Payment details removed.'
                  : 'Payment details saved.',
            );
            context.pop();
          },
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

/// What saving the form did.
enum DetailsOutcome { saved, removed, unchanged }

/// Bank account and/or QR code, saved through `set_payment_details`. The
/// caller says what happens next ([onDone]); a failure is shown here.
class PaymentDetailsForm extends ConsumerStatefulWidget {
  const PaymentDetailsForm({
    super.key,
    required this.forBusiness,
    required this.initial,
    required this.intro,
    required this.submitLabel,
    required this.onDone,
    this.secondary,
  });

  final bool forBusiness;
  final PaymentDetails? initial;
  final String intro;
  final String submitLabel;

  /// Runs after the details are saved (or left as they were); its failures
  /// are shown too.
  final Future<void> Function(DetailsOutcome outcome) onDone;

  /// Another way out, under the main button.
  final Widget? secondary;

  static const Key bankKey = Key('pay-details-bank');
  static const Key nameKey = Key('pay-details-name');
  static const Key numberKey = Key('pay-details-number');
  static const Key qrKey = Key('pay-details-qr');
  static const Key removeQrKey = Key('pay-details-remove-qr');
  static const Key saveKey = Key('pay-details-save');

  @override
  ConsumerState<PaymentDetailsForm> createState() => _PaymentDetailsFormState();
}

class _PaymentDetailsFormState extends ConsumerState<PaymentDetailsForm> {
  final _form = GlobalKey<FormState>();
  late final _bank = TextEditingController(text: widget.initial?.bankName);
  late final _name = TextEditingController(text: widget.initial?.accountName);
  late final _number = TextEditingController(
    text: widget.initial?.accountNumber,
  );
  late String? _qrPath = widget.initial?.qrPath;
  NewPhoto? _newQr;
  bool _busy = false;

  @override
  void dispose() {
    _bank.dispose();
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _pickQr() async {
    try {
      final photo = await ref
          .read(photoPickerProvider)
          .pick(PhotoSource.gallery);
      if (photo != null && mounted) setState(() => _newQr = photo);
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    }
  }

  String _trimmed(TextEditingController c) => c.text.trim();

  bool get _unchanged {
    final before = widget.initial;
    return _newQr == null &&
        _qrPath == before?.qrPath &&
        _trimmed(_bank) == (before?.bankName ?? '') &&
        _trimmed(_name) == (before?.accountName ?? '') &&
        PaymentRules.normaliseAccountNumber(_trimmed(_number)) ==
            (before?.accountNumber ?? '');
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final problem = PaymentRules.together(
      bankName: _bank.text,
      accountName: _name.text,
      accountNumber: _number.text,
    );
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _busy = true);
    try {
      var outcome = DetailsOutcome.unchanged;
      if (!_unchanged) {
        await ref
            .read(paymentActionsProvider)
            .saveDetails(
              forBusiness: widget.forBusiness,
              bankName: _bank.text,
              accountName: _name.text,
              accountNumber: PaymentRules.normaliseAccountNumber(
                _trimmed(_number),
              ),
              keptQrPath: _newQr == null ? _qrPath : null,
              newQr: _newQr,
              previousQrPath: widget.initial?.qrPath,
            );
        outcome = _trimmed(_number).isEmpty && _qrPath == null && _newQr == null
            ? DetailsOutcome.removed
            : DetailsOutcome.saved;
      }
      await widget.onDone(outcome);
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasQr = _newQr != null || _qrPath != null;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(widget.intro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Text('Bank account', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            key: PaymentDetailsForm.bankKey,
            controller: _bank,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Bank',
              hintText: 'e.g. Maybank',
            ),
            validator: PaymentRules.bankName,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: PaymentDetailsForm.nameKey,
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Account holder’s name',
            ),
            validator: PaymentRules.accountName,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: PaymentDetailsForm.numberKey,
            controller: _number,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Account number'),
            validator: PaymentRules.accountNumber,
          ),
          const SizedBox(height: 20),
          Text(
            'QR code (DuitNow or bank QR)',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (hasQr)
            Container(
              height: 220,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: switch (_newQr) {
                final NewPhoto photo => Image.memory(photo.bytes),
                null => PaymentImage(
                  bucket: PaymentRepository.qrBucket,
                  path: _qrPath!,
                ),
              },
            ),
          Wrap(
            children: [
              TextButton.icon(
                key: PaymentDetailsForm.qrKey,
                onPressed: _busy ? null : _pickQr,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: Text(hasQr ? 'Change QR code' : 'Add QR code'),
              ),
              if (hasQr)
                TextButton.icon(
                  key: PaymentDetailsForm.removeQrKey,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _newQr = null;
                          _qrPath = null;
                        }),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF5E7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Only a buyer with an open transfer payment to you sees these. '
              'Check your own bank before accepting any payment: CampusNiaga '
              'doesn’t handle money. Leave everything empty to take cash '
              'only.',
              style: TextStyle(height: 1.35),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: PaymentDetailsForm.saveKey,
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.submitLabel),
          ),
          if (widget.secondary case final secondary?) ...[
            const SizedBox(height: 8),
            secondary,
          ],
        ],
      ),
    );
  }
}
