import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../config/api_config.dart';
import 'service_locator.dart';
import 'auth_service.dart';

class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([this.message = 'Session expired. Please sign in again.']);
  @override
  String toString() => message;
}

/// User Service - Handles self-service user profile and security operations.
class UserService {
  static UserService? _instance;

  factory UserService() {
    _instance ??= UserService._internal();
    return _instance!;
  }

  UserService._internal();
  final _authService = getIt<AuthService>();

  /// Validate stored JWT session and fetch current user profile.
  /// Throws [SessionExpiredException] on 401/404; returns null on transient network errors.
  Future<Map<String, dynamic>?> getMe({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http
          .get(Uri.parse('${ApiConfig.users}/me'), headers: headers)
          .timeout(timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 401 || response.statusCode == 404) {
        throw SessionExpiredException();
      }
      debugPrint('Failed to verify session: HTTP ${response.statusCode}');
      return null;
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      debugPrint('Transient error fetching /me: $e');
      return null;
    }
  }

  /// Get user data by MongoDB ID (self only)
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http
          .get(Uri.parse('${ApiConfig.users}/$userId'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return null;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        debugPrint('Failed to get user data: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting user data: $e');
      return null;
    }
  }

  /// Update own profile
  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? address,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http
          .patch(
            Uri.parse('${ApiConfig.users}/$userId'),
            headers: headers,
            body: jsonEncode({
              if (fullName != null) 'fullName': fullName,
              if (phoneNumber != null) 'phoneNumber': phoneNumber,
              if (address != null) 'address': address,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        throw SessionExpiredException();
      }
      if (response.statusCode != 200) {
        throw 'Failed to update profile';
      }
    } catch (e) {
      if (e is SessionExpiredException || e is String) rethrow;
      throw 'Failed to update user profile: $e';
    }
  }

  /// Change password while authenticated
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http
          .post(
            Uri.parse('${ApiConfig.users}/change-password'),
            headers: headers,
            body: jsonEncode({
              'currentPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        throw SessionExpiredException();
      }
      if (response.statusCode != 200) {
        final decoded = _tryDecodeJson(response.body);
        throw decoded?['message'] ?? 'Failed to change password';
      }
    } catch (e) {
      if (e is SessionExpiredException || e is String) rethrow;
      throw 'Failed to change password: $e';
    }
  }

  /// Permanently delete own account and sign out locally
  Future<void> deleteUser(String userId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http
          .delete(
            Uri.parse('${ApiConfig.users}/$userId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        throw SessionExpiredException();
      }
      if (response.statusCode != 200 && response.statusCode != 204) {
        final decoded = _tryDecodeJson(response.body);
        throw decoded?['message'] ?? 'Failed to delete account (${response.statusCode})';
      }
      await _authService.signOut();
    } catch (e) {
      debugPrint('Error deleting user: $e');
      rethrow;
    }
  }

  /// Request password reset
  Future<void> requestPasswordReset(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.users}/request-reset'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        final decoded = _tryDecodeJson(response.body);
        throw decoded?['message'] ?? 'Failed to request password reset';
      }
    } catch (e) {
      if (e is String) rethrow;
      throw 'Failed to request password reset: $e';
    }
  }

  /// Verify reset code
  Future<bool> verifyResetCode(String email, String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.users}/verify-reset-code'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'code': code}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = _tryDecodeJson(response.body);
        return data?['valid'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error verifying reset code: $e');
      return false;
    }
  }

  /// Reset password with code
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.users}/reset-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'code': code,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        final decoded = _tryDecodeJson(response.body);
        throw decoded?['message'] ?? 'Failed to reset password';
      }
    } catch (e) {
      if (e is String) rethrow;
      throw 'Failed to reset password: $e';
    }
  }

  Map<String, dynamic>? _tryDecodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {}

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
