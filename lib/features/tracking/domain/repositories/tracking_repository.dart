import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/tracking.dart';

/// Tracking repository interface - Domain layer
/// 
/// Defines the contract for tracking data operations.
/// Implementations are in the data layer.
abstract class TrackingRepository {
  /// Register a new tracking ID
  Future<Either<Failure, void>> registerTracking({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  });

  /// Get active orders for a user (stream for real-time updates)
  Stream<Either<Failure, List<Tracking>>> watchActiveOrders(String userId);

  /// Get all trackings for a user
  Future<Either<Failure, List<Tracking>>> getAllTrackings(String userId);

  /// Get tracking by ID
  Future<Either<Failure, Tracking>> getTrackingById(String trackingId);

  /// Update tracking status
  Future<Either<Failure, void>> updateStatus({
    required String trackingId,
    required String status,
  });

  /// Mark tracking as retrieved
  Future<Either<Failure, void>> markAsRetrieved(String trackingId);

  /// Delete tracking
  Future<Either<Failure, void>> deleteTracking(String trackingId);

  /// Verify tracking ID exists
  Future<Either<Failure, bool>> verifyTrackingId(String trackingId);
}
