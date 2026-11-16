import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/domain/business_enums.dart';
import '../../../../core/domain/listing_enums.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../marketplace/domain/listing.dart';
import '../../../marketplace/domain/listing_input.dart';
import '../../../marketplace/presentation/marketplace_providers.dart';
import '../../application/presentation/application_providers.dart';
import '../domain/store_models.dart';
import 'store_providers.dart';

/// Create a pre-order ([campaignId] null) or edit a draft or open one.
class CampaignFormScreen extends ConsumerWidget {
  const CampaignFormScreen({super.key, this.campaignId});

  final String? campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(myListingsProvider);
    final campaigns = ref.watch(myCampaignsProvider);
    final business = ref.watch(myBusinessProvider);

    final Widget body;
    final error = products.error ?? campaigns.error ?? business.error;
    if (error != null) {
      body = ErrorView(
        error: error,
        onRetry: () => ref
          ..invalidate(myListingsProvider)
          ..invalidate(myCampaignsProvider)
          ..invalidate(myBusinessProvider),
      );
    } else if (!products.hasValue ||
        !campaigns.hasValue ||
        !business.hasValue) {
      body = const LoadingView();
    } else {
      final existing = campaigns.value!
          .where((c) => c.id == campaignId)
          .firstOrNull;
      if (campaignId != null && existing == null) {
        body = const EmptyView(
          icon: Icons.search_off_rounded,
          title: 'Pre-order not found',
          message: 'It may have been closed.',
        );
      } else {
        body = _CampaignForm(
          existing: existing,
          products: [
            for (final l in products.value!)
              if (l.isBusiness && l.status != ListingStatus.draft && !l.hidden)
                l,
          ],
          defaultPickup: business.value?.pickupDetails ?? '',
        );
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(campaignId == null ? 'New pre-order' : 'Edit pre-order'),
      ),
      body: body,
    );
  }
}

class _CampaignForm extends ConsumerStatefulWidget {
  const _CampaignForm({
    required this.existing,
    required this.products,
    required this.defaultPickup,
  });

  final Campaign? existing;
  final List<Listing> products;
  final String defaultPickup;

  @override
  ConsumerState<_CampaignForm> createState() => _CampaignFormState();
}

class _CampaignFormState extends ConsumerState<_CampaignForm> {
  final _form = GlobalKey<FormState>();
  late final Campaign? _existing = widget.existing;
  late String? _listingId =
      _existing?.listingId ?? widget.products.firstOrNull?.id;
  late final _title = TextEditingController(text: _existing?.title);
  late final _price = TextEditingController(
    text: _existing == null ? '' : senToInput(_existing.priceSen),
  );
  late final _capacity = TextEditingController(
    text: _existing == null ? '' : '${_existing.capacity}',
  );
  late final _limit = TextEditingController(
    text: _existing?.perOrderLimit?.toString() ?? '',
  );
  late final _pickup = TextEditingController(
    text: _existing?.pickupDetails ?? widget.defaultPickup,
  );
  late DateTime _startAt = _existing?.startAt.toLocal() ?? DateTime.now();
  late DateTime _closeAt =
      _existing?.closeAt.toLocal() ??
      DateTime.now().add(const Duration(days: 7));
  String? _dateError;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _price, _capacity, _limit, _pickup]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _save({required bool open}) async {
    final datesProblem = StoreRules.dates(_startAt, _closeAt, DateTime.now());
    setState(() => _dateError = datesProblem);
    if (!_form.currentState!.validate() || datesProblem != null) return;

    setState(() => _busy = true);
    final limitText = _limit.text.trim();
    final input = CampaignInput(
      listingId: _listingId!,
      title: _title.text,
      priceSen: parseRmToSen(_price.text)!,
      startAt: _startAt,
      closeAt: _closeAt,
      capacity: int.parse(_capacity.text.trim()),
      perOrderLimit: limitText.isEmpty ? null : int.parse(limitText),
      pickupDetails: _pickup.text,
    );
    final actions = ref.read(storeActionsProvider);
    try {
      final id = await actions.saveCampaign(input, campaignId: _existing?.id);
      if (open) {
        await actions.setCampaignStatus(id, CampaignStatus.open);
      }
      if (!mounted) return;
      showMessage(
        context,
        open
            ? 'Pre-order is open. Buyers see it on your storefront.'
            : _existing == null
            ? 'Saved as a draft. Open it when you’re ready.'
            : 'Changes saved.',
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
    final existing = _existing;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (existing == null && widget.products.isEmpty) {
      return const EmptyView(
        icon: Icons.inventory_2_outlined,
        title: 'Publish a product first',
        message: 'A pre-order is for one of your published products.',
      );
    }

    return Form(
      key: _form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label('Product'),
            if (existing != null)
              Text(existing.listingTitle ?? 'Product')
            else
              DropdownButtonFormField<String>(
                key: const Key('campaign-product'),
                initialValue: _listingId,
                items: [
                  for (final p in widget.products)
                    DropdownMenuItem(value: p.id, child: Text(p.title)),
                ],
                onChanged: (id) => setState(() => _listingId = id),
                validator: (id) => id == null ? 'Choose a product.' : null,
              ),
            label('Title'),
            TextFormField(
              key: const Key('campaign-title'),
              controller: _title,
              maxLength: 80,
              validator: StoreRules.title,
              decoration: const InputDecoration(
                hintText: 'e.g. Raya brownie pre-order',
                counterText: '',
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Price (RM)'),
                      TextFormField(
                        key: const Key('campaign-price'),
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: ListingRules.price,
                        decoration: const InputDecoration(prefixText: 'RM '),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Capacity'),
                      TextFormField(
                        key: const Key('campaign-capacity'),
                        controller: _capacity,
                        keyboardType: TextInputType.number,
                        validator: StoreRules.capacity,
                        decoration: const InputDecoration(hintText: 'e.g. 30'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (existing != null && existing.allocatedQty > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${existing.allocatedQty} already ordered; the capacity '
                  'can’t go below that.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            label('Per-order limit (optional)'),
            TextFormField(
              key: const Key('campaign-limit'),
              controller: _limit,
              keyboardType: TextInputType.number,
              validator: (v) => StoreRules.perOrderLimit(
                v,
                int.tryParse(_capacity.text.trim()),
              ),
              decoration: const InputDecoration(hintText: 'No limit'),
            ),
            label('Dates'),
            _DateRow(
              label: 'Opens',
              value: _startAt,
              onTap: _busy
                  ? null
                  : () async {
                      final picked = await _pickDateTime(_startAt);
                      if (picked != null) setState(() => _startAt = picked);
                    },
            ),
            _DateRow(
              label: 'Closes',
              value: _closeAt,
              onTap: _busy
                  ? null
                  : () async {
                      final picked = await _pickDateTime(_closeAt);
                      if (picked != null) setState(() => _closeAt = picked);
                    },
            ),
            if (_dateError case final error?)
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            label('Collection'),
            TextFormField(
              key: const Key('campaign-pickup'),
              controller: _pickup,
              maxLength: 200,
              validator: StoreRules.pickupDetails,
              decoration: const InputDecoration(
                hintText: 'e.g. Tekun lobby, Sat 10am',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 20),
            if (existing == null) ...[
              FilledButton(
                key: const Key('campaign-save-open'),
                onPressed: _busy ? null : () => _save(open: true),
                child: const Text('Save and open'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('campaign-save-draft'),
                onPressed: _busy ? null : () => _save(open: false),
                child: const Text('Save as draft'),
              ),
            ] else
              FilledButton(
                key: const Key('campaign-save'),
                onPressed: _busy ? null : () => _save(open: false),
                child: const Text('Save changes'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value, this.onTap});

  final String label;
  final DateTime value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.event_outlined),
    title: Text(label),
    subtitle: Text(formatDayTime(value)),
    trailing: const Icon(Icons.edit_calendar_outlined),
    onTap: onTap,
  );
}
