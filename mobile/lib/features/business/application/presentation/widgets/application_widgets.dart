import 'package:flutter/material.dart';

import '../../../../../core/domain/business_enums.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../marketplace/presentation/widgets/listing_widgets.dart';

/// The approval is a simulated reviewer workflow for the FYP prototype, and
/// every application screen says so.
class SimulatedReviewNotice extends StatelessWidget {
  const SimulatedReviewNotice({super.key});

  static const Key noticeKey = Key('simulated-review-notice');

  @override
  Widget build(BuildContext context) => Container(
    key: noticeKey,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.inputFill,
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: AppColors.icon),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Prototype: approval is a simulated reviewer workflow for this '
            'FYP. It is not an official USM or HDC business registration.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// What the reviewer wrote, highlighted.
class ReviewerNoteCard extends StatelessWidget {
  const ReviewerNoteCard({
    super.key,
    required this.note,
    this.title = 'Reviewer’s note',
  });

  final String note;
  final String title;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFDF0DA),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.rate_review_outlined, color: Color(0xFF9A5B00)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9A5B00),
                ),
              ),
              const SizedBox(height: 4),
              Text(note),
            ],
          ),
        ),
      ],
    ),
  );
}

/// "Step 1 of 2 · Business details" / "Step 2 of 2 · Documents".
class ApplicationStepHeader extends StatelessWidget {
  const ApplicationStepHeader({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => Text(
    'Step $step of 2 · ${step == 1 ? 'Business details' : 'Documents'}',
    style: Theme.of(context).textTheme.labelLarge,
  );
}

StatusPill applicationStatusPill(ApplicationStatus status) => StatusPill(
  label: status.label,
  tone: switch (status) {
    ApplicationStatus.draft => PillTone.neutral,
    ApplicationStatus.submitted ||
    ApplicationStatus.underReview => PillTone.info,
    ApplicationStatus.infoRequested => PillTone.warning,
    ApplicationStatus.approved => PillTone.good,
    ApplicationStatus.rejected => PillTone.muted,
  },
);
