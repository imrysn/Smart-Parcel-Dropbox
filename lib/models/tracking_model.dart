// No longer using cloud_firestore

/// Model for tracking ID data
class TrackingModel {
  final String trackingId;
  final String userId;
  final String shopName;
  final String status; // pending, in_transit, delivered, retrieved
  final String mode;   // drop_off, pickup
  final DateTime? registeredAt;
  final String? expectedDeliveryDate;
  final DateTime? deliveredAt;
  final DateTime? retrievedAt;

  TrackingModel({
    required this.trackingId,
    required this.userId,
    required this.shopName,
    required this.status,
    this.mode = 'drop_off',
    this.registeredAt,
    this.expectedDeliveryDate,
    this.deliveredAt,
    this.retrievedAt,
  });

  /// Create TrackingModel from Map (JSON)
  factory TrackingModel.fromMap(Map<String, dynamic> data) {
    return TrackingModel(
      trackingId: data['trackingId'] ?? '',
      userId: data['userId'] ?? '',
      shopName: data['shopName'] ?? '',
      status: data['status'] ?? 'pending',
      mode: data['mode'] ?? 'drop_off',
      registeredAt: data['registeredAt'] != null ? DateTime.parse(data['registeredAt']) : (data['createdAt'] != null ? DateTime.parse(data['createdAt']) : null),
      expectedDeliveryDate: data['expectedDeliveryDate'],
      deliveredAt: data['deliveredAt'] != null ? DateTime.parse(data['deliveredAt']) : null,
      retrievedAt: data['retrievedAt'] != null ? DateTime.parse(data['retrievedAt']) : null,
    );
  }


  /// Convert to Map for API
  Map<String, dynamic> toMap() {
    return {
      'trackingId': trackingId,
      'userId': userId,
      'shopName': shopName,
      'status': status,
      'mode': mode,
      'registeredAt': registeredAt?.toIso8601String(),
      'expectedDeliveryDate': expectedDeliveryDate,
      'deliveredAt': deliveredAt?.toIso8601String(),
      'retrievedAt': retrievedAt?.toIso8601String(),
    };
  }

  /// Get status display text
  String getStatusText() {
    if (mode == 'pickup') {
      switch (status) {
        case 'pending':
          return 'Pending Deposit';
        case 'ready_for_pickup':
          return 'Ready for Pickup';
        case 'retrieved':
          return 'Picked Up';
        default:
          return 'Unknown';
      }
    }
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
      case 'ready_for_pickup':
        return 'deepPurple';
      case 'retrieved':
        return 'grey';
      default:
        return 'grey';
    }
  }
}
