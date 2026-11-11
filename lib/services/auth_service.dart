import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Authentication Service for Smart Parcel Drop Box System
/// MongoDB-based authentication with JWT tokens
class AuthService {
  final _storage = const FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  static const String _serverKey = 'auth_server_url';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _userRoleKey = 'user_role';
  static const String _biometricLockKey = 'biometric_lock_enabled';

  /// Thrown or invoked when stored credentials fail server validation (401/404).
  static VoidCallback? onSessionExpired;
  static VoidCallback? onSessionEnded;
  static Future<void> Function()? onSessionEnding;
  static bool _handlingExpiration = false;

  // Get current user ID
  Future<String?> get currentUserId async {
    return await _storage.read(key: _userIdKey);
  }

  // Get current user email
  Future<String?> get currentUserEmail async {
    return await _storage.read(key: _userEmailKey);
  }

  // Get current user role
  Future<String?> get currentUserRole async {
    return await _storage.read(key: _userRoleKey);
  }

  // Check if user has a stored token
  Future<bool> get isLoggedIn async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Decodes JWT `exp` claim offline and returns true if missing or expired.
  Future<bool> isTokenExpired() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return true;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final normalized = base64Url.normalize(parts[1]);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(payloadJson);
      if (payload is Map<String, dynamic> && payload['exp'] is num) {
        final expMs = (payload['exp'] as num).toInt() * 1000;
        return DateTime.now().millisecondsSinceEpoch >= expMs;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> isBiometricLockEnabled() async {
    final val = await _storage.read(key: _biometricLockKey);
    return val == 'true';
  }

  Future<void> setBiometricLockEnabled(bool enabled) async {
    await _storage.write(key: _biometricLockKey, value: enabled ? 'true' : 'false');
  }

  Future<void> handleSessionExpired() async {
    if (_handlingExpiration) return;
    _handlingExpiration = true;
    try {
      await signOut();
      onSessionExpired?.call();
    } finally {
      _handlingExpiration = false;
    }
  }

  // Get auth token
  Future<String?> getToken() async {
    if (await _storage.read(key: _serverKey) != ApiConfig.serverUrl) return null;
    return _storage.read(key: _tokenKey);
  }

  Future<void> _persistSession(Map<String, dynamic> data) async {
    final user = data['user'] as Map<String, dynamic>;
    final previousUserId = await currentUserId;
    if (previousUserId != null) {
      onSessionEnded?.call();
      await onSessionEnding?.call();
    }
    await _storage.write(key: _serverKey, value: ApiConfig.serverUrl);
    await _storage.write(key: _tokenKey, value: data['token'] as String?);
    await _storage.write(key: _userIdKey, value: user['id']?.toString());
    await _storage.write(key: _userEmailKey, value: user['email'] as String?);
    await _storage.write(key: _userRoleKey, value: user['role'] as String?);
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response, String fallbackError) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw fallbackError;
    } on FormatException {
      throw 'Server returned an unexpected response (${response.statusCode}). Please try again.';
    }
  }

  String _extractErrorMessage(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } on FormatException {
      // Non-JSON HTML/text response (e.g., proxy 502/503 or waking server)
    }
    if (response.statusCode == 502 || response.statusCode == 503 || response.statusCode == 504) {
      return 'Server is starting up (${response.statusCode}). Please wait a moment and try again.';
    }
    return '$fallback (HTTP ${response.statusCode})';
  }

  Future<http.Response> _postAuth({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    return http.post(
      Uri.parse('${ApiConfig.users}$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 20));
  }

  // Sign in with email and password
  Future<Map<String, dynamic>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _postAuth(
        path: '/login',
        body: {
          'email': email,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = _decodeJsonResponse(response, 'Invalid server response');
        await _persistSession(data);
        return data['user'] as Map<String, dynamic>;
      }
      throw _extractErrorMessage(response, 'Login failed');
    } on TimeoutException {
      throw 'Connection timed out. The server may be waking up, please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'Login failed: $e';
    }
  }

  // Register new user
  Future<Map<String, dynamic>> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required String address,
  }) async {
    try {
      final response = await _postAuth(
        path: '/register',
        body: {
          'email': email,
          'password': password,
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'address': address,
        },
      );

      if (response.statusCode == 201) {
        final data = _decodeJsonResponse(response, 'Invalid server response');
        await _persistSession(data);
        return data['user'] as Map<String, dynamic>;
      }
      throw _extractErrorMessage(response, 'Registration failed');
    } on TimeoutException {
      throw 'Connection timed out. The server may be waking up, please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'Registration failed: $e';
    }
  }

  // Sign out
  Future<void> signOut() async {
    onSessionEnded?.call();
    await onSessionEnding?.call();
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _serverKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userEmailKey);
    await _storage.delete(key: _userRoleKey);
  }

  // Get authorization header
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
