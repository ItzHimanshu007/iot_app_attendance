import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';

// ── Token extraction ──────────────────────────────────────────────────────────

String? extractAttendanceToken(String deviceName) {
  const prefix = 'SCA_';
  if (deviceName.startsWith(prefix) && deviceName.length > prefix.length) {
    return deviceName.substring(prefix.length);
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// BLE Diagnostic Screen
//
// LOGGING: Uses print() — NOT dart:developer log().
// dart:developer is compiled away in release builds and produces zero output.
// print() always appears in: adb logcat | Select-String "flutter"
// ─────────────────────────────────────────────────────────────────────────────

class BleScannerScreen extends StatefulWidget {
  const BleScannerScreen({super.key});

  @override
  State<BleScannerScreen> createState() => _BleScannerScreenState();
}

class _BleScannerScreenState extends State<BleScannerScreen> {

  // ── Diagnostic state — ALL shown in UI table ──────────────────────────────
  String _dBtSupported   = '...';
  String _dAdapterState  = '...';
  String _dAndroidSdk    = '...';
  String _dScanPerm      = '...';
  String _dConnectPerm   = '...';
  String _dLocationPerm  = '...';
  String _dLocServices   = '...';
  String _dScanCalled    = 'NO';
  String _dScanResult    = '...';
  String _dIsScanning    = 'NO';
  int    _dCallbacks     = 0;
  int    _dTotalResults  = 0;

  // ── Scan results — ZERO filtering ────────────────────────────────────────
  final Map<String, Map<String, dynamic>> _devices = {};

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;
  Timer? _uiTick;

  @override
  void initState() {
    super.initState();
    print('[BLE] Screen Init');
    _uiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _boot();
  }

  @override
  void dispose() {
    print('[BLE] Screen Disposed — calling stopScan');
    _uiTick?.cancel();
    _scanSub?.cancel();
    _isScanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Boot sequence — each step logged and shown in table
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _boot() async {
    // Step 1 — BT supported?
    try {
      final supported = await FlutterBluePlus.isSupported;
      _dBtSupported = supported ? 'TRUE ✅' : 'FALSE ❌';
      print('[BLE] isSupported=$supported');
    } catch (e) {
      _dBtSupported = 'ERROR: $e';
      print('[BLE] isSupported threw: $e');
    }
    _setState();

    // Step 2 — Android version
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _dAndroidSdk = 'SDK ${info.version.sdkInt}';
      print('[BLE] Android SDK=${info.version.sdkInt}');
    } catch (e) {
      _dAndroidSdk = 'ERROR: $e';
      print('[BLE] androidInfo threw: $e');
    }
    _setState();

    // Step 3 — Adapter state WITH TIMEOUT
    // IMPORTANT: adapterState.first can hang on some Android versions.
    // Always use a timeout.
    try {
      final state = await FlutterBluePlus.adapterState
          .first
          .timeout(const Duration(seconds: 4));
      _dAdapterState = state.toString();
      print('[BLE] Adapter State = $state');
    } on TimeoutException {
      _dAdapterState = 'TIMEOUT (stream hung)';
      print('[BLE] ERROR: adapterState.first timed out after 4s');
    } catch (e) {
      _dAdapterState = 'ERROR: $e';
      print('[BLE] adapterState threw: $e');
    }
    _setState();

    // Step 4 — Permissions
    print('[BLE] Requesting Permissions');
    try {
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final scan    = results[Permission.bluetoothScan];
      final connect = results[Permission.bluetoothConnect];
      final loc     = results[Permission.locationWhenInUse];

      _dScanPerm     = '${scan?.name ?? "null"} ${scan?.isGranted == true ? "✅" : "❌"}';
      _dConnectPerm  = '${connect?.name ?? "null"} ${connect?.isGranted == true ? "✅" : "❌"}';
      _dLocationPerm = '${loc?.name ?? "null"} ${loc?.isGranted == true ? "✅" : "❌"}';

      print('[BLE] Permissions Requested');
      print('[BLE] scan=$scan connect=$connect location=$loc');
    } catch (e) {
      _dScanPerm = 'ERROR: $e';
      print('[BLE] Permission request threw: $e');
    }
    _setState();

    // Step 5 — Location Services
    try {
      final enabled = await Permission.locationWhenInUse.serviceStatus
          .timeout(const Duration(seconds: 3))
          .then((s) => s.isEnabled);
      _dLocServices = enabled ? 'ON ✅' : 'OFF ❌ — turn ON in Quick Settings';
      print('[BLE] Location Services enabled=$enabled');
    } catch (e) {
      _dLocServices = 'CHECK FAILED: $e';
      print('[BLE] locationServiceStatus threw: $e');
    }
    _setState();

    // Step 6 — Start scan
    await _startScan();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Scan
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _startScan() async {
    setState(() {
      _dScanCalled  = 'YES';
      _dScanResult  = 'PENDING...';
      _dCallbacks   = 0;
      _dTotalResults = 0;
      _devices.clear();
    });

    print('[BLE] startScan() called');

    // Subscribe to isScanning BEFORE startScan
    _isScanSub?.cancel();
    _isScanSub = FlutterBluePlus.isScanning.listen((v) {
      _dIsScanning = v ? 'YES ✅' : 'NO';
      print('[BLE] isScanning=$v');
      _setState();
    });

    // Subscribe to scanResults BEFORE startScan — NO FILTER
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen(
      (results) {
        _dCallbacks++;
        _dTotalResults += results.length;
        print('[BLE] scanResults callback fired  count=${results.length}  total=$_dTotalResults  cb#=$_dCallbacks');

        for (final r in results) {
          final id          = r.device.remoteId.str;
          final platName    = r.device.platformName;
          final advName     = r.advertisementData.advName;
          final rssi        = r.rssi;

          print('[BLE RAW] id=$id  platName="$platName"  advName="$advName"  rssi=$rssi');

          _devices[id] = {
            'id'       : id,
            'platName' : platName,
            'advName'  : advName,
            'rssi'     : rssi,
            'ts'       : DateTime.now(),
          };
        }
        _setState();
      },
      onError: (e) {
        _dScanResult = 'STREAM ERROR: $e';
        print('[BLE] scanResults stream error: $e');
        _setState();
      },
    );

    // Call startScan — catch ALL exceptions
    try {
      print('[BLE] Calling FlutterBluePlus.startScan(androidUsesFineLocation: true)');
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 30),
        androidUsesFineLocation: true,
      );
      _dScanResult = 'STARTED ✅';
      print('[BLE] startScan() returned without exception');
    } catch (e) {
      _dScanResult = 'FAILED: $e';
      print('[BLE] startScan() THREW: $e');
    }
    _setState();

    // After 5s with no callbacks, log a warning
    Future.delayed(const Duration(seconds: 5), () {
      if (_dCallbacks == 0) {
        print('[BLE ERROR] scanResults callback never fired after 5s  isScanning=$_dIsScanning');
      }
    });
  }

  Future<void> _rescan() async {
    print('[BLE] User triggered rescan');
    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 500));
    await _boot();
  }

  void _setState() {
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) => (b['rssi'] as int).compareTo(a['rssi'] as int));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('BLE Diagnostic'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy diagnostics',
            onPressed: _copyDiag,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan',
            onPressed: _rescan,
          ),
          if (_dIsScanning == 'YES ✅')
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Diagnostic Table ────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DIAGNOSTIC STATE',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textSecondary, letterSpacing: 1)),
                const SizedBox(height: 8),
                _diagTable([
                  ['Bluetooth Supported',   _dBtSupported],
                  ['Bluetooth Adapter',     _dAdapterState],
                  ['Android SDK',           _dAndroidSdk],
                  ['Scan Permission',       _dScanPerm],
                  ['Connect Permission',    _dConnectPerm],
                  ['Location Permission',   _dLocationPerm],
                  ['Location Services',     _dLocServices],
                  ['startScan() called',    _dScanCalled],
                  ['startScan() result',    _dScanResult],
                  ['Scanning',             _dIsScanning],
                  ['Callbacks fired',       '$_dCallbacks'],
                  ['Results received',      '$_dTotalResults'],
                  ['Devices in list',       '${devices.length}'],
                ]),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Device list ─────────────────────────────────────────────────
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bluetooth_searching_rounded,
                              size: 56, color: Colors.grey.withValues(alpha: 0.35)),
                          const SizedBox(height: 12),
                          Text('No BLE devices found yet',
                              style: AppTypography.titleMedium,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text(
                            'Check the table above.\n'
                            'All rows should show ✅ or a number.\n'
                            'Any ❌ row is the root cause.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: devices.length > 20 ? 20 : devices.length,
                    itemBuilder: (ctx, i) {
                      final d = devices[i];
                      final bestName = (d['advName'] as String).isNotEmpty
                          ? d['advName'] as String
                          : (d['platName'] as String).isNotEmpty
                              ? d['platName'] as String
                              : '(no name)';
                      final isSca = bestName.startsWith('SCA_');
                      final rssi = d['rssi'] as int;
                      final rssiColor = rssi >= -55
                          ? AppColors.success
                          : rssi >= -70 ? AppColors.warning : AppColors.error;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: isSca
                              ? BorderSide(
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                  width: 1.5)
                              : BorderSide(color: AppColors.divider),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isSca
                                        ? Icons.sensors_rounded
                                        : Icons.bluetooth_rounded,
                                    color: isSca
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(bestName,
                                        style: AppTypography.titleSmall.copyWith(
                                          color: isSca ? AppColors.primary : null,
                                        )),
                                  ),
                                  Text('$rssi dBm',
                                      style: AppTypography.labelMedium
                                          .copyWith(color: rssiColor)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'platName="${d['platName']}"  '
                                'advName="${d['advName']}"\n'
                                'id=${d['id']}',
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    height: 1.5),
                              ),
                              if (isSca) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: AppColors.success
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    '🔑 Token: ${extractAttendanceToken(bestName)}',
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.success),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _diagTable(List<List<String>> rows) {
    return Column(
      children: rows.map((row) {
        final key = row[0];
        final val = row[1];
        final isIssue = val.contains('❌') || val.contains('FAILED') ||
            val.contains('ERROR') || val.contains('TIMEOUT') ||
            val.contains('DENIED');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: Text(key,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.black54)),
              ),
              Expanded(
                child: Text(
                  val,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isIssue ? AppColors.error : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _copyDiag() {
    final text = '''
BLE Diagnostic Report
=====================
Bluetooth Supported:  $_dBtSupported
Bluetooth Adapter:    $_dAdapterState
Android SDK:          $_dAndroidSdk
Scan Permission:      $_dScanPerm
Connect Permission:   $_dConnectPerm
Location Permission:  $_dLocationPerm
Location Services:    $_dLocServices
startScan() called:   $_dScanCalled
startScan() result:   $_dScanResult
Scanning:             $_dIsScanning
Callbacks fired:      $_dCallbacks
Results received:     $_dTotalResults
Devices in list:      ${_devices.length}
''';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard')),
    );
    print('[BLE] Diagnostics copied:\n$text');
  }
}
