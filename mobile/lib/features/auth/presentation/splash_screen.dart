import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../data/auth_repository.dart';
import 'auth_controller.dart';

/// Brand screen shown while access is looked up, and if the lookup fails.
/// Layout from the Nestora splash reference.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  static const retryKey = Key('splash-retry');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(userAccessProvider).hasError;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.night,
      // Scaffold gives its body loose constraints, so without SizedBox.expand
      // the gradient only covers the column's width and leaves a white strip.
      body: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.nightGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  const AppLogoMark(size: 96, onDark: true),
                  const SizedBox(height: 24),
                  const AppWordmark(fontSize: 36, onDark: true),
                  const SizedBox(height: 12),
                  Text(
                    'BUY. SELL. START YOUR BUSINESS.',
                    textAlign: TextAlign.center,
                    style: textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(flex: 3),
                  if (!failed)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  else ...[
                    Text(
                      "Couldn't reach CampusNiaga. Check your internet "
                      'connection and try again.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: retryKey,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryDark,
                      ),
                      onPressed: () => ref
                          .read(authControllerProvider.notifier)
                          .recheckAccess(),
                      child: const Text('Try again'),
                    ),
                  ],
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
