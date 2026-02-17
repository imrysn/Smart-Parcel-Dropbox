import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/tracking.dart';
import '../repositories/tracking_repository.dart';

/// Use case for getting tracking by ID
class GetTrackingByIdUseCase {
  final TrackingRepository repository;

  GetTrackingByIdUseCase(this.repository);

  Future<Either<Failure, Tracking>> call(String trackingId) {
    return repository.getTrackingById(trackingId);
  }
}
