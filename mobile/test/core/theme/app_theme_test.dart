import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/theme/app_theme.dart';

void main() {
  final theme = buildAppTheme();

  test('uses the brand navy as the primary colour', () {
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.primary, const Color(0xFF3B66C4));
  });

  test('uses the bundled Montserrat font', () {
    expect(theme.textTheme.bodyMedium?.fontFamily, appFontFamily);
  });

  test('inputs are filled', () {
    expect(theme.inputDecorationTheme.filled, isTrue);
    expect(theme.inputDecorationTheme.fillColor, AppColors.inputFill);
  });
}
