import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'widgets/gate_message.dart';

class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(authControllerProvider.notifier);
    return GateMessage(
      icon: Icons.mark_email_unread_outlined,
      title: 'Confirm your email',
      message:
          'We sent a confirmation link to your USM email. Open it, then come '
          'back here. Check your Junk folder if you cannot find it.',
      actions: [
        FilledButton(
          onPressed: controller.recheckAccess,
          child: const Text("I've confirmed it"),
        ),
        TextButton(
          onPressed: controller.signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

class NotEligibleScreen extends ConsumerWidget {
  const NotEligibleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GateMessage(
      icon: Icons.school_outlined,
      title: 'CampusNiaga is for USM students',
      message:
          'Sign in with your @student.usm.my email to buy, sell and start a '
          'student business.',
      actions: [
        FilledButton(
          onPressed: ref.read(authControllerProvider.notifier).signOut,
          child: const Text('Use another account'),
        ),
      ],
    );
  }
}

class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GateMessage(
      icon: Icons.block_outlined,
      title: 'Account suspended',
      message:
          'Your account has been suspended by a CampusNiaga administrator. '
          'Contact the CampusNiaga team if you think this is a mistake.',
      actions: [
        TextButton(
          onPressed: ref.read(authControllerProvider.notifier).signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
