import '../models/tracking_model.dart';

/// Remote data source for tracking operations
/// 
/// Handles all HTTP requests related to tracking.
/// Throws exceptions on errors (converted to Failures by repository).
abstract class TrackingRemoteDataSource {
  /// Register a new tracking ID
  Future<void> registerTracking({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  });

  /// Watch active orders (stream)
  Stream<List<TrackingModel>> watchActiveOrders(String userId);

  /// Get all trackings for a user
  Future<List<TrackingModel>> getAllTrackings(String userId);

  /// Get tracking by ID
  Future<TrackingModel> getTrackingById(String trackingId);

  /// Update tracking status
  Future<void> updateStatus({
    required String trackingId,
    required String status,
  });

  /// Mark as retrieved
  Future<void> markAsRetrieved(String trackingId);

  /// Delete tracking
  Future<void> deleteTracking(String trackingId);

  /// Verify tracking ID
  Future<bool> verifyTrackingId(String trackingId);
}
