import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _envServerUrl = String.fromEnvironment('API_URL');
  static const String productionServerUrl = 'https://smart-parcel-dropbox.onrender.com';
  static const String localServerUrl = 'http://localhost:3000';
  static const String androidEmulatorServerUrl = 'http://10.0.2.2:3000';

  static final String serverUrl = _initialServerUrl();

  static String _initialServerUrl() {
    if (_envServerUrl.isNotEmpty) return _envServerUrl.replaceFirst(RegExp(r'/+$'), '');
    if (!kDebugMode) return productionServerUrl;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? androidEmulatorServerUrl : localServerUrl;
  }

  static String get baseUrl => '$serverUrl/api';

  // Socket.IO connects to the root server URL (no /api)
  static String get socketUrl => serverUrl;

  static String get users => '$baseUrl/users';
  static String get tracking => '$baseUrl/tracking';
  static String get scanLogs => '$baseUrl/scan-logs';
  static String get notifications => '$baseUrl/notifications';
  // Mounted at root (/device-control), not under /api
  static String get deviceControl => '$serverUrl/device-control';
  static String get dropbox => '$baseUrl/dropbox';
  static String get business => '$baseUrl/business';
  static String get riders => '$baseUrl/riders';
}
