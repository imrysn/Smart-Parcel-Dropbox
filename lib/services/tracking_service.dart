import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/tracking_model.dart';
import '../config/api_config.dart';

/// Tracking Service - Handles tracking-related operations
///
/// Single Responsibility: Manage tracking IDs and their lifecycle
class TrackingService {
  static TrackingService? _instance;

  factory TrackingService() {
    _instance ??= TrackingService._internal();
    return _instance!;
  }

  TrackingService._internal();

  final _trackingController = StreamController<List<TrackingModel>>.broadcast();
  List<TrackingModel> _cachedTracking = [];
  bool _isFetching = false;

  // Public getters
  List<TrackingModel> get cachedTracking => _cachedTracking;
  Stream<List<TrackingModel>> get trackingStream => _trackingController.stream;

  /// Register a new tracking ID for a user
  Future<void> registerTrackingId({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
    String mode = 'drop_off',
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.tracking),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'trackingId': trackingId,
          'userId': userId,
          'shopName': shopName,
          'expectedDeliveryDate': expectedDeliveryDate,
          'mode': mode,
        }),
      );

      if (response.statusCode != 201) {
        final error = jsonDecode(response.body);
        throw error['message'] ?? 'Failed to register tracking ID';
      }

      // Refresh tracking data immediately
      await refreshTracking(userId);
    } catch (e) {
      throw 'Failed to register tracking ID: $e';
    }
  }

  /// Refresh tracking data for a user
  Future<void> refreshTracking(String userId) async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.tracking}/user/$userId'),
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        final list = data.map((json) => TrackingModel.fromMap(json)).toList();
        _cachedTracking = list;
        _trackingController.add(list);
      }
    } catch (e) {
      debugPrint('Error refreshing tracking: $e');
    } finally {
      _isFetching = false;
    }
  }

  /// Get all tracking IDs for a specific user
  Stream<List<TrackingModel>> getUserTrackingIds(String userId) {
    // If cache is empty, trigger a fetch
    if (_cachedTracking.isEmpty && !_isFetching) {
      refreshTracking(userId);
    }
    
    return _trackingController.stream;
  }

  /// Get active orders (not retrieved yet)
  Stream<List<TrackingModel>> getActiveOrders(String userId) {
    return getUserTrackingIds(userId).map(
      (list) => list
          .where((t) =>
              t.mode == 'drop_off' &&
              ['pending', 'in_transit', 'delivered'].contains(t.status))
          .toList(),
    ).asBroadcastStream();
  }

  /// Get active pickups (waiting for rider, or picked up)
  Stream<List<TrackingModel>> getActivePickups(String userId) {
    return getUserTrackingIds(userId).map(
      (list) => list
          .where((t) =>
              t.mode == 'pickup' &&
              ['pending', 'ready_for_pickup', 'retrieved'].contains(t.status))
          .toList(),
    ).asBroadcastStream();
  }

  /// Verify tracking ID (used by courier/drop box system)
  Future<Map<String, dynamic>?> verifyTrackingId(String trackingId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.tracking}/$trackingId'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      throw 'Failed to verify tracking ID: $e';
    }
  }

  /// Update tracking status
  Future<void> updateTrackingStatus({
    required String trackingId,
    required String status,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.tracking}/$trackingId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode != 200) {
        throw 'Failed to update status';
      }
    } catch (e) {
      throw 'Failed to update tracking status: $e';
    }
  }

  /// Get all tracking IDs (Admin)
  Future<List<TrackingModel>> getAllTrackingIds() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.tracking));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => TrackingModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching all tracking: $e');
      return [];
    }
  }

  /// Dispose resources
  void dispose() {
    _trackingController.close();
  }

  /// Reset singleton instance
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
