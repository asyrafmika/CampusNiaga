import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/domain/business_enums.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../marketplace/presentation/marketplace_providers.dart';
import '../domain/business_application.dart';
import 'application_providers.dart';
import 'widgets/application_widgets.dart';

/// Apply: the business details. Continues a draft or answers a request for
/// changes; otherwise starts a new application.
class ApplicationFormScreen extends ConsumerWidget {
  const ApplicationFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(myApplicationProvider);
    final categories = ref.watch(categoriesProvider);

    final Widget body;
    if (application case AsyncError(:final error)) {
      body = ErrorView(
        error: error,
        onRetry: () => ref.invalidate(myApplicationProvider),
      );
    } else if (categories case AsyncError(:final error)) {
      body = ErrorView(
        error: error,
        onRetry: () => ref.invalidate(categoriesProvider),
      );
    } else if (!application.hasValue || !categories.hasValue) {
      body = const LoadingView();
    } else {
      final current = application.value;
      if (current != null &&
          !current.canEdit &&
          current.status != ApplicationStatus.rejected) {
        body = const EmptyView(
          icon: Icons.lock_clock_outlined,
          title: 'Your application is with the HDC administrator',
          message: 'You can change it if the administrator asks for changes.',
        );
      } else {
        body = _ApplicationForm(
          // A rejected application stays as it was; the form starts afresh.
          existing: current?.canEdit ?? false ? current : null,
          categories: categories.value!,
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Apply for a business')),
      body: body,
    );
  }
}

class _ApplicationForm extends ConsumerStatefulWidget {
  const _ApplicationForm({required this.existing, required this.categories});

  final BusinessApplication? existing;
  final List<String> categories;

  @override
  ConsumerState<_ApplicationForm> createState() => _ApplicationFormState();
}

class _ApplicationFormState extends ConsumerState<_ApplicationForm> {
  static const Key nameKey = Key('application-name');
  static const Key descriptionKey = Key('application-description');
  static const Key contactKey = Key('application-contact');
  static const Key collectionKey = Key('application-collection');

  final _form = GlobalKey<FormState>();
  late final ApplicationContent _initial =
      widget.existing?.content ?? ApplicationContent.empty;
  late final _name = TextEditingController(text: _initial.businessName);
  late final _description = TextEditingController(text: _initial.description);
  late final _contact = TextEditingController(text: _initial.contactDetails);
  late final _collection = TextEditingController(
    text: _initial.collectionDetails,
  );
  late String? _category = widget.categories.contains(_initial.category)
      ? _initial.category
      : null;
  late String? _applicationId = widget.existing?.id;

  /// True while checking for "Next" (everything a submission needs); false
  /// for "Save draft" (only the length limits).
  bool _strict = false;
  bool _busy = false;

  bool get _isRespond =>
      widget.existing?.status == ApplicationStatus.infoRequested;

  @override
  void dispose() {
    for (final c in [_name, _description, _contact, _collection]) {
      c.dispose();
    }
    super.dispose();
  }

  ApplicationContent get _content => ApplicationContent(
    businessName: _name.text,
    category: _category ?? '',
    description: _description.text,
    contactDetails: _contact.text,
    collectionDetails: _collection.text,
  );

  FormFieldValidator<String> _rule(
    FormFieldValidator<String> strict,
    int max,
  ) =>
      (value) =>
          _strict ? strict(value) : ApplicationRules.draftLength(value, max);

  Future<bool> _save({required bool strict}) async {
    setState(() => _strict = strict);
    if (!_form.currentState!.validate()) return false;
    setState(() => _busy = true);
    try {
      _applicationId = await ref
          .read(applicationActionsProvider)
          .save(applicationId: _applicationId, content: _content);
      return true;
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDraft() async {
    if (!await _save(strict: false) || !mounted) return;
    showMessage(
      context,
      _isRespond ? 'Changes saved.' : 'Draft saved. Continue any time.',
    );
    context.pop();
  }

  Future<void> _next() async {
    if (!await _save(strict: true) || !mounted) return;
    final submitted = await context.push<bool>(AppRoutes.businessDocuments);
    if (submitted == true && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remarks = widget.existing?.remarks;
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ApplicationStepHeader(step: 1),
            if (_isRespond && remarks != null) ...[
              const SizedBox(height: 12),
              ReviewerNoteCard(
                note: remarks,
                title: 'What the administrator asked for',
              ),
            ],
            label('Business name'),
            TextFormField(
              key: nameKey,
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              validator: _rule(ApplicationRules.businessName, 80),
              decoration: const InputDecoration(
                hintText: 'e.g. Ali Bakes',
                counterText: '',
              ),
            ),
            label('Category'),
            DropdownButtonFormField<String>(
              key: const Key('application-category'),
              initialValue: _category,
              items: [
                for (final c in widget.categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (c) => setState(() => _category = c),
              validator: (c) => _strict ? ApplicationRules.category(c) : null,
              decoration: const InputDecoration(hintText: 'Choose one'),
            ),
            label('What you sell'),
            TextFormField(
              key: descriptionKey,
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 5,
              maxLength: 1000,
              validator: _rule(ApplicationRules.description, 1000),
              decoration: const InputDecoration(
                hintText: 'Your products, prices and how often you sell',
              ),
            ),
            label('Contact details'),
            TextFormField(
              key: contactKey,
              controller: _contact,
              maxLength: 200,
              validator: _rule(ApplicationRules.contactDetails, 200),
              decoration: const InputDecoration(
                hintText: 'e.g. WhatsApp 012-3456789, Instagram @alibakes',
                prefixIcon: Icon(Icons.call_outlined),
                counterText: '',
              ),
            ),
            label('Collection'),
            TextFormField(
              key: collectionKey,
              controller: _collection,
              maxLength: 200,
              validator: _rule(ApplicationRules.collectionDetails, 200),
              decoration: const InputDecoration(
                hintText: 'e.g. Desasiswa Tekun lobby, weekdays 6-8pm',
                prefixIcon: Icon(Icons.place_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('application-next'),
              onPressed: _busy ? null : _next,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Next: documents'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('application-save-draft'),
              onPressed: _busy ? null : _saveDraft,
              child: Text(_isRespond ? 'Save changes' : 'Save draft'),
            ),
            const SizedBox(height: 20),
            const SimulatedReviewNotice(),
          ],
        ),
      ),
    );
  }
}
