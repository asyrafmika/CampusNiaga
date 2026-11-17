import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/theme/app_theme.dart';

void main() {
  final theme = buildAppTheme();

  test('uses USM purple as the primary colour and gold as the accent', () {
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.primary, const Color(0xFF5B2A86));
    expect(theme.colorScheme.secondary, const Color(0xFFF5B301));
  });

  test('uses the bundled Montserrat font', () {
    expect(theme.textTheme.bodyMedium?.fontFamily, appFontFamily);
  });

  test('inputs are filled', () {
    expect(theme.inputDecorationTheme.filled, isTrue);
    expect(theme.inputDecorationTheme.fillColor, AppColors.inputFill);
  });
}
