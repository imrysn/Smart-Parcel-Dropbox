import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tracking_model.dart';

/// Database Service for Smart Parcel Drop Box System
/// Handles all Firestore operations for tracking IDs and delivery logs
class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collections
  final String _trackingCollection = 'tracking_ids';
  final String _deliveryLogsCollection = 'delivery_logs';
  final String _usersCollection = 'users';

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
}
