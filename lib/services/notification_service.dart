import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/notification_model.dart';
import '../config/api_config.dart';

/// Enhanced Notification Service - Handles notification management
///
/// Single Responsibility: Manage user notifications and push notification setup
class NotificationService {
  static NotificationService? _instance;

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

  // ── Stream / cache for in-app notifications ───────────────────────────────
  final _notificationController =
      StreamController<List<NotificationModel>>.broadcast();
  List<NotificationModel> _cachedNotifications = [];

  // Public getters
  List<NotificationModel> get cachedNotifications => _cachedNotifications;
  Stream<List<NotificationModel>> get notificationStream =>
      _notificationController.stream;

  // ── Initialization ────────────────────────────────────────────────────────

  /// Call once on app start (inside _initializeServices in main.dart).
  /// Sets up both the local-notification plugin AND the in-app stream.
  Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
        InitializationSettings(android: androidSettings);

    await _notifications.initialize(settings);

    // Create high-importance channel for Android 8.0+
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    debugPrint('✅ Notification service initialized: channel=$_channelId');
  }

  // ── System tray / push notifications ─────────────────────────────────────

  /// Show a system notification when a parcel status changes.
  /// Called by DatabaseService when 'trackingStatusChanged' socket event fires.
  Future<void> showDeliveryNotification({
    required String trackingId,
    required String status,
  }) async {
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
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
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
      final response = await http.get(
        Uri.parse('${ApiConfig.notifications}/user/$userId'),
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
      await http.post(
        Uri.parse(ApiConfig.notifications),
        headers: {'Content-Type': 'application/json'},
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
      await http.patch(
        Uri.parse('${ApiConfig.notifications}/$notificationId/read'),
      );
    } catch (e) {
      debugPrint('Error marking read: $e');
    }
  }

  /// Mark all notifications as read
  Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      await http.patch(
        Uri.parse('${ApiConfig.notifications}/user/$userId/read'),
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
