import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

/// Authentication Service for Smart Parcel Drop Box System
/// MongoDB-based authentication with JWT tokens
class AuthService {
  final _storage = const FlutterSecureStorage();
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _userRoleKey = 'user_role';

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

  // Check if user is logged in
  Future<bool> get isLoggedIn async {
    final token = await _storage.read(key: _tokenKey);
    return token != null;
  }

  // Get auth token
  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  // Sign in with email and password
  Future<Map<String, dynamic>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.users}/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Store token and user info
        await _storage.write(key: _tokenKey, value: data['token']);
        await _storage.write(key: _userIdKey, value: data['user']['id']);
        await _storage.write(key: _userEmailKey, value: data['user']['email']);
        await _storage.write(key: _userRoleKey, value: data['user']['role']);
        
        return data['user'];
      } else {
        final error = jsonDecode(response.body);
        throw error['message'] ?? 'Login failed';
      }
    } catch (e) {
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
      final response = await http.post(
        Uri.parse('${ApiConfig.users}/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'address': address,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        
        // Store token and user info
        await _storage.write(key: _tokenKey, value: data['token']);
        await _storage.write(key: _userIdKey, value: data['user']['id']);
        await _storage.write(key: _userEmailKey, value: data['user']['email']);
        await _storage.write(key: _userRoleKey, value: data['user']['role']);
        
        return data['user'];
      } else {
        final error = jsonDecode(response.body);
        throw error['message'] ?? 'Registration failed';
      }
    } catch (e) {
      throw 'Registration failed: $e';
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
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
