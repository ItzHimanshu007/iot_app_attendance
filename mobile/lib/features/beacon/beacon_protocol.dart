import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/config.dart';

/// One decoded ESP32 advertisement.
class BeaconAdvertisement {
  const BeaconAdvertisement({
    required this.beaconId,
    required this.token,
    required this.rssi,
    required this.name,
    required this.seenAt,
  });

  final String beaconId;
  final String token;
  final int rssi;
  final String name;
  final DateTime seenAt;

  Map<String, dynamic> toJson() => {'beacon_id': beaconId, 'token': token, 'rssi': rssi};

  /// Rough signal quality for the UI.
  String get signalLabel => rssi >= -65
      ? 'Excellent'
      : rssi >= -75
      ? 'Good'
      : rssi >= -85
      ? 'Fair'
      : 'Weak';
}

/// Protocol V3 decoder — byte layout unchanged from the student system:
///
///   manufacturer data (company 0xFFFF):
///     [0]      0x03  protocol version
///     [1]      0x01  payload type (attendance beacon)
///     [2..9]   8 token bytes        → 16-char lowercase hex
///     [10..25] 16 beacon UUID bytes → "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
class BeaconProtocol {
  BeaconProtocol._();

  static const int companyId = 0xFFFF;
  static const int version = 0x03;
  static const int payloadType = 0x01;
  static const int minLength = 26;

  static BeaconAdvertisement? parse(ScanResult result) {
    final manufacturer = result.advertisementData.manufacturerData;
    if (manufacturer.isEmpty) return null;
    final bytes = manufacturer[companyId] ?? manufacturer.values.first;
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
    return parseBytes(bytes, rssi: result.rssi, name: name, seenAt: result.timeStamp);
  }

  static BeaconAdvertisement? parseBytes(
    List<int> bytes, {
    required int rssi,
    String name = '',
    DateTime? seenAt,
  }) {
    if (bytes.length < minLength || bytes[0] != version || bytes[1] != payloadType) return null;
    final token = _hex(bytes.sublist(2, 10));
    final uuid = _hex(bytes.sublist(10, 26));
    final beaconId =
        '${uuid.substring(0, 8)}-${uuid.substring(8, 12)}-'
        '${uuid.substring(12, 16)}-${uuid.substring(16, 20)}-${uuid.substring(20)}';
    return BeaconAdvertisement(
      beaconId: beaconId,
      token: token,
      rssi: rssi,
      name: name.isEmpty ? '${AppConfig.beaconNamePrefix}beacon' : name,
      seenAt: seenAt ?? DateTime.now(),
    );
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0')).join();
}
