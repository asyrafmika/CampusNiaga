import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../marketplace/data/photo_picker.dart';
import '../../../marketplace/domain/listing_input.dart';
import '../../application/domain/business_application.dart';
import '../../application/presentation/application_providers.dart';
import '../domain/store_models.dart';
import 'store_providers.dart';
import 'widgets/store_widgets.dart';

/// Edit the storefront: description, pickup details and logo. The name
/// stays the one the reviewer approved.
class StorefrontEditScreen extends ConsumerWidget {
  const StorefrontEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(myBusinessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit storefront')),
      body: switch (business) {
        AsyncData(value: final b?) => _StorefrontForm(business: b),
        AsyncData() => const EmptyView(
          icon: Icons.storefront_outlined,
          title: 'No business yet',
          message: 'Your storefront opens once your business is approved.',
        ),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(myBusinessProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _StorefrontForm extends ConsumerStatefulWidget {
  const _StorefrontForm({required this.business});

  final MyBusiness business;

  @override
  ConsumerState<_StorefrontForm> createState() => _StorefrontFormState();
}

class _StorefrontFormState extends ConsumerState<_StorefrontForm> {
  final _form = GlobalKey<FormState>();
  late final _description = TextEditingController(
    text: widget.business.description,
  );
  late final _pickup = TextEditingController(
    text: widget.business.pickupDetails,
  );
  late String? _logoPath = widget.business.logoPath;
  NewPhoto? _newLogo;
  bool _busy = false;

  @override
  void dispose() {
    _description.dispose();
    _pickup.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final photo = await ref
          .read(photoPickerProvider)
          .pick(PhotoSource.gallery);
      if (photo != null && mounted) setState(() => _newLogo = photo);
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(storeActionsProvider)
          .updateStorefront(
            businessId: widget.business.id,
            description: _description.text,
            pickupDetails: _pickup.text,
            logoPath: _logoPath,
            newLogo: _newLogo,
          );
      if (!mounted) return;
      showMessage(context, 'Storefront saved.');
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
    final newLogo = _newLogo;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              if (newLogo != null)
                ClipOval(
                  child: Image.memory(
                    newLogo.bytes,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                )
              else
                BusinessLogo(
                  name: widget.business.name,
                  path: _logoPath,
                  size: 72,
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.business.name,
                      style: theme.textTheme.titleLarge,
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : _pickLogo,
                          child: Text(
                            newLogo == null && _logoPath == null
                                ? 'Add logo'
                                : 'Change logo',
                          ),
                        ),
                        if (newLogo != null || _logoPath != null)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _newLogo = null;
                                    _logoPath = null;
                                  }),
                            child: const Text('Remove'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('About the business', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('storefront-description'),
            controller: _description,
            maxLines: 5,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            validator: StoreRules.description,
            decoration: const InputDecoration(
              hintText: 'What you sell, when you bake or restock',
            ),
          ),
          const SizedBox(height: 12),
          Text('Pickup details', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('storefront-pickup'),
            controller: _pickup,
            maxLength: 200,
            validator: StoreRules.pickupDetails,
            decoration: const InputDecoration(
              hintText: 'e.g. Desasiswa Tekun lobby, weekdays 6-8pm',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('storefront-save'),
            onPressed: _busy ? null : _save,
            child: const Text('Save storefront'),
          ),
        ],
      ),
    );
  }
}
