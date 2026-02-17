import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/error/exceptions.dart';
import '../models/user_model.dart';
import 'auth_remote_datasource.dart';

/// Implementation of AuthRemoteDataSource
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final ApiClient apiClient;
  final FlutterSecureStorage secureStorage;

  static const String _userIdKey = 'user_id';
  static const String _tokenKey = 'auth_token';

  AuthRemoteDataSourceImpl({
    required this.apiClient,
    required this.secureStorage,
  });

  @override
  Future<String?> getCurrentUserId() async {
    return await secureStorage.read(key: _userIdKey);
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    final userId = await getCurrentUserId();
    if (userId == null) return null;

    try {
      return await getUserData(userId);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'email': email,
          'password': password,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      final user = UserModel.fromJson(response['user'] as Map<String, dynamic>);
      final token = response['token'] as String;

      // Save credentials
      await secureStorage.write(key: _userIdKey, value: user.id);
      await secureStorage.write(key: _tokenKey, value: token);

      // Set auth token for future requests
      apiClient.setAuthToken(token);

      return user;
    } catch (e) {
      if (e.toString().contains('401')) {
        throw UnauthorizedException('Invalid email or password');
      }
      throw ServerException('Login failed: $e');
    }
  }

  @override
  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        '/api/auth/register',
        data: {
          'email': email,
          'password': password,
          'fullName': fullName,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      final user = UserModel.fromJson(response['user'] as Map<String, dynamic>);
      final token = response['token'] as String;

      // Save credentials
      await secureStorage.write(key: _userIdKey, value: user.id);
      await secureStorage.write(key: _tokenKey, value: token);

      // Set auth token
      apiClient.setAuthToken(token);

      return user;
    } catch (e) {
      if (e.toString().contains('409')) {
        throw ValidationException('Email already exists');
      }
      throw ServerException('Registration failed: $e');
    }
  }

  @override
  Future<void> logout() async {
    await secureStorage.delete(key: _userIdKey);
    await secureStorage.delete(key: _tokenKey);
    apiClient.clearAuthToken();
  }

  @override
  Future<void> updateProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? address,
  }) async {
    try {
      await apiClient.put(
        '/api/users/$userId',
        data: {
          if (fullName != null) 'fullName': fullName,
          if (phoneNumber != null) 'phoneNumber': phoneNumber,
          if (address != null) 'address': address,
        },
      );
    } catch (e) {
      throw ServerException('Failed to update profile: $e');
    }
  }

  @override
  Future<UserModel> getUserData(String userId) async {
    try {
      final response = await apiClient.get<Map<String, dynamic>>(
        '/api/users/$userId',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return UserModel.fromJson(response);
    } catch (e) {
      if (e.toString().contains('404')) {
        throw NotFoundException('User not found');
      }
      throw ServerException('Failed to get user data: $e');
    }
  }

  @override
  Future<bool> checkEmailExists(String email) async {
    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        '/api/auth/check-email',
        data: {'email': email},
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return response['exists'] as bool? ?? false;
    } catch (e) {
      throw ServerException('Failed to check email: $e');
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await apiClient.post(
        '/api/auth/request-reset',
        data: {'email': email},
      );
    } catch (e) {
      throw ServerException('Failed to request password reset: $e');
    }
  }

  @override
  Future<bool> verifyResetCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await apiClient.post<Map<String, dynamic>>(
        '/api/auth/verify-reset-code',
        data: {
          'email': email,
          'code': code,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return response['valid'] as bool? ?? false;
    } catch (e) {
      throw ServerException('Failed to verify reset code: $e');
    }
  }

  @override
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      await apiClient.post(
        '/api/auth/reset-password',
        data: {
          'email': email,
          'code': code,
          'newPassword': newPassword,
        },
      );
    } catch (e) {
      throw ServerException('Failed to reset password: $e');
    }
  }

  @override
  Future<void> deleteAccount(String userId) async {
    try {
      await apiClient.delete('/api/users/$userId');
      await logout();
    } catch (e) {
      throw ServerException('Failed to delete account: $e');
    }
  }
}
