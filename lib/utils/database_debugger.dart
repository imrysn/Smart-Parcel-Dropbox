import 'package:flutter/foundation.dart';

class DatabaseDebugger {
  static Future<void> dumpFullDatabase() async {
    debugPrint('--- DATABASE DUMP (STUB) ---');
    debugPrint('Database dump is not available for MongoDB-based version via this tool.');
    debugPrint('Please check the MongoDB collection directly using Compass or the Node.js API.');
  }
}
