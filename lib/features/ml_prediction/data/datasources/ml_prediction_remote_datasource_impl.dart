import '../../../../core/network/api_client.dart';
import '../../../../core/error/exceptions.dart';
import '../models/delivery_prediction_model.dart';
import 'ml_prediction_remote_datasource.dart';

/// Implementation of MLPredictionRemoteDataSource
class MLPredictionRemoteDataSourceImpl
    implements MLPredictionRemoteDataSource {
  final ApiClient apiClient;

  MLPredictionRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<DeliveryPredictionModel> predictDeliveryTime({
    required String trackingId,
    required double shopLatitude,
    required double shopLongitude,
    String? shopName,
  }) async {
    try {
      final now = DateTime.now();
      
      final response = await apiClient.post<Map<String, dynamic>>(
        '/api/ml/predict-delivery-time',
        data: {
          'tracking_id': trackingId,
          'shop_lat': shopLatitude,
          'shop_long': shopLongitude,
          'shop_name': shopName,
          'hour': now.hour,
          'day_of_week': now.weekday,
          'timestamp': now.toIso8601String(),
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return DeliveryPredictionModel.fromJson(response);
    } catch (e) {
      if (e.toString().contains('404')) {
        throw NotFoundException('Prediction service not available');
      }
      throw ServerException('Failed to predict delivery time: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getModelMetrics() async {
    try {
      final response = await apiClient.get<Map<String, dynamic>>(
        '/api/ml/model-metrics',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return response;
    } catch (e) {
      throw ServerException('Failed to get model metrics: $e');
    }
  }

  @override
  Future<void> retrainModel() async {
    try {
      await apiClient.post('/api/ml/retrain-model');
    } catch (e) {
      throw ServerException('Failed to retrain model: $e');
    }
  }
}
