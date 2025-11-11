import 'package:cloud_firestore/cloud_firestore.dart';

/// Model class for scan log entries
/// Records every QR/barcode scan attempt at the drop box
class ScanLogModel {
  final String id;
  final String scannedCode;
  final bool accessGranted;
  final DateTime timestamp;
  final String? trackingId;
  final String? userId;
  final String? reason;

  ScanLogModel({
    required this.id,
    required this.scannedCode,
    required this.accessGranted,
    required this.timestamp,
    this.trackingId,
    this.userId,
    this.reason,
  });

  /// Create ScanLogModel from Firestore document
  factory ScanLogModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    
    return ScanLogModel(
      id: doc.id,
      scannedCode: data['scannedCode'] ?? '',
      accessGranted: data['accessGranted'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      trackingId: data['trackingId'],
      userId: data['userId'],
      reason: data['reason'],
    );
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'scannedCode': scannedCode,
      'accessGranted': accessGranted,
      'timestamp': Timestamp.fromDate(timestamp),
      if (trackingId != null) 'trackingId': trackingId,
      if (userId != null) 'userId': userId,
      if (reason != null) 'reason': reason,
    };
  }

  /// Get formatted timestamp string
  String getFormattedTimestamp() {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  /// Get status text
  String getStatusText() {
    if (accessGranted) {
      return 'Access Granted';
    } else {
      return reason ?? 'Access Denied';
    }
  }

  /// Get status color indicator
  String getStatusColor() {
    return accessGranted ? 'green' : 'red';
  }
}
