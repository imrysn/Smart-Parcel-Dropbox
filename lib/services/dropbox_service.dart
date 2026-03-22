import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../models/dropbox_model.dart';
import '../services/websocket_service.dart';
import '../services/service_locator.dart';

/// Service for managing the registered Smart Parcel Dropbox hardware.
class DropboxService {
  final WebSocketService _ws;

  DropboxService() : _ws = getIt<WebSocketService>();

  /// Fetch the registered dropbox for a given userId (REST GET).
  Future<Dropbox?> getUserDropbox(String userId) async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.dropbox}/$userId'));
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
}
