import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/user_model.dart';
import '../config/api_config.dart';

/// User Service - Handles user management operations
///
/// Single Responsibility: Manage user data and profiles
class UserService {
  static UserService? _instance;

  factory UserService() {
    _instance ??= UserService._internal();
    return _instance!;
  }

  UserService._internal();

  final _usersController = StreamController<List<UserModel>>.broadcast();
  List<UserModel> _cachedUsers = [];
  bool _isFetching = false;

  // Public getters
  List<UserModel> get cachedUsers => _cachedUsers;
  Stream<List<UserModel>> get usersStream => _usersController.stream;

  /// Get user data by MongoDB ID
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.users}/$userId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
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

  /// Update user profile
  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? address,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.users}/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (fullName != null) 'fullName': fullName,
          if (phoneNumber != null) 'phoneNumber': phoneNumber,
          if (address != null) 'address': address,
        }),
      );

      if (response.statusCode != 200) {
        throw 'Failed to update profile';
      }
    } catch (e) {
      throw 'Failed to update user profile: $e';
    }
  }

  /// Get all users (Admin)
  Stream<List<UserModel>> getAllUsers() {
    // Important: do not trigger the initial fetch until a listener is attached.
    // Otherwise, the first `add`/`addError` can happen before `StreamBuilder`
    // subscribes, leaving the UI stuck in the initial loading spinner state.
    final controller = StreamController<List<UserModel>>();
    StreamSubscription<List<UserModel>>? subscription;

    void forwardError(Object error, StackTrace st) {
      controller.addError(error, st);
    }

    controller.onListen = () {
      subscription = _usersController.stream.listen(
        controller.add,
        onError: forwardError,
      );

      if (_cachedUsers.isNotEmpty) {
        controller.add(_cachedUsers);
      } else {
        // This will no-op if another refresh is already in-flight.
        refreshAllUsers();
      }
    };

    controller.onCancel = () async {
      await subscription?.cancel();
      await controller.close();
    };

    return controller.stream;
  }

  /// Refresh all users list
  Future<void> refreshAllUsers() async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      final users = await _fetchAllUsers();
      _cachedUsers = users;
      _usersController.add(users);
    } catch (e, st) {
      // Let the UI stop showing the endless spinner and show an actionable error state.
      debugPrint('Error refreshing all users: $e');
      _usersController.addError(e, st);
    } finally {
      _isFetching = false;
    }
  }

  Future<List<UserModel>> _fetchAllUsers() async {
    try {
      final response =
          await http.get(Uri.parse(ApiConfig.users)).timeout(
                const Duration(seconds: 10),
              );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to fetch all users: HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      final List data = decoded as List;
      return data.map((e) => UserModel.fromMap(e)).toList();
    } catch (e) {
      // Re-throw so refreshAllUsers can send the error to the StreamBuilder.
      debugPrint('Error fetching all users: $e');
      rethrow;
    }
  }

  /// Update user role (Admin)
  Future<void> updateUserRole({
    required String userId,
    required String role,
  }) async {
    try {
      await http.patch(
        Uri.parse('${ApiConfig.users}/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'role': role}),
      );
    } catch (e) {
      debugPrint('Error updating role: $e');
      rethrow;
    }
  }

  /// Get user role
  Future<String?> getUserRole(String userId) async {
    final data = await getUserData(userId);
    return data?['role'];
  }

  /// Delete user (Admin)
  Future<void> deleteUser(String userId) async {
    try {
      debugPrint('Deleting user: $userId');
      final response = await http.delete(
        Uri.parse('${ApiConfig.users}/$userId'),
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
          'Failed to delete user: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error deleting user: $e');
      rethrow;
    }
  }

  /// Get pending users (awaiting admin approval)
  Future<List<UserModel>> getPendingUsers() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.pendingUsers));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => UserModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching pending users: $e');
      return [];
    }
  }

  /// Approve pending user
  Future<void> approveUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.approveUser}/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to approve user: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error approving user: $e');
      rethrow;
    }
  }

  /// Reject pending user
  Future<void> rejectUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.rejectUser}/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to reject user: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error rejecting user: $e');
      rethrow;
    }
  }

  /// Check if email exists
  Future<bool> checkEmailExists(String email) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.users}/check-email/$email'),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error checking email: $e');
      return false;
    }
  }

  /// Request password reset
  Future<void> requestPasswordReset(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.users}/request-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw error['message'] ?? 'Failed to request password reset';
      }
    } catch (e) {
      throw 'Failed to request password reset: $e';
    }
  }

  /// Verify reset code
  Future<bool> verifyResetCode(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.users}/verify-reset-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['valid'] == true;
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
      final response = await http.post(
        Uri.parse('${ApiConfig.users}/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw error['message'] ?? 'Failed to reset password';
      }
    } catch (e) {
      throw 'Failed to reset password: $e';
    }
  }

  /// Dispose resources
  void dispose() {
    _usersController.close();
  }

  /// Reset singleton instance
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
