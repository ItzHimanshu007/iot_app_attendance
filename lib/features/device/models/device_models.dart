// Device fingerprint and biometric models.
//
// DeviceRegisterRequest mirrors backend/app/schemas/user.py → DeviceRegister.
// DeviceInfo mirrors DeviceResponse.

/// Raw device hardware metadata — collected before hashing.
class DeviceMetadata {
  const DeviceMetadata({
    required this.androidId,
    required this.deviceModel,
    required this.manufacturer,
    required this.brand,
    required this.sdkVersion,
    required this.osVersion,
    required this.appVersion,
  });

  final String androidId;
  final String deviceModel;
  final String manufacturer;
  final String brand;
  final int sdkVersion;
  final String osVersion;
  final String appVersion;

  @override
  String toString() =>
      'DeviceMetadata(model=$deviceModel, sdk=$sdkVersion, brand=$brand)';
}

/// Device registration request — mirrors backend DeviceRegister schema.
/// Only the hashed fingerprint is sent; raw IDs stay on device.
class DeviceRegisterRequest {
  const DeviceRegisterRequest({
    required this.androidId,
    required this.deviceModel,
    required this.deviceManufacturer,
    required this.deviceFingerprint,
    required this.osVersion,
    required this.appVersion,
  });

  final String androidId;
  final String deviceModel;
  final String deviceManufacturer;
  final String deviceFingerprint; // SHA-256 hash
  final String osVersion;
  final String appVersion;

  Map<String, dynamic> toJson() => {
        'android_id': androidId,
        'device_model': deviceModel,
        'device_manufacturer': deviceManufacturer,
        'device_fingerprint': deviceFingerprint,
        'os_version': osVersion,
        'app_version': appVersion,
      };
}

/// Registered device — mirrors backend DeviceResponse schema.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.userId,
    required this.deviceModel,
    required this.deviceFingerprint,
    required this.isActive,
    required this.registeredAt,
    this.lastActiveAt,
  });

  final String id;
  final String userId;
  final String deviceModel;
  final String deviceFingerprint;
  final bool isActive;
  final DateTime registeredAt;
  final DateTime? lastActiveAt;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      deviceModel: json['device_model'] as String,
      deviceFingerprint: json['device_fingerprint'] as String,
      isActive: json['is_active'] as bool,
      registeredAt: DateTime.parse(json['registered_at'] as String),
      lastActiveAt: json['last_active_at'] != null
          ? DateTime.parse(json['last_active_at'] as String)
          : null,
    );
  }
}

/// Result of checking whether this device is registered and active.
enum DeviceRegistrationStatus {
  /// Device has never been registered.
  unregistered,

  /// Device is registered and active.
  registered,

  /// Device is registered but deactivated by admin.
  inactive,

  /// A different device is registered for this account.
  mismatch,

  /// Registration status is unknown (network error, etc.).
  unknown,
}

/// Available biometric types (app-level enum, avoids collision with local_auth).
enum AppBiometricType {
  fingerprint,
  face,
  iris,
  none,
}

/// Biometric availability status.
enum BiometricAvailability {
  /// Hardware present and at least one biometric enrolled.
  available,

  /// Hardware present but no biometrics enrolled.
  notEnrolled,

  /// No biometric hardware.
  unavailable,

  /// Device is not secured (no lock screen).
  notSecured,
}

/// Result of a biometric authentication attempt.
sealed class BiometricResult {}

class BiometricSuccess extends BiometricResult {
  BiometricSuccess();
}

class BiometricFailure extends BiometricResult {
  BiometricFailure(this.reason);
  final BiometricFailureReason reason;
}

class BiometricCancelled extends BiometricResult {
  BiometricCancelled();
}

enum BiometricFailureReason {
  notAvailable,
  notEnrolled,
  notSecured,
  permanentlyLocked,
  temporarilyLocked,
  authenticationFailed,
  unknown,
}

extension BiometricFailureReasonX on BiometricFailureReason {
  String get userMessage {
    switch (this) {
      case BiometricFailureReason.notAvailable:
        return 'Biometrics are not available on this device.';
      case BiometricFailureReason.notEnrolled:
        return 'No biometrics enrolled. Please set up a fingerprint or face unlock in Settings.';
      case BiometricFailureReason.notSecured:
        return 'Device not secured. Please set up a PIN or pattern lock.';
      case BiometricFailureReason.permanentlyLocked:
        return 'Biometrics are locked out. Please use your PIN to unlock.';
      case BiometricFailureReason.temporarilyLocked:
        return 'Too many failed attempts. Please wait and try again.';
      case BiometricFailureReason.authenticationFailed:
        return 'Biometric verification failed. Please try again.';
      case BiometricFailureReason.unknown:
        return 'An unknown error occurred. Please try again.';
    }
  }
}
