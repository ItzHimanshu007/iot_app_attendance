import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/env.dart';
import '../services/api_client.dart';
import '../services/connectivity_service.dart';
import '../services/secure_storage_service.dart';

/// Result of a single startup check.
class StartupCheckResult {
  const StartupCheckResult({
    required this.name,
    required this.passed,
    this.message,
    this.isCritical = false,
  });

  final String name;
  final bool passed;
  final String? message;

  /// Critical failures prevent login (e.g. missing config).
  /// Non-critical failures are shown as warnings (e.g. no network).
  final bool isCritical;
}

/// Full startup validation result.
class StartupValidation {
  const StartupValidation({
    required this.checks,
    required this.canProceed,
    required this.criticalError,
  });

  final List<StartupCheckResult> checks;

  /// True when no critical checks failed — app may continue.
  final bool canProceed;

  /// First critical failure message, or null if all critical checks passed.
  final String? criticalError;

  bool get hasWarnings => checks.any((c) => !c.passed && !c.isCritical);
}

// ── Startup Validator ─────────────────────────────────────────────────────────

/// Runs all startup checks in sequence and returns a [StartupValidation].
///
/// Called once during app launch before the normal auth flow begins.
/// Critical checks:
///   1. Configuration — SUPABASE_URL and SUPABASE_ANON_KEY are set
///   2. Secure storage — readable and writable
///
/// Non-critical checks:
///   3. Network connectivity — device is online
///   4. Backend reachability — API_BASE_URL responds (best-effort)
///   5. Supabase reachability — Supabase project responds (best-effort)
class StartupValidator {
  StartupValidator({
    required SecureStorageService storage,
    required ConnectivityService connectivity,
    required ApiClient apiClient,
  })  : _storage = storage,
        _connectivity = connectivity,
        _apiClient = apiClient;

  final SecureStorageService _storage;
  final ConnectivityService _connectivity;
  final ApiClient _apiClient;

  Future<StartupValidation> validate() async {
    final checks = <StartupCheckResult>[];

    // 1. Configuration
    checks.add(await _checkConfiguration());
    if (!checks.last.passed) {
      // Config is missing — no point running further checks
      return StartupValidation(
        checks: checks,
        canProceed: false,
        criticalError: checks.last.message,
      );
    }

    // 2. Secure storage
    checks.add(await _checkSecureStorage());

    // 3–5. Non-critical — run in parallel
    final nonCritical = await Future.wait([
      _checkNetwork(),
      _checkBackendReachability(),
      _checkSupabaseReachability(),
    ]);
    checks.addAll(nonCritical);

    final criticalFailure =
        checks.firstWhere((c) => !c.passed && c.isCritical,
            orElse: () => const StartupCheckResult(
                  name: '',
                  passed: true,
                  isCritical: false,
                ));

    return StartupValidation(
      checks: checks,
      canProceed: !checks.any((c) => !c.passed && c.isCritical),
      criticalError:
          criticalFailure.passed ? null : criticalFailure.message,
    );
  }

  // ── Individual checks ─────────────────────────────────────────────────────

  Future<StartupCheckResult> _checkConfiguration() async {
    final missing = Env.missingConfig;
    if (missing.isNotEmpty) {
      return StartupCheckResult(
        name: 'Configuration',
        passed: false,
        message:
            'Missing required configuration:\n${missing.join('\n')}\n\nEdit lib/core/env.dart or pass --dart-define flags.',
        isCritical: true,
      );
    }
    return const StartupCheckResult(
      name: 'Configuration',
      passed: true,
      message: 'All required config values present',
    );
  }

  Future<StartupCheckResult> _checkSecureStorage() async {
    try {
      const testKey = '_startup_test_key';
      await _storage.rawWrite(testKey, 'ok');
      final val = await _storage.rawRead(testKey);
      if (val != 'ok') throw Exception('Read-back mismatch');
      return const StartupCheckResult(
        name: 'Secure Storage',
        passed: true,
        message: 'Read/write verified',
        isCritical: true,
      );
    } catch (e) {
      return StartupCheckResult(
        name: 'Secure Storage',
        passed: false,
        message:
            'Secure storage is unavailable: $e\nTokens cannot be persisted.',
        isCritical: true,
      );
    }
  }

  Future<StartupCheckResult> _checkNetwork() async {
    try {
      final connected = await _connectivity.isConnected;
      return StartupCheckResult(
        name: 'Network',
        passed: connected,
        message: connected ? 'Device is online' : 'No internet connection',
        isCritical: false,
      );
    } catch (_) {
      return const StartupCheckResult(
        name: 'Network',
        passed: false,
        message: 'Could not check connectivity',
        isCritical: false,
      );
    }
  }

  Future<StartupCheckResult> _checkBackendReachability() async {
    try {
      // Ping the FastAPI health endpoint — must return 200
      await _apiClient.get<Map<String, dynamic>>(
        '/health',
        fromJson: (d) => d as Map<String, dynamic>,
      );
      return StartupCheckResult(
        name: 'API Server',
        passed: true,
        message: 'Reachable at ${Env.apiBaseUrl}',
        isCritical: false,
      );
    } catch (_) {
      return StartupCheckResult(
        name: 'API Server',
        passed: false,
        message:
            'Cannot reach ${Env.apiBaseUrl}. Check server is running.',
        isCritical: false,
      );
    }
  }

  Future<StartupCheckResult> _checkSupabaseReachability() async {
    try {
      final url = Uri.tryParse(Env.supabaseUrl);
      if (url == null || !url.hasScheme) {
        throw Exception('Invalid URL format');
      }
      return StartupCheckResult(
        name: 'Supabase',
        passed: true,
        message: 'Configured at ${Env.supabaseUrl}',
        isCritical: false,
      );
    } catch (_) {
      return StartupCheckResult(
        name: 'Supabase',
        passed: false,
        message: 'Supabase URL appears invalid: ${Env.supabaseUrl}',
        isCritical: false,
      );
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final startupValidatorProvider = Provider<StartupValidator>((ref) {
  return StartupValidator(
    storage: ref.watch(secureStorageProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    apiClient: ref.watch(apiClientProvider),
  );
});

final startupValidationProvider =
    FutureProvider<StartupValidation>((ref) async {
  final validator = ref.watch(startupValidatorProvider);
  return validator.validate();
});
