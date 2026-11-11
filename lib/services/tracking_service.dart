import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/tracking_model.dart';
import '../config/api_config.dart';
import 'service_locator.dart';
import 'auth_service.dart';

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
  final _authService = getIt<AuthService>();
  List<TrackingModel> _cachedTracking = [];
  bool _isFetching = false;
  int _sessionGeneration = 0;
  String? _queuedRefresh;

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
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse(ApiConfig.tracking),
        headers: headers,
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
    if (_isFetching) {
      _queuedRefresh = userId;
      return;
    }
    _isFetching = true;
    final generation = _sessionGeneration;

    try {
      if (await _authService.currentUserId != userId || generation != _sessionGeneration) return;
      final headers = await _authService.getAuthHeaders();
      if (generation != _sessionGeneration) return;
      final response = await http.get(
        Uri.parse('${ApiConfig.tracking}/user/$userId'),
        headers: headers,
      ).timeout(const Duration(seconds: 12));
      if (generation != _sessionGeneration) return;
      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return;
      }

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        final list = data.map((json) => TrackingModel.fromMap(json)).toList();
        _cachedTracking = list;
        _trackingController.add(list);
      } else {
        // Emit cached data so stream listeners don't hang in waiting state
        if (!_trackingController.isClosed) {
          _trackingController.add(_cachedTracking);
        }
      }
    } catch (e) {
      debugPrint('Error refreshing tracking: $e');
      if (generation == _sessionGeneration && !_trackingController.isClosed) {
        _trackingController.add(_cachedTracking);
      }
    } finally {
      if (generation == _sessionGeneration) {
        _isFetching = false;
        final queuedUser = _queuedRefresh;
        _queuedRefresh = null;
        if (queuedUser != null) unawaited(refreshTracking(queuedUser));
      }
    }
  }

  /// Get all tracking IDs for a specific user
  Stream<List<TrackingModel>> getUserTrackingIds(String userId) {
    if (_cachedTracking.isNotEmpty) {
      final generation = _sessionGeneration;
      Future.microtask(() {
        if (generation == _sessionGeneration && !_trackingController.isClosed) {
          _trackingController.add(_cachedTracking);
        }
      });
    }
    // If cache is empty, trigger a fetch
    if (_cachedTracking.isEmpty && !_isFetching) {
      refreshTracking(userId);
    }
    
    return _trackingController.stream;
  }

  /// Get active orders (drop_off mode — all non-archived statuses)
  Stream<List<TrackingModel>> getActiveOrders(String userId) {
    return getUserTrackingIds(userId).map(
      (list) => list
          .where((t) =>
              t.mode == 'drop_off' &&
              ['pending', 'in_transit', 'delivered', 'awaiting_pickup', 'done']
                  .contains(t.status))
          .toList(),
    ).asBroadcastStream();
  }

  /// Get active pickups (waiting for rider, or picked up)
  Stream<List<TrackingModel>> getActivePickups(String userId) {
    return getUserTrackingIds(userId).map(
      (list) => list
          .where((t) =>
              (t.mode == 'pickup' || t.mode == 'pick_up') &&
              ['pending', 'awaiting_pickup', 'ready_for_pickup', 'retrieved', 'done']
                  .contains(t.status))
          .toList(),
    ).asBroadcastStream();
  }

  /// Verify tracking ID (used by courier/drop box system)
  Future<Map<String, dynamic>?> verifyTrackingId(String trackingId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.tracking}/$trackingId'),
        headers: headers,
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
      final headers = await _authService.getAuthHeaders();
      final response = await http.patch(
        Uri.parse('${ApiConfig.tracking}/$trackingId/status'),
        headers: headers,
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode != 200) {
        throw 'Failed to update status';
      }
    } catch (e) {
      throw 'Failed to update tracking status: $e';
    }
  }

  /// Trigger an automated simulation for a tracking ID
  Future<void> simulateTracking(String trackingId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.tracking}/$trackingId/simulate'),
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw 'Failed to start simulation';
      }
    } catch (e) {
      throw 'Simulation error: $e';
    }
  }

  /// Manually reset tracking status (for development/testing)
  Future<void> resetTracking(String trackingId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.tracking}/$trackingId/reset'),
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw 'Failed to reset tracking';
      }
    } catch (e) {
      throw 'Reset error: $e';
    }
  }

  /// Delete a tracking ID
  Future<void> deleteTrackingId(String userId, String trackingId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.tracking}/$trackingId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        try {
          final error = jsonDecode(response.body);
          throw error['message'] ?? 'Failed to delete tracking ID (Status: ${response.statusCode})';
        } catch (e) {
          // If body is not JSON (e.g. HTML 404 page), throw a generic but informative error
          if (response.statusCode == 404) {
            throw 'Delete route not found on server. Please restart the backend server.';
          }
          throw 'Server error (${response.statusCode}): ${response.reasonPhrase}';
        }
      }

      // Refresh tracking data immediately
      await refreshTracking(userId);
    } catch (e) {
      throw 'Failed to delete tracking ID: $e';
    }
  }

  /// Stage an outbound customer order
  Future<Map<String, dynamic>> stageOutboundPackage({
    required String trackingId,
    required String shopName,
    required String customerName,
    String? customerPhone,
    String? courierName,
    String? riderName,
    String? riderPhone,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.business}/outbound-staging'),
        headers: headers,
        body: jsonEncode({
          'trackingId': trackingId,
          'shopName': shopName,
          'customerName': customerName,
          'customerPhone': customerPhone,
          'courierName': courierName,
          'riderName': riderName,
          'riderPhone': riderPhone,
        }),
      );

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (_) {
        // Non-JSON response (e.g. HTML 404/502 from server or proxy)
      }

      if (response.statusCode == 201 && body != null) {
        final userId = await _authService.currentUserId;
        if (userId != null) await refreshTracking(userId);
        return body['data'];
      } else {
        final msg = body?['message'] ??
            (response.statusCode == 404
                ? 'Outbound staging route not found on server (404). Please ensure server is updated.'
                : 'Server error (HTTP ${response.statusCode}). Please try again.');
        throw msg;
      }
    } catch (e) {
      throw 'Outbound staging error: $e';
    }
  }

  /// Batch stage multiple outbound customer packages
  Future<({List<dynamic> packages, bool doorConfirmed})> batchStageOutboundPackages({
    required List<Map<String, String>> packages,
    required String shopName,
    bool openDoor = true,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.business}/batch-outbound-staging'),
        headers: headers,
        body: jsonEncode({
          'packages': packages,
          'shopName': shopName,
          'openDoor': openDoor,
        }),
      ).timeout(const Duration(seconds: 20));

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (_) {
        // Non-JSON response
      }

      if (response.statusCode == 201 && body != null) {
        final userId = await _authService.currentUserId;
        if (userId != null) await refreshTracking(userId);
        return (packages: body['data'] as List, doorConfirmed: (body['doorCommand'] as Map?)?['ok'] == true);
      } else {
        final msg = body?['message'] ??
            (response.statusCode == 404
                ? 'Batch staging route not found on server (404). Please ensure server is updated.'
                : 'Server error (HTTP ${response.statusCode}). Please try again.');
        throw msg;
      }
    } catch (e) {
      throw 'Batch outbound staging error: $e';
    }
  }

  /// Generate customer dispatch notification link/text
  Future<Map<String, String>?> generateDispatchLink(String trackingId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.business}/generate-dispatch-link'),
        headers: headers,
        body: jsonEncode({'trackingId': trackingId}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        return {
          'text': data['text']?.toString() ?? '',
          'shareText': (data['shareText'] ?? data['text'])?.toString() ?? '',
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error generating dispatch text: $e');
      return null;
    }
  }

  /// Dispose resources
  void clearSession() {
    _sessionGeneration++;
    _isFetching = false;
    _queuedRefresh = null;
    _cachedTracking = [];
    if (!_trackingController.isClosed) _trackingController.add([]);
  }

  void dispose() {
    _sessionGeneration++;
    _trackingController.close();
  }

  /// Reset singleton instance
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
