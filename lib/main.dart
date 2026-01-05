import 'dart:async';
import 'package:flutter/material.dart';
import 'config/user_theme.dart';
import 'services/notification_service.dart';
import 'services/service_locator.dart';
import 'services/connectivity_service.dart';
import 'screens/splash_screen.dart';

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
  late final ConnectivityService _connectivityService;

  @override
  void initState() {
    super.initState();
    _notificationService = getIt<NotificationService>();
    _connectivityService = getIt<ConnectivityService>();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _notificationService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Parcel Drop Box',
      debugShowCheckedModeBanner: false,
      theme: UserTheme.theme,
      home: const SplashScreen(),
    );
  }
}
