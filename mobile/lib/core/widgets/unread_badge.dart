import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A small gold count of unread messages.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 8),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    constraints: const BoxConstraints(minWidth: 22),
    decoration: BoxDecoration(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppColors.night,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
