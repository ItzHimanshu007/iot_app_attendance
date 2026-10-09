import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config.dart';
import 'beacon_protocol.dart';

enum BeaconStatus {
  idle,
  starting,
  scanning,
  bluetoothOff,
  permissionDenied,
  locationOff,
  unsupported,
  error,
}

class BeaconState {
  const BeaconState({this.status = BeaconStatus.idle, this.beacons = const [], this.message});

  final BeaconStatus status;

  /// Beacons currently in range, strongest first.
  final List<BeaconAdvertisement> beacons;
  final String? message;

  BeaconAdvertisement? get nearest => beacons.isEmpty ? null : beacons.first;

  BeaconAdvertisement? byId(String id) {
    for (final b in beacons) {
      if (b.beaconId == id) return b;
    }
    return null;
  }

  BeaconState copyWith({
    BeaconStatus? status,
    List<BeaconAdvertisement>? beacons,
    String? message,
  }) => BeaconState(
    status: status ?? this.status,
    beacons: beacons ?? this.beacons,
    message: message,
  );
}

/// Continuous BLE scan for campus beacons.
///
/// Lessons kept from the student app:
///   * never pass `timeout` to startScan (it returns early on Android) — the
///     scan runs until [stop] is called;
///   * low-latency scan mode (100 % duty cycle);
///   * on Android ≤ 11 location permission is mandatory for BLE scans.
/// New: `continuousUpdates` + `removeIfGone` so RSSI and the rotating token
/// stay fresh and out-of-range beacons disappear.
class BeaconController extends Notifier<BeaconState> {
  StreamSubscription<List<ScanResult>>? _results;
  StreamSubscription<BluetoothAdapterState>? _adapter;

  @override
  BeaconState build() {
    ref.onDispose(() {
      _results?.cancel();
      _adapter?.cancel();
      FlutterBluePlus.stopScan();
    });
    return const BeaconState();
  }

  bool get isRunning =>
      state.status == BeaconStatus.scanning || state.status == BeaconStatus.starting;

  Future<void> start() async {
    if (isRunning) return;
    state = state.copyWith(status: BeaconStatus.starting);

    if (!await FlutterBluePlus.isSupported) {
      state = state.copyWith(
        status: BeaconStatus.unsupported,
        message: 'This phone does not support Bluetooth LE.',
      );
      return;
    }

    if (!await _ensurePermissions()) {
      state = state.copyWith(
        status: BeaconStatus.permissionDenied,
        message: 'Allow "Nearby devices" and "Location" so the app can find the campus beacon.',
      );
      return;
    }

    _adapter ??= FlutterBluePlus.adapterState.listen((s) {
      if (s == BluetoothAdapterState.off && state.status != BeaconStatus.bluetoothOff) {
        _results?.cancel();
        _results = null;
        state = const BeaconState(
          status: BeaconStatus.bluetoothOff,
          message: 'Turn on Bluetooth to find the beacon.',
        );
      } else if (s == BluetoothAdapterState.on && state.status == BeaconStatus.bluetoothOff) {
        start();
      }
    });

    final adapter = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.on);
    if (adapter != BluetoothAdapterState.on) {
      state = const BeaconState(
        status: BeaconStatus.bluetoothOff,
        message: 'Turn on Bluetooth to find the beacon.',
      );
      return;
    }

    await _results?.cancel();
    _results = FlutterBluePlus.scanResults.listen(
      _onResults,
      onError: (Object e) {
        state = state.copyWith(status: BeaconStatus.error, message: e.toString());
      },
    );

    try {
      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: true,
        continuousUpdates: true,
        continuousDivisor: 2,
        removeIfGone: AppConfig.beaconGoneAfter,
      );
      state = state.copyWith(status: BeaconStatus.scanning);
    } catch (e) {
      final text = e.toString().toLowerCase();
      state = state.copyWith(
        status: text.contains('location') ? BeaconStatus.locationOff : BeaconStatus.error,
        message: text.contains('location')
            ? 'Turn on Location (GPS). Android needs it for Bluetooth scanning.'
            : 'Could not start Bluetooth scan: $e',
      );
    }
  }

  Future<void> stop() async {
    await _results?.cancel();
    _results = null;
    await FlutterBluePlus.stopScan();
    state = const BeaconState();
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> turnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {
      // user declined
    }
  }

  void _onResults(List<ScanResult> results) {
    final found = <String, BeaconAdvertisement>{};
    for (final r in results) {
      final adv = BeaconProtocol.parse(r);
      if (adv == null) continue;
      final existing = found[adv.beaconId];
      if (existing == null || adv.seenAt.isAfter(existing.seenAt)) found[adv.beaconId] = adv;
    }
    final list = found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    state = state.copyWith(status: BeaconStatus.scanning, beacons: list);
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    bool granted(Permission p) => statuses[p]?.isGranted ?? false;

    var sdk = 31;
    try {
      sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (e) {
      debugPrint('SDK check failed: $e');
    }
    // Android ≤ 11 has no BLUETOOTH_SCAN permission; location is mandatory.
    if (sdk <= 30) return granted(Permission.locationWhenInUse);
    return granted(Permission.bluetoothScan) && granted(Permission.bluetoothConnect);
  }
}

final beaconControllerProvider = NotifierProvider<BeaconController, BeaconState>(
  BeaconController.new,
);
