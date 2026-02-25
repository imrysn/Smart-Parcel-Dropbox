import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../config/api_config.dart';
import 'service_locator.dart';
import 'biometric_service.dart';

/// Device Control Service - Handles IoT device control
///
/// Single Responsibility: Manage dropbox door control and device state
class DeviceControlService {
  static DeviceControlService? _instance;

  factory DeviceControlService() {
    _instance ??= DeviceControlService._internal();
    return _instance!;
  }

  DeviceControlService._internal();

  final _doorStateController =
      StreamController<Map<String, dynamic>?>.broadcast();
  Map<String, dynamic>? _cachedDoorState;

  // Public getters
  Map<String, dynamic>? get cachedDoorState => _cachedDoorState;
  Stream<Map<String, dynamic>?> get doorStateStream =>
      _doorStateController.stream;

  /// Control dropbox door
  Future<void> controlDropBoxDoor({
    required String userId,
    required bool open,
    String doorType = 'user', // 'parcel' or 'user'
    bool useBiometrics = true,
  }) async {
    if (useBiometrics) {
      final bioService = getIt<BiometricService>();
      if (await bioService.isBiometricAvailable()) {
        final authenticated = await bioService.authenticate(
          reason: 'Authenticate to ${open ? 'unlock' : 'lock'} the $doorType door',
        );
        if (!authenticated) {
          throw Exception('Biometric authentication failed or canceled');
        }
      }
    }

    try {
      await http.post(
        Uri.parse(ApiConfig.deviceControl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'command': open ? 'open' : 'close',
          'doorType': doorType,
        }),
      );
    } catch (e) {
      debugPrint('Error controlling door: $e');
      rethrow;
    }
  }

  /// Get door state
  Stream<Map<String, dynamic>?> getDropBoxDoorState() {
    // Seed with cached data
    if (_cachedDoorState != null) {
      Timer.run(() => _doorStateController.add(_cachedDoorState));
    }

    // Fetch latest state
    _fetchDoorState().then((data) {
      _cachedDoorState = data;
      _doorStateController.add(data);
    });

    return _doorStateController.stream;
  }

  Future<Map<String, dynamic>?> _fetchDoorState() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.deviceControl));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching door state: $e');
      return null;
    }
  }

  /// Update door state from WebSocket
  void updateDoorState(Map<String, dynamic> state) {
    _cachedDoorState = state;
    _doorStateController.add(state);
  }

  /// Dispose resources
  void dispose() {
    _doorStateController.close();
  }

  /// Reset singleton instance
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
