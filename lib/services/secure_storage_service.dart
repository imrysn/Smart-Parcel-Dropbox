import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

/// Secure Storage Service for sensitive data
/// Uses platform-specific encryption (Keychain on iOS, KeyStore on Android)
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );
  
  // Keys
  static const String _fcmTokenKey = 'fcm_token';
  static const String _userIdKey = 'user_id';
  static const String _lastLoginKey = 'last_login';
  
  /// Save FCM token securely
  Future<void> saveFcmToken(String token) async {
    try {
      await _storage.write(key: _fcmTokenKey, value: token);
      debugPrint('FCM token saved securely');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }
  
  /// Get FCM token
  Future<String?> getFcmToken() async {
    try {
      return await _storage.read(key: _fcmTokenKey);
    } catch (e) {
      debugPrint('Error reading FCM token: $e');
      return null;
    }
  }
  
  /// Save user ID
  Future<void> saveUserId(String userId) async {
    try {
      await _storage.write(key: _userIdKey, value: userId);
      debugPrint('User ID saved securely');
    } catch (e) {
      debugPrint('Error saving user ID: $e');
    }
  }
  
  /// Get user ID
  Future<String?> getUserId() async {
    try {
      return await _storage.read(key: _userIdKey);
    } catch (e) {
      debugPrint('Error reading user ID: $e');
      return null;
    }
  }
  
  /// Save last login timestamp
  Future<void> saveLastLogin() async {
    try {
      await _storage.write(
        key: _lastLoginKey,
        value: DateTime.now().toIso8601String(),
      );
      debugPrint('Last login saved');
    } catch (e) {
      debugPrint('Error saving last login: $e');
    }
  }
  
  /// Get last login
  Future<DateTime?> getLastLogin() async {
    try {
      final value = await _storage.read(key: _lastLoginKey);
      if (value != null) {
        return DateTime.parse(value);
      }
      return null;
    } catch (e) {
      debugPrint('Error reading last login: $e');
      return null;
    }
  }
  
  /// Save user preference
  Future<void> savePreference(String key, String value) async {
    try {
      await _storage.write(key: 'pref_$key', value: value);
      debugPrint('Preference saved: $key');
    } catch (e) {
      debugPrint('Error saving preference $key: $e');
    }
  }
  
  /// Get user preference
  Future<String?> getPreference(String key) async {
    try {
      return await _storage.read(key: 'pref_$key');
    } catch (e) {
      debugPrint('Error reading preference $key: $e');
      return null;
    }
  }
  
  /// Delete specific key
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
      debugPrint('Deleted secure storage key: $key');
    } catch (e) {
      debugPrint('Error deleting key $key: $e');
    }
  }
  
  /// Delete all secure data (on logout)
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
      debugPrint('All secure storage cleared');
    } catch (e) {
      debugPrint('Error clearing secure storage: $e');
    }
  }
  
  /// Check if key exists
  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      debugPrint('Error checking key $key: $e');
      return false;
    }
  }
  
  /// Get all keys
  Future<List<String>> getAllKeys() async {
    try {
      final all = await _storage.readAll();
      return all.keys.toList();
    } catch (e) {
      debugPrint('Error getting all keys: $e');
      return [];
    }
  }
}
