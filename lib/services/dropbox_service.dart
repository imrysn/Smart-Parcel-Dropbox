import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../models/dropbox_model.dart';
import '../services/websocket_service.dart';
import '../services/service_locator.dart';
import '../services/auth_service.dart';

/// Service for managing the registered Smart Parcel Dropbox hardware.
class DropboxService {
  final WebSocketService _ws;
  final AuthService _authService;

  DropboxService() : 
    _ws = getIt<WebSocketService>(),
    _authService = getIt<AuthService>();

  /// Fetch the registered dropbox for a given userId (REST GET).
  Future<Dropbox?> getUserDropbox(String userId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.dropbox}/$userId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return Dropbox.fromJson(jsonDecode(response.body));
      }
      return null; // 404 = not registered yet
    } catch (_) {
      return null;
    }
  }

  /// Emit registerDevice event via Socket.IO (after QR scan).
  void registerDevice(String token, String userId, String deviceName) {
    _ws.socket?.emit('registerDevice', {
      'token': token,
      'userId': userId,
      'deviceName': deviceName,
    });
  }

  /// REST fallback to claim and pair hardware device.
  Future<Map<String, dynamic>> claimDevice({
    required String token,
    required String deviceName,
    bool buttonConfirmed = true,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.dropbox}/claim'),
        headers: headers,
        body: jsonEncode({
          'token': token,
          'name': deviceName,
          'buttonConfirmed': buttonConfirmed,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final err = jsonDecode(response.body);
        throw err['message'] ?? 'Failed to pair device';
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Unregister device via both Socket.IO and REST (for redundancy).
  Future<void> unregisterDevice(String userId) async {
    // 1. Socket emission
    debugPrint('📤 Socket: Requesting unregisterDevice for $userId');
    _ws.emit('unregisterDevice', {
      'userId': userId,
    });

    // 2. REST fallback
    try {
      debugPrint('📤 REST: Falling back to DELETE /api/dropbox/$userId');
      final headers = await _authService.getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/dropbox/$userId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        debugPrint('✅ REST: Unregistered successfully');
      } else {
        debugPrint('⚠️ REST: Unregistration failed with status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ REST Error: $e');
    }
  }

  /// Emit pushHardwareConfig event to send WiFi credentials to the device.
  void pushHardwareConfig({required String ssid, required String password}) {
    _ws.socket?.emit('pushHardwareConfig', {
      'ssid': ssid,
      'password': password,
    });
  }

  /// Stream of successful device registration events.
  Stream<Map<String, dynamic>> get deviceRegisteredStream =>
      _ws.deviceRegisteredStream;

  /// Stream of device registration failure events.
  Stream<Map<String, dynamic>> get deviceRegistrationFailedStream =>
      _ws.deviceRegistrationFailedStream;

  /// Stream of hardware config applied confirmation from the device.
  Stream<Map<String, dynamic>> get hardwareConfigAppliedStream =>
      _ws.hardwareConfigAppliedStream;

  /// Stream of device unregistration confirmation.
  Stream<Map<String, dynamic>> get deviceUnregisteredStream =>
      _ws.deviceUnregisteredStream;
}
