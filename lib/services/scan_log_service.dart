import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/scan_log_model.dart';
import '../config/api_config.dart';
import 'service_locator.dart';
import 'auth_service.dart';

/// Scan Log Service - Handles scan attempt logging
///
/// Single Responsibility: Manage scan logs and access attempts
class ScanLogService {
  static ScanLogService? _instance;

  factory ScanLogService() {
    _instance ??= ScanLogService._internal();
    return _instance!;
  }

  ScanLogService._internal();
  final _authService = getIt<AuthService>();

  /// Log a scan attempt
  Future<void> logScanAttempt({
    required String scannedCode,
    required bool accessGranted,
    String? trackingId,
    String? userId,
    String? reason,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      await http.post(
        Uri.parse(ApiConfig.scanLogs),
        headers: headers,
        body: jsonEncode({
          'scannedCode': scannedCode,
          'accessGranted': accessGranted,
          'trackingId': trackingId,
          'userId': userId,
          'reason': reason,
        }),
      );
    } catch (e) {
      debugPrint('Error logging scan: $e');
    }
  }

  /// Get all scan logs (Admin)
  Future<List<ScanLogModel>> getScanLogs() async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse(ApiConfig.scanLogs),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => ScanLogModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching scan logs: $e');
      return [];
    }
  }

  /// Get scan logs for a specific user
  Future<List<ScanLogModel>> getUserScanLogs(String userId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.scanLogs}/user/$userId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => ScanLogModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching user scan logs: $e');
      return [];
    }
  }

  /// Get owner access logs (Feature #7)
  Future<List<ScanLogModel>> getOwnerAccessLogs() async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        // Ensure this matches the Express route
        Uri.parse('${ApiConfig.scanLogs}/owner-access'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => ScanLogModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching owner access logs: $e');
      return [];
    }
  }

  /// Get all delivery logs (Admin)
  Future<List<Map<String, dynamic>>> getAllDeliveryLogs() async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/delivery-logs'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching all delivery logs: $e');
      return [];
    }
  }

  /// Get delivery logs for a tracking ID
  Future<List<Map<String, dynamic>>> getDeliveryLogs(String trackingId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/delivery-logs/$trackingId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching delivery logs: $e');
      return [];
    }
  }

  /// Reset singleton instance
  static void reset() {
    _instance = null;
  }
}
