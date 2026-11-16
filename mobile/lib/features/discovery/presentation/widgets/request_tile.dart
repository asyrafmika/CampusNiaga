import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/dates.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../marketplace/presentation/widgets/listing_widgets.dart';
import '../../domain/discovery_models.dart';
import '../discovery_providers.dart';

/// One product request with its Interested toggle (or Close, for the
/// student who made it).
class RequestTile extends ConsumerStatefulWidget {
  const RequestTile({super.key, required this.request});

  final ProductRequest request;

  @override
  ConsumerState<RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends ConsumerState<RequestTile> {
  /// The theme's buttons are full width; beside text they must not be.
  static final ButtonStyle _compact = ButtonStyle(
    minimumSize: WidgetStateProperty.all(const Size(0, 40)),
    padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(horizontal: 14),
    ),
  );

  late ProductRequest _request = widget.request;
  bool _busy = false;

  @override
  void didUpdateWidget(RequestTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _request = widget.request;
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(discoveryActionsProvider)
          .toggleInterest(_request.id);
      if (mounted) {
        setState(
          () => _request = _request.withInterest(
            interested: result.interested,
            count: result.count,
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close this request?'),
        content: const Text(
          'It leaves the requests list and no longer counts toward '
          'opportunities.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close request'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(discoveryActionsProvider).closeRequest(_request.id);
    } on Object catch (e) {
      if (mounted) showMessage(context, AppFailure.messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _request;
    final price = r.preferredPriceSen;
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(categoryIcon(r.category), color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    [
                      if (price != null) 'Wants it for ${formatRm(price)}',
                      r.campusArea,
                      formatDay(r.createdAt),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (r.notes case final notes?)
                    Text(
                      notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${r.studentCount} '
                    '${r.studentCount == 1 ? 'student wants' : 'students want'} '
                    'this',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (r.isMine)
              r.isActive
                  ? TextButton(
                      key: Key('request-close-${r.id}'),
                      style: _compact,
                      onPressed: _busy ? null : _close,
                      child: const Text('Close'),
                    )
                  : const StatusPill(label: 'Closed', tone: PillTone.muted)
            else
              r.iAmInterested
                  ? FilledButton.tonal(
                      key: Key('request-interest-${r.id}'),
                      style: _compact,
                      onPressed: _busy ? null : _toggle,
                      child: const Text('Interested ✓'),
                    )
                  : OutlinedButton(
                      key: Key('request-interest-${r.id}'),
                      style: _compact,
                      onPressed: _busy ? null : _toggle,
                      child: const Text('Interested'),
                    ),
          ],
        ),
      ),
    );
  }
}
