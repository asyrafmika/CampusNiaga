import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/app_failure.dart';
import '../../../core/domain/listing_enums.dart';
import '../../../core/widgets/state_views.dart';
import 'marketplace_providers.dart';

/// Report a listing to the admins.
class ReportListingScreen extends ConsumerStatefulWidget {
  const ReportListingScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<ReportListingScreen> createState() =>
      _ReportListingScreenState();
}

class _ReportListingScreenState extends ConsumerState<ReportListingScreen> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Choose a reason.');
      return;
    }
    if (reason == ReportReason.other && _details.text.trim().isEmpty) {
      setState(() => _error = 'Tell us what’s wrong.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(marketplaceActionsProvider)
          .reportListing(
            listingId: widget.listingId,
            reason: reason,
            details: _details.text,
          );
      if (!mounted) return;
      showMessage(context, 'Thanks. An administrator will review it.');
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppFailure.messageOf(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Report listing')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            'What’s wrong with this listing?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Reports go to the CampusNiaga administrators. The seller won’t '
            'see who reported.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          RadioGroup<ReportReason>(
            groupValue: _reason,
            onChanged: (r) => setState(() {
              _reason = r;
              _error = null;
            }),
            child: Column(
              children: [
                for (final reason in ReportReason.values)
                  RadioListTile<ReportReason>(
                    value: reason,
                    title: Text(reason.label),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _details,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: _reason == ReportReason.other
                  ? 'Tell us what’s wrong'
                  : 'More details (optional)',
            ),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Send report'),
          ),
        ],
      ),
    );
  }
}
