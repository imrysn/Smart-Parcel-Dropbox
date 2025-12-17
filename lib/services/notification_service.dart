import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Notification Service for Smart Parcel Drop Box System
/// Handles push notifications for delivery updates
class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initialize notification service
  Future<void> initialize() async {
    try {
      // Request permission for iOS
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted notification permission');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        debugPrint('User granted provisional notification permission');
      } else {
        debugPrint('User declined or has not accepted notification permission');
      }

      // Get FCM token (optimized)
      final token = await _getTokenSafely();
      if (token != null && token.isNotEmpty) {
        debugPrint(
            'FCM Token: ${token.substring(0, 20)}...'); // Truncate for privacy
      }

      // Set up listeners only when needed
      _setupMessageHandlers();
    } catch (e) {
      debugPrint('Failed to initialize notifications: $e');
    }
  }

  /// Safely get FCM token
  Future<String?> _getTokenSafely() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Setup message handlers with error handling
  void _setupMessageHandlers() {
    try {
      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background messages
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
    } catch (e) {
      debugPrint('Error setting up message handlers: $e');
    }
  }

  /// Get FCM token for the device
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('Error unsubscribing from topic: $e');
    }
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received:');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
    debugPrint('Data: ${message.data}');

    // You can show a local notification here or update UI
    // For now, we'll just log it
  }

  /// Handle background messages (when app is opened from notification)
  void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint('Background message opened:');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
    debugPrint('Data: ${message.data}');

    // Navigate to specific screen based on message data
    // This will be handled in the main app
  }
}
