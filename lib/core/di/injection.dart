import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../network/api_client.dart';
import '../network/socket_client.dart';
import '../../services/cache_service.dart';
import '../../services/connectivity_service.dart';

// Tracking feature imports
import '../../features/tracking/data/datasources/tracking_remote_datasource.dart';
import '../../features/tracking/data/datasources/tracking_remote_datasource_impl.dart';
import '../../features/tracking/data/repositories/tracking_repository_impl.dart';
import '../../features/tracking/domain/repositories/tracking_repository.dart';
import '../../features/tracking/domain/usecases/get_active_orders_usecase.dart';
import '../../features/tracking/domain/usecases/register_tracking_usecase.dart';
import '../../features/tracking/domain/usecases/get_tracking_by_id_usecase.dart';
import '../../features/tracking/domain/usecases/update_tracking_status_usecase.dart';

// Auth feature imports
import '../../features/auth/data/datasources/auth_remote_datasource.dart';
import '../../features/auth/data/datasources/auth_remote_datasource_impl.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/domain/usecases/register_usecase.dart';
import '../../features/auth/domain/usecases/logout_usecase.dart';
import '../../features/auth/domain/usecases/get_current_user_usecase.dart';

/// Global service locator instance
final getIt = GetIt.instance;

/// Setup dependency injection
///
/// Call this in main() before runApp()
Future<void> setupDependencyInjection() async {
  // Core - Network
  getIt.registerLazySingleton<Dio>(() => Dio());
  getIt.registerLazySingleton<ApiClient>(() => ApiClient());
  getIt.registerLazySingleton<SocketClient>(() => SocketClient());

  // Core - Storage
  getIt.registerLazySingleton<FlutterSecureStorage>(
    () => const FlutterSecureStorage(),
  );

  // Core - Services
  getIt.registerLazySingleton<CacheService>(() => CacheService());
  getIt.registerLazySingleton<ConnectivityService>(() => ConnectivityService());

  // Initialize cache service
  await getIt<CacheService>().initialize();

  // ========== Tracking Feature ==========

  // Data sources
  getIt.registerLazySingleton<TrackingRemoteDataSource>(
    () => TrackingRemoteDataSourceImpl(
      apiClient: getIt<ApiClient>(),
      socketClient: getIt<SocketClient>(),
    ),
  );

  // Repositories
  getIt.registerLazySingleton<TrackingRepository>(
    () => TrackingRepositoryImpl(getIt<TrackingRemoteDataSource>()),
  );

  // Use cases
  getIt.registerLazySingleton(
    () => GetActiveOrdersUseCase(getIt<TrackingRepository>()),
  );
  getIt.registerLazySingleton(
    () => RegisterTrackingUseCase(getIt<TrackingRepository>()),
  );
  getIt.registerLazySingleton(
    () => GetTrackingByIdUseCase(getIt<TrackingRepository>()),
  );
  getIt.registerLazySingleton(
    () => UpdateTrackingStatusUseCase(getIt<TrackingRepository>()),
  );

  // ========== Auth Feature ==========

  // Data sources
  getIt.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSourceImpl(
      apiClient: getIt<ApiClient>(),
      secureStorage: getIt<FlutterSecureStorage>(),
    ),
  );

  // Repositories
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(getIt<AuthRemoteDataSource>()),
  );

  // Use cases
  getIt.registerLazySingleton(
    () => LoginUseCase(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton(
    () => RegisterUseCase(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton(
    () => LogoutUseCase(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton(
    () => GetCurrentUserUseCase(getIt<AuthRepository>()),
  );

  // ========== Notification Feature (TODO) ==========
  // Will be added when we implement notification repository

  // ========== IoT Feature (TODO) ==========
  // Will be added when we implement IoT repository
}
