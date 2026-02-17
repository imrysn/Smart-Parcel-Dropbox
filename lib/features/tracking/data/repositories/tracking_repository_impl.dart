import 'package:dartz/dartz.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/tracking.dart';
import '../../domain/repositories/tracking_repository.dart';
import '../datasources/tracking_remote_datasource.dart';

/// Implementation of TrackingRepository
/// 
/// Converts exceptions from data sources into Failures for the domain layer.
/// Follows the Repository pattern to abstract data sources.
class TrackingRepositoryImpl implements TrackingRepository {
  final TrackingRemoteDataSource remoteDataSource;

  TrackingRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, void>> registerTracking({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  }) async {
    try {
      await remoteDataSource.registerTracking(
        userId: userId,
        trackingId: trackingId,
        shopName: shopName,
        expectedDeliveryDate: expectedDeliveryDate,
      );
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message, errors: e.errors));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Stream<Either<Failure, List<Tracking>>> watchActiveOrders(String userId) {
    try {
      return remoteDataSource.watchActiveOrders(userId).map(
        (trackingModels) {
          final trackings =
              trackingModels.map((model) => model.toEntity()).toList();
          return Right<Failure, List<Tracking>>(trackings);
        },
      ).handleError((error) {
        if (error is ServerException) {
          return Left<Failure, List<Tracking>>(ServerFailure(error.message));
        } else if (error is NetworkException) {
          return Left<Failure, List<Tracking>>(NetworkFailure(error.message));
        } else {
          return Left<Failure, List<Tracking>>(
              UnknownFailure(error.toString()));
        }
      });
    } catch (e) {
      return Stream.value(Left(UnknownFailure(e.toString())));
    }
  }

  @override
  Future<Either<Failure, List<Tracking>>> getAllTrackings(
      String userId) async {
    try {
      final trackingModels = await remoteDataSource.getAllTrackings(userId);
      final trackings =
          trackingModels.map((model) => model.toEntity()).toList();
      return Right(trackings);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Tracking>> getTrackingById(String trackingId) async {
    try {
      final trackingModel =
          await remoteDataSource.getTrackingById(trackingId);
      return Right(trackingModel.toEntity());
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateStatus({
    required String trackingId,
    required String status,
  }) async {
    try {
      await remoteDataSource.updateStatus(
        trackingId: trackingId,
        status: status,
      );
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> markAsRetrieved(String trackingId) async {
    try {
      await remoteDataSource.markAsRetrieved(trackingId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteTracking(String trackingId) async {
    try {
      await remoteDataSource.deleteTracking(trackingId);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, bool>> verifyTrackingId(String trackingId) async {
    try {
      final exists = await remoteDataSource.verifyTrackingId(trackingId);
      return Right(exists);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }
}
