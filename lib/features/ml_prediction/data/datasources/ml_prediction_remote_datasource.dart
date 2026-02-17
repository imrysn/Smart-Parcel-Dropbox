import '../models/delivery_prediction_model.dart';

/// Remote data source for ML predictions
abstract class MLPredictionRemoteDataSource {
  /// Predict delivery time for a tracking
  Future<DeliveryPredictionModel> predictDeliveryTime({
    required String trackingId,
    required double shopLatitude,
    required double shopLongitude,
    String? shopName,
  });

  /// Get model accuracy metrics
  Future<Map<String, dynamic>> getModelMetrics();

  /// Retrain model with new data (admin only)
  Future<void> retrainModel();
}
