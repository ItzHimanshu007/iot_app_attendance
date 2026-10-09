import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';

/// Secure storage service — wraps flutter_secure_storage with typed accessors.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  // ── Token management ───────────────────────────────────────────────────────

  Future<String?> getAccessToken() =>
      _storage.read(key: AppConstants.keyAccessToken);

  Future<void> setAccessToken(String token) =>
      _storage.write(key: AppConstants.keyAccessToken, value: token);

  Future<String?> getRefreshToken() =>
      _storage.read(key: AppConstants.keyRefreshToken);

  Future<void> setRefreshToken(String token) =>
      _storage.write(key: AppConstants.keyRefreshToken, value: token);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await setAccessToken(accessToken);
    await setRefreshToken(refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: AppConstants.keyAccessToken);
    await _storage.delete(key: AppConstants.keyRefreshToken);
  }

  // ── User info ──────────────────────────────────────────────────────────────

  Future<String?> getUserRole() =>
      _storage.read(key: AppConstants.keyUserRole);

  Future<void> setUserRole(String role) =>
      _storage.write(key: AppConstants.keyUserRole, value: role);

  Future<String?> getUserId() =>
      _storage.read(key: AppConstants.keyUserId);

  Future<void> setUserId(String id) =>
      _storage.write(key: AppConstants.keyUserId, value: id);

  // ── Device ─────────────────────────────────────────────────────────────────

  Future<String?> getDeviceFingerprint() =>
      _storage.read(key: AppConstants.keyDeviceFingerprint);

  Future<void> setDeviceFingerprint(String fp) =>
      _storage.write(key: AppConstants.keyDeviceFingerprint, value: fp);

  Future<String?> getDeviceId() =>
      _storage.read(key: AppConstants.keyDeviceId);

  Future<void> setDeviceId(String id) =>
      _storage.write(key: AppConstants.keyDeviceId, value: id);

  Future<bool> isDeviceRegistered() async {
    final v = await _storage.read(key: AppConstants.keyDeviceRegistered);
    return v == 'true';
  }

  Future<void> setDeviceRegistered(bool registered) =>
      _storage.write(
        key: AppConstants.keyDeviceRegistered,
        value: registered.toString(),
      );

  Future<String?> getAndroidId() =>
      _storage.read(key: AppConstants.keyDeviceAndroidId);

  Future<void> setAndroidId(String id) =>
      _storage.write(key: AppConstants.keyDeviceAndroidId, value: id);

  // ── Generic key-value ──────────────────────────────────────────────────────

  Future<String?> rawRead(String key) => _storage.read(key: key);

  Future<void> rawWrite(String key, String value) =>
      _storage.write(key: key, value: value);

  // ── Generic ────────────────────────────────────────────────────────────────

  Future<void> clearAll() => _storage.deleteAll();

  Future<bool> hasToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}

/// Global provider for secure storage service.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
