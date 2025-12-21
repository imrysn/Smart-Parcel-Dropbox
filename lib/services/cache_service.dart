import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

/// Cache Service for local data storage and performance optimization
/// Reduces Firestore reads and improves offline support
class CacheService {
  static const String _cacheBoxName = 'app_cache';
  static const Duration _defaultCacheDuration = Duration(hours: 1);
  static const Duration _userCacheDuration = Duration(hours: 6);
  static const Duration _trackingCacheDuration = Duration(minutes: 30);
  
  Box? _cacheBox;
  
  /// Initialize Hive and open cache box
  Future<void> initialize() async {
    try {
      await Hive.initFlutter();
      _cacheBox = await Hive.openBox(_cacheBoxName);
      debugPrint('Cache service initialized');
    } catch (e) {
      debugPrint('Error initializing cache: $e');
    }
  }
  
  /// Get cached data with type conversion
  Future<T?> getCached<T>(
    String key, 
    T Function(dynamic) fromJson, {
    Duration? customDuration,
  }) async {
    if (_cacheBox == null) return null;
    
    try {
      final cached = _cacheBox!.get(key);
      if (cached == null) return null;
      
      final timestamp = cached['timestamp'] as int?;
      if (timestamp == null) return null;
      
      final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final duration = customDuration ?? _defaultCacheDuration;
      
      if (now.difference(cachedTime) > duration) {
        await _cacheBox!.delete(key);
        debugPrint('Cache expired for key: $key');
        return null;
      }
      
      debugPrint('Cache hit for key: $key');
      return fromJson(cached['data']);
    } catch (e) {
      debugPrint('Error parsing cached data for $key: $e');
      return null;
    }
  }
  
  /// Set cached data
  Future<void> setCached(String key, dynamic data) async {
    if (_cacheBox == null) return;
    
    try {
      await _cacheBox!.put(key, {
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      debugPrint('Cached data for key: $key');
    } catch (e) {
      debugPrint('Error caching data for $key: $e');
    }
  }
  
  /// Clear all cache
  Future<void> clearCache() async {
    if (_cacheBox == null) return;
    
    try {
      await _cacheBox!.clear();
      debugPrint('All cache cleared');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
  
  /// Delete specific cached item
  Future<void> deleteCached(String key) async {
    if (_cacheBox == null) return;
    
    try {
      await _cacheBox!.delete(key);
      debugPrint('Cache deleted for key: $key');
    } catch (e) {
      debugPrint('Error deleting cache for $key: $e');
    }
  }
  
  /// Clear expired cache items
  Future<void> clearExpiredCache() async {
    if (_cacheBox == null) return;
    
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final keysToDelete = <String>[];
      
      for (var key in _cacheBox!.keys) {
        final cached = _cacheBox!.get(key);
        if (cached != null && cached['timestamp'] != null) {
          final timestamp = cached['timestamp'] as int;
          final age = now - timestamp;
          
          // Delete if older than 24 hours
          if (age > Duration(hours: 24).inMilliseconds) {
            keysToDelete.add(key as String);
          }
        }
      }
      
      for (var key in keysToDelete) {
        await _cacheBox!.delete(key);
      }
      
      debugPrint('Cleared ${keysToDelete.length} expired cache items');
    } catch (e) {
      debugPrint('Error clearing expired cache: $e');
    }
  }
  
  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    if (_cacheBox == null) return {};
    
    return {
      'totalItems': _cacheBox!.length,
      'keys': _cacheBox!.keys.toList(),
      'isOpen': _cacheBox!.isOpen,
    };
  }
  
  /// Close cache box
  Future<void> close() async {
    try {
      await _cacheBox?.close();
      debugPrint('Cache service closed');
    } catch (e) {
      debugPrint('Error closing cache: $e');
    }
  }
}
