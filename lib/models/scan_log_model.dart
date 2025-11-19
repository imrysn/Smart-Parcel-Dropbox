import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for scan access logs
class ScanLogModel {
  final String id;
  final String scannedCode; // QR code or barcode that was scanned
  final bool accessGranted; // Whether access was granted or denied
  final DateTime timestamp;
  final String? trackingId; // Associated tracking ID if found
  final String? userId; // User ID if tracking ID was found
  final String? reason; // Reason for denial if access was denied

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
      'trackingId': trackingId,
      'userId': userId,
      'reason': reason,
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

  /// Get full formatted date and time
  String getFullFormattedDateTime() {
    final date = timestamp;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute:$second';
  }
}

