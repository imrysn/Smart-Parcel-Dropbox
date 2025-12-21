import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Performance Monitoring Service
/// Tracks app performance and reports to Firebase
class PerformanceService {
  final FirebasePerformance _performance = FirebasePerformance.instance;
  
  /// Track operation with automatic timing
  Future<T> trace<T>(String name, Future<T> Function() operation) async {
    final trace = _performance.newTrace(name);
    await trace.start();
    
    try {
      final result = await operation();
      trace.setMetric('success', 1);
      return result;
    } catch (e) {
      trace.setMetric('error', 1);
      debugPrint('Performance trace error in $name: $e');
      rethrow;
    } finally {
      await trace.stop();
    }
  }
  
  /// Track HTTP request
  Future<T> traceHttpRequest<T>(
    String url,
    String method,
    Future<T> Function() operation,
  ) async {
    final metric = _performance.newHttpMetric(url, HttpMethod.values.firstWhere(
      (m) => m.toString().split('.').last.toUpperCase() == method.toUpperCase(),
      orElse: () => HttpMethod.Get,
    ));
    
    await metric.start();
    
    try {
      final result = await operation();
      metric.httpResponseCode = 200;
      return result;
    } catch (e) {
      metric.httpResponseCode = 500;
      debugPrint('HTTP metric error for $url: $e');
      rethrow;
    } finally {
      await metric.stop();
    }
  }
  
  /// Create custom trace
  Trace createTrace(String name) {
    return _performance.newTrace(name);
  }
  
  /// Track specific metrics
  Future<void> trackMetric(String traceName, String metricName, int value) async {
    try {
      final trace = _performance.newTrace(traceName);
      await trace.start();
      trace.setMetric(metricName, value);
      await trace.stop();
    } catch (e) {
      debugPrint('Error tracking metric: $e');
    }
  }
  
  /// Enable/disable performance monitoring
  Future<void> setPerformanceCollectionEnabled(bool enabled) async {
    try {
      await _performance.setPerformanceCollectionEnabled(enabled);
      debugPrint('Performance collection ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('Error setting performance collection: $e');
    }
  }
}
