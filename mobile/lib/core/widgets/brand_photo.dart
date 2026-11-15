import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Photo slots. Put the files in `mobile/assets/images/` with these names;
/// until then each slot shows a navy panel with an icon.
abstract final class AppImages {
  static const List<String> onboarding = [
    'assets/images/onboarding_1.jpg',
    'assets/images/onboarding_2.jpg',
    'assets/images/onboarding_3.jpg',
  ];
}

/// A cover-fit photo that falls back to a branded panel if the file is
/// missing, with [fallbackIcon] in the middle when given.
class BrandPhoto extends StatelessWidget {
  const BrandPhoto({super.key, required this.asset, this.fallbackIcon});

  final String asset;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) => DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: fallbackIcon == null
            ? const SizedBox.expand()
            : Center(
                child: Icon(
                  fallbackIcon,
                  size: 96,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
      ),
    );
  }
}
