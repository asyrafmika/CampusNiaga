import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/domain/geo_point.dart';
import '../../../core/domain/listing_enums.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/pickup_map.dart';
import '../../../core/widgets/state_views.dart';
import '../data/photo_picker.dart';
import '../domain/listing.dart';
import '../domain/listing_input.dart';
import 'marketplace_providers.dart';
import 'widgets/listing_widgets.dart';

/// Create a listing ([listingId] null) or edit one of the user's own.
/// [business] creates a business product (approved businesses only; the
/// database checks).
class ListingFormScreen extends ConsumerWidget {
  const ListingFormScreen({super.key, this.listingId, this.business = false});

  final String? listingId;
  final bool business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = listingId;
    final categories = ref.watch(categoriesProvider);
    final existing = id == null ? null : ref.watch(listingDetailProvider(id));
    final title = id != null
        ? 'Edit listing'
        : business
        ? 'Add a product'
        : 'Sell an item';

    Widget body;
    if (categories case AsyncError(:final error)) {
      body = ErrorView(
        error: error,
        onRetry: () => ref.invalidate(categoriesProvider),
      );
    } else if (existing case AsyncError(:final error)) {
      body = ErrorView(
        error: error,
        onRetry: () => ref.invalidate(listingDetailProvider(id!)),
      );
    } else if (categories.value == null ||
        (existing != null && existing.value == null)) {
      body = const LoadingView();
    } else {
      body = _ListingForm(
        categories: categories.value!,
        existing: existing?.value,
        business: business,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}

/// A photo in the form: already uploaded ([path]) or just picked ([photo]).
class _FormPhoto {
  const _FormPhoto.saved(String this.path) : photo = null;
  const _FormPhoto.picked(NewPhoto this.photo) : path = null;

  final String? path;
  final NewPhoto? photo;
}

class _ListingForm extends ConsumerStatefulWidget {
  const _ListingForm({
    required this.categories,
    this.existing,
    this.business = false,
  });

  final List<String> categories;
  final Listing? existing;
  final bool business;

  @override
  ConsumerState<_ListingForm> createState() => _ListingFormState();
}

class _ListingFormState extends ConsumerState<_ListingForm> {
  final _form = GlobalKey<FormState>();
  late final Listing? _existing = widget.existing;
  late final _title = TextEditingController(text: _existing?.title);
  late final _description = TextEditingController(text: _existing?.description);
  late final _price = TextEditingController(
    text: _existing == null ? '' : senToInput(_existing.priceSen),
  );
  late final _quantity = TextEditingController(
    text: '${_existing?.stock ?? 1}',
  );
  late final _pickup = TextEditingController(text: _existing?.pickupArea);
  late GeoPoint? _pin = _existing?.pickupPin;
  late String? _category = _existing?.category;
  late ListingCondition _condition =
      _existing?.condition ?? ListingCondition.good;
  late final List<_FormPhoto> _photos = [
    for (final p in _existing?.photoPaths ?? const <String>[])
      _FormPhoto.saved(p),
  ];
  bool _busy = false;
  String? _photoError;

  bool get _isDraftOrNew =>
      _existing == null || _existing.status == ListingStatus.draft;

  /// A personal listing goes on to its payment step; a business product
  /// uses the business's payment details (ADR 0008).
  bool get _hasPaymentStep => !widget.business;

  @override
  void dispose() {
    for (final c in [_title, _description, _price, _quantity, _pickup]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final photo = await ref.read(photoPickerProvider).pick(source);
      if (photo != null && mounted) {
        setState(() {
          _photos.add(_FormPhoto.picked(photo));
          _photoError = null;
        });
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    }
  }

  /// [publish]: for a personal listing, go on to the payment step, which
  /// publishes it.
  Future<void> _save({required bool publish}) async {
    final valid = _form.currentState!.validate();
    final photoProblem = publish
        ? ListingRules.publishProblem(_photos.length)
        : null;
    setState(() => _photoError = photoProblem);
    if (!valid || photoProblem != null) return;

    setState(() => _busy = true);
    final existing = _existing;
    try {
      final id = await ref
          .read(marketplaceActionsProvider)
          .saveListing(
            listingId: existing?.id,
            previousPhotos: existing?.photoPaths ?? const [],
            input: ListingInput(
              title: _title.text,
              description: _description.text,
              category: _category!,
              priceSen: parseRmToSen(_price.text)!,
              condition: _condition,
              quantity: int.parse(_quantity.text.trim()),
              pickupArea: _pickup.text,
              pickupPin: _pin,
            ),
            keptPhotos: [for (final p in _photos) ?p.path],
            newPhotos: [for (final p in _photos) ?p.photo],
            publish: publish && _isDraftOrNew && !_hasPaymentStep,
            mode: widget.business ? ListingMode.business : ListingMode.personal,
          );
      if (!mounted) return;
      // Next: payment (publishing a draft, or editing a published listing).
      // The form is done, so Back from the step returns to where it began.
      if (_hasPaymentStep && (publish || !_isDraftOrNew)) {
        context.pushReplacement(
          AppRoutes.listingPayment(id, publish: publish && _isDraftOrNew),
        );
        return;
      }
      showMessage(
        context,
        publish && _isDraftOrNew
            ? 'Published! Your item is now in the marketplace.'
            : existing == null
            ? 'Saved as a draft. Publish it when you’re ready.'
            : 'Changes saved.',
      );
      if (existing == null) {
        context.pushReplacement(AppRoutes.listing(id));
      } else {
        context.pop();
      }
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
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Form(
      key: _form,
      // A plain scroll view, not a lazy list: every field must exist so the
      // form validates all of them.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label('Photos (up to ${ListingRules.maxPhotos})'),
            _PhotoStrip(
              photos: _photos,
              onAdd: _photos.length < ListingRules.maxPhotos && !_busy
                  ? _addPhoto
                  : null,
              onRemove: (i) => setState(() => _photos.removeAt(i)),
            ),
            if (_photoError case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            label('Title'),
            TextFormField(
              key: const Key('form-title'),
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              validator: ListingRules.title,
              decoration: const InputDecoration(
                hintText: 'e.g. Casio FX-570 calculator',
                counterText: '',
              ),
            ),
            label('Description'),
            TextFormField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              maxLength: 1000,
              validator: ListingRules.description,
              decoration: const InputDecoration(
                hintText:
                    'Condition details, what’s included, why you’re selling',
              ),
            ),
            label('Category'),
            DropdownButtonFormField<String>(
              key: const Key('form-category'),
              initialValue: _category,
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        Icon(
                          categoryIcon(c),
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Text(c),
                      ],
                    ),
                  ),
              ],
              onChanged: (c) => setState(() => _category = c),
              validator: (c) => c == null ? 'Choose a category.' : null,
              decoration: const InputDecoration(hintText: 'Choose one'),
            ),
            label('Condition'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in ListingCondition.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _condition == c,
                    onSelected: (_) => setState(() => _condition = c),
                  ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label('Price (RM)'),
                      TextFormField(
                        key: const Key('form-price'),
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: ListingRules.price,
                        decoration: const InputDecoration(
                          hintText: '25.00',
                          prefixText: 'RM ',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      label(_isDraftOrNew ? 'Quantity' : 'Available'),
                      TextFormField(
                        key: const Key('form-quantity'),
                        controller: _quantity,
                        keyboardType: TextInputType.number,
                        validator: ListingRules.quantity,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            label('Pickup location'),
            TextFormField(
              key: const Key('form-pickup'),
              controller: _pickup,
              maxLength: 80,
              validator: ListingRules.pickupArea,
              decoration: const InputDecoration(
                hintText: 'e.g. Desasiswa Tekun lobby',
                prefixIcon: Icon(Icons.place_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            PickupPinField(
              value: _pin,
              enabled: !_busy,
              onChanged: (pin) => setState(() => _pin = pin),
            ),
            const SizedBox(height: 28),
            if (_isDraftOrNew) ...[
              FilledButton(
                key: const Key('form-publish'),
                onPressed: _busy ? null : () => _save(publish: true),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(_hasPaymentStep ? 'Next: payment' : 'Publish'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('form-draft'),
                onPressed: _busy ? null : () => _save(publish: false),
                child: const Text('Save draft'),
              ),
            ] else
              FilledButton(
                key: const Key('form-save'),
                onPressed: _busy ? null : () => _save(publish: false),
                child: Text(_hasPaymentStep ? 'Next: payment' : 'Save changes'),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_FormPhoto> photos;
  final VoidCallback? onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (var i = 0; i < photos.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox.square(
                    dimension: 96,
                    child: switch (photos[i]) {
                      _FormPhoto(:final photo?) => Image.memory(
                        photo.bytes,
                        fit: BoxFit.cover,
                      ),
                      _FormPhoto(:final path) => ListingPhoto(path: path),
                    },
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: InkWell(
                    onTap: () => onRemove(i),
                    customBorder: const CircleBorder(),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xB3000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (i == 0)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Cover',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (onAdd != null)
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 96,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
                  SizedBox(height: 4),
                  Text(
                    'Add photo',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
