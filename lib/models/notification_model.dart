// Firestore removed

/// Model for in-app notifications
class NotificationModel {
  final String id;
  final String userId;
  final String type; // scan_attempt, delivery, status_update, access_granted, access_denied
  final String title;
  final String message;
  final bool isRead;
  final DateTime timestamp;
  final String? trackingId;
  final Map<String, dynamic>? data; // Additional data for the notification

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.timestamp,
    this.trackingId,
    this.data,
  });

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? type,
    String? title,
    String? message,
    bool? isRead,
    DateTime? timestamp,
    String? trackingId,
    Map<String, dynamic>? data,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp ?? this.timestamp,
      trackingId: trackingId ?? this.trackingId,
      data: data ?? this.data,
    );
  }

  static DateTime _safeParseTimestamp(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is DateTime) return val;
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return DateTime.tryParse(val.toString()) ?? DateTime.now();
  }

  /// Create NotificationModel from Map (JSON)
  factory NotificationModel.fromMap(Map<String, dynamic> data) {
    return NotificationModel(
      id: data['id'] ?? data['_id'] ?? '',
      userId: data['userId'] ?? '',
      type: data['type'] ?? '',
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      isRead: data['isRead'] ?? false,
      timestamp: _safeParseTimestamp(data['timestamp']),
      trackingId: data['trackingId'],
      data: data['data'] != null ? Map<String, dynamic>.from(data['data']) : null,
    );
  }

  /// Convert to Map for API
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'title': title,
      'message': message,
      'isRead': isRead,
      'timestamp': timestamp.toIso8601String(),
      'trackingId': trackingId,
      'data': data,
    };
  }

  /// Get formatted date and time string
  String getFormattedDateTime() {
    final date = timestamp;
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
      }
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${_formatTime(date)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago at ${_formatTime(date)}';
    } else {
      return '${_formatDate(date)} at ${_formatTime(date)}';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Get icon based on notification type
  String getIconName() {
    switch (type) {
      case 'scan_attempt':
        return 'qr_code_scanner';
      case 'access_granted':
        return 'check_circle';
      case 'access_denied':
        return 'cancel';
      case 'delivery':
        return 'local_shipping';
      case 'status_update':
        return 'update';
      case 'parcel_delivered':
        return 'inventory';
      case 'parcel_retrieved':
        return 'check_box';
      default:
        return 'notifications';
    }
  }

  /// Get color based on notification type
  int getColorValue() {
    switch (type) {
      case 'access_granted':
      case 'parcel_delivered':
      case 'parcel_retrieved':
        return 0xFF4CAF50; // Green
      case 'access_denied':
        return 0xFFF44336; // Red
      case 'scan_attempt':
      case 'status_update':
        return 0xFF2196F3; // Blue
      case 'delivery':
        return 0xFFFF9800; // Orange
      default:
        return 0xFF757575; // Grey
    }
  }
}

