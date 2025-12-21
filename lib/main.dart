import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'config/firebase_options.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Colors.grey[50],
        ),
      ),
      builder: (context, child) {
        return StreamBuilder<bool>(
          stream: _connectivityService.isConnected,
          builder: (context, snapshot) {
            final isConnected = snapshot.data ?? true;
            
            return Column(
              children: [
                if (!isConnected)
                  Container(
                    width: double.infinity,
                    color: Colors.red,
                    padding: const EdgeInsets.all(8),
                    child: const Text(
                      'No Internet Connection',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(child: child!),
              ],
            );
          },
        );
      },
      home: const SplashScreen(),
    );
  }
}
