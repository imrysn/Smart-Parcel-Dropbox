import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/notification_model.dart';
import '../config/api_config.dart';
import 'service_locator.dart';
import 'auth_service.dart';

/// Enhanced Notification Service - Handles notification management
///
/// Single Responsibility: Manage user notifications and push notification setup
class NotificationService {
  static NotificationService? _instance;
  bool _isInitialized = false;

  factory NotificationService() {
    _instance ??= NotificationService._internal();
    return _instance!;
  }

  NotificationService._internal();

  // ── flutter_local_notifications setup ────────────────────────────────────
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'parcel_updates';
  static const _channelName = 'Parcel Updates';
  static const _channelDesc =
      'Real-time notifications when your parcel is delivered or picked up';

  // Dedicated channel for owner access alerts
  static const _ownerChannelId   = 'owner_access';
  static const _ownerChannelName = 'Owner Access Alerts';
  static const _ownerChannelDesc =
      'Urgent alerts when someone attempts owner-level access to your dropbox';

  // ── Stream / cache for in-app notifications ───────────────────────────────
  final _notificationController =
      StreamController<List<NotificationModel>>.broadcast();
  List<NotificationModel> _cachedNotifications = [];
  final _authService = getIt<AuthService>();

  // Public getters
  List<NotificationModel> get cachedNotifications => _cachedNotifications;
  Stream<List<NotificationModel>> get notificationStream =>
      _notificationController.stream;

  // ── Initialization ────────────────────────────────────────────────────────

  /// Call once on app start (inside _initializeServices in main.dart).
  /// Sets up both the local-notification plugin AND the in-app stream.
  ///
  /// [onNotificationTap] — optional callback invoked with the notification
  /// payload when the user taps a system notification. Use this to navigate
  /// to the correct screen (e.g. OwnerVerifyScreen for 'owner_verify').
  Future<void> initialize({void Function(String? payload)? onNotificationTap}) async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
        InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Delegate to the injected handler first (navigation logic in main.dart)
        onNotificationTap?.call(response.payload);
        _onNotificationResponse(response);
      },
    );

    // Create high-importance channel for Android 8.0+
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Owner access alert channel — max importance so it rings even in DND
    const AndroidNotificationChannel ownerChannel = AndroidNotificationChannel(
      _ownerChannelId,
      _ownerChannelName,
      description: _ownerChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.createNotificationChannel(ownerChannel);

    // Request Android 13+ permission
    await androidPlugin?.requestNotificationsPermission();

    _isInitialized = true;
    debugPrint('✅ Notification service initialized: channel=$_channelId');
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId == 'action_unlock') {
      debugPrint('[Notifications] Unlock action triggered via notification');
      // Logic for unlocking will be handled if needed (e.g., via background service or navigation)
    }
  }

  // ── Owner access alert notification ─────────────────────────────────────

  /// Show an urgent notification when the hardware enters Owner Verification
  /// mode (QR displayed on LCD). Tapping the notification will open the
  /// Verify Owner Access camera screen via the [payload] `'owner_verify'`.
  Future<void> showOwnerAccessAlert() async {
    if (!_isInitialized) {
      debugPrint('[Notifications] Warning: showOwnerAccessAlert called before initialization');
      return;
    }
    const title = '🔒 Dropbox Access Alert';
    const body  = 'Someone is accessing your dropbox. Are you the owner? Tap to verify.';
    try {
      await _notifications.show(
        // Fixed ID — a new alert replaces the previous one instead of stacking
        99901,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _ownerChannelId,
            _ownerChannelName,
            channelDescription: _ownerChannelDesc,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            // Feature #4: "I Didn't Request This" quick-dismiss action
            actions: [
              AndroidNotificationAction(
                'action_not_me',
                "❌ I Didn't Request This",
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
        ),
        payload: 'owner_verify',
      );
      debugPrint('[Notifications] Owner access alert shown');
    } catch (e) {
      debugPrint('[Notifications] Error showing owner access alert: $e');
    }
  }

  // ── System tray / push notifications ─────────────────────────────────────

  /// Show a system notification when a parcel status changes.
  /// Called by DatabaseService when 'trackingStatusChanged' socket event fires.
  Future<void> showDeliveryNotification({
    required String trackingId,
    required String status,
  }) async {
    if (!_isInitialized) {
      debugPrint('[Notifications] Warning: showDeliveryNotification called before initialization');
      return;
    }
    String title;
    String body;

    switch (status) {
      case 'delivered':
        title = '📦 Parcel Delivered!';
        body = 'Your parcel ($trackingId) is now in the dropbox.';
        break;
      case 'retrieved':
        title = '✅ Parcel Picked Up!';
        body = 'Your parcel ($trackingId) was retrieved successfully.';
        break;
      default:
        title = 'Parcel Update';
        body = 'Order $trackingId status changed to $status.';
    }

    try {
      await _notifications.show(
        trackingId.hashCode.abs(), // unique id per tracking
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            actions: (status == 'delivered') 
              ? [
                  const AndroidNotificationAction(
                    'action_unlock',
                    '🔓 UNLOCK NOW',
                    showsUserInterface: true,
                  ),
                ] : null,
          ),
        ),
      );
      debugPrint('[Notifications] Shown: $title');
    } catch (e) {
      debugPrint('[Notifications] Error showing notification: $e');
    }
  }

  // ── Interface compatibility stubs ─────────────────────────────────────────
  Future<String?> getToken() async => null;
  Future<void> subscribeToTopic(String topic) async {
    debugPrint('Subscribed to topic: $topic');
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    debugPrint('Unsubscribed from topic: $topic');
  }

  // ── In-app notification API (HTTP + streams) ──────────────────────────────

  /// Refresh notifications for a user
  Future<void> refreshNotifications(String userId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.notifications}/user/$userId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        final list = data.map((e) => NotificationModel.fromMap(e)).toList();
        _cachedNotifications = list;
        _notificationController.add(list);
      }
    } catch (e) {
      debugPrint('Error refreshing notifications: $e');
    }
  }

  /// Create a notification
  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? trackingId,
    Map<String, dynamic>? data,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      await http.post(
        Uri.parse(ApiConfig.notifications),
        headers: headers,
        body: jsonEncode({
          'userId': userId,
          'type': type,
          'title': title,
          'message': message,
          'trackingId': trackingId,
          'data': data,
        }),
      );
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  /// Get notifications for a user
  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    if (_cachedNotifications.isNotEmpty) {
      Timer.run(() => _notificationController.add(_cachedNotifications));
    }
    refreshNotifications(userId);
    return _notificationController.stream;
  }

  /// Get unread count
  Stream<int> getUnreadNotificationsCount(String userId) {
    return getUserNotifications(userId)
        .map((list) => list.where((n) => !n.isRead).length);
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      await http.patch(
        Uri.parse('${ApiConfig.notifications}/$notificationId/read'),
        headers: headers,
      );
    } catch (e) {
      debugPrint('Error marking read: $e');
    }
  }

  /// Mark all notifications as read
  Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      await http.patch(
        Uri.parse('${ApiConfig.notifications}/user/$userId/read'),
        headers: headers,
      );
      refreshNotifications(userId);
    } catch (e) {
      debugPrint('Error marking all read: $e');
    }
  }

  /// Helper: Create scan attempt notification
  Future<void> createScanAttemptNotification({
    required String userId,
    required String scannedCode,
    required bool accessGranted,
    String? trackingId,
    String? reason,
  }) async {
    String title;
    String message;
    String type;

    if (accessGranted) {
      type = 'access_granted';
      title = 'Access Granted';
      message = trackingId != null
          ? 'Access granted for tracking ID: $trackingId'
          : 'Access granted for code: $scannedCode';
    } else {
      type = 'access_denied';
      title = 'Access Denied';
      message = reason ?? 'Access denied for code: $scannedCode';
    }

    await createNotification(
      userId: userId,
      type: type,
      title: title,
      message: message,
      trackingId: trackingId,
      data: {
        'scannedCode': scannedCode,
        'accessGranted': accessGranted,
        'reason': reason,
      },
    );
  }

  /// Helper: Create delivery notification
  Future<void> createDeliveryNotification({
    required String userId,
    required String trackingId,
    required String shopName,
  }) async {
    await createNotification(
      userId: userId,
      type: 'parcel_delivered',
      title: 'Parcel Delivered',
      message: 'Your parcel from $shopName has been delivered to the dropbox.',
      trackingId: trackingId,
      data: {'shopName': shopName},
    );
  }

  /// Helper: Create status update notification
  Future<void> createStatusUpdateNotification({
    required String userId,
    required String trackingId,
    required String status,
    required String shopName,
  }) async {
    String title = 'Status Updated';
    String message =
        'Your order from $shopName is now ${_getStatusText(status)}.';

    await createNotification(
      userId: userId,
      type: 'status_update',
      title: title,
      message: message,
      trackingId: trackingId,
      data: {
        'status': status,
        'shopName': shopName,
      },
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'in_transit':
        return 'In Transit';
      case 'delivered':
        return 'Delivered';
      case 'retrieved':
        return 'Retrieved';
      default:
        return status;
    }
  }

  /// Dispose resources
  void dispose() {
    _notificationController.close();
  }

  /// Reset singleton instance
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
