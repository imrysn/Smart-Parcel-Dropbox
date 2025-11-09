import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for tracking ID data
class TrackingModel {
  final String trackingId;
  final String userId;
  final String shopName;
  final String status; // pending, in_transit, delivered, retrieved
  final DateTime? registeredAt;
  final String? expectedDeliveryDate;
  final DateTime? deliveredAt;
  final DateTime? retrievedAt;

  TrackingModel({
    required this.trackingId,
    required this.userId,
    required this.shopName,
    required this.status,
    this.registeredAt,
    this.expectedDeliveryDate,
    this.deliveredAt,
    this.retrievedAt,
  });

  /// Create TrackingModel from Firestore document
  factory TrackingModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return TrackingModel(
      trackingId: data['trackingId'] ?? '',
      userId: data['userId'] ?? '',
      shopName: data['shopName'] ?? '',
      status: data['status'] ?? 'pending',
      registeredAt: (data['registeredAt'] as Timestamp?)?.toDate(),
      expectedDeliveryDate: data['expectedDeliveryDate'],
      deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
      retrievedAt: (data['retrievedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'trackingId': trackingId,
      'userId': userId,
      'shopName': shopName,
      'status': status,
      'registeredAt': registeredAt != null ? Timestamp.fromDate(registeredAt!) : null,
      'expectedDeliveryDate': expectedDeliveryDate,
      'deliveredAt': deliveredAt != null ? Timestamp.fromDate(deliveredAt!) : null,
      'retrievedAt': retrievedAt != null ? Timestamp.fromDate(retrievedAt!) : null,
    };
  }

  /// Get status display text
  String getStatusText() {
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
        return 'Unknown';
    }
  }

  /// Get status color
  String getStatusColor() {
    switch (status) {
      case 'pending':
        return 'orange';
      case 'in_transit':
        return 'blue';
      case 'delivered':
        return 'green';
      case 'retrieved':
        return 'grey';
      default:
        return 'grey';
    }
  }
}
