import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'config/firebase_options.dart';
import 'config/user_theme.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('Background message: ${message.notification?.title}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const SmartParcelDropBoxApp());
}

class SmartParcelDropBoxApp extends StatefulWidget {
  const SmartParcelDropBoxApp({super.key});

  @override
  State<SmartParcelDropBoxApp> createState() => _SmartParcelDropBoxAppState();
}

class _SmartParcelDropBoxAppState extends State<SmartParcelDropBoxApp> {
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
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
