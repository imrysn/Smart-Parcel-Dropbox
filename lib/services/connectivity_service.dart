import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Connectivity Service for monitoring network status
/// Provides real-time connection state and offline handling
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  
  /// Stream of connectivity changes
  Stream<bool> get isConnected => _connectivity.onConnectivityChanged
      .map((result) => _isConnected(result));
  
  /// Check current connection status
  Future<bool> hasConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _isConnected(result);
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      return false;
    }
  }
  
  /// Get detailed connection info
  Future<Map<String, dynamic>> getConnectionInfo() async {
    try {
      final result = await _connectivity.checkConnectivity();
      
      return {
        'isConnected': _isConnected(result),
        'type': _getConnectionType(result),
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('Error getting connection info: $e');
      return {
        'isConnected': false,
        'type': 'none',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }
  
  /// Check if connected
  bool _isConnected(ConnectivityResult result) {
    return result != ConnectivityResult.none;
  }
  
  /// Get connection type as string
  String _getConnectionType(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
        return 'wifi';
      case ConnectivityResult.mobile:
        return 'mobile';
      case ConnectivityResult.ethernet:
        return 'ethernet';
      case ConnectivityResult.bluetooth:
        return 'bluetooth';
      case ConnectivityResult.vpn:
        return 'vpn';
      case ConnectivityResult.none:
        return 'none';
      default:
        return 'other';
    }
  }
  
  /// Wait for connection (with timeout)
  Future<bool> waitForConnection({Duration timeout = const Duration(seconds: 30)}) async {
    final connected = await hasConnection();
    if (connected) return true;
    
    debugPrint('Waiting for connection (timeout: ${timeout.inSeconds}s)...');
    
    try {
      await isConnected
          .firstWhere((connected) => connected)
          .timeout(timeout);
      return true;
    } catch (e) {
      debugPrint('Connection timeout: $e');
      return false;
    }
  }
  
  /// Start monitoring connectivity
  void startMonitoring() {
    debugPrint('Connectivity monitoring started');
    isConnected.listen((connected) {
      debugPrint('Connectivity changed: ${connected ? 'Connected' : 'Disconnected'}');
    });
  }
}
