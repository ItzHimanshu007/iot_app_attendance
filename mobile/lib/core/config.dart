/// Build-time configuration.
///
/// Pass values with `--dart-define-from-file=config/dev.json` (see
/// `config/example.json`) or individual `--dart-define=KEY=value` flags.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String apiBaseUrl = String.fromEnvironment('API_URL');

  // ── Branding (shown before sign-in; the backend campus name is used after) ─
  static const String appName = 'Staff Attendance';
  static const String collegeName = String.fromEnvironment(
    'COLLEGE_NAME',
    defaultValue: 'Smart Campus',
  );
  static const String supportContact = String.fromEnvironment(
    'SUPPORT_CONTACT',
    defaultValue: 'the administration office',
  );

  static bool get isConfigured =>
      supabaseUrl.startsWith('https://') &&
      supabaseAnonKey.isNotEmpty &&
      apiBaseUrl.startsWith('http');

  static List<String> get missing => [
    if (!supabaseUrl.startsWith('https://')) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    if (!apiBaseUrl.startsWith('http')) 'API_URL',
  ];

  // ── Network ────────────────────────────────────────────────────────────────
  // Render's free tier can take ~50 s to wake up.
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);

  // ── BLE beacon (Protocol V3, unchanged from the ESP32 firmware) ────────────
  static const String beaconNamePrefix = 'SCA-';
  static const Duration beaconGoneAfter = Duration(seconds: 8);

  // ── Face recognition ───────────────────────────────────────────────────────
  static const String faceModelAsset = 'assets/models/mobilefacenet.tflite';
  static const String faceModelVersion = 'mobilefacenet-112-v1';
  static const int enrollSamples = 3;
  static const Duration livenessTimeout = Duration(seconds: 60);
}
