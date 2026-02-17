import 'package:equatable/equatable.dart';

/// Tracking status enum
enum TrackingStatus {
  pending,
  inTransit,
  delivered,
  retrieved;

  String get displayName {
    switch (this) {
      case TrackingStatus.pending:
        return 'Pending';
      case TrackingStatus.inTransit:
        return 'In Transit';
      case TrackingStatus.delivered:
        return 'Delivered';
      case TrackingStatus.retrieved:
        return 'Retrieved';
    }
  }

  String get value {
    switch (this) {
      case TrackingStatus.pending:
        return 'pending';
      case TrackingStatus.inTransit:
        return 'in_transit';
      case TrackingStatus.delivered:
        return 'delivered';
      case TrackingStatus.retrieved:
        return 'retrieved';
    }
  }

  static TrackingStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return TrackingStatus.pending;
      case 'in_transit':
      case 'intransit':
        return TrackingStatus.inTransit;
      case 'delivered':
        return TrackingStatus.delivered;
      case 'retrieved':
        return TrackingStatus.retrieved;
      default:
        return TrackingStatus.pending;
    }
  }
}

/// Tracking entity - Domain layer
/// 
/// Represents a parcel tracking in the business logic layer.
/// This is immutable and contains only business logic, no serialization.
class Tracking extends Equatable {
  final String trackingId;
  final String userId;
  final String shopName;
  final TrackingStatus status;
  final String? expectedDeliveryDate;
  final DateTime? deliveredAt;
  final DateTime? retrievedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Tracking({
    required this.trackingId,
    required this.userId,
    required this.shopName,
    required this.status,
    this.expectedDeliveryDate,
    this.deliveredAt,
    this.retrievedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        trackingId,
        userId,
        shopName,
        status,
        expectedDeliveryDate,
        deliveredAt,
        retrievedAt,
        createdAt,
        updatedAt,
      ];

  /// Check if tracking is active (not retrieved)
  bool get isActive => status != TrackingStatus.retrieved;

  /// Check if tracking is delivered
  bool get isDelivered => status == TrackingStatus.delivered;

  /// Check if tracking can be retrieved
  bool get canRetrieve => status == TrackingStatus.delivered;

  /// Get days since delivery
  int? get daysSinceDelivery {
    if (deliveredAt == null) return null;
    return DateTime.now().difference(deliveredAt!).inDays;
  }

  Tracking copyWith({
    String? trackingId,
    String? userId,
    String? shopName,
    TrackingStatus? status,
    String? expectedDeliveryDate,
    DateTime? deliveredAt,
    DateTime? retrievedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Tracking(
      trackingId: trackingId ?? this.trackingId,
      userId: userId ?? this.userId,
      shopName: shopName ?? this.shopName,
      status: status ?? this.status,
      expectedDeliveryDate: expectedDeliveryDate ?? this.expectedDeliveryDate,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      retrievedAt: retrievedAt ?? this.retrievedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
