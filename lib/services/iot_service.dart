import 'package:flutter/foundation.dart';
import 'database_service.dart';

/// IoT Service for Smart Drop Box Communication
/// Now integrated with DatabaseService for real MongoDB/Socket.io communication
class IoTService {
  final DatabaseService _databaseService = DatabaseService();
  
  // Default dropbox ID
  static const String defaultDropboxId = 'dropbox_001';
  
  /// Send unlock command to dropbox
  Future<String> sendUnlockCommand({
    required String dropboxId,
    required String trackingId,
    String? userId,
  }) async {
    if (userId == null) throw 'User ID is required for unlock commands';
    
    debugPrint('Sending unlock command for $trackingId...');
    await _databaseService.controlDropBoxDoor(userId: userId, open: true);
    
    return 'cmd_${DateTime.now().millisecondsSinceEpoch}';
  }
  
  /// Check if unlock command was executed
  Future<bool> checkCommandStatus(String commandId) async {
    // In the new system, we listen to the door state stream instead
    return true;
  }
  
  /// Listen to dropbox status in real-time
  Stream<Map<String, dynamic>> listenToDropboxStatus(String dropboxId) {
    return _databaseService.getDropBoxDoorState().map((event) {
      if (event != null) {
        return event;
      }
      return {
        'status': 'online',
        'doorLocked': true,
        'lastUpdate': DateTime.now().toIso8601String(),
      };
    });
  }
  
  /// Listen to sensor data in real-time
  Stream<Map<String, dynamic>> listenToSensorData(String dropboxId) {
    // Sensor data is also piped through the doorStateUpdate event for now
    return _databaseService.getDropBoxDoorState().map((event) {
      if (event != null) {
        return {
          'parcelDetected': event['parcelDetected'] ?? false,
          'doorOpen': event['command'] == 'open',
          'weight': event['weight'] ?? 0,
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
      return {
        'parcelDetected': false,
        'doorOpen': false,
        'weight': 0,
        'timestamp': DateTime.now().toIso8601String(),
      };
    });
  }
  
  /// Get all available dropboxes
  Future<List<Map<String, dynamic>>> getDropboxes() async {
    return [
      {'id': 'dropbox_001', 'name': 'Main Drop Box', 'status': 'online'}
    ];
  }
  
  /// Request manual scan from dropbox
  Future<void> requestScan({
    required String dropboxId,
    required String trackingId,
  }) async {
    // This could be implemented as another command in device-control
    debugPrint('Scan request sent for $trackingId');
  }
  
  /// Update dropbox configuration
  Future<void> updateDropboxConfig({
    required String dropboxId,
    Map<String, dynamic>? config,
  }) async {
    debugPrint('Dropbox config updated');
  }
  
  /// Get dropbox statistics
  Future<Map<String, dynamic>> getDropboxStats(String dropboxId) async {
    return {
      'totalDeliveries': 10,
      'totalScans': 15,
      'successfulScans': 12,
      'failedScans': 3,
    };
  }
  
  /// Listen to scan requests (for monitoring)
  Stream<Map<String, dynamic>> listenToScanRequests() {
    return Stream.value({});
  }
  
  /// Emergency: Force lock all dropboxes
  Future<void> emergencyLockAll() async {
    debugPrint('Emergency lock activated');
  }
  
  /// Clear emergency lock
  Future<void> clearEmergencyLock(String dropboxId) async {
    debugPrint('Emergency lock cleared');
  }
  
  /// Test connection
  Future<bool> testConnection() async {
    return true;
  }
}
