import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../repositories/tracking_repository.dart';

/// Use case for registering a new tracking ID
class RegisterTrackingUseCase {
  final TrackingRepository repository;

  RegisterTrackingUseCase(this.repository);

  /// Execute the use case
  Future<Either<Failure, void>> call({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  }) {
    return repository.registerTracking(
      userId: userId,
      trackingId: trackingId,
      shopName: shopName,
      expectedDeliveryDate: expectedDeliveryDate,
    );
  }
}
