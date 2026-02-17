import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/socket_client.dart';
import '../../../../core/error/exceptions.dart';
import '../models/tracking_model.dart';
import 'tracking_remote_datasource.dart';

/// Implementation of TrackingRemoteDataSource
/// 
/// Uses ApiClient for HTTP requests and SocketClient for real-time updates
class TrackingRemoteDataSourceImpl implements TrackingRemoteDataSource {
  final ApiClient apiClient;
  final SocketClient socketClient;

  // Stream controller for active orders
  final _activeOrdersController =
      StreamController<List<TrackingModel>>.broadcast();

  // Cache for active orders
  List<TrackingModel> _cachedTrackings = [];

  TrackingRemoteDataSourceImpl({
    required this.apiClient,
    required this.socketClient,
  }) {
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    // Listen for tracking updates from server
    socketClient.on('trackingUpdate', (data) {
      debugPrint('📦 Tracking update received: $data');
      _refreshActiveOrders();
    });
  }

  Future<void> _refreshActiveOrders() async {
    // This will be called when socket receives updates
    // The stream will automatically emit new data
    _activeOrdersController.add(_cachedTrackings);
  }

  @override
  Future<void> registerTracking({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  }) async {
    try {
      await apiClient.post(
        '/api/tracking/register',
        data: {
          'userId': userId,
          'trackingId': trackingId,
          'shopName': shopName,
          if (expectedDeliveryDate != null)
            'expectedDeliveryDate': expectedDeliveryDate,
        },
      );
    } catch (e) {
      throw ServerException('Failed to register tracking: $e');
    }
  }

  @override
  Stream<List<TrackingModel>> watchActiveOrders(String userId) {
    // Initial fetch
    getAllTrackings(userId).then((trackings) {
      final activeTrackings = trackings
          .where((t) =>
              t.status.value == 'pending' ||
              t.status.value == 'in_transit' ||
              t.status.value == 'delivered')
          .toList();
      _cachedTrackings = activeTrackings;
      _activeOrdersController.add(activeTrackings);
    }).catchError((error) {
      _activeOrdersController.addError(error);
    });

    return _activeOrdersController.stream;
  }

  @override
  Future<List<TrackingModel>> getAllTrackings(String userId) async {
    try {
      final response = await apiClient.get<List<dynamic>>(
        '/api/tracking/user/$userId',
        fromJson: (data) => data as List<dynamic>,
      );

      return response
          .map((json) => TrackingModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ServerException('Failed to get trackings: $e');
    }
  }

  @override
  Future<TrackingModel> getTrackingById(String trackingId) async {
    try {
      final response = await apiClient.get<Map<String, dynamic>>(
        '/api/tracking/$trackingId',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return TrackingModel.fromJson(response);
    } catch (e) {
      if (e.toString().contains('404')) {
        throw NotFoundException('Tracking ID not found');
      }
      throw ServerException('Failed to get tracking: $e');
    }
  }

  @override
  Future<void> updateStatus({
    required String trackingId,
    required String status,
  }) async {
    try {
      await apiClient.put(
        '/api/tracking/$trackingId/status',
        data: {'status': status},
      );
    } catch (e) {
      throw ServerException('Failed to update status: $e');
    }
  }

  @override
  Future<void> markAsRetrieved(String trackingId) async {
    return updateStatus(trackingId: trackingId, status: 'retrieved');
  }

  @override
  Future<void> deleteTracking(String trackingId) async {
    try {
      await apiClient.delete('/api/tracking/$trackingId');
    } catch (e) {
      throw ServerException('Failed to delete tracking: $e');
    }
  }

  @override
  Future<bool> verifyTrackingId(String trackingId) async {
    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        '/api/tracking/verify',
        data: {'trackingId': trackingId},
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return response['exists'] as bool? ?? false;
    } catch (e) {
      throw ServerException('Failed to verify tracking: $e');
    }
  }

  void dispose() {
    _activeOrdersController.close();
  }
}
