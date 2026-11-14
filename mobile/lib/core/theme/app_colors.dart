import 'package:flutter/material.dart';

/// CampusNiaga colours: a bright, softened navy with an amber accent,
/// inspired by the Nestora reference.
abstract final class AppColors {
  static const Color primary = Color(0xFF3B66C4);
  static const Color primaryDark = Color(0xFF26488F);
  static const Color primarySoft = Color(0xFFE8EEFA);
  static const Color accent = Color(0xFFF2A93B);

  static const Color background = Color(0xFFF7F7F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color hint = Color(0xFF9CA3AF);
  static const Color icon = Color(0xFF6B7280);
  static const Color inputFill = Color(0xFFF3F2EF);
  static const Color border = Color(0xFFE5E3DF);
  static const Color error = Color(0xFFC62828);

  /// Splash and header backgrounds.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary],
  );
}
