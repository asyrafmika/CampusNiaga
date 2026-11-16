import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../../marketplace/presentation/marketplace_providers.dart';
import '../domain/discovery_models.dart';
import 'discovery_providers.dart';

/// Request a product nobody sells yet.
class RequestFormScreen extends ConsumerWidget {
  const RequestFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Request a product')),
      body: switch (categories) {
        AsyncData(:final value) => _RequestForm(categories: value),
        AsyncError(:final error) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm({required this.categories});

  final List<String> categories;

  @override
  ConsumerState<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<_RequestForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _area = TextEditingController();
  final _notes = TextEditingController();
  String? _category;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _area, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _priceRule(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final sen = parseRmToSen(text);
    if (sen == null) return 'Enter a price, e.g. 5 or 4.50, or leave it empty.';
    if (sen > 10000000) return 'The maximum is RM 100,000.';
    return null;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final priceText = _price.text.trim();
    try {
      await ref
          .read(discoveryActionsProvider)
          .createRequest(
            RequestInput(
              name: _name.text,
              category: _category!,
              campusArea: _area.text,
              preferredPriceSen: priceText.isEmpty
                  ? null
                  : parseRmToSen(priceText),
              notes: _notes.text,
            ),
          );
      if (!mounted) return;
      showMessage(
        context,
        'Requested! Students can tap Interested, and sellers see the demand.',
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
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Form(
      key: _form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Can’t find something on campus? Ask for it. Students with the '
              'same need tap Interested, and sellers see the demand.',
              style: theme.textTheme.bodyMedium,
            ),
            label('What do you want?'),
            TextFormField(
              key: const Key('request-name'),
              controller: _name,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              validator: RequestRules.name,
              decoration: const InputDecoration(
                hintText: 'e.g. Chocolate brownie',
                counterText: '',
              ),
            ),
            label('Category'),
            DropdownButtonFormField<String>(
              key: const Key('request-category'),
              initialValue: _category,
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (c) => setState(() => _category = c),
              validator: (c) => c == null ? 'Choose a category.' : null,
              decoration: const InputDecoration(hintText: 'Choose one'),
            ),
            label('Price you’d pay (optional)'),
            TextFormField(
              key: const Key('request-price'),
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _priceRule,
              decoration: const InputDecoration(
                hintText: 'e.g. 5',
                prefixText: 'RM ',
              ),
            ),
            label('Where on campus'),
            TextFormField(
              key: const Key('request-area'),
              controller: _area,
              maxLength: 80,
              validator: RequestRules.campusArea,
              decoration: const InputDecoration(
                hintText: 'e.g. Desasiswa Tekun',
                prefixIcon: Icon(Icons.place_outlined),
                counterText: '',
              ),
            ),
            label('Notes (optional)'),
            TextFormField(
              key: const Key('request-notes'),
              controller: _notes,
              maxLines: 3,
              maxLength: 300,
              validator: RequestRules.notes,
              decoration: const InputDecoration(
                hintText: 'Size, flavour, when you need it',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('request-submit'),
              onPressed: _busy ? null : _submit,
              child: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
  }
}
