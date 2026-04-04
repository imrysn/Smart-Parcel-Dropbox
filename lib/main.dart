import 'dart:async';
import 'package:flutter/material.dart';
import 'config/user_theme.dart';
import 'services/notification_service.dart';
import 'services/service_locator.dart';
import 'services/connectivity_service.dart';
import 'services/websocket_service.dart';
import 'screens/splash_screen.dart';
import 'screens/owner_verify_screen.dart';

/// Global navigator key — lets us navigate from outside the widget tree
/// (e.g. from a notification tap handler that runs before any widget is ready).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Service Locator (includes Cache Service)
    await setupServiceLocator();

    // Start connectivity monitoring
    final connectivityService = getIt<ConnectivityService>();
    connectivityService.startMonitoring();

    runApp(const SmartParcelDropBoxApp());
  }, (error, stack) {
    debugPrint('Error: $error');
  });
}

class SmartParcelDropBoxApp extends StatefulWidget {
  const SmartParcelDropBoxApp({super.key});

  @override
  State<SmartParcelDropBoxApp> createState() => _SmartParcelDropBoxAppState();
}

class _SmartParcelDropBoxAppState extends State<SmartParcelDropBoxApp> {
  late final NotificationService _notificationService;
  StreamSubscription<Map<String, dynamic>>? _ownerAlertSub;

  @override
  void initState() {
    super.initState();
    _notificationService = getIt<NotificationService>();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Initialize the notification plugin with our custom tap handler
    await _notificationService.initialize(
      onNotificationTap: _handleNotificationTap,
    );

    // Subscribe to the ownerAccessAlert socket event pushed by the backend
    // whenever the hardware shows the owner QR code on its LCD screen.
    _ownerAlertSub = WebSocketService().ownerAccessAlerts.listen((_) {
      debugPrint('[main] ownerAccessAlert received → showing push notification');
      _notificationService.showOwnerAccessAlert();
    });
  }

  /// Called when the user taps any local notification.
  /// Routes 'owner_verify' payload → OwnerVerifyScreen.
  void _handleNotificationTap(String? payload) {
    if (payload == 'owner_verify') {
      debugPrint('[main] Notification tapped: opening OwnerVerifyScreen');
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const OwnerVerifyScreen()),
      );
    }
  }

  @override
  void dispose() {
    _ownerAlertSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Parcel Drop Box',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: UserTheme.getTheme(Brightness.light),
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}

