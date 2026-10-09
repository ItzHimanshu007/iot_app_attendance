import 'package:flutter/material.dart';

import 'api_exception.dart';

/// Friendly title, icon and tip for each backend error code.
class ErrorText {
  const ErrorText(this.title, this.icon, [this.tip]);

  final String title;
  final IconData icon;
  final String? tip;

  static ErrorText of(Object error) {
    final code = error is ApiException ? error.code : 'UNKNOWN';
    return _byCode[code] ??
        const ErrorText('Could not mark attendance', Icons.error_outline_rounded);
  }

  /// Errors the staff member can fix by simply trying again (new challenge, new capture).
  static bool canRetry(Object error) => error is ApiException && _retryable.contains(error.code);

  static const _retryable = {
    'FACE_MISMATCH',
    'LIVENESS_FAILED',
    'CHALLENGE_EXPIRED',
    'CHALLENGE_USED',
    'CHALLENGE_INVALID',
    'BEACON_TOKEN_INVALID',
    'BEACON_TOO_FAR',
    'BEACON_MISMATCH',
    'LOCATION_REQUIRED',
    'NETWORK_ERROR',
    'TIMEOUT',
  };

  static ErrorText forCode(String? code) =>
      _byCode[code] ?? const ErrorText('Verification failed', Icons.gpp_bad_outlined);

  static const _byCode = <String, ErrorText>{
    'FACE_MISMATCH': ErrorText(
      'Face not recognised',
      Icons.face_retouching_off,
      'Face a light, remove mask or cap, hold the phone at eye level and try again.',
    ),
    'LIVENESS_FAILED': ErrorText(
      'Liveness check failed',
      Icons.visibility_off_outlined,
      'Follow the on-screen actions in the order shown.',
    ),
    'BEACON_TOO_FAR': ErrorText(
      'Too far from the beacon',
      Icons.bluetooth_searching,
      'Move closer to the campus beacon and try again.',
    ),
    'BEACON_TOKEN_INVALID': ErrorText(
      'Beacon code expired',
      Icons.bluetooth_disabled,
      'Stay near the beacon for a few seconds and try again.',
    ),
    'BEACON_UNKNOWN': ErrorText(
      'Unknown beacon',
      Icons.bluetooth_disabled,
      'This beacon is not registered. Use a campus beacon.',
    ),
    'BEACON_MISMATCH': ErrorText(
      'Beacon changed',
      Icons.bluetooth_disabled,
      'Stay near the same beacon during verification.',
    ),
    'MOCK_LOCATION': ErrorText(
      'Fake location detected',
      Icons.wrong_location_outlined,
      'Turn off any mock-location / fake GPS app.',
    ),
    'OUTSIDE_CAMPUS': ErrorText(
      'Outside campus',
      Icons.wrong_location_outlined,
      'Attendance can only be marked inside the campus.',
    ),
    'LOCATION_REQUIRED': ErrorText(
      'Location needed',
      Icons.location_off_outlined,
      'Turn on GPS (Location) and allow the app to use it.',
    ),
    'DEVICE_MISMATCH': ErrorText(
      'Unregistered phone',
      Icons.phonelink_erase,
      'Use the phone registered to your account, or ask the admin to reset it.',
    ),
    'DEVICE_NOT_REGISTERED': ErrorText(
      'Phone not registered',
      Icons.phonelink_lock,
      'Bind this phone from the setup screen first.',
    ),
    'EMULATOR_NOT_ALLOWED': ErrorText('Emulator not allowed', Icons.computer, null),
    'CHALLENGE_EXPIRED': ErrorText(
      'Verification timed out',
      Icons.timer_off_outlined,
      'Complete the face check within two minutes.',
    ),
    'CHALLENGE_USED': ErrorText('Please start again', Icons.replay_rounded, null),
    'CHALLENGE_INVALID': ErrorText('Please start again', Icons.replay_rounded, null),
    'ALREADY_CHECKED_IN': ErrorText('Already checked in', Icons.event_available_outlined, null),
    'ALREADY_CHECKED_OUT': ErrorText('Already checked out', Icons.event_available_outlined, null),
    'NOT_CHECKED_IN': ErrorText('Not checked in yet', Icons.event_busy_outlined, null),
    'DAY_LOCKED': ErrorText('Marked by admin', Icons.lock_outline_rounded, null),
    'FACE_NOT_ENROLLED': ErrorText('Face not enrolled', Icons.face_outlined, null),
    'FACE_REENROLL_REQUIRED': ErrorText(
      'Enroll your face again',
      Icons.face_retouching_natural,
      'The app was updated. Ask the administrator to reset your face, then enroll again.',
    ),
    'FACE_NOT_APPROVED': ErrorText(
      'Awaiting approval',
      Icons.hourglass_top_rounded,
      'Ask the administrator to approve your face enrollment.',
    ),
    'FACE_DUPLICATE': ErrorText(
      'Face already registered',
      Icons.people_alt_outlined,
      'This face is enrolled for another staff member.',
    ),
    'ACCOUNT_PENDING': ErrorText('Awaiting approval', Icons.hourglass_top_rounded, null),
    'ACCOUNT_DISABLED': ErrorText('Account disabled', Icons.block, null),
    'NETWORK_ERROR': ErrorText(
      'No connection',
      Icons.wifi_off_rounded,
      'Check your mobile data or Wi-Fi.',
    ),
    'TIMEOUT': ErrorText(
      'Server is waking up',
      Icons.hourglass_bottom_rounded,
      'Wait a few seconds and try again.',
    ),
  };
}
