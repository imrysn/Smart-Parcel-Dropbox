import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification Service for Smart Parcel Drop Box System
/// Shows system tray notifications when parcel status changes arrive
/// via the trackingStatusChanged Socket.io event (Phase 4).
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'parcel_updates';
  static const _channelName = 'Parcel Updates';
  static const _channelDesc =
      'Real-time notifications when your parcel is delivered or picked up';

  /// Call once on app start (inside _initializeServices in main.dart)
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

    debugPrint('[Notifications] Initialized: channel=$_channelId');
  }

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

  // ── Stubs retained for interface compatibility ──────────────────────────
  Future<String?> getToken() async => null;
  Future<void> subscribeToTopic(String topic) async {}
  Future<void> unsubscribeFromTopic(String topic) async {}
}
