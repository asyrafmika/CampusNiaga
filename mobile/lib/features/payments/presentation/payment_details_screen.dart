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

/// Where buyers who pay by transfer send money: a bank account, a QR code,
/// or both. One set for the student; a business may have its own.
class PaymentDetailsScreen extends ConsumerWidget {
  const PaymentDetailsScreen({super.key, this.forBusiness = false});

  final bool forBusiness;

  static const Key bankKey = Key('pay-details-bank');
  static const Key nameKey = Key('pay-details-name');
  static const Key numberKey = Key('pay-details-number');
  static const Key qrKey = Key('pay-details-qr');
  static const Key removeQrKey = Key('pay-details-remove-qr');
  static const Key saveKey = Key('pay-details-save');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(myPaymentDetailsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          forBusiness ? 'Business payment details' : 'Payment details',
        ),
      ),
      body: switch (saved) {
        AsyncData(:final value) => _DetailsForm(
          forBusiness: forBusiness,
          initial: forBusiness ? value.business : value.personal,
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

class _DetailsForm extends ConsumerStatefulWidget {
  const _DetailsForm({required this.forBusiness, this.initial});

  final bool forBusiness;
  final PaymentDetails? initial;

  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
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

  Future<void> _save() async {
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
    final removing =
        _number.text.trim().isEmpty && _qrPath == null && _newQr == null;
    setState(() => _busy = true);
    try {
      await ref
          .read(paymentActionsProvider)
          .saveDetails(
            forBusiness: widget.forBusiness,
            bankName: _bank.text,
            accountName: _name.text,
            accountNumber: PaymentRules.normaliseAccountNumber(
              _number.text.trim(),
            ),
            keptQrPath: _newQr == null ? _qrPath : null,
            newQr: _newQr,
            previousQrPath: widget.initial?.qrPath,
          );
      if (!mounted) return;
      showMessage(
        context,
        removing ? 'Payment details removed.' : 'Payment details saved.',
      );
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showMessage(context, AppFailure.messageOf(e));
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
          Text(
            widget.forBusiness
                ? 'Used for your business’s orders. Without them, buyers pay '
                      'to your personal details.'
                : 'Buyers can then choose to pay you by bank transfer or QR. '
                      'Without details, they pay cash on pickup.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Bank account', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            key: PaymentDetailsScreen.bankKey,
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
            key: PaymentDetailsScreen.nameKey,
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Account holder’s name',
            ),
            validator: PaymentRules.accountName,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: PaymentDetailsScreen.numberKey,
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
                key: PaymentDetailsScreen.qrKey,
                onPressed: _busy ? null : _pickQr,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: Text(hasQr ? 'Change QR code' : 'Add QR code'),
              ),
              if (hasQr)
                TextButton.icon(
                  key: PaymentDetailsScreen.removeQrKey,
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
              'doesn’t handle money. Clear everything and save to remove them.',
              style: TextStyle(height: 1.35),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: PaymentDetailsScreen.saveKey,
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
