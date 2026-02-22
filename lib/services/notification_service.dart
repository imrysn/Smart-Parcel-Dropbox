import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:async';
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

  final _notificationController =
      StreamController<List<NotificationModel>>.broadcast();
  List<NotificationModel> _cachedNotifications = [];

  // Public getters
  List<NotificationModel> get cachedNotifications => _cachedNotifications;
  Stream<List<NotificationModel>> get notificationStream =>
      _notificationController.stream;

  /// Initialize notification service (for push notifications)
  Future<void> initialize() async {
    debugPrint('✅ Notification service initialized');
    // In a real implementation, initialize push notification service here
  }

  /// Get FCM token for the device
  Future<String?> getToken() async {
    return 'custom_mongodb_token';
  }

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    debugPrint('Subscribed to topic: $topic');
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    debugPrint('Unsubscribed from topic: $topic');
  }

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
