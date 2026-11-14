import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_photo.dart';
import 'onboarding_controller.dart';

class _Slide {
  const _Slide(this.image, this.icon, this.title, this.body);

  final String image;
  final IconData icon;
  final String title;
  final String body;
}

final _slides = [
  _Slide(
    AppImages.onboarding[0],
    Icons.search_rounded,
    'Find campus deals',
    'Books, gadgets and hostel essentials from fellow USM students, all in '
        'one place.',
  ),
  _Slide(
    AppImages.onboarding[1],
    Icons.storefront_rounded,
    'Sell or start a business',
    'List an item in a minute, or apply to run your own approved student '
        'business.',
  ),
  _Slide(
    AppImages.onboarding[2],
    Icons.handshake_outlined,
    'Collect on campus',
    'Meet at your desasiswa or faculty and pay the seller directly. No fees, '
        'no delivery.',
  ),
];

/// First-launch slides. Layout from the Pixel Market reference: a photo card
/// on top, then the page dots, text and a full-width button.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const continueKey = Key('onboarding-continue');
  static const skipKey = Key('onboarding-skip');

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // Finishing onboarding makes the router move on to sign-in.
  void _finish() => ref.read(onboardingSeenProvider.notifier).complete();

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _slides.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: BrandPhoto(
                                asset: slide.image,
                                fallbackIcon: slide.icon,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            children: [
                              Text(
                                slide.title,
                                textAlign: TextAlign.center,
                                style: textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                slide.body,
                                textAlign: TextAlign.center,
                                style: textTheme.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              _Dots(count: _slides.length, active: _index),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: FilledButton(
                  key: OnboardingScreen.continueKey,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryDark,
                  ),
                  onPressed: _next,
                  child: Text(_isLast ? 'Get started' : 'Continue'),
                ),
              ),
              Opacity(
                opacity: _isLast ? 0 : 1,
                child: TextButton(
                  key: OnboardingScreen.skipKey,
                  onPressed: _isLast ? null : _finish,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.8),
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active
                  ? AppColors.accent
                  : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(appRadius),
            ),
          ),
      ],
    );
  }
}
