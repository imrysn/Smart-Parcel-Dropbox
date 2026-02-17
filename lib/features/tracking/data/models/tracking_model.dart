import '../../domain/entities/tracking.dart';

/// Tracking model - Data layer
/// 
/// Handles JSON serialization/deserialization.
/// Extends the domain entity to add data layer concerns.
class TrackingModel extends Tracking {
  const TrackingModel({
    required super.trackingId,
    required super.userId,
    required super.shopName,
    required super.status,
    super.expectedDeliveryDate,
    super.deliveredAt,
    super.retrievedAt,
    required super.createdAt,
    required super.updatedAt,
  });

  /// Create from JSON
  factory TrackingModel.fromJson(Map<String, dynamic> json) {
    return TrackingModel(
      trackingId: json['trackingId'] as String,
      userId: json['userId'] as String,
      shopName: json['shopName'] as String? ?? 'Unknown Shop',
      status: TrackingStatus.fromString(json['status'] as String? ?? 'pending'),
      expectedDeliveryDate: json['expectedDeliveryDate'] as String?,
      deliveredAt: json['deliveredAt'] != null
          ? DateTime.parse(json['deliveredAt'] as String)
          : null,
      retrievedAt: json['retrievedAt'] != null
          ? DateTime.parse(json['retrievedAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'trackingId': trackingId,
      'userId': userId,
      'shopName': shopName,
      'status': status.value,
      'expectedDeliveryDate': expectedDeliveryDate,
      'deliveredAt': deliveredAt?.toIso8601String(),
      'retrievedAt': retrievedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from domain entity
  factory TrackingModel.fromEntity(Tracking tracking) {
    return TrackingModel(
      trackingId: tracking.trackingId,
      userId: tracking.userId,
      shopName: tracking.shopName,
      status: tracking.status,
      expectedDeliveryDate: tracking.expectedDeliveryDate,
      deliveredAt: tracking.deliveredAt,
      retrievedAt: tracking.retrievedAt,
      createdAt: tracking.createdAt,
      updatedAt: tracking.updatedAt,
    );
  }

  /// Convert to domain entity
  Tracking toEntity() {
    return Tracking(
      trackingId: trackingId,
      userId: userId,
      shopName: shopName,
      status: status,
      expectedDeliveryDate: expectedDeliveryDate,
      deliveredAt: deliveredAt,
      retrievedAt: retrievedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
