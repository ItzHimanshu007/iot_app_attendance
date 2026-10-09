/// env.dart — Real Supabase & Backend configuration.
///
/// !! IMPORTANT — Fill in your actual values below before running. !!
///
/// How to find these values:
///   SUPABASE_URL     → Supabase dashboard → Project Settings → API → Project URL
///   SUPABASE_ANON_KEY → Supabase dashboard → Project Settings → API → anon public key
///   API_BASE_URL     → Your FastAPI server address (LAN IP for local, HTTPS for production)
///
/// Usage (recommended — pass via --dart-define so secrets are NOT committed):
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGci... \
///     --dart-define=API_URL=http://192.168.1.x:8000
///
/// OR — edit the defaultValue strings directly below for quick local development.
/// DO NOT commit real keys to source control.

class Env {
  Env._();

  // ── Supabase ──────────────────────────────────────────────────────────────

  /// Your Supabase project URL.
  /// Example: https://abcdefghijklmn.supabase.co
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jwrnvhgngduhofqhnvnl.supabase.co', // ← REPLACE
  );

  /// Your Supabase anon (public) key.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp3cm52aGduZ2R1aG9mcWhudm5sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwNDI5OTUsImV4cCI6MjA5NTYxODk5NX0.O3uadazfYqMpMLOg4MM1vkbx6pPds1Ji9j1Y69TX9WY', // ← PASTE YOUR ANON KEY HERE
  );

  // ── FastAPI Backend ───────────────────────────────────────────────────────

  /// FastAPI server base URL.
  ///
  /// Build-time injection (recommended — keeps URL configurable per env):
  ///   flutter build apk --release \
  ///     --dart-define=API_URL=https://smart-campus-api.onrender.com
  ///
  /// !! REPLACE the defaultValue below with your real Render URL !!
  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue:
        'https://iot-based-smart-attendance-system-backend.onrender.com', // ← REPLACE with your Render URL
  );

  // ── Validation ────────────────────────────────────────────────────────────

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty &&
      !supabaseUrl.contains('YOUR_PROJECT_REF') &&
      supabaseAnonKey.isNotEmpty;

  static bool get isApiConfigured =>
      apiBaseUrl.isNotEmpty &&
      !apiBaseUrl.contains('localhost') &&
      !apiBaseUrl.contains('127.0.0.1') &&
      !apiBaseUrl.contains('10.0.2.2') &&
      !apiBaseUrl.contains('192.168.');

  static bool get isFullyConfigured => isSupabaseConfigured && isApiConfigured;

  static List<String> get missingConfig {
    final issues = <String>[];
    if (supabaseUrl.isEmpty || supabaseUrl.contains('YOUR_PROJECT_REF')) {
      issues.add('SUPABASE_URL not configured');
    }
    if (supabaseAnonKey.isEmpty) {
      issues.add('SUPABASE_ANON_KEY not configured');
    }
    return issues;
  }
}
