import '../../domain/entities/delivery_prediction.dart';

/// Delivery prediction model - Data layer
class DeliveryPredictionModel extends DeliveryPrediction {
  const DeliveryPredictionModel({
    required super.trackingId,
    required super.predictedMinutes,
    required super.confidenceLowerMinutes,
    required super.confidenceUpperMinutes,
    required super.accuracy,
    required super.predictedAt,
  });

  factory DeliveryPredictionModel.fromJson(Map<String, dynamic> json) {
    return DeliveryPredictionModel(
      trackingId: json['tracking_id'] as String? ?? json['trackingId'] as String,
      predictedMinutes: json['predicted_minutes'] as int? ?? 
          json['predictedMinutes'] as int,
      confidenceLowerMinutes: json['confidence_lower'] as int? ?? 
          json['confidenceLower'] as int? ?? 0,
      confidenceUpperMinutes: json['confidence_upper'] as int? ?? 
          json['confidenceUpper'] as int? ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      predictedAt: json['predicted_at'] != null
          ? DateTime.parse(json['predicted_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tracking_id': trackingId,
      'predicted_minutes': predictedMinutes,
      'confidence_lower': confidenceLowerMinutes,
      'confidence_upper': confidenceUpperMinutes,
      'accuracy': accuracy,
      'predicted_at': predictedAt.toIso8601String(),
    };
  }

  factory DeliveryPredictionModel.fromEntity(DeliveryPrediction prediction) {
    return DeliveryPredictionModel(
      trackingId: prediction.trackingId,
      predictedMinutes: prediction.predictedMinutes,
      confidenceLowerMinutes: prediction.confidenceLowerMinutes,
      confidenceUpperMinutes: prediction.confidenceUpperMinutes,
      accuracy: prediction.accuracy,
      predictedAt: prediction.predictedAt,
    );
  }

  DeliveryPrediction toEntity() {
    return DeliveryPrediction(
      trackingId: trackingId,
      predictedMinutes: predictedMinutes,
      confidenceLowerMinutes: confidenceLowerMinutes,
      confidenceUpperMinutes: confidenceUpperMinutes,
      accuracy: accuracy,
      predictedAt: predictedAt,
    );
  }
}
