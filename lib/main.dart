import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'config/firebase_options.dart';
import 'config/user_theme.dart';
import 'services/notification_service.dart';
import 'services/service_locator.dart';
import 'services/connectivity_service.dart';
import 'screens/splash_screen.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background message: ${message.notification?.title}');
}

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize Service Locator (includes Cache Service)
    await setupServiceLocator();

    // Start connectivity monitoring
    final connectivityService = getIt<ConnectivityService>();
    connectivityService.startMonitoring();

    runApp(const SmartParcelDropBoxApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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
