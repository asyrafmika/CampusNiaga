import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The CampusNiaga mark: an amber storefront on a rounded tile.
/// Replace with an image asset once there is a designed logo.
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 40, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.storefront_rounded,
        color: AppColors.accent,
        size: size * 0.6,
      ),
    );
  }
}

/// Mark plus the "CampusNiaga" wordmark, side by side.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogoMark(size: size, onDark: onDark),
        SizedBox(width: size * 0.3),
        Text(
          'CampusNiaga',
          style: TextStyle(
            fontSize: size * 0.6,
            fontWeight: FontWeight.w700,
            color: onDark ? Colors.white : AppColors.text,
          ),
        ),
      ],
    );
  }
}
