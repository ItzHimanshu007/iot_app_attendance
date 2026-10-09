import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config.dart';
import '../models/ble_models.dart';
import 'ble_payload_parser.dart';

/// Abstract interface for BLE scanning — enables mock injection in tests.
abstract class BleScannerInterface {
  /// Whether Bluetooth hardware is currently enabled.
  Future<bool> isBluetoothEnabled();

  /// Request all BLE-related permissions.
  /// Returns true if all required permissions are granted.
  Future<bool> requestPermissions();

  /// Check current permission status without requesting.
  Future<BlePermissionStatus> checkPermissions();

  /// Start a BLE scan. Results stream via [scanResults].
  /// Automatically stops after [duration].
  Future<void> startScan({Duration? duration});

  /// Stop any active BLE scan.
  Future<void> stopScan();

  /// Stream of parsed SCA beacon advertisements.
  /// Only emits beacons that pass protocol validation.
  Stream<List<AttendanceSessionAdvertisement>> get scanResults;

  /// Stream of scanning state (true = actively scanning).
  Stream<bool> get isScanning;

  /// Dispose resources.
  void dispose();
}

/// Permission status model.
class BlePermissionStatus {
  const BlePermissionStatus({
    required this.bluetoothScan,
    required this.bluetoothConnect,
    required this.location,
  });

  final bool bluetoothScan;
  final bool bluetoothConnect;
  final bool location;

  bool get allGranted => bluetoothScan && bluetoothConnect;
  bool get isPermanentlyDenied => false; // set by real impl
}

// ── Real BLE Scanner ─────────────────────────────────────────────────────────

/// Production BLE scanner using flutter_blue_plus.
///
/// Filters devices by SCA- prefix or manufacturer data, parses manufacturer
/// data (Protocol V2 / V3), deduplicates by classroomId with a 10-second TTL.
///
/// Improvements over original:
///   • AndroidScanMode.lowLatency set explicitly — 100% duty cycle (already
///     the default in FBP ≥ 1.36.8, but explicit for documentation/safety).
///   • 10-second TTL on _found entries — stale beacons are pruned each callback.
///   • Safe manufacturer lookup — prefers 0xFFFF company ID, falls back to first.
///   • API ≤ 30 — ACCESS_FINE_LOCATION is treated as a hard requirement.
class RealBleScanner implements BleScannerInterface {
  RealBleScanner({BlePayloadParser? parser})
      : _parser = parser ?? const BlePayloadParser();

  final BlePayloadParser _parser;

  // Deduplicated map: classroomId → latest advertisement
  final Map<String, AttendanceSessionAdvertisement> _found = {};

  // ── TTL constant ────────────────────────────────────────────────────────────
  static const int _beaconTtlMs = 10000; // 10 seconds

  @override
  Future<bool> isBluetoothEnabled() async {
    // IMPORTANT: adapterState.first with no timeout can hang indefinitely
    // on some Android devices/versions. Always use a timeout.
    try {
      final state = await FlutterBluePlus.adapterState
          .first
          .timeout(const Duration(seconds: 3));
      print('[SESSION] isBluetoothEnabled: adapterState=$state');
      return state == BluetoothAdapterState.on;
    } on TimeoutException {
      print('[SESSION] isBluetoothEnabled: adapterState.first TIMED OUT — assuming ON');
      // Assume on; startScan() will fail fast if the adapter is really off.
      return true;
    } catch (e) {
      print('[SESSION] isBluetoothEnabled: error=$e');
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // Location is required for BLE scanning on Android when the
      // neverForLocation manifest flag is NOT set (our manifest omits it).
      Permission.locationWhenInUse,
    ].request();

    final scanOk     = statuses[Permission.bluetoothScan]    == PermissionStatus.granted;
    final connectOk  = statuses[Permission.bluetoothConnect] == PermissionStatus.granted;
    final locationOk = statuses[Permission.locationWhenInUse] == PermissionStatus.granted;

    print('[BLE PROD] requestPermissions scan=$scanOk connect=$connectOk '
        'location=$locationOk');

    // On Android API ≤ 30, ACCESS_FINE_LOCATION is mandatory for BLE scanning
    // (legacy permission model — BLUETOOTH_SCAN does not exist yet).
    // On API 31+ (Android 12+), BLUETOOTH_SCAN is sufficient.
    bool locationRequired = false;
    try {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      locationRequired = sdkInt <= 30;
      if (locationRequired) {
        print('[BLE PROD] Android API $sdkInt ≤ 30 — location is mandatory for BLE');
      }
    } catch (e) {
      // If device info is unavailable, treat location as best-effort.
      print('[BLE PROD] Could not determine Android SDK: $e');
    }

    if (locationRequired) {
      return scanOk && connectOk && locationOk;
    }
    return scanOk && connectOk;
  }

  @override
  Future<BlePermissionStatus> checkPermissions() async {
    final scan = await Permission.bluetoothScan.status;
    final connect = await Permission.bluetoothConnect.status;
    final location = await Permission.location.status;

    return BlePermissionStatus(
      bluetoothScan: scan.isGranted,
      bluetoothConnect: connect.isGranted,
      location: location.isGranted,
    );
  }

  @override
  Future<void> startScan({Duration? duration}) async {
    _found.clear();
    print('[BLE PROD] startScan() called — ScanMode.lowLatency, no timeout, '
        'caller controls stop via Timer');

    // CONFIRMED BUG FIX: FlutterBluePlus.startScan(timeout: T) returns in ~40ms
    // (NOT T) on Android. Passing a timeout causes BleController to cancel its
    // subscription 40ms after starting, while the native scan keeps running
    // for T seconds with no listener. Fix: omit timeout entirely so the native
    // scan runs indefinitely. BleController's Dart Timer calls stopScan() after
    // bleScanDuration to end the window cleanly.
    //
    // AndroidScanMode.lowLatency = SCAN_MODE_LOW_LATENCY (Android) = 100% duty cycle.
    // Default (BALANCED) only scans ~50% of the time, which halves detection
    // probability in a fixed scan window — critical at range where packets are
    // already sparse.
    //
    // NOTE: In flutter_blue_plus ≥ 1.36.8, AndroidScanMode.lowLatency is already
    // the DEFAULT value for androidScanMode. We set it explicitly here so that
    // the intent is documented and cannot regress if the FBP default changes.
    await FlutterBluePlus.startScan(
      androidUsesFineLocation: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );

    print('[BLE PROD] startScan() returned — native scan running with LOW_LATENCY mode');
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Stream<List<AttendanceSessionAdvertisement>> get scanResults {
    // IMPORTANT: Use scanResults, NOT onScanResults.
    // onScanResults only emits NEW results since the last callback.
    // scanResults emits the FULL cumulative list on every advertisement,
    // which is far more reliable on Android.
    return FlutterBluePlus.scanResults.map((results) {
      final int totalReceived = results.length;
      int accepted = 0;
      int rejected = 0;

      if (kDebugMode) {
        debugPrint('[SESSION] ═══════════════════════════════════════════');
        debugPrint('[SESSION] scanResults callback  totalRaw=$totalReceived');
      }

      for (final scanResult in results) {
        final platName    = scanResult.device.platformName;
        final advName     = scanResult.advertisementData.advName;
        final rssi        = scanResult.rssi;
        final id          = scanResult.device.remoteId.str;
        final resolvedName = advName.isNotEmpty ? advName : platName;
        final manufKeys   = scanResult.advertisementData.manufacturerData.keys.toList();

        // Raw advertisement logging — gated behind debug mode to reduce noise
        // in release builds.
        if (kDebugMode) {
          debugPrint('[SESSION RAW] name="$resolvedName" platName="$platName" '
              'advName="$advName" id=$id rssi=$rssi manufKeys=$manufKeys');
        }

        // Parse and log decision
        final parsed = _parser.parse(scanResult);
        if (parsed is BleParseSuccess) {
          final adv = parsed.advertisement;
          accepted++;
          print('[SESSION DECISION] accepted=true '
              'protocolVersion=${adv.protocolVersion} '
              'token=${adv.token} '
              'classroomId=${adv.classroomId} '
              'rssi=${adv.rssi}');
          _found[adv.classroomId] = adv;
        } else if (parsed is BleParseFailure) {
          rejected++;
          // Categorize the reason for structured logcat filtering.
          String category;
          if (parsed.reason.contains('Not an SCA device') ||
              parsed.reason.contains('no manufacturer data')) {
            category = 'non_sca_or_no_data';
          } else if (parsed.reason.contains('manufacturer data') ||
              parsed.reason.contains('payload too short')) {
            category = 'manufacturer_data_missing_or_short';
          } else if (parsed.reason.contains('Token') || parsed.reason.contains('token')) {
            category = 'token_parse_failed';
          } else if (parsed.reason.contains('protocol') || parsed.reason.contains('payload')) {
            category = 'binary_parse_failed';
          } else {
            category = 'filtered_out';
          }

          // Only log non-SCA rejections in debug mode — too noisy otherwise.
          if (kDebugMode || category != 'non_sca_or_no_data') {
            print('[SESSION DECISION] accepted=false reason=$category '
                'name="$resolvedName" detail="${parsed.reason}"');
          }
        }
      }

      // ── TTL pruning: remove beacons older than _beaconTtlMs ─────────────────
      // Keeps the _found map fresh so RSSI readings reflect the current
      // RF environment. Beacons that go silent (ESP32 powered off, user moved
      // away) are automatically removed after 10 seconds.
      //
      // NOTE: This does NOT affect attendance SUBMISSION validity, which is
      // determined by the backend session lookup in AttendanceController.
      final now = DateTime.now();
      _found.removeWhere((_, adv) {
        final ageMs = now.difference(adv.scannedAt).inMilliseconds;
        if (ageMs > _beaconTtlMs) {
          print('[SESSION TTL] pruned classroomId=${adv.classroomId} age=${ageMs}ms');
          return true;
        }
        return false;
      });

      // Sort by RSSI descending so the strongest beacon is first.
      final allFound = _found.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));

      print('[SESSION] accepted=$accepted  rejected=$rejected  '
          'found=${allFound.length}  raw=$totalReceived');

      return allFound;
    });
  }

  @override
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
  }
}

// ── Mock BLE Scanner ─────────────────────────────────────────────────────────

/// Mock BLE scanner for unit tests and UI development without hardware.
///
/// Emits configurable fake advertisements on a timer.
class MockBleScanner implements BleScannerInterface {
  MockBleScanner({
    this.simulatedBeacons = const [],
    this.scanDelay = const Duration(milliseconds: 500),
    this.bluetoothEnabled = true,
    this.permissionsGranted = true,
  });

  final List<AttendanceSessionAdvertisement> simulatedBeacons;
  final Duration scanDelay;
  final bool bluetoothEnabled;
  final bool permissionsGranted;

  bool _scanning = false;

  // Simulated beacon defaults
  static List<AttendanceSessionAdvertisement> get defaultBeacons => [
        AttendanceSessionAdvertisement(
          classroomId: 'room-101',
          token: 'a3f1b2c4d5e6f789',
          protocolVersion: BleProtocol.protocolVersion,
          payloadType: BleProtocol.payloadTypeAttendance,
          rssi: -62,
          deviceName: 'SCA-room-101',
          scannedAt: DateTime.now(),
        ),
        AttendanceSessionAdvertisement(
          classroomId: 'lab-202',
          token: 'b4c5d6e7f8091a2b',
          protocolVersion: BleProtocol.protocolVersion,
          payloadType: BleProtocol.payloadTypeAttendance,
          rssi: -82, // updated to reflect new -85 threshold environment
          deviceName: 'SCA-lab-202',
          scannedAt: DateTime.now(),
        ),
      ];

  @override
  Future<bool> isBluetoothEnabled() async => bluetoothEnabled;

  @override
  Future<bool> requestPermissions() async => permissionsGranted;

  @override
  Future<BlePermissionStatus> checkPermissions() async =>
      BlePermissionStatus(
        bluetoothScan: permissionsGranted,
        bluetoothConnect: permissionsGranted,
        location: permissionsGranted,
      );

  @override
  Future<void> startScan({Duration? duration}) async {
    _scanning = true;
    await Future.delayed(scanDelay);
  }

  @override
  Future<void> stopScan() async {
    _scanning = false;
  }

  @override
  Stream<List<AttendanceSessionAdvertisement>> get scanResults async* {
    if (!_scanning) return;
    await Future.delayed(scanDelay);
    yield simulatedBeacons.isNotEmpty ? simulatedBeacons : defaultBeacons;
  }

  @override
  Stream<bool> get isScanning =>
      Stream.value(_scanning).asBroadcastStream();

  @override
  void dispose() {}
}
