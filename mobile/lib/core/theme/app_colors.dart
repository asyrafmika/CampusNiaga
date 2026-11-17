import 'package:flutter/material.dart';

/// CampusNiaga colours: USM purple with a gold accent, taken from the
/// CampusNiaga logo (docs/brand/).
abstract final class AppColors {
  /// USM purple, the logo tile.
  static const Color primary = Color(0xFF5B2A86);
  static const Color primaryDark = Color(0xFF3F1C5E);
  static const Color primarySoft = Color(0xFFF1EAF7);

  /// The deep purple behind the dark logo; splash and launch screens.
  static const Color night = Color(0xFF1E0F2E);

  /// Gold, the mortarboard tassel. On white, text uses [accentDeep].
  static const Color accent = Color(0xFFF5B301);
  static const Color accentDeep = Color(0xFFE0A100);

  static const Color background = Color(0xFFF7F7F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color hint = Color(0xFF9CA3AF);
  static const Color icon = Color(0xFF6B7280);
  static const Color inputFill = Color(0xFFF3F2EF);
  static const Color border = Color(0xFFE5E3DF);
  static const Color error = Color(0xFFC62828);

  /// Header and banner backgrounds.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary],
  );

  /// Splash and sign-in backgrounds: from [night] (the launch screen's
  /// colour) to USM purple.
  static const LinearGradient nightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [night, primaryDark, primary],
    stops: [0, 0.55, 1],
  );
}
