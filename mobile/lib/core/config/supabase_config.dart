/// Connection details of the CampusNiaga Supabase project, from the dashboard:
/// Project Settings → API (Project URL) and API Keys (publishable key).
///
/// The publishable key is designed to ship inside the app: Row Level Security
/// in the database decides what each user may do. Never put the secret
/// (service_role) key here.
abstract final class SupabaseConfig {
  static const String url = 'https://abctyhurvvprthgwrxyi.supabase.co';
  static const String publishableKey =
      'sb_publishable_eG3N5cMp9hbVj_fcfukRpA_Ge-NV8AE';

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
