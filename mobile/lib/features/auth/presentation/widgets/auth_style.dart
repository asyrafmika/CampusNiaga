import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';

/// The sign-in and sign-up look: the deep purple gradient of the splash and
/// onboarding, soft "aurora" glows, and a frosted-glass form card.
abstract final class AuthStyle {
  static const Color text = Colors.white;
  static const Color textMuted = Color(0xC7FFFFFF);
  static const Color link = AppColors.accent;
  static const Color field = Color(0x1AFFFFFF);
  static const Color fieldBorder = Color(0x38FFFFFF);
  static const Color glass = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x2EFFFFFF);
  static const Color error = Color(0xFFFFB4AB);
  static const Color glowLavender = Color(0xFFB98CE6);

  static const double fieldRadius = 14;

  /// The app theme adjusted for the purple auth screens: light text, frosted
  /// inputs that light up gold when focused.
  static ThemeData themeFrom(ThemeData base) {
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(fieldRadius),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        error: error,
        onSurface: text,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: Color(0x66F5B301),
        selectionHandleColor: AppColors.accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        hintStyle: const TextStyle(
          color: Color(0x8CFFFFFF),
          fontSize: 15,
          fontFamily: appFontFamily,
        ),
        errorStyle: const TextStyle(color: error),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        border: border(fieldBorder),
        enabledBorder: border(fieldBorder),
        focusedBorder: border(AppColors.accent, width: 1.6),
        errorBorder: border(error),
        focusedErrorBorder: border(error, width: 1.6),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: link,
          textStyle: const TextStyle(
            fontFamily: appFontFamily,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textMuted),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryDark,
      ),
    );
  }
}
