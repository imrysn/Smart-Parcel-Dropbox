import '../models/user_model.dart';

/// Remote data source for authentication operations
abstract class AuthRemoteDataSource {
  /// Get current user ID from local storage
  Future<String?> getCurrentUserId();

  /// Get current user data
  Future<UserModel?> getCurrentUser();

  /// Login with email and password
  Future<UserModel> login({
    required String email,
    required String password,
  });

  /// Register new user
  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
  });

  /// Logout
  Future<void> logout();

  /// Update user profile
  Future<void> updateProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? address,
  });

  /// Get user data by ID
  Future<UserModel> getUserData(String userId);

  /// Check if email exists
  Future<bool> checkEmailExists(String email);

  /// Request password reset
  Future<void> requestPasswordReset(String email);

  /// Verify reset code
  Future<bool> verifyResetCode({
    required String email,
    required String code,
  });

  /// Reset password with code
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  });

  /// Delete account
  Future<void> deleteAccount(String userId);
}
