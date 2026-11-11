import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'config/user_theme.dart';
import 'services/notification_service.dart';
import 'services/delivery_push_service.dart';
import 'services/service_locator.dart';
import 'services/connectivity_service.dart';
import 'services/websocket_service.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
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

class _SmartParcelDropBoxAppState extends State<SmartParcelDropBoxApp> with WidgetsBindingObserver {
  late final NotificationService _notificationService;
  StreamSubscription<Map<String, dynamic>>? _ownerAlertSub;
  StreamSubscription<bool>? _connectionSub;
  Map<String, dynamic>? _pendingOwnerTap;
  String? _lastOwnerAlert;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationService = getIt<NotificationService>();
    AuthService.onSessionExpired = _handleSessionExpired;
    _initializeServices();
  }

  void _handleSessionExpired() {
    _pendingOwnerTap = null;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Your session expired. Please sign in again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _initializeServices() async {
    final socket = getIt<WebSocketService>();
    try {
      await _notificationService.initialize(onNotificationTap: _handleNotificationTap);
    } catch (error) {
      debugPrint('Local notifications unavailable: $error');
    }
    if (!mounted) return;
    if (getIt.isRegistered<DeliveryPushService>()) {
      final push = getIt<DeliveryPushService>();
      final userId = getIt<DatabaseService>().sessionUserId;
      if (userId == null) {
        unawaited(push.initialize());
      } else {
        unawaited(push.sync(userId));
      }
    }
    _ownerAlertSub = socket.ownerAccessAlerts.listen((data) {
      final userId = getIt<DatabaseService>().sessionUserId;
      final alertId = data['alertId'];
      final expiresAt = data['expiresAt'];
      if (userId == null || alertId is! String || expiresAt is! int ||
          expiresAt <= DateTime.now().millisecondsSinceEpoch) {
        return;
      }
      final key = '$userId:$alertId';
      if (key == _lastOwnerAlert) return;
      _lastOwnerAlert = key;
      _notificationService.showOwnerAccessAlert(userId: userId, expiresAt: expiresAt);
    });
    _connectionSub = socket.connectionStatusStream.listen((connected) {
      if (connected) _openPendingOwnerTap();
    });
    if (socket.isConnected) {
      socket.emit('requestOwnerAlert', null);
      _openPendingOwnerTap();
    }
  }

  void _handleNotificationTap(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic> && data['type'] == 'owner_verify') {
        _pendingOwnerTap = data;
        _openPendingOwnerTap();
      } else if (data is Map<String, dynamic> && getIt.isRegistered<DeliveryPushService>()) {
        getIt<DeliveryPushService>().handleTap(data);
      }
    } on FormatException {
      // Ignore payloads from an earlier version of the app.
    }
  }

  void _openPendingOwnerTap() {
    final data = _pendingOwnerTap;
    final userId = getIt<DatabaseService>().sessionUserId;
    final navigator = navigatorKey.currentState;
    if (data == null || userId == null || navigator == null || !getIt<WebSocketService>().isConnected) return;
    _pendingOwnerTap = null;
    final expiresAt = data['expiresAt'];
    if (data['userId'] != userId || expiresAt is! int || expiresAt <= DateTime.now().millisecondsSinceEpoch) return;
    navigator.push(MaterialPageRoute(builder: (_) => const OwnerVerifyScreen()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final database = getIt<DatabaseService>();
    final userId = database.sessionUserId;
    if (userId == null) return;
    if (getIt.isRegistered<DeliveryPushService>()) {
      unawaited(getIt<DeliveryPushService>().sync(userId));
    }
    unawaited(database.initSocket(userId));
    unawaited(database.refreshSession());
    final socket = getIt<WebSocketService>();
    if (socket.isConnected) {
      socket.emit('requestOwnerAlert', null);
      socket.requestEsp32Status();
      socket.requestDoorStatus();
      _openPendingOwnerTap();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AuthService.onSessionExpired = null;
    _ownerAlertSub?.cancel();
    _connectionSub?.cancel();
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

