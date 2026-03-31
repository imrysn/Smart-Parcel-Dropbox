import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:smart_parcel_dropbox/main.dart';
import 'package:smart_parcel_dropbox/services/notification_service.dart';
import 'package:smart_parcel_dropbox/services/websocket_service.dart';
import 'package:smart_parcel_dropbox/services/connectivity_service.dart';
import 'package:smart_parcel_dropbox/services/cache_service.dart';
import 'package:smart_parcel_dropbox/services/auth_service.dart';
import 'package:smart_parcel_dropbox/services/database_service.dart';
import 'dart:async';

// Manual mocks for simplicity in this smoke test.

class MockNotificationService extends Mock implements NotificationService {
  @override
  Future<void> initialize({void Function(String?)? onNotificationTap}) async {
    return;
  }
  @override
  void dispose() {}
}

class MockWebSocketService extends Mock implements WebSocketService {
  @override
  Stream<Map<String, dynamic>> get ownerAccessAlerts => const Stream.empty();
  @override
  void dispose() {}
}

class MockConnectivityService extends Mock implements ConnectivityService {
  @override
  void startMonitoring() {}
}

class MockCacheService extends Mock implements CacheService {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> clearExpiredCache() async {}
  @override
  Future<void> close() async {}
}

class MockAuthService extends Mock implements AuthService {
  @override
  Future<bool> get isLoggedIn async => false;
  @override
  Future<void> signOut() async {}
}

class MockDatabaseService extends Mock implements DatabaseService {}

void main() {
  final getIt = GetIt.instance;

  setUp(() {
    getIt.reset();
    getIt.registerLazySingleton<NotificationService>(() => MockNotificationService());
    getIt.registerLazySingleton<WebSocketService>(() => MockWebSocketService());
    getIt.registerLazySingleton<ConnectivityService>(() => MockConnectivityService());
    getIt.registerLazySingleton<CacheService>(() => MockCacheService());
    getIt.registerLazySingleton<AuthService>(() => MockAuthService());
    getIt.registerLazySingleton<DatabaseService>(() => MockDatabaseService());
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartParcelDropBoxApp());

    // Verify that the app builds and shows the splash screen (initial state)
    expect(find.byType(SmartParcelDropBoxApp), findsOneWidget);

    // Advanced: Handle the splash screen timer to prevent "Timer still pending" error
    // SplashScreen has a 800ms delay.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
  });
}
