import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device_models.dart';
import '../services/biometric_service.dart';

// ── Biometric State ───────────────────────────────────────────────────────────

sealed class BiometricState {
  const BiometricState();
}

class BiometricIdle extends BiometricState {
  const BiometricIdle();
}

class BiometricCheckingAvailability extends BiometricState {
  const BiometricCheckingAvailability();
}

/// Biometrics checked — shows availability and types.
class BiometricAvailable extends BiometricState {
  const BiometricAvailable({required this.types});
  final List<AppBiometricType> types;
}

class BiometricUnavailableState extends BiometricState {
  const BiometricUnavailableState({required this.availability});
  final BiometricAvailability availability;
}

class BiometricAuthenticating extends BiometricState {
  const BiometricAuthenticating();
}

class BiometricAuthenticated extends BiometricState {
  const BiometricAuthenticated();
}

class BiometricAuthFailed extends BiometricState {
  const BiometricAuthFailed({required this.reason});
  final BiometricFailureReason reason;
}

class BiometricAuthCancelled extends BiometricState {
  const BiometricAuthCancelled();
}

// ── Biometric Controller ──────────────────────────────────────────────────────

/// Manages the biometric authentication flow.
class BiometricController extends StateNotifier<BiometricState> {
  BiometricController(this._biometricService)
      : super(const BiometricIdle());

  final BiometricServiceInterface _biometricService;

  // ── Availability check ────────────────────────────────────────────────────

  /// Check if biometrics are available. Call before showing the prompt.
  Future<BiometricAvailability> checkAvailability() async {
    state = const BiometricCheckingAvailability();

    final availability = await _biometricService.canAuthenticate();

    if (availability == BiometricAvailability.available) {
      final types = await _biometricService.getAvailableBiometrics();
      state = BiometricAvailable(types: types);
    } else {
      state = BiometricUnavailableState(availability: availability);
    }

    return availability;
  }

  // ── Authentication ────────────────────────────────────────────────────────

  /// Prompt the user for biometric verification.
  ///
  /// Updates state to [BiometricAuthenticated] on success.
  /// Returns true if authentication succeeded.
  Future<bool> authenticate({
    String reason = 'Verify your identity to record attendance',
  }) async {
    // Quick availability check if not already done
    final current = state;
    if (current is! BiometricAvailable) {
      final avail = await checkAvailability();
      if (avail != BiometricAvailability.available) return false;
    }

    state = const BiometricAuthenticating();

    final result = await _biometricService.authenticate(reason: reason);

    switch (result) {
      case BiometricSuccess():
        state = const BiometricAuthenticated();
        return true;
      case BiometricFailure(reason: final r):
        state = BiometricAuthFailed(reason: r);
        return false;
      case BiometricCancelled():
        state = const BiometricAuthCancelled();
        return false;
    }
  }

  /// Reset to idle — allows re-authentication.
  void reset() => state = const BiometricIdle();

  /// Reset to available — keeps availability info but allows retry.
  void resetToAvailable() {
    final current = state;
    if (current is BiometricAuthFailed || current is BiometricAuthCancelled) {
      // Re-check availability
      checkAvailability();
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final biometricControllerProvider =
    StateNotifierProvider<BiometricController, BiometricState>((ref) {
  final service = ref.watch(biometricServiceProvider);
  return BiometricController(service);
});

/// Convenience — whether the user is currently authenticated.
final isBiometricAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(biometricControllerProvider) is BiometricAuthenticated;
});
