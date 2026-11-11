import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../config/api_config.dart';
import 'auth_service.dart';
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
  int _sessionGeneration = 0;

  // Public getters
  Map<String, dynamic>? get cachedDoorState => _cachedDoorState;
  Stream<Map<String, dynamic>?> get doorStateStream =>
      _doorStateController.stream;

  /// Control dropbox door
  Future<void> controlDropBoxDoor({
    required String userId,
    required bool open,
    String doorType = 'user', // 'parcel' or 'user'
    bool useBiometrics = false, // Set to true for real device biometric testing
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

    await setDoorLock(doorType: doorType, unlock: open);
  }

  Future<Map<String, dynamic>> setDoorLock({
    required String doorType,
    required bool unlock,
    String? deviceId,
  }) async {
    final generation = _sessionGeneration;
    final auth = getIt<AuthService>();
    final headers = await auth.getAuthHeaders();
    if (generation != _sessionGeneration) throw StateError('The session changed');
    final response = await http.post(
      Uri.parse(ApiConfig.deviceControl),
      headers: headers,
      body: jsonEncode({
        'command': unlock ? 'open' : 'close',
        'doorType': doorType,
        if (deviceId != null) 'deviceId': deviceId,
      }),
    ).timeout(const Duration(seconds: 12));
    if (generation != _sessionGeneration) throw StateError('The session changed');
    if (response.statusCode == 401) {
      await auth.handleSessionExpired();
      throw StateError('Your session expired');
    }
    final dynamic result;
    try {
      result = jsonDecode(response.body);
    } on FormatException {
      throw StateError('The server returned an unexpected door response');
    }
    if (response.statusCode != 200 || result is! Map || result['success'] != true || result['doorState'] is! Map) {
      throw StateError(result is Map ? '${result['message'] ?? 'Door command could not be confirmed'}' : 'Door command could not be confirmed');
    }
    final state = Map<String, dynamic>.from(result['doorState'] as Map);
    updateDoorState(state);
    return state;
  }

  /// Get door state
  Stream<Map<String, dynamic>?> getDropBoxDoorState() {
    final generation = _sessionGeneration;
    // Seed with cached data
    if (_cachedDoorState != null) {
      Timer.run(() {
        if (generation == _sessionGeneration && !_doorStateController.isClosed) {
          _doorStateController.add(_cachedDoorState);
        }
      });
    }

    // Fetch latest state
    _fetchDoorState().then((data) {
      if (generation != _sessionGeneration || _doorStateController.isClosed) return;
      _cachedDoorState = data;
      _doorStateController.add(data);
    });

    return _doorStateController.stream;
  }

  Future<Map<String, dynamic>?> _fetchDoorState() async {
    try {
      final headers = await getIt<AuthService>().getAuthHeaders();
      final response = await http.get(
        Uri.parse(ApiConfig.deviceControl),
        headers: headers,
      );
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
  void clearSession() {
    _sessionGeneration++;
    _cachedDoorState = null;
    if (!_doorStateController.isClosed) _doorStateController.add(null);
  }

  void dispose() {
    _sessionGeneration++;
    _doorStateController.close();
  }

  /// Reset singleton instance
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
