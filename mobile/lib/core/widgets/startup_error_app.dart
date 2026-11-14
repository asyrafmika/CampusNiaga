import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shown instead of the app when startup fails, so the problem is visible
/// rather than a blank screen.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CampusNiaga could not start',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text('$error'),
                const SizedBox(height: 12),
                const Text(
                  'Check lib/core/config/supabase_config.dart and your internet '
                  'connection, and run the app on an Android emulator or phone.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
