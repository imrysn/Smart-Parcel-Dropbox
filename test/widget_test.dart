import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:smart_parcel_dropbox/main.dart';
import 'package:smart_parcel_dropbox/services/notification_service.dart';
import 'package:smart_parcel_dropbox/services/websocket_service.dart';
import 'package:smart_parcel_dropbox/services/connectivity_service.dart';
import 'package:smart_parcel_dropbox/services/cache_service.dart';
import 'package:smart_parcel_dropbox/services/auth_service.dart';
import 'package:smart_parcel_dropbox/services/biometric_service.dart';
import 'package:smart_parcel_dropbox/services/database_service.dart';
import 'package:smart_parcel_dropbox/services/dropbox_service.dart';
import 'package:smart_parcel_dropbox/widgets/notification_badge.dart';
import 'package:smart_parcel_dropbox/widgets/smart_scanner_view.dart';
import 'package:smart_parcel_dropbox/widgets/camera_barcode_scanner_dialog.dart';
import 'package:smart_parcel_dropbox/screens/notifications_screen.dart';
import 'package:smart_parcel_dropbox/screens/owner_verify_screen.dart';
import 'package:smart_parcel_dropbox/screens/home_screen.dart';
import 'package:smart_parcel_dropbox/screens/login_screen.dart';
import 'package:smart_parcel_dropbox/screens/register_screen.dart';
import 'package:smart_parcel_dropbox/screens/splash_screen.dart';
import 'package:smart_parcel_dropbox/presentation/screens/profile/profile_tab.dart';
import 'package:smart_parcel_dropbox/widgets/startup_intro.dart';
import 'package:smart_parcel_dropbox/widgets/user_ui.dart';
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
  Future<Map<String, dynamic>?> getUserData(String userId) async => null;

  @override
  Future<Map<String, dynamic>?> getMe({Duration timeout = const Duration(seconds: 10)}) async => null;

  @override
  Stream<int> getUnreadNotificationsCount(String userId) => Stream<int>.value(14);
}

class MockDropboxService extends Mock implements DropboxService {}

void main() {
  final getIt = GetIt.instance;
  final startupClip = find.descendant(
    of: find.byType(StartupIntro),
    matching: find.byType(Image),
  );

  void showIntroFrame(WidgetTester tester, int index) {
    tester.widget<Image>(startupClip).frameBuilder!(
          tester.element(startupClip),
          const SizedBox.shrink(),
          index,
          false,
        );
  }

  Future<void> finishIntroPlayback(WidgetTester tester) async {
    showIntroFrame(tester, StartupIntro.frameCount - 1);
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump(StartupIntro.finalFrameHold);
  }

  setUp(() {
    getIt.reset();
    FlutterSecureStorage.setMockInitialValues({'pref_startup_intro_v1': 'true'});
    getIt.registerLazySingleton<NotificationService>(() => MockNotificationService());
    getIt.registerLazySingleton<WebSocketService>(() => MockWebSocketService());
    getIt.registerLazySingleton<ConnectivityService>(() => MockConnectivityService());
    getIt.registerLazySingleton<CacheService>(() => MockCacheService());
    getIt.registerLazySingleton<AuthService>(() => MockAuthService());
    getIt.registerLazySingleton<DatabaseService>(() => MockDatabaseService());
  });

  testWidgets('Main navbar uses accessible icons and compact tap targets',
      (tester) async {
    getIt.registerSingleton<DropboxService>(MockDropboxService());
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);

    Widget buildApp(double textScale) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const HomeScreen(),
        );

    Finder navigation() {
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      return find.byWidget(scaffold.bottomNavigationBar!);
    }

    double navigationHeight() => tester.getSize(navigation()).height;

    await tester.pumpWidget(buildApp(1));
    await tester.pumpAndSettle();
    expect(navigationHeight(), 58);

    Finder tabTarget(String label) => find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == label,
        );
    Finder highlight(String label) => find.descendant(
          of: tabTarget(label),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.alignment == Alignment.center &&
                widget.decoration is BoxDecoration,
          ),
        );
    expect(
      find.descendant(of: navigation(), matching: find.byType(Text)),
      findsNothing,
    );
    for (final label in ['Home', 'Orders', 'Dropbox', 'Profile']) {
      expect(find.byTooltip(label), findsOneWidget);
    }
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(tester.getSize(highlight('Home')), const Size(36, 32));
    expect(highlight('Orders'), findsNothing);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    final cabinetIcon = find.descendant(
      of: tabTarget('Dropbox'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter != null &&
            widget.size == const Size.square(22),
      ),
    );
    expect(tester.getSize(cabinetIcon), const Size.square(22));

    final ordersTarget = tabTarget('Orders');
    final ordersRect = tester.getRect(ordersTarget);
    expect(ordersRect.width, greaterThanOrEqualTo(48));
    expect(ordersRect.height, greaterThanOrEqualTo(48));
    final overlay = tester.widget<IconButton>(ordersTarget).style!.overlayColor!;
    expect(overlay.resolve({WidgetState.hovered}), Colors.transparent);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(ordersRect.center);
    await tester.pump();
    expect(tester.getSize(highlight('Orders')), const Size(36, 32));
    await mouse.moveTo(tester.getCenter(tabTarget('Home')));
    await tester.pump();
    expect(highlight('Orders'), findsNothing);
    expect(tester.getSize(highlight('Home')), const Size(36, 32));
    await mouse.removePointer();
    await tester.pump();

    await tester.longPress(ordersTarget);
    await tester.pumpAndSettle();
    expect(find.text('Orders'), findsOneWidget);
    Tooltip.dismissAllToolTips();
    await tester.pumpAndSettle();

    await tester.tapAt(Offset(ordersRect.center.dx, ordersRect.top + 2));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Orders'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
    expect(tester.widget<IconButton>(ordersTarget).isSelected, isTrue);
    expect(highlight('Home'), findsNothing);
    expect(tester.getSize(highlight('Orders')), const Size(36, 32));

    tester.view.physicalSize = const Size(450, 680);
    await tester.pumpAndSettle();
    expect(navigationHeight(), 58);

    tester.view.physicalSize = const Size(450, 800);
    await tester.pumpAndSettle();
    expect(navigationHeight(), 70);
    expect(tester.getSize(highlight('Orders')), const Size(38, 34));

    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpWidget(buildApp(1.8));
    await tester.pumpAndSettle();
    expect(navigationHeight(), 58);
    expect(find.byTooltip('Dropbox'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('App smoke test verifies responsive mobile centering', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Build our app and trigger a frame.
    await tester.pumpWidget(const SmartParcelDropBoxApp());

    expect(find.byType(SmartParcelDropBoxApp), findsOneWidget);
    final cabinet = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image == const AssetImage('assets/dropbox/smart-parcel-dropbox.png'),
    );
    await tester.pump();
    expect(cabinet, findsOneWidget);
    expect(find.byType(StartupIntro), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Starting up…'), findsOneWidget);
    final splashScaffoldCenter = tester.getCenter(find.byType(Scaffold).first);
    final splashTitleCenter = tester.getCenter(find.text('Smart Parcel Dropbox'));
    expect((splashTitleCenter.dx - splashScaffoldCenter.dx).abs(), lessThan(1.0));
    expect(tester.getCenter(cabinet).dx, closeTo(splashTitleCenter.dx, 1));

    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  for (final brightness in Brightness.values) {
    testWidgets('Login actions fit on a narrow screen in ${brightness.name}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.6),
            ),
            child: child!,
          ),
          home: const LoginScreen(),
        ),
      );

      final screen = tester.element(find.byType(LoginScreen));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        UserUi.dashboardColors(screen).background,
      );
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Fill demo account'), findsNothing);

      final signIn = find.widgetWithText(FilledButton, 'Sign in');
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      await tester.pumpAndSettle();
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Please enter password'), findsOneWidget);

      final showPassword = find.byTooltip('Show password');
      await tester.ensureVisible(showPassword);
      await tester.tap(showPassword);
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
        isFalse,
      );

      const email = 'resident@example.com';
      await tester.enterText(find.byType(TextFormField).first, email);
      final forgotPassword = find.text('Forgot password?');
      await tester.ensureVisible(forgotPassword);
      await tester.tap(forgotPassword);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(find.text('Reset password'), findsOneWidget);
      final resetEmail = find.descendant(
        of: dialog,
        matching: find.byType(EditableText),
      );
      final dialogContext = tester.element(resetEmail);
      final modalTheme = Theme.of(dialogContext);
      final colors = UserUi.dashboardColors(dialogContext);
      expect(modalTheme.dialogTheme.backgroundColor, colors.surface);
      expect(modalTheme.inputDecorationTheme.fillColor, colors.background);
      expect(
        modalTheme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        colors.foreground,
      );
      expect(tester.widget<EditableText>(resetEmail).controller.text, email);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final createAccount = find.text('Create account');
      await tester.ensureVisible(createAccount);
      await tester.tap(createAccount);
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('First launch plays the local intro, reveals the title, and signs in',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const SmartParcelDropBoxApp());
    await tester.pump();

    final intro = find.byType(StartupIntro);
    expect(startupClip, findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(find.text(StartupIntro.title), findsNothing);
    await tester.runAsync(() async {
      final data = await rootBundle.load(StartupIntro.asset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        expect(codec.frameCount, StartupIntro.frameCount);
        expect(codec.repetitionCount, 0);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 360);
        expect(frame.image.height, 640);
        frame.image.dispose();
        var finalFrameDuration = frame.duration;
        for (var index = 1; index < codec.frameCount; index++) {
          final next = await codec.getNextFrame();
          finalFrameDuration = next.duration;
          next.image.dispose();
        }
        expect(finalFrameDuration, StartupIntro.finalFrameHold);
      } finally {
        codec.dispose();
      }
    });

    showIntroFrame(tester, 0);
    await tester.tapAt(tester.getCenter(startupClip));
    // Even if the nominal runtime has passed, the title must wait for the drop.
    await tester.pump(const Duration(seconds: 7));
    expect(intro, findsOneWidget);
    expect(find.text(StartupIntro.title), findsNothing);
    expect(find.text('Welcome back'), findsNothing);

    showIntroFrame(tester, StartupIntro.frameCount - 2);
    await tester.pump(const Duration(milliseconds: 250));
    expect(intro, findsOneWidget);

    await finishIntroPlayback(tester);
    expect(intro, findsNothing);
    expect(find.text('Smart Parcel Dropbox'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      await const FlutterSecureStorage().read(key: 'pref_startup_intro_v1'),
      'true',
    );
  });

  testWidgets('Startup continues if the intro fails to load',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const SmartParcelDropBoxApp());
    await tester.pump();
    tester.widget<Image>(startupClip).errorBuilder!(
          tester.element(startupClip),
          StateError('Unable to load the startup clip'),
          null,
        );
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump();
    expect(find.byType(StartupIntro), findsNothing);
    expect(find.text('Starting up…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('Dev mode plays the intro on each launch until turned off',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'pref_startup_intro_v1': 'true',
      'pref_dropbox_dev_mode': 'true',
    });
    final intro = find.byType(StartupIntro);

    for (var launch = 0; launch < 2; launch++) {
      await tester.pumpWidget(const SmartParcelDropBoxApp());
      await tester.pump();
      expect(intro, findsOneWidget);

      await finishIntroPlayback(tester);
      await tester.pump(const Duration(milliseconds: 650));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await const FlutterSecureStorage().write(
      key: 'pref_dropbox_dev_mode',
      value: 'false',
    );
    await tester.pumpWidget(const SmartParcelDropBoxApp());
    await tester.pump();
    expect(intro, findsNothing);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('Dev mode replays the complete intro with a fresh image stream',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileTab(
            userId: 'user-1',
            databaseService: getIt<DatabaseService>(),
            authService: getIt<AuthService>(),
            biometricService: BiometricService(),
            supportsDevMode: true,
            devModeEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final replay = find.text('Replay startup intro');
    await tester.ensureVisible(replay);
    await tester.tap(replay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final firstImage = tester.widget<Image>(startupClip);
    await finishIntroPlayback(tester);
    expect(find.text(StartupIntro.title), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(StartupIntro), findsNothing);

    await tester.tap(replay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      (tester.widget<Image>(startupClip).image as AssetImage).bundle,
      isNot(same((firstImage.image as AssetImage).bundle)),
    );
    await finishIntroPlayback(tester);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(StartupIntro), findsNothing);
  });

  testWidgets('Startup status fits enlarged text without loading motion',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'pref_dropbox_dev_mode': 'true'});
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const SplashScreen(),
      ),
    );

    final status = find.text('Starting up…');
    await tester.ensureVisible(status);
    await tester.pump();
    expect(status.hitTestable(), findsOneWidget);
    expect(find.byType(StartupIntro), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image == const AssetImage('assets/dropbox/smart-parcel-dropbox.png'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 650));
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
    await tester.binding.setSurfaceSize(const Size(320, 600));
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.reset);

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

    expect(find.text('Waybill barcode scanner'), findsOneWidget);
    final scanner = tester.element(find.byType(CameraBarcodeScannerDialog));
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, UserUi.dashboardColors(scanner).surface);
    expect(sheet.showDragHandle, isTrue);
    await tester.enterText(find.byType(TextField), 'SPXPH987654321');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    final useBarcode = find.widgetWithText(FilledButton, 'Use barcode');
    await tester.ensureVisible(useBarcode);
    await tester.tap(useBarcode);
    await tester.pumpAndSettle();

    expect(scanned, isNotNull);
    expect(scanned!.trackingId, 'SPXPH987654321');
    expect(scanned!.detectedCourier, 'Shopee (SPX)');
  });
}
