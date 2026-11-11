import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiConfig {
  static const String _envServerUrl = String.fromEnvironment('API_URL');
  static const String productionServerUrl = 'https://smart-parcel-dropbox.onrender.com';
  static const String localServerUrl = 'http://localhost:3000';
  static const String androidEmulatorServerUrl = 'http://10.0.2.2:3000';

  static String _serverUrl = _initialServerUrl();
  static bool _resolved = false;

  static String _normalize(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  static String _initialServerUrl() {
    if (_envServerUrl.isNotEmpty) {
      return _normalize(_envServerUrl);
    }
    // Try localhost first in debug builds; release builds default to production.
    return kDebugMode ? localServerUrl : productionServerUrl;
  }

  static bool get hasExplicitOverride => _envServerUrl.isNotEmpty;
  static bool get hasResolved => _resolved;
  static bool get isUsingLocalServer =>
      _serverUrl == localServerUrl || _serverUrl == androidEmulatorServerUrl;

  /// Probes local backend candidates first (debug mode without `--dart-define=API_URL`)
  /// and falls back to production if no local server is reachable.
  static Future<String> resolveServerUrl({
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    if (_envServerUrl.isNotEmpty || !kDebugMode) {
      _resolved = true;
      return _serverUrl;
    }

    final candidates = <String>[
      localServerUrl,
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        androidEmulatorServerUrl,
    ];

    for (final candidate in candidates) {
      try {
        final res = await http.get(Uri.parse('$candidate/health')).timeout(timeout);
        if (res.statusCode == 200) {
          _serverUrl = candidate;
          _resolved = true;
          debugPrint('🌐 [ApiConfig] Connected to local backend: $_serverUrl');
          return _serverUrl;
        }
      } catch (_) {
        // Candidate unavailable; continue checking next candidate or fallback.
      }
    }

    _serverUrl = productionServerUrl;
    _resolved = true;
    debugPrint('🌐 [ApiConfig] Localhost unavailable; using production: $_serverUrl');
    return _serverUrl;
  }

  /// Switches to production when a previously detected local backend drops offline.
  static bool useProductionFallback() {
    if (_envServerUrl.isNotEmpty || _serverUrl == productionServerUrl) {
      return false;
    }
    _serverUrl = productionServerUrl;
    _resolved = true;
    debugPrint('🌐 [ApiConfig] Falling back to production: $_serverUrl');
    return true;
  }

  static String get serverUrl => _serverUrl;
  static String get baseUrl => '$_serverUrl/api';

  // Socket.IO connects to the root server URL (no /api)
  static String get socketUrl => _serverUrl;

  static String get users => '$baseUrl/users';
  static String get tracking => '$baseUrl/tracking';
  static String get scanLogs => '$baseUrl/scan-logs';
  static String get notifications => '$baseUrl/notifications';
  // Mounted at root (/device-control), not under /api
  static String get deviceControl => '$_serverUrl/device-control';
  static String get dropbox => '$baseUrl/dropbox';
  static String get business => '$baseUrl/business';
  static String get riders => '$baseUrl/riders';
}
