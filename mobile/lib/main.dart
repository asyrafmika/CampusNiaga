import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/preferences.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'core/widgets/startup_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences preferences;
  try {
    await initializeSupabase();
    preferences = await SharedPreferences.getInstance();
  } catch (error) {
    runApp(StartupErrorApp(error: error));
    return;
  }
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const CampusNiagaApp(),
    ),
  );
}
