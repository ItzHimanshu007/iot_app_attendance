/// Application configuration — reads from [Env] (which reads from --dart-define).
///
/// All configuration must be accessed through this class.
/// Never use [Env] directly in feature code.
import 'env.dart';

class AppConfig {
  AppConfig._();

  static const String env =
      String.fromEnvironment('ENV', defaultValue: 'dev');

  static const String appName = 'Smart Campus';
  static const String appVersion = '0.1.0';
  static const int buildNumber = 1;

  // ── API ────────────────────────────────────────────────────────────────────

  /// FastAPI backend base URL.
  static String get apiBaseUrl => Env.apiBaseUrl;

  // ── Supabase ───────────────────────────────────────────────────────────────

  /// Supabase project URL.
  static String get supabaseUrl => Env.supabaseUrl;

  /// Supabase anon (public) key.
  static String get supabaseAnonKey => Env.supabaseAnonKey;

  // ── Timeouts ───────────────────────────────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 15);
  static const int maxRetries = 3;

  // ── BLE ────────────────────────────────────────────────────────────────────
  static const Duration bleScanDuration = Duration(seconds: 10);
  static const String bleDevicePrefix = 'SCA-';
  static const int bleRssiThreshold = -85;
  static const int bleAdvertisementMaxAgeDebugSeconds = 300;
  static const int bleScanRefreshMs = 2000;

  // ── Token ──────────────────────────────────────────────────────────────────
  static const Duration tokenRefreshBuffer = Duration(minutes: 5);

  // ── Debug ──────────────────────────────────────────────────────────────────
  static bool get isDebug => env == 'dev';
  static bool get isProduction => env == 'prod';
}
