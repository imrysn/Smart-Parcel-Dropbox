import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/tracking.dart';
import '../repositories/tracking_repository.dart';

/// Use case for getting active orders
/// 
/// Follows Clean Architecture principles:
/// - Single responsibility
/// - Depends on repository abstraction
/// - Returns Either<Failure, T> for error handling
class GetActiveOrdersUseCase {
  final TrackingRepository repository;

  GetActiveOrdersUseCase(this.repository);

  /// Execute the use case
  /// 
  /// Returns a stream of active orders for the given user ID
  Stream<Either<Failure, List<Tracking>>> call(String userId) {
    return repository.watchActiveOrders(userId);
  }
}
