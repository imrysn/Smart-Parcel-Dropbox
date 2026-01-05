import 'package:flutter/foundation.dart';

/// Performance Service for Smart Parcel Drop Box System
/// Stubbed out version (previously used Firebase Performance)
class PerformanceService {
  /// Start tracking a trace
  Future<void> startTrace(String name) async {
    debugPrint('Trace started: $name');
  }

  /// Stop tracking a trace
  Future<void> stopTrace(String name) async {
    debugPrint('Trace stopped: $name');
  }
}
