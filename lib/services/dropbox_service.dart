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

  /// Whether the real-time WebSocket connection is currently active.
  bool get isSocketConnected => _ws.isConnected;

  /// Ensures WebSocket is initialized for the signed-in user (e.g. straight after signup).
  Future<void> ensureSocketConnected() async {
    if (_ws.isConnected) return;
    final userId = await _authService.currentUserId;
    if (userId != null && userId.isNotEmpty) {
      await _ws.connect(userId);
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

  String _parseErrorMessage(http.Response response, String fallback) {
    try {
      final err = jsonDecode(response.body);
      if (err is Map && err['message'] is String && (err['message'] as String).isNotEmpty) {
        return err['message'] as String;
      }
    } on FormatException {
      // Non-JSON proxy/cold-start response; keep status-aware fallback message
    }
    return '$fallback (HTTP ${response.statusCode})';
  }

  /// REST fallback to claim and pair hardware device.
  Future<Map<String, dynamic>> claimDevice({
    required String token,
    required String deviceName,
    bool buttonConfirmed = true,
  }) async {
    final headers = await _authService.getAuthHeaders();
    final response = await http
        .post(
          Uri.parse('${ApiConfig.dropbox}/claim'),
          headers: headers,
          body: jsonEncode({
            'token': token,
            'name': deviceName,
            'buttonConfirmed': buttonConfirmed,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw _parseErrorMessage(response, 'Failed to pair device');
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
        Uri.parse('${ApiConfig.dropbox}/$userId'),
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

  /// List household members paired to [deviceId].
  Future<Map<String, dynamic>?> getDeviceMembers(String deviceId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http
          .get(Uri.parse('${ApiConfig.dropbox}/$deviceId/members'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching members: $e');
      return null;
    }
  }

  /// Remove a household member from [deviceId] (primary owner only).
  Future<void> removeDeviceMember({
    required String deviceId,
    required String memberId,
  }) async {
    final headers = await _authService.getAuthHeaders();
    final response = await http
        .delete(
          Uri.parse('${ApiConfig.dropbox}/$deviceId/members/$memberId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw _parseErrorMessage(response, 'Failed to remove member');
    }
  }

  /// Directly add a household member by registered email (primary owner only).
  Future<Map<String, dynamic>> addDeviceMember({
    required String deviceId,
    required String email,
  }) async {
    final headers = await _authService.getAuthHeaders();
    final response = await http
        .post(
          Uri.parse('${ApiConfig.dropbox}/$deviceId/members'),
          headers: headers,
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw _parseErrorMessage(response, 'Failed to add member');
  }

  /// Generate a 15-minute in-app pairing QR/PIN invite for a household member (primary owner only).
  Future<Map<String, dynamic>> createHouseholdInvite({
    required String deviceId,
  }) async {
    final headers = await _authService.getAuthHeaders();
    final response = await http
        .post(
          Uri.parse('${ApiConfig.dropbox}/$deviceId/invite'),
          headers: headers,
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw _parseErrorMessage(response, 'Failed to create invite code');
  }

  /// List owner-scoped trusted courier passes.
  Future<List<Map<String, dynamic>>> getTrustedCouriers() async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http
          .get(Uri.parse(ApiConfig.riders), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body) as List;
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching trusted couriers: $e');
      return [];
    }
  }

  /// Register a recurring trusted courier pass for the paired unit.
  Future<void> addTrustedCourier({
    required String riderId,
    required String name,
  }) async {
    final headers = await _authService.getAuthHeaders();
    final response = await http
        .post(
          Uri.parse(ApiConfig.riders),
          headers: headers,
          body: jsonEncode({'riderId': riderId.trim(), 'name': name.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 201) {
      throw _parseErrorMessage(response, 'Failed to register courier pass');
    }
  }

  /// Revoke an owner-scoped trusted courier pass.
  Future<void> removeTrustedCourier(String id) async {
    final headers = await _authService.getAuthHeaders();
    final response = await http
        .delete(Uri.parse('${ApiConfig.riders}/$id'), headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw _parseErrorMessage(response, 'Failed to revoke courier pass');
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
