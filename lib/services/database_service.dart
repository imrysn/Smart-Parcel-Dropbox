import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/tracking_model.dart';
import '../models/scan_log_model.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';

/// Database Service for Smart Parcel Drop Box System
/// Handles all Firestore operations for tracking IDs and delivery logs
class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collections
  final String _trackingCollection = 'tracking_ids';
  final String _deliveryLogsCollection = 'delivery_logs';
  final String _usersCollection = 'users';
  final String _scanLogsCollection = 'scan_logs';
  final String _notificationsCollection = 'notifications';
  final String _deviceControlCollection = 'device_control';

  /// Register a new tracking ID for a user
  Future<void> registerTrackingId({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  }) async {
    try {
      await _firestore.collection(_trackingCollection).doc(trackingId).set({
        'trackingId': trackingId,
        'userId': userId,
        'shopName': shopName,
        'status': 'pending', // pending, in_transit, delivered, retrieved
        'registeredAt': FieldValue.serverTimestamp(),
        'expectedDeliveryDate': expectedDeliveryDate,
        'deliveredAt': null,
        'retrievedAt': null,
      });
    } catch (e) {
      throw 'Failed to register tracking ID: $e';
    }
  }

  /// Get all tracking IDs for a specific user
  Stream<List<TrackingModel>> getUserTrackingIds(String userId) {
    return _firestore
        .collection(_trackingCollection)
        .where('userId', isEqualTo: userId)
        .orderBy('registeredAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => TrackingModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Get active orders (not retrieved yet)
  Stream<List<TrackingModel>> getActiveOrders(String userId) {
    return _firestore
        .collection(_trackingCollection)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'in_transit', 'delivered'])
        .orderBy('registeredAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => TrackingModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Verify tracking ID (used by courier/drop box system)
  Future<Map<String, dynamic>?> verifyTrackingId(String trackingId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection(_trackingCollection)
          .doc(trackingId)
          .get();

      if (doc.exists) {
        return doc.data() as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      throw 'Failed to verify tracking ID: $e';
    }
  }

  /// Update tracking status
  Future<void> updateTrackingStatus({
    required String trackingId,
    required String status,
  }) async {
    try {
      Map<String, dynamic> updateData = {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'delivered') {
        updateData['deliveredAt'] = FieldValue.serverTimestamp();
      } else if (status == 'retrieved') {
        updateData['retrievedAt'] = FieldValue.serverTimestamp();
      }

      await _firestore
          .collection(_trackingCollection)
          .doc(trackingId)
          .update(updateData);
    } catch (e) {
      throw 'Failed to update tracking status: $e';
    }
  }

  /// Log delivery event
  Future<void> logDeliveryEvent({
    required String trackingId,
    required String userId,
    required String eventType, // scanned, door_opened, parcel_inserted, door_closed
    String? details,
  }) async {
    try {
      await _firestore.collection(_deliveryLogsCollection).add({
        'trackingId': trackingId,
        'userId': userId,
        'eventType': eventType,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'Failed to log delivery event: $e';
    }
  }

  /// Get delivery logs for a tracking ID
  Stream<List<Map<String, dynamic>>> getDeliveryLogs(String trackingId) {
    return _firestore
        .collection(_deliveryLogsCollection)
        .where('trackingId', isEqualTo: trackingId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// Get user data
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection(_usersCollection).doc(userId).get();

      if (doc.exists) {
        return doc.data() as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      throw 'Failed to get user data: $e';
    }
  }

  /// Update user profile
  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? address,
  }) async {
    try {
      Map<String, dynamic> updateData = {
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (fullName != null) updateData['fullName'] = fullName;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;
      if (address != null) updateData['address'] = address;

      await _firestore.collection(_usersCollection).doc(userId).update(updateData);
    } catch (e) {
      throw 'Failed to update user profile: $e';
    }
  }

  /// Log a scan attempt (QR code or barcode scan)
  /// This should be called when the dropbox scans a code
  Future<void> logScanAttempt({
    required String scannedCode,
    required bool accessGranted,
    String? trackingId,
    String? userId,
    String? reason,
  }) async {
    try {
      await _firestore.collection(_scanLogsCollection).add({
        'scannedCode': scannedCode,
        'accessGranted': accessGranted,
        'timestamp': FieldValue.serverTimestamp(),
        'trackingId': trackingId,
        'userId': userId,
        'reason': reason,
      });

      // Create notification for the user if userId is provided
      if (userId != null) {
        try {
          await createScanAttemptNotification(
            userId: userId,
            scannedCode: scannedCode,
            accessGranted: accessGranted,
            trackingId: trackingId,
            reason: reason,
          );
        } catch (e) {
          // Don't fail the scan log if notification creation fails
          debugPrint('Failed to create notification: $e');
        }
      }
    } catch (e) {
      throw 'Failed to log scan attempt: $e';
    }
  }

  /// Get all scan logs (for the logs page)
  /// Returns logs ordered by timestamp (most recent first)
  Stream<List<ScanLogModel>> getScanLogs() {
    return _firestore
        .collection(_scanLogsCollection)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ScanLogModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Get scan logs for a specific user
  Stream<List<ScanLogModel>> getUserScanLogs(String userId) {
    return _firestore
        .collection(_scanLogsCollection)
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ScanLogModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Create a notification for a user
  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? trackingId,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection(_notificationsCollection).add({
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'trackingId': trackingId,
        'data': data,
      });
    } catch (e) {
      throw 'Failed to create notification: $e';
    }
  }

  /// Get notifications for a specific user
  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    return _firestore
        .collection(_notificationsCollection)
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Get unread notifications count for a user
  Stream<int> getUnreadNotificationsCount(String userId) {
    return _firestore
        .collection(_notificationsCollection)
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Mark a notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore
          .collection(_notificationsCollection)
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
      throw 'Failed to mark notification as read: $e';
    }
  }

  /// Mark all notifications as read for a user
  Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection(_notificationsCollection)
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
    } catch (e) {
      throw 'Failed to mark all notifications as read: $e';
    }
  }

  /// Create notification when scan attempt happens
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

  /// Create notification when parcel is delivered
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
      data: {
        'shopName': shopName,
      },
    );
  }

  /// Create notification when tracking status changes
  Future<void> createStatusUpdateNotification({
    required String userId,
    required String trackingId,
    required String status,
    required String shopName,
  }) async {
    String title = 'Status Updated';
    String message = 'Your order from $shopName is now ${_getStatusText(status)}.';

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

  /// ADMIN: Get all users
  Stream<List<UserModel>> getAllUsers() {
    return _firestore
        .collection(_usersCollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        // Ensure uid is present even if missing in stored data
        data['uid'] = data['uid'] ?? doc.id;
        return UserModel.fromMap(data);
      }).toList();
    });
  }

  /// ADMIN: Update a user's role
  Future<void> updateUserRole({
    required String userId,
    required String role,
  }) async {
    try {
      await _firestore.collection(_usersCollection).doc(userId).update({
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'Failed to update user role: $e';
    }
  }

  /// ADMIN/ROUTING: Get a user's role quickly
  Future<String?> getUserRole(String userId) async {
    try {
      final doc = await _firestore.collection(_usersCollection).doc(userId).get();
      if (doc.exists) {
        return (doc.data() as Map<String, dynamic>?)?['role'] as String?;
      }
      return null;
    } catch (e) {
      throw 'Failed to fetch user role: $e';
    }
  }

  /// ADMIN: Get all tracking IDs
  Stream<List<TrackingModel>> getAllTrackingIds() {
    return _firestore
        .collection(_trackingCollection)
        .orderBy('registeredAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => TrackingModel.fromFirestore(doc))
          .toList();
    });
  }

  /// ADMIN: Get all delivery logs
  Stream<List<Map<String, dynamic>>> getAllDeliveryLogs() {
    return _firestore
        .collection(_deliveryLogsCollection)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// Control drop box door (open/close)
  /// This sends a command to the IoT device via Firestore
  Future<void> controlDropBoxDoor({
    required String userId,
    required bool open,
  }) async {
    try {
      // Create or update the device control document
      await _firestore.collection(_deviceControlCollection).doc('door_control').set({
        'command': open ? 'open' : 'close',
        'userId': userId,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending', // pending, processing, completed
      }, SetOptions(merge: true));

      // Log the manual control event
      await logDeliveryEvent(
        trackingId: 'manual_control',
        userId: userId,
        eventType: open ? 'door_opened' : 'door_closed',
        details: 'Manual control by user',
      );
    } catch (e) {
      throw 'Failed to control drop box door: $e';
    }
  }

  /// Get current drop box door state
  Stream<Map<String, dynamic>?> getDropBoxDoorState() {
    return _firestore
        .collection(_deviceControlCollection)
        .doc('door_control')
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        return snapshot.data();
      }
      return null;
    });
  }
}
