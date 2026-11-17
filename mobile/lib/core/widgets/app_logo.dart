import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The CampusNiaga mark: the shopping bag with a mortarboard on a USM purple
/// tile (assets/images/logo_mark.png, from docs/brand/app-icon.png).
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 40, this.onDark = false});

  static const String asset = 'assets/images/logo_mark.png';

  final double size;

  /// Adds a faint white outline so the purple tile stands out on purple.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'CampusNiaga',
    );
    if (!onDark) return image;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: image,
    );
  }
}

/// The "Campus" + "Niaga" wordmark: purple and gold on light backgrounds,
/// white and gold on dark ones, as in the logo.
class AppWordmark extends StatelessWidget {
  const AppWordmark({
    super.key,
    this.fontSize = 18,
    this.onDark = false,
    this.fontWeight = FontWeight.w800,
  });

  final double fontSize;
  final bool onDark;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: -0.3,
        ),
        children: [
          TextSpan(
            text: 'Campus',
            style: TextStyle(color: onDark ? Colors.white : AppColors.primary),
          ),
          TextSpan(
            text: 'Niaga',
            style: TextStyle(
              color: onDark ? AppColors.accent : AppColors.accentDeep,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mark plus wordmark, side by side.
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
        AppWordmark(fontSize: size * 0.6, onDark: onDark),
      ],
    );
  }
}
