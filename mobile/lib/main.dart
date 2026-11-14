import 'package:flutter/material.dart';

import 'core/supabase/supabase_bootstrap.dart';
import 'dev/connection_check_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeSupabase();
  } catch (error) {
    // Show why startup failed instead of a blank screen.
    runApp(StartupErrorApp(error: error));
    return;
  }
  runApp(const CampusNiagaApp());
}

class CampusNiagaApp extends StatelessWidget {
  const CampusNiagaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusNiaga',
      theme: ThemeData(colorSchemeSeed: const Color(0xFFF83758)),
      home: const ConnectionCheckScreen(),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
