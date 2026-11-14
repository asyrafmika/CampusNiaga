import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Connects to the Supabase project; call once before `runApp`.
Future<void> initializeSupabase() async {
  if (!SupabaseConfig.isConfigured) {
    throw StateError(
      'Supabase is not configured yet. Add the project URL and publishable '
      'key to lib/core/config/supabase_config.dart.',
    );
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
}
