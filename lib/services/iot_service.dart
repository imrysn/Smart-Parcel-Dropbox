import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// IoT Service for Smart Drop Box Communication
/// Handles real-time communication with ESP32 hardware
class IoTService {
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  // Default dropbox ID (can be made dynamic for multiple dropboxes)
  static const String defaultDropboxId = 'dropbox_001';
  
  /// Send unlock command to dropbox
  Future<String> sendUnlockCommand({
    required String dropboxId,
    required String trackingId,
    String? userId,
  }) async {
    try {
      final cmdRef = _database.ref('unlock_commands').push();
      await cmdRef.set({
        'dropboxId': dropboxId,
        'trackingId': trackingId,
        'userId': userId,
        'timestamp': ServerValue.timestamp,
        'executed': false,
        'acknowledged': false,
      });
      
      debugPrint('Unlock command sent: ${cmdRef.key}');
      return cmdRef.key!;
    } catch (e) {
      debugPrint('Error sending unlock command: $e');
      throw 'Failed to send unlock command: $e';
    }
  }
  
  /// Check if unlock command was executed
  Future<bool> checkCommandStatus(String commandId) async {
    try {
      final snapshot = await _database.ref('unlock_commands/$commandId').get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return data['executed'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking command status: $e');
      return false;
    }
  }
  
  /// Listen to dropbox status in real-time
  Stream<Map<String, dynamic>> listenToDropboxStatus(String dropboxId) {
    return _database
        .ref('dropboxes/$dropboxId')
        .onValue
        .map((event) {
      if (event.snapshot.value != null) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return <String, dynamic>{
        'status': 'offline',
        'doorLocked': true,
        'lastUpdate': null,
      };
    });
  }
  
  /// Listen to sensor data in real-time
  Stream<Map<String, dynamic>> listenToSensorData(String dropboxId) {
    return _database
        .ref('sensor_data/$dropboxId')
        .onValue
        .map((event) {
      if (event.snapshot.value != null) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return <String, dynamic>{
        'parcelDetected': false,
        'doorOpen': false,
        'weight': 0,
        'timestamp': null,
      };
    });
  }
  
  /// Get all available dropboxes
  Future<List<Map<String, dynamic>>> getDropboxes() async {
    try {
      final snapshot = await _database.ref('dropboxes').get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return data.entries.map((entry) {
          final dropboxData = Map<String, dynamic>.from(entry.value);
          dropboxData['id'] = entry.key;
          return dropboxData;
        }).toList();
      }
      
      return [];
    } catch (e) {
      debugPrint('Error getting dropboxes: $e');
      return [];
    }
  }
  
  /// Request manual scan from dropbox
  Future<void> requestScan({
    required String dropboxId,
    required String trackingId,
  }) async {
    try {
      final scanRef = _database.ref('scan_requests').push();
      await scanRef.set({
        'trackingId': trackingId,
        'dropboxId': dropboxId,
        'timestamp': ServerValue.timestamp,
        'status': 'pending',
        'requestedViaApp': true,
      });
      
      debugPrint('Scan request sent: ${scanRef.key}');
    } catch (e) {
      debugPrint('Error requesting scan: $e');
      throw 'Failed to request scan: $e';
    }
  }
  
  /// Update dropbox configuration
  Future<void> updateDropboxConfig({
    required String dropboxId,
    Map<String, dynamic>? config,
  }) async {
    try {
      if (config != null) {
        await _database.ref('dropboxes/$dropboxId/config').update(config);
        debugPrint('Dropbox config updated');
      }
    } catch (e) {
      debugPrint('Error updating dropbox config: $e');
      throw 'Failed to update dropbox config: $e';
    }
  }
  
  /// Get dropbox statistics
  Future<Map<String, dynamic>> getDropboxStats(String dropboxId) async {
    try {
      final snapshot = await _database.ref('dropbox_stats/$dropboxId').get();
      
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      
      return {
        'totalDeliveries': 0,
        'totalScans': 0,
        'successfulScans': 0,
        'failedScans': 0,
      };
    } catch (e) {
      debugPrint('Error getting dropbox stats: $e');
      return {};
    }
  }
  
  /// Listen to scan requests (for monitoring)
  Stream<Map<String, dynamic>> listenToScanRequests() {
    return _database
        .ref('scan_requests')
        .orderByChild('timestamp')
        .limitToLast(10)
        .onValue
        .map((event) {
      if (event.snapshot.value != null) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return <String, dynamic>{};
    });
  }
  
  /// Emergency: Force lock all dropboxes
  Future<void> emergencyLockAll() async {
    try {
      final snapshot = await _database.ref('dropboxes').get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        
        for (var dropboxId in data.keys) {
          await _database.ref('dropboxes/$dropboxId').update({
            'emergencyLock': true,
            'emergencyTimestamp': ServerValue.timestamp,
          });
        }
        
        debugPrint('Emergency lock activated for all dropboxes');
      }
    } catch (e) {
      debugPrint('Error activating emergency lock: $e');
      throw 'Failed to activate emergency lock: $e';
    }
  }
  
  /// Clear emergency lock
  Future<void> clearEmergencyLock(String dropboxId) async {
    try {
      await _database.ref('dropboxes/$dropboxId').update({
        'emergencyLock': false,
      });
      
      debugPrint('Emergency lock cleared for $dropboxId');
    } catch (e) {
      debugPrint('Error clearing emergency lock: $e');
      throw 'Failed to clear emergency lock: $e';
    }
  }
  
  /// Test connection to Firebase Realtime Database
  Future<bool> testConnection() async {
    try {
      await _database.ref('test_connection').set({
        'timestamp': ServerValue.timestamp,
        'source': 'mobile_app',
      });
      return true;
    } catch (e) {
      debugPrint('Connection test failed: $e');
      return false;
    }
  }
}
