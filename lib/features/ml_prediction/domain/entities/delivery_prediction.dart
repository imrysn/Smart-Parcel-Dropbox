import 'package:equatable/equatable.dart';

/// Delivery prediction entity - Domain layer
class DeliveryPrediction extends Equatable {
  final String trackingId;
  final int predictedMinutes;
  final int confidenceLowerMinutes;
  final int confidenceUpperMinutes;
  final double accuracy;
  final DateTime predictedAt;

  const DeliveryPrediction({
    required this.trackingId,
    required this.predictedMinutes,
    required this.confidenceLowerMinutes,
    required this.confidenceUpperMinutes,
    required this.accuracy,
    required this.predictedAt,
  });

  @override
  List<Object?> get props => [
        trackingId,
        predictedMinutes,
        confidenceLowerMinutes,
        confidenceUpperMinutes,
        accuracy,
        predictedAt,
      ];

  /// Get estimated delivery time as formatted string
  String get estimatedTime {
    final hours = predictedMinutes ~/ 60;
    final minutes = predictedMinutes % 60;
    
    if (hours > 0) {
      return minutes > 0 ? '$hours hr $minutes min' : '$hours hr';
    }
    return '$minutes min';
  }

  /// Get confidence range as formatted string
  String get confidenceRange {
    final lowerHours = confidenceLowerMinutes ~/ 60;
    final upperHours = confidenceUpperMinutes ~/ 60;
    return '$lowerHours-$upperHours hours';
  }

  /// Get estimated delivery date/time
  DateTime get estimatedDeliveryTime {
    return predictedAt.add(Duration(minutes: predictedMinutes));
  }

  /// Get confidence level as percentage
  String get confidenceLevel {
    return '${(accuracy * 100).toStringAsFixed(0)}%';
  }

  DeliveryPrediction copyWith({
    String? trackingId,
    int? predictedMinutes,
    int? confidenceLowerMinutes,
    int? confidenceUpperMinutes,
    double? accuracy,
    DateTime? predictedAt,
  }) {
    return DeliveryPrediction(
      trackingId: trackingId ?? this.trackingId,
      predictedMinutes: predictedMinutes ?? this.predictedMinutes,
      confidenceLowerMinutes:
          confidenceLowerMinutes ?? this.confidenceLowerMinutes,
      confidenceUpperMinutes:
          confidenceUpperMinutes ?? this.confidenceUpperMinutes,
      accuracy: accuracy ?? this.accuracy,
      predictedAt: predictedAt ?? this.predictedAt,
    );
  }
}
