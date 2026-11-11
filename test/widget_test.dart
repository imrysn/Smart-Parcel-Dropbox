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
import 'package:smart_parcel_dropbox/widgets/notification_badge.dart';
import 'package:smart_parcel_dropbox/widgets/smart_scanner_view.dart';
import 'package:smart_parcel_dropbox/widgets/camera_barcode_scanner_dialog.dart';
import 'package:smart_parcel_dropbox/screens/notifications_screen.dart';
import 'package:smart_parcel_dropbox/screens/owner_verify_screen.dart';
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
  Stream<bool> get connectionStatusStream => const Stream.empty();
  @override
  bool get isConnected => false;
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
  bool _loggedIn = false;
  bool _expired = false;
  bool signedOutCalled = false;

  void configure({bool loggedIn = false, bool expired = false}) {
    _loggedIn = loggedIn;
    _expired = expired;
    signedOutCalled = false;
  }

  @override
  Future<bool> get isLoggedIn async => _loggedIn;
  @override
  Future<bool> isTokenExpired() async => _expired;
  @override
  Future<bool> isBiometricLockEnabled() async => false;
  @override
  Future<String?> get currentUserId async => _loggedIn ? 'user-1' : null;
  @override
  Future<void> signOut() async {
    signedOutCalled = true;
    _loggedIn = false;
  }
}

class MockDatabaseService extends Mock implements DatabaseService {
  @override
  Future<Map<String, dynamic>?> getMe({Duration timeout = const Duration(seconds: 10)}) async => null;

  @override
  Stream<int> getUnreadNotificationsCount(String userId) => Stream<int>.value(14);
}

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

  testWidgets('App smoke test verifies responsive mobile centering', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartParcelDropBoxApp());

    // Verify that the app builds and SplashScreen content is horizontally centered on mobile
    expect(find.byType(SmartParcelDropBoxApp), findsOneWidget);
    final splashScaffoldCenter = tester.getCenter(find.byType(Scaffold).first);
    final splashTitleCenter = tester.getCenter(find.text('Smart Parcel Drop Box'));
    expect((splashTitleCenter.dx - splashScaffoldCenter.dx).abs(), lessThan(1.0));

    // Advance past SplashScreen delay and verify LoginScreen renders cleanly without overflow
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('Expired token triggers clean signOut and routes to LoginScreen', (WidgetTester tester) async {
    final mockAuth = getIt<AuthService>() as MockAuthService;
    mockAuth.configure(loggedIn: true, expired: true);

    await tester.pumpWidget(const SmartParcelDropBoxApp());
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    expect(mockAuth.signedOutCalled, isTrue);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('Tapping directly on notification count badge opens NotificationsScreen', (WidgetTester tester) async {
    final mockDb = getIt<DatabaseService>() as MockDatabaseService;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              NotificationBadge(
                userId: 'user-1',
                databaseService: mockDb,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('14'), findsOneWidget);
    // Tap dead center on the '14' badge itself (previously blocked by Positioned overlay)
    await tester.tap(find.text('14'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  testWidgets('OwnerVerifyScreen opens manual PIN entry directly on non-mobile hosts', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OwnerVerifyScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Enter Code Manually'), findsOneWidget);
    expect(find.text('Verify Access'), findsOneWidget);
    expect(SmartScannerView.isCameraSupportedPlatform, isFalse);
  });

  testWidgets('CameraBarcodeScannerDialog returns ScannedBarcodeResult from manual fallback', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    ScannedBarcodeResult? scanned;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                scanned = await CameraBarcodeScannerDialog.scan(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Waybill Barcode Scanner'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'SPXPH987654321');
    await tester.tap(find.text('Use Barcode'));
    await tester.pumpAndSettle();

    expect(scanned, isNotNull);
    expect(scanned!.trackingId, 'SPXPH987654321');
    expect(scanned!.detectedCourier, 'Shopee (SPX)');
  });
}
