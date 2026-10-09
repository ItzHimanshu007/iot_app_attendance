import 'dart:convert';

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Stable identity of this phone, used to bind it to one staff account.
///
/// The fingerprint is a SHA-256 of Android's `ANDROID_ID` (unique per phone,
/// per app signing key and per user, and stable across reinstalls) plus brand/model.
/// The original student app hashed `Build.ID` instead, which is identical on
/// every phone of the same model and ROM, so two staff members with the same
/// phone would have collided.
class DeviceIdentity {
  const DeviceIdentity({
    required this.fingerprint,
    required this.model,
    required this.manufacturer,
    required this.osVersion,
    required this.appVersion,
    required this.isPhysicalDevice,
  });

  final String fingerprint;
  final String model;
  final String manufacturer;
  final String osVersion;
  final String appVersion;
  final bool isPhysicalDevice;

  Map<String, dynamic> toRegisterJson() => {
    'device_fingerprint': fingerprint,
    'device_model': model,
    'device_manufacturer': manufacturer,
    'os_version': osVersion,
    'app_version': appVersion,
    'is_physical_device': isPhysicalDevice,
  };

  static Future<DeviceIdentity> load() async {
    final info = await DeviceInfoPlugin().androidInfo;
    final androidId = await const AndroidId().getId();
    if (androidId == null || androidId.isEmpty) {
      throw Exception('Could not read this phone\'s device ID.');
    }
    final package = await PackageInfo.fromPlatform();
    final raw = 'staff-attendance|$androidId|${info.brand}|${info.model}';
    return DeviceIdentity(
      fingerprint: sha256.convert(utf8.encode(raw)).toString(),
      model: info.model,
      manufacturer: info.manufacturer,
      osVersion: 'Android ${info.version.release} (SDK ${info.version.sdkInt})',
      appVersion: '${package.version}+${package.buildNumber}',
      isPhysicalDevice: info.isPhysicalDevice,
    );
  }
}

final deviceIdentityProvider = FutureProvider<DeviceIdentity>((ref) => DeviceIdentity.load());
