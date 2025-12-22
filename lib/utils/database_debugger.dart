import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class DatabaseDebugger {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> dumpFullDatabase() async {
    debugPrint('--- STARTING DATABASE DUMP ---');
    
    final collections = [
      'users',
      'tracking_ids',
      'delivery_logs',
      'scan_logs',
      'notifications',
      'device_control'
    ];

    for (var collectionName in collections) {
      debugPrint('\n--- Collection: $collectionName ---');
      try {
        QuerySnapshot snapshot = await _firestore.collection(collectionName).get();
        if (snapshot.docs.isEmpty) {
          debugPrint('No documents found in $collectionName.');
          continue;
        }

        for (var doc in snapshot.docs) {
          debugPrint('ID: ${doc.id} => ${doc.data()}');
        }
      } catch (e) {
        debugPrint('Error fetching collection $collectionName: $e');
      }
    }

    debugPrint('\n--- END OF DATABASE DUMP ---');
  }
}
