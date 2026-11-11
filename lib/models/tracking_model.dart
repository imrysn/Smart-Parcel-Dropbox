// No longer using cloud_firestore

/// Model for tracking ID data
class TrackingModel {
  final String trackingId;
  final String userId;
  final String shopName;
  final String status; // pending, in_transit, delivered, retrieved, awaiting_pickup, done
  final String mode;   // drop_off, pickup
  final DateTime? registeredAt;
  final String? expectedDeliveryDate;
  final DateTime? deliveredAt;
  final DateTime? retrievedAt;
  final DateTime? doneAt;

  // Business fulfillment fields
  final String direction; // INBOUND_SUPPLIER, OUTBOUND_CUSTOMER
  final String? customerName;
  final String? customerPhone;
  final String? courierName;
  final String? courierOtp;

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
    this.doneAt,
    this.direction = 'INBOUND_SUPPLIER',
    this.customerName,
    this.customerPhone,
    this.courierName,
    this.courierOtp,
  });

  static DateTime? _safeParseDate(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    return DateTime.tryParse(val.toString());
  }

  /// Create TrackingModel from Map (JSON)
  factory TrackingModel.fromMap(Map<String, dynamic> data) {
    return TrackingModel(
      trackingId: data['trackingId'] ?? '',
      userId: data['userId'] ?? '',
      shopName: data['shopName'] ?? '',
      status: data['status'] ?? 'pending',
      mode: data['mode'] ?? 'drop_off',
      registeredAt: _safeParseDate(data['createdAt']) ?? _safeParseDate(data['registeredAt']),
      expectedDeliveryDate: data['expectedDeliveryDate'],
      deliveredAt: _safeParseDate(data['deliveredAt']),
      retrievedAt: _safeParseDate(data['retrievedAt']),
      doneAt:      _safeParseDate(data['doneAt']),
      direction:   data['direction']   ?? 'INBOUND_SUPPLIER',
      customerName: data['customerName'],
      customerPhone: data['customerPhone'],
      courierName: data['courierName'],
      courierOtp: data['courierOtp'],
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
      'doneAt':      doneAt?.toIso8601String(),
      'direction':   direction,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'courierName': courierName,
      'courierOtp': courierOtp,
    };
  }

  bool get isOutbound => direction == 'OUTBOUND_CUSTOMER';

  /// Get status display text
  String getStatusText() {
    if (mode == 'pickup' || mode == 'pick_up') {
      switch (status) {
        case 'pending':
          return 'PENDING DEPOSIT';
        case 'awaiting_pickup':
          return 'AWAITING PICKUP';
        case 'ready_for_pickup':
          return 'READY FOR PICKUP';
        case 'retrieved':
          return 'PICKED UP';
        case 'done':
          return 'COLLECTED BY RIDER';
        default:
          return status.toUpperCase();
      }
    }
    switch (status) {
      case 'pending':
        return 'PENDING';
      case 'in_transit':
        return 'IN TRANSIT';
      case 'delivered':
        return 'DELIVERED';
      case 'awaiting_pickup':
        return 'AWAITING PICKUP';
      case 'retrieved':
        return 'RETRIEVED';
      case 'done':
        return 'DELIVERED'; // parcel successfully deposited into the box
      default:
        return status.toUpperCase();
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
      case 'awaiting_pickup':
        return 'indigo';
      case 'ready_for_pickup':
        return 'deepPurple';
      case 'retrieved':
        return 'grey';
      case 'done':
        return 'teal';
      default:
        return 'grey';
    }
  }
}
