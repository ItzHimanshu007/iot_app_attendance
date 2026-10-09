import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../models/ble_models.dart';
import '../services/ble_scanner.dart';

// ── BLE State ─────────────────────────────────────────────────────────────────

/// All possible BLE states — represented as a sealed hierarchy.
sealed class BleState {
  const BleState();
}

/// Initial state — not yet checked anything.
class BleIdle extends BleState {
  const BleIdle();
}

/// Permissions being requested or Bluetooth state being checked.
class BleCheckingPrerequisites extends BleState {
  const BleCheckingPrerequisites();
}

/// Bluetooth hardware is off.
class BleDisabled extends BleState {
  const BleDisabled();
}

/// Permissions denied by user.
class BlePermissionDenied extends BleState {
  const BlePermissionDenied({this.isPermanent = false});
  final bool isPermanent;
}

/// Actively scanning for SCA beacons.
class BleScanning extends BleState {
  const BleScanning({this.advertisements = const [], this.attempt = 1});
  final List<AttendanceSessionAdvertisement> advertisements;
  /// Current scan attempt (1-based). Displayed in diagnostic logs.
  final int attempt;
}

/// Scan completed — may have found beacons or none.
class BleScanComplete extends BleState {
  const BleScanComplete({required this.advertisements});
  final List<AttendanceSessionAdvertisement> advertisements;

  bool get hasResults => advertisements.isNotEmpty;

  /// Best in-range beacon (highest RSSI that meets threshold).
  AttendanceSessionAdvertisement? get bestBeacon =>
      advertisements.where((a) => a.isInRange).isNotEmpty
          ? (advertisements.where((a) => a.isInRange).toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi)))
              .first
          : null;
}

/// An error occurred during scanning.
class BleError extends BleState {
  const BleError(this.message);
  final String message;
}

// ── BLE Controller ────────────────────────────────────────────────────────────

/// BLE controller — manages the full scan lifecycle with auto-retry.
///
/// Transitions:
///   idle → checkingPrerequisites → [disabled | permissionDenied | scanning]
///   scanning → scanComplete | error
///   scanning (empty, attempt < max) → scanning (retry)
///   Any state → idle (via reset)
///
/// Auto-retry:
///   If the first scan window completes with zero beacons found, the controller
///   automatically starts a second scan window without user interaction.
///   Maximum attempts: [_maxScanAttempts] = 2. Never creates an infinite loop.
class BleController extends StateNotifier<BleState> {
  BleController(this._scanner) : super(const BleIdle()) {
    _listenToAdapterState();
  }

  final BleScannerInterface _scanner;

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<AttendanceSessionAdvertisement>>? _resultsSub;
  Timer? _refreshTimer;
  Timer? _scanStopTimer;    // Controls scan window duration via Dart Timer
  DateTime? _scanStartTime; // For elapsed-time diagnostics

  // ── Auto-retry state ────────────────────────────────────────────────────────
  int _scanAttempt = 0;
  static const int _maxScanAttempts = 2;

  // ── Adapter state listener ─────────────────────────────────────────────────

  void _listenToAdapterState() {
    // Only wire up for real scanner — MockBleScanner skips this
    if (_scanner is! RealBleScanner) return;

    _adapterSub = FlutterBluePlus.adapterState.listen((adapterState) {
      if (adapterState == BluetoothAdapterState.off) {
        if (state is BleScanning) {
          _cancelScan();
          state = const BleDisabled();
        }
      }
    });
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Check Bluetooth + permissions, then start scanning.
  Future<void> startScan() async {
    if (state is BleScanning) {
      print('[SESSION STATE] startScan() called while already scanning — skip');
      return;
    }

    // Reset attempt counter on a fresh user-initiated scan.
    _scanAttempt = 0;

    print('[SESSION STATE] ${state.runtimeType} → BleCheckingPrerequisites');
    state = const BleCheckingPrerequisites();

    // 1. Check Bluetooth — with timeout to prevent hanging
    print('[SESSION] checking isBluetoothEnabled');
    final enabled = await _scanner.isBluetoothEnabled();
    print('[SESSION] isBluetoothEnabled=$enabled');
    if (!enabled) {
      print('[SESSION STATE] BleCheckingPrerequisites → BleDisabled');
      state = const BleDisabled();
      return;
    }

    // 2. Request permissions
    print('[SESSION] requesting permissions');
    final granted = await _scanner.requestPermissions();
    print('[SESSION] permissions granted=$granted');
    if (!granted) {
      print('[SESSION STATE] BleCheckingPrerequisites → BlePermissionDenied');
      state = const BlePermissionDenied();
      return;
    }

    // 3. Ensure no stale scan is running (prevents 'already scanning' errors)
    print('[SESSION] stopping any stale scan before starting');
    await _scanner.stopScan();

    await _startScanAttempt();
  }

  /// Start a single scan attempt (shared by startScan and auto-retry).
  Future<void> _startScanAttempt() async {
    _scanAttempt++;
    print('[SESSION STATE] → BleScanning(attempt=$_scanAttempt)');
    state = BleScanning(advertisements: const [], attempt: _scanAttempt);

    // ── Subscribe BEFORE starting scan ────────────────────────────────────
    //
    // Root cause confirmed (logcat evidence):
    //   FBP.startScan(timeout: T) returns in ~40ms regardless of T.
    //   Awaiting it caused the subscription to be cancelled 40ms in while
    //   the native scan kept running for T seconds with no listener.
    //
    // Fix: subscribe first → start scan (returns immediately) → Dart Timer
    //   fires after bleScanDuration → stopScan() → BleScanComplete.
    // ─────────────────────────────────────────────────────────────────────
    print('[SESSION] subscribing to scanResults BEFORE starting scan (attempt=$_scanAttempt)');
    _resultsSub?.cancel();
    _resultsSub = _scanner.scanResults.listen(
      (adverts) {
        if (adverts.isNotEmpty) {
          print('[SESSION] advertisement received  count=${adverts.length}  attempt=$_scanAttempt');
          for (final a in adverts) {
            print('[SESSION] advertisement:\n'
                '  deviceName=${a.deviceName}\n'
                '  token=${a.token}\n'
                '  rssi=${a.rssi}\n'
                '  isFresh=${a.isFresh}');
          }
        }
        if (state is BleScanning) {
          state = BleScanning(advertisements: adverts, attempt: _scanAttempt);
        }
      },
      onError: (e) {
        print('[SESSION] scanResults stream error: $e');
        state = BleError('Scan error: $e');
      },
    );

    // Fire the native scan (returns immediately — no timeout in FBP call)
    _startScanBackground();

    // Dart Timer owns the scan window. After bleScanDuration:
    //   stopScan() → brief settle → check for retry or complete
    _scheduleScanStop();

    // Periodic UI refresh — re-evaluates freshness of cached advertisements
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      Duration(milliseconds: AppConfig.bleScanRefreshMs),
      (_) => _refreshScan(),
    );
  }

  /// Starts the native BLE scan. Returns quickly (FBP fires and forgets).
  /// Does NOT cancel the subscription — the Timer in [_scheduleScanStop] does.
  void _startScanBackground() async {
    _scanStartTime = DateTime.now();
    try {
      print('[SESSION] scan started (attempt=$_scanAttempt)');
      await _scanner.startScan(); // No duration: returns immediately
      final elapsed = DateTime.now().difference(_scanStartTime!).inMilliseconds;
      print('[SESSION] scan active  elapsed=${elapsed}ms — native scan running, '
          'subscription alive (attempt=$_scanAttempt)');
    } catch (e) {
      print('[SESSION] _startScanBackground: startScan() THREW: $e');
      if (state is BleScanning || state is BleCheckingPrerequisites) {
        state = BleError('Failed to start scan: $e');
      }
    }
    // ← subscription stays alive; _scheduleScanStop() handles teardown
  }

  /// Schedules the end of the scan window.
  ///
  /// After [AppConfig.bleScanDuration]:
  ///   1. Stops the native scan.
  ///   2. Waits 300 ms for any in-flight advertisements.
  ///   3a. If no beacons found AND attempt < [_maxScanAttempts]: auto-retry.
  ///   3b. Otherwise: cancel subscription and transition to BleScanComplete.
  void _scheduleScanStop() {
    _scanStopTimer?.cancel();
    final stopwatch = Stopwatch()..start();
    _scanStopTimer = Timer(AppConfig.bleScanDuration, () async {
      final elapsed = stopwatch.elapsedMilliseconds;
      print('[SESSION] scan window ended  elapsed=${elapsed}ms  attempt=$_scanAttempt');

      _refreshTimer?.cancel();
      _refreshTimer = null;

      print('[SESSION] stopScan called');
      await _scanner.stopScan();

      // Brief settle window: let any in-flight advertisements arrive
      // before we evaluate results.
      await Future.delayed(const Duration(milliseconds: 300));

      final current = state;
      if (current is! BleScanning) {
        // State was changed externally (e.g., Bluetooth turned off).
        _cleanupAfterScan();
        return;
      }

      final ads = current.advertisements;

      // ── Auto-retry logic ─────────────────────────────────────────────────
      if (ads.isEmpty && _scanAttempt < _maxScanAttempts) {
        print('[SESSION] Auto-retry: no beacons found on attempt $_scanAttempt, '
            'starting attempt ${_scanAttempt + 1} of $_maxScanAttempts');
        // Cancel old subscription — _startScanAttempt will re-subscribe.
        await _resultsSub?.cancel();
        _resultsSub = null;
        _scanStopTimer = null;
        // Brief pause before retry to let the BLE stack reset.
        await Future.delayed(const Duration(milliseconds: 200));
        await _startScanAttempt();
        return;
      }

      // ── Final result ─────────────────────────────────────────────────────
      _cleanupAfterScan();

      print('[SESSION] BleScanComplete  devices=${ads.length}  '
          'totalAttempts=$_scanAttempt');
      if (ads.isEmpty) {
        print('[SESSION] session not found  reason=scan complete after '
            '$_scanAttempt attempt(s), zero advertisements accepted');
      } else {
        print('[SESSION] session discovered  token=${ads.first.token}');
      }
      state = BleScanComplete(advertisements: ads);
    });
  }

  void _cleanupAfterScan() {
    _resultsSub?.cancel();
    _resultsSub = null;
    _scanStopTimer = null;
    _scanAttempt = 0;
  }

  /// Stop scanning early and freeze the current results.
  Future<void> stopScan() async {
    _scanStopTimer?.cancel();
    _scanStopTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _resultsSub?.cancel();
    _resultsSub = null;
    _scanAttempt = 0;
    await _scanner.stopScan();
    final current = state;
    if (current is BleScanning) {
      print('[SESSION STATE] BleScanning → BleScanComplete(stopScan called early)');
      state = BleScanComplete(advertisements: current.advertisements);
    }
  }

  /// Reset to idle — clears all results.
  void reset() {
    _scanStopTimer?.cancel();
    _scanStopTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _resultsSub?.cancel();
    _resultsSub = null;
    _scanAttempt = 0;
    _scanner.stopScan();
    print('[SESSION STATE] ${state.runtimeType} → BleIdle (reset)');
    state = const BleIdle();
  }

  /// Restart a completed scan.
  Future<void> rescan() async {
    print('[SESSION] rescan() called');
    _scanStopTimer?.cancel();
    _scanStopTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _resultsSub?.cancel();
    _resultsSub = null;
    _scanAttempt = 0;
    await _scanner.stopScan();
    state = const BleIdle();
    await startScan();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _cancelScan() async {
    _scanStopTimer?.cancel();
    _scanStopTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _resultsSub?.cancel();
    _resultsSub = null;
    _scanAttempt = 0;
    await _scanner.stopScan();
  }

  void _refreshScan() {
    // Re-emit the current advertisement list so the UI stays live.
    // Advertisements are NOT filtered by age here — beacon validity is
    // determined by the backend session check in AttendanceController.
    final current = state;
    if (current is BleScanning) {
      state = BleScanning(
        advertisements: current.advertisements,
        attempt: _scanAttempt,
      );
    }
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _cancelScan();
    _scanner.dispose();
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Provider for the BLE scanner interface.
/// Override in tests with MockBleScanner.
final bleScannerProvider = Provider<BleScannerInterface>((ref) {
  return RealBleScanner();
});

/// BLE controller provider — primary BLE state machine.
final bleControllerProvider =
    StateNotifierProvider<BleController, BleState>((ref) {
  final scanner = ref.watch(bleScannerProvider);
  return BleController(scanner);
});

/// Convenience provider — current advertisements (empty if not scanning/complete).
final bleAdvertisementsProvider =
    Provider<List<AttendanceSessionAdvertisement>>((ref) {
  final state = ref.watch(bleControllerProvider);
  return switch (state) {
    BleScanning(advertisements: final ads) => ads,
    BleScanComplete(advertisements: final ads) => ads,
    _ => const [],
  };
});

/// Convenience provider — best in-range beacon or null.
final bestBeaconProvider =
    Provider<AttendanceSessionAdvertisement?>((ref) {
  final state = ref.watch(bleControllerProvider);
  if (state is BleScanComplete) return state.bestBeacon;
  return null;
});
