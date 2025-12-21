import 'package:get_it/get_it.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'notification_service.dart';
import 'google_auth_service.dart';
import 'cache_service.dart';
import 'secure_storage_service.dart';
import 'connectivity_service.dart';
import 'performance_service.dart';
import 'iot_service.dart';

/// Service Locator for Dependency Injection
/// Provides centralized access to all services
final getIt = GetIt.instance;

/// Setup all services for dependency injection
Future<void> setupServiceLocator() async {
  // Core Services
  getIt.registerLazySingleton(() => AuthService());
  getIt.registerLazySingleton(() => GoogleAuthService());
  getIt.registerLazySingleton(() => DatabaseService());
  getIt.registerLazySingleton(() => NotificationService());
  
  // New Services
  getIt.registerLazySingleton(() => CacheService());
  getIt.registerLazySingleton(() => SecureStorageService());
  getIt.registerLazySingleton(() => ConnectivityService());
  getIt.registerLazySingleton(() => PerformanceService());
  getIt.registerLazySingleton(() => IoTService());
  
  // Initialize cache service
  final cacheService = getIt<CacheService>();
  await cacheService.initialize();
  
  // Clear expired cache on startup
  await cacheService.clearExpiredCache();
}

/// Dispose all services on app close
Future<void> disposeServices() async {
  if (getIt.isRegistered<CacheService>()) {
    await getIt<CacheService>().close();
  }
  
  await getIt.reset();
}
