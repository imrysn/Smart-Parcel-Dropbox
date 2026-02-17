import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/user.dart';

/// Auth repository interface - Domain layer
abstract class AuthRepository {
  /// Get current user ID
  Future<Either<Failure, String?>> getCurrentUserId();

  /// Get current user
  Future<Either<Failure, User?>> getCurrentUser();

  /// Login with email and password
  Future<Either<Failure, User>> login({
    required String email,
    required String password,
  });

  /// Register new user
  Future<Either<Failure, User>> register({
    required String email,
    required String password,
    required String fullName,
  });

  /// Logout
  Future<Either<Failure, void>> logout();

  /// Update user profile
  Future<Either<Failure, void>> updateProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? address,
  });

  /// Get user data by ID
  Future<Either<Failure, User>> getUserData(String userId);

  /// Check if email exists
  Future<Either<Failure, bool>> checkEmailExists(String email);

  /// Request password reset
  Future<Either<Failure, void>> requestPasswordReset(String email);

  /// Verify reset code
  Future<Either<Failure, bool>> verifyResetCode({
    required String email,
    required String code,
  });

  /// Reset password with code
  Future<Either<Failure, void>> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Delete user account
  Future<Either<Failure, void>> deleteAccount(String userId);

  /// Stream of auth state changes
  Stream<User?> get authStateChanges;
}
