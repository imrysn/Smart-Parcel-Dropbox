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

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _combinedText =>
      '${type.toLowerCase()} ${title.toLowerCase()} ${message.toLowerCase()}';

  /// Whether this alert relates to parcel deliveries, pickups, or rider dispatches.
  bool get isDeliveryAlert {
    final text = _combinedText;
    return type == 'delivery' ||
        type == 'parcel_delivered' ||
        type == 'parcel_retrieved' ||
        type == 'status_update' ||
        text.contains('parcel') ||
        text.contains('pickup') ||
        text.contains('rider') ||
        text.contains('delivery') ||
        text.contains('delivered') ||
        text.contains('dispatch');
  }

  /// Whether this alert relates to access, scans, household sharing, or security.
  bool get isSecurityAlert {
    final text = _combinedText;
    return type == 'access_denied' ||
        type == 'access_granted' ||
        type == 'scan_attempt' ||
        text.contains('owner') ||
        text.contains('verify') ||
        text.contains('denied') ||
        text.contains('scan') ||
        text.contains('security') ||
        text.contains('household') ||
        text.contains('member') ||
        text.contains('access');
  }

  /// Chronological section header using calendar day boundaries.
  String getDateGroupLabel() {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(local.year, local.month, local.day);
    final dayDiff = today.difference(itemDay).inDays;

    if (dayDiff <= 0) return 'Today';
    if (dayDiff == 1) return 'Yesterday';
    if (dayDiff < 7) return 'This Week';
    return 'Earlier';
  }

  /// Concise timestamp suited for notification card headers.
  String getCompactTimestamp() {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inSeconds < 60 && diff.inSeconds >= 0) return 'Just now';
    if (diff.inMinutes < 60 && diff.inMinutes >= 0) return '${diff.inMinutes}m ago';
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return _formatTime(local);
    }
    if (local.year == now.year) {
      return '${_monthNames[local.month - 1]} ${local.day} · ${_formatTime(local)}';
    }
    return '${_monthNames[local.month - 1]} ${local.day}, ${local.year}';
  }

  /// Get formatted date and time string
  String getFormattedDateTime() {
    final date = timestamp.toLocal();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${_formatTime(date)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago · ${_formatTime(date)}';
    } else {
      return '${_monthNames[date.month - 1]} ${date.day}, ${date.year} · ${_formatTime(date)}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Get icon identifier based on notification type and semantic content.
  String getIconName() {
    final text = _combinedText;
    if (type == 'access_denied' || text.contains('denied') || text.contains('failed') || text.contains('unauthorized')) {
      return 'cancel';
    }
    if (type == 'parcel_delivered' || text.contains('delivered') || text.contains('dropped off')) {
      return 'inventory';
    }
    if (type == 'parcel_retrieved' || text.contains('retrieved') || text.contains('collected')) {
      return 'check_box';
    }
    if (type == 'access_granted' || text.contains('owner') || text.contains('granted') || text.contains('verified')) {
      return 'check_circle';
    }
    if (type == 'scan_attempt' || text.contains('scan') || text.contains('qr')) {
      return 'qr_code_scanner';
    }
    if (text.contains('household') || text.contains('member')) {
      return 'group';
    }
    if (type == 'delivery' || text.contains('pickup') || text.contains('rider') || text.contains('dispatch')) {
      return 'local_shipping';
    }
    if (type == 'status_update') {
      return 'update';
    }
    return 'notifications';
  }

  /// Get semantic accent color based on notification type and content.
  int getColorValue() {
    final text = _combinedText;
    if (type == 'access_denied' || text.contains('denied') || text.contains('failed') || text.contains('unauthorized')) {
      return 0xFFDC2626; // Red
    }
    if (type == 'access_granted' ||
        type == 'parcel_delivered' ||
        type == 'parcel_retrieved' ||
        text.contains('delivered') ||
        text.contains('retrieved') ||
        text.contains('collected') ||
        text.contains('granted')) {
      return 0xFF16A34A; // Green
    }
    if (type == 'scan_attempt' || type == 'status_update' || text.contains('owner') || text.contains('verify')) {
      return 0xFF2563EB; // Blue
    }
    return 0xFFFF9800; // Signature Orange
  }
}

