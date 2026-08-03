import 'package:get_it/get_it.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'notification_service.dart';
import 'cache_service.dart';
import 'secure_storage_service.dart';
import 'connectivity_service.dart';
import 'performance_service.dart';
import 'iot_service.dart';
// New SRP-compliant services
import 'websocket_service.dart';
import 'tracking_service.dart';
import 'user_service.dart';
import 'scan_log_service.dart';
import 'device_control_service.dart';
import 'biometric_service.dart';
import 'dropbox_service.dart';
import 'task_service.dart';

/// Service Locator for Dependency Injection
/// Provides centralized access to all services
final getIt = GetIt.instance;

/// Setup all services for dependency injection
Future<void> setupServiceLocator() async {
  // Core Services
  getIt.registerLazySingleton(() => AuthService());

  // New SRP-compliant services (Phase 1 refactoring)
  getIt.registerLazySingleton(() => WebSocketService());
  getIt.registerLazySingleton(() => TrackingService());
  getIt.registerLazySingleton(() => UserService());
  getIt.registerLazySingleton(() => ScanLogService());
  getIt.registerLazySingleton(() => DeviceControlService());
  getIt.registerLazySingleton(() => NotificationService());
  getIt.registerLazySingleton(() => DropboxService());
  getIt.registerLazySingleton(() => TaskService());

  // Legacy DatabaseService (facade for backward compatibility)
  // TODO: Remove after all screens are migrated to new services
  getIt.registerLazySingleton(() => DatabaseService());

  // Utility Services
  getIt.registerLazySingleton(() => CacheService());
  getIt.registerLazySingleton(() => SecureStorageService());
  getIt.registerLazySingleton(() => ConnectivityService());
  getIt.registerLazySingleton(() => PerformanceService());
  getIt.registerLazySingleton(() => IoTService());
  getIt.registerLazySingleton(() => BiometricService());

  // Initialize cache service
  final cacheService = getIt<CacheService>();
  await cacheService.initialize();

  // Clear expired cache on startup
  await cacheService.clearExpiredCache();
}

/// Dispose all services on app close
Future<void> disposeServices() async {
  // Dispose new services
  if (getIt.isRegistered<WebSocketService>()) {
    getIt<WebSocketService>().dispose();
  }
  if (getIt.isRegistered<TrackingService>()) {
    getIt<TrackingService>().dispose();
  }
  if (getIt.isRegistered<UserService>()) {
    getIt<UserService>().dispose();
  }
  if (getIt.isRegistered<DeviceControlService>()) {
    getIt<DeviceControlService>().dispose();
  }
  if (getIt.isRegistered<NotificationService>()) {
    getIt<NotificationService>().dispose();
  }

  // Dispose cache service
  if (getIt.isRegistered<CacheService>()) {
    await getIt<CacheService>().close();
  }

  await getIt.reset();
}
