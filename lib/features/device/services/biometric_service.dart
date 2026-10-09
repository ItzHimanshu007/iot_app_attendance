import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth_android/local_auth_android.dart';

import '../models/device_models.dart';

// ── Interface ─────────────────────────────────────────────────────────────────

/// Interface for biometric authentication — enables mock injection in tests.
abstract class BiometricServiceInterface {
  /// Check whether biometric authentication is available and enrolled.
  Future<BiometricAvailability> canAuthenticate();

  /// Return list of available biometric types on this device.
  Future<List<AppBiometricType>> getAvailableBiometrics();

  /// Prompt the user for biometric authentication.
  ///
  /// Returns [BiometricSuccess], [BiometricFailure], or [BiometricCancelled].
  Future<BiometricResult> authenticate({required String reason});
}

// ── Real Implementation ───────────────────────────────────────────────────────

/// Production biometric service using local_auth.
class BiometricService implements BiometricServiceInterface {
  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricAvailability> canAuthenticate() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return BiometricAvailability.unavailable;

      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return BiometricAvailability.notEnrolled;

      final available = await _auth.getAvailableBiometrics();
      if (available.isEmpty) return BiometricAvailability.notEnrolled;

      return BiometricAvailability.available;
    } catch (_) {
      return BiometricAvailability.unavailable;
    }
  }

  @override
  Future<List<AppBiometricType>> getAvailableBiometrics() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      return types.map(_toAppBiometricType).toList();
    } catch (_) {
      return [AppBiometricType.none];
    }
  }

  @override
  Future<BiometricResult> authenticate({required String reason}) async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        authMessages: [
          AndroidAuthMessages(
            signInTitle: 'Verify Your Identity',
            cancelButton: 'Cancel',
            biometricHint: 'Touch the fingerprint sensor',
            biometricNotRecognized: 'Not recognized. Try again.',
            biometricRequiredTitle: 'Biometric Required',
            goToSettingsButton: 'Go to Settings',
            goToSettingsDescription: 'Set up biometrics in your device settings.',
          ),
        ],
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: false,
          sensitiveTransaction: true,
        ),
      );
      return authenticated ? BiometricSuccess() : BiometricCancelled();
    } on PlatformException catch (e) {
      return BiometricFailure(_mapPlatformError(e));
    } catch (_) {
      return BiometricFailure(BiometricFailureReason.unknown);
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  AppBiometricType _toAppBiometricType(BiometricType type) {
    // BiometricType here is local_auth's enum (no collision since we use
    // AppBiometricType as our own enum name)
    switch (type) {
      case BiometricType.fingerprint:
        return AppBiometricType.fingerprint;
      case BiometricType.face:
        return AppBiometricType.face;
      case BiometricType.iris:
        return AppBiometricType.iris;
      default:
        return AppBiometricType.none;
    }
  }

  BiometricFailureReason _mapPlatformError(PlatformException e) {
    switch (e.code) {
      case auth_error.notAvailable:
        return BiometricFailureReason.notAvailable;
      case auth_error.notEnrolled:
        return BiometricFailureReason.notEnrolled;
      case auth_error.lockedOut:
        return BiometricFailureReason.temporarilyLocked;
      case auth_error.permanentlyLockedOut:
        return BiometricFailureReason.permanentlyLocked;
      case auth_error.passcodeNotSet:
        return BiometricFailureReason.notSecured;
      default:
        return BiometricFailureReason.unknown;
    }
  }
}

// ── Mock Implementation ───────────────────────────────────────────────────────

/// Mock biometric service — simulates outcomes without physical hardware.
class MockBiometricService implements BiometricServiceInterface {
  MockBiometricService({
    this.availability = BiometricAvailability.available,
    BiometricResult? authResult,
    List<AppBiometricType>? availableTypes,
  })  : _authResult = authResult,
        availableTypes = availableTypes ?? [AppBiometricType.fingerprint];

  final BiometricAvailability availability;
  final BiometricResult? _authResult;
  final List<AppBiometricType> availableTypes;

  @override
  Future<BiometricAvailability> canAuthenticate() async => availability;

  @override
  Future<List<AppBiometricType>> getAvailableBiometrics() async =>
      availableTypes;

  @override
  Future<BiometricResult> authenticate({required String reason}) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return _authResult ?? BiometricSuccess();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final biometricServiceProvider = Provider<BiometricServiceInterface>((ref) {
  return BiometricService();
});
