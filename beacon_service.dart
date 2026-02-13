
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

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
    
    // Request permissions
    await _ensurePermissions();

    // Start scanning
    // Note: 'services' filter doesn't work well for iBeacons on Android/iOS as they are Manufacturer Data.
    // We scan for everything and filter in the listener.
    try {
      await FlutterBluePlus.startScan(
        timeout: null, // continuous scanning
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('Beacon scan failed (likely simulator): $e');
    }
    
    _scanSubscription = FlutterBluePlus.scanResults.listen(_onScanResults, onError: (e) {
      debugPrint('Beacon scan error: $e');
    });

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

  Future<void> _ensurePermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
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
    // We don't immediately set _isInside to false here because scan results 
    // might be empty for a brief moment even if we are still there. 
    // We use a timer to check for "exit".
  }

  void _startExitCheckTimer() {
    _exitTimer?.cancel();
    _exitTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isInside && _lastSeen != null) {
        // If we haven't seen the beacon for 10 seconds, assume we exited
        if (DateTime.now().difference(_lastSeen!) > const Duration(seconds: 10)) {
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
    if (!manufacturerData.containsKey(0x004C)) {
      return false;
    }

    final data = manufacturerData[0x004C]!;
    
    // iBeacon data structure:
    // Byte 0: 0x02 (iBeacon type)
    // Byte 1: 0x15 (Length = 21 bytes)
    // Bytes 2-17: UUID (16 bytes)
    // Bytes 18-19: Major (2 bytes)
    // Bytes 20-21: Minor (2 bytes)
    // Byte 22: TX Power (1 byte)
    
    if (data.length < 23) return false;
    if (data[0] != 0x02 || data[1] != 0x15) return false;

    // Parse UUID
    final uuidBytes = data.sublist(2, 18);
    final uuidHex = uuidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('-');
    final formattedUuid = '${uuidHex.substring(0, 8)}-${uuidHex.substring(8, 12)}-${uuidHex.substring(12, 16)}-${uuidHex.substring(16, 20)}-${uuidHex.substring(20)}';

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
