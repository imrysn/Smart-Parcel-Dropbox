import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../repositories/tracking_repository.dart';

/// Use case for updating tracking status
class UpdateTrackingStatusUseCase {
  final TrackingRepository repository;

  UpdateTrackingStatusUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String trackingId,
    required String status,
  }) {
    return repository.updateStatus(
      trackingId: trackingId,
      status: status,
    );
  }
}
