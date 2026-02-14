import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Beacon service implementing manual iBeacon parsing using flutter_blue_plus.
class BeaconService extends ChangeNotifier {
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _scanning = false;

  // Provided beacon identifiers (from user)
  static const String beaconUuid = 'fda50693-a4e2-4fb1-afcf-c6eb07647825';
  static const int beaconMajor = 10011;
  static const int beaconMinor = 19641;

  bool _isInside = false;
  bool get isInside => _isInside;

  DateTime? lastEnter;
  DateTime? lastExit;

  // Track the last time we saw the beacon to handle "exit" logic
  DateTime? _lastSeen;
  Timer? _exitTimer;

  /// Start scanning for the configured beacon. Call this from your app init.
  Future<void> startScanning() async {
    if (_scanning) return;

    // ✅ Ensure permissions are granted BEFORE scanning
    final ok = await _ensurePermissions();
    if (!ok) {
      debugPrint('Beacon scan blocked: permissions not granted.');
      return;
    }

    // ✅ Ensure Bluetooth is ON
    try {
      // Wait a moment for bluetooth state to be ready
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        debugPrint('Beacon scan blocked: Bluetooth is OFF.');
        return;
      }
    } catch (e) {
      debugPrint('Bluetooth state check failed: $e');
    }

    try {
      await FlutterBluePlus.startScan(
        timeout: null, // continuous scanning
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('Beacon scan failed: $e');
      return;
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (e) => debugPrint('Beacon scan error: $e'),
    );

    _scanning = true;
    _startExitCheckTimer();
  }

  void stopScanning() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _exitTimer?.cancel();
    _exitTimer = null;
    _scanning = false;
  }

  /// ✅ Returns true only if permissions granted
  Future<bool> _ensurePermissions() async {
    // Android 12+ needs BLUETOOTH_SCAN/CONNECT at runtime
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      // Many BLE scan libs still require location on Android for scan results
      Permission.locationWhenInUse,
      // (Optional fallback for older Android)
      Permission.bluetooth,
    ].request();

    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

    // We require scan+connect, and location (safer for beacon detection)
    return scanOk && connectOk && locOk;
  }

  void _onScanResults(List<ScanResult> results) {
    bool found = false;

    for (final result in results) {
      if (_isTargetBeacon(result)) {
        found = true;
        _lastSeen = DateTime.now();
        break;
      }
    }

    if (found && !_isInside) {
      _isInside = true;
      lastEnter = DateTime.now();
      notifyListeners();
    }
  }

  void _startExitCheckTimer() {
    _exitTimer?.cancel();
    _exitTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isInside && _lastSeen != null) {
        if (DateTime.now().difference(_lastSeen!) >
            const Duration(seconds: 10)) {
          _isInside = false;
          lastExit = DateTime.now();
          notifyListeners();
        }
      }
    });
  }

  bool _isTargetBeacon(ScanResult result) {
    // iBeacon Manufacturer ID is 0x004C (Apple)
    final manufacturerData = result.advertisementData.manufacturerData;
    if (!manufacturerData.containsKey(0x004C)) return false;

    final data = manufacturerData[0x004C]!;
    if (data.length < 23) return false;
    if (data[0] != 0x02 || data[1] != 0x15) return false;

    // ✅ Parse UUID correctly (NO random hyphens)
    final uuidBytes = data.sublist(2, 18);
    final hex = uuidBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final formattedUuid =
        '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';

    if (formattedUuid.toLowerCase() != beaconUuid.toLowerCase()) return false;

    final major = (data[18] << 8) + data[19];
    if (major != beaconMajor) return false;

    final minor = (data[20] << 8) + data[21];
    if (minor != beaconMinor) return false;

    return true;
  }

  // For testing: fallback to mock toggle if needed
  void toggleMock() {
    if (_isInside) {
      _isInside = false;
      lastExit = DateTime.now();
    } else {
      _isInside = true;
      lastEnter = DateTime.now();
    }
    notifyListeners();
  }
}
