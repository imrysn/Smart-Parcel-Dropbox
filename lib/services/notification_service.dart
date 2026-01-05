import 'package:flutter/foundation.dart';

/// Notification Service for Smart Parcel Drop Box System
/// Stubbed out version (previously used Firebase Messaging)
class NotificationService {
  /// Initialize notification service
  Future<void> initialize() async {
    debugPrint('Notification service initialized (STUB)');
    // In a real MongoDB-only system, you would initialize 
    // WebSocket listeners here to show local notifications.
  }

  /// Get FCM token for the device
  Future<String?> getToken() async {
    return 'custom_mongodb_token';
  }

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    debugPrint('Subscribed to topic: $topic (STUB)');
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    debugPrint('Unsubscribed from topic: $topic (STUB)');
  }
}
