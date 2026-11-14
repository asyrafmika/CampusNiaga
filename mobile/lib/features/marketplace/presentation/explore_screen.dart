import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_controller.dart';

/// Home for signed-in students. Placeholder until the Phase 2 marketplace.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = switch (ref.watch(userAccessProvider)) {
      AsyncData(:final value) => value?.email ?? '',
      _ => '',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('CampusNiaga')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome!', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text('Signed in as $email', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            Text(
              'The marketplace arrives in Phase 2.',
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: ref.read(authControllerProvider.notifier).signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
