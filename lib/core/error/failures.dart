import 'package:equatable/equatable.dart';

/// Base class for all failures in the application
/// 
/// Failures represent errors that have been handled and are safe
/// to present to the user or log. They are returned by repositories
/// using Either<Failure, T> pattern.
abstract class Failure extends Equatable {
  final String message;

  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

class ServerFailure extends Failure {
  final int? statusCode;

  const ServerFailure(super.message, {this.statusCode});

  @override
  List<Object> get props => [message, statusCode ?? 0];
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message);
}

class ValidationFailure extends Failure {
  final Map<String, String>? errors;

  const ValidationFailure(super.message, {this.errors});

  @override
  List<Object> get props => [message, errors ?? {}];
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
