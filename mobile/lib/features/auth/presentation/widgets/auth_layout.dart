import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_logo.dart';
import 'auth_style.dart';

/// Sign-in style page on the brand purple: logo bar, a large left-aligned
/// headline whose last words are gold, a subtitle, and the form on a
/// frosted-glass card that fades and slides in.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    this.titleAccent,
    required this.subtitle,
    required this.children,
    this.showBack = false,
    this.showBadge = false,
    this.footer,
  });

  /// Headline text; [titleAccent] follows it in gold ("Welcome " + "back.").
  final String title;
  final String? titleAccent;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  /// Shows the "Verified USM students" badge above the headline.
  final bool showBadge;

  /// Shown below the card, e.g. the "Create an account" link.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: AuthStyle.themeFrom(Theme.of(context)),
        child: Scaffold(
          backgroundColor: AppColors.primaryDark,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(child: _AuroraBackground()),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopBar(showBack: showBack),
                      const SizedBox(height: 32),
                      _EntranceMotion(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showBadge) ...[
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: _VerifiedBadge(),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Text.rich(
                              TextSpan(
                                text: title,
                                children: [
                                  if (titleAccent case final accent?)
                                    TextSpan(
                                      text: accent,
                                      style: const TextStyle(
                                        color: AppColors.accent,
                                      ),
                                    ),
                                ],
                              ),
                              style: const TextStyle(
                                color: AuthStyle.text,
                                fontSize: 38,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: AuthStyle.textMuted,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _GlassCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: children,
                              ),
                            ),
                            if (footer case final footer?) ...[
                              const SizedBox(height: 12),
                              footer,
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showBack});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (showBack)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              color: Colors.white,
              tooltip: 'Back',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x1FFFFFFF),
              ),
            ),
          const Spacer(),
          const AppLogo(size: 30, onDark: true),
        ],
      ),
    );
  }
}

/// The splash gradient with three soft, blurred glows.
class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppColors.nightGradient),
      child: Stack(
        children: [
          _Glow(right: -80, top: -60, size: 260, color: AuthStyle.glowLavender),
          _Glow(left: -90, top: 260, size: 220, color: AppColors.primary),
          _Glow(right: -60, bottom: -40, size: 220, color: AppColors.accent),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    this.left,
    this.right,
    this.top,
    this.bottom,
    required this.size,
    required this.color,
  });

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

/// Frosted glass: blurs whatever is behind it.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(28));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AuthStyle.glass,
            borderRadius: radius,
            border: Border.all(color: AuthStyle.glassBorder),
          ),
          child: Padding(padding: const EdgeInsets.all(22), child: child),
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AuthStyle.glassBorder),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 16, color: AppColors.accent),
          SizedBox(width: 6),
          Text(
            'Verified USM students',
            style: TextStyle(
              color: AuthStyle.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades and slides the content up once, unless the device asks for reduced
/// motion.
class _EntranceMotion extends StatelessWidget {
  const _EntranceMotion({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Label above a field ("Email").
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AuthStyle.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// A failure message above the submit button.
class FormErrorText extends StatelessWidget {
  const FormErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x26FF5449),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AuthStyle.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AuthStyle.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Question? Action" line at the bottom of a form.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  final String question;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Wraps onto two lines on narrow screens or with large accessibility text.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: const TextStyle(color: AuthStyle.textMuted)),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    );
  }
}

/// White button with purple text (as on onboarding); shows a spinner while
/// [busy].
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primaryDark,
        disabledBackgroundColor: const Color(0xCCFFFFFF),
        disabledForegroundColor: AppColors.primaryDark,
        minimumSize: const Size.fromHeight(56),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AuthStyle.fieldRadius),
          ),
        ),
        textStyle: const TextStyle(
          fontFamily: appFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
    );
  }
}
